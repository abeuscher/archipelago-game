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
