## Headless strong-against-strong study of campaign levels: match length,
## wins, research pace and nukes fired.
##
##   godot --headless --path . -s tools/level_study.gd -- [--levels 1,2,3] [--matches 150] [--seed 1000]
##
## Prints one line per level, e.g.
##   Level 3: median 31 rounds (10%: 24, 90%: 36), wins [74, 76], errors 0; research items by round 15: median 2; nukes in 34 matches (42 fired)
## and, where there are any, spy trips (how many found something, how many
## buildings they found, how many were shot down) and silos destroyed.
extends SceneTree

const GameData = preload("res://rules/game_data.gd")
const StrongAI = preload("res://ai/strong_ai.gd")
const MatchState = preload("res://rules/match_state.gd")
const Levels = preload("res://rules/levels.gd")


func _initialize() -> void:
	var levels: Array = [1, 2, 3]
	var n := 150
	var first_seed := 1000
	var args := OS.get_cmdline_user_args()
	for i in args.size() - 1:
		match args[i]:
			"--levels": levels = Array(args[i + 1].split(",")).map(func(s): return int(s))
			"--matches": n = int(args[i + 1])
			"--seed": first_seed = int(args[i + 1])
	for lvl in levels:
		_study(int(lvl), n, first_seed)
	quit(0)


func _study(lvl: int, n: int, first_seed: int) -> void:
	var d = Levels.data_for(GameData.load_default(), lvl)
	var rounds: Array = []
	var wins := [0, 0]
	var errors := 0
	var researched_at_15: Array = []
	var nuke_matches := 0
	var nukes := 0
	var first_err := ""
	var spy := {"sent": 0, "found": 0, "found_buildings": 0, "lost": 0, "silos_destroyed": 0}
	for s in n:
		var m = MatchState.create(d, first_seed + s)
		var ais := [StrongAI.new(0, d, first_seed + s), StrongAI.new(1, d, first_seed + 4000 + s)]
		for side in 2:
			var su: Dictionary = ais[side].choose_setup(m.view_for(side))
			m.setup_side(side, su["bases"], su["decoys"])
		var fired := 0
		while not m.is_over() and m.round_number < 200:
			m.begin_round()
			if m.round_number == 15:
				researched_at_15.append(m.sides[0].researched_count())
			var planned := [ais[0].choose_build(m.view_for(0)), ais[1].choose_build(m.view_for(1))]
			for side in 2:
				for a in planned[side]:
					var e: String = m.build_action(side, a)
					if e != "":
						errors += 1
						if first_err == "":
							first_err = " (first: %s: %s)" % [str(a), e]
			m.end_build_phase()
			var ords := [ais[0].choose_targets(m.view_for(0)), ais[1].choose_targets(m.view_for(1))]
			for side in 2:
				if m.set_launch_orders(side, ords[side]) != "":
					errors += 1
			for e in m.resolve_playout():
				if e["type"] == "launch" and e["missile"] == "nuke":
					fired += 1
				elif e["type"] == "launch" and e["missile"] == "spy":
					spy["sent"] += 1
				elif e["type"] == "spy" and not e["found"].is_empty():
					spy["found"] += 1
					spy["found_buildings"] += e["found"].size()
				elif e["type"] == "spy_lost":
					spy["lost"] += 1
				elif e["type"] == "destroyed" and e["building"] == "nuclear_silo":
					spy["silos_destroyed"] += 1
			if m.phase == MatchState.Phase.COIN_FLIP:
				m.resolve_coin_flip()
		rounds.append(m.round_number)
		if m.is_over():
			wins[m.winner] += 1
		if fired > 0:
			nuke_matches += 1
			nukes += fired
	rounds.sort()
	researched_at_15.sort()
	var med := func(a: Array): return a[a.size() / 2] if not a.is_empty() else -1
	print("Level %d: median %d rounds (10%%: %d, 90%%: %d), wins %s, errors %d%s; research items by round 15: median %d; nukes in %d matches (%d fired)" % [
		lvl, med.call(rounds), rounds[n / 10], rounds[n * 9 / 10], str(wins), errors, first_err, med.call(researched_at_15), nuke_matches, nukes])
	if int(spy["sent"]) > 0 or int(spy["silos_destroyed"]) > 0:
		print("    spy trips %d (found something %d, %d buildings in all; shot down %d); silos destroyed %d" % [spy["sent"], spy["found"], spy["found_buildings"], spy["lost"], spy["silos_destroyed"]])
