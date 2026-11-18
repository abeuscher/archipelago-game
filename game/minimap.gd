## Bottom-right minimap: own island on the left, the opposing space (as
## known) on the right. Clicking either half moves the view there; it is the
## only way to look at the other island. Drawn top-down, unrotated.
extends Control

signal view_requested(side: int, fraction: Vector2)

var own_tiles: Array = []
var enemy_tiles: Array = []
var grid
var viewing: int = 0

const GAP := 8.0


func set_data(g, own: Array, enemy: Array) -> void:
	grid = g
	own_tiles = own
	enemy_tiles = enemy
	queue_redraw()


func _half_rect(side: int) -> Rect2:
	var w := (size.x - GAP) / 2.0
	return Rect2(Vector2(side * (w + GAP), 0), Vector2(w, size.y))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for side in 2:
			var r := _half_rect(side)
			if r.has_point(event.position):
				view_requested.emit(side, (event.position - r.position) / r.size)
				accept_event()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.06, 0.08, 0.9))
	if grid == null:
		return
	for side in 2:
		var r := _half_rect(side)
		var tiles: Array = own_tiles if side == 0 else enemy_tiles
		var cw: float = r.size.x / (grid.width + 0.5)
		var ch: float = r.size.y / grid.height
		for i in grid.count:
			if i >= tiles.size():
				break
			var t: Dictionary = tiles[i]
			var col := Color(0.10, 0.11, 0.13)
			if t.get("known", false):
				if not t["land"]:
					col = Color(0.16, 0.30, 0.45)
				else:
					col = [Color(0.42, 0.56, 0.32), Color(0.55, 0.58, 0.36), Color(0.62, 0.55, 0.42)][clampi(int(t["level"]), 0, 2)]
				if t.get("building") != null:
					col = Color(0.95, 0.95, 0.95) if String(t["building"]["type"]) in ["base", "decoy", "suspected_base"] else Color(0.9, 0.3, 0.3)
			var col_i: int = grid.col_of(i)
			var row_i: int = grid.row_of(i)
			var x: float = r.position.x + (col_i + (0.5 if row_i % 2 == 1 else 0.0)) * cw
			var y: float = r.position.y + row_i * ch
			draw_rect(Rect2(x, y, cw - 0.5, ch - 0.5), col)
		draw_rect(r, Color(1.0, 0.85, 0.2) if side == viewing else Color(0.4, 0.4, 0.45), false, 2.0)
