## Projection math for the isometric view (no rendering needed).
extends "res://tests/test_case.gd"

const Iso = preload("res://game/iso.gd")


func test_six_rotations_return_to_start() -> void:
	var iso := Iso.new(HexGrid.new(15, 15))
	var start := iso.plane(40)
	for k in 6:
		iso.rotation_step = k
		eq(iso.top_polygon(40, 0, true).size(), 6, "hex outline")
	iso.rotation_step = 6 % 6
	check(iso.plane(40).is_equal_approx(start), "full turn")


func test_rotation_keeps_neighbour_spacing() -> void:
	var g := HexGrid.new(15, 15)
	var iso := Iso.new(g)
	var c := g.center_index()
	for k in 6:
		iso.rotation_step = k
		for n in g.neighbors(c):
			check(is_equal_approx(iso.plane(c).distance_to(iso.plane(n)), Iso.HEX_SIZE * sqrt(3.0)), "neighbour spacing")


func test_higher_hex_drawn_higher() -> void:
	var iso := Iso.new(HexGrid.new(15, 15))
	check(iso.top_center(50, 2, true).y < iso.top_center(50, 0, true).y, "top level drawn further up")
	check(iso.top_center(50, 0, true).y < iso.top_center(50, 0, false).y, "land above sea")


func test_draw_order_back_to_front() -> void:
	var iso := Iso.new(HexGrid.new(15, 15))
	for k in 6:
		iso.rotation_step = k
		var order: Array = iso.draw_order()
		for i in range(1, order.size()):
			check(iso.plane(order[i - 1]).y <= iso.plane(order[i]).y + 0.001, "sorted by depth")


func test_edge_neighbor_matches_the_drawn_outline() -> void:
	const BoardView = preload("res://game/board_view.gd")
	var g = HexGrid.new(9, 9)
	var bv = BoardView.new()
	bv.setup(g)
	var i: int = g.center_index()
	for r in 6:
		bv.iso.rotation_step = r
		var c: Vector2 = bv.iso.top_center(i, 0, false)
		var top: PackedVector2Array = bv.iso.top_polygon(i, 0, false)
		for k in 6:
			var n: int = bv.edge_neighbor(i, k)
			check(n >= 0, "inner hex has all neighbours")
			var expect: Vector2 = c + ((top[k] + top[(k + 1) % 6]) / 2.0 - c) * 2.0
			check(bv.iso.top_center(n, 0, false).distance_to(expect) < 0.5, "edge %d, rotation %d faces its neighbour" % [k, r])
	bv.free()


# --- Batch: shapes collected into one triangle list ------------------------

const Batch = preload("res://game/batch.gd")


func test_interface_scales_with_the_window() -> void:
	# Without a stretch mode the panels are drawn in physical pixels and come
	# out half size on a Retina Mac while the board fills the window.
	eq(ProjectSettings.get_setting("display/window/stretch/mode"), "canvas_items")
	eq(ProjectSettings.get_setting("display/window/stretch/aspect"), "expand")


func test_batch_polygon_is_triangulated_as_godot_does() -> void:
	var node := Node2D.new()
	var g := Batch.new(node)
	var hex := Iso.hex_at(Vector2(10, 10))
	g.draw_colored_polygon(hex, Color.RED)
	eq(g._pts.size(), Geometry2D.triangulate_polygon(hex).size(), "same triangles as Godot's own polygon")
	eq(g._pts.size(), 12, "a hex is four triangles")
	check(g._cols.has(Color.RED) and g._cols.count(Color.RED) == 12, "every vertex in the polygon's colour")
	node.free()


func test_batch_line_matches_godot_geometry() -> void:
	var node := Node2D.new()
	var g := Batch.new(node)
	g.draw_line(Vector2(0, 0), Vector2(10, 0), Color.WHITE, 2.0)
	eq(g._pts.size(), 6, "a plain line is one quad")
	check(is_equal_approx(absf(g._pts[0].y - g._pts[1].y), 2.0), "full width without antialiasing")
	g = Batch.new(node)
	g.draw_line(Vector2(0, 0), Vector2(10, 0), Color.WHITE, 1.2, true)
	eq(g._pts.size(), 9 * 6, "antialiased: the line, four feathered edges and four corners")
	check(is_equal_approx(absf(g._pts[0].y - g._pts[1].y), 0.6), "width compensated for the feather, as Godot 4.7")
	eq(g._cols[1].a, 1.0, "the line itself is solid")
	node.free()


func test_batch_polyline_strip_counts() -> void:
	var node := Node2D.new()
	var g := Batch.new(node)
	var pts := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10)])
	g.draw_polyline(pts, Color.WHITE, 2.0)
	eq(g._pts.size(), (pts.size() * 2 - 2) * 3, "plain: one strip")
	g = Batch.new(node)
	g.draw_polyline(pts, Color.WHITE, 2.0, true)
	var n := pts.size()
	eq(g._pts.size(), ((n * 2 + 4 - 2) + 2 * (n * 2 + 5 - 2)) * 3, "antialiased open line: middle strip and two feathers")
	g = Batch.new(node)
	g.flush()   # nothing collected: no command, no error
	eq(g._pts.size(), 0, "empty")
	node.free()
