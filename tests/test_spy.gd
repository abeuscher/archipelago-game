## Level 4: the spy (sent from an airport, stays on the enemy island and
## uncovers three hexes a round until a radar or bunker catches him) and the
## refinery upgrade.
extends "res://tests/test_case.gd"

const Levels = preload("res://rules/levels.gd")
const BattleReport = preload("res://game/battle_report.gd")
const StrongAI = preload("res://ai/strong_ai.gd")
const MatchRunner = preload("res://ai/match_runner.gd")


func _spy_match():
	var d = Levels.data_for(data(), 4)
	var m = flat_match(d)
	var st = m.sides[0]
	st.unlocked["airport"] = true
	st.unlocked["spy"] = true
	st.fuel = 30
	st.money = 500
	var port = put(m, 0, "airport", 0, 0)
	return [m, port]


func _spy(port, target: int) -> Dictionary:
	return {"launcher": port.hex, "missile": "spy", "target": target}


func _contiguous(m, path: Array) -> bool:
	var g = m.sides[1].island.grid
	for k in range(1, path.size()):
		if g.distance(int(path[k - 1]), int(path[k])) != 1:
			return false
	return true


func test_spy_lands_and_uncovers_three_contiguous_hexes() -> void:
	var r = _spy_match()
	var m = r[0]
	var lab = put(m, 1, "lab", 6, 6)
	var target := hex(m, 6, 6)
	var ev := play_round(m, [_spy(r[1], target)])
	var s: Array = events_of(ev, "spy")
	eq(s.size(), 1, "the spy lands")
	var path: Array = s[0]["path"]
	check(bool(s[0]["landed"]), "landed this round")
	eq(path.size(), int(m.data.missile("spy")["walks"]), "three hexes")
	eq(int(path[0]), target, "the landing hex first")
	check(_contiguous(m, path), "one after another: %s" % str(path))
	for h in path:
		check(m.knowledge[0].has(int(h)), "hex %d uncovered" % h)
	eq(String(m.knowledge[0][lab.hex]["building"]["type"]), "lab", "the lab he landed on is seen")
	eq(m.spies[0].size(), 1, "he stays on the island")
	eq(int(m.spies[0][0]["hex"]), int(path[-1]), "where he stopped")
	check(m.sides[1].building_at(lab.hex) != null, "he does no damage")


func test_spy_walks_three_new_hexes_every_round() -> void:
	var r = _spy_match()
	var m = r[0]
	play_round(m, [_spy(r[1], hex(m, 6, 6))])
	for k in 3:
		var was: int = int(m.spies[0][0]["hex"])
		var known_before: Dictionary = m.knowledge[0].duplicate()
		var s: Array = events_of(play_round(m, []), "spy")
		eq(s.size(), 1, "round %d: he walks on" % k)
		check(not bool(s[0]["landed"]), "not a landing")
		eq(int(s[0]["start"]), was, "from where he was")
		var path: Array = s[0]["path"]
		eq(path.size(), 3, "three hexes")
		check(_contiguous(m, [was] + path), "contiguous from where he stood: %s" % str(path))
		for h in path:
			check(not known_before.has(int(h)), "hex %d was never seen" % h)
			eq(int(m.knowledge[0][int(h)]["seen_round"]), m.round_number, "and is seen now")


func test_spy_caught_on_landing_by_a_radar_in_range() -> void:
	var r = _spy_match()
	var m = r[0]
	var radar = put(m, 1, "radar", 6, 8)
	var s: Array = events_of(play_round(m, [_spy(r[1], hex(m, 6, 6))]), "spy")
	eq(int(s[0]["caught_by"]), radar.hex, "caught by the radar")
	eq(s[0]["path"], [hex(m, 6, 6)], "only the landing hex")
	eq(m.spies[0].size(), 0, "he is gone")
	eq(String(m.knowledge[0][radar.hex]["building"]["type"]), "radar", "the radar shows itself")


func test_spy_caught_by_a_bunker_built_next_to_him() -> void:
	var r = _spy_match()
	var m = r[0]
	play_round(m, [_spy(r[1], hex(m, 6, 6))])
	var at: int = int(m.spies[0][0]["hex"])
	var g = m.sides[1].island.grid
	var spot := -1
	for n in g.neighbors(at):
		if m.sides[1].building_at(n) == null:
			spot = n
			break
	var bk = put(m, 1, "bunker", spot % g.width, spot / g.width)
	eq(bk.hex, spot, "bunker beside him")
	var s: Array = events_of(play_round(m, []), "spy")
	eq(int(s[0]["caught_by"]), bk.hex, "caught by the bunker")
	eq(s[0]["path"], [], "before he takes a step")
	eq(m.spies[0].size(), 0, "he is gone")


func test_spy_keeps_out_of_known_radar_reach() -> void:
	var r = _spy_match()
	var m = r[0]
	var radar = put(m, 1, "radar", 9, 6)
	m.record_sighting(0, radar.hex)
	var g = m.sides[1].island.grid
	var reach: int = m.sides[1].radar_range(radar, m.data)
	play_round(m, [_spy(r[1], hex(m, 5, 6))])
	for k in 4:
		var s: Array = events_of(play_round(m, []), "spy")
		eq(int(s[0]["caught_by"]), -1, "round %d: not caught" % k)
		for h in s[0]["path"]:
			check(g.distance(int(h), radar.hex) > reach, "hex %d out of the known radar's reach" % h)


func test_spy_landing_on_the_sea_is_lost() -> void:
	var r = _spy_match()
	var m = r[0]
	var h := hex(m, 6, 6)
	m.sides[1].island.land[h] = 0
	var s: Array = events_of(play_round(m, [_spy(r[1], h)]), "spy")
	check(bool(s[0]["lost_at_sea"]), "lost at sea")
	eq(m.spies[0].size(), 0, "no spy on the island")


func test_one_spy_at_a_time_and_new_launches_get_new_ids() -> void:
	var r = _spy_match()
	var m = r[0]
	var launcher = put(m, 0, "basic_launcher", 2, 0)
	play_round(m, [_spy(r[1], hex(m, 6, 6))])
	var spy_id = m.spies[0][0]["id"]
	m.begin_round()
	m.end_build_phase()
	err_contains(m.set_launch_orders(0, [_spy(r[1], hex(m, 3, 3))]), "still on the enemy island", "no second spy")
	ok(m.set_launch_orders(0, [{"launcher": launcher.hex, "missile": "basic", "target": hex(m, 2, 2)}]))
	ok(m.set_launch_orders(1, []))
	var ev: Array = m.resolve_playout()
	var launches: Array = events_of(ev, "launch")
	eq(launches.size(), 1, "the missile goes")
	check(launches.all(func(e): return e["id"] != spy_id), "the missile's id is not the spy's")


func test_spy_costs_two_fuel_and_sixty_money() -> void:
	var r = _spy_match()
	var m = r[0]
	var st = m.sides[0]
	var spy: Dictionary = m.data.missile("spy")
	eq(int(spy["fuel"]), 2, "2 fuel")
	eq(int(spy["money"]), 60, "60 money")
	m.begin_round()
	var fuel_before: int = st.fuel
	var money_before: int = st.money
	m.end_build_phase()
	ok(m.set_launch_orders(0, [_spy(r[1], hex(m, 3, 3))]))
	ok(m.set_launch_orders(1, []))
	m.resolve_playout()
	eq(st.fuel, fuel_before - 2, "fuel paid")
	eq(st.money, money_before - 60, "money paid")


func test_spy_is_half_as_easy_to_shoot_down() -> void:
	var d = data()
	var spy: Dictionary = d.missile("spy")
	var aa: Dictionary = d.section("anti_air")
	eq(float(spy["anti_air_accuracy"]), float(aa["accuracy"]) / 2.0, "half the usual chance")
	eq(float(spy["anti_air_accuracy_with_radar"]), float(aa["accuracy_with_radar"]) / 2.0, "half with radar too")


func test_spy_shot_down_finds_nothing_but_keeps_the_transport() -> void:
	var r = _spy_match()
	var m = r[0]
	var port = r[1]
	m.data.set_path("rules.missiles.spy.anti_air_accuracy", 1.0)
	var bank = put(m, 1, "bank", 2, 2)
	put(m, 1, "anti_air", 6, 6)
	var ev := play_round(m, [_spy(port, hex(m, 6, 6))])
	eq(events_of(ev, "engage").size(), 1, "anti-air fires at him")
	eq(events_of(ev, "spy").size(), 0, "he never lands")
	check(not m.knowledge[0].has(bank.hex), "the bank stays hidden")
	check(not port.carrier_lost, "the airport keeps its transport")
	eq(events_of(ev, "carrier_lost").size(), 0, "no transport lost")


func test_spy_flies_while_the_transport_is_lost_but_not_alongside_it() -> void:
	var r = _spy_match()
	var m = r[0]
	var port = r[1]
	m.begin_round()
	m.end_build_phase()
	err_contains(m.set_launch_orders(0, [_spy(port, 1),
		{"launcher": port.hex, "missile": "transport", "target": 2, "dir": 0}]), "already has an order", "one order per airport")
	port.carrier_lost = true
	ok(m.set_launch_orders(0, [_spy(port, 1)]), "his own helicopter")


func test_spy_needs_its_research() -> void:
	var r = _spy_match()
	var m = r[0]
	m.sides[0].unlocked.erase("spy")
	m.begin_round()
	m.end_build_phase()
	err_contains(m.set_launch_orders(0, [_spy(r[1], 1)]), "not researched", "no spy without the research")


func test_spy_research_needs_the_airport_and_level_4() -> void:
	for n in [1, 2, 3]:
		var dn = Levels.data_for(data(), n)
		var sn = flat_match(dn).sides[0]
		sn.unlocked["airport"] = true
		check(not sn.research_available(dn).has("spy"), "no spy in level %d" % n)
		check(not sn.research_available(dn).has("refinery_upgrade"), "no refinery upgrade in level %d" % n)
	var d = Levels.data_for(data(), 4)
	var m4 = flat_match(d)
	var st = m4.sides[0]
	st.money = 500
	var lab = put(m4, 0, "lab", 0, 0)
	err_contains(st.can_start_research(lab.id, "spy", d), "Airport", "the airport first")
	check(not st.research_available(d).has("spy"), "not offered before the airport")
	st.unlocked["airport"] = true
	eq(st.can_start_research(lab.id, "spy", d), "", "then the spy")
	check(st.research_available(d).has("refinery_upgrade"), "refinery upgrade in level 4")
	check(bool(d.research_item("nuclear_silo").get("available", false)), "silos in level 4")


func test_refinery_upgrade_doubles_refinery_fuel() -> void:
	var d = Levels.data_for(data(), 4)
	var m = flat_match(d)
	var st = m.sides[0]
	put(m, 0, "refinery", 0, 0)
	put(m, 0, "refinery", 2, 0)
	var base := int(d.section("economy")["baseline_fuel"])
	var each := int(d.building("refinery")["produces"]["fuel"])
	eq(int(st.compute_income(d)["fuel"]), base + 2 * each, "before")
	st.unlocked["refinery_upgrade"] = true
	eq(int(st.compute_income(d)["fuel"]), base + 4 * each, "each refinery makes twice as much")


func test_spy_shot_down_is_its_own_event_and_not_a_missile_in_the_report() -> void:
	var r = _spy_match()
	var m = r[0]
	m.data.set_path("rules.missiles.spy.anti_air_accuracy", 1.0)
	put(m, 1, "anti_air", 6, 6)
	var ev := play_round(m, [_spy(r[1], hex(m, 6, 6))])
	eq(events_of(ev, "spy_lost").size(), 1, "spy_lost event")
	var c: Dictionary = BattleReport.counts(ev)
	eq(int(c["our_shot_down"]), 0, "not counted as a missile shot down")
	eq(int(c["hit_them"]), 0, "not counted as a hit")


func _ai_spy_match():
	var d = Levels.data_for(data(), 4)
	var m = flat_match(d)
	var st = m.sides[1]
	st.unlocked["airport"] = true
	st.unlocked["spy"] = true
	st.unlocked["nuclear_silo"] = true
	st.fuel = 30
	st.money = 300
	var port = put(m, 1, "airport", 3, 3)
	m.round_number = 9
	return [m, port]


func test_strong_ai_sends_the_spy_when_it_knows_few_targets() -> void:
	var r = _ai_spy_match()
	var m = r[0]
	put(m, 0, "anti_air", 2, 2)
	m.record_sighting(1, hex(m, 2, 2))
	m.begin_round()
	m.end_build_phase()
	var ai = StrongAI.new(1, m.data, 5)
	var orders: Array = ai.choose_targets(m.view_for(1))
	var spies: Array = orders.filter(func(o): return o["missile"] == "spy")
	eq(spies.size(), 1, "the spy goes")
	eq(int(spies[0]["launcher"]), r[1].hex, "from the airport")
	var g = m.sides[0].island.grid
	check(g.distance(int(spies[0]["target"]), hex(m, 2, 2)) > int(m.data.section("anti_air")["radius"]), "out of the known gun's reach")
	ok(m.set_launch_orders(1, orders), "orders are legal")
	ok(m.set_launch_orders(0, []))
	m.resolve_playout()
	m.begin_round()
	m.end_build_phase()
	orders = ai.choose_targets(m.view_for(1))
	eq(orders.filter(func(o): return o["missile"] == "spy").size(), 0, "not again the round after")


func test_strong_ai_level_4_matches_play_legally() -> void:
	var d = Levels.data_for(data(), 4)
	for s in [3, 4]:
		var res: Dictionary = MatchRunner.play(d, s, [StrongAI.new(0, d, s), StrongAI.new(1, d, s + 50)], 300)
		eq(res["errors"].size(), 0, "seed %d rejected actions %s" % [s, str(res["errors"].slice(0, 3))])
		check(not res["timed_out"], "seed %d finished" % s)


func test_level_4_starts_both_sides_with_level_3_research_done() -> void:
	var m = MatchState.create(Levels.data_for(data(), 4), 7)
	for side in 2:
		var st = m.sides[side]
		check(st.is_unlocked("nuclear_silo") and st.is_unlocked("bank_upgrade"), "side %d has the silo and the bank upgrade" % side)
		check(not st.is_unlocked("spy") and not st.is_unlocked("refinery_upgrade"), "side %d: level 4's own research still to do" % side)
		check(st.building_unlocked("nuclear_silo", m.data), "side %d can build a silo at once" % side)
	var m3 = MatchState.create(Levels.data_for(data(), 3), 7)
	eq(m3.sides[0].unlocked.size(), 0, "level 3 starts with nothing researched")
	eq(m3.sides[1].unlocked.size(), 0, "nor does its enemy")


func test_strong_ai_sends_no_new_spy_while_one_is_on_the_island() -> void:
	var r = _ai_spy_match()
	var m = r[0]
	var ai = StrongAI.new(1, m.data, 5)
	m.begin_round()
	m.end_build_phase()
	var orders: Array = ai.choose_targets(m.view_for(1))
	eq(orders.filter(func(o): return o["missile"] == "spy").size(), 1, "the spy goes")
	ok(m.set_launch_orders(1, orders))
	ok(m.set_launch_orders(0, []))
	m.resolve_playout()
	for k in 4:
		check(not m.spies[1].is_empty(), "round %d: he is still there" % k)
		m.begin_round()
		m.end_build_phase()
		orders = ai.choose_targets(m.view_for(1))
		eq(orders.filter(func(o): return o["missile"] == "spy").size(), 0, "round %d: no second spy" % k)
		ok(m.set_launch_orders(1, orders))
		ok(m.set_launch_orders(0, []))
		m.resolve_playout()
	m.spies[1].clear()   # caught
	m.begin_round()
	m.end_build_phase()
	eq(ai.choose_targets(m.view_for(1)).filter(func(o): return o["missile"] == "spy").size(), 1, "a new one once he is gone")


func test_strong_ai_lands_the_spy_out_of_known_radar_reach() -> void:
	var r = _ai_spy_match()
	var m = r[0]
	var radar = put(m, 0, "radar", 7, 7)
	m.record_sighting(1, radar.hex)
	m.begin_round()
	m.end_build_phase()
	var orders: Array = StrongAI.new(1, m.data, 5).choose_targets(m.view_for(1))
	var spies: Array = orders.filter(func(o): return o["missile"] == "spy")
	eq(spies.size(), 1, "the spy goes")
	var reach := int(m.data.section("radar")["range_by_level"][0])
	check(m.sides[0].island.grid.distance(int(spies[0]["target"]), radar.hex) > reach, "landing out of the radar's reach")


func test_strong_ai_researches_the_spy_right_after_the_airport() -> void:
	var d4 = Levels.data_for(data(), 4)
	for s in [1, 2, 3, 4]:
		var ai = StrongAI.new(1, d4, s)
		var ap: int = ai.research.find("airport")
		check(ap >= 0 and ai.research.find("spy") == ap + 1, "spy right after the airport (seed %d)" % s)
		check(ai.research.has("refinery_upgrade"), "refinery upgrade")
		check(not ai.research.has("nuclear_silo") and not ai.research.has("bank_upgrade"), "carried-over research is not in the order")
	var ai3 = StrongAI.new(1, Levels.data_for(data(), 3), 1)
	check(not ai3.research.has("spy") and not ai3.research.has("refinery_upgrade"), "neither in level 3")


func test_strong_ai_fires_at_banks_and_labs_it_knows() -> void:
	var d = Levels.data_for(data(), 4)
	var m = flat_match(d)
	var st = m.sides[1]
	st.fuel = 30
	put(m, 1, "basic_launcher", 3, 3)
	put(m, 1, "basic_launcher", 5, 3)   # one shot kept for finding what's hidden, one spare
	# Every enemy base already found and destroyed, so nothing else to aim at.
	for b in m.sides[0].of_role(d, "base"):
		m.sides[0].remove_building(b.hex, d)
		m.bases_destroyed_by[1].append(b.hex)
	var lab = put(m, 0, "lab", 9, 9)
	m.record_sighting(1, lab.hex)
	m.begin_round()
	m.end_build_phase()
	var orders: Array = StrongAI.new(1, d, 5).choose_targets(m.view_for(1))
	check(orders.any(func(o): return int(o["target"]) == lab.hex), "the known lab is shot at: %s" % str(orders))


func test_strong_ai_keeps_the_spy_money_back_in_the_build() -> void:
	var r = _ai_spy_match()
	var m = r[0]
	m.begin_round()
	var st = m.sides[1]
	st.money = 100
	var ai = StrongAI.new(1, m.data, 5)
	for a in ai.choose_build(m.view_for(1)):
		m.build_action(1, a)
	check(st.money >= int(m.data.missile("spy")["money"]), "money left for the trip: %d" % st.money)
	m.end_build_phase()
	var orders: Array = ai.choose_targets(m.view_for(1))
	eq(orders.filter(func(o): return o["missile"] == "spy").size(), 1, "and he goes")


func test_level_4_enemy_builds_labs_early_and_focuses_its_research() -> void:
	var d4 = Levels.data_for(data(), 4)
	var ai = StrongAI.new(1, d4, 1)
	var order: Array = ai._build_order()
	var at := int(d4.ai["strong"]["nukes"]["lab_at"])
	eq(order[at], "lab", "first lab at %d" % at)
	eq(order[at + 1], "lab", "the extra lab right after")
	var ai3 = StrongAI.new(1, Levels.data_for(data(), 3), 1)
	check(ai3._build_order().find("lab") > at, "level 3 unchanged")
	# Two labs, one project: the second helps instead of starting another.
	var m = flat_match(d4)
	var st = m.sides[1]
	st.money = 1000
	put(m, 1, "lab", 3, 3)
	put(m, 1, "lab", 5, 3)
	m.begin_round()
	var acts: Array = ai.choose_build(m.view_for(1)).filter(func(a): return a["action"] == "research")
	eq(acts.size(), 1, "one project at a time")
