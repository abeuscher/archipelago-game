## Terrain for one side's space: which hexes are land and at what level.
## Ocean is not land and sits at the ocean level from data (base level).
extends RefCounted

const HexGrid = preload("res://rules/hex_grid.gd")

var grid: HexGrid
var land: PackedByteArray
var level: PackedInt32Array


func _init(g: HexGrid) -> void:
	grid = g
	land = PackedByteArray()
	land.resize(g.count)
	level = PackedInt32Array()
	level.resize(g.count)


func is_land(index: int) -> bool:
	return land[index] == 1


func land_count() -> int:
	var n := 0
	for v in land:
		n += v
	return n


func land_hexes() -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in grid.count:
		if land[i] == 1:
			out.append(i)
	return out


func duplicate_island():
	var c = get_script().new(grid)
	c.land = land.duplicate()
	c.level = level.duplicate()
	return c


## Grow an island from the centre, then raise a hill near the middle.
static func generate(data, rng):
	var m: Dictionary = data.section("map")
	var g := HexGrid.new(int(m["width"]), int(m["height"]))
	var script: GDScript = load("res://rules/island.gd")
	var isl = script.new(g)
	var ocean_level := int(data.section("elevation")["ocean_level"])
	for i in g.count:
		isl.level[i] = ocean_level

	var target := floori(g.count * float(m["land_fraction"]))
	var bias := float(m["growth_center_bias"])
	var noise_min := float(m["growth_noise_min"])
	var center := g.center_index()

	var noise := PackedFloat32Array()
	noise.resize(g.count)
	for i in g.count:
		noise[i] = noise_min + rng.rand_float() * (1.0 - noise_min)

	var in_frontier := {}
	var frontier: Array[int] = []
	isl.land[center] = 1
	var placed := 1
	for n in g.neighbors(center):
		frontier.append(n)
		in_frontier[n] = true

	while placed < target and not frontier.is_empty():
		var total := 0.0
		var weights := PackedFloat32Array()
		for f in frontier:
			var w := noise[f] / pow(1.0 + g.distance(f, center), bias)
			weights.append(w)
			total += w
		var roll: float = rng.rand_float() * total
		var pick := frontier.size() - 1
		for k in frontier.size():
			roll -= weights[k]
			if roll < 0.0:
				pick = k
				break
		var chosen := frontier[pick]
		frontier.remove_at(pick)
		isl.land[chosen] = 1
		placed += 1
		for n in g.neighbors(chosen):
			if isl.land[n] == 0 and not in_frontier.has(n):
				frontier.append(n)
				in_frontier[n] = true

	_raise_hill(isl, data, rng)
	return isl


static func _raise_hill(isl, data, rng) -> void:
	var m: Dictionary = data.section("map")
	var g: HexGrid = isl.grid
	var levels := int(m["levels"])
	var center := g.center_index()

	var near_center: Array = []
	for i in g.within(center, int(m["hill_center_jitter"])):
		if isl.is_land(i):
			near_center.append(i)
	var hill: int = rng.pick(near_center) if not near_center.is_empty() else center

	var land: PackedInt32Array = isl.land_hexes()
	var scored: Array = []
	var hill_noise := float(m["hill_noise"])
	for i in land:
		scored.append([g.distance(i, hill) + rng.rand_float() * hill_noise, i])
	scored.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))

	# Fractions of land at each level, from the top level downward. Whatever
	# is left over is base level (0).
	var fractions: Array = m["hill_level_fractions_from_top"]
	var thresholds: Array[int] = []
	var running := 0
	for f in fractions:
		running += roundi(land.size() * float(f))
		thresholds.append(running)
	for k in scored.size():
		var idx: int = scored[k][1]
		var lvl := 0
		for t in thresholds.size():
			if k < thresholds[t]:
				lvl = maxi(0, levels - 1 - t)
				break
		isl.level[idx] = lvl
