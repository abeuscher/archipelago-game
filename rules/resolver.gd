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
	for s in m.LAUNCH_ORDER:
		for o in m.orders[s]:
			var ms := {
				"id": next_id, "side": s, "launcher": int(o["launcher"]),
				"missile": String(o["missile"]), "target": int(o["target"]),
				"intercepted": false,
			}
			next_id += 1
			missiles[s].append(ms)
			m.sides[s].fuel -= int(data.missile(ms["missile"])["fuel"])
			m.stats[s]["fired"] += 1
			m.stats[s]["fired_" + ms["missile"]] = int(m.stats[s].get("fired_" + ms["missile"], 0)) + 1
			events.append({"type": "launch", "side": s, "id": ms["id"], "launcher": ms["launcher"],
				"missile": ms["missile"], "target": ms["target"]})

	# Enemy strikes land first, then the player's (presentation order). Dice
	# are rolled in this order too, so the sequence is fixed for a given seed.
	for attacker in m.LAUNCH_ORDER:
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
	for b in def.of_role(data, "anti_air"):
		if not def.weapon_active(b):
			continue
		var covered := false
		for r in radars:
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
			var hit: bool = m.dice.chance(acc)
			events.append({"type": "engage", "side": defender, "anti_air": a["b"].hex,
				"id": ms["id"], "hit": hit, "accuracy": acc})
			if hit:
				ms["intercepted"] = true
				m.stats[attacker]["intercepted"] += 1
			break   # No missile is engaged more than once a round.

	var elev: Dictionary = data.section("elevation")
	var crosses := bool(elev["blast_crosses_height_step"])
	var reveal_up := bool(elev["impact_reveals_uphill"])

	for ms in missiles:
		if ms["intercepted"]:
			continue
		var mdef: Dictionary = data.missile(ms["missile"])
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
		if int(mdef["blast_radius"]) >= 0 and (dmax > 0 or hits_on_base > 0.0):
			for h in grid.within(impact, int(mdef["blast_radius"])):
				if not crosses and isl.level[h] != lvl:
					continue
				var b = def.building_at(h)
				if b == null:
					continue
				var p: Dictionary = pending.get(h, {"damage": 0, "hits": 0.0})
				if data.is_base_like(b.type):
					p["hits"] = float(p["hits"]) + hits_on_base
					damaged.append({"hex": h, "hits": hits_on_base})
				else:
					var dmg: int = m.dice.rand_int(dmin, dmax)
					p["damage"] = int(p["damage"]) + dmg
					damaged.append({"hex": h, "damage": dmg})
				pending[h] = p
		for h in grid.within(impact, int(mdef["view_radius"])):
			if reveal_up or isl.level[h] <= lvl:
				reveals.append(h)
		events.append({"type": "impact", "side": attacker, "id": ms["id"], "missile": ms["missile"],
			"hex": impact, "damaged": damaged})


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
		if data.is_base_like(b.type):
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
