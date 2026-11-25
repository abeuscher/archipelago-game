## The enemy AI from spec section 12: as strong as it can be made without any
## unfair advantage. It sees only a SideView, like the simple AI. Its
## strength comes from:
##   Placement: bases spread so no single missile's view covers two of
##     them, away from the obvious middle; the decoy goes where a player
##     would expect a base.
##   Search: a running estimate of where enemy bases can still be, aiming
##     each search shot where the most likely unexplored ground is.
##   Targeting: weapons and radar first while the enemy has known active
##     launchers, always keeping a shot for bases or scouting; extra
##     missiles where known anti-air covers a target.
##   Economy: a build order from data (chosen by batch testing), never a
##     launcher it can't fuel.
##   Adapting: building and rebuilding on hexes the enemy hasn't seen;
##     repairing in priority order.
## Difficulty comes from handicaps (data/ai.json "strong.handicap_presets"):
## noisier choices, shorter memory, a weaker build order, plainer placement.
extends "res://ai/simple_ai.gd"

const Island = preload("res://rules/island.gd")
const SideState = preload("res://rules/side_state.gd")

const PRIOR_SAMPLES := 60
const PRIOR_SEED := 7919

static var _land_prior_cache: Dictionary = {}   ## "w x h" -> PackedFloat32Array

var hc: Dictionary          ## active handicap settings
var _land_prior: PackedFloat32Array


var research: Array = []   ## research order for this match
var _last_spy: int = -1000 ## round of the spy's last trip


func _init(side_index: int, game_data, match_seed: int, handicap: String = "") -> void:
	super(side_index, game_data, match_seed)
	cfg = game_data.ai["strong"]
	var presets: Dictionary = cfg["handicap_presets"]
	var key := handicap if handicap != "" else String(cfg["handicap"])
	hc = presets.get(key, presets["none"])
	# One troop route favoured per match, so both airports and docks appear.
	research = Array(cfg["research_order"]).duplicate()
	var a := research.find("airport")
	var d := research.find("docks")
	if a >= 0 and d >= 0 and rng.chance(0.5):
		research[a] = "docks"
		research[d] = "airport"
	# Strongholds fall only to troops: in a level with them, the way to get
	# troops (and the bunkers that stop the enemy's) is researched first.
	if _strongholds() > 0:
		var first: Array = cfg["strongholds"]["research_first"]
		for item in first:
			research.erase(item)
		research = first + research
	# Nuke levels: the silo first (it waits on other research anyway), the
	# bank upgrade early.
	if _in_level("nuclear_silo"):
		research.push_front("nuclear_silo")
	if _in_level("bank_upgrade"):
		var at := int(cfg["nukes"]["bank_upgrade_at"]) + (1 if research.has("nuclear_silo") else 0)
		research.insert(mini(research.size(), at), "bank_upgrade")
	# Level 5: logistics.
	if _in_level("logistics"):
		var at3 := int(cfg["stealth"]["logistics_at"]) + (1 if research.has("nuclear_silo") else 0)
		research.insert(mini(research.size(), at3), "logistics")
	# Level 4: the refinery upgrade early.
	if _in_level("refinery_upgrade"):
		var at2 := int(cfg["nukes"]["refinery_upgrade_at"]) + (1 if research.has("nuclear_silo") else 0)
		research.insert(mini(research.size(), at2), "refinery_upgrade")
	# Research the level starts with done (carried over) needs no slot.
	for item in SideState.starting_research(data):
		research.erase(item)


## A research item this level offers.
func _in_level(item: String) -> bool:
	return data.rules["research"].has(item) and bool(data.research_item(item).get("available", true))


func _strongholds() -> int:
	return SideState.strongholds_per_side(data)


# --- Shared helpers --------------------------------------------------------

func _build_order() -> Array:
	var order: Array = cfg[String(hc["build_order"])]
	if _in_level("nuclear_silo"):
		# Nuke levels: more labs right after the first, to reach the silo sooner.
		order = order.duplicate()
		var lab_at := order.find("lab")
		for k in int(cfg["nukes"].get("extra_labs", 0)):
			order.insert(lab_at + 1 if lab_at >= 0 else 0, "lab")
	if _strongholds() > 0:
		# Stronghold levels: the troop buildings move up to just after the lab.
		var early: Array = cfg["strongholds"]["build_early"]
		var out: Array = order.duplicate()
		for t in early:
			out.erase(t)
		var at := out.find("lab")
		if at < 0:
			out.insert(0, "lab")
			at = 0
		for k in early.size():
			out.insert(at + 1 + k, early[k])
		order = out
	return _labs_at(order)


## nukes.lab_at (a level may set it): the first lab and the extra labs move
## to that place in the build order, so research starts sooner. -1 leaves
## the order alone.
func _labs_at(order: Array) -> Array:
	var at := int(cfg["nukes"].get("lab_at", -1))
	if at < 0 or not _in_level("nuclear_silo"):
		return order
	var out: Array = order.duplicate()
	var n := 1 + int(cfg["nukes"].get("extra_labs", 0))
	var moved := 0
	while moved < n and out.has("lab"):
		out.erase("lab")
		moved += 1
	for k in moved:
		out.insert(mini(at, out.size()), "lab")
	return out


## A sighting map with the memory handicap applied.
func _knowledge(view) -> Dictionary:
	var mem := int(hc["memory_rounds"])
	if mem < 0:
		return view.enemy_knowledge
	var out := {}
	for h in view.enemy_knowledge:
		if view.round_number - int(view.enemy_knowledge[h]["seen_round"]) <= mem:
			out[h] = view.enemy_knowledge[h]
	return out


## Best item by score, but with the noise handicap: sometimes a random
## candidate with a positive score instead.
func _choose(items: Array, score: Callable) -> int:
	var noise := float(hc["choice_noise"])
	if noise > 0.0 and rng.chance(noise):
		var ok := items.filter(func(it): return float(score.call(it)) > 0.0)
		if not ok.is_empty():
			return rng.pick(ok)
	return _best(items, score)


## Largest view radius of any missile: two bases closer than twice this
## could be revealed by one missile.
func _max_view() -> int:
	var r := 0
	for mt in data.missile_types():
		r = maxi(r, int(data.missile(mt)["view_radius"]))
	return r


# --- Setup -----------------------------------------------------------------

func choose_setup(view) -> Dictionary:
	if bool(hc["plain_placement"]):
		return super(view)
	var st = view.own
	var g = st.island.grid
	var isl = st.island
	var per_side: int = data.integer("bases", "per_side")
	var decoys := mini(int(view.settings["decoys_per_side"]), st.money / maxi(1, data.cost("decoy")))
	decoys = mini(decoys, int(cfg["setup_decoys_max"]))
	var land: Array = Array(isl.land_hexes())
	var centre := _land_centre(isl)
	var max_d := 1.0
	for h in land:
		max_d = maxf(max_d, float(g.distance(h, centre)))
	var pc: Dictionary = cfg["placement"]
	# How tucked away a hex is: far from the middle, and on a level that
	# impacts on lower ground can't reveal.
	var hidden := {}
	for h in land:
		var lower := 0
		var near: PackedInt32Array = g.within(h, 1)
		for n in near:
			if isl.level[n] < isl.level[h] or not isl.is_land(n):
				lower += 1
		hidden[h] = float(pc["edge_weight"]) * g.distance(h, centre) / max_d \
			+ float(pc["height_weight"]) * lower / float(near.size()) \
			+ float(pc["noise"]) * rng.rand_float()
	var spacing := 2 * _max_view() + 1
	var best_set: Array = []
	var best_score := -INF
	while best_set.is_empty() and spacing >= 2:
		for attempt in int(pc["attempts"]):
			# Each attempt ranks the land by tuckedness plus fresh jitter, then
			# takes hexes greedily while they keep their distance.
			var key := {}
			for h in land:
				key[h] = float(hidden[h]) + float(pc["attempt_jitter"]) * rng.rand_float()
			var order := land.duplicate()
			order.sort_custom(func(a, b): return key[a] > key[b] or (key[a] == key[b] and a < b))
			var chosen: Array = []
			for h in order:
				if chosen.all(func(c): return g.distance(h, c) >= spacing):
					chosen.append(h)
					if chosen.size() == per_side:
						break
			if chosen.size() < per_side:
				continue
			var s := 0.0
			for h in chosen:
				s += hidden[h]
			if s > best_score:
				best_score = s
				best_set = chosen
		if best_set.is_empty():
			spacing -= 1
	# The decoy: the most obvious spot left, near the middle and up high,
	# far enough from the real bases that hitting it reveals none of them.
	var decoy_hexes: Array = []
	for k in decoys:
		var taken: Array = best_set + decoy_hexes
		var pick := _best(land, func(h):
			for c in taken:
				if g.distance(h, c) < 2:
					return -INF
			var ok := taken.all(func(c): return g.distance(h, c) >= spacing)
			return (1.0 - g.distance(h, centre) / max_d) + 0.3 * isl.level[h] + (1.0 if ok else -2.0))
		if pick < 0:
			break
		decoy_hexes.append(pick)
	# The first bases become strongholds: put them where troops have the
	# hardest time, up high and away from the beach.
	if _strongholds() > 0 and best_set.size() > 1:
		best_set.sort_custom(func(a, b): return _fort_score(isl, a) > _fort_score(isl, b))
	return {"bases": best_set, "decoys": decoy_hexes}


func _fort_score(isl, h: int) -> float:
	return float(isl.level[h]) + (0.0 if isl.is_coastal(h) else 1.5)


func _land_centre(isl) -> int:
	var g = isl.grid
	var sum := Vector2.ZERO
	var n := 0
	for h in isl.land_hexes():
		sum += Vector2(g.col_of(h), g.row_of(h))
		n += 1
	if n == 0:
		return g.center_index()
	sum /= n
	return g.index_of(clampi(roundi(sum.x), 0, g.width - 1), clampi(roundi(sum.y), 0, g.height - 1))


# --- Build and repair ------------------------------------------------------

func choose_build(view) -> Array:
	var st = view.own
	var actions: Array = []
	# A spy trip due this round: its money is kept back from the build (st is
	# our own copy, so this only changes what we plan to spend).
	if _spy_due(view, st):
		st.money -= mini(st.money, int(data.missile("spy").get("money", 0)))
	for type in cfg["repair_priority"]:
		for b in st.buildings_sorted():
			if b.type == type and st.can_repair(b.hex, data) == "":
				st.repair(b.hex, data)
				actions.append({"action": "repair", "hex": b.hex})
	# A transport shot down is replaced as soon as there is money for it, and
	# an empty silo gets a new nuke.
	for port in st.of_role(data, "airport") + st.of_role(data, "docks") + st.of_role(data, "silo"):
		if st.can_replace_carrier(port.hex, data) == "":
			st.replace_carrier(port.hex, data)
			actions.append({"action": "replace_carrier", "hex": port.hex})
	# Troops seen coming: their counters jump the research queue.
	var queue: Array = research.duplicate()
	var threats: Array = []
	var enemy_boats: Array = view.boats[1 - side] if view.boats.size() == 2 else []
	var known_types := {}
	for h in view.enemy_knowledge:
		var kb = view.enemy_knowledge[h].get("building")
		if kb != null:
			known_types[String(kb["type"])] = true
	if not enemy_boats.is_empty() or known_types.has("docks") or view.enemy_boats_arrived > 0:
		threats.append_array(["coastal_cannon", "bunker"])
	if known_types.has("airport"):
		threats.append("bunker")
	for t in threats:
		queue.erase(t)
	queue = threats + queue
	# focus_research (a level may set it): one project at a time, the other
	# labs helping it, so each item comes sooner.
	var focus := bool(cfg.get("focus_research", false))
	for lab in st.of_role(data, "lab"):
		if st.project_for_lab(lab.id) != null:
			continue
		if focus and not st.projects.is_empty():
			break
		for item in queue:
			if st.can_start_research(lab.id, item, data) == "":
				st.start_research(lab.id, item, data)
				actions.append({"action": "research", "lab": lab.id, "item": item})
				break

	# Stored research goes straight into the oldest project.
	var first = st.oldest_project()
	if first != null and st.can_use_stored_research(String(first["item"]), data) == "":
		st.use_stored_research(String(first["item"]), data)
		actions.append({"action": "use_stored_research", "item": String(first["item"])})
	# Under threat, one of each counter goes up before the usual order.
	for t in threats:
		if st.building_unlocked(t, data) and st.count_role(data, data.role(t)) == 0 and st.money >= data.cost(t):
			var th := _place_strong(st, t, view)
			if th >= 0 and st.build(t, th, data, view.settings, view.round_number) == "":
				actions.append({"action": "build", "type": t, "hex": th})
	# A silo as soon as it is researched and affordable.
	if data.has_building("nuclear_silo") and st.building_unlocked("nuclear_silo", data) 			and st.count_role(data, "silo") == 0 and st.money >= data.cost("nuclear_silo"):
		var sh := _place_strong(st, "nuclear_silo", view)
		if sh >= 0 and st.build("nuclear_silo", sh, data, view.settings, view.round_number) == "":
			actions.append({"action": "build", "type": "nuclear_silo", "hex": sh})
	# Level 5: stealth silos from stealth.build_from_round, up to stealth.count.
	if data.has_building("stealth_silo") and st.building_unlocked("stealth_silo", data):
		var sc5: Dictionary = cfg["stealth"]
		while view.round_number >= int(sc5["build_from_round"]) and st.money >= data.cost("stealth_silo") \
				and st.buildings.values().filter(func(b): return b.type == "stealth_silo").size() < int(sc5["count"]):
			var sth := _place_strong(st, "stealth_silo", view)
			if sth < 0 or st.build("stealth_silo", sth, data, view.settings, view.round_number) != "":
				break
			actions.append({"action": "build", "type": "stealth_silo", "hex": sth})
	# Level 4: an enclave from spy.enclave_from_round, once there is money.
	if data.has_building("enclave") and st.building_unlocked("enclave", data) and st.count_role(data, "enclave") == 0 \
			and view.round_number >= int(cfg["spy"]["enclave_from_round"]) and st.money >= data.cost("enclave"):
		var eh := _place_strong(st, "enclave", view)
		if eh >= 0 and st.build("enclave", eh, data, view.settings, view.round_number) == "":
			actions.append({"action": "build", "type": "enclave", "hex": eh})
	while true:
		var type := _next_in_order(st)
		if type == "" or st.money < data.cost(type):
			break
		var hex := _place_strong(st, type, view)
		if hex < 0 or st.build(type, hex, data, view.settings, view.round_number) != "":
			break
		actions.append({"action": "build", "type": type, "hex": hex})
	if _next_in_order(st) == "" and st.count_role(data, "decoy") < int(view.settings["decoys_per_side"]):
		var hex := _place_strong(st, "decoy", view)
		if hex >= 0 and st.build("decoy", hex, data, view.settings, view.round_number) == "":
			actions.append({"action": "build", "type": "decoy", "hex": hex})
	return actions


## The next building to buy: the build order, then late_cycle repeated so
## the side keeps growing for as long as it has money. Refineries are passed
## over while stored fuel already covers fuel_reserve_rounds of firing.
## With skip_blocked_research, a building still waiting on research is
## passed over rather than holding the money.
func _next_in_order(st) -> String:
	var order: Array = _build_order().duplicate()
	var cycle: Array = cfg.get("late_cycle", [])
	if not cycle.is_empty():
		for k in LATE_CYCLE_REPEATS:
			order.append_array(cycle)
	var skip_blocked := bool(cfg.get("skip_blocked_research", false))
	var need := {}
	for type in order:
		need[type] = int(need.get(type, 0)) + 1
		var have := 0
		for b in st.buildings.values():
			if b.type == type:
				have += 1
		if have >= int(need[type]):
			continue
		if not st.building_unlocked(type, data):
			var req := String(data.building(type).get("requires", ""))
			if req != "" and research.has(req) and not skip_blocked:
				return ""
			continue
		if data.role(type) == "launcher" and not _can_fuel_another(st, type):
			continue
		if data.role(type) == "refinery" and _fuel_to_spare(st):
			continue
		return type
	return ""


const LATE_CYCLE_REPEATS := 20


## Fuel for one round of firing every launcher (plus `extra` more).
func _fuel_per_round(st, extra_type: String = "") -> int:
	var per_round := 0
	for b in st.of_role(data, "launcher"):
		per_round += _cheapest_fuel(b.type)
	if extra_type != "":
		per_round += _cheapest_fuel(extra_type)
	return per_round


## Stored fuel covers fuel_reserve_rounds of firing every launcher.
func _fuel_to_spare(st) -> bool:
	var rounds := int(cfg.get("fuel_reserve_rounds", 0))
	return rounds > 0 and st.fuel >= maxi(1, _fuel_per_round(st)) * rounds


## Another launcher is worth it if fuel income, plus a share of the fuel
## in store spread over fuel_reserve_rounds, pays for firing them all.
func _can_fuel_another(st, type: String) -> bool:
	var per_round := _fuel_per_round(st, type)
	var rounds := maxi(1, int(cfg.get("fuel_reserve_rounds", 1)))
	return per_round <= int(st.compute_income(data)["fuel"]) + st.fuel / rounds


## Placement that keeps other buildings from giving bases away and prefers
## ground the enemy hasn't seen.
func _place_strong(st, type: String, view) -> int:
	if bool(hc["plain_placement"]):
		return _place(st, type)
	var free := _empty_land(st)
	if bool(data.building(type).get("coastal", false)):
		free = free.filter(func(h): return st.island.is_coastal(h))
	if type == "decoy":
		free = free.filter(func(h): return st._base_spacing_error(h, data) == "")
	if free.is_empty():
		return -1
	var g = st.island.grid
	var pc: Dictionary = cfg["placement"]
	var seen: Dictionary = view.own_seen_by_enemy
	var bases: Array = st.of_role(data, "base")
	var keep := int(pc["keep_from_bases"])
	var unseen_w := float(pc["unseen_weight"])
	var common := func(h) -> float:
		var s := 0.0 if seen.has(h) else unseen_w
		for b in bases:
			if g.distance(h, b.hex) < keep:
				s -= 2.0
		return s
	match data.role(type):
		"anti_air":
			var radius := int(data.section("anti_air")["radius"])
			var w: Dictionary = cfg["anti_air_protect_weights"]
			var aas: Array = st.of_role(data, "anti_air")
			return _choose(free, func(h):
				var s: float = common.call(h)
				for b in st.buildings.values():
					if g.distance(h, b.hex) <= radius:
						var covered := 0
						for a in aas:
							if g.distance(a.hex, b.hex) <= radius:
								covered += 1
						s += float(w.get(data.role(b.type), w["default"])) / (1.0 + covered)
				return s)
		"radar":
			var ranges: Array = data.section("radar")["range_by_level"]
			var aas: Array = st.of_role(data, "anti_air")
			return _choose(free, func(h):
				var r := int(ranges[clampi(st.island.level[h], 0, ranges.size() - 1)])
				var s: float = common.call(h)
				for a in aas:
					if g.distance(h, a.hex) <= r:
						s += 3.0
				return s + 0.1 * st.island.level[h])
		"bunker":
			# Where it covers the most of what matters, bases above all.
			var reach := int(data.section("troops")["bunker_range"])
			var w2: Dictionary = cfg["troops"]["bunker_weights"]
			var bunkers: Array = st.of_role(data, "bunker")
			return _choose(free, func(h):
				var s: float = common.call(h)
				for b in st.buildings.values():
					if g.distance(h, b.hex) <= reach:
						var covered := 0
						for bk in bunkers:
							if g.distance(bk.hex, b.hex) <= reach:
								covered += 1
						s += float(w2.get(b.type, w2.get(data.role(b.type), w2["default"]))) / (1.0 + covered)
				return s)
		"coastal_cannon":
			var reach2 := int(data.section("troops")["cannon_range"])
			var w3: Dictionary = cfg["troops"]["cannon_weights"]
			return _choose(free, func(h):
				var s: float = common.call(h)
				for b in st.buildings.values():
					if st.island.is_coastal(b.hex) and g.distance(h, b.hex) <= reach2:
						s += float(w3.get(data.role(b.type), w3["default"]))
				return s)
		"decoy":
			var centre := _land_centre(st.island)
			return _choose(free, func(h): return common.call(h) + 2.0 - 0.2 * g.distance(h, centre))
		_:
			# Spread out so one blast or view doesn't take in several.
			return _choose(free, func(h):
				var s: float = common.call(h)
				for b in st.buildings.values():
					if not data.is_base_like(b.type) and g.distance(h, b.hex) <= 1:
						s -= 0.5
				return s + 0.05 * rng.rand_float())


# --- Search estimate -------------------------------------------------------

## Chance that each hex of a w x h space is land, from the island generator
## run on fixed seeds. Every player can learn this shape by playing, so it is
## fair knowledge; it uses no information about this match.
func _prior(w: int, h: int) -> PackedFloat32Array:
	var key := "%dx%d" % [w, h]
	if _land_prior_cache.has(key):
		return _land_prior_cache[key]
	var counts := PackedFloat32Array()
	counts.resize(w * h)
	var d = data.duplicate_data()
	d.rules["map"]["width"] = w
	d.rules["map"]["height"] = h
	for k in PRIOR_SAMPLES:
		var isl = Island.generate(d, Rng.derive(PRIOR_SEED + k, "prior"))
		for i in isl.grid.count:
			if isl.is_land(i):
				counts[i] += 1.0
	for i in counts.size():
		counts[i] /= PRIOR_SAMPLES
	_land_prior_cache[key] = counts
	return counts


## Probability-like weight that an enemy base is on each hex.
func _base_estimate(view, know: Dictionary) -> PackedFloat32Array:
	var g := _enemy_grid
	var prior := _prior(g.width, g.height)
	var est := PackedFloat32Array()
	est.resize(g.count)
	var blocked := {}
	for h in know:
		var b = know[h].get("building")
		if (b != null and String(b["type"]) in ["suspected_base", "decoy", "stronghold"]) or String(know[h].get("destroyed", "")) in ["base", "decoy", "stronghold"]:
			for n in g.within(h, 1):
				blocked[n] = true
	for h in view.enemy_bases_destroyed:
		for n in g.within(h, 1):
			blocked[n] = true
	for i in g.count:
		if know.has(i) or blocked.has(i):
			continue
		var p := prior[i]
		var known_n := 0
		var land_n := 0
		for n in g.neighbors(i):
			if know.has(n):
				known_n += 1
				if know[n]["land"]:
					land_n += 1
		if known_n > 0:
			p = 0.4 * p + 0.6 * float(land_n) / known_n
		est[i] = p
	return est


## How many enemy bases (or base-like pieces) are still unaccounted for.
func _bases_unfound(view, know: Dictionary) -> int:
	var found := 0
	for h in know:
		var b = know[h].get("building")
		if b != null and String(b["type"]) in ["suspected_base", "stronghold"]:
			found += 1
	return view.enemy_bases_left() + int(view.settings["decoys_per_side"]) - found


# --- Targeting -------------------------------------------------------------

func choose_targets(view) -> Array:
	var st = view.own
	if _enemy_grid == null:
		_enemy_grid = HexGrid.new(view.enemy_width, view.enemy_height)
	var g := _enemy_grid
	var know := _knowledge(view)
	var tc: Dictionary = cfg["targeting"]

	# Launchers we can fire this round, cheapest missile first per launcher.
	var shots: Array = []
	for b in st.of_role(data, "launcher"):
		if st.weapon_active(b):
			shots.append(b)
	var fuel: int = st.fuel

	# What we know is on their island.
	var aa_known: Array = []
	var weapons: Array = []     # [hex, priority]
	var bases: Array = []       # [hex, hits]
	var enemy_launchers_active := false
	var forts: Array = []       # known enemy strongholds: [hex, gun working]
	var live_bunkers: Array = []   # known enemy bunkers in action
	var wprio: Array = tc["weapon_priority"]
	var eprio: Array = tc.get("economy_priority", [])
	var economy: Array = []     # [hex, priority]
	for h in know:
		var b = know[h].get("building")
		if b == null:
			continue
		var t := String(b["type"])
		var active: bool = not b["disabled"] or b["repairing"]
		if (t == "anti_air" or (data.has_building(t) and data.mounts_anti_air(t))) and active:
			aa_known.append(h)
		if t == "stronghold":
			forts.append([h, active])
		if t == "bunker" and active:
			live_bunkers.append(h)
		if t == "suspected_base":
			bases.append([h, float(b["hits"])])
		elif eprio.has(t) and not b["disabled"]:
			economy.append([h, eprio.find(t)])
		elif wprio.has(t) and active:
			weapons.append([h, wprio.find(t)])
			if data.has_building(t) and data.role(t) == "launcher":
				enemy_launchers_active = true
	weapons.sort_custom(func(a, b): return a[1] < b[1] or (a[1] == b[1] and a[0] < b[0]))
	economy.sort_custom(func(a, b): return a[1] < b[1] or (a[1] == b[1] and a[0] < b[0]))
	bases.sort_custom(func(a, b): return a[1] > b[1] or (a[1] == b[1] and a[0] < b[0]))

	var aa_radius := int(data.section("anti_air")["radius"])
	var cover := func(h: int) -> int:
		var c := 0
		for a in aa_known:
			if a != h and g.distance(a, h) <= aa_radius:
				c += 1
		return c
	# For a transport, a stronghold's own gun covers its hex too.
	var air_cover := func(h: int) -> int:
		var c := 0
		for a in aa_known:
			if g.distance(a, h) <= aa_radius:
				c += 1
		return c

	# Build the wish list of [hex, purpose], most important first.
	var base_hits := float(data.building("base")["hits_to_destroy"])
	var hit_value := float(data.missile("basic")["base_hits"])
	var base_list: Array = []
	for e in bases:
		var need := maxi(1, ceili((base_hits - float(e[1])) / hit_value))
		need += mini(int(cover.call(e[0])), int(tc["max_extra_for_cover"]))
		for k in need:
			base_list.append(e[0])
	var weapon_list: Array = []
	for e in weapons:
		weapon_list.append(e[0])
		if int(cover.call(e[0])) > 0 and bool(tc["extra_for_covered_weapons"]):
			weapon_list.append(e[0])

	var orders: Array = []
	var planned_seen := {}
	var est := PackedFloat32Array()
	var unfound := _bases_unfound(view, know)
	var keep := int(tc["keep_for_bases"])
	var wish: Array = []
	if enemy_launchers_active:
		var weapon_shots := maxi(0, shots.size() - keep)
		wish = weapon_list.slice(0, weapon_shots)
		wish.append_array(base_list)
		wish.append_array(weapon_list.slice(weapon_shots))
	else:
		# No known threat: bases first, then the anti-air guarding them.
		wish = base_list.duplicate()
		var guard: Array = weapon_list.filter(func(h): return aa_known.has(h))
		wish.append_array(guard)
		wish.append_array(weapon_list.filter(func(h): return not aa_known.has(h)))
	# Known banks, labs and refineries (a spy's finds) after that, leaving the
	# usual shots for finding bases while some are still hidden.
	var eco_list: Array = economy.map(func(e): return e[0])
	if unfound > 0:
		eco_list = eco_list.slice(0, maxi(0, shots.size() - keep - wish.size()))
	wish.append_array(eco_list)

	# Siege: whenever we have troops to send, a known stronghold's gun and the
	# bunkers guarding it are knocked out first. A building hit this round is
	# out next round too (still broken, or under repair), so the troops that
	# follow get through.
	var have_troops: bool = not st.of_role(data, "airport").is_empty() or not st.of_role(data, "docks").is_empty()
	if have_troops and bool(cfg["strongholds"]["silence_gun_first"]):
		var bunker_reach := int(data.section("troops")["bunker_range"])
		var siege: Array = []
		for f in forts:
			if f[1]:
				siege.append(f[0])
			for bk in live_bunkers:
				if g.distance(bk, f[0]) <= bunker_reach and not siege.has(bk):
					siege.append(bk)
		siege.reverse()
		for h in siege:
			while wish.has(h):
				wish.erase(h)
			wish.push_front(h)

	# The nuke first: aimed where its blast does the most, if anything known
	# is worth it. Until it fires, its fuel is kept back from other shots.
	for silo in st.of_role(data, "silo"):
		if not st.weapon_active(silo) or silo.carrier_lost:
			continue
		var nuke_fuel := int(data.missile("nuke")["fuel"])
		var aim := _nuke_aim(know) if silo.loading == 0 and fuel >= nuke_fuel else -1
		if aim >= 0:
			orders.append({"launcher": silo.hex, "missile": "nuke", "target": aim})
			for h in g.within(aim, 1):
				while wish.has(h):
					wish.erase(h)
		fuel -= mini(fuel, nuke_fuel)   # spent now, or saved for it
	# Troop drops next: they are the strongest single strike.
	var money: int = st.money
	for enc in st.of_role(data, "enclave"):
		if not _enclave_free(view, st, enc):
			continue
		var spy_aim := _spy_aim(view, know, st, fuel, money, air_cover)
		if spy_aim >= 0:
			var sp: Dictionary = data.missile("spy")
			orders.append({"launcher": enc.hex, "missile": "spy", "target": spy_aim})
			fuel -= int(sp["fuel"])
			money -= int(sp.get("money", 0))
			_last_spy = view.round_number
	for port in st.of_role(data, "airport"):
		if not st.weapon_active(port):
			continue
		if port.carrier_lost:
			continue
		var t: Dictionary = data.missile("transport")
		if int(t["fuel"]) > fuel or int(t.get("money", 0)) > money:
			continue
		var plan := _plan_drop(know, air_cover)
		if plan.is_empty():
			continue
		orders.append({"launcher": port.hex, "missile": "transport", "target": plan["target"], "dir": plan["dir"]})
		fuel -= int(t["fuel"])
		money -= int(t.get("money", 0))
		for h in plan["path"]:
			while wish.has(h):
				wish.erase(h)
	# Boats: the same, onto known coast, wary of known coastal cannons.
	for dk in st.of_role(data, "docks"):
		if not st.weapon_active(dk) or dk.carrier_lost or dk.boat_out:
			continue
		var bm: Dictionary = data.missile("boat")
		if int(bm["fuel"]) > fuel or int(bm.get("money", 0)) > money:
			continue
		var cannon_reach := int(data.section("troops")["cannon_range"])
		var cannons: Array = []
		for h in know:
			var kb = know[h].get("building")
			if kb != null and String(kb["type"]) == "coastal_cannon":
				cannons.append(h)
		var guns := func(h: int) -> int:
			var c := 0
			for cn in cannons:
				if g.distance(cn, h) <= cannon_reach:
					c += 1
			return c
		var plan2 := _plan_drop(know, guns, true)
		if plan2.is_empty():
			continue
		orders.append({"launcher": dk.hex, "missile": "boat", "target": plan2["target"], "dir": plan2["dir"]})
		fuel -= int(bm["fuel"])
		money -= int(bm.get("money", 0))
	for b in shots:
		var target := -1
		var missile := ""
		if not wish.is_empty():
			missile = _attack_missile(st, b.type)
			target = wish.pop_front()
			if missile != "" and bool(data.missile(missile).get("anti_air_proof", false)):
				# A stealth missile goes where anti-air guards best.
				var pick := target
				for h in wish.slice(0, int(cfg["stealth"]["pick_from"]) - 1):
					if int(cover.call(h)) > int(cover.call(pick)):
						pick = h
				if pick != target:
					wish.erase(pick)
					wish.push_front(target)
					target = pick
			if missile != "" and int(data.missile(missile)["blast_radius"]) > 0:
				target = _best_blast_aim(target, know)
		elif unfound > 0:
			if est.is_empty():
				est = _base_estimate(view, know)
			missile = _search_missile(st, b.type, fuel)
			if missile == "":
				continue
			target = _search_aim(missile, est, planned_seen)
		else:
			continue
		if missile == "" or target < 0:
			continue
		var cost := int(data.missile(missile)["fuel"])
		if cost > fuel:
			# Fall back to a cheaper search shot if we can afford one.
			missile = _search_missile(st, b.type, fuel)
			if missile == "":
				continue
			if est.is_empty():
				est = _base_estimate(view, know)
			target = _search_aim(missile, est, planned_seen)
			cost = int(data.missile(missile)["fuel"])
			if target < 0 or cost > fuel:
				continue
		for h in g.within(target, int(data.missile(missile)["view_radius"])):
			planned_seen[h] = true
		orders.append({"launcher": b.hex, "missile": missile, "target": target})
		fuel -= cost
	return orders


## Where to send a foreign agent this round, or -1. When one is due
## (_spy_due) and the fuel and money are there, he lands where the most
## never-seen hexes lie within two of him, plus silo_weight for each known
## silo with a nuke he could reach and disarm in his first round, less
## cover_weight for each known anti-air gun reaching the hex; never on known
## sea, and on an unseen hex only within unknown_land_within of the centre
## (the island grows from there, so it is likely land).
func _spy_aim(view, know: Dictionary, st, fuel: int, money: int, air_cover: Callable) -> int:
	if not _spy_due(view, st):
		return -1
	var sp: Dictionary = data.missile("spy")
	if int(sp["fuel"]) > fuel or int(sp.get("money", 0)) > money:
		return -1
	var sc: Dictionary = cfg["spy"]
	var g = _enemy_grid
	var reach := int(sp["walks"]) - 1 + int(sp.get("disarm_range", 0))
	var silos: Array = []
	for h in view.enemy_knowledge:
		var kb = view.enemy_knowledge[h].get("building")
		if kb != null and kb.has("nuke") and String(kb["nuke"]) != "none":
			silos.append(int(h))
	var centre: int = g.center_index()
	var best := -1
	var best_s := -1.0e9
	for h in g.count:
		var k = view.enemy_knowledge.get(h)
		if k != null and not bool(k["land"]):
			continue
		if k == null and g.distance(h, centre) > int(sc["unknown_land_within"]):
			continue
		var s := 0.0
		for n in g.within(h, 2):
			if not view.enemy_knowledge.has(n):
				s += 1.0
		for silo in silos:
			if g.distance(h, silo) <= reach:
				s += float(sc["silo_weight"])
		s -= float(sc["cover_weight"]) * float(air_cover.call(h))
		if s > best_s:
			best_s = s
			best = h
	return best


## An enclave in action with no agent of its own on the enemy island.
func _enclave_free(view, st, enc) -> bool:
	return st.weapon_active(enc) and not view.own_spies.any(func(x): return int(x["enclave"]) == enc.id)


## Whether a foreign agent trip is due this round: an enclave is free, and it
## is at least from_round and every_rounds since the last trip.
func _spy_due(view, st) -> bool:
	if not data.rules["missiles"].has("spy"):
		return false
	if not st.of_role(data, "enclave").any(func(b): return _enclave_free(view, st, b)):
		return false
	var sc: Dictionary = cfg["spy"]
	return view.round_number >= int(sc["from_round"]) and view.round_number - _last_spy >= int(sc["every_rounds"])


## The best troop drop on what we know: every known building as a landing
## hex, every direction, the march followed over known ground (unknown
## hexes count as passable at the same height), stopping where a known
## bunker would wipe it out. Scored by what it would overrun, discounted by
## known anti-air over the landing hex. {} if nothing reaches min_value.
func _plan_drop(know: Dictionary, cover: Callable, coast_only: bool = false) -> Dictionary:
	var g := _enemy_grid
	var tc: Dictionary = data.section("troops")
	var ai_t: Dictionary = cfg["troops"]
	var vals: Dictionary = ai_t["values"]
	var reach := int(tc["platoon_march"])
	var bunker_range := int(tc["bunker_range"])
	var climb := bool(tc["platoon_can_climb"])
	var bunkers: Array = []
	for h in know:
		var b = know[h].get("building")
		if b != null and String(b["type"]) == "bunker" and (not b["disabled"] or b["repairing"]):
			bunkers.append(h)
	var guarded := func(h: int) -> bool:
		for bk in bunkers:
			if g.distance(bk, h) <= bunker_range:
				return true
		return false
	var best := {}
	var best_score := float(ai_t["min_value"])
	for start in know:
		var e: Dictionary = know[start]
		if e.get("building") == null or not bool(e["land"]) or guarded.call(start):
			continue
		if coast_only and not _known_coast(start, know):
			continue
		for dir in 6:
			var path: Array = [start]
			var here: int = start
			for k in reach:
				var n: int = g.step(here, dir)
				if n < 0:
					break
				var en = know.get(n)
				if en != null and not bool(en["land"]):
					break
				if en != null and not climb and int(en["level"]) > int(know[here]["level"] if know.has(here) else 0):
					break
				if guarded.call(n):
					break
				path.append(n)
				here = n
			var score := 0.0
			for h in path:
				var b = know.get(h, {}).get("building")
				if b != null:
					score += float(vals.get(String(b["type"]), vals["default"]))
			score /= 1.0 + float(cover.call(start))
			if score > best_score:
				best_score = score
				best = {"target": start, "dir": dir, "path": path}
	return best


## The known hex where a nuke does the most: what stands on it counts at
## the centre value, what is around it at the ring value. -1 if nothing
## reaches min_value.
func _nuke_aim(know: Dictionary) -> int:
	var g := _enemy_grid
	var nc: Dictionary = cfg["nukes"]
	var vals: Dictionary = nc["values"]
	var ring: Dictionary = nc["ring_values"]
	var worth := func(h: int, table: Dictionary) -> float:
		var b = know.get(h, {}).get("building")
		if b == null:
			return 0.0
		return float(table.get(String(b["type"]), table["default"]))
	var best := -1
	var best_score := float(nc["min_value"]) - 0.001
	var cands := {}
	for h in know:
		if know[h].get("building") != null:
			for n in g.within(h, 1):
				cands[n] = true
	var keys := cands.keys()
	keys.sort()
	for c in keys:
		var s: float = worth.call(c, vals)
		for n in g.neighbors(c):
			var b = know.get(n, {}).get("building")
			# A base that has already taken a hit falls to the edge of the blast too.
			if b != null and String(b["type"]) == "suspected_base" and float(b["hits"]) >= 1.0:
				s += float(vals["suspected_base"])
			else:
				s += worth.call(n, ring)
		if s > best_score:
			best_score = s
			best = c
	return best


## A hex we know is land with known sea (or the edge of the space) beside it.
func _known_coast(h: int, know: Dictionary) -> bool:
	var ns: PackedInt32Array = _enemy_grid.neighbors(h)
	if ns.size() < 6:
		return true
	for n in ns:
		var e = know.get(n)
		if e != null and not bool(e["land"]):
			return true
	return false


## For a missile with a wide blast: aim at the neighbour of `target` (or the
## target itself) that catches the most known enemy pieces.
func _best_blast_aim(target: int, know: Dictionary) -> int:
	var g := _enemy_grid
	var cands: Array = Array(g.within(target, 1))
	return _best(cands, func(h):
		var s := 0.0
		for n in g.within(h, 1):
			var e = know.get(n)
			if e != null and e.get("building") != null:
				s += 2.0 if n == target else 1.0
		return s)


## The missile to search with: scouting if unlocked and affordable (it sees
## far more for its fuel), otherwise the launcher's attack missile.
func _search_missile(st, launcher_type: String, fuel: int) -> String:
	var best := ""
	var best_ratio := -1.0
	for mt in data.building(launcher_type)["missiles"]:
		if not st.missile_unlocked(mt, data):
			continue
		var def: Dictionary = data.missile(mt)
		var f := int(def["fuel"])
		if f > fuel:
			continue
		var r := int(def["view_radius"])
		var ratio := float(1 + 3 * r * (r + 1)) / maxf(1.0, f)
		if ratio > best_ratio:
			best_ratio = ratio
			best = mt
	return best


## Where to look next: among the aims that would uncover nearly as much
## likely ground as the best one (within search_spread of it), one picked at
## random, weighted by how much it uncovers. So the opening shots differ from
## match to match instead of always landing in the middle.
func _search_aim(missile: String, est: PackedFloat32Array, planned_seen: Dictionary) -> int:
	var g := _enemy_grid
	var radius := int(data.missile(missile)["view_radius"])
	var candidates: Array = range(g.count)
	var score := func(h):
		var s := 0.0
		for n in g.within(h, radius):
			if planned_seen.has(n):
				continue
			s += est[n]
		return s + 0.5 * est[h]
	var spread := float(cfg.get("search_spread", 0.0))
	if spread <= 0.0:
		return _choose(candidates, score)
	var scores := {}
	var top := 0.0
	for h in candidates:
		scores[h] = float(score.call(h))
		top = maxf(top, scores[h])
	if top <= 0.0:
		return _choose(candidates, score)
	var pool: Array = candidates.filter(func(h): return scores[h] >= top * (1.0 - spread))
	var total := 0.0
	for h in pool:
		total += scores[h]
	var r: float = rng.rand_float() * total
	for h in pool:
		r -= scores[h]
		if r <= 0.0:
			return h
	return pool[-1]
