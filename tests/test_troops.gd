## Troops (spec section 10): air transports, platoons and bunkers.
extends "res://tests/test_case.gd"

const EAST := 0   # HexGrid.AXIAL_DIRS[0]: one hex to the right along a row


func _airport(m, side: int = 0):
	m.sides[side].unlocked["airport"] = true
	m.sides[side].fuel = 30
	m.sides[side].money = 500
	return put(m, side, "airport", 0, 0)


func _drop(port, target: int, dir: int = EAST) -> Dictionary:
	return {"launcher": port.hex, "missile": "transport", "target": target, "dir": dir}


func test_platoon_marches_three_hexes_destroying_everything() -> void:
	var m = flat_match()
	var port = _airport(m)
	var bank = put(m, 1, "bank", 5, 5)
	var lab = put(m, 1, "lab", 7, 5)
	var far = put(m, 1, "refinery", 8, 5)
	var ev := play_round(m, [_drop(port, hex(m, 5, 5))])
	var p: Array = events_of(ev, "platoon")
	eq(p.size(), 1, "one platoon")
	eq(p[0]["path"], [hex(m, 5, 5), hex(m, 6, 5), hex(m, 7, 5)], "lands and marches two hexes east")
	check(m.sides[1].building_at(bank.hex) == null, "bank on the landing hex destroyed")
	check(m.sides[1].building_at(lab.hex) == null, "lab on the march destroyed")
	check(m.sides[1].building_at(far.hex) != null, "fourth hex untouched")
	check(m.knowledge[0].has(hex(m, 7, 5)), "march revealed to the attacker")


func test_platoon_kills_a_base_outright() -> void:
	var m = flat_match()
	var port = _airport(m)
	var base_hex := hex(m, 14, 14)
	check(m.sides[1].building_at(base_hex) != null, "a base there")
	play_round(m, [_drop(port, base_hex)])
	check(m.sides[1].building_at(base_hex) == null, "one landing destroys the base")
	eq(m.view_for(0).enemy_bases_destroyed.size(), 1, "counts as a base destroyed")


func test_platoon_jumps_down_but_cannot_climb() -> void:
	var m = flat_match()
	var port = _airport(m)
	var isl = m.sides[1].island
	isl.level[hex(m, 3, 3)] = 1
	isl.level[hex(m, 4, 3)] = 0   # step down: fine
	isl.level[hex(m, 5, 3)] = 1   # step up: stops
	var ev := play_round(m, [_drop(port, hex(m, 3, 3))])
	eq(events_of(ev, "platoon")[0]["path"], [hex(m, 3, 3), hex(m, 4, 3)], "down one, then blocked by the climb")


func test_sea_loses_or_stops_a_platoon() -> void:
	var m = flat_match()
	var port = _airport(m)
	var isl = m.sides[1].island
	isl.land[hex(m, 2, 7)] = 0
	isl.land[hex(m, 5, 7)] = 0
	var ev := play_round(m, [_drop(port, hex(m, 2, 7))])
	check(events_of(ev, "platoon")[0]["lost_at_sea"], "landing in the sea loses it")
	m.sides[0].fuel = 30
	ev = play_round(m, [_drop(port, hex(m, 3, 7))])
	eq(events_of(ev, "platoon")[0]["path"], [hex(m, 3, 7), hex(m, 4, 7)], "the sea ends the march")


func test_bunker_wipes_out_a_platoon_in_range() -> void:
	var m = flat_match()
	var port = _airport(m)
	var bank = put(m, 1, "bank", 5, 9)
	var lab = put(m, 1, "lab", 6, 9)
	var bunker = put(m, 1, "bunker", 8, 9)   # 2 hexes from (6, 9)
	var ev := play_round(m, [_drop(port, hex(m, 5, 9))])
	var p: Dictionary = events_of(ev, "platoon")[0]
	eq(p["stopped_by"], bunker.hex, "the bunker stops it")
	check(m.sides[1].building_at(bank.hex) == null, "destroyed before coming in range")
	check(m.sides[1].building_at(lab.hex) != null, "nothing destroyed on the hex where it is wiped out")
	check(m.knowledge[0].has(bunker.hex), "the bunker that stopped it is revealed")


func test_transport_shot_down_must_be_replaced() -> void:
	var m = flat_match()
	var port = _airport(m)
	var d = m.data
	d.set_path("rules.anti_air.accuracy", 1.0)
	put(m, 1, "anti_air", 6, 6)
	var ev := play_round(m, [_drop(port, hex(m, 6, 6))])
	eq(events_of(ev, "carrier_lost").size(), 1, "transport shot down")
	eq(events_of(ev, "platoon").size(), 0, "no platoon lands")
	check(port.carrier_lost, "airport has lost its transport")
	m.begin_round()
	m.end_build_phase()
	err_contains(m.set_launch_orders(0, [_drop(port, hex(m, 2, 2))]), "Transport lost", "can't launch without one")


func test_replacing_a_transport_costs_money() -> void:
	var m = flat_match()
	var port = _airport(m)
	port.carrier_lost = true
	m.begin_round()
	var before: int = m.sides[0].money
	ok(m.build_action(0, {"action": "replace_carrier", "hex": port.hex}), "replace")
	eq(m.sides[0].money, before - int(m.data.section("troops")["transport_replace_cost"]), "costs the replacement")
	check(not port.carrier_lost, "airport ready again")


func test_launch_costs_fuel_and_money_and_needs_a_direction() -> void:
	var m = flat_match()
	var port = _airport(m)
	m.begin_round()
	m.end_build_phase()
	var bad := _drop(port, hex(m, 5, 5))
	bad.erase("dir")
	err_contains(m.set_launch_orders(0, [bad]), "direction", "needs a march direction")
	m.sides[0].money = 10
	err_contains(m.set_launch_orders(0, [_drop(port, hex(m, 5, 5))]), "money", "needs the launch money")
	m.sides[0].money = 500
	var fuel_before: int = m.sides[0].fuel
	ok(m.set_launch_orders(0, [_drop(port, hex(m, 5, 5))]))
	ok(m.set_launch_orders(1, []))
	m.resolve_playout()
	var t: Dictionary = m.data.missile("transport")
	eq(m.sides[0].fuel, fuel_before - int(t["fuel"]), "fuel paid")
	eq(m.sides[0].money, 500 - int(t["money"]), "money paid")
