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
	queue_redraw()


func _process(delta: float) -> void:
	if missiles.is_empty() and flashes.is_empty():
		return
	for f in flashes.duplicate():
		f.t += delta
		if f.t >= f.duration:
			flashes.erase(f)
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
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


static func _ellipse(c: Vector2, rx: float, ry: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in 14:
		var a := TAU * k / 14.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts
