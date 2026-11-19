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
var _clock: float = 0.0


class Aircraft extends RefCounted:
	var ground: Vector2
	var alt: float
	var heading: float
	var color: Color


class Chute extends RefCounted:
	var ground: Vector2
	var alt: float
	var color: Color
	var phase: float


class Squad extends RefCounted:
	var ground: Vector2
	var color: Color


## Placeholder troop art until the sprites arrive (docs/troop_assets.md).
func add_plane(ground: Vector2, alt: float, heading: float, color: Color) -> Aircraft:
	var p := Aircraft.new()
	p.ground = ground
	p.alt = alt
	p.heading = heading
	p.color = color
	planes.append(p)
	return p


func remove_plane(p) -> void:
	planes.erase(p)


func add_chute(ground: Vector2, alt: float, color: Color) -> Chute:
	var c := Chute.new()
	c.ground = ground
	c.alt = alt
	c.color = color
	c.phase = randf() * TAU
	chutes.append(c)
	return c


func remove_chute(c) -> void:
	chutes.erase(c)


func add_squad(ground: Vector2, color: Color) -> Squad:
	var s := Squad.new()
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
	queue_redraw()


func _process(delta: float) -> void:
	_clock += delta
	if missiles.is_empty() and flashes.is_empty() and planes.is_empty() and chutes.is_empty() and squads.is_empty():
		return
	for f in flashes.duplicate():
		f.t += delta
		if f.t >= f.duration:
			flashes.erase(f)
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	for s in squads:
		_draw_squad(s)
	for c in chutes:
		_draw_chute(c)
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
	for k in 8:
		var off := Vector2(float(k % 4) * 7.0 - 10.5, float(k / 4) * 6.0 - 3.0)
		var bob := sin(_clock * 10.0 + k) * 0.8
		_soldier(s.ground + off + Vector2(0, bob), s.color)


## A tiny soldier, feet at p.
func _soldier(p: Vector2, col: Color) -> void:
	draw_rect(Rect2(p + Vector2(-1.5, -6), Vector2(3, 6)), col.darkened(0.35))
	draw_circle(p + Vector2(0, -7.5), 1.8, Color(0.95, 0.8, 0.65))
	draw_rect(Rect2(p + Vector2(-1.5, -6), Vector2(3, 6)), Color(0.1, 0.1, 0.1, 0.6), false, 0.6)


static func _ellipse(c: Vector2, rx: float, ry: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in 14:
		var a := TAU * k / 14.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts
