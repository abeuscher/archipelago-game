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
