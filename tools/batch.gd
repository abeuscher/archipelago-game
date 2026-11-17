## Headless AI-against-AI batch runner.
##
##   godot --headless --path . -s tools/batch.gd -- [options]
##
## Options:
##   --matches N         number of matches (default from data/ai.json batch)
##   --seed S            first seed; match k uses seed S + k
##   --max-rounds R      stop a match after R rounds and count it as a timeout
##   --set path=value    override a data value for this run only, e.g.
##                       --set rules.anti_air.engagements=1   (repeatable)
##   --csv FILE          also write one row per match
extends SceneTree

const GameData = preload("res://rules/game_data.gd")
const SimpleAI = preload("res://ai/simple_ai.gd")
const MatchRunner = preload("res://ai/match_runner.gd")


func _initialize() -> void:
	var data = GameData.load_default()
	var batch_cfg: Dictionary = data.ai["batch"]
	var matches := int(batch_cfg["default_matches"])
	var first_seed := int(batch_cfg["default_seed"])
	var max_rounds := int(batch_cfg["max_rounds"])
	var csv_path := ""
	var overrides: Array[String] = []

	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		match args[i]:
			"--matches": matches = int(args[i + 1]); i += 1
			"--seed": first_seed = int(args[i + 1]); i += 1
			"--max-rounds": max_rounds = int(args[i + 1]); i += 1
			"--csv": csv_path = args[i + 1]; i += 1
			"--set":
				var kv := args[i + 1].split("=", true, 1)
				data.set_path(kv[0], JSON.parse_string(kv[1]))
				overrides.append(args[i + 1])
				i += 1
			_:
				push_error("Unknown option " + args[i])
				quit(2)
				return
		i += 1

	var t0 := Time.get_ticks_msec()
	var results: Array = []
	for k in matches:
		var seed_in := first_seed + k
		var ais := [SimpleAI.new(0, data, seed_in), SimpleAI.new(1, data, seed_in)]
		results.append(MatchRunner.play(data, seed_in, ais, max_rounds))
	var secs := (Time.get_ticks_msec() - t0) / 1000.0

	_report(results, overrides, matches, first_seed, max_rounds, secs)
	if csv_path != "":
		_write_csv(results, csv_path)
	var any_errors := results.any(func(r): return not r["errors"].is_empty())
	quit(1 if any_errors else 0)


func _report(results: Array, overrides: Array[String], matches: int, first_seed: int, max_rounds: int, secs: float) -> void:
	var finished := results.filter(func(r): return not r["timed_out"])
	var rounds: Array = finished.map(func(r): return r["rounds"])
	rounds.sort()
	var busier: Array = finished.map(func(r): return maxi(r["fired"][0], r["fired"][1]))
	busier.sort()
	var wins := [0, 0]
	var reasons := {}
	var fired_total := 0
	var intercepted_total := 0
	var error_count := 0
	for r in results:
		if r["winner"] >= 0:
			wins[r["winner"]] += 1
		reasons[r["reason"]] = int(reasons.get(r["reason"], 0)) + 1
		fired_total += r["fired"][0] + r["fired"][1]
		intercepted_total += r["intercepted"][0] + r["intercepted"][1]
		error_count += r["errors"].size()

	print("")
	print("Archipelago batch: %d matches, seeds %d..%d, max %d rounds (%.1fs)" % [matches, first_seed, first_seed + matches - 1, max_rounds, secs])
	print("Overrides: %s" % (", ".join(overrides) if not overrides.is_empty() else "none"))
	if rounds.is_empty():
		print("No match finished.")
	else:
		print("Rounds to a result: median %s, range %d to %d, middle 80%% %d to %d" % [
			_median(rounds), rounds[0], rounds[-1], _pct(rounds, 0.10), _pct(rounds, 0.90)])
		print("Missiles fired by the busier side: median %s" % _median(busier))
	print("Timeouts: %d" % (results.size() - finished.size()))
	print("Wins: side 0 %d, side 1 %d" % wins)
	print("End reasons: %s" % str(reasons))
	if fired_total > 0:
		print("Share of missiles shot down: %.1f%%" % (100.0 * intercepted_total / fired_total))
	if error_count > 0:
		print("Rejected AI actions: %d (first: %s)" % [error_count,
			results.filter(func(r): return not r["errors"].is_empty())[0]["errors"][0]])


func _median(sorted: Array) -> String:
	var n := sorted.size()
	if n % 2 == 1:
		return str(sorted[n / 2])
	return str((sorted[n / 2 - 1] + sorted[n / 2]) / 2.0)


func _pct(sorted: Array, p: float) -> int:
	return sorted[clampi(int(p * (sorted.size() - 1)), 0, sorted.size() - 1)]


func _write_csv(results: Array, path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_line("seed,rounds,winner,reason,fired0,fired1,intercepted0,intercepted1,errors")
	for r in results:
		f.store_line("%d,%d,%d,%s,%d,%d,%d,%d,%d" % [r["seed"], r["rounds"], r["winner"], r["reason"],
			r["fired"][0], r["fired"][1], r["intercepted"][0], r["intercepted"][1], r["errors"].size()])
	f.close()
	print("Wrote ", path)
