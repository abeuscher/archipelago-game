## Debug probe: plays one AI-vs-AI match on a level and prints what each
## side ended with and how its troops did, round by round when asked.
##   godot --headless --path . -s tools/level_probe.gd -- --level 2 --seed 301 [--rounds 80] [--verbose]
extends SceneTree

const GameData = preload("res://rules/game_data.gd")
const Levels = preload("res://rules/levels.gd")
const StrongAI = preload("res://ai/strong_ai.gd")
const MatchState = preload("res://rules/match_state.gd")


func _initialize() -> void:
	var lvl := 2
	var seed_in := 301
	var rounds := 80
	var verbose := false
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		match args[i]:
			"--level": lvl = int(args[i + 1])
			"--seed": seed_in = int(args[i + 1])
			"--rounds": rounds = int(args[i + 1])
			"--verbose": verbose = true
	var d = Levels.data_for(GameData.load_default(), lvl)
	var ais := [StrongAI.new(0, d, seed_in), StrongAI.new(1, d, seed_in)]
	var m = MatchState.create(d, seed_in)
	for s in 2:
		var su: Dictionary = ais[s].choose_setup(m.view_for(s))
		m.setup_side(s, su["bases"], su["decoys"])
	while not m.is_over() and m.round_number < rounds:
		m.begin_round()
		for s in 2:
			for a in ais[s].choose_build(m.view_for(s)):
				m.build_action(s, a)
		m.end_build_phase()
		var orders: Array = []
		for s in 2:
			orders.append(ais[s].choose_targets(m.view_for(s)))
			m.set_launch_orders(s, orders[s])
		var ev: Array = m.resolve_playout()
		if verbose:
			var line := "R%d" % m.round_number
			for s in 2:
				var kinds := {}
				for o in orders[s]:
					kinds[o["missile"]] = int(kinds.get(o["missile"], 0)) + 1
				line += "  s%d %s money %d fuel %d bases %d" % [s, str(kinds), m.sides[s].money, m.sides[s].fuel, m.sides[s].bases_alive(d)]
			for e in ev:
				if e["type"] in ["platoon", "carrier_lost", "boat_sunk", "stronghold_revealed"]:
					line += "\n    " + str(e)
			print(line)
		if m.phase == MatchState.Phase.COIN_FLIP:
			m.resolve_coin_flip()
	print("Level %d seed %d: round %d, winner %d (%s)" % [lvl, seed_in, m.round_number, m.winner, m.end_reason])
	for s in 2:
		var st = m.sides[s]
		var types := {}
		for b in st.buildings.values():
			types[b.type] = int(types.get(b.type, 0)) + 1
		print("side %d: money %d fuel %d research %d unlocked %s" % [s, st.money, st.fuel, st.research, str(st.unlocked.keys())])
		print("   buildings %s" % str(types))
		var known := {}
		for h in m.knowledge[s]:
			var b = m.knowledge[s][h]["building"]
			if b != null:
				known[b["type"]] = int(known.get(b["type"], 0)) + 1
		print("   knows of enemy: %s, enemy bases destroyed %s" % [str(known), str(m.bases_destroyed_by[s].size())])
	quit(0)
