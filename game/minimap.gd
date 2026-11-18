## Bottom-right minimap: each island drawn as the board draws it, with real
## hexes in the current rotation and squash, own island in the left half and
## the opposing space (as known) in the right. Each island fills its half;
## the camera's view is framed. Clicking or dragging moves the view to that
## spot; it is the only way to look at the other island besides panning.
extends Control

signal view_requested(world_pos: Vector2)

const BG := Color(0.05, 0.06, 0.08, 0.92)
const UNKNOWN := Color(0.10, 0.11, 0.13)
const SEA := Color(0.16, 0.30, 0.45)
const LAND := [Color(0.42, 0.56, 0.32), Color(0.55, 0.58, 0.36), Color(0.62, 0.55, 0.42)]
const BASE_MARK := Color(0.96, 0.96, 0.96)
const BUILDING_MARK := Color(0.92, 0.32, 0.30)
const VIEWING := Color(1.0, 0.85, 0.2)
const IDLE := Color(0.32, 0.35, 0.40)
const FRAME := Color(1, 1, 1, 0.85)
const GAP := 6.0
const PAD := 5.0
const REDRAW_SECONDS := 0.1

var boards: Array = []     ## [own BoardView, enemy BoardView]
var camera: Camera2D
var viewing: int = 0
var _since: float = 0.0


func setup(own_board, enemy_board, cam: Camera2D) -> void:
	boards = [own_board, enemy_board]
	camera = cam
	queue_redraw()


## Board tiles change during the playout without a refresh, so the map
## simply redraws a few times a second.
func _process(delta: float) -> void:
	_since += delta
	if _since >= REDRAW_SECONDS:
		_since = 0.0
		queue_redraw()


func half_rect(side: int) -> Rect2:
	var w := (size.x - GAP) / 2.0
	return Rect2(Vector2(side * (w + GAP), 0), Vector2(w, size.y))


## World-to-map transform for one island: its board bounds fitted, centred,
## into its half. map = world * scale + offset.
func _fit(side: int) -> Dictionary:
	var b = boards[side]
	var wb: Rect2 = b.bounds()
	wb.position += b.position
	var r := half_rect(side).grow(-PAD)
	var s := minf(r.size.x / maxf(wb.size.x, 1.0), r.size.y / maxf(wb.size.y, 1.0))
	var off := r.position + (r.size - wb.size * s) / 2.0 - wb.position * s
	return {"scale": s, "offset": off}


func side_at(local: Vector2) -> int:
	return 1 if local.x >= size.x / 2.0 else 0


func to_world(local: Vector2) -> Vector2:
	var f := _fit(side_at(local))
	return (local - f["offset"]) / f["scale"]


func to_map(side: int, world: Vector2) -> Vector2:
	var f := _fit(side)
	return world * f["scale"] + f["offset"]


func _gui_input(event: InputEvent) -> void:
	if boards.is_empty():
		return
	var drag: bool = event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0
	var click: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	if click or drag:
		view_requested.emit(to_world(event.position))
		accept_event()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	if boards.is_empty():
		return
	for side in boards.size():
		var b = boards[side]
		if b.iso == null:
			continue
		var f := _fit(side)
		var s: float = f["scale"]
		var origin: Vector2 = b.position * s + f["offset"]
		for k in b.iso.frame.size():
			var fp: PackedVector2Array = b.iso.frame_polygon(k)
			for j in fp.size():
				fp[j] = origin + fp[j] * s
			draw_colored_polygon(fp, SEA)
		for i in b.tiles.size():
			var poly: PackedVector2Array = b.iso.top_polygon(i, 0, false)
			for j in poly.size():
				poly[j] = origin + poly[j] * s
			draw_colored_polygon(poly, _color(b.tiles[i]))
		if camera != null:
			var vs := camera.get_viewport_rect().size / camera.zoom
			var view := Rect2((camera.position - vs / 2.0) * s + f["offset"], vs * s)
			view = view.intersection(half_rect(side).grow(-1.0))
			if view.has_area():
				draw_rect(view, FRAME, false, 1.0)
		var hr := half_rect(side)
		draw_rect(hr, VIEWING if side == viewing else IDLE, false, 1.5 if side == viewing else 1.0)


static func _color(t: Dictionary) -> Color:
	if not t.get("known", false):
		return UNKNOWN
	var b = t.get("building")
	if b != null:
		return BASE_MARK if String(b["type"]) in ["base", "decoy", "suspected_base"] else BUILDING_MARK
	if not t.get("land", false):
		return SEA
	return LAND[clampi(int(t.get("level", 0)), 0, 2)]
