## Levels (data/levels.json) and the level 2 stronghold: a base that
## missiles can't destroy, with its own anti-air gun.
extends "res://tests/test_case.gd"

const Levels = preload("res://rules/levels.gd")
const Campaign = preload("res://game/campaign.gd")
const StrongAI = preload("res://ai/strong_ai.gd")
const MatchRunner = preload("res://ai/match_runner.gd")

const EAST := 0


func _launcher(m, side: int = 0):
	m.sides[side].fuel = 50
	m.sides[side].money = 500
	return put(m, side, "basic_launcher", 0, 0)


func _missile(launcher, target: int) -> Dictionary:
	return {"launcher": launcher.hex, "missile": "basic", "target": target}


## A flat match where side 1 also has a stronghold at (8, 8).
func _fort_match():
	var m = flat_match(Levels.data_for(data(), 2))
	return [m, put(m, 1, "stronghold", 8, 8)]


func test_level_2_has_one_stronghold_per_side() -> void:
	eq(int(Levels.data_for(data(), 1).rules["bases"]["strongholds_per_side"]), 0, "level 1: none")
	eq(int(Levels.data_for(data(), 2).rules["bases"]["strongholds_per_side"]), 1, "level 2: one")
	eq(int(data().rules["bases"]["strongholds_per_side"]), 0, "the base data is untouched")


func test_setup_makes_the_first_base_a_stronghold() -> void:
	var m = MatchState.create(Levels.data_for(data(), 2), 3)
	var land: Array = Array(m.sides[0].island.land_hexes())
	var picks: Array = []
	for h in land:
		if picks.all(func(p): return m.sides[0].island.grid.distance(p, h) >= 3):
			picks.append(h)
		if picks.size() == 3:
			break
	ok(m.setup_side(0, picks, []), "setup")
	eq(m.sides[0].building_at(picks[0]).type, "stronghold", "first is the stronghold")
	eq(m.sides[0].building_at(picks[1]).type, "base", "the rest are bases")
	eq(m.sides[0].bases_alive(m.data), 3, "the stronghold counts as a base")


func test_missile_knocks_out_the_gun_but_cannot_destroy_it() -> void:
	var r = _fort_match()
	var m = r[0]
	var fort = r[1]
	var lau = _launcher(m)
	for k in 3:
		m.sides[0].fuel = 50
		var ev := play_round(m, [_missile(lau, fort.hex)])
		if k == 0:
			eq(events_of(ev, "stronghold_revealed").size(), 1, "the first hit gives it away")
			eq(String(m.knowledge[0][fort.hex]["building"]["type"]), "stronghold", "seen as a stronghold")
		elif events_of(ev, "engage").size() == 0:
			eq(events_of(ev, "stronghold_revealed").size(), 0, "revealed only once")
	check(m.sides[1].building_at(fort.hex) != null, "still standing after missile hits")
	check(m.sides[1].building_at(fort.hex).disabled, "its gun is out of action")
	check(not m.is_over(), "no result while it stands")


func test_unhit_stronghold_looks_like_any_base() -> void:
	var r = _fort_match()
	var m = r[0]
	var fort = r[1]
	m.record_sighting(0, fort.hex)
	eq(String(m.knowledge[0][fort.hex]["building"]["type"]), "suspected_base", "seen but never hit: a potential base")


func test_troops_take_a_stronghold() -> void:
	var r = _fort_match()
	var m = r[0]
	var fort = r[1]
	fort.disabled = true   # gun down, so the transport isn't shot at
	m.sides[0].unlocked["airport"] = true
	m.sides[0].fuel = 30
	m.sides[0].money = 500
	var port = put(m, 0, "airport", 0, 0)
	play_round(m, [{"launcher": port.hex, "missile": "transport", "target": fort.hex, "dir": EAST}])
	check(m.sides[1].building_at(fort.hex) == null, "the platoon destroys it")
	check(m.view_for(0).enemy_bases_destroyed.has(fort.hex), "counted as a base destroyed")


func test_stronghold_gun_shoots_at_missiles() -> void:
	var r = _fort_match()
	var m = r[0]
	var fort = r[1]
	var lau = _launcher(m)
	var bank = put(m, 1, "bank", 9, 8)
	var ev := play_round(m, [_missile(lau, bank.hex)])
	var eng: Array = events_of(ev, "engage")
	eq(eng.size(), 1, "the missile is engaged")
	eq(int(eng[0]["anti_air"]), fort.hex, "by the stronghold's gun")


func test_stronghold_gun_can_be_repaired() -> void:
	var r = _fort_match()
	var m = r[0]
	var fort = r[1]
	var st = m.sides[1]
	check(not st.needs_repair(fort, m.data), "nothing to repair while the gun works")
	fort.disabled = true
	st.money = 100
	check(st.needs_repair(fort, m.data), "a knocked-out gun needs repair")
	eq(st.repair_cost("stronghold", m.data), int(m.data.building("stronghold")["repair_cost"]), "its own repair cost")
	ok(st.repair(fort.hex, m.data), "repair")
	check(not st.weapon_active(fort), "out for the round of the repair")
	m.begin_round()
	check(st.weapon_active(fort), "back the round after")


func test_plain_bases_still_cannot_be_repaired() -> void:
	var m = flat_match()
	var b = m.sides[0].building_at(hex(m, 14, 14))
	b.hits = 1.0
	err_contains(m.sides[0].can_repair(b.hex, m.data), "cannot be repaired")


func test_campaign_advance_carries_the_award() -> void:
	Campaign.restart()
	eq(Campaign.level, 1, "starts at level 1")
	check(Campaign.has_next(), "a level 2 to go to")
	Campaign.advance()
	eq(Campaign.level, 2, "on to level 2")
	eq(Campaign.award_money, int(Levels.level(1)["win_award_money"]), "level 1's award carried")
	Campaign.restart()


func test_strong_ai_goes_for_troops_in_level_2() -> void:
	var d = Levels.data_for(data(), 2)
	var ai = StrongAI.new(1, d, 5)
	eq(ai.research[0], "airport", "airport research first")
	var order: Array = ai._build_order()
	var lab := order.find("lab")
	eq(order[lab + 1], "airport", "the airport right after the lab")


func test_level_2_ai_matches_finish_legally() -> void:
	var d = Levels.data_for(data(), 2)
	var wins := 0
	for s in 4:
		var r: Dictionary = MatchRunner.play(d, 300 + s, [StrongAI.new(0, d, 300 + s), StrongAI.new(1, d, 300 + s)], 80)
		eq(r["errors"], [], "no rejected actions, seed %d" % (300 + s))
		check(not r["timed_out"], "seed %d reaches a result" % (300 + s))


func test_strong_ai_opening_search_varies() -> void:
	var firsts := {}
	for s in 8:
		var m = MatchState.create(data(), 700 + s)
		var ai = StrongAI.new(1, data(), 700 + s)
		for side in 2:
			var setup_ai = ai if side == 1 else StrongAI.new(0, data(), 700 + s)
			var es: Dictionary = setup_ai.choose_setup(m.view_for(side))
			ok(m.setup_side(side, es["bases"], es["decoys"]))
		m.begin_round()
		for a in ai.choose_build(m.view_for(1)):
			m.build_action(1, a)
		m.end_build_phase()
		for o in ai.choose_targets(m.view_for(1)):
			firsts[int(o["target"])] = true
	check(firsts.size() >= 4, "opening shots spread over several hexes (%d)" % firsts.size())
