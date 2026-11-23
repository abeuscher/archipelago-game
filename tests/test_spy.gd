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


func test_spy_reveals_every_bank_lab_and_refinery_and_nothing_else() -> void:
	var r = _spy_match()
	var m = r[0]
	var bank = put(m, 1, "bank", 2, 2)
	var lab = put(m, 1, "lab", 10, 3)
	var refinery = put(m, 1, "refinery", 12, 8)
	var silo = put(m, 1, "nuclear_silo", 6, 6)
	var launcher = put(m, 1, "basic_launcher", 8, 8)
	var ev := play_round(m, [_spy(r[1], hex(m, 6, 6))])
	var s: Array = events_of(ev, "spy")
	eq(s.size(), 1, "the spy lands")
	var want: Array = [bank.hex, lab.hex, refinery.hex]
	want.sort()
	var got: Array = s[0]["found"].duplicate()
	got.sort()
	eq(got, want, "the bank, the lab and the refinery found")
	for b in [bank, lab, refinery]:
		check(m.knowledge[0].has(b.hex), "%s revealed" % b.type)
	eq(String(m.knowledge[0][lab.hex]["building"]["type"]), "lab", "seen as a lab")
	check(not m.knowledge[0].has(silo.hex), "not the silo he landed on")
	check(not m.knowledge[0].has(launcher.hex), "nor weapons")
	for h in m.sides[1].of_role(m.data, "base").map(func(x): return x.hex):
		check(not m.knowledge[0].has(h), "nor bases")
	check(m.sides[1].building_at(bank.hex) != null, "he does no damage")


func test_spy_finding_nothing_reports_nothing() -> void:
	var r = _spy_match()
	var m = r[0]
	var ev := play_round(m, [_spy(r[1], hex(m, 3, 3))])
	eq(events_of(ev, "spy")[0]["found"], [], "nothing found")


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


func test_strong_ai_keeps_the_spy_home_when_it_knows_enough_targets() -> void:
	var r = _ai_spy_match()
	var m = r[0]
	var n := int(m.data.ai["strong"]["spy"]["known_below"])
	for k in n:
		var b = put(m, 0, "bank", 2 * k, 10)
		m.record_sighting(1, b.hex)
	m.begin_round()
	m.end_build_phase()
	var ai = StrongAI.new(1, m.data, 5)
	eq(ai.choose_targets(m.view_for(1)).filter(func(o): return o["missile"] == "spy").size(), 0, "no spy with %d known" % n)


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
