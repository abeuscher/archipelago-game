## The simple AI and the headless match runner.
extends "res://tests/test_case.gd"

const SimpleAI = preload("res://ai/simple_ai.gd")
const MatchRunner = preload("res://ai/match_runner.gd")
const SideView = preload("res://rules/side_view.gd")


func _play(seed_in: int) -> Dictionary:
	var d = data()
	return MatchRunner.play(d, seed_in, [SimpleAI.new(0, d, seed_in), SimpleAI.new(1, d, seed_in)], 300)


func test_ai_match_is_deterministic() -> void:
	var a := _play(31)
	var b := _play(31)
	eq(a["fingerprint"], b["fingerprint"], "same seed, same match")
	eq(a["rounds"], b["rounds"], "rounds")


func test_ai_matches_finish_without_rejected_actions() -> void:
	for s in [1, 2, 3]:
		var r := _play(s)
		check(not r["timed_out"], "seed %d timed out" % s)
		eq(r["errors"].size(), 0, "seed %d rejected actions %s" % [s, str(r["errors"].slice(0, 3))])


func test_ai_setup_respects_spacing() -> void:
	var d = data()
	var m = MatchState.create(d, 8)
	var ai = SimpleAI.new(0, d, 8)
	var setup: Dictionary = ai.choose_setup(m.view_for(0))
	eq(setup["bases"].size(), 3, "three bases")
	eq(setup["decoys"].size(), 1, "one decoy by default")
	ok(m.setup_side(0, setup["bases"], setup["decoys"]))


func test_ai_only_receives_a_side_view() -> void:
	# The AI's entry points take a SideView; a SideView exposes no opponent state.
	var d = data()
	var m = MatchState.create(d, 4)
	var v = m.view_for(1)
	check(v is SideView, "view type")
	for prop in v.get_property_list():
		var n: String = prop["name"]
		check(n != "sides" and n != "knowledge" and n != "dice", "view leaks %s" % n)


func test_ai_opening_follows_build_order() -> void:
	var d = data()
	var m = MatchState.create(d, 12)
	var ai = SimpleAI.new(0, d, 12)
	var setup: Dictionary = ai.choose_setup(m.view_for(0))
	ok(m.setup_side(0, setup["bases"], setup["decoys"]))
	var view = m.view_for(0)
	view.round_number = 1
	var actions: Array = ai.choose_build(view)
	var built: Array = actions.filter(func(a): return a["action"] == "build").map(func(a): return a["type"])
	var spent := 0
	for t in built:
		spent += d.cost(t)
	check(spent <= m.sides[0].money, "spends no more than it has")
	check(built.size() >= 2 and built[0] == "basic_launcher" and built[1] == "bank", "opens launcher, then bank: %s" % str(built))
	var left: int = m.sides[0].money - spent
	check(built.size() < 11, "stops at the build order's end or when money runs out (%d left)" % left)


# --- Strong AI (section 12) --------------------------------------------------

const StrongAI = preload("res://ai/strong_ai.gd")


func _play_strong(seed_in: int, handicap: String = "") -> Dictionary:
	var d = data()
	return MatchRunner.play(d, seed_in, [StrongAI.new(0, d, seed_in, handicap), SimpleAI.new(1, d, seed_in)], 300)


func test_strong_ai_deterministic_and_legal() -> void:
	var a := _play_strong(21)
	var b := _play_strong(21)
	eq(a["fingerprint"], b["fingerprint"], "same seed, same match")
	for s in [21, 22, 23]:
		var r := _play_strong(s)
		check(not r["timed_out"], "seed %d timed out" % s)
		eq(r["errors"].size(), 0, "seed %d rejected actions %s" % [s, str(r["errors"].slice(0, 3))])


func test_strong_ai_handicaps_play_legally() -> void:
	var d = data()
	for preset in d.ai["strong"]["handicap_presets"]:
		var r := _play_strong(5, preset)
		eq(r["errors"].size(), 0, "%s rejected actions %s" % [preset, str(r["errors"].slice(0, 3))])
		check(not r["timed_out"], "%s timed out" % preset)


func test_strong_ai_bases_out_of_one_missiles_view() -> void:
	var d = data()
	var max_view := 0
	for mt in d.missile_types():
		max_view = maxi(max_view, int(d.missile(mt)["view_radius"]))
	for seed_in in [3, 4, 5, 6]:
		var m = MatchState.create(d, seed_in)
		var ai = StrongAI.new(0, d, seed_in)
		var setup: Dictionary = ai.choose_setup(m.view_for(0))
		ok(m.setup_side(0, setup["bases"], setup["decoys"]), "setup legal")
		var g = m.sides[0].island.grid
		var bs: Array = setup["bases"]
		for i in bs.size():
			for j in range(i + 1, bs.size()):
				check(g.distance(bs[i], bs[j]) > 2 * max_view, "seed %d: bases %d and %d share a view" % [seed_in, bs[i], bs[j]])
		eq(setup["decoys"].size(), 1, "buys the decoy")


func test_strong_ai_hits_weapons_but_keeps_a_shot_for_bases() -> void:
	var m = flat_match()
	var d = m.data
	put(m, 0, "basic_launcher", 1, 1)
	put(m, 0, "basic_launcher", 3, 1)
	m.sides[0].fuel = 6
	var enemy_launcher = put(m, 1, "basic_launcher", 5, 5)
	var enemy_base_hex: int = hex(m, 14, 14)   # one of flat_match's corner bases
	m.begin_round()
	m.end_build_phase()
	m.record_sighting(0, enemy_launcher.hex)
	m.record_sighting(0, enemy_base_hex)
	var ai = StrongAI.new(0, d, 1)
	var orders: Array = ai.choose_targets(m.view_for(0))
	var targets: Array = orders.map(func(o): return o["target"])
	eq(orders.size(), 2, "both launchers fire")
	check(targets.has(enemy_launcher.hex), "hits the known active launcher")
	check(targets.has(enemy_base_hex), "keeps a shot for the known base")
	ok(m.set_launch_orders(0, orders), "orders legal")


func test_strong_ai_builds_where_the_enemy_has_not_looked() -> void:
	var m = flat_match()
	var d = m.data
	var g = m.sides[0].island.grid
	# The enemy has seen every hex except a small patch.
	var hidden := {}
	for h in g.within(hex(m, 3, 3), 1):
		hidden[h] = true
	for i in g.count:
		if not hidden.has(i):
			m.record_sighting(1, i)
	var ai = StrongAI.new(0, d, 1)
	var view = m.view_for(0)
	ai._enemy_grid = HexGrid.new(view.enemy_width, view.enemy_height)
	var h: int = ai._place_strong(view.own, "bank", view)
	check(hidden.has(h), "bank placed on an unseen hex (got %d)" % h)


func test_strong_ai_search_skips_explored_ground() -> void:
	var m = flat_match()
	var d = m.data
	put(m, 0, "basic_launcher", 1, 1)
	m.round_number = 2
	var g = m.sides[1].island.grid
	var c: int = g.center_index()
	for h in g.within(c, 3):
		m.record_sighting(0, h)
	var ai = StrongAI.new(0, d, 1)
	var orders: Array = ai.choose_targets(m.view_for(0))
	eq(orders.size(), 1, "one search shot")
	if orders.size() == 1:
		check(g.distance(int(orders[0]["target"]), c) > 1, "aims away from explored ground")


func test_strong_ai_keeps_adding_launchers() -> void:
	# The enemy must build up its offence, not sit on one launcher.
	const StrongAI = preload("res://ai/strong_ai.gd")
	var d = data()
	for seed_in in [3, 11]:
		var m = MatchState.create(d, seed_in)
		var ais := [StrongAI.new(0, d, seed_in), StrongAI.new(1, d, seed_in + 1)]
		for s in 2:
			var setup: Dictionary = ais[s].choose_setup(m.view_for(s))
			m.setup_side(s, setup["bases"], setup["decoys"])
		while not m.is_over() and m.round_number < 10:
			m.begin_round()
			for s in 2:
				for a in ais[s].choose_build(m.view_for(s)):
					m.build_action(s, a)
			m.end_build_phase()
			for s in 2:
				m.set_launch_orders(s, ais[s].choose_targets(m.view_for(s)))
			m.resolve_playout()
		if not m.is_over():
			check(m.sides[1].count_role(d, "launcher") >= 3, "at least 3 launchers by round 10 (seed %d)" % seed_in)
