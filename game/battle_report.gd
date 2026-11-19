## The end-of-round battle report: what each side's attack did this round,
## counted from the playout events. Only lines with a number other than zero
## are given, so a quiet round gives no report at all.
extends RefCounted

const PLAYER := 0
const ENEMY := 1


## Lines of the report for the player, in order: their attack on us, then
## ours on them, then troops.
static func lines(events: Array) -> Array:
	var c := counts(events)
	var rows := [
		["Enemy missiles that hit us", c["hit_us"]],
		["Our buildings damaged", c["our_damaged"]],
		["Our buildings destroyed", c["our_destroyed"]],
		["Enemy missiles shot down", c["shot_down_by_us"]],
		["Enemy transports shot down", c["transports_shot_down_by_us"]],
		["Our missiles that hit", c["hit_them"]],
		["Our missiles shot down", c["our_shot_down"]],
		["Our transports shot down", c["our_transports_shot_down"]],
		["Enemy buildings damaged", c["enemy_damaged"]],
		["Enemy buildings destroyed", c["enemy_destroyed"]],
		["Our platoons lost", c["our_platoons_lost"]],
		["Enemy platoons stopped", c["enemy_platoons_lost"]],
	]
	var out: Array = []
	for r in rows:
		if int(r[1]) != 0:
			out.append("%s: %d" % [r[0], int(r[1])])
	return out


static func counts(events: Array) -> Dictionary:
	var transports := {}   # missile ids that were transports shot down
	for ev in events:
		if ev["type"] == "carrier_lost":
			transports[ev["id"]] = true
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
				if bool(ev["hit"]):
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
	for s in 2:
		var hurt := 0
		for h in damaged[s]:
			if not destroyed[s].has(h):
				hurt += 1
		c["our_damaged" if s == PLAYER else "enemy_damaged"] = hurt
		c["our_destroyed" if s == PLAYER else "enemy_destroyed"] = destroyed[s].size()
	return c
