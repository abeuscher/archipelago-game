## Level 4: the enclave and its agents (foreign agents fly to the enemy
## island, uncover three hexes a round and disarm nukes; domestic agents
## patrol at home and kill them) and the refinery upgrade.
extends "res://tests/test_case.gd"

const Levels = preload("res://rules/levels.gd")
const BattleReport = preload("res://game/battle_report.gd")
const StrongAI = preload("res://ai/strong_ai.gd")
const MatchRunner = preload("res://ai/match_runner.gd")


func _spy_match():
	var d = Levels.data_for(data(), 4)
	var m = flat_match(d)
	var st = m.sides[0]
	st.fuel = 30
	st.money = 500
	var enc = put(m, 0, "enclave", 0, 0)
	return [m, enc]


func _spy(enc, target: int) -> Dictionary:
	return {"launcher": enc.hex, "missile": "spy", "target": target}


func _contiguous(m, path: Array) -> bool:
	var g = m.sides[1].island.grid
	for k in range(1, path.size()):
		if g.distance(int(path[k - 1]), int(path[k])) != 1:
			return false
	return true


# --- The building ------------------------------------------------------------

func test_the_enclave_is_a_level_4_building_and_the_spy_research_is_gone() -> void:
	for n in [1, 2, 3, 4]:
		var d = Levels.data_for(data(), n)
		var st = MatchState.create(d, 3).sides[0]
		eq(st.building_unlocked("enclave", d), n == 4, "enclave buildable in level %d: %s" % [n, n == 4])
		check(not d.rules["research"].has("spy"), "no spy research in level %d" % n)
		check(not d.building("airport")["missiles"].has("spy"), "the airport sends no spy")
	var d4 = Levels.data_for(data(), 4)
	eq(d4.building("enclave")["missiles"], ["spy"], "the enclave sends foreign agents")


func test_sending_an_agent_costs_its_fuel_and_money() -> void:
	var r = _spy_match()
	var m = r[0]
	var st = m.sides[0]
	var spy: Dictionary = m.data.missile("spy")
	m.begin_round()
	var fuel_before: int = st.fuel
	var money_before: int = st.money
	m.end_build_phase()
	ok(m.set_launch_orders(0, [_spy(r[1], hex(m, 3, 3))]))
	ok(m.set_launch_orders(1, []))
	m.resolve_playout()
	eq(st.fuel, fuel_before - int(spy["fuel"]), "fuel paid")
	eq(st.money, money_before - int(spy["money"]), "money paid")


func test_the_helicopter_is_half_as_easy_to_shoot_down() -> void:
	var d = data()
	var spy: Dictionary = d.missile("spy")
	var aa: Dictionary = d.section("anti_air")
	eq(float(spy["anti_air_accuracy"]), float(aa["accuracy"]) / 2.0, "half the usual chance")
	eq(float(spy["anti_air_accuracy_with_radar"]), float(aa["accuracy_with_radar"]) / 2.0, "half with radar too")


func test_agent_shot_down_is_its_own_event_and_not_a_missile_in_the_report() -> void:
	var r = _spy_match()
	var m = r[0]
	m.data.set_path("rules.missiles.spy.anti_air_accuracy", 1.0)
	put(m, 1, "anti_air", 6, 6)
	var ev := play_round(m, [_spy(r[1], hex(m, 6, 6))])
	eq(events_of(ev, "spy_lost").size(), 1, "spy_lost event")
	eq(events_of(ev, "spy").size(), 0, "he never lands")
	eq(m.spies[0].size(), 0, "no agent on the island")
	var c: Dictionary = BattleReport.counts(ev)
	eq(int(c["our_shot_down"]), 0, "not counted as a missile shot down")
	eq(int(c["hit_them"]), 0, "not counted as a hit")


# --- Foreign agents ------------------------------------------------------------

func test_agent_lands_and_uncovers_three_contiguous_hexes() -> void:
	var r = _spy_match()
	var m = r[0]
	var lab = put(m, 1, "lab", 6, 6)
	var target := hex(m, 6, 6)
	var s: Array = events_of(play_round(m, [_spy(r[1], target)]), "spy")
	eq(s.size(), 1, "the agent lands")
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
	eq(int(m.spies[0][0]["enclave"]), r[1].id, "sent by our enclave")
	check(m.sides[1].building_at(lab.hex) != null, "he does no damage")
	eq(m.spy_sightings[1], [target], "the enemy saw where he landed")


func test_agent_walks_three_new_hexes_every_round() -> void:
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


func test_radar_and_bunkers_do_not_catch_agents() -> void:
	var r = _spy_match()
	var m = r[0]
	put(m, 1, "radar", 6, 7)
	put(m, 1, "bunker", 7, 6)
	var s: Array = events_of(play_round(m, [_spy(r[1], hex(m, 6, 6))]), "spy")
	eq(int(s[0]["caught_by"]), -1, "not caught")
	eq(m.spies[0].size(), 1, "still there")


func test_agent_landing_on_the_sea_is_lost() -> void:
	var r = _spy_match()
	var m = r[0]
	var h := hex(m, 6, 6)
	m.sides[1].island.land[h] = 0
	var s: Array = events_of(play_round(m, [_spy(r[1], h)]), "spy")
	check(bool(s[0]["lost_at_sea"]), "lost at sea")
	eq(m.spies[0].size(), 0, "no agent on the island")


func test_one_agent_out_per_enclave_and_new_launches_get_new_ids() -> void:
	var r = _spy_match()
	var m = r[0]
	var launcher = put(m, 0, "basic_launcher", 2, 0)
	var enc2 = put(m, 0, "enclave", 4, 0)
	play_round(m, [_spy(r[1], hex(m, 6, 6))])
	var spy_id = m.spies[0][0]["id"]
	check(m.agent_out(0, r[1].hex) and not m.agent_out(0, enc2.hex), "the first enclave's agent is out")
	m.begin_round()
	m.end_build_phase()
	err_contains(m.set_launch_orders(0, [_spy(r[1], hex(m, 3, 3))]), "still on the enemy island", "not a second from the same enclave")
	ok(m.set_launch_orders(0, [_spy(enc2, hex(m, 10, 10)),
		{"launcher": launcher.hex, "missile": "basic", "target": hex(m, 2, 2)}]), "the other enclave can send one")
	ok(m.set_launch_orders(1, []))
	var launches: Array = events_of(m.resolve_playout(), "launch")
	eq(launches.size(), 2, "both go")
	check(launches.all(func(e): return e["id"] != spy_id), "new launches don't reuse the agent's id")


func test_agent_disarms_a_nuke_next_to_where_he_lands() -> void:
	var r = _spy_match()
	var m = r[0]
	var armed = put(m, 1, "nuclear_silo", 6, 7)
	armed.carrier_lost = false
	var empty = put(m, 1, "nuclear_silo", 2, 12)
	var ev := play_round(m, [_spy(r[1], hex(m, 6, 6))])
	var d: Array = events_of(ev, "nuke_disarmed")
	eq(d.size(), 1, "one nuke disarmed")
	eq(int(d[0]["hex"]), armed.hex, "the one beside him")
	check(armed.carrier_lost, "the silo is empty now")
	eq(armed.loading, 0, "nothing being built in it")
	eq(String(m.knowledge[0][armed.hex]["building"]["nuke"]), "none", "and seen empty")
	check(not m.knowledge[0].has(empty.hex), "a far silo is untouched and unseen")


func test_agent_disarms_a_nuke_being_built() -> void:
	var r = _spy_match()
	var m = r[0]
	var silo = put(m, 1, "nuclear_silo", 6, 7)
	silo.carrier_lost = false
	silo.loading = 1
	play_round(m, [_spy(r[1], hex(m, 6, 6))])
	check(silo.carrier_lost and silo.loading == 0, "the nuke in the making is gone")


func test_agent_heads_for_a_known_armed_silo() -> void:
	var r = _spy_match()
	var m = r[0]
	var silo = put(m, 1, "nuclear_silo", 6, 10)
	silo.carrier_lost = false
	m.record_sighting(0, silo.hex)
	var g = m.sides[1].island.grid
	var land := hex(m, 6, 6)
	var ev: Array = []
	for k in 3:
		ev = play_round(m, [_spy(r[1], land)] if k == 0 else [])
		if not events_of(ev, "nuke_disarmed").is_empty():
			break
		var at: int = int(m.spies[0][0]["hex"])
		check(g.distance(at, silo.hex) < g.distance(land, silo.hex), "round %d: closer to the silo" % k)
	check(silo.carrier_lost, "he reached it and disarmed it")


# --- Domestic agents ---------------------------------------------------------

func test_an_enclave_musters_a_domestic_agent_who_patrols() -> void:
	var r = _spy_match()
	var m = r[0]
	var ag: Dictionary = m.data.section("agents")
	var ev := play_round(m)
	var p: Array = events_of(ev, "agent_patrol").filter(func(e): return e["side"] == 0)
	eq(p.size(), 1, "one agent for our enclave")
	eq(int(p[0]["start"]), r[1].hex, "starting at the enclave")
	var n: int = p[0]["path"].size()
	check(n >= int(ag["domestic_walks_min"]) and n <= int(ag["domestic_walks_max"]), "walks %d hexes" % n)
	check(_contiguous(m, [r[1].hex] + p[0]["path"]), "one step at a time")
	eq(int(m.agents[0][0]["hex"]), int(p[0]["path"][-1]), "and stays where he stopped")
	eq(events_of(ev, "agent_patrol").filter(func(e): return e["side"] == 1).size(), 0, "no enclave, no agent")
	for k in 3:
		play_round(m)
	eq(m.agents[0].size(), 1, "still just the one")


func test_domestic_agents_go_with_their_enclave() -> void:
	var r = _spy_match()
	var m = r[0]
	play_round(m)
	m.sides[0].remove_building(r[1].hex, m.data)
	play_round(m)
	eq(m.agents[0].size(), 0, "no enclave, no agent")


func test_a_domestic_agent_kills_a_foreign_agent_next_to_him() -> void:
	var r = _spy_match()
	var m = r[0]
	var their = put(m, 1, "enclave", 6, 6)
	m.agents[1] = [{"id": "x", "enclave": their.id, "hex": hex(m, 6, 6), "home": their.hex, "home_by": 100}]
	m.spies[0] = [{"id": 99, "missile": "spy", "hex": hex(m, 7, 6), "enclave": r[1].id, "landed_round": 0}]
	var s: Array = events_of(play_round(m), "spy")
	eq(s.size(), 1, "his round")
	eq(s[0]["path"], [], "killed before a step")
	eq(int(s[0]["caught_at"]), hex(m, 7, 6), "where he stood")
	eq(int(s[0]["caught_by"]), hex(m, 6, 6), "by the agent beside him")
	eq(m.spies[0].size(), 0, "he is gone")
	check(not m.agent_out(0, r[1].hex), "our enclave can send another")


func test_a_foreign_agent_landing_beside_a_domestic_agent_is_killed() -> void:
	var r = _spy_match()
	var m = r[0]
	var their = put(m, 1, "enclave", 12, 12)
	m.data.set_path("rules.agents.domestic_walks_min", 0)
	m.data.set_path("rules.agents.domestic_walks_max", 0)
	m.agents[1] = [{"id": "x", "enclave": their.id, "hex": hex(m, 6, 7), "home": their.hex, "home_by": 100}]
	var s: Array = events_of(play_round(m, [_spy(r[1], hex(m, 6, 6))]), "spy")
	eq(s[0]["path"], [hex(m, 6, 6)], "only the landing hex")
	eq(int(s[0]["caught_by"]), hex(m, 6, 7), "killed on landing")
	eq(m.spies[0].size(), 0, "he is gone")


func test_a_domestic_agent_heads_for_where_a_foreign_agent_landed() -> void:
	var r = _spy_match()
	var m = r[0]
	var their = put(m, 1, "enclave", 4, 4)
	play_round(m)   # their agent mustered
	var g = m.sides[1].island.grid
	var land: int = g.step(g.step(g.step(their.hex, 0), 0), 0)
	eq(g.distance(their.hex, land), 3, "the landing is well inside his circle")
	play_round(m, [_spy(r[1], land)])
	if m.spy_sightings[1].is_empty():
		return   # he happened to walk onto it already
	var was: int = int(m.agents[1][0]["hex"])
	var p: Array = events_of(play_round(m), "agent_patrol").filter(func(e): return e["side"] == 1)
	if was != land:
		eq(g.distance(int(p[0]["path"][0]), land), g.distance(was, land) - 1, "his first step is toward the landing hex")


func test_a_domestic_agent_is_home_every_fifth_round_and_never_strays_too_far() -> void:
	var r = _spy_match()
	var m = r[0]
	var ag: Dictionary = m.data.section("agents")
	var every := int(ag["return_every"])
	var lo := int(ag["domestic_walks_min"])
	var g = m.sides[0].island.grid
	var first: int = m.round_number + 1
	for k in 3 * every:
		play_round(m)
		var a: Dictionary = m.agents[0][0]
		var d: int = g.distance(int(a["hex"]), r[1].hex)
		var due: int = first + every - 1 + (k / every) * every
		if m.round_number == due:
			eq(int(a["hex"]), r[1].hex, "round %d: back on the enclave" % m.round_number)
		else:
			check(d <= (due - m.round_number) * lo, "round %d: %d hexes out, can still make it home" % [m.round_number, d])


func test_a_domestic_agent_leaves_landings_outside_his_circle_alone() -> void:
	var r = _spy_match()
	var m = r[0]
	var ag: Dictionary = m.data.section("agents")
	var their = put(m, 1, "enclave", 0, 0)
	var g = m.sides[1].island.grid
	var land := hex(m, 14, 0)
	var reach: int = int(ag["return_every"]) * int(ag["domestic_walks_max"]) / 2
	check(g.distance(their.hex, land) > reach, "the landing is beyond his reach")
	play_round(m, [_spy(r[1], land)])
	for k in 10:
		play_round(m)
		check(g.distance(int(m.agents[1][0]["hex"]), their.hex) <= reach, "round %d: within his circle" % k)
	check(m.spy_sightings[1].has(land), "the far landing is left alone")


# --- The AI ------------------------------------------------------------------

func _ai_spy_match():
	var d = Levels.data_for(data(), 4)
	var m = flat_match(d)
	var st = m.sides[1]
	st.fuel = 30
	st.money = 300
	var enc = put(m, 1, "enclave", 3, 3)
	m.round_number = 9
	return [m, enc]


func test_strong_ai_builds_an_enclave_in_level_4() -> void:
	var d = Levels.data_for(data(), 4)
	var m = flat_match(d)
	var st = m.sides[1]
	m.round_number = int(d.ai["strong"]["spy"]["enclave_from_round"]) - 1
	m.begin_round()
	st.money = 1000
	var ai = StrongAI.new(1, d, 5)
	for a in ai.choose_build(m.view_for(1)):
		m.build_action(1, a)
	eq(st.count_role(d, "enclave"), 1, "an enclave once it is time and there is money")


func test_strong_ai_sends_an_agent_away_from_known_anti_air() -> void:
	var r = _ai_spy_match()
	var m = r[0]
	put(m, 0, "anti_air", 2, 2)
	m.record_sighting(1, hex(m, 2, 2))
	m.begin_round()
	m.end_build_phase()
	var orders: Array = StrongAI.new(1, m.data, 5).choose_targets(m.view_for(1))
	var spies: Array = orders.filter(func(o): return o["missile"] == "spy")
	eq(spies.size(), 1, "the agent goes")
	eq(int(spies[0]["launcher"]), r[1].hex, "from the enclave")
	var g = m.sides[0].island.grid
	check(g.distance(int(spies[0]["target"]), hex(m, 2, 2)) > int(m.data.section("anti_air")["radius"]), "out of the known gun's reach")
	ok(m.set_launch_orders(1, orders), "orders are legal")


func test_strong_ai_sends_no_new_agent_while_its_last_is_out() -> void:
	var r = _ai_spy_match()
	var m = r[0]
	var ai = StrongAI.new(1, m.data, 5)
	m.begin_round()
	m.end_build_phase()
	var orders: Array = ai.choose_targets(m.view_for(1))
	eq(orders.filter(func(o): return o["missile"] == "spy").size(), 1, "the agent goes")
	ok(m.set_launch_orders(1, orders))
	ok(m.set_launch_orders(0, []))
	m.resolve_playout()
	for k in 3:
		check(not m.spies[1].is_empty(), "round %d: he is still there" % k)
		m.begin_round()
		m.end_build_phase()
		orders = ai.choose_targets(m.view_for(1))
		eq(orders.filter(func(o): return o["missile"] == "spy").size(), 0, "round %d: no second agent" % k)
		ok(m.set_launch_orders(1, orders))
		ok(m.set_launch_orders(0, []))
		m.resolve_playout()
	m.spies[1].clear()   # killed
	m.begin_round()
	m.end_build_phase()
	eq(ai.choose_targets(m.view_for(1)).filter(func(o): return o["missile"] == "spy").size(), 1, "a new one once he is gone")


func test_strong_ai_lands_its_agent_where_he_can_disarm_a_known_nuke() -> void:
	var r = _ai_spy_match()
	var m = r[0]
	var silo = put(m, 0, "nuclear_silo", 10, 4)
	silo.carrier_lost = false
	m.record_sighting(1, silo.hex)
	m.begin_round()
	m.end_build_phase()
	var orders: Array = StrongAI.new(1, m.data, 5).choose_targets(m.view_for(1))
	var spies: Array = orders.filter(func(o): return o["missile"] == "spy")
	eq(spies.size(), 1, "the agent goes")
	var sp: Dictionary = m.data.missile("spy")
	var reach := int(sp["walks"]) - 1 + int(sp["disarm_range"])
	check(m.sides[0].island.grid.distance(int(spies[0]["target"]), silo.hex) <= reach, "near enough to disarm it at once")


func test_strong_ai_keeps_the_agent_money_back_in_the_build() -> void:
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


func test_strong_ai_fires_at_banks_and_labs_it_knows() -> void:
	var d = Levels.data_for(data(), 4)
	var m = flat_match(d)
	var st = m.sides[1]
	st.fuel = 30
	put(m, 1, "basic_launcher", 3, 3)
	put(m, 1, "basic_launcher", 5, 3)   # one shot kept for finding what's hidden, one spare
	for b in m.sides[0].of_role(d, "base"):
		m.sides[0].remove_building(b.hex, d)
		m.bases_destroyed_by[1].append(b.hex)
	var lab = put(m, 0, "lab", 9, 9)
	m.record_sighting(1, lab.hex)
	m.begin_round()
	m.end_build_phase()
	var orders: Array = StrongAI.new(1, d, 5).choose_targets(m.view_for(1))
	check(orders.any(func(o): return int(o["target"]) == lab.hex), "the known lab is shot at: %s" % str(orders))


func test_strong_ai_level_4_matches_play_legally() -> void:
	var d = Levels.data_for(data(), 4)
	for s in [3, 4]:
		var res: Dictionary = MatchRunner.play(d, s, [StrongAI.new(0, d, s), StrongAI.new(1, d, s + 50)], 300)
		eq(res["errors"].size(), 0, "seed %d rejected actions %s" % [s, str(res["errors"].slice(0, 3))])
		check(not res["timed_out"], "seed %d finished" % s)


# --- Level 4's other changes ---------------------------------------------------

func test_level_4_starts_both_sides_with_level_3_research_done() -> void:
	var m = MatchState.create(Levels.data_for(data(), 4), 7)
	for side in 2:
		var st = m.sides[side]
		check(st.is_unlocked("nuclear_silo") and st.is_unlocked("bank_upgrade"), "side %d has the silo and the bank upgrade" % side)
		check(not st.is_unlocked("refinery_upgrade"), "side %d: level 4's own research still to do" % side)
		check(st.building_unlocked("nuclear_silo", m.data), "side %d can build a silo at once" % side)
	var m3 = MatchState.create(Levels.data_for(data(), 3), 7)
	eq(m3.sides[0].unlocked.size(), 0, "level 3 starts with nothing researched")
	eq(m3.sides[1].unlocked.size(), 0, "nor does its enemy")


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
