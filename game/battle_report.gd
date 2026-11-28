## The battle summary: what each side's attack did this round, counted from
## the playout events and listed as stats in the comms screen, the enemy's
## half as soon as its strikes land and ours when ours do.
## Only counts that aren't zero are listed, so a quiet round gives none.
extends RefCounted

const PLAYER := 0
const ENEMY := 1
const SOLDIERS_PER_PLATOON := 8   ## the eight parachutes of a drop


## The summary as stats for the comms screen: "label: n" for each count in
## `labels` (count name -> label, from battle_report.stats in
## data/dialogue.json), in that order. Counts of zero are skipped. keys:
## only these counts (one half of the summary, battle_report.sections);
## empty for all of them.
static func stat_lines(events: Array, labels: Dictionary, keys: Array = []) -> Array:
	var c := counts(events)
	var out: Array = []
	for key in labels:
		if not keys.is_empty() and not keys.has(key):
			continue
		var n := int(c.get(key, 0))
		if n != 0:
			out.append("%s: %d" % [String(labels[key]), n])
	return out


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
