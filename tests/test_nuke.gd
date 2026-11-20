## Level 3: the nuclear silo and its nuke, the research gate in front of it,
## and the bank upgrade.
extends "res://tests/test_case.gd"

const Levels = preload("res://rules/levels.gd")


## A level 3 flat match where side 0 has an armed silo at (0, 0) and plenty
## of fuel and money.
func _armed():
	var m = flat_match(Levels.data_for(data(), 3))
	var st = m.sides[0]
	st.unlocked["nuclear_silo"] = true
	st.fuel = 50
	st.money = 500
	var silo = put(m, 0, "nuclear_silo", 0, 0)
	silo.carrier_lost = false
	return [m, silo]


func _nuke(silo, target: int) -> Dictionary:
	return {"launcher": silo.hex, "missile": "nuke", "target": target}


func test_a_new_silo_is_empty_and_a_nuke_takes_a_round_to_build() -> void:
	var m = flat_match(Levels.data_for(data(), 3))
	var st = m.sides[0]
	st.unlocked["nuclear_silo"] = true
	st.money = 1000
	st.fuel = 50
	m.begin_round()
	var h := hex(m, 0, 0)
	ok(m.build_action(0, {"action": "build", "type": "nuclear_silo", "hex": h}), "build the silo")
	var silo = st.building_at(h)
	check(silo.carrier_lost, "a new silo has no nuke")
	ok(m.build_action(0, {"action": "replace_carrier", "hex": h}), "build a nuke")
	eq(silo.loading, 1, "the nuke is being built")
	m.end_build_phase()
	err_contains(m.set_launch_orders(0, [_nuke(silo, hex(m, 5, 5))]), "not ready", "can't fire it this round")
	m.resolve_playout()
	m.begin_round()
	eq(silo.loading, 0, "ready the round after")
	m.end_build_phase()
	ok(m.set_launch_orders(0, [_nuke(silo, hex(m, 5, 5))]), "fires next round")


func test_the_nuke_costs_ten_fuel_and_is_used_up() -> void:
	var r = _armed()
	var m = r[0]
	var silo = r[1]
	m.sides[0].fuel = 9
	m.begin_round()
	m.end_build_phase()
	err_contains(m.set_launch_orders(0, [_nuke(silo, hex(m, 5, 5))]), "fuel", "9 fuel is not enough")
	m.sides[0].fuel = 10
	ok(m.set_launch_orders(0, [_nuke(silo, hex(m, 5, 5))]), "10 fuel is")
	m.resolve_playout()
	eq(m.sides[0].fuel, 0, "10 fuel spent")
	check(silo.carrier_lost, "the silo is empty again")


func test_centre_takes_double_and_the_ring_a_missile_each() -> void:
	var r = _armed()
	var m = r[0]
	var silo = r[1]
	var centre = put(m, 1, "base", 6, 6)
	var ring_base = put(m, 1, "decoy", 7, 6)
	var ring_bank = put(m, 1, "bank", 5, 6)
	var outside = put(m, 1, "bank", 3, 6)
	var ev := play_round(m, [_nuke(silo, centre.hex)])
	var hits := {}
	for d in events_of(ev, "impact")[0]["damaged"]:
		hits[int(d["hex"])] = d
	eq(float(hits[centre.hex]["hits"]), 2.0, "the centre takes 2 hits")
	eq(float(hits[ring_base.hex]["hits"]), 1.0, "a hex beside it takes 1")
	var dmg := int(hits[ring_bank.hex]["damage"])
	check(dmg >= 30 and dmg <= 50, "a building beside it takes a basic missile's damage (%d)" % dmg)
	check(not hits.has(outside.hex), "two hexes out is untouched")
	eq(m.sides[1].building_at(centre.hex), null, "a base at the centre falls outright")


func test_centre_damage_is_doubled_for_buildings() -> void:
	var r = _armed()
	var m = r[0]
	var silo = r[1]
	var bunker = put(m, 1, "bunker", 6, 6)
	var ev := play_round(m, [_nuke(silo, bunker.hex)])
	var dmg := int(events_of(ev, "impact")[0]["damaged"][0]["damage"])
	check(dmg >= 60 and dmg <= 100 and dmg % 2 == 0, "twice a basic missile's damage (%d)" % dmg)


func test_a_nuke_takes_down_a_stronghold_at_the_centre_only() -> void:
	var r = _armed()
	var m = r[0]
	var silo = r[1]
	var fort = put(m, 1, "stronghold", 6, 6)
	var fort2 = put(m, 1, "stronghold", 9, 9)
	play_round(m, [_nuke(silo, fort.hex)])
	eq(m.sides[1].building_at(fort.hex), null, "the centre of a nuke destroys a stronghold")
	silo.carrier_lost = false
	m.sides[0].fuel = 50
	play_round(m, [_nuke(silo, hex(m, 10, 9))])
	var f2 = m.sides[1].building_at(fort2.hex)
	check(f2 != null, "the edge of the blast doesn't")
	check(f2.disabled, "but it knocks out the gun")


func test_anti_air_rarely_stops_a_nuke() -> void:
	var stopped := [0, 0]   # without radar, with radar
	for with_radar in [false, true]:
		for k in 200:
			var m = flat_match(Levels.data_for(data(), 3), 100 + k)
			var st = m.sides[0]
			st.unlocked["nuclear_silo"] = true
			st.fuel = 50
			var silo = put(m, 0, "nuclear_silo", 0, 0)
			silo.carrier_lost = false
			put(m, 1, "anti_air", 6, 7)
			if with_radar:
				put(m, 1, "radar", 6, 8)
			var ev := play_round(m, [_nuke(silo, hex(m, 6, 6))])
			for e in events_of(ev, "engage"):
				if e["hit"]:
					stopped[1 if with_radar else 0] += 1
	check(stopped[0] >= 2 and stopped[0] <= 25, "about 5%% without radar (%d of 200)" % stopped[0])
	check(stopped[1] >= 22 and stopped[1] <= 60, "about 20%% with radar (%d of 200)" % stopped[1])


func test_silo_research_waits_for_four_other_items() -> void:
	var d = Levels.data_for(data(), 3)
	var m = flat_match(d)
	var st = m.sides[0]
	st.money = 1000
	var lab = put(m, 0, "lab", 0, 0)
	check(not st.research_available(d).has("nuclear_silo"), "not offered with nothing researched")
	err_contains(st.can_start_research(lab.id, "nuclear_silo", d), "4 research", "says what it needs")
	for item in ["radar", "bunker", "airport", "docks"]:
		st.unlocked[item] = true
	check(st.research_available(d).has("nuclear_silo"), "offered after four")
	ok(st.can_start_research(lab.id, "nuclear_silo", d), "can start it")


func test_silo_and_bank_upgrade_only_in_level_3() -> void:
	for n in [1, 2]:
		var d = Levels.data_for(data(), n)
		var st = flat_match(d).sides[0]
		for item in ["radar", "bunker", "airport", "docks"]:
			st.unlocked[item] = true
		check(not st.research_available(d).has("nuclear_silo"), "no silo in level %d" % n)
		check(not st.research_available(d).has("bank_upgrade"), "no bank upgrade in level %d" % n)
	var d3 = Levels.data_for(data(), 3)
	eq(int(d3.rules["bases"]["strongholds_per_side"]), 1, "level 3 keeps one stronghold per side")
	check(flat_match(d3).sides[0].research_available(d3).has("bank_upgrade"), "bank upgrade in level 3")


func test_bank_upgrade_raises_bank_income_to_25() -> void:
	var d = Levels.data_for(data(), 3)
	var m = flat_match(d)
	var st = m.sides[0]
	put(m, 0, "bank", 0, 0)
	var before := int(st.compute_income(d)["money"])
	st.unlocked["bank_upgrade"] = true
	eq(int(st.compute_income(d)["money"]) - before, 10, "each bank makes 10 more")
