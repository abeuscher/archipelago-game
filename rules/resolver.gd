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
		_walk_spies(m, attacker, events, reveals[attacker])
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


## A spy who got through lands on his hex and stays on the enemy island
## (landing on the sea loses him). He uncovers his landing hex and walks on,
## walks hexes in all this round, then walks hexes every round after (see
## _spy_walk), until a radar or bunker catches him.
static func _spy(m, attacker: int, ms: Dictionary, mdef: Dictionary, events: Array, reveals: Array) -> void:
	var isl = m.sides[1 - attacker].island
	var here := int(ms["target"])
	var ev := _spy_event(attacker, ms["id"], here, true)
	if not isl.is_land(here):
		ev["lost_at_sea"] = true
		reveals.append(here)
		events.append(ev)
		return
	var spy := {"id": ms["id"], "missile": ms["missile"], "hex": here, "landed_round": m.round_number}
	m.spies[attacker].append(spy)
	_spy_walk(m, attacker, spy, ev, int(mdef["walks"]), true, reveals)
	events.append(ev)


## Spies already on the enemy island walk on, before this side's strikes.
static func _walk_spies(m, attacker: int, events: Array, reveals: Array) -> void:
	for spy in m.spies[attacker].duplicate():
		var ev := _spy_event(attacker, spy["id"], int(spy["hex"]), false)
		_spy_walk(m, attacker, spy, ev, int(m.data.missile(String(spy["missile"]))["walks"]), false, reveals)
		events.append(ev)


static func _spy_event(attacker: int, id, start: int, landed: bool) -> Dictionary:
	return {"type": "spy", "side": attacker, "id": id, "landed": landed, "start": start,
		"path": [], "caught_by": -1, "lost_at_sea": false}


## One round of a spy's walk: `steps` contiguous hexes uncovered (on landing,
## the landing hex is the first). Each step goes toward the nearest hex his
## side has never seen (failing that, the one seen longest ago), keeping out
## of the reach of radars and bunkers his side knows of. Where an enemy
## radar (its range) or bunker (troops.bunker_range) reaches the hex he
## stands on, he is caught: what he uncovered up to there still comes back,
## and so does what caught him.
static func _spy_walk(m, attacker: int, spy: Dictionary, ev: Dictionary, steps: int, landing: bool, reveals: Array) -> void:
	var def = m.sides[1 - attacker]
	var grid = def.island.grid
	var catchers := _spy_catchers(m, def)
	var fresh := {}
	var here := int(spy["hex"])
	if landing:
		ev["path"].append(here)
		reveals.append(here)
		fresh[here] = true
		steps -= 1
	var caught := _caught_by(grid, catchers, here)
	var danger := known_danger(m.data, grid, m.knowledge[attacker])
	while caught < 0 and steps > 0:
		var nxt := _spy_step(m, attacker, here, fresh, danger)
		if nxt < 0:
			break
		here = nxt
		steps -= 1
		spy["hex"] = here
		ev["path"].append(here)
		reveals.append(here)
		fresh[here] = true
		caught = _caught_by(grid, catchers, here)
	if caught >= 0:
		ev["caught_by"] = caught
		reveals.append(caught)
		m.spies[attacker].erase(spy)


## [hex, reach] for every enemy radar and bunker able to catch a spy now.
static func _spy_catchers(m, def) -> Array:
	var out: Array = []
	for r in def.of_role(m.data, "radar"):
		var rr: int = def.radar_range(r, m.data)
		if rr > 0 and not r.disabled:
			out.append([r.hex, rr])
	var br := int(m.data.section("troops")["bunker_range"])
	for bk in def.of_role(m.data, "bunker"):
		if def.weapon_active(bk):
			out.append([bk.hex, br])
	return out


static func _caught_by(grid, catchers: Array, hex: int) -> int:
	for c in catchers:
		if grid.distance(int(c[0]), hex) <= int(c[1]):
			return int(c[0])
	return -1


## Hexes a side knows a spy would be caught on: within reach of a radar or
## bunker in its knowledge of the enemy island (the AI uses this too).
static func known_danger(data, grid, knowledge: Dictionary) -> Dictionary:
	var ranges: Array = data.section("radar")["range_by_level"]
	var br := int(data.section("troops")["bunker_range"])
	var out := {}
	for h in knowledge:
		var e: Dictionary = knowledge[h]
		var kb = e.get("building")
		if kb == null or not data.has_building(String(kb["type"])):
			continue
		var reach := -1
		match data.role(String(kb["type"])):
			"radar":
				reach = int(ranges[clampi(int(e["level"]), 0, ranges.size() - 1)])
			"bunker":
				reach = br
		if reach < 0:
			continue
		for w in grid.within(int(h), reach):
			out[w] = true
	return out


## The spy's next hex from `here`, or -1: a breadth-first search over land
## outside known danger finds the best hex to head for (never seen, nearest
## first; else seen longest ago, then nearest), and he takes the first step
## toward it.
static func _spy_step(m, attacker: int, here: int, fresh: Dictionary, danger: Dictionary) -> int:
	var isl = m.sides[1 - attacker].island
	var grid = isl.grid
	var known: Dictionary = m.knowledge[attacker]
	var first := {here: -1}   # hex -> the first step toward it
	var dist := {here: 0}
	var frontier: Array = [here]
	var best := -1
	var best_key: Array = []
	while not frontier.is_empty():
		var next: Array = []
		for h in frontier:
			for n in grid.neighbors(h):
				if dist.has(n) or not isl.is_land(n) or danger.has(n):
					continue
				dist[n] = int(dist[h]) + 1
				first[n] = n if h == here else int(first[h])
				next.append(n)
				var key: Array
				if fresh.has(n):
					key = [2, 0, int(dist[n]), n]
				elif not known.has(n):
					key = [0, 0, int(dist[n]), n]
				else:
					key = [1, int(known[n]["seen_round"]), int(dist[n]), n]
				if best < 0 or key < best_key:
					best = n
					best_key = key
		frontier = next
	if best < 0 or int(best_key[0]) == 2:
		return -1
	return int(first[best])


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
