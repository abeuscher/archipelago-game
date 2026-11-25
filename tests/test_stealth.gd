## Level 5: the stealth launcher (missiles anti-air can't hit, half strength,
## deadly to a domestic agent on the hex) and logistics (anti-air and radar
## reach one hex farther).
extends "res://tests/test_case.gd"

const Levels = preload("res://rules/levels.gd")
const StrongAI = preload("res://ai/strong_ai.gd")
const MatchRunner = preload("res://ai/match_runner.gd")


func _l5():
	return Levels.data_for(data(), 5)


func _stealth_match():
	var m = flat_match(_l5())
	var st = m.sides[0]
	st.fuel = 40
	st.money = 500
	var silo = put(m, 0, "stealth_launcher", 0, 0)
	return [m, silo]


func _shot(silo, target: int) -> Dictionary:
	return {"launcher": silo.hex, "missile": "stealth", "target": target}


func test_level_5_brings_the_stealth_launcher_and_logistics_and_keeps_level_4() -> void:
	for n in [1, 2, 3, 4, 5]:
		var d = Levels.data_for(data(), n)
		var st = MatchState.create(d, 3).sides[0]
		eq(st.building_unlocked("stealth_launcher", d), n == 5, "stealth launcher in level %d: %s" % [n, n == 5])
		eq(st.research_available(d).has("logistics"), n == 5, "logistics in level %d: %s" % [n, n == 5])
	var m = MatchState.create(_l5(), 3)
	for side in 2:
		var st = m.sides[side]
		check(st.is_unlocked("nuclear_silo") and st.is_unlocked("bank_upgrade") and st.is_unlocked("refinery_upgrade"), "side %d keeps level 4's research" % side)
		check(st.building_unlocked("enclave", m.data), "side %d keeps the enclave" % side)
		check(not st.is_unlocked("logistics"), "side %d: logistics still to research" % side)


func test_anti_air_never_engages_a_stealth_missile() -> void:
	var r = _stealth_match()
	var m = r[0]
	var launcher = put(m, 0, "basic_launcher", 2, 0)
	m.data.set_path("rules.anti_air.accuracy", 1.0)
	put(m, 1, "anti_air", 6, 6)
	var bank = put(m, 1, "bank", 6, 7)
	var ev := play_round(m, [_shot(r[1], bank.hex), {"launcher": launcher.hex, "missile": "basic", "target": hex(m, 7, 6)}])
	var engaged: Array = events_of(ev, "engage").map(func(e): return e["id"])
	var stealth_id = events_of(ev, "launch").filter(func(e): return e["missile"] == "stealth")[0]["id"]
	check(not engaged.has(stealth_id), "the stealth missile is never engaged")
	eq(engaged.size(), 1, "the basic missile still is")
	check(events_of(ev, "impact").any(func(e): return e["missile"] == "stealth" and int(e["hex"]) == bank.hex), "the stealth missile lands")


func test_a_stealth_missile_hits_half_as_hard() -> void:
	var d = _l5()
	var st: Dictionary = d.missile("stealth")
	var basic: Dictionary = d.missile("basic")
	eq(int(st["damage_min"]) * 2, int(basic["damage_min"]), "half the least damage")
	eq(int(st["damage_max"]) * 2, int(basic["damage_max"]), "half the most damage")
	eq(float(st["base_hits"]), float(basic["base_hits"]) / 2.0, "half a hit on a base")
	var r = _stealth_match()
	var m = r[0]
	var base = m.sides[1].of_role(m.data, "base")[0]
	play_round(m, [_shot(r[1], base.hex)])
	eq(float(base.hits), 0.5, "the base took half a hit")


func test_a_stealth_missile_kills_a_domestic_agent_on_its_hex_and_he_comes_back_later() -> void:
	var r = _stealth_match()
	var m = r[0]
	m.data.set_path("rules.agents.domestic_walks_min", 0)
	m.data.set_path("rules.agents.domestic_walks_max", 0)
	var their = put(m, 1, "enclave", 2, 12)
	var spot := hex(m, 7, 7)
	m.agents[1] = [{"id": "x", "enclave": their.id, "hex": spot, "home": their.hex, "home_by": 100}]
	var ev := play_round(m, [_shot(r[1], spot)])
	var k: Array = events_of(ev, "agent_killed")
	eq(k.size(), 1, "agent killed")
	eq(int(k[0]["side"]), 1, "told to his own side only")
	eq(int(k[0]["hex"]), spot, "where the missile hit")
	eq(m.agents[1].size(), 0, "he is gone")
	var wait := int(m.data.section("agents")["respawn_after_rounds"])
	for i in wait:
		play_round(m)
		eq(m.agents[1].size(), 0, "no new agent %d round(s) later" % (i + 1))
	play_round(m)
	eq(m.agents[1].size(), 1, "a new one musters after %d rounds" % wait)
	eq(int(m.agents[1][0]["hex"]), their.hex, "at the enclave")


func test_only_the_hex_hit_and_only_stealth_missiles_kill_agents() -> void:
	var r = _stealth_match()
	var m = r[0]
	var launcher = put(m, 0, "basic_launcher", 2, 0)
	m.data.set_path("rules.agents.domestic_walks_min", 0)
	m.data.set_path("rules.agents.domestic_walks_max", 0)
	var their = put(m, 1, "enclave", 2, 12)
	var a := hex(m, 7, 7)
	m.agents[1] = [{"id": "x", "enclave": their.id, "hex": a, "home": their.hex, "home_by": 100}]
	var ev := play_round(m, [_shot(r[1], hex(m, 8, 7)), {"launcher": launcher.hex, "missile": "basic", "target": a}])
	eq(events_of(ev, "agent_killed").size(), 0, "a basic missile on him, a stealth one next to him: he lives")
	eq(m.agents[1].size(), 1, "still there")


func test_logistics_extends_anti_air_and_radar_reach() -> void:
	var d = _l5()
	var m = flat_match(d)
	var st = m.sides[1]
	var radar = put(m, 1, "radar", 6, 6)
	var base_radar: int = st.radar_range(radar, d)
	eq(st.anti_air_radius(d), int(d.section("anti_air")["radius"]), "usual anti-air reach")
	st.unlocked["logistics"] = true
	eq(st.anti_air_radius(d), int(d.section("anti_air")["radius_upgraded"]), "one hex farther")
	eq(st.radar_range(radar, d), base_radar + 1, "radar one hex farther")


func test_logistics_lets_anti_air_engage_a_missile_one_hex_farther() -> void:
	var r = _stealth_match()
	var m = r[0]
	var launcher = put(m, 0, "basic_launcher", 2, 0)
	var gun = put(m, 1, "anti_air", 3, 6)
	var g = m.sides[1].island.grid
	var target := -1
	for h in g.count:
		if g.distance(gun.hex, h) == int(m.data.section("anti_air")["radius"]) + 1:
			target = h
			break
	var order := [{"launcher": launcher.hex, "missile": "basic", "target": target}]
	eq(events_of(play_round(m, order), "engage").size(), 0, "out of reach without logistics")
	m.sides[1].unlocked["logistics"] = true
	eq(events_of(play_round(m, order), "engage").size(), 1, "in reach with it")


# --- The AI ------------------------------------------------------------------

func test_strong_ai_builds_a_stealth_launcher_and_researches_logistics_in_level_5() -> void:
	var d = _l5()
	var m = flat_match(d)
	var st = m.sides[1]
	m.round_number = int(d.ai["strong"]["stealth"]["build_from_round"]) - 1
	m.begin_round()
	st.money = 1000
	var ai = StrongAI.new(1, d, 5)
	for a in ai.choose_build(m.view_for(1)):
		m.build_action(1, a)
	check(st.buildings.values().any(func(b): return b.type == "stealth_launcher"), "a stealth launcher")
	check(ai.research.has("logistics"), "logistics in the research order")
	check(not StrongAI.new(1, Levels.data_for(data(), 4), 5).research.has("logistics"), "not in level 4")


func test_strong_ai_aims_a_stealth_missile_at_the_best_guarded_target() -> void:
	var d = _l5()
	var m = flat_match(d)
	var st = m.sides[1]
	st.fuel = 40
	var silo = put(m, 1, "stealth_launcher", 3, 3)
	for b in m.sides[0].of_role(d, "base"):
		m.sides[0].remove_building(b.hex, d)
		m.bases_destroyed_by[1].append(b.hex)
	var open_lab = put(m, 0, "lab", 2, 10)
	var guarded = put(m, 0, "bank", 10, 4)
	for c in [Vector2i(11, 4), Vector2i(10, 5)]:
		var aa = put(m, 0, "anti_air", c.x, c.y)
		m.record_sighting(1, aa.hex)
	m.record_sighting(1, open_lab.hex)
	m.record_sighting(1, guarded.hex)
	m.begin_round()
	m.end_build_phase()
	var orders: Array = StrongAI.new(1, d, 5).choose_targets(m.view_for(1))
	var mine: Array = orders.filter(func(o): return int(o["launcher"]) == silo.hex)
	eq(mine.size(), 1, "the stealth launcher fires")
	check(int(mine[0]["target"]) != open_lab.hex, "not at the unguarded lab: %s" % str(mine))


func test_strong_ai_level_5_matches_play_legally() -> void:
	var d = _l5()
	for s in [3, 4]:
		var res: Dictionary = MatchRunner.play(d, s, [StrongAI.new(0, d, s), StrongAI.new(1, d, s + 50)], 300)
		eq(res["errors"].size(), 0, "seed %d rejected actions %s" % [s, str(res["errors"].slice(0, 3))])
		check(not res["timed_out"], "seed %d finished" % s)
