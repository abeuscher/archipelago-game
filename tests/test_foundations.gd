## Seeded dice, hex maths, island generation, data hygiene.
extends "res://tests/test_case.gd"


func test_rng_same_seed_same_sequence() -> void:
	var a = Rng.new(12345)
	var b = Rng.new(12345)
	for i in 200:
		eq(a.next_u32(), b.next_u32(), "draw %d" % i)


func test_rng_streams_differ() -> void:
	var a = Rng.derive(7, "dice")
	var b = Rng.derive(7, "island_0")
	var same := 0
	for i in 50:
		if a.next_u32() == b.next_u32():
			same += 1
	check(same < 3, "derived streams should not match")


func test_rng_range_and_uniformity() -> void:
	var r = Rng.new(99)
	var counts := [0, 0, 0, 0, 0, 0]
	for i in 6000:
		var v: int = r.rand_int(1, 6)
		check(v >= 1 and v <= 6, "out of range %d" % v)
		counts[v - 1] += 1
	for c in counts:
		check(c > 850 and c < 1150, "die face count %d looks biased" % c)
	for i in 1000:
		var f: float = r.rand_float()
		check(f >= 0.0 and f < 1.0, "randf out of range")


func test_rng_shuffle_is_permutation() -> void:
	var r = Rng.new(3)
	var arr := range(20)
	r.shuffle(arr)
	var sorted := arr.duplicate()
	sorted.sort()
	eq(sorted, range(20), "shuffle")


## Regression: bare randf()/randi_range() inside the class used to resolve to
## the engine's unseeded globals, so pick/chance/shuffle were not repeatable.
func test_rng_helpers_are_seeded() -> void:
	var picks: Array = []
	for k in 2:
		var r = Rng.new(11)
		var arr := range(30)
		r.shuffle(arr)
		picks.append([r.pick(range(100)), r.chance(0.5), r.rand_int(0, 1000), arr])
	eq(picks[0], picks[1], "seeded helpers repeat")


func test_rng_copy_continues_identically() -> void:
	var r = Rng.new(5)
	r.next_u32()
	var c = r.copy()
	eq(r.next_u32(), c.next_u32(), "copy")


func test_hex_distance_and_rings() -> void:
	var g := HexGrid.new(15, 15)
	var c := g.center_index()
	eq(g.neighbors(c).size(), 6, "interior neighbours")
	eq(g.within(c, 1).size(), 7, "radius 1")
	eq(g.within(c, 2).size(), 19, "radius 2")
	eq(g.within(c, 3).size(), 37, "radius 3")
	for n in g.neighbors(c):
		eq(g.distance(c, n), 1, "neighbour distance")
	eq(g.neighbors(g.index_of(0, 0)).size(), 2, "corner (0,0) neighbours")
	for a in [0, 17, 100, 224]:
		for b in [3, 50, 112, 200]:
			eq(g.distance(a, b), g.distance(b, a), "symmetry")


func test_island_shape() -> void:
	var d = data()
	for seed_in in [1, 2, 3, 4, 5, 77, 1000]:
		var isl = Island.generate(d, Rng.derive(seed_in, "island_0"))
		eq(isl.land_count(), floori(225 * 0.70), "land count seed %d" % seed_in)
		# Connected.
		var land = isl.land_hexes()
		var seen := {land[0]: true}
		var stack := [land[0]]
		while not stack.is_empty():
			var h = stack.pop_back()
			for n in isl.grid.neighbors(h):
				if isl.is_land(n) and not seen.has(n):
					seen[n] = true
					stack.append(n)
		eq(seen.size(), land.size(), "island connected seed %d" % seed_in)
		# Three levels, top near the middle.
		var levels := {}
		var top_far := 0
		var top_count := 0
		for h in land:
			levels[isl.level[h]] = true
			if isl.level[h] == 2:
				top_count += 1
				if isl.grid.distance(h, isl.grid.center_index()) > 4:
					top_far += 1
		eq(levels.size(), 3, "levels seed %d" % seed_in)
		check(top_count > 0 and top_far * 4 < top_count, "hill should sit toward the middle, seed %d" % seed_in)


func test_island_deterministic() -> void:
	var d = data()
	var a = Island.generate(d, Rng.derive(42, "island_1"))
	var b = Island.generate(d, Rng.derive(42, "island_1"))
	eq(a.land, b.land, "land")
	eq(a.level, b.level, "level")


## All randomness must go through rules/rng.gd.
func test_no_engine_randomness_in_rules_or_ai() -> void:
	var banned := ["randi(", "randf(", "randomize(", "RandomNumberGenerator", "randi_range(", "randf_range(", "shuffle()", "pick_random("]
	for dir in ["res://rules", "res://ai"]:
		if not DirAccess.dir_exists_absolute(dir):
			continue
		for f in DirAccess.get_files_at(dir):
			if not f.ends_with(".gd") or f == "rng.gd":
				continue
			var text := FileAccess.get_file_as_string(dir + "/" + f)
			for line in text.split("\n"):
				var code := line.strip_edges()
				if code.begins_with("#"):
					continue
				for word in banned:
					if code.contains(word):
						failures.append("%s/%s uses %s: %s" % [dir, f, word, code])


## The rules layer must not touch scenes or rendering.
func test_rules_layer_has_no_scene_dependencies() -> void:
	var banned := ["extends Node", "get_tree(", "preload(\"res://game", "load(\"res://game", "CanvasItem", "Sprite2D", "Input."]
	for dir in ["res://rules", "res://ai"]:
		if not DirAccess.dir_exists_absolute(dir):
			continue
		for f in DirAccess.get_files_at(dir):
			if not f.ends_with(".gd"):
				continue
			var text := FileAccess.get_file_as_string(dir + "/" + f)
			for word in banned:
				if text.contains(word):
					failures.append("%s/%s contains %s" % [dir, f, word])
