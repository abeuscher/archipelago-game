## A simple, fair enemy AI. It sees only a SideView: its own island in full
## and the opposing space as its strikes have revealed it. All behaviour
## numbers come from data/ai.json ("simple").
##
## Interface used by every AI:
##   choose_setup(view)   -> {"bases": [hex...], "decoys": [hex...]}
##   choose_build(view)   -> [build action...] (MatchState.build_action format)
##   choose_targets(view) -> [launch order...] (MatchState.set_launch_orders format)
extends RefCounted

const Rng = preload("res://rules/rng.gd")
const HexGrid = preload("res://rules/hex_grid.gd")

var side: int
var data
var cfg: Dictionary
var rng
var _enemy_grid: HexGrid


func _init(side_index: int, game_data, match_seed: int) -> void:
	side = side_index
	data = game_data
	cfg = game_data.ai["simple"]
	rng = Rng.derive(match_seed, "ai_%d" % side_index)


# --- Setup -----------------------------------------------------------------

func choose_setup(view) -> Dictionary:
	var st = view.own
	var g = st.island.grid
	var per_side: int = data.integer("bases", "per_side")
	var decoys := 0
	if bool(cfg["buy_decoys_at_setup"]):
		decoys = mini(int(view.settings["decoys_per_side"]), st.money / data.cost("decoy"))
	var wanted := per_side + decoys
	var land: Array = Array(st.island.land_hexes())
	rng.shuffle(land)
	# Try the configured spacing first, then relax down to "not adjacent".
	var chosen: Array = []
	var spacing := int(cfg["base_min_spacing"])
	while spacing >= 2:
		chosen = []
		for h in land:
			var fits := true
			for c in chosen:
				if g.distance(h, c) < spacing:
					fits = false
					break
			if fits:
				chosen.append(h)
				if chosen.size() == wanted:
					break
		if chosen.size() == wanted:
			break
		spacing -= 1
	return {"bases": chosen.slice(0, per_side), "decoys": chosen.slice(per_side)}


# --- Build and repair ------------------------------------------------------

func choose_build(view) -> Array:
	var st = view.own   # a copy: we apply our own actions to keep it consistent
	var actions: Array = []

	for type in cfg["repair_priority"]:
		for b in st.buildings_sorted():
			if b.type == type and st.can_repair(b.hex, data) == "":
				st.repair(b.hex, data)
				actions.append({"action": "repair", "hex": b.hex})

	_buy_research(st, cfg["research_order"], actions)

	while true:
		var type := _next_in_order(st)
		if type == "":
			break
		if st.money < data.cost(type):
			break
		var hex := _place(st, type)
		if hex < 0 or st.build(type, hex, data, view.settings, view.round_number) != "":
			break
		actions.append({"action": "build", "type": type, "hex": hex})

	if _next_in_order(st) == "" and st.count_role(data, "decoy") < int(view.settings["decoys_per_side"]):
		var hex := _place(st, "decoy")
		if hex >= 0 and st.build("decoy", hex, data, view.settings, view.round_number) == "":
			actions.append({"action": "build", "type": "decoy", "hex": hex})
	return actions


## The first build-order entry not yet satisfied. Rebuilds anything lost.
## Research in order: the next item it can research is bought as soon as
## the money and points are there, then the one after. Returns the money to
## keep back for the next item once its points are in hand (0 if none).
func _buy_research(st, queue: Array, actions: Array) -> int:
	for item in queue:
		if st.research_block(item, data) != "":
			continue   # done, not in this level, or waiting on other research
		if st.can_research(item, data) == "":
			st.do_research(item, data)
			actions.append({"action": "research", "item": item})
			continue
		var cost := int(data.research_item(item)["cost"])
		return cost if st.research >= int(data.research_item(item)["points"]) else 0
	return 0


## Waits on items still being researched; skips launchers it cannot fuel.
func _next_in_order(st) -> String:
	var need := {}
	for type in cfg["build_order"]:
		need[type] = int(need.get(type, 0)) + 1
		var have := 0
		for b in st.buildings.values():
			if b.type == type:
				have += 1
		if have >= int(need[type]):
			continue
		if not st.building_unlocked(type, data):
			var req := String(data.building(type).get("requires", ""))
			if req != "" and cfg["research_order"].has(req):
				return ""      # wait for the research
			continue
		if data.role(type) == "launcher" and not _can_fuel_another(st, type):
			continue
		return type
	return ""


func _can_fuel_another(st, type: String) -> bool:
	var per_round := 0
	for b in st.of_role(data, "launcher"):
		per_round += _cheapest_fuel(b.type)
	per_round += _cheapest_fuel(type)
	return per_round <= int(st.compute_income(data)["fuel"])


func _cheapest_fuel(launcher_type: String) -> int:
	var best := -1
	for m in data.building(launcher_type)["missiles"]:
		var f := int(data.missile(m)["fuel"])
		if int(data.missile(m)["damage_max"]) > 0 and (best < 0 or f < best):
			best = f
	return maxi(best, 0)


func _empty_land(st) -> Array:
	var out: Array = []
	for h in st.island.land_hexes():
		if not st.buildings.has(h):
			out.append(h)
	return out


func _place(st, type: String) -> int:
	var free := _empty_land(st)
	if type == "decoy":
		free = free.filter(func(h): return st._base_spacing_error(h, data) == "")
	if free.is_empty():
		return -1
	var g = st.island.grid
	match data.role(type):
		"anti_air":
			var radius := int(data.section("anti_air")["radius"])
			var w: Dictionary = cfg["anti_air_protect_weights"]
			return _best(free, func(h):
				var s := 0.0
				for b in st.buildings.values():
					if g.distance(h, b.hex) <= radius:
						s += float(w.get(data.role(b.type), w["default"]))
				return s)
		"radar":
			var ranges: Array = data.section("radar")["range_by_level"]
			var aas: Array = st.of_role(data, "anti_air")
			return _best(free, func(h):
				var r := int(ranges[clampi(st.island.level[h], 0, ranges.size() - 1)])
				var s := 0.0
				for a in aas:
					if g.distance(h, a.hex) <= r:
						s += 1.0
				return s + 0.01 * st.island.level[h])
		_:
			return rng.pick(free)


## Highest-scoring item; ties broken by the AI's own dice.
func _best(items: Array, score: Callable) -> int:
	var best_score := -INF
	var best: Array = []
	for it in items:
		var s: float = score.call(it)
		if s > best_score + 1e-9:
			best_score = s
			best = [it]
		elif absf(s - best_score) <= 1e-9:
			best.append(it)
	return rng.pick(best) if not best.is_empty() else -1


# --- Targeting -------------------------------------------------------------

func choose_targets(view) -> Array:
	var st = view.own
	if _enemy_grid == null:
		_enemy_grid = HexGrid.new(view.enemy_width, view.enemy_height)
	var queue := _known_targets(view)
	var planned_seen := {}
	var fuel: int = st.fuel
	var orders: Array = []
	for b in st.of_role(data, "launcher"):
		if not st.weapon_active(b):
			continue
		var missile := _attack_missile(st, b.type)
		if missile == "":
			continue
		var cost := int(data.missile(missile)["fuel"])
		if cost > fuel:
			continue
		var target := -1
		if not queue.is_empty():
			target = queue.pop_front()
		else:
			target = _search_target(view, missile, planned_seen)
		if target < 0:
			continue
		for h in _enemy_grid.within(target, int(data.missile(missile)["view_radius"])):
			planned_seen[h] = true
		orders.append({"launcher": b.hex, "missile": missile, "target": target})
		fuel -= cost
	return orders


func _attack_missile(st, launcher_type: String) -> String:
	for m in data.building(launcher_type)["missiles"]:
		if int(data.missile(m)["damage_max"]) > 0 and st.missile_unlocked(m, data):
			return m
	return ""


## Known targets in priority order. A suspected base appears once per hit it
## still needs, so several launchers can finish it in one round.
func _known_targets(view) -> Array:
	var by_type := {}
	for h in view.enemy_knowledge:
		var e: Dictionary = view.enemy_knowledge[h]
		var b = e.get("building")
		if b == null or b["disabled"]:
			continue
		var t := String(b["type"])
		if not by_type.has(t):
			by_type[t] = []
		by_type[t].append([h, float(b["hits"])])
	var base_hits := float(data.building("base")["hits_to_destroy"])
	var hit_value := float(data.missile("basic")["base_hits"])
	var queue: Array = []
	for t in cfg["target_priority"]:
		var list: Array = by_type.get(t, [])
		list.sort_custom(func(a, b): return a[1] > b[1] or (a[1] == b[1] and a[0] < b[0]))
		for entry in list:
			var copies := 1
			if t == "suspected_base":
				copies = maxi(1, ceili((base_hits - float(entry[1])) / hit_value))
			for c in copies:
				queue.append(entry[0])
	return queue


## Aim where the most unexplored ground falls inside the missile's view,
## with a mild pull toward the centre where the island is likely to be.
func _search_target(view, missile: String, planned_seen: Dictionary) -> int:
	var g := _enemy_grid
	var radius := int(data.missile(missile)["view_radius"])
	var center := g.center_index()
	var max_d := float(maxi(1, g.distance(0, center)))
	var bias := float(cfg["search_center_bias"])
	var candidates: Array = range(g.count)
	return _best(candidates, func(h):
		var s := 0.0
		for n in g.within(h, radius):
			if view.enemy_knowledge.has(n) or planned_seen.has(n):
				continue
			s += 1.0 + bias * (1.0 - g.distance(n, center) / max_d)
		return s)
