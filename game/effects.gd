## Short-lived playout visuals in world space: missiles in flight with a
## shadow on the hex beneath, anti-air tracers, bursts and explosions.
extends Node2D


class Missile extends RefCounted:
	var ground: Vector2   ## point on the board beneath the missile
	var alt: float        ## height above that point, in screen pixels
	var color: Color
	var alive: bool = true
	var last_alt: float = -1.0   ## to tell rising from falling
	var falling: bool = true


class Flash extends RefCounted:
	var pos: Vector2
	var radius: float
	var color: Color
	var t: float = 0.0
	var duration: float
	var kind: String      ## "explosion", "burst", "tracer", "text"
	var to: Vector2
	var text: String


const TRAIL_LENGTH := 70.0

var missiles: Array = []
var flashes: Array = []
var planes: Array = []
var chutes: Array = []
var squads: Array = []
var agents: Array = []         ## the spy on the ground
var sea_boats: Array = []      ## boats in the channel (and coming ashore)
var _clock: float = 0.0


class SeaBoat extends RefCounted:
	var ground: Vector2
	var facing: int = 0
	var side: String = "player"


func make_boat(at: Vector2, facing: int, side: String) -> SeaBoat:
	var b := SeaBoat.new()
	b.ground = at
	b.facing = facing
	b.side = side
	return b


class Aircraft extends RefCounted:
	var ground: Vector2
	var alt: float
	var heading: float
	var color: Color
	var side: String = "player"   ## colourway of the unit art
	var door_open: bool = false
	var kind: String = "transport"   ## or "helicopter" (the spy's)


class Agent extends RefCounted:
	var ground: Vector2
	var side: String = "player"
	var pose: int = 0             ## sheet column: stand, step, report


class Chute extends RefCounted:
	var ground: Vector2
	var alt: float
	var color: Color
	var phase: float
	var side: String = "player"


class Squad extends RefCounted:
	var ground: Vector2
	var color: Color
	var side: String = "player"
	var facing: int = 0          ## screen direction row: E, SE, SW, W, NW, NE
	var walking: bool = false
	var wiped: bool = false


## Placeholder troop art until the sprites arrive (docs/troop_assets.md).
func add_plane(ground: Vector2, alt: float, heading: float, color: Color, side: String = "player") -> Aircraft:
	var p := Aircraft.new()
	p.side = side
	p.ground = ground
	p.alt = alt
	p.heading = heading
	p.color = color
	planes.append(p)
	return p


func remove_plane(p) -> void:
	planes.erase(p)


func add_agent(ground: Vector2, side: String = "player") -> Agent:
	var a := Agent.new()
	a.ground = ground
	a.side = side
	agents.append(a)
	return a


func remove_agent(a) -> void:
	agents.erase(a)


func add_chute(ground: Vector2, alt: float, color: Color, side: String = "player") -> Chute:
	var c := Chute.new()
	c.side = side
	c.ground = ground
	c.alt = alt
	c.color = color
	c.phase = randf() * TAU
	chutes.append(c)
	return c


func remove_chute(c) -> void:
	chutes.erase(c)


func add_squad(ground: Vector2, color: Color, side: String = "player") -> Squad:
	var s := Squad.new()
	s.side = side
	s.ground = ground
	s.color = color
	squads.append(s)
	return s


func remove_squad(s) -> void:
	squads.erase(s)


func add_missile(ground: Vector2, alt: float, color: Color) -> Missile:
	var m := Missile.new()
	m.ground = ground
	m.alt = alt
	m.falling = alt > 0.0   # launched from the ground: rising
	m.color = color
	missiles.append(m)
	return m


func remove_missile(m: Missile) -> void:
	missiles.erase(m)


func explosion(pos: Vector2, radius: float = 40.0, color: Color = Color(1.0, 0.55, 0.15)) -> void:
	_flash("explosion", pos, radius, color, 0.85)


func burst(pos: Vector2) -> void:
	_flash("burst", pos, 14.0, Color(1, 1, 0.7), 0.35)


func tracer(from: Vector2, to: Vector2) -> void:
	var f := _flash("tracer", from, 0.0, Color(0.6, 1.0, 0.6), 0.25)
	f.to = to


func float_text(pos: Vector2, text: String, color: Color = Color.WHITE) -> void:
	var f := _flash("text", pos, 0.0, color, 1.1)
	f.text = text


func _flash(kind: String, pos: Vector2, radius: float, color: Color, duration: float) -> Flash:
	var f := Flash.new()
	f.kind = kind
	f.pos = pos
	f.radius = radius
	f.color = color
	f.duration = duration
	flashes.append(f)
	return f


func clear() -> void:
	missiles.clear()
	flashes.clear()
	planes.clear()
	chutes.clear()
	squads.clear()
	agents.clear()
	queue_redraw()


func _process(delta: float) -> void:
	_clock += delta
	if missiles.is_empty() and flashes.is_empty() and planes.is_empty() and chutes.is_empty() and squads.is_empty() \
			and sea_boats.is_empty() and agents.is_empty():
		return
	for f in flashes.duplicate():
		f.t += delta
		if f.t >= f.duration:
			flashes.erase(f)
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	for bt in sea_boats:
		if not _unit_frame("boat_" + bt.side, int(_clock * 3.0) % 2, bt.facing, bt.ground, 0.0):
			draw_colored_polygon(_ellipse(bt.ground, 12.0, 5.0), Color(0.35, 0.38, 0.33))
	for s in squads:
		_draw_squad(s)
	for c in chutes:
		_draw_chute(c)
	for a in agents:
		# A pool of light under him: a man in black has to show on the fog too.
		draw_colored_polygon(_ellipse(a.ground, 15.0, 6.5), Color(1.0, 0.96, 0.8, 0.55))
		draw_colored_polygon(_ellipse(a.ground, 9.0, 4.0), Color(1.0, 0.98, 0.9, 0.6))
		if not _unit_frame("spy_" + a.side, a.pose, 0, a.ground, 0.0):
			draw_rect(Rect2(a.ground + Vector2(-2.5, -11), Vector2(5, 11)), Color(0.08, 0.08, 0.1))
			draw_circle(a.ground + Vector2(0, -13), 2.6, Color(0.95, 0.8, 0.65))
	for p in planes:
		_draw_plane(p)
	for m in missiles:
		if m.last_alt >= 0.0 and not is_equal_approx(m.alt, m.last_alt):
			m.falling = m.alt < m.last_alt
		m.last_alt = m.alt
		var shadow_r := clampf(9.0 - m.alt / 60.0, 3.0, 9.0)
		draw_colored_polygon(_ellipse(m.ground, shadow_r, shadow_r * 0.45), Color(0, 0, 0, 0.35))
		var p: Vector2 = m.ground - Vector2(0, m.alt)
		# A long fading smoke trail on the side the missile came from, then a
		# glowing head.
		var back := Vector2(0, -1) if m.falling else Vector2(0, 1)
		var steps := 10
		for k in steps:
			var t0 := float(k) / steps
			var t1 := float(k + 1) / steps
			var a := 0.75 * (1.0 - t0)
			draw_line(p + back * (TRAIL_LENGTH * t0), p + back * (TRAIL_LENGTH * t1),
				Color(1, 0.95, 0.85, a), lerpf(5.0, 1.5, t0))
		draw_circle(p, 9.0, Color(m.color, 0.30))
		draw_circle(p, 5.0, m.color)
		draw_circle(p, 2.2, Color(1, 1, 0.9))
	for f in flashes:
		var k: float = f.t / f.duration
		var col: Color = f.color
		col.a = 1.0 - k
		match f.kind:
			"explosion":
				# Smoke that lingers, the fireball, a hot core and a shock ring.
				if k > 0.35:
					var sk := (k - 0.35) / 0.65
					draw_circle(f.pos + Vector2(0, -12.0 * sk), f.radius * (0.6 + 0.4 * sk), Color(0.18, 0.17, 0.16, 0.5 * (1.0 - sk)))
				draw_circle(f.pos, f.radius * (0.45 + 0.55 * k), col)
				draw_circle(f.pos, f.radius * 0.5 * (1.0 - k), Color(1.0, 0.95, 0.7, 1.0 - k))
				draw_arc(f.pos, f.radius * (0.6 + 1.0 * k), 0, TAU, 32, Color(1, 0.9, 0.6, col.a), 3.0)
			"burst":
				for a in 8:
					var dir := Vector2.RIGHT.rotated(TAU * a / 8.0)
					draw_line(f.pos + dir * 3.0, f.pos + dir * f.radius * (0.5 + k), col, 2.0)
			"tracer":
				draw_line(f.pos, f.to, col, 2.0)
			"text":
				draw_string(font, f.pos + Vector2(-40, -20 - 30 * k), f.text, HORIZONTAL_ALIGNMENT_CENTER, 80, 16, col)


func _draw_plane(p) -> void:
	draw_colored_polygon(_ellipse(p.ground, 20.0, 7.0), Color(0, 0, 0, 0.25))
	var c: Vector2 = p.ground - Vector2(0, p.alt)
	# The art: nose to the right, turned to the heading; props spin, and the
	# cargo door opens for the drop.
	if p.kind == "helicopter":
		if _unit_frame("helicopter_" + p.side, int(_clock * 24.0) % 2, 0, c, p.heading):
			return
	var frame := 2 if p.door_open else int(_clock * 20.0) % 2
	if p.kind == "transport" and _unit_frame("transport_" + p.side, frame, 0, c, p.heading):
		return
	var shape := PackedVector2Array([Vector2(26, 0), Vector2(14, -4), Vector2(4, -4), Vector2(-2, -24), Vector2(-9, -24), Vector2(-6, -4),
		Vector2(-18, -4), Vector2(-24, -11), Vector2(-28, -11), Vector2(-25, 0), Vector2(-28, 11), Vector2(-24, 11), Vector2(-18, 4),
		Vector2(-6, 4), Vector2(-9, 24), Vector2(-2, 24), Vector2(4, 4), Vector2(14, 4)])
	var pts := PackedVector2Array()
	for v in shape:
		pts.append(c + v.rotated(p.heading))
	draw_colored_polygon(pts, p.color.darkened(0.25))
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, Color(0.1, 0.09, 0.08), 1.5, true)


func _draw_chute(c) -> void:
	var sway := sin(_clock * 3.0 + c.phase) * 4.0
	var feet: Vector2 = c.ground - Vector2(0, c.alt)
	var col := 3 if c.alt < 6.0 else (1 if sway < 0.0 else 2)
	if c.alt > 130.0:
		col = 0   # canopy still opening
	if _unit_frame("parachutist_" + c.side, col, 0, feet + Vector2(sway, 0), 0.0):
		return
	var top := feet + Vector2(sway, -16)
	if c.alt > 1.0:
		var canopy := PackedVector2Array()
		for k in 9:
			var a := PI + PI * k / 8.0
			canopy.append(top + Vector2(cos(a) * 9.0, sin(a) * 6.0))
		draw_colored_polygon(canopy, Color(0.95, 0.95, 0.9))
		draw_polyline(canopy, Color(0.2, 0.2, 0.2), 1.0, true)
		draw_line(top + Vector2(-9, 0), feet + Vector2(0, -5), Color(0.2, 0.2, 0.2, 0.7), 1.0)
		draw_line(top + Vector2(9, 0), feet + Vector2(0, -5), Color(0.2, 0.2, 0.2, 0.7), 1.0)
	_soldier(feet, c.color)


func _draw_squad(s) -> void:
	var col := 0
	if s.wiped:
		col = 7
	elif s.walking:
		col = 1 + int(_clock * 8.0) % 4
	else:
		col = 5 + int(_clock * 6.0) % 2   # fighting on the hex
	if _unit_frame("platoon_" + s.side, col, s.facing, s.ground, 0.0):
		return
	for k in 8:
		var off := Vector2(float(k % 4) * 7.0 - 10.5, float(k / 4) * 6.0 - 3.0)
		var bob := sin(_clock * 10.0 + k) * 0.8
		_soldier(s.ground + off + Vector2(0, bob), s.color)


## A tiny soldier, feet at p.
func _soldier(p: Vector2, col: Color) -> void:
	draw_rect(Rect2(p + Vector2(-1.5, -6), Vector2(3, 6)), col.darkened(0.35))
	draw_circle(p + Vector2(0, -7.5), 1.8, Color(0.95, 0.8, 0.65))
	draw_rect(Rect2(p + Vector2(-1.5, -6), Vector2(3, 6)), Color(0.1, 0.1, 0.1, 0.6), false, 0.6)


# --- Unit art (assets/units, described by units.json) ----------------------

const UNIT_DIR := "res://assets/units/"
const BOARD_HEX_WIDTH := 30.0 * 1.7320508
const Textures = preload("res://game/textures.gd")
static var _unit_meta = null
static var _unit_tex: Dictionary = {}


static func unit_meta() -> Dictionary:
	if _unit_meta == null:
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(UNIT_DIR + "units.json"))
		_unit_meta = parsed if parsed is Dictionary else {}
	return _unit_meta


## Draws one frame of a unit sheet with its anchor on `at`, rotated by
## `angle`. False if the sheet is missing (the caller draws a placeholder).
func _unit_frame(sheet: String, col: int, row: int, at: Vector2, angle: float) -> bool:
	var meta := unit_meta()
	var info: Dictionary = meta.get("sheets", {}).get(sheet, {})
	if info.is_empty():
		return false
	if not _unit_tex.has(sheet):
		_unit_tex[sheet] = Textures.load_texture(UNIT_DIR + String(info["file"]))
	var tex: Texture2D = _unit_tex[sheet]
	if tex == null:
		return false
	var fw := float(info["frame_width"])
	var fh := float(info["frame_height"])
	var anchor := Vector2(float(info["anchor"][0]), float(info["anchor"][1]))
	var k := BOARD_HEX_WIDTH / float(meta.get("hex_width", 104.0))
	draw_set_transform(at, angle, Vector2(k, k))
	draw_texture_rect_region(tex, Rect2(-anchor, Vector2(fw, fh)), Rect2(col * fw, row * fh, fw, fh))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return true


## The unit-art direction row for a movement on screen: E, SE, SW, W, NW, NE
## (hex neighbours as they look on the board).
static func facing_for(v: Vector2) -> int:
	var ang := fposmod(rad_to_deg(v.angle()), 360.0)
	var dirs := [0.0, 45.0, 135.0, 180.0, 225.0, 315.0]
	var best := 0
	var best_d := 999.0
	for i in dirs.size():
		var d: float = absf(fposmod(ang - float(dirs[i]) + 180.0, 360.0) - 180.0)
		if d < best_d:
			best_d = d
			best = i
	return best


static func _ellipse(c: Vector2, rx: float, ry: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in 14:
		var a := TAU * k / 14.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts
