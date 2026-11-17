## Isometric projection for a hex space: a fixed viewing angle, six board
## rotations in 60-degree steps, and height drawn as vertical offset.
## Presentation only: these are drawing sizes, not game rules.
extends RefCounted

const HEX_SIZE := 30.0         ## Hex radius on the board plane, in pixels.
const SQUASH := 0.58           ## Vertical squash that fakes the camera tilt.
const LEVEL_HEIGHT := 14.0     ## Screen pixels per elevation level.
const LAND_BASE := 6.0         ## Base-level land sits this far above the sea.

var grid
var rotation_step: int = 0     ## 0..5, each step turns the board 60 degrees.
var _center_plane: Vector2


func _init(g) -> void:
	grid = g
	_center_plane = Vector2.ZERO
	var sum := Vector2.ZERO
	for i in g.count:
		sum += _plane_raw(i)
	_center_plane = sum / g.count


func _plane_raw(index: int) -> Vector2:
	var a: Vector2i = grid.axial_of(index)
	return Vector2(HEX_SIZE * sqrt(3.0) * (a.x + a.y / 2.0), HEX_SIZE * 1.5 * a.y)


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
	var c := top_center(index, level, land)
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


## Screen bounds of the whole space at sea level.
func bounds() -> Rect2:
	var r := Rect2(top_center(0, 0, false), Vector2.ZERO)
	for i in grid.count:
		r = r.expand(top_center(i, 0, false))
	return r.grow(HEX_SIZE * 1.5)
