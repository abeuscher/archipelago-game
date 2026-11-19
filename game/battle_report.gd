## The end-of-round battle report: what each side's attack did this round,
## counted from the playout events, and said by the Admiral as sentences.
## Only things whose number isn't zero are said, so a quiet round gives no
## report at all.
extends RefCounted

const PLAYER := 0
const ENEMY := 1
const SOLDIERS_PER_PLATOON := 8   ## the eight parachutes of a drop
const WORDS := ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
	"eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen", "twenty"]


## The Admiral's sentences for the round, in order, from `parts` (the
## battle_report parts in data/dialogue.json: a count name -> [said for one,
## said for more], with {n} for the number, spelled out up to twenty).
## Counts of zero are skipped.
static func sentences(events: Array, parts: Dictionary) -> Array:
	var c := counts(events)
	var out: Array = []
	for key in parts:
		var n := int(c.get(key, 0))
		if n == 0:
			continue
		var forms: Array = parts[key]
		var said := String(forms[0] if n == 1 else forms[1]).format({"n": WORDS[n] if n < WORDS.size() else str(n)})
		out.append(said.left(1).to_upper() + said.substr(1))
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
