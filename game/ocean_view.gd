## The sea the two islands sit in: every lattice hex around and between the
## boards that no board covers, drawn under both boards. It is always
## visible, so the channel between the islands is open water and the fog on
## the enemy space starts at its edge. Presentation only: the rules space,
## targeting and the AI know nothing of it.
extends Node2D

const Iso = preload("res://game/iso.gd")
const Palette = preload("res://game/palette.gd")
const MARGIN_HEXES := 2       ## open sea beyond the outermost island hex

var cells: Array = []         ## screen centres of the sea hexes
var _rect := Rect2()          ## screen bounds of the whole sea


## Recomputes the sea for the boards' current rotation and positions.
## Each board's position must be its centre hex on the lattice.
func rebuild(boards: Array) -> void:
	var occupied := {}
	var plane_rect := Rect2()
	var first := true
	for b in boards:
		var origin := Vector2(b.position.x, b.position.y / Iso.SQUASH)
		for i in b.iso.grid.count:
			var p: Vector2 = origin + b.iso.plane(i)
			occupied[Iso.plane_axial(p)] = true
			if first:
				plane_rect = Rect2(p, Vector2.ZERO)
				first = false
			else:
				plane_rect = plane_rect.expand(p)
	plane_rect = plane_rect.grow(Iso.HEX_W * MARGIN_HEXES)
	cells = []
	var r0 := floori(plane_rect.position.y / Iso.ROW_H)
	var r1 := ceili(plane_rect.end.y / Iso.ROW_H)
	for r in range(r0, r1 + 1):
		var q0 := floori(plane_rect.position.x / Iso.HEX_W - r / 2.0)
		var q1 := ceili(plane_rect.end.x / Iso.HEX_W - r / 2.0)
		for q in range(q0, q1 + 1):
			var a := Vector2i(q, r)
			var p := Iso.axial_plane(a)
			if not plane_rect.has_point(p) or occupied.has(a):
				continue
			cells.append(Vector2(p.x, p.y * Iso.SQUASH))
	_rect = Rect2(Vector2(plane_rect.position.x, plane_rect.position.y * Iso.SQUASH),
		Vector2(plane_rect.size.x, plane_rect.size.y * Iso.SQUASH)).grow(Iso.HEX_SIZE)
	queue_redraw()


## Screen bounds of the sea, which contains both islands.
func world_rect() -> Rect2:
	return _rect


func _draw() -> void:
	for c in cells:
		var poly := Iso.hex_at(c)
		draw_colored_polygon(poly, Palette.SEA)
		var closed := poly.duplicate()
		closed.append(poly[0])
		draw_polyline(closed, Palette.SEA_LINE, 1.0)
		Palette.draw_wave(self, c, Palette.hash_v(c))
