## Isometric projection for a hex space: a fixed viewing angle, six board
## rotations in 60-degree steps, and height drawn as vertical offset.
## Presentation only: these are drawing sizes, not game rules.
extends RefCounted

const HEX_SIZE := 30.0         ## Hex radius on the board plane, in pixels.
const SQUASH := 0.58           ## Vertical squash that fakes the camera tilt.
const LEVEL_HEIGHT := 14.0     ## Screen pixels per elevation level.
const LAND_BASE := 6.0         ## Base-level land sits this far above the sea.

const AXIAL_DIRS := [Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)]

var grid
var rotation_step: int = 0     ## 0..5, each step turns the board 60 degrees.
var frame: Array = []          ## Axial coords of the sea ring drawn around the grid (presentation only).
var _center_plane: Vector2


func _init(g) -> void:
	grid = g
	_center_plane = Vector2.ZERO
	var sum := Vector2.ZERO
	for i in g.count:
		sum += _plane_raw(i)
	_center_plane = sum / g.count
	var seen := {}
	for i in g.count:
		var a: Vector2i = g.axial_of(i)
		for d in AXIAL_DIRS:
			var n: Vector2i = a + d
			if g.axial_to_index(n) < 0 and not seen.has(n):
				seen[n] = true
				frame.append(n)


func _plane_raw(index: int) -> Vector2:
	return _plane_axial_raw(grid.axial_of(index))


func _plane_axial_raw(a: Vector2i) -> Vector2:
	return Vector2(HEX_SIZE * sqrt(3.0) * (a.x + a.y / 2.0), HEX_SIZE * 1.5 * a.y)


## Sea-level top face of the k-th hex of the surrounding sea ring.
func frame_polygon(k: int) -> PackedVector2Array:
	var p := (_plane_axial_raw(frame[k]) - _center_plane).rotated(rotation_step * PI / 3.0)
	return _hex_at(Vector2(p.x, p.y * SQUASH))


## Board-plane position after rotation, centred on the space.
func plane(index: int) -> Vector2:
	return (_plane_raw(index) - _center_plane).rotated(rotation_step * PI / 3.0)


func height_px(level: int, land: bool) -> float:
	if not land:
		return 0.0
	return LAND_BASE + level * LEVEL_HEIGHT


## Screen position of the centre of a hex's top face.
func top_center(index: int, level: int, land: bool) -> Vector2:
	var p := plane(index)
	return Vector2(p.x, p.y * SQUASH - height_px(level, land))


## Corners of the top face. Pointy-top hexes map onto themselves under a
## 60-degree turn, so the outline is the same in every view.
func top_polygon(index: int, level: int, land: bool) -> PackedVector2Array:
	return _hex_at(top_center(index, level, land))


static func _hex_at(c: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in 6:
		var ang := deg_to_rad(30.0 + 60.0 * k)
		pts.append(c + Vector2(cos(ang) * HEX_SIZE, sin(ang) * HEX_SIZE * SQUASH))
	return pts


## Indices in back-to-front order for the painter's algorithm.
func draw_order() -> Array:
	var order: Array = range(grid.count)
	order.sort_custom(func(a, b):
		var pa := plane(a)
		var pb := plane(b)
		return pa.y < pb.y or (pa.y == pb.y and pa.x < pb.x))
	return order


## Screen bounds of the whole space at sea level, sea ring included.
func bounds() -> Rect2:
	var r := Rect2(top_center(0, 0, false), Vector2.ZERO)
	for i in grid.count:
		r = r.expand(top_center(i, 0, false))
	for k in frame.size():
		for v in frame_polygon(k):
			r = r.expand(v)
	return r.grow(HEX_SIZE * 0.5)
