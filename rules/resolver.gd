## Playout: both sides' launches are resolved against the state at the start
## of the playout, and all damage is applied together at the end. A building
## destroyed this round has therefore already fired and defended this round.
extends RefCounted


## Resolves the round's launches on `m` (a MatchState). Mutates m and returns
## the ordered event list the presentation plays back.
static func resolve(m) -> Array:
	var events: Array = []
	var data = m.data
	var pending: Array = [{}, {}]   # defender side -> hex -> {"damage": int, "hits": float}
	var reveals: Array = [[], []]   # attacker side -> hexes revealed in the opposing space

	var missiles: Array = [[], []]
	var next_id := 1
	for s in [0, 1]:
		for bt in m.boats[s]:
			next_id = maxi(next_id, int(bt["id"]) + 1)
		for sp in m.spies[s]:
			next_id = maxi(next_id, int(sp["id"]) + 1)
	for s in m.LAUNCH_ORDER:
		for o in m.orders[s]:
			var ms := {
				"id": next_id, "side": s, "launcher": int(o["launcher"]),
				"missile": String(o["missile"]), "target": int(o["target"]),
				"intercepted": false,
			}
			if o.has("dir"):
				ms["dir"] = int(o["dir"])
			next_id += 1
			var mdef0: Dictionary = data.missile(ms["missile"])
			m.sides[s].fuel -= int(mdef0["fuel"])
			m.sides[s].money -= int(mdef0.get("money", 0))
			if mdef0.has("crossing_rounds"):
				# A boat: it puts to sea now and lands in a later playout.
				var bt := {"id": ms["id"], "side": s, "launcher": ms["launcher"], "target": ms["target"],
					"dir": int(ms.get("dir", 0)), "lands_round": m.round_number + int(mdef0["crossing_rounds"])}
				m.boats[s].append(bt)
				var dk = m.sides[s].building_at(ms["launcher"])
				if dk != null:
					dk.boat_out = true
				m.stats[s]["fired"] += 1
				events.append({"type": "boat_launch", "side": s, "id": ms["id"], "launcher": ms["launcher"],
					"target": ms["target"], "dir": bt["dir"], "lands_round": bt["lands_round"]})
				continue
			if bool(mdef0.get("spent_on_launch", false)):
				# A nuke leaves its silo empty, whether or not it gets through.
				var silo = m.sides[s].building_at(ms["launcher"])
				if silo != null:
					silo.carrier_lost = true
			if bool(mdef0.get("launch_reveals_launcher", false)):
				# The launch is seen: the other side learns where it came from.
				reveals[1 - s].append(ms["launcher"])
				events.append({"type": "launcher_revealed", "side": s, "hex": ms["launcher"], "missile": ms["missile"]})
			missiles[s].append(ms)
			m.stats[s]["fired"] += 1
			m.stats[s]["fired_" + ms["missile"]] = int(m.stats[s].get("fired_" + ms["missile"], 0)) + 1
			events.append({"type": "launch", "side": s, "id": ms["id"], "launcher": ms["launcher"],
				"missile": ms["missile"], "target": ms["target"]})

	# Enemy strikes land first, then the player's (presentation order). Dice
	# are rolled in this order too, so the sequence is fixed for a given seed.
	for attacker in m.LAUNCH_ORDER:
		_agents_round(m, 1 - attacker, events, reveals[attacker])
		_land_boats(m, attacker, events, pending[1 - attacker], reveals[attacker])
		_resolve_attack(m, attacker, missiles[attacker], events, pending[1 - attacker], reveals[attacker])

	for defender in [0, 1]:
		_apply_damage(m, defender, pending[defender], events)

	for attacker in [0, 1]:
		var seen := {}
		for h in reveals[attacker]:
			if seen.has(h):
				continue
			seen[h] = true
			m.record_sighting(attacker, h)

	return events


static func _resolve_attack(m, attacker: int, missiles: Array, events: Array, pending: Dictionary, reveals: Array) -> void:
	var data = m.data
	var defender := 1 - attacker
	var att = m.sides[attacker]
	var def = m.sides[defender]
	var isl = def.island
	var grid = isl.grid
	var aa_cfg: Dictionary = data.section("anti_air")
	var aa_radius := int(aa_cfg["radius"])

	# Anti-air active at the start of playout, radar-covered ones first.
	var radars: Array = def.of_role(data, "radar")
	var defenders: Array = []
	for b in def.anti_air_guns(data):
		if not def.weapon_active(b):
			continue
		var covered := false
		for r in radars:
			if def.out_for_repair(r, data):
				continue
			if grid.distance(b.hex, r.hex) <= def.radar_range(r, data):
				covered = true
				break
		defenders.append({"b": b, "covered": covered, "left": def.anti_air_engagements(data)})
	defenders.sort_custom(func(a, b):
		if a["covered"] != b["covered"]:
			return a["covered"]
		return a["b"].id < b["b"].id)

	var shuffled := missiles.duplicate()
	m.dice.shuffle(shuffled)
	for ms in shuffled:
		for a in defenders:
			if int(a["left"]) <= 0:
				continue
			if grid.distance(a["b"].hex, ms["target"]) > aa_radius:
				continue
			a["left"] = int(a["left"]) - 1
			var acc := float(aa_cfg["accuracy_with_radar"]) if a["covered"] else float(aa_cfg["accuracy"])
			var md: Dictionary = data.missile(ms["missile"])
			if md.has("anti_air_accuracy"):   # the nuke is far harder to hit
				acc = float(md["anti_air_accuracy_with_radar"]) if a["covered"] else float(md["anti_air_accuracy"])
			var hit: bool = m.dice.chance(acc)
			events.append({"type": "engage", "side": defender, "anti_air": a["b"].hex,
				"id": ms["id"], "hit": hit, "accuracy": acc})
			if hit:
				ms["intercepted"] = true
				m.stats[attacker]["intercepted"] += 1
				if data.missile(ms["missile"]).has("carries"):
					# A transport shot down is lost; its airport needs a new one.
					var port = att.building_at(int(ms["launcher"]))
					if port != null:
						port.carrier_lost = true
					events.append({"type": "carrier_lost", "side": attacker, "id": ms["id"], "launcher": ms["launcher"]})
				elif data.missile(ms["missile"]).has("walks"):
					events.append({"type": "spy_lost", "side": attacker, "id": ms["id"], "launcher": ms["launcher"]})
			break   # No missile is engaged more than once a round.

	var elev: Dictionary = data.section("elevation")
	var crosses := bool(elev["blast_crosses_height_step"])
	var reveal_up := bool(elev["impact_reveals_uphill"])

	for ms in missiles:
		if ms["intercepted"]:
			continue
		var mdef: Dictionary = data.missile(ms["missile"])
		if mdef.has("carries"):
			_platoon(m, attacker, ms, events, pending, reveals)
			continue
		if mdef.has("walks"):
			_spy(m, attacker, ms, mdef, events, reveals)
			continue
		var impact: int = ms["target"]
		if mdef.has("seeks_with") and att.is_unlocked(String(mdef["seeks_with"])) and def.building_at(impact) == null:
			var dest := _seek(m, def, impact)
			if dest != impact:
				events.append({"type": "seek", "side": attacker, "id": ms["id"], "from": impact, "to": dest})
				impact = dest
		var lvl: int = isl.level[impact]
		var hits_on_base := float(mdef["base_hits"])
		var dmin := int(mdef["damage_min"])
		var dmax := int(mdef["damage_max"])
		var damaged: Array = []
		var centre_factor := float(mdef.get("centre_factor", 1.0))
		var crosses_here := bool(mdef.get("blast_crosses_height_step", crosses))
		var breaks := bool(mdef.get("breaks_strongholds", false))
		if int(mdef["blast_radius"]) >= 0 and (dmax > 0 or hits_on_base > 0.0):
			for h in grid.within(impact, int(mdef["blast_radius"])):
				if not crosses_here and isl.level[h] != lvl:
					continue
				var b = def.building_at(h)
				if b == null:
					continue
				var k := centre_factor if h == impact else 1.0
				var p: Dictionary = pending.get(h, {"damage": 0, "hits": 0.0})
				if data.is_base_like(b.type):
					p["hits"] = float(p["hits"]) + hits_on_base * k
					if breaks:
						p["breaking_hits"] = float(p.get("breaking_hits", 0.0)) + hits_on_base * k
					damaged.append({"hex": h, "hits": hits_on_base * k})
				else:
					var dmg: int = roundi(m.dice.rand_int(dmin, dmax) * k)
					p["damage"] = int(p["damage"]) + dmg
					damaged.append({"hex": h, "damage": dmg})
				pending[h] = p
		var seen: Array = []
		for h in grid.within(impact, int(mdef["view_radius"])):
			if reveal_up or isl.level[h] <= lvl:
				reveals.append(h)
				seen.append(h)
		events.append({"type": "impact", "side": attacker, "id": ms["id"], "missile": ms["missile"],
			"hex": impact, "damaged": damaged, "revealed": seen})
		m.note_bombed(defender, impact)


## --- Agents (level 4) -------------------------------------------------------
## An enclave sends foreign agents (the "spy" missile, by helicopter) to the
## enemy island and keeps domestic agents patrolling its own. A foreign agent
## uncovers the hexes he walks and disarms any nuke within disarm_range of
## him; a domestic agent within agents.catch_range of a foreign agent kills
## him. Radar and bunkers play no part.

## A foreign agent who got through lands on his hex (the defender sees where)
## and stays on the enemy island; landing on the sea loses him. He walks his
## first `walks` hexes at once, the landing hex the first of them.
static func _spy(m, attacker: int, ms: Dictionary, mdef: Dictionary, events: Array, reveals: Array) -> void:
	var defender := 1 - attacker
	var isl = m.sides[defender].island
	var here := int(ms["target"])
	var ev := _spy_event(attacker, ms["id"], here, true)
	if not isl.is_land(here):
		ev["lost_at_sea"] = true
		reveals.append(here)
		events.append(ev)
		return
	m.spy_sightings[defender].append(here)
	var enclave = m.sides[attacker].building_at(int(ms["launcher"]))
	var sp := {"id": ms["id"], "missile": ms["missile"], "hex": here,
		"enclave": enclave.id if enclave != null else -1, "landed_round": m.round_number}
	m.spies[attacker].append(sp)
	ev["path"].append(here)
	reveals.append(here)
	var fresh := {here: true}
	_disarm(m, attacker, sp, ev, events, reveals)
	_catch(m, attacker, sp, ev)
	for k in int(mdef["walks"]) - 1:
		if not m.spies[attacker].has(sp) or not _spy_advance(m, attacker, sp, ev, fresh, events, reveals):
			break
	events.append(ev)


## One round of agents on `defender`'s island: its enclaves' domestic agents
## are mustered (one per enclave, at the enclave, while it stands), then the
## other side's foreign agents already there and the domestic agents take a
## step each in turn until all have walked: `walks` hexes for a foreign
## agent, domestic_walks_min to _max (rolled) for a domestic one. A foreign
## agent within catch_range of a domestic one, at any point, is killed.
static func _agents_round(m, defender: int, events: Array, reveals: Array) -> void:
	var attacker := 1 - defender
	var ag: Dictionary = m.data.section("agents")
	_muster(m, defender)
	var spies: Array = m.spies[attacker].duplicate()
	var walk := []
	for sp in spies:
		var ev := _spy_event(attacker, sp["id"], int(sp["hex"]), false)
		walk.append({"sp": sp, "ev": ev, "left": int(m.data.missile(String(sp["missile"]))["walks"]), "fresh": {}})
		_catch(m, attacker, sp, ev)
	var patrol := []
	var isl = m.sides[defender].island
	for a in m.agents[defender]:
		var n: int = m.dice.rand_int(int(ag["domestic_walks_min"]), int(ag["domestic_walks_max"]))
		patrol.append({"a": a, "left": n, "home": _land_distances(isl, int(a["home"])), "ev": {"type": "agent_patrol",
			"side": defender, "agent": a["id"], "start": int(a["hex"]), "path": [], "home_by": int(a["home_by"])}})
		m.patrolled[defender][int(a["hex"])] = m.round_number
	var moving := true
	while moving:
		moving = false
		for w in walk:
			if int(w["left"]) <= 0 or not m.spies[attacker].has(w["sp"]):
				continue
			w["left"] = int(w["left"]) - 1
			if _spy_advance(m, attacker, w["sp"], w["ev"], w["fresh"], events, reveals):
				moving = true
			else:
				w["left"] = 0
		for p in patrol:
			if int(p["left"]) <= 0:
				continue
			# Steps he can count on before he must be home: the rest of this
			# round's, and the fewest a round for the rounds after it.
			var budget: int = int(p["left"]) + (int(p["a"]["home_by"]) - m.round_number) * int(ag["domestic_walks_min"])
			var nxt := _agent_step(m, defender, p["a"], p["home"], budget)
			p["left"] = int(p["left"]) - 1
			if nxt < 0:
				p["left"] = 0
				continue
			moving = true
			p["a"]["hex"] = nxt
			p["ev"]["path"].append(nxt)
			m.patrolled[defender][nxt] = m.round_number
			m.spy_sightings[defender].erase(nxt)
			for w in walk:
				if m.spies[attacker].has(w["sp"]):
					_catch(m, attacker, w["sp"], w["ev"])
	for p in patrol:
		if m.round_number >= int(p["a"]["home_by"]):
			# Back home on time: the next leg starts.
			p["a"]["home_by"] = int(p["a"]["home_by"]) + int(ag["return_every"])
		events.append(p["ev"])
	for w in walk:
		events.append(w["ev"])


static func _spy_event(attacker: int, id, start: int, landed: bool) -> Dictionary:
	return {"type": "spy", "side": attacker, "id": id, "landed": landed, "start": start,
		"path": [], "caught_by": -1, "caught_at": -1, "disarmed": [], "lost_at_sea": false}


## One domestic agent per enclave (agents.domestic_per_enclave), starting on
## the enclave; an enclave's agents go when it does. home_by: the round at
## whose end he must be back on his enclave (every return_every rounds,
## counting the round he appears as the first).
static func _muster(m, side: int) -> void:
	var st = m.sides[side]
	var per := int(m.data.section("agents")["domestic_per_enclave"])
	var ids := {}
	for e in st.of_role(m.data, "enclave"):
		ids[e.id] = e
	m.agents[side] = m.agents[side].filter(func(a): return ids.has(int(a["enclave"])))
	for id in ids:
		var have: int = m.agents[side].filter(func(a): return int(a["enclave"]) == id).size()
		for k in per - have:
			m.agents[side].append({"id": "%d:%d" % [id, have + k], "enclave": id, "hex": ids[id].hex, "home": ids[id].hex,
				"home_by": m.round_number + int(m.data.section("agents")["return_every"]) - 1})


## A foreign agent's step: to the next hex (see _spy_step), uncovered, then
## any nuke near him disarmed and the domestic agents checked. false if he
## has nowhere to go.
static func _spy_advance(m, attacker: int, sp: Dictionary, ev: Dictionary, fresh: Dictionary, events: Array, reveals: Array) -> bool:
	var nxt := _spy_step(m, attacker, int(sp["hex"]), fresh, ev["disarmed"])
	if nxt < 0:
		return false
	sp["hex"] = nxt
	ev["path"].append(nxt)
	reveals.append(nxt)
	fresh[nxt] = true
	_disarm(m, attacker, sp, ev, events, reveals)
	_catch(m, attacker, sp, ev)
	return true


## Every enemy silo holding a nuke (built or being built) within disarm_range
## of the agent loses it, and is revealed to his side.
static func _disarm(m, attacker: int, sp: Dictionary, ev: Dictionary, events: Array, reveals: Array) -> void:
	var def = m.sides[1 - attacker]
	var grid = def.island.grid
	var reach := int(m.data.missile(String(sp["missile"])).get("disarm_range", -1))
	if reach < 0:
		return
	for silo in def.of_role(m.data, "silo"):
		if silo.carrier_lost or grid.distance(silo.hex, int(sp["hex"])) > reach:
			continue
		silo.carrier_lost = true
		silo.loading = 0
		ev["disarmed"].append(silo.hex)
		reveals.append(silo.hex)
		events.append({"type": "nuke_disarmed", "side": attacker, "hex": silo.hex, "by": int(sp["hex"])})


## Kills the foreign agent if a domestic agent of the island's side is within
## catch_range of him. true if he was caught.
static func _catch(m, attacker: int, sp: Dictionary, ev: Dictionary) -> bool:
	var defender := 1 - attacker
	var grid = m.sides[defender].island.grid
	var reach := int(m.data.section("agents")["catch_range"])
	for a in m.agents[defender]:
		if grid.distance(int(a["hex"]), int(sp["hex"])) <= reach:
			ev["caught_by"] = int(a["hex"])
			ev["caught_at"] = int(sp["hex"])
			m.spies[attacker].erase(sp)
			return true
	return false


## Breadth-first search over land from `here`; returns the first step toward
## the hex with the smallest key, or -1. key(hex, distance) is an Array, or
## null to skip the hex as a goal.
static func _first_step(isl, here: int, key: Callable) -> int:
	var grid = isl.grid
	var first := {here: -1}
	var dist := {here: 0}
	var frontier: Array = [here]
	var best := -1
	var best_key = null
	while not frontier.is_empty():
		var next: Array = []
		for h in frontier:
			for n in grid.neighbors(h):
				if dist.has(n) or not isl.is_land(n):
					continue
				dist[n] = int(dist[h]) + 1
				first[n] = n if h == here else int(first[h])
				next.append(n)
				var k = key.call(n, int(dist[n]))
				if k != null and (best_key == null or k < best_key):
					best = n
					best_key = k
		frontier = next
	return int(first[best]) if best >= 0 else -1


## A foreign agent heads for the nearest silo his side has seen with a nuke
## in it (not one he has just disarmed), else the nearest hex his side has
## never seen, else the one seen longest ago; never back over hexes he
## uncovered this round.
static func _spy_step(m, attacker: int, here: int, fresh: Dictionary, disarmed: Array) -> int:
	var isl = m.sides[1 - attacker].island
	var known: Dictionary = m.knowledge[attacker]
	var targets := {}
	for h in known:
		var kb = known[h].get("building")
		if kb != null and kb.has("nuke") and String(kb["nuke"]) != "none" and not disarmed.has(int(h)):
			targets[int(h)] = true
	return _first_step(isl, here, func(n: int, d: int):
		if targets.has(n):
			return [0, 0, d, n]
		if fresh.has(n):
			return null
		if not known.has(n):
			return [1, 0, d, n]
		return [2, int(known[n]["seen_round"]), d, n])


## A domestic agent heads for the nearest hex where a foreign agent was seen
## landing and no patrol has been since, else the nearest hex least recently
## patrolled (never first); but only for a hex he can reach and still get
## home from within `budget` steps (walking there, then back: home holds the
## land distances to his enclave). With none, he heads home, or waits there.
static func _agent_step(m, side: int, a: Dictionary, home: Dictionary, budget: int) -> int:
	var isl = m.sides[side].island
	var here := int(a["hex"])
	var seen: Array = m.spy_sightings[side]
	var pat: Dictionary = m.patrolled[side]
	var nxt := _first_step(isl, here, func(n: int, d: int):
		if d + int(home.get(n, 1 << 20)) > budget:
			return null
		if seen.has(n):
			return [0, 0, d, n]
		return [1, int(pat.get(n, -1)), d, n])
	if nxt >= 0 or here == int(a["home"]):
		return nxt
	return _first_step(isl, here, func(n: int, d: int):
		return [0, d, n] if n == int(a["home"]) else null)


## Land distance from `from` to every land hex it can reach.
static func _land_distances(isl, from: int) -> Dictionary:
	var dist := {from: 0}
	var frontier: Array = [from]
	while not frontier.is_empty():
		var next: Array = []
		for h in frontier:
			for n in isl.grid.neighbors(h):
				if dist.has(n) or not isl.is_land(n):
					continue
				dist[n] = int(dist[h]) + 1
				next.append(n)
		frontier = next
	return dist


## Boats due this round reach the defender's coast. Each active coastal
## cannon within cannon_range of the landing hex fires once; a hit sinks the
## boat and its docks must replace it. A boat aimed at a hex that isn't
## coast finds nowhere to land and turns back. Otherwise its platoon lands
## and marches as from a transport. Either way the docks can launch again.
static func _land_boats(m, attacker: int, events: Array, pending: Dictionary, reveals: Array) -> void:
	var data = m.data
	var defender := 1 - attacker
	var def = m.sides[defender]
	var isl = def.island
	var tc: Dictionary = data.section("troops")
	var due: Array = m.boats[attacker].filter(func(bt): return int(bt["lands_round"]) <= m.round_number)
	if due.is_empty():
		return
	var cannons: Array = def.of_role(data, "coastal_cannon").filter(func(b): return def.weapon_active(b))
	for bt in due:
		m.boats[attacker].erase(bt)
		m.boats_arrived_at[defender] += 1
		var dk = m.sides[attacker].building_at(int(bt["launcher"]))
		events.append({"type": "boat_arrive", "side": attacker, "id": bt["id"], "launcher": bt["launcher"],
			"target": bt["target"], "dir": bt["dir"]})
		var sunk := false
		for c in cannons:
			if isl.grid.distance(c.hex, int(bt["target"])) > int(tc["cannon_range"]):
				continue
			var hit: bool = m.dice.chance(float(tc["cannon_accuracy"]))
			events.append({"type": "cannon_fire", "side": defender, "cannon": c.hex, "id": bt["id"], "hit": hit})
			if hit:
				sunk = true
				break
		if dk != null:
			dk.boat_out = false
		if sunk:
			if dk != null:
				dk.carrier_lost = true
			events.append({"type": "boat_sunk", "side": attacker, "id": bt["id"], "launcher": bt["launcher"]})
			continue
		if not isl.is_coastal(int(bt["target"])):
			reveals.append(int(bt["target"]))
			events.append({"type": "boat_no_landing", "side": attacker, "id": bt["id"]})
			continue
		_platoon(m, attacker, {"id": bt["id"], "target": int(bt["target"]), "dir": int(bt["dir"])}, events, pending, reveals)


## A platoon lands on its target hex and marches platoon_march more hexes
## in its direction. It can step down but not up (unless platoon_can_climb);
## the sea or the edge of the space ends the march. Landing on the sea loses
## it. On each hex it destroys whatever stands there, unless an active
## bunker is within bunker_range, which wipes it out on that hex. Every hex
## it reaches is revealed, and so is the bunker that stops it.
static func _platoon(m, attacker: int, ms: Dictionary, events: Array, pending: Dictionary, reveals: Array) -> void:
	var data = m.data
	var defender := 1 - attacker
	var def = m.sides[defender]
	var isl = def.island
	var grid = isl.grid
	var tc: Dictionary = data.section("troops")
	var reach := int(tc["platoon_march"])
	var climb := bool(tc["platoon_can_climb"])
	var bunker_range := int(tc["bunker_range"])
	var bunkers: Array = def.of_role(data, "bunker").filter(func(b): return def.weapon_active(b))
	var ev := {"type": "platoon", "side": attacker, "id": ms["id"], "target": ms["target"], "dir": int(ms.get("dir", 0)),
		"path": [], "destroyed": [], "stopped_by": -1, "lost_at_sea": false}
	var here: int = ms["target"]
	if not isl.is_land(here):
		ev["lost_at_sea"] = true
		reveals.append(here)
		events.append(ev)
		return
	m.note_bombed(defender, here)
	for step in reach + 1:
		if step > 0:
			var nxt: int = grid.step(here, int(ev["dir"]))
			if nxt < 0 or not isl.is_land(nxt):
				break
			if not climb and isl.level[nxt] > isl.level[here]:
				break
			here = nxt
		ev["path"].append(here)
		reveals.append(here)
		var stopper := -1
		for bk in bunkers:
			if grid.distance(bk.hex, here) <= bunker_range:
				stopper = bk.hex
				break
		if stopper >= 0:
			ev["stopped_by"] = stopper
			reveals.append(stopper)
			break
		if def.building_at(here) != null:
			var p: Dictionary = pending.get(here, {"damage": 0, "hits": 0.0})
			p["destroy"] = true
			pending[here] = p
			ev["destroyed"].append(here)
	events.append(ev)


## Motion sensor: from an empty hex, move to the nearest building within the
## seek range, travelling only across hexes at the impact's level.
static func _seek(m, def, start: int) -> int:
	var data = m.data
	var isl = def.island
	var grid = isl.grid
	var reach := int(data.section("motion_sensor")["seek_range"])
	var any_level := bool(data.section("elevation")["seek_can_change_level"])
	var lvl: int = isl.level[start]
	var seen := {start: true}
	var frontier: Array = [start]
	for step in reach:
		var next: Array = []
		for h in frontier:
			for n in grid.neighbors(h):
				if seen.has(n):
					continue
				if not any_level and isl.level[n] != lvl:
					continue
				seen[n] = true
				next.append(n)
		next.sort()
		var found: Array = []
		for n in next:
			if def.building_at(n) != null:
				found.append(n)
		if not found.is_empty():
			return m.dice.pick(found)
		frontier = next
	return start


## Hits from a stronghold-breaking missile (the nuke) in one round that bring
## a stronghold down: the centre of a nuke's blast.
const STRONGHOLD_BREAK_HITS := 2.0


static func _apply_damage(m, defender: int, pending: Dictionary, events: Array) -> void:
	var data = m.data
	var def = m.sides[defender]
	var hexes := pending.keys()
	hexes.sort()
	for h in hexes:
		var b = def.building_at(h)
		var p: Dictionary = pending[h]
		var destroyed := false
		# Any hit on a building under repair cancels the repair.
		b.repairing = false
		if bool(p.get("destroy", false)):
			destroyed = true   # overrun by a platoon
		elif data.is_missile_proof(b.type) and float(p.get("breaking_hits", 0.0)) >= STRONGHOLD_BREAK_HITS:
			destroyed = true   # a nuke on it: the one missile it can't stand
		elif data.is_missile_proof(b.type):
			# A stronghold: a hit knocks out its gun and gives it away, but
			# only troops (or a nuke) can take it. Its hits only count for the reveal.
			if float(p["hits"]) > 0.0:
				if b.hits <= 0.0:
					events.append({"type": "stronghold_revealed", "side": defender, "hex": h})
				b.hits += float(p["hits"])
				b.disabled = true
				events.append({"type": "disabled", "side": defender, "hex": h, "building": b.type})
		elif data.is_base_like(b.type):
			var bdef: Dictionary = data.building(b.type)
			b.hits += float(p["hits"])
			if b.hits >= float(bdef["hits_to_destroy"]):
				destroyed = true
			elif bdef.has("reveals_as_decoy_at_hits") and b.hits >= float(bdef["reveals_as_decoy_at_hits"]):
				events.append({"type": "decoy_revealed", "side": defender, "hex": h})
		else:
			b.hp -= int(p["damage"])
			if b.hp <= 0:
				destroyed = true
			elif data.is_weapon(b.type):
				b.disabled = true
				events.append({"type": "disabled", "side": defender, "hex": h, "building": b.type})
			else:
				events.append({"type": "damaged", "side": defender, "hex": h, "building": b.type, "hp": b.hp})
		if destroyed:
			m.note_destroyed(defender, h, b.type)
			def.remove_building(h, data)
			events.append({"type": "destroyed", "side": defender, "hex": h, "building": b.type})
