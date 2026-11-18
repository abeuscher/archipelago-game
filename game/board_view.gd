## Draws one side's space in isometric view: terrain with height walls, fog,
## and building sprites turned to match the board rotation. Reads tiles prepared
## by the controller; never touches the rules state directly.
extends Node2D

const Iso = preload("res://game/iso.gd")
const Pieces = preload("res://game/pieces.gd")
const Palette = preload("res://game/palette.gd")

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
var _time: float = 0.0
var _since_redraw: float = 0.0
var _has_fog: bool = false
var _edge: Dictionary = {}        ## hexes on the border of the space

const SEA := Palette.SEA
const LAND_TOP := Palette.LAND_TOP
const WALL := Palette.WALL
## Surf around known land: the hex footprint at sea level, scaled up, drawn
## under the land so it shows only where the land meets the sea.
const SURF_SCALE := [[1.24, Palette.SURF_OUTER], [1.13, Palette.SURF]]
## Fog: near-black, feathered over its edges, with faint blotches that stay
## put (so panning is visible) and a few slow drifting wisps and swirls.
const FOG := Color(0.045, 0.05, 0.065)
const FOG_BLOTCH := Color(0.16, 0.17, 0.20, 0.10)
const FOG_WISP := Color(0.42, 0.45, 0.50)
const FOG_FEATHER := [[1.18, 0.55], [1.38, 0.28], [1.6, 0.12]]   ## [scale, alpha]
const FOG_FPS := 30.0
const STALE_TINT := Color(0.2, 0.2, 0.25, 0.22)
## Own hexes the enemy has revealed are lightened slightly.
const ENEMY_SEEN_TINT := Color(1, 1, 1, 0.15)
## Selection is cyan so it never reads as a hit outline (yellow to red).
const SELECTED := Color(0.35, 0.9, 1.0)
## Outline widths. Outlines are drawn with their hex, after its ground and
## before its building, so buildings sit on top of them; each is pulled just
## inside its hex so neighbours drawn later don't cover it.
const RING_WIDTH := 1.2
const BOMBED_WIDTH := 1.5
const HOVER_WIDTH := 1.5
const SELECTED_WIDTH := 2.0


func setup(grid) -> void:
	iso = Iso.new(grid)
	_order = iso.draw_order()
	for i in grid.count:
		if grid.neighbors(i).size() < 6:
			_edge[i] = true


func set_rotation_step(step: int) -> void:
	iso.rotation_step = step
	_order = iso.draw_order()
	queue_redraw()


func set_tiles(new_tiles: Array) -> void:
	tiles = new_tiles
	_has_fog = tiles.any(func(t): return not t.get("known", false))
	queue_redraw()


## Only boards with fog animate, at a modest frame rate.
func _process(delta: float) -> void:
	if not _has_fog:
		return
	_time += delta
	_since_redraw += delta
	if _since_redraw >= 1.0 / FOG_FPS:
		_since_redraw = 0.0
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
	var rings_at := {}
	for ring in range_rings:
		for h in ring["hexes"]:
			if not rings_at.has(h):
				rings_at[h] = []
			rings_at[h].append(ring["color"])
	# Pass 1: everything flat at sea level (sea and fog), so it can never
	# hide land. Pass 2: surf around the land. Pass 3: land, back to front,
	# with the buildings on it.
	for i in _order:
		var t: Dictionary = tiles[i]
		if _land(t):
			continue
		var top := iso.top_polygon(i, 0, false)
		if not t.get("known", false):
			_draw_fog(i, top)
		else:
			draw_colored_polygon(top, Palette.SEA_SHALLOW if _near_land(i) else SEA)
			draw_polyline(_closed(top), Palette.SEA_LINE, 1.0)
			Palette.draw_wave(self, iso.top_center(i, 0, false), Palette.hash_i(i))
			if t.get("stale", false):
				draw_colored_polygon(top, STALE_TINT)
		_draw_tile_extras(i, t, top, rings_at, font)
	for i in _order:
		if not _land(tiles[i]):
			continue
		var c0 := iso.top_center(i, 0, false)
		var foot := iso.top_polygon(i, 0, false)
		for layer in SURF_SCALE:
			var poly := PackedVector2Array()
			for v in foot:
				poly.append(c0 + (v - c0) * float(layer[0]))
			draw_colored_polygon(poly, layer[1])
	for i in _order:
		var t: Dictionary = tiles[i]
		if not _land(t):
			continue
		var lvl := _lvl(t)
		var top := iso.top_polygon(i, lvl, true)
		_draw_walls(i, top, lvl)
		draw_colored_polygon(top, LAND_TOP[clampi(lvl, 0, 2)])
		Palette.draw_ground_marks(self, iso.top_center(i, lvl, true), lvl, Palette.hash_i(i))
		draw_polyline(_closed(top), Palette.INK, 1.3, true)
		if t.get("stale", false):
			draw_colored_polygon(top, STALE_TINT)
		_draw_tile_extras(i, t, top, rings_at, font)

	if _has_fog:
		_draw_fog_overlay()
	for h in markers:
		var t3: Dictionary = tiles[h]
		var mc := iso.top_center(h, _lvl(t3), _land(t3))
		var col: Color = markers[h]
		draw_arc(mc, 11.0, 0, TAU, 20, col, 2.0)
		draw_line(mc + Vector2(-15, 0), mc + Vector2(15, 0), col, 2.0)
		draw_line(mc + Vector2(0, -9), mc + Vector2(0, 9), col, 2.0)


## A known sea hex next to known land is drawn as shallow water.
func _near_land(i: int) -> bool:
	for n in iso.grid.neighbors(i):
		if n < tiles.size() and _land(tiles[n]):
			return true
	return false


## Tints, outlines and the building for one hex, after its ground.
func _draw_tile_extras(i: int, t: Dictionary, top: PackedVector2Array, rings_at: Dictionary, font: Font) -> void:
	var lvl := _lvl(t)
	var land := _land(t)
	if t.get("enemy_seen", false):
		draw_colored_polygon(top, ENEMY_SEEN_TINT)
	if placement_ok.has(i):
		draw_colored_polygon(top, Color(1, 1, 1, 0.10))
	var c := iso.top_center(i, lvl, land)
	_draw_outlines(i, c, top, rings_at.get(i, []))
	var b = t.get("building")
	if b != null:
		Pieces.draw_piece(self, font, c, b, iso.rotation_step)
		if show_hits and String(b["type"]) in ["suspected_base", "decoy"] and float(b["hits"]) > 0.0:
			_draw_yard_number(font, c, b)
	elif String(t.get("destroyed", "")) != "":
		Pieces.draw_rubble(self, c, String(t["destroyed"]), iso.rotation_step)


## Range rings, hit outline, hover and selection for one hex, in that
## order, each inset by half its width so it stays inside the hex.
func _draw_outlines(i: int, c: Vector2, top: PackedVector2Array, ring_colors: Array) -> void:
	for col in ring_colors:
		_inset_outline(c, top, col, RING_WIDTH)
	var n := int(tiles[i].get("bombed", 0))
	if n > 0:
		_inset_outline(c, top, bombed_color(n), BOMBED_WIDTH)
	if i == hover:
		_inset_outline(c, top, Color(1, 1, 1, 0.9), HOVER_WIDTH)
	if i == selected:
		_inset_outline(c, top, SELECTED, SELECTED_WIDTH)


func _inset_outline(c: Vector2, top: PackedVector2Array, col: Color, width: float) -> void:
	var k := 1.0 - (width * 0.5 + 0.5) / Iso.HEX_SIZE
	var poly := PackedVector2Array()
	for v in top:
		poly.append(c + (v - c) * k)
	draw_polyline(_closed(poly), col, width, true)


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
		draw_line(a + Vector2(0, drop), b + Vector2(0, drop), Palette.INK, 1.3, true)
		draw_line(a, a + Vector2(0, drop), Color(Palette.INK, 0.5), 1.0, true)


## Fog has a fixed speckle pattern in board space, so it visibly moves when
## the view pans or rotates.
func _draw_fog(i: int, top: PackedVector2Array) -> void:
	draw_colored_polygon(top, FOG)
	# Fixed blotches, so the fog has a texture that moves when you pan.
	var c := iso.top_center(i, 0, false)
	var h := _hash(i)
	for k in 2:
		h = _next(h)
		var ox := float(h % 1000) / 1000.0 - 0.5
		h = _next(h)
		var oy := float(h % 1000) / 1000.0 - 0.5
		var p := c + Vector2(ox * Iso.HEX_SIZE, oy * Iso.HEX_SIZE * Iso.SQUASH)
		_soft_ellipse(p, 9.0 + float(h % 7), FOG_BLOTCH, 3)


## Drawn after every tile: feathered edges that spill softly over the
## neighbouring hexes, then drifting wisps and the odd slow swirl. Hexes on
## the border of the space get none of these, so the fog stops at the
## island's edge and never spills onto the open sea around it.
func _draw_fog_overlay() -> void:
	for i in tiles.size():
		if tiles[i].get("known", false) or _edge.has(i):
			continue
		var c := iso.top_center(i, 0, false)
		var top := iso.top_polygon(i, 0, false)
		for f in FOG_FEATHER:
			var poly := PackedVector2Array()
			for v in top:
				poly.append(c + (v - c) * float(f[0]))
			draw_colored_polygon(poly, Color(FOG, float(f[1]) * 0.5))
	for i in tiles.size():
		if tiles[i].get("known", false) or _edge.has(i):
			continue
		var h := _hash(i)
		var c := iso.top_center(i, 0, false)
		var phase := float(h % 6283) / 1000.0
		if h % 4 == 0:
			var drift := Vector2(sin(_time * 0.25 + phase) * 10.0, cos(_time * 0.19 + phase) * 4.0)
			var a := 0.035 + 0.025 * (0.5 + 0.5 * sin(_time * 0.4 + phase * 2.0))
			_soft_ellipse(c + drift, 22.0, Color(FOG_WISP, a), 5)
		if h % 11 == 0:
			var ang := _time * 0.35 * (1.0 if h % 2 == 0 else -1.0) + phase
			var a2 := 0.10 + 0.06 * sin(_time * 0.5 + phase)
			_swirl(c, 12.0 + float(h % 5), ang, Color(FOG_WISP, a2))


## A filled ellipse made of `layers` stacked translucent ellipses, so its
## edge fades out instead of ending sharply.
func _soft_ellipse(c: Vector2, r: float, col: Color, layers: int) -> void:
	for k in layers:
		var rr := r * (1.0 - float(k) / layers)
		draw_colored_polygon(_ellipse_points(c, rr, rr * Iso.SQUASH, 18), Color(col, col.a / layers * (k + 1) * 0.6))


## A short spiral curl lying flat on the hex.
func _swirl(c: Vector2, r: float, start: float, col: Color) -> void:
	var pts := PackedVector2Array()
	var steps := 22
	for k in steps + 1:
		var t := float(k) / steps
		var ang := start + t * 4.2
		var rr := r * (0.35 + 0.65 * t)
		pts.append(c + Vector2(cos(ang) * rr, sin(ang) * rr * Iso.SQUASH))
	draw_polyline(pts, col, 1.6, true)


static func _ellipse_points(c: Vector2, rx: float, ry: float, n: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in n:
		var a := TAU * k / n
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


static func _hash(i: int) -> int:
	return ((i + 1) * 2654435761) & 0x7FFFFFFF


static func _next(h: int) -> int:
	return (h * 1103515245 + 12345) & 0x7FFFFFFF


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

## Outline for a hex hit n times: yellow, orange, then red from 3 on.
static func bombed_color(n: int) -> Color:
	if n >= 3:
		return Color(0.95, 0.2, 0.15)
	if n == 2:
		return Color(1.0, 0.55, 0.1)
	return Color(1.0, 0.9, 0.2)


## Tiles for a side's own island: everything visible. `enemy_seen` holds
## the hexes the enemy has revealed (its knowledge); they are drawn lighter.
## `bombed` maps hexes to {"count", "last_round"} for missiles that landed.
static func own_tiles(st, data, enemy_seen: Dictionary = {}, bombed: Dictionary = {}) -> Array:
	var out: Array = []
	var isl = st.island
	for i in isl.grid.count:
		var t := {"known": true, "land": isl.is_land(i), "level": isl.level[i], "stale": false,
			"building": null, "destroyed": "", "enemy_seen": enemy_seen.has(i),
			"bombed": int(bombed.get(i, {}).get("count", 0))}
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
