## Level 4: the spy (sent from an airport, finds the enemy's silos) and the
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


func test_spy_reveals_every_silo_and_nothing_else() -> void:
	var r = _spy_match()
	var m = r[0]
	var silo_a = put(m, 1, "nuclear_silo", 2, 2)
	var silo_b = put(m, 1, "nuclear_silo", 10, 3)
	var bank = put(m, 1, "bank", 6, 6)
	var ev := play_round(m, [_spy(r[1], hex(m, 6, 6))])
	var s: Array = events_of(ev, "spy")
	eq(s.size(), 1, "the spy lands")
	eq(s[0]["found"], [silo_a.hex, silo_b.hex], "both silos found")
	check(m.knowledge[0].has(silo_a.hex) and m.knowledge[0].has(silo_b.hex), "silo hexes revealed")
	eq(String(m.knowledge[0][silo_a.hex]["building"]["type"]), "nuclear_silo", "seen as a silo")
	check(not m.knowledge[0].has(bank.hex), "not even the hex he landed on is revealed")
	check(m.sides[1].building_at(bank.hex) != null, "he does no damage")


func test_spy_finding_nothing_reports_no_silos() -> void:
	var r = _spy_match()
	var m = r[0]
	var ev := play_round(m, [_spy(r[1], hex(m, 3, 3))])
	eq(events_of(ev, "spy")[0]["found"], [], "no silos")


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
	var silo = put(m, 1, "nuclear_silo", 2, 2)
	put(m, 1, "anti_air", 6, 6)
	var ev := play_round(m, [_spy(port, hex(m, 6, 6))])
	eq(events_of(ev, "engage").size(), 1, "anti-air fires at him")
	eq(events_of(ev, "spy").size(), 0, "he never lands")
	check(not m.knowledge[0].has(silo.hex), "the silo stays hidden")
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


func test_strong_ai_sends_the_spy_when_no_silo_is_known() -> void:
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


func test_strong_ai_keeps_the_spy_home_once_a_silo_is_known() -> void:
	var r = _ai_spy_match()
	var m = r[0]
	var silo = put(m, 0, "nuclear_silo", 6, 6)
	m.record_sighting(1, silo.hex)
	m.begin_round()
	m.end_build_phase()
	var ai = StrongAI.new(1, m.data, 5)
	var orders: Array = ai.choose_targets(m.view_for(1))
	eq(orders.filter(func(o): return o["missile"] == "spy").size(), 0, "no spy")


func test_strong_ai_researches_the_spy_after_the_airport_and_the_refinery_upgrade() -> void:
	var d4 = Levels.data_for(data(), 4)
	for s in [1, 2, 3, 4]:
		var ai = StrongAI.new(1, d4, s)
		var sp: int = ai.research.find("spy")
		var ap: int = ai.research.find("airport")
		check(ap >= 0 and sp > ap and sp > ai.research.find("refinery_upgrade"), "spy after the airport and the refinery upgrade (seed %d)" % s)
		check(not ai.research.has("nuclear_silo") and not ai.research.has("bank_upgrade"), "carried-over research is not in the order")
	var d3 = Levels.data_for(data(), 3)
	var ai3 = StrongAI.new(1, d3, 1)
	check(not ai3.research.has("spy") and not ai3.research.has("refinery_upgrade"), "neither in level 3")


func test_strong_ai_level_4_matches_play_legally() -> void:
	var d = Levels.data_for(data(), 4)
	for s in [3, 4]:
		var res: Dictionary = MatchRunner.play(d, s, [StrongAI.new(0, d, s), StrongAI.new(1, d, s + 50)], 300)
		eq(res["errors"].size(), 0, "seed %d rejected actions %s" % [s, str(res["errors"].slice(0, 3))])
		check(not res["timed_out"], "seed %d finished" % s)


func test_strong_ai_waits_for_its_own_silo_research_before_spying() -> void:
	var r = _ai_spy_match()
	var m = r[0]
	m.sides[1].unlocked.erase("nuclear_silo")
	m.begin_round()
	m.end_build_phase()
	var ai = StrongAI.new(1, m.data, 5)
	eq(ai.choose_targets(m.view_for(1)).filter(func(o): return o["missile"] == "spy").size(), 0, "no spy yet")


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
