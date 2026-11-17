## Playout: interception, damage, disabling, hits on bases, seeking, fog,
## win/tie rules and determinism.
extends "res://tests/test_case.gd"


func _sure_data():
	# Deterministic anti-air for rule tests.
	var d = data()
	d.set_path("rules.anti_air.accuracy", 1.0)
	d.set_path("rules.anti_air.accuracy_with_radar", 1.0)
	return d


func _shot(launcher, target: int, missile: String = "basic") -> Dictionary:
	return {"launcher": launcher.hex, "missile": missile, "target": target}


func test_basic_missile_damage_and_disable() -> void:
	var m = flat_match()
	var l = put(m, 0, "basic_launcher", 1, 1)
	var aa = put(m, 1, "anti_air", 7, 7)   # out of its own radius? no: it is the target.
	m.data.set_path("rules.anti_air.accuracy", 0.0)
	var ev := play_round(m, [_shot(l, aa.hex)])
	var imp := events_of(ev, "impact")
	eq(imp.size(), 1, "one impact")
	var dmg: int = imp[0]["damaged"][0]["damage"]
	check(dmg >= 30 and dmg <= 50, "basic damage in 30..50, got %d" % dmg)
	eq(aa.hp, 50 - dmg, "hp reduced")
	check(aa.disabled, "a hit that does not destroy a weapon disables it")


func test_radar_dies_to_one_basic_hit() -> void:
	var m = flat_match()
	var l = put(m, 0, "basic_launcher", 1, 1)
	var r = put(m, 1, "radar", 7, 7)
	play_round(m, [_shot(l, r.hex)])
	check(m.sides[1].building_at(r.hex) == null, "radar destroyed")


func test_damage_applied_at_end_destroyed_still_fires() -> void:
	var m = flat_match()
	var l0 = put(m, 0, "basic_launcher", 1, 1)
	var l1 = put(m, 1, "basic_launcher", 1, 1)
	l0.hp = 1
	l1.hp = 1
	var ev := play_round(m, [_shot(l0, l1.hex)], [_shot(l1, l0.hex)])
	eq(events_of(ev, "impact").size(), 2, "both launchers fired")
	check(m.sides[0].building_at(l0.hex) == null and m.sides[1].building_at(l1.hex) == null, "both destroyed")


func test_destroyed_anti_air_still_engages_that_round() -> void:
	var m = flat_match(_sure_data())
	var l0 = put(m, 0, "basic_launcher", 1, 1)
	var l1 = put(m, 1, "basic_launcher", 1, 1)
	var aa = put(m, 0, "anti_air", 8, 8)
	aa.hp = 1
	var target_near_aa := hex(m, 9, 8)
	m.sides[1].fuel = 6
	put(m, 1, "basic_launcher", 2, 1)
	var l1b = m.sides[1].building_at(hex(m, 2, 1))
	var ev := play_round(m, [], [_shot(l1, aa.hex), _shot(l1b, target_near_aa)])
	eq(events_of(ev, "engage").size(), 2, "aa engages both (2 engagements)")
	eq(events_of(ev, "impact").size(), 0, "both intercepted at 100%")
	check(l0 != null)


func test_anti_air_radius_and_capacity() -> void:
	var m = flat_match(_sure_data())
	var aa = put(m, 1, "anti_air", 7, 7)
	var launchers: Array = []
	for c in 4:
		launchers.append(put(m, 0, "basic_launcher", c, 0))
	m.sides[0].fuel = 12
	var g = m.sides[1].island.grid
	var near: Array = []
	for h in g.within(aa.hex, 3):
		if h != aa.hex:
			near.append(h)
	var far := hex(m, 0, 14)
	check(g.distance(far, aa.hex) > 3, "far target outside radius")
	var ev := play_round(m, [_shot(launchers[0], near[0]), _shot(launchers[1], near[1]),
		_shot(launchers[2], near[2]), _shot(launchers[3], far)])
	eq(events_of(ev, "engage").size(), 2, "2 engagements per anti-air")
	var impacts := events_of(ev, "impact")
	eq(impacts.size(), 2, "one inside-radius missile and the far one land")
	check(impacts.any(func(e): return e["hex"] == far), "missile outside radius never engaged")


func test_anti_air_capacity_upgrade() -> void:
	var m = flat_match(_sure_data())
	put(m, 1, "anti_air", 7, 7)
	m.sides[1].unlocked["anti_air_capacity"] = true
	var launchers: Array = []
	for c in 3:
		launchers.append(put(m, 0, "basic_launcher", c, 0))
	m.sides[0].fuel = 9
	var t := hex(m, 7, 6)
	var ev := play_round(m, [_shot(launchers[0], t), _shot(launchers[1], t), _shot(launchers[2], t)])
	eq(events_of(ev, "engage").size(), 3, "3 engagements with upgrade")


func test_no_missile_engaged_twice() -> void:
	var d = data()
	d.set_path("rules.anti_air.accuracy", 0.0)
	var m = flat_match(d)
	put(m, 1, "anti_air", 7, 7)
	put(m, 1, "anti_air", 8, 7)
	put(m, 1, "anti_air", 6, 7)
	var l = put(m, 0, "basic_launcher", 0, 0)
	var ev := play_round(m, [_shot(l, hex(m, 7, 8))])
	eq(events_of(ev, "engage").size(), 1, "single engagement even with three anti-air")


func test_radar_covered_anti_air_engages_first() -> void:
	var d = data()
	d.set_path("rules.anti_air.accuracy", 0.0)
	d.set_path("rules.anti_air.accuracy_with_radar", 1.0)
	var m = flat_match(d)
	put(m, 1, "anti_air", 6, 7)          # id lower, not covered
	var covered = put(m, 1, "anti_air", 10, 7)
	put(m, 1, "radar", 11, 7)            # range 2 at base level
	var l = put(m, 0, "basic_launcher", 0, 0)
	var ev := play_round(m, [_shot(l, hex(m, 8, 7))])
	var eng := events_of(ev, "engage")
	eq(eng.size(), 1, "one engagement")
	eq(eng[0]["anti_air"], covered.hex, "covered anti-air chosen first")
	check(eng[0]["hit"], "90%% path used (set to 100%% here)")


func test_ballistic_blast_seven_hexes_same_level() -> void:
	var m = flat_match()
	var bl = put(m, 0, "ballistic_launcher", 0, 0)
	m.sides[0].fuel = 5
	var center := hex(m, 7, 7)
	var g = m.sides[1].island.grid
	var ring: Array = Array(g.neighbors(center))
	var targets: Array = [put(m, 1, "bank", 7, 7)]
	for h in ring:
		targets.append(m.sides[1]._add_building("bank", h, m.data, 0))
	# One neighbour is on a hill: the blast must not reach it.
	var uphill: int = ring[0]
	m.sides[1].island.level[uphill] = 1
	var outside := hex(m, 7, 10)
	var far_bank = m.sides[1]._add_building("bank", outside, m.data, 0)
	play_round(m, [_shot(bl, center, "ballistic")])
	var hit := 0
	for b in targets:
		var dmg: int = 40 - b.hp
		if b.hex == uphill:
			eq(dmg, 0, "no damage across a height step")
		else:
			check(dmg >= 15 and dmg <= 25, "ballistic damage per hex in 15..25, got %d" % dmg)
			hit += 1
	eq(hit, 6, "six same-level hexes hit")
	eq(far_bank.hp, 40, "outside blast untouched")


func test_base_hits_and_decoy_reveal() -> void:
	var m = flat_match()
	var base = put(m, 1, "base", 7, 7)
	var decoy = put(m, 1, "decoy", 3, 3)
	var l = put(m, 0, "basic_launcher", 0, 0)
	var l2 = put(m, 0, "basic_launcher", 1, 0)
	var bl = put(m, 0, "ballistic_launcher", 2, 0)
	for r in 2:
		m.sides[0].fuel = 6
		play_round(m, [_shot(l, base.hex), _shot(l2, decoy.hex)])
	eq(base.hits, 2.0, "two basic hits")
	eq(m.knowledge[0][base.hex]["building"]["type"], "suspected_base", "still looks like a base")
	eq(m.knowledge[0][base.hex]["building"]["hits"], 2.0, "hits shown")
	m.sides[0].fuel = 8
	var ev := play_round(m, [_shot(bl, base.hex, "ballistic"), _shot(l2, decoy.hex)])
	eq(base.hits, 2.5, "ballistic counts half a hit")
	eq(events_of(ev, "decoy_revealed").size(), 1, "decoy gives itself away on the third hit")
	eq(m.knowledge[0][decoy.hex]["building"]["type"], "decoy", "attacker now sees a decoy")
	m.sides[0].fuel = 6
	ev = play_round(m, [_shot(l, base.hex), _shot(l2, decoy.hex)])
	check(m.sides[1].building_at(base.hex) == null, "base destroyed at 3 hits")
	check(m.sides[1].building_at(decoy.hex) == null, "decoy destroyed at 4 hits")
	eq(m.knowledge[0][base.hex]["destroyed"], "base", "attacker sees destroyed base")
	eq(m.view_for(0).enemy_bases_destroyed.size(), 1, "view counts destroyed bases")


func test_scouting_reveals_without_damage() -> void:
	var m = flat_match()
	var l = put(m, 0, "basic_launcher", 0, 0)
	m.sides[0].unlocked["scouting_missile"] = true
	var aa = put(m, 1, "anti_air", 7, 8)
	var ev := play_round(m, [_shot(l, hex(m, 7, 7), "scouting")])
	eq(events_of(ev, "impact").size(), 0 if events_of(ev, "engage").any(func(e): return e["hit"]) else 1, "impact unless shot down")
	if events_of(ev, "impact").size() == 1:
		eq(m.knowledge[0].size(), 19, "view radius 2 = 19 hexes")
		check(not aa.disabled and aa.hp == 50, "no damage")
	eq(m.sides[0].fuel, 2, "scouting costs 1 fuel")


func test_fog_reveal_rules_and_staleness() -> void:
	var m = flat_match()
	var l = put(m, 0, "basic_launcher", 0, 0)
	var isl = m.sides[1].island
	var center := hex(m, 7, 7)
	var g = isl.grid
	var uphill: int = g.neighbors(center)[0]
	isl.level[uphill] = 2
	play_round(m, [_shot(l, center)])
	var k: Dictionary = m.knowledge[0]
	eq(k.size(), 6, "impact reveals its level and lower, not the hill hex")
	check(not k.has(uphill), "uphill hex stays fogged")
	# A building that appears later does not show until revealed again.
	var nb: int = g.neighbors(center)[1]
	m.sides[1]._add_building("bank", nb, m.data, 1)
	eq(m.view_for(0).seen(nb)["building"], null, "stale view")
	check(not m.view_for(0).enemy_knowledge.has(hex(m, 0, 14)), "unrevealed hexes unknown")


func test_side_view_hides_opponent() -> void:
	var m = flat_match()
	put(m, 1, "base", 7, 7)
	var v = m.view_for(0)
	eq(v.enemy_knowledge.size(), 0, "nothing known at start")
	check(not ("sides" in v), "view has no access to match sides")
	v.own.money = 99999
	check(m.sides[0].money != 99999, "view holds a copy")


func test_motion_sensor_seeks_on_same_level() -> void:
	var m = flat_match()
	m.sides[0].unlocked["motion_sensor"] = true
	var l = put(m, 0, "basic_launcher", 0, 0)
	var bank = put(m, 1, "bank", 7, 9)   # two rows down from target
	var t := hex(m, 7, 7)
	var ev := play_round(m, [_shot(l, t)])
	eq(events_of(ev, "seek").size(), 1, "seeks")
	check(bank.hp < 40, "moved onto the bank")

	var m2 = flat_match()
	m2.sides[0].unlocked["motion_sensor"] = true
	var l2 = put(m2, 0, "basic_launcher", 0, 0)
	var bank2 = put(m2, 1, "bank", 7, 9)
	m2.sides[1].island.level[bank2.hex] = 1
	ev = play_round(m2, [_shot(l2, hex(m2, 7, 7))])
	eq(events_of(ev, "seek").size(), 0, "cannot change level while seeking")
	eq(bank2.hp, 40, "uphill bank untouched")

	var m3 = flat_match()
	var l3 = put(m3, 0, "basic_launcher", 0, 0)
	var bank3 = put(m3, 1, "bank", 7, 9)
	ev = play_round(m3, [_shot(l3, hex(m3, 7, 7))])
	eq(events_of(ev, "seek").size(), 0, "no seeking without the research")
	eq(bank3.hp, 40, "dumb missile lands where aimed")


func test_hit_cancels_repair() -> void:
	var m = flat_match()
	var aa = put(m, 1, "anti_air", 7, 7)
	aa.hp = 10
	aa.disabled = true
	var l = put(m, 0, "basic_launcher", 0, 0)
	m.begin_round()
	ok(m.build_action(1, {"action": "repair", "hex": aa.hex}))
	m.end_build_phase()
	ok(m.set_launch_orders(0, [_shot(l, aa.hex)]))
	m.resolve_playout()
	if m.sides[1].building_at(aa.hex) != null:
		m.begin_round()
		check(aa.disabled, "weapon hit during repair stays disabled")


func test_win_by_bases() -> void:
	var m = flat_match(null, 1, false)
	var base = put(m, 1, "base", 7, 7)
	base.hits = 2.0
	put(m, 0, "base", 7, 7)
	var l = put(m, 0, "basic_launcher", 0, 0)
	play_round(m, [_shot(l, base.hex)])
	check(m.is_over(), "game over")
	eq(m.winner, 0, "player wins")


func test_tie_goes_to_money_then_coin() -> void:
	var m = flat_match(null, 1, false)
	var b0 = put(m, 0, "base", 7, 7)
	var b1 = put(m, 1, "base", 7, 7)
	b0.hits = 2.0
	b1.hits = 2.0
	var l0 = put(m, 0, "basic_launcher", 0, 0)
	var l1 = put(m, 1, "basic_launcher", 0, 0)
	m.sides[1].money = 500
	play_round(m, [_shot(l0, b1.hex)], [_shot(l1, b0.hex)])
	eq(m.winner, 1, "richer side wins a double knockout")
	eq(m.end_reason, "money", "reason")

	var m2 = flat_match(null, 1, false)
	var c0 = put(m2, 0, "base", 7, 7)
	var c1 = put(m2, 1, "base", 7, 7)
	c0.hits = 2.0
	c1.hits = 2.0
	var k0 = put(m2, 0, "basic_launcher", 0, 0)
	var k1 = put(m2, 1, "basic_launcher", 0, 0)
	play_round(m2, [_shot(k0, c1.hex)], [_shot(k1, c0.hex)])
	eq(m2.phase, MatchState.Phase.COIN_FLIP, "equal money needs a coin flip")
	check(m2.coin["call"] in ["heads", "tails"], "enemy has called before the flip")
	var ev: Array = m2.resolve_coin_flip()
	check(m2.is_over(), "flip ends it")
	var flip: Dictionary = ev[0]
	eq(m2.winner, 1 if flip["call"] == flip["flip"] else 0, "enemy wins on a correct call")


## Same seed and same orders give the same result; the island and dice differ by seed.
func test_determinism_scripted_match() -> void:
	var a := _scripted(2024)
	var b := _scripted(2024)
	var c := _scripted(2025)
	eq(a, b, "same seed, same orders")
	check(a != c, "different seed differs")


func _scripted(seed_in: int) -> String:
	var m = MatchState.create(data(), seed_in)
	for s in 2:
		var land: PackedInt32Array = m.sides[s].island.land_hexes()
		ok(m.setup_side(s, [land[0], land[40], land[100]], [land[150]]), "setup")
	for r in 6:
		m.begin_round()
		for s in 2:
			var land: PackedInt32Array = m.sides[s].island.land_hexes()
			m.build_action(s, {"action": "build", "type": "basic_launcher", "hex": land[10 + r]})
			m.build_action(s, {"action": "build", "type": "anti_air", "hex": land[20 + r]})
		m.end_build_phase()
		for s in 2:
			var orders: Array = []
			var fuel: int = m.sides[s].fuel
			for b in m.sides[s].of_role(m.data, "launcher"):
				if fuel >= 3 and m.sides[s].weapon_active(b):
					orders.append({"launcher": b.hex, "missile": "basic", "target": 30 + r * 7 + orders.size() * 13})
					fuel -= 3
			ok(m.set_launch_orders(s, orders), "orders")
		m.resolve_playout()
	return m.fingerprint()
