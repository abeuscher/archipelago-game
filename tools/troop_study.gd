## Headless study: how often a "player" beats the in-game enemy AI, how often
## each side gets soldiers (airport/docks), and whether troops pay off.
## Rules layer only: no scenes, no audio.
##
##   godot --headless --path . -s tools/troop_study.gd -- [--matches N] [--part 1|2|search]
##     [--level L] [--award M]
## --level plays a campaign level (data/levels.json); --award adds money to
## both sides' start, as the win before it does in the game.
extends SceneTree

const GameData = preload("res://rules/game_data.gd")
const SimpleAI = preload("res://ai/simple_ai.gd")
const StrongAI = preload("res://ai/strong_ai.gd")
const MatchRunner = preload("res://ai/match_runner.gd")
const MatchState = preload("res://rules/match_state.gd")
const Levels = preload("res://rules/levels.gd")

var data
var max_rounds := 60
var award := 0


func _initialize() -> void:
	data = GameData.load_default()
	var n := 200
	var part := "all"
	var lvl := 1
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		match args[i]:
			"--matches": n = int(args[i + 1])
			"--part": part = args[i + 1]
			"--level": lvl = int(args[i + 1])
			"--award": award = int(args[i + 1])
	data = Levels.data_for(data, lvl)
	max_rounds = int(data.ai["batch"]["max_rounds"])
	print("Level %d, side 0 award %d" % [lvl, award])

	if part in ["all", "1"]:
		print("\n=== Part 1: player stand-ins (side 0) vs the game's enemy (strong, side 1) ===")
		for p in ["strong:easy", "strong:medium", "strong"]:
			_run(p, "normal", "strong", "normal", n, 1000, false)
	if part in ["all", "2"]:
		print("\n=== Part 2: are troops worth it? strong vs strong, sides alternate ===")
		_run("strong", "no_troops", "strong", "normal", n, 5000, true)
		_run("strong", "eager_troops", "strong", "normal", n, 9000, true)
	if part == "search":
		print("\n=== Varied search shots vs always the best aim, sides alternate ===")
		_run("strong", "normal", "strong", "fixed_search", n, 17000, true)
	quit(0)


## A copy of the data with the AI's troop habits changed.
func _variant(kind: String):
	var d = data.duplicate_data()
	var s: Dictionary = d.ai["strong"]
	match kind:
		"no_troops":
			# Never researches or builds airports/docks; money goes elsewhere.
			s["research_order"] = Array(s["research_order"]).filter(func(x): return x != "airport" and x != "docks")
			s["build_order"] = Array(s["build_order"]).filter(func(x): return x != "airport" and x != "docks")
		"eager_troops":
			# Gets troops early and drops on anything of modest value.
			var r: Array = Array(s["research_order"]).filter(func(x): return x != "airport" and x != "docks")
			r.insert(0, "docks")
			r.insert(0, "airport")
			s["research_order"] = r
			var b: Array = Array(s["build_order"]).filter(func(x): return x != "airport" and x != "docks")
			b.insert(5, "docks")
			b.insert(4, "airport")
			s["build_order"] = b
			s["troops"]["min_value"] = 3.0
		"fixed_search":
			s["search_spread"] = 0.0
	return d


func _make(name: String, side: int, d, seed_in: int):
	var parts := name.split(":")
	if parts[0] == "simple":
		return SimpleAI.new(side, d, seed_in)
	return StrongAI.new(side, d, seed_in, parts[1] if parts.size() > 1 else "")


func _run(a_name: String, a_kind: String, b_name: String, b_kind: String, n: int, seed0: int, swap: bool) -> void:
	var da = data if a_kind == "normal" else _variant(a_kind)
	var db = data if b_kind == "normal" else _variant(b_kind)
	var label_a := "A %s[%s]" % [a_name, a_kind]
	var label_b := "B %s[%s]" % [b_name, b_kind]
	# Per-label totals.
	var T := {label_a: _blank(), label_b: _blank()}
	var timeouts := 0
	var rounds_all: Array = []
	for k in n:
		var seed_in := seed0 + k
		var flip := swap and k % 2 == 1
		var labels: Array = [label_b, label_a] if flip else [label_a, label_b]
		var ais := [
			_make(b_name if flip else a_name, 0, db if flip else da, seed_in),
			_make(a_name if flip else b_name, 1, da if flip else db, seed_in)]
		var r := _play(seed_in, ais)
		var m = r["m"]
		if r["timed_out"]:
			timeouts += 1
		else:
			rounds_all.append(m.round_number)
		var per := _troop_stats(m, r["ports"])
		for s in 2:
			var t: Dictionary = T[labels[s]]
			var ps: Dictionary = per[s]
			t["games"] += 1
			var won: bool = m.winner == s
			if won:
				t["wins"] += 1
			if ps["first_capable"] > 0:
				t["capable"] += 1
				t["capable_rounds"].append(ps["first_capable"])
			if ps["drops"] > 0:
				t["used"] += 1
				t["used_wins"] += int(won)
				t["first_drop_rounds"].append(ps["first_drop"])
			else:
				t["unused_wins"] += int(won)
			for key in ["drops", "landed", "lost", "buildings", "bases", "bases_all", "spent"]:
				t[key] += ps[key]
			if ps["bases"] > 0:
				t["games_troop_base_kill"] += 1
	rounds_all.sort()
	print("\n-- %s  vs  %s  (%d matches%s, timeouts %d, median rounds %s)" % [label_a, label_b, n,
		", sides alternate" if swap else "", timeouts, rounds_all[rounds_all.size() / 2] if not rounds_all.is_empty() else "-"])
	for lab in [label_a, label_b]:
		var t: Dictionary = T[lab]
		var g: int = t["games"]
		print("  %s" % lab)
		print("    wins %d/%d (%.0f%%)" % [t["wins"], g, 100.0 * t["wins"] / g])
		print("    got troops (airport/docks built) in %.0f%% of matches, median round %s" % [100.0 * t["capable"] / g, _med(t["capable_rounds"])])
		print("    actually sent troops in %.0f%% of matches, first drop median round %s" % [100.0 * t["used"] / g, _med(t["first_drop_rounds"])])
		if t["drops"] > 0:
			print("    drops %d: landed and marched %d, lost %d (shot down / sunk / sea / bunker)" % [t["drops"], t["landed"], t["lost"]])
			print("    per drop: %.2f buildings destroyed; bases destroyed by troops %d of %d bases they destroyed in all (%.0f%%)" % [
				float(t["buildings"]) / t["drops"], t["bases"], t["bases_all"], 100.0 * t["bases"] / maxf(t["bases_all"], 1)])
			print("    money spent on troops (ports, transports, boats): %d, i.e. %.0f per enemy building destroyed" % [t["spent"], float(t["spent"]) / maxf(t["buildings"], 1)])
			print("    win rate when it sent troops %.0f%% (%d), when it didn't %.0f%% (%d)" % [
				100.0 * t["used_wins"] / maxf(t["used"], 1), t["used"], 100.0 * t["unused_wins"] / maxf(g - t["used"], 1), g - t["used"]])


func _blank() -> Dictionary:
	return {"games": 0, "wins": 0, "capable": 0, "capable_rounds": [], "used": 0, "used_wins": 0, "unused_wins": 0,
		"first_drop_rounds": [], "drops": 0, "landed": 0, "lost": 0, "buildings": 0, "bases": 0, "bases_all": 0,
		"spent": 0, "games_troop_base_kill": 0}


func _play(seed_in: int, ais: Array) -> Dictionary:
	# Same loop as MatchRunner.play, but keeps the match for its history.
	var m = MatchState.create(data, seed_in, {})
	m.sides[0].money += award
	m.sides[1].money += award   # the enemy gets the same, as in the game
	var port_info := [{"first": 0, "spent": 0}, {"first": 0, "spent": 0}]
	for s in 2:
		var setup: Dictionary = ais[s].choose_setup(m.view_for(s))
		m.setup_side(s, setup["bases"], setup["decoys"])
	while not m.is_over() and m.round_number < max_rounds:
		m.begin_round()
		var planned: Array = []
		for s in 2:
			planned.append(ais[s].choose_build(m.view_for(s)))
		for s in 2:
			for a in planned[s]:
				if m.build_action(s, a) == "":
					_note_build(m, s, a, port_info)
		m.end_build_phase()
		var orders: Array = []
		for s in 2:
			orders.append(ais[s].choose_targets(m.view_for(s)))
		for s in 2:
			m.set_launch_orders(s, orders[s])
		m.resolve_playout()
		if m.phase == MatchState.Phase.COIN_FLIP:
			m.resolve_coin_flip()
	return {"m": m, "timed_out": not m.is_over(), "ports": port_info}


func _note_build(m, s: int, a: Dictionary, port_info: Array) -> void:
	var p: Dictionary = port_info[s]
	match String(a.get("action", "")):
		"build":
			var t := String(a["type"])
			if t == "airport" or t == "docks":
				p["spent"] += int(m.data.building(t)["cost"])
				if p["first"] == 0:
					p["first"] = m.round_number
		"replace_carrier":
			var b = m.sides[s].building_at(int(a["hex"]))
			if b != null:
				p["spent"] += int(m.data.missile("transport" if b.type == "airport" else "boat").get("replace_money", 0))


func _troop_stats(m, ports: Array) -> Array:
	var out := []
	for s in 2:
		out.append({"first_capable": 0, "first_drop": 0, "drops": 0, "landed": 0, "lost": 0,
			"buildings": 0, "bases": 0, "bases_all": 0, "spent": 0})
	var troop_ids := {}       # side*100000+id -> true
	var round_destroyed := {} # "round:side:hex" -> building type
	for ev in m.history:
		if ev["type"] == "destroyed":
			round_destroyed["%d:%d:%d" % [ev["round"], ev["side"], ev["hex"]]] = ev["building"]
	for ev in m.history:
		var t: String = ev["type"]
		var s := int(ev.get("side", -1))
		match t:
			"launch":
				if String(ev.get("missile", "")) == "transport":
					_drop(out[s], ev, m)
			"boat_launch":
				_drop(out[s], ev, m)
			"carrier_lost", "boat_sunk":
				out[s]["lost"] += 1
			"platoon":
				if bool(ev["lost_at_sea"]) or int(ev["stopped_by"]) >= 0:
					out[s]["lost"] += 1
				else:
					out[s]["landed"] += 1
				for h in ev["destroyed"]:
					var key := "%d:%d:%d" % [ev["round"], 1 - s, h]
					if round_destroyed.has(key):
						out[s]["buildings"] += 1
						if round_destroyed[key] == "base":
							out[s]["bases"] += 1
			"destroyed":
				if ev["building"] == "base":
					out[1 - s]["bases_all"] += 1
	for s in 2:
		out[s]["first_capable"] = int(ports[s]["first"])
		out[s]["spent"] += int(ports[s]["spent"])
	return out


func _drop(o: Dictionary, ev: Dictionary, m) -> void:
	o["drops"] += 1
	if o["first_drop"] == 0:
		o["first_drop"] = int(ev["round"])
	var ms: Dictionary = m.data.missile("boat" if ev["type"] == "boat_launch" else "transport")
	o["spent"] += int(ms.get("money", 0))


func _med(a: Array) -> String:
	if a.is_empty():
		return "-"
	var b := a.duplicate()
	b.sort()
	return str(b[b.size() / 2])
