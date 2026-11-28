## The battle summary: what each side's attack did this round, counted from
## the playout events, as a table in the comms screen (the enemy's column as
## soon as its strikes land, ours when ours do). counts() is the older,
## finer count of hits, losses and soldiers.
extends RefCounted

const PLAYER := 0
const ENEMY := 1
const SOLDIERS_PER_PLATOON := 8   ## the eight parachutes of a drop


## What one side's attack did this round, for the summary table:
## "fired_<missile>" and "hit_<missile>" (reached its target, not shot down)
## per missile type, "shot_down" (missiles and transports brought down by
## the other side's anti-air; spy helicopters are left out, the log tells of
## them), "platoons_landed" (came ashore alive, by transport or boat),
## "boats_sunk" (by coastal cannons), "destroyed" (the other side's buildings
## destroyed).
static func side_counts(events: Array, attacker: int) -> Dictionary:
	var c := {"shot_down": 0, "platoons_landed": 0, "boats_sunk": 0, "destroyed": 0}
	var spies := {}
	for ev in events:
		if ev["type"] == "spy_lost":
			spies[ev["id"]] = true
	for ev in events:
		var side := int(ev.get("side", -1))
		match String(ev["type"]):
			"launch":
				if side == attacker:
					var k := "fired_" + String(ev["missile"])
					c[k] = int(c.get(k, 0)) + 1
			"impact":
				if side == attacker:
					var k := "hit_" + String(ev["missile"])
					c[k] = int(c.get(k, 0)) + 1
			"engage":   # side is the defender
				if side == 1 - attacker and bool(ev["hit"]) and not spies.has(ev["id"]):
					c["shot_down"] += 1
			"platoon":
				if side == attacker and not bool(ev["lost_at_sea"]):
					c["platoons_landed"] += 1
			"boat_sunk":   # side is the boat's owner
				if side == attacker:
					c["boats_sunk"] += 1
			"destroyed":   # side is the owner
				if side == 1 - attacker:
					c["destroyed"] += 1
	return c


## One cell of the summary table: `row` (from battle_report.rows in
## data/dialogue.json) filled in from side_counts; `none` when it is zero.
static func cell(row: Dictionary, c: Dictionary, none: String) -> String:
	if row.has("missiles"):
		var fired := 0
		var hit := 0
		for t in row["missiles"]:
			fired += int(c.get("fired_" + String(t), 0))
			hit += int(c.get("hit_" + String(t), 0))
		if fired == 0:
			return none
		return String(row["format"]).format({"fired": fired, "hit": hit})
	var n := int(c.get(String(row["count"]), 0))
	if n == 0:
		return none
	return String(row.get("format_one", row["format"]) if n == 1 else row["format"]).format({"n": n})


## Whether a row is in the table: only when either side has something in
## it this round (null: a side not yet in).
static func row_shown(row: Dictionary, sides: Array, none: String) -> bool:
	for c in sides:
		if c != null and cell(row, c, none) != none:
			return true
	return false


static func counts(events: Array) -> Dictionary:
	var transports := {}   # missile ids that were transports shot down
	var spies := {}        # spy helicopters shot down: the log tells of them, not the report
	for ev in events:
		if ev["type"] == "carrier_lost":
			transports[ev["id"]] = true
		elif ev["type"] == "spy_lost":
			spies[ev["id"]] = true
	var c := {"hit_us": 0, "hit_them": 0, "shot_down_by_us": 0, "transports_shot_down_by_us": 0,
		"our_shot_down": 0, "our_transports_shot_down": 0, "our_platoons_lost": 0, "enemy_platoons_lost": 0}
	var damaged := [{}, {}]     # side -> hexes hit this round
	var destroyed := [{}, {}]   # side -> hexes destroyed this round
	for ev in events:
		var side := int(ev.get("side", -1))
		match String(ev["type"]):
			"impact":   # side is the attacker
				c["hit_us" if side == ENEMY else "hit_them"] += 1
				for d in ev["damaged"]:
					damaged[1 - side][int(d["hex"])] = true
			"engage":   # side is the defender
				if bool(ev["hit"]) and not spies.has(ev["id"]):
					var key: String
					if side == PLAYER:
						key = "transports_shot_down_by_us" if transports.has(ev["id"]) else "shot_down_by_us"
					else:
						key = "our_transports_shot_down" if transports.has(ev["id"]) else "our_shot_down"
					c[key] += 1
			"destroyed":   # side is the owner
				destroyed[side][int(ev["hex"])] = true
			"boat_sunk":   # side is the boat's owner
				c["our_platoons_lost" if side == PLAYER else "enemy_platoons_lost"] += 1
			"platoon":     # side is the attacker
				if bool(ev["lost_at_sea"]) or int(ev["stopped_by"]) >= 0:
					c["our_platoons_lost" if side == PLAYER else "enemy_platoons_lost"] += 1
	# A transport shot down takes its platoon with it.
	for ev in events:
		if ev["type"] == "carrier_lost":
			c["our_platoons_lost" if int(ev["side"]) == PLAYER else "enemy_platoons_lost"] += 1
	c["our_soldiers_lost"] = c["our_platoons_lost"] * SOLDIERS_PER_PLATOON
	c["enemy_soldiers_lost"] = c["enemy_platoons_lost"] * SOLDIERS_PER_PLATOON
	for s in 2:
		var hurt := 0
		for h in damaged[s]:
			if not destroyed[s].has(h):
				hurt += 1
		c["our_damaged" if s == PLAYER else "enemy_damaged"] = hurt
		c["our_destroyed" if s == PLAYER else "enemy_destroyed"] = destroyed[s].size()
	return c
