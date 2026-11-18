## Bottom-right minimap: the whole world at one scale, as the boards draw
## it: the sea, the enemy island to the north and ours to the south, in the
## current rotation with real hexes. The white box is the current view.
## Clicking or dragging moves the view to that spot.
extends Control

const Iso = preload("res://game/iso.gd")
const Palette = preload("res://game/palette.gd")

signal view_requested(world_pos: Vector2)

const BG := Color(0.05, 0.06, 0.08, 0.92)
const UNKNOWN := Color(0.10, 0.11, 0.13)
const SEA := Palette.SEA
const LAND := Palette.LAND_TOP
const BASE_MARK := Color(0.96, 0.96, 0.96)
const BUILDING_MARK := Color(0.92, 0.32, 0.30)
const BORDER := Color(1.0, 0.85, 0.2)
const FRAME := Color(1, 1, 1, 0.9)
const PAD := 4.0
const REDRAW_SECONDS := 0.1

var boards: Array = []     ## [own BoardView, enemy BoardView]
var ocean
var camera: Camera2D
var _since: float = 0.0


func setup(own_board, enemy_board, ocean_view, cam: Camera2D) -> void:
	boards = [own_board, enemy_board]
	ocean = ocean_view
	camera = cam
	queue_redraw()


## Board tiles change during the playout without a refresh, and the camera
## glides between islands, so the map simply redraws a few times a second.
func _process(delta: float) -> void:
	_since += delta
	if _since >= REDRAW_SECONDS:
		_since = 0.0
		queue_redraw()


## World-to-map transform: the sea's bounds fitted, centred, into the
## control. map = world * scale + offset.
func _fit() -> Dictionary:
	var wb: Rect2 = ocean.world_rect()
	var avail := size - Vector2(PAD, PAD) * 2.0
	var s := minf(avail.x / maxf(wb.size.x, 1.0), avail.y / maxf(wb.size.y, 1.0))
	var off := Vector2(PAD, PAD) + (avail - wb.size * s) / 2.0 - wb.position * s
	return {"scale": s, "offset": off}


func to_world(local: Vector2) -> Vector2:
	var f := _fit()
	return (local - f["offset"]) / f["scale"]


func _gui_input(event: InputEvent) -> void:
	if ocean == null:
		return
	var drag: bool = event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0
	var click: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	if click or drag:
		view_requested.emit(to_world(event.position))
		accept_event()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	if ocean == null:
		return
	var f := _fit()
	var s: float = f["scale"]
	var off: Vector2 = f["offset"]
	var wb: Rect2 = ocean.world_rect()
	for c in ocean.cells:
		if not wb.has_point(c):
			continue
		draw_colored_polygon(_scaled(Iso.hex_at(c), Vector2.ZERO, s, off), SEA)
	for b in boards:
		if b.iso == null:
			continue
		for i in b.tiles.size():
			draw_colored_polygon(_scaled(b.iso.top_polygon(i, 0, false), b.position, s, off), _color(b.tiles[i]))
	if camera != null:
		var vs := camera.get_viewport_rect().size / camera.zoom
		var view := Rect2((camera.position - vs / 2.0) * s + off, vs * s)
		view = view.intersection(Rect2(Vector2.ONE, size - Vector2(2, 2)))
		if view.has_area():
			draw_rect(view, FRAME, false, 1.0)
	draw_rect(Rect2(Vector2.ZERO, size), BORDER, false, 1.5)


static func _scaled(poly: PackedVector2Array, origin: Vector2, s: float, off: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for v in poly:
		out.append((origin + v) * s + off)
	return out


static func _color(t: Dictionary) -> Color:
	if not t.get("known", false):
		return UNKNOWN
	var b = t.get("building")
	if b != null:
		return BASE_MARK if String(b["type"]) in ["base", "decoy", "suspected_base"] else BUILDING_MARK
	if not t.get("land", false):
		return SEA
	return LAND[clampi(int(t.get("level", 0)), 0, 2)]
