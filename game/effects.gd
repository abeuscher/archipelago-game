## Short-lived playout visuals in world space: missiles in flight with a
## shadow on the hex beneath, anti-air tracers, bursts and explosions.
extends Node2D


class Missile extends RefCounted:
	var ground: Vector2   ## point on the board beneath the missile
	var alt: float        ## height above that point, in screen pixels
	var color: Color
	var alive: bool = true


class Flash extends RefCounted:
	var pos: Vector2
	var radius: float
	var color: Color
	var t: float = 0.0
	var duration: float
	var kind: String      ## "explosion", "burst", "tracer", "text"
	var to: Vector2
	var text: String


var missiles: Array = []
var flashes: Array = []


func add_missile(ground: Vector2, alt: float, color: Color) -> Missile:
	var m := Missile.new()
	m.ground = ground
	m.alt = alt
	m.color = color
	missiles.append(m)
	return m


func remove_missile(m: Missile) -> void:
	missiles.erase(m)


func explosion(pos: Vector2, radius: float = 26.0, color: Color = Color(1.0, 0.55, 0.15)) -> void:
	_flash("explosion", pos, radius, color, 0.55)


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
		var shadow_r := clampf(9.0 - m.alt / 60.0, 3.0, 9.0)
		draw_colored_polygon(_ellipse(m.ground, shadow_r, shadow_r * 0.45), Color(0, 0, 0, 0.35))
		var p: Vector2 = m.ground - Vector2(0, m.alt)
		draw_line(p, p - Vector2(0, 14), Color(1, 1, 1, 0.35), 3.0)
		draw_circle(p, 4.0, m.color)
	for f in flashes:
		var k: float = f.t / f.duration
		var col: Color = f.color
		col.a = 1.0 - k
		match f.kind:
			"explosion":
				draw_circle(f.pos, f.radius * (0.4 + 0.6 * k), col)
				draw_arc(f.pos, f.radius * (0.6 + 0.8 * k), 0, TAU, 24, Color(1, 0.9, 0.6, col.a), 2.0)
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
