## Draws one side's space in isometric view: terrain with height walls, fog,
## and placeholder pieces that always face the camera. Reads tiles prepared
## by the controller; never touches the rules state directly.
extends Node2D

const Iso = preload("res://game/iso.gd")
const Pieces = preload("res://game/pieces.gd")

## One tile per hex:
## {"known": bool, "land": bool, "level": int, "stale": bool,
##  "building": null or {"type", "hits", "damaged", "disabled", "repairing"},
##  "destroyed": String}
var tiles: Array = []
var iso: Iso
var hover: int = -1
var selected: int = -1
var markers: Dictionary = {}      ## hex -> Color, e.g. planned targets
var range_rings: Array = []       ## [{"hexes": PackedInt32Array, "color": Color}]
var placement_ok: Dictionary = {} ## hex -> true where the current tool may place
var show_hits: bool = false       ## draw hit counts on suspected bases
var _order: Array = []

const SEA := Color(0.16, 0.30, 0.45)
const SEA_EDGE := Color(0.12, 0.24, 0.37)
const LAND_TOP := [Color(0.42, 0.56, 0.32), Color(0.55, 0.58, 0.36), Color(0.62, 0.55, 0.42)]
const WALL := [Color(0.30, 0.36, 0.22), Color(0.38, 0.36, 0.24), Color(0.42, 0.35, 0.27)]
const FOG := Color(0.33, 0.34, 0.37)
const FOG_SPECK := Color(0.42, 0.43, 0.46)
const FOG_SPECK_DARK := Color(0.27, 0.28, 0.30)
const STALE_TINT := Color(0.2, 0.2, 0.25, 0.22)


func setup(grid) -> void:
	iso = Iso.new(grid)
	_order = iso.draw_order()


func set_rotation_step(step: int) -> void:
	iso.rotation_step = step
	_order = iso.draw_order()
	queue_redraw()


func set_tiles(new_tiles: Array) -> void:
	tiles = new_tiles
	queue_redraw()


func bounds() -> Rect2:
	return iso.bounds()


func tile_center(index: int) -> Vector2:
	var t: Dictionary = tiles[index] if index < tiles.size() else {}
	return iso.top_center(index, _lvl(t), _land(t))


func _lvl(t: Dictionary) -> int:
	return int(t.get("level", 0)) if t.get("known", false) else 0


func _land(t: Dictionary) -> bool:
	return bool(t.get("land", false)) and bool(t.get("known", false))


## Hex under a point in this node's local coordinates, front-most first.
func hex_at(local: Vector2) -> int:
	for k in range(_order.size() - 1, -1, -1):
		var i: int = _order[k]
		var t: Dictionary = tiles[i]
		if Geometry2D.is_point_in_polygon(local, iso.top_polygon(i, _lvl(t), _land(t))):
			return i
	return -1


func _draw() -> void:
	if iso == null or tiles.is_empty():
		return
	var font := ThemeDB.fallback_font
	for i in _order:
		var t: Dictionary = tiles[i]
		var lvl := _lvl(t)
		var land := _land(t)
		var top := iso.top_polygon(i, lvl, land)
		if not t.get("known", false):
			_draw_fog(i, top)
		elif not land:
			draw_colored_polygon(top, SEA)
			draw_polyline(_closed(top), SEA_EDGE, 1.0)
		else:
			_draw_walls(i, top, lvl)
			draw_colored_polygon(top, LAND_TOP[clampi(lvl, 0, 2)])
			draw_polyline(_closed(top), WALL[clampi(lvl, 0, 2)].darkened(0.2), 1.0)
			if t.get("stale", false):
				draw_colored_polygon(top, STALE_TINT)
		if placement_ok.has(i):
			draw_colored_polygon(top, Color(1, 1, 1, 0.10))
		var c := iso.top_center(i, lvl, land)
		var b = t.get("building")
		if b != null:
			Pieces.draw_piece(self, font, c, b)
			if show_hits and String(b["type"]) in ["suspected_base", "decoy"] and float(b["hits"]) > 0.0:
				_draw_yard_number(font, c, b)
		elif String(t.get("destroyed", "")) != "":
			Pieces.draw_rubble(self, c, String(t["destroyed"]))

	for ring in range_rings:
		for h in ring["hexes"]:
			var t2: Dictionary = tiles[h]
			draw_polyline(_closed(iso.top_polygon(h, _lvl(t2), _land(t2))), ring["color"], 1.5)
	for h in markers:
		var t3: Dictionary = tiles[h]
		var mc := iso.top_center(h, _lvl(t3), _land(t3))
		var col: Color = markers[h]
		draw_arc(mc, 11.0, 0, TAU, 20, col, 2.0)
		draw_line(mc + Vector2(-15, 0), mc + Vector2(15, 0), col, 2.0)
		draw_line(mc + Vector2(0, -9), mc + Vector2(0, 9), col, 2.0)
	if hover >= 0:
		var th: Dictionary = tiles[hover]
		draw_polyline(_closed(iso.top_polygon(hover, _lvl(th), _land(th))), Color(1, 1, 1, 0.9), 2.0)
	if selected >= 0:
		var ts: Dictionary = tiles[selected]
		draw_polyline(_closed(iso.top_polygon(selected, _lvl(ts), _land(ts))), Color(1.0, 0.85, 0.2), 2.5)


func _draw_walls(i: int, top: PackedVector2Array, lvl: int) -> void:
	var drop := iso.height_px(lvl, true)
	var c := iso.top_center(i, lvl, true)
	for k in 6:
		var a := top[k]
		var b := top[(k + 1) % 6]
		if (a + b).y * 0.5 <= c.y + 0.01:
			continue   # edge faces away from the camera
		var wall := PackedVector2Array([a, b, b + Vector2(0, drop), a + Vector2(0, drop)])
		var shade: Color = WALL[clampi(lvl, 0, 2)]
		if (b - a).x * (b - a).y < 0.0:
			shade = shade.darkened(0.15)
		draw_colored_polygon(wall, shade)


## Fog has a fixed speckle pattern in board space, so it visibly moves when
## the view pans or rotates.
func _draw_fog(i: int, top: PackedVector2Array) -> void:
	draw_colored_polygon(top, FOG)
	draw_polyline(_closed(top), FOG.darkened(0.15), 1.0)
	var c := iso.top_center(i, 0, false)
	var h := (i * 2654435761) & 0xFFFFFFFF
	for k in 5:
		h = (h * 1103515245 + 12345) & 0x7FFFFFFF
		var ox := float(h % 1000) / 1000.0 - 0.5
		h = (h * 1103515245 + 12345) & 0x7FFFFFFF
		var oy := float(h % 1000) / 1000.0 - 0.5
		var p := c + Vector2(ox * Iso.HEX_SIZE * 1.2, oy * Iso.HEX_SIZE * Iso.SQUASH * 1.2)
		draw_circle(p, 2.5 if k % 2 == 0 else 1.6, FOG_SPECK if k % 2 == 0 else FOG_SPECK_DARK)


## Hit count drawn flat on the hex in perspective, like a yard marker.
func _draw_yard_number(font: Font, c: Vector2, b: Dictionary) -> void:
	var hits := float(b["hits"])
	var text := str(int(hits)) if is_equal_approx(hits, roundf(hits)) else "%.1f" % hits
	draw_set_transform(c + Vector2(0, 9), 0.0, Vector2(1.0, Iso.SQUASH))
	draw_string(font, Vector2(-20, 8), text, HORIZONTAL_ALIGNMENT_CENTER, 40, 22, Color(1, 1, 1, 0.95))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _closed(poly: PackedVector2Array) -> PackedVector2Array:
	var p := poly.duplicate()
	p.append(poly[0])
	return p


# --- Tile builders ---------------------------------------------------------

## Tiles for a side's own island: everything visible.
static func own_tiles(st, data) -> Array:
	var out: Array = []
	var isl = st.island
	for i in isl.grid.count:
		var t := {"known": true, "land": isl.is_land(i), "level": isl.level[i], "stale": false,
			"building": null, "destroyed": ""}
		var b = st.building_at(i)
		if b != null:
			t["building"] = {
				"type": b.type, "hits": b.hits,
				"damaged": b.hp < data.max_hp(b.type), "disabled": b.disabled, "repairing": b.repairing,
				"half": st.is_half_strength(b, data),
			}
		out.append(t)
	return out


## Tiles for the opposing space as this side knows it.
static func enemy_tiles(knowledge: Dictionary, grid, round_number: int) -> Array:
	var out: Array = []
	for i in grid.count:
		var e = knowledge.get(i)
		if e == null:
			out.append({"known": false})
			continue
		out.append({"known": true, "land": e["land"], "level": e["level"],
			"stale": int(e["seen_round"]) < round_number, "building": e["building"],
			"destroyed": e["destroyed"]})
	return out
