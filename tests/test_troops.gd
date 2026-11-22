## Troops (spec section 10): air transports, platoons and bunkers.
extends "res://tests/test_case.gd"

const StrongAI = preload("res://ai/strong_ai.gd")

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
	eq(m.sides[0].money, before - int(m.data.missile("transport")["replace_money"]), "costs the replacement")
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


# --- Boats -----------------------------------------------------------------

func _docks(m, side: int = 0):
	m.sides[side].unlocked["docks"] = true
	m.sides[side].fuel = 30
	m.sides[side].money = 500
	return put(m, side, "docks", 0, 1)   # column 0: the edge of the space is coast


func _sail(dk, target: int, dir: int = EAST) -> Dictionary:
	return {"launcher": dk.hex, "missile": "boat", "target": target, "dir": dir}


func test_docks_and_cannons_need_the_coast() -> void:
	var m = flat_match()
	var st = m.sides[0]
	st.unlocked["docks"] = true
	st.unlocked["coastal_cannon"] = true
	st.money = 500
	err_contains(st.can_build("docks", hex(m, 6, 6), m.data, m.settings), "coast", "inland refused")
	ok(st.can_build("docks", hex(m, 0, 6), m.data, m.settings), "edge of the space is coast")
	m.sides[0].island.land[hex(m, 6, 7)] = 0
	ok(st.can_build("coastal_cannon", hex(m, 6, 6), m.data, m.settings), "next to the sea")


func test_boat_lands_in_the_round_it_sails() -> void:
	var m = flat_match()
	var dk = _docks(m)
	var bank = put(m, 1, "bank", 0, 9)
	var ev := play_round(m, [_sail(dk, hex(m, 0, 9))])
	eq(events_of(ev, "boat_launch").size(), 1, "boat puts to sea")
	eq(events_of(ev, "boat_arrive").size(), 1, "and comes ashore in the same playout")
	eq(events_of(ev, "platoon").size(), 1, "the platoon lands")
	check(m.sides[1].building_at(bank.hex) == null, "and overruns the bank")
	check(not dk.boat_out, "the boat is back")
	eq(m.boats[0].size(), 0, "nothing left at sea")
	eq(m.view_for(1).enemy_boats_arrived, 1, "the defender saw it arrive")
	m.begin_round()
	m.end_build_phase()
	ok(m.set_launch_orders(0, [_sail(dk, hex(m, 0, 9))]), "the docks can send it again next round")


func test_boat_lands_before_the_missiles() -> void:
	var m = flat_match()
	var dk = _docks(m)
	var ev := play_round(m, [_sail(dk, hex(m, 0, 9))])
	var types: Array = ev.map(func(e): return e["type"])
	check(types.find("boat_arrive") < types.find("platoon"), "arrival, then the landing")


func test_coastal_cannon_sinks_a_boat() -> void:
	var m = flat_match()
	m.data.set_path("rules.troops.cannon_accuracy", 1.0)
	var dk = _docks(m)
	var cannon = put(m, 1, "coastal_cannon", 0, 7)
	var ev := play_round(m, [_sail(dk, hex(m, 0, 9))])
	var shots: Array = events_of(ev, "cannon_fire")
	eq(shots.size(), 1, "the cannon fires")
	eq(int(shots[0]["cannon"]), cannon.hex, "from its own hex")
	eq(int(shots[0]["side"]), 1, "for the defender")
	eq(events_of(ev, "boat_sunk").size(), 1, "sunk")
	eq(events_of(ev, "platoon").size(), 0, "no landing")
	check(dk.carrier_lost and not dk.boat_out, "docks need a new boat")
	m.begin_round()
	var before: int = m.sides[0].money
	ok(m.build_action(0, {"action": "replace_carrier", "hex": dk.hex}))
	eq(m.sides[0].money, before - int(m.data.missile("boat")["replace_money"]), "boat replacement cost")


func test_coastal_cannon_that_misses_lets_the_boat_land() -> void:
	var m = flat_match()
	m.data.set_path("rules.troops.cannon_accuracy", 0.0)
	var dk = _docks(m)
	put(m, 1, "coastal_cannon", 0, 7)
	var ev := play_round(m, [_sail(dk, hex(m, 0, 9))])
	eq(events_of(ev, "cannon_fire").size(), 1, "it still fires")
	check(not bool(events_of(ev, "cannon_fire")[0]["hit"]), "and misses")
	eq(events_of(ev, "platoon").size(), 1, "the platoon lands")


func test_every_cannon_in_range_fires_and_none_beyond() -> void:
	var m = flat_match()
	m.data.set_path("rules.troops.cannon_accuracy", 0.0)
	var dk = _docks(m)
	var reach := int(m.data.section("troops")["cannon_range"])
	put(m, 1, "coastal_cannon", 0, 9 - reach)
	put(m, 1, "coastal_cannon", 0, 10)
	put(m, 1, "coastal_cannon", 0, 9 + reach + 1)
	var ev := play_round(m, [_sail(dk, hex(m, 0, 9))])
	eq(events_of(ev, "cannon_fire").size(), 2, "the two within %d hexes fire" % reach)


func test_strong_ai_researches_cannons_once_a_boat_has_landed() -> void:
	var m = flat_match()
	var dk = _docks(m)
	m.sides[1].money = 500
	put(m, 1, "lab", 9, 9)
	var ai = StrongAI.new(1, m.data, 3)
	m.begin_round()
	var before: Array = ai.choose_build(m.view_for(1)).filter(func(a): return a["action"] == "research")
	check(before.is_empty() or before[0]["item"] != "coastal_cannon", "no cannon research before any boat")
	var m2 = flat_match()
	var dk2 = _docks(m2)
	m2.sides[1].money = 500
	put(m2, 1, "lab", 9, 9)
	play_round(m2, [_sail(dk2, hex(m2, 0, 9))])
	m2.begin_round()
	var after: Array = StrongAI.new(1, m2.data, 3).choose_build(m2.view_for(1)).filter(func(a): return a["action"] == "research")
	eq(after.size(), 1, "one lab, one project")
	eq(String(after[0]["item"]), "coastal_cannon", "cannons first once a boat has come ashore")


func test_boat_aimed_inland_cannot_land() -> void:
	var m = flat_match()
	var dk = _docks(m)
	var ev := play_round(m, [_sail(dk, hex(m, 6, 6))])
	eq(events_of(ev, "boat_no_landing").size(), 1, "nowhere to land")
	eq(events_of(ev, "platoon").size(), 0, "no platoon")
	check(not dk.boat_out and not dk.carrier_lost, "the boat comes home")
