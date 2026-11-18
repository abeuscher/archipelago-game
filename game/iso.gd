## Isometric projection for a hex space: a fixed viewing angle, six board
## rotations in 60-degree steps, and height drawn as vertical offset.
## Presentation only: these are drawing sizes, not game rules.
##
## The board is centred on its middle hex, which sits on a hex lattice in
## the board plane. Turning by 60 degrees about a lattice hex maps the
## lattice onto itself, so after any rotation every hex of the space is
## still on the lattice. That lets the sea around and between the islands
## (ocean_view.gd) line up with both boards in every view.
extends RefCounted

const HEX_SIZE := 30.0         ## Hex radius on the board plane, in pixels.
const SQUASH := 0.58           ## Vertical squash that fakes the camera tilt.
const LEVEL_HEIGHT := 14.0     ## Screen pixels per elevation level.
const LAND_BASE := 6.0         ## Base-level land sits this far above the sea.
const HEX_W := HEX_SIZE * 1.7320508075688772   ## Lattice spacing along a row.
const ROW_H := HEX_SIZE * 1.5                   ## Lattice spacing between rows.

var grid
var rotation_step: int = 0     ## 0..5, each step turns the board 60 degrees.
var _center_plane: Vector2


func _init(g) -> void:
	grid = g
	_center_plane = _plane_raw(g.center_index())


func _plane_raw(index: int) -> Vector2:
	return axial_plane(grid.axial_of(index))


## Plane position of a lattice hex given in axial coordinates.
static func axial_plane(a: Vector2i) -> Vector2:
	return Vector2(HEX_W * (a.x + a.y / 2.0), ROW_H * a.y)


## Nearest lattice hex to a plane position (exact for lattice points).
static func plane_axial(p: Vector2) -> Vector2i:
	var r := roundi(p.y / ROW_H)
	return Vector2i(roundi(p.x / HEX_W - r / 2.0), r)


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
	return hex_at(top_center(index, level, land))


## A flat hex outline around a screen point.
static func hex_at(c: Vector2) -> PackedVector2Array:
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


## Plane extents of the space in the current rotation: {min, max} corners
## of the hex centres.
func plane_extent() -> Rect2:
	var r := Rect2(plane(0), Vector2.ZERO)
	for i in grid.count:
		r = r.expand(plane(i))
	return r


## Screen bounds of the whole space at sea level.
func bounds() -> Rect2:
	var r := Rect2(top_center(0, 0, false), Vector2.ZERO)
	for i in grid.count:
		r = r.expand(top_center(i, 0, false))
	return r.grow(HEX_SIZE * 1.2)
