## Resources, building, placement, repair and research.
extends "res://tests/test_case.gd"


func test_start_resources_and_no_income_round_one() -> void:
	var m = flat_match()
	eq(m.sides[0].money, m.data.integer("economy", "start_money"), "start money")
	eq(m.sides[0].fuel, 3, "start fuel")
	m.begin_round()
	eq(m.sides[0].money, m.data.integer("economy", "start_money"), "round 1 money")
	eq(m.sides[0].fuel, 3, "round 1 fuel")


func test_baseline_and_building_income() -> void:
	var m = flat_match()
	put(m, 0, "bank", 1, 1)
	put(m, 0, "refinery", 2, 1)
	play_round(m)
	m.begin_round()
	eq(m.sides[0].money, m.data.integer("economy", "start_money") + 20 + 15, "money round 2")
	eq(m.sides[0].fuel, 3 + 3 + 3, "fuel round 2")
	eq(m.sides[1].money, m.data.integer("economy", "start_money") + 20, "other side baseline")


func test_damaged_buildings_half_income_rounded_up() -> void:
	var m = flat_match()
	var bank = put(m, 0, "bank", 1, 1)
	var ref = put(m, 0, "refinery", 2, 1)
	bank.hp = 10
	ref.hp = 39
	var inc: Dictionary = m.sides[0].compute_income(m.data)
	eq(inc["money"], 20 + 8, "half bank")
	eq(inc["fuel"], 3 + 2, "half refinery")


func test_half_strength_flag_off() -> void:
	var d = data()
	d.set_path("rules.damage.half_strength_when_damaged", false)
	var m = flat_match(d)
	var bank = put(m, 0, "bank", 1, 1)
	bank.hp = 10
	eq(m.sides[0].compute_income(d)["money"], 35, "damaged bank at full strength when flag off")


func test_build_costs_and_checks() -> void:
	var m = flat_match()
	m.begin_round()
	m.sides[0].money = 160   # enough for a launcher and a lab, not a second lab
	var h := hex(m, 3, 3)
	ok(m.build_action(0, {"action": "build", "type": "basic_launcher", "hex": h}))
	eq(m.sides[0].money, 100, "after launcher")
	err_contains(m.build_action(0, {"action": "build", "type": "bank", "hex": h}), "occupied")
	err_contains(m.build_action(0, {"action": "build", "type": "radar", "hex": hex(m, 5, 5)}), "Not available")
	err_contains(m.build_action(0, {"action": "build", "type": "ballistic_launcher", "hex": hex(m, 5, 5)}), "Not available")
	err_contains(m.build_action(0, {"action": "build", "type": "base", "hex": hex(m, 5, 5)}), "Not available")
	ok(m.build_action(0, {"action": "build", "type": "lab", "hex": hex(m, 6, 6)}))
	err_contains(m.build_action(0, {"action": "build", "type": "lab", "hex": hex(m, 7, 7)}), "money")


func test_build_on_ocean_rejected() -> void:
	var m = MatchState.create(data(), 9)
	var st = m.sides[0]
	var ocean := -1
	for i in st.island.grid.count:
		if not st.island.is_land(i):
			ocean = i
			break
	err_contains(st.can_build("bank", ocean, m.data, m.settings), "Not land")


func test_setup_bases_not_adjacent() -> void:
	var m = flat_match(null, 1, false)
	var st = m.sides[0]
	st.setup_done = false
	var g = st.island.grid
	err_contains(st.setup([hex(m, 2, 2), hex(m, 3, 2), hex(m, 8, 8)], [], m.data, m.settings), "close")
	err_contains(st.setup([hex(m, 2, 2), hex(m, 5, 2), hex(m, 8, 8)], [hex(m, 9, 8)], m.data, m.settings), "close")
	eq(st.buildings.size(), 0, "failed setup leaves no buildings")
	ok(st.setup([hex(m, 2, 2), hex(m, 5, 2), hex(m, 8, 8)], [hex(m, 11, 11)], m.data, m.settings))
	eq(st.money, m.data.integer("economy", "start_money") - 20, "decoy bought from starting money")
	eq(st.bases_alive(m.data), 3, "bases")
	check(g != null)


func test_decoy_limit_and_rebuild() -> void:
	var m = flat_match()
	put(m, 0, "decoy", 1, 1)
	m.begin_round()
	err_contains(m.build_action(0, {"action": "build", "type": "decoy", "hex": hex(m, 6, 6)}), "limit")
	m.sides[0].remove_building(hex(m, 1, 1), m.data)
	ok(m.build_action(0, {"action": "build", "type": "decoy", "hex": hex(m, 6, 6)}), "rebuild decoy")

	var m3 = MatchState.create(data(), 1, {"decoys_per_side": 3})
	check(m3.settings["decoys_per_side"] == 3, "setting override")


func test_weapon_repair_out_one_round() -> void:
	var m = flat_match()
	var l = put(m, 0, "basic_launcher", 1, 1)
	l.hp = 20
	l.disabled = true
	m.begin_round()
	ok(m.build_action(0, {"action": "repair", "hex": l.hex}))
	eq(m.sides[0].money, m.data.integer("economy", "start_money") - 18, "repair is 30% of 60")
	eq(l.hp, 50, "repair restores HP")
	m.end_build_phase()
	var tgt := hex(m, 7, 7)
	err_contains(m.set_launch_orders(0, [{"launcher": l.hex, "missile": "basic", "target": tgt}]), "out of action")
	m.resolve_playout()
	m.begin_round()
	check(not l.disabled and not l.repairing, "launcher back next round")
	m.end_build_phase()
	ok(m.set_launch_orders(0, [{"launcher": l.hex, "missile": "basic", "target": tgt}]))


func test_repair_takes_any_building_out_for_a_round() -> void:
	var m = flat_match()
	var radar = put(m, 0, "radar", 1, 1)
	var bank = put(m, 0, "bank", 2, 1)
	radar.hp = 10
	bank.hp = 10
	eq(m.sides[0].radar_range(radar, m.data), 1, "damaged radar at base level: 2 / 2 = 1")
	m.begin_round()
	ok(m.build_action(0, {"action": "repair", "hex": radar.hex}))
	ok(m.build_action(0, {"action": "repair", "hex": bank.hex}))
	eq(m.sides[0].radar_range(radar, m.data), 0, "radar off while repairing")
	m.end_build_phase()
	ok(m.set_launch_orders(0, []))
	ok(m.set_launch_orders(1, []))
	m.resolve_playout()
	var money_before: int = m.sides[0].money
	m.begin_round()
	eq(m.sides[0].money - money_before, int(m.data.section("economy")["baseline_money"]), "bank made nothing in its repair round")
	eq(m.sides[0].radar_range(radar, m.data), 2, "full range after repair")
	m.end_build_phase()
	ok(m.set_launch_orders(0, []))
	ok(m.set_launch_orders(1, []))
	m.resolve_playout()
	money_before = m.sides[0].money
	m.begin_round()
	eq(m.sides[0].money - money_before, int(m.data.section("economy")["baseline_money"]) + 15, "bank pays in full after")


func test_half_strength_while_repairing_when_switched_off() -> void:
	var m = flat_match()
	m.data.set_path("rules.damage.repair_takes_building_out", false)
	var radar = put(m, 0, "radar", 1, 1)
	radar.hp = 10
	m.begin_round()
	ok(m.build_action(0, {"action": "repair", "hex": radar.hex}))
	eq(m.sides[0].radar_range(radar, m.data), 1, "spec rule: still half while repairing")
	m.end_build_phase()
	ok(m.set_launch_orders(0, []))
	ok(m.set_launch_orders(1, []))
	m.resolve_playout()
	m.begin_round()
	eq(m.sides[0].radar_range(radar, m.data), 2, "full range after repair")


func test_radar_range_by_level() -> void:
	var m = flat_match()
	var st = m.sides[0]
	var r = put(m, 0, "radar", 4, 4)
	for lvl in 3:
		st.island.level[r.hex] = lvl
		eq(st.radar_range(r, m.data), [2, 3, 4][lvl], "radar level %d" % lvl)
	r.hp = 1
	st.island.level[r.hex] = 2
	eq(st.radar_range(r, m.data), 2, "half of 4")
	st.island.level[r.hex] = 1
	eq(st.radar_range(r, m.data), 1, "half of 3 rounds down")


func test_bases_and_decoys_not_repairable() -> void:
	var m = flat_match()
	var b = put(m, 0, "base", 1, 1)
	b.hits = 1.0
	m.begin_round()
	err_contains(m.build_action(0, {"action": "repair", "hex": b.hex}), "cannot be repaired")


func test_research_one_lab_radar_three_rounds() -> void:
	var m = flat_match()
	var lab = put(m, 0, "lab", 1, 1)
	m.begin_round()
	ok(m.build_action(0, {"action": "research", "lab": lab.id, "item": "radar"}))
	eq(m.sides[0].money, m.data.integer("economy", "start_money") - 30, "radar research costs 30")
	for i in 2:
		m.end_build_phase()
		m.resolve_playout()
		m.begin_round()
		check(not m.sides[0].is_unlocked("radar"), "not yet after %d income rounds" % (i + 1))
	m.end_build_phase()
	m.resolve_playout()
	m.begin_round()
	check(m.sides[0].is_unlocked("radar"), "radar after 3 rounds of points")
	ok(m.build_action(0, {"action": "build", "type": "radar", "hex": hex(m, 5, 5)}))


func test_research_idle_lab_helps_oldest() -> void:
	var m = flat_match()
	var lab1 = put(m, 0, "lab", 1, 1)
	put(m, 0, "lab", 2, 1)
	var lab3 = put(m, 0, "lab", 3, 1)
	m.sides[0].money = 1000
	m.begin_round()
	ok(m.build_action(0, {"action": "research", "lab": lab1.id, "item": "motion_sensor"}))
	ok(m.build_action(0, {"action": "research", "lab": lab3.id, "item": "ballistic_launcher"}))
	err_contains(m.build_action(0, {"action": "research", "lab": lab1.id, "item": "radar"}), "already")
	err_contains(m.build_action(0, {"action": "research", "lab": lab3.id + 99, "item": "radar"}), "No such lab")
	m.end_build_phase()
	m.resolve_playout()
	m.begin_round()
	eq(m.sides[0].project_for_item("motion_sensor")["progress"], 4, "oldest gets own lab + idle lab")
	eq(m.sides[0].project_for_item("ballistic_launcher")["progress"], 2, "newer gets its own lab only")


func test_two_labs_twice_as_fast() -> void:
	var m = flat_match()
	var lab1 = put(m, 0, "lab", 1, 1)
	put(m, 0, "lab", 2, 1)
	m.begin_round()
	ok(m.build_action(0, {"action": "research", "lab": lab1.id, "item": "scouting_missile"}))
	m.end_build_phase()
	m.resolve_playout()
	m.begin_round()
	check(m.sides[0].is_unlocked("scouting_missile"), "4 points in one round with two labs")
	eq(m.sides[0].projects.size(), 0, "project cleared")


func test_research_survives_lab_loss_and_resumes_free() -> void:
	var m = flat_match()
	var lab1 = put(m, 0, "lab", 1, 1)
	m.begin_round()
	ok(m.build_action(0, {"action": "research", "lab": lab1.id, "item": "radar"}))
	m.end_build_phase()
	m.resolve_playout()
	m.begin_round()
	m.sides[0].remove_building(lab1.hex, m.data)
	eq(m.sides[0].project_for_item("radar")["lab_id"], -1, "orphaned")
	eq(m.sides[0].project_for_item("radar")["progress"], 2, "progress kept")
	var lab2 = put(m, 0, "lab", 4, 4)
	var money: int = m.sides[0].money
	ok(m.build_action(0, {"action": "research", "lab": lab2.id, "item": "radar"}))
	eq(m.sides[0].money, money, "resuming is free")


func test_launch_validation() -> void:
	var m = flat_match()
	var l = put(m, 0, "basic_launcher", 1, 1)
	var l2 = put(m, 0, "basic_launcher", 2, 1)
	put(m, 0, "anti_air", 3, 1)
	m.begin_round()
	m.end_build_phase()
	var t := hex(m, 7, 7)
	err_contains(m.set_launch_orders(0, [{"launcher": l.hex, "missile": "scouting", "target": t}]), "researched")
	err_contains(m.set_launch_orders(0, [{"launcher": l.hex, "missile": "ballistic", "target": t}]), "cannot fire")
	err_contains(m.set_launch_orders(0, [{"launcher": hex(m, 3, 1), "missile": "basic", "target": t}]), "No launcher")
	err_contains(m.set_launch_orders(0, [{"launcher": l.hex, "missile": "basic", "target": t},
		{"launcher": l2.hex, "missile": "basic", "target": t}]), "fuel")
	err_contains(m.set_launch_orders(0, [{"launcher": l.hex, "missile": "basic", "target": t},
		{"launcher": l.hex, "missile": "basic", "target": t}]), "already")
	ok(m.set_launch_orders(0, [{"launcher": l.hex, "missile": "basic", "target": t}]))
	ok(m.set_launch_orders(0, []), "undo is free")
	eq(m.sides[0].fuel, 3, "no fuel spent until playout")
	ok(m.set_launch_orders(0, [{"launcher": l.hex, "missile": "basic", "target": t}]))
	m.resolve_playout()
	eq(m.sides[0].fuel, 0, "fuel spent at playout")
