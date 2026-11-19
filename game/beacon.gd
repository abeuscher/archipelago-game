## The alarm light, sitting on top of the round timer: a red dome like an ambulance
## light. Off, it sits dim. On, a bright spot sweeps round the dome and
## beams of light turn across the panel behind it.
extends Control

const DOME := Color(0.85, 0.12, 0.10)
const DOME_OFF := Color(0.32, 0.08, 0.07)
const BASE := Color(0.22, 0.23, 0.26)
const BEAM := Color(1.0, 0.25, 0.15)
const SPIN := 5.0            ## radians a second

var active: bool = false
var _angle: float = 0.0


func _init() -> void:
	custom_minimum_size = Vector2(0, 44)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_active(on: bool) -> void:
	if on == active:
		return
	active = on
	queue_redraw()


func _process(delta: float) -> void:
	if active:
		_angle = fmod(_angle + delta * SPIN, TAU)
		queue_redraw()


func _draw() -> void:
	var c := Vector2(size.x / 2.0, size.y - 8.0)   # its base sits on the timer below
	var r := 15.0
	if active:
		# Two beams on opposite sides of the turning lamp, widest when they
		# face the viewer (sideways on screen).
		for k in 2:
			var a := _angle + k * PI
			if absf(cos(a)) < 0.08:
				continue   # edge-on: no visible beam
			var dir := Vector2(cos(a), 0.0)
			var facing := absf(sin(a))
			var reach := 30.0 + 70.0 * absf(cos(a))
			var spread := 9.0 + 10.0 * facing
			var tip := c + Vector2(0, -r * 0.55) + dir * reach
			var col := Color(BEAM, 0.10 + 0.22 * absf(cos(a)))
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r * 0.55),
				tip + Vector2(0, -spread), tip + Vector2(0, spread)]), col)
		draw_circle(c + Vector2(0, -r * 0.5), r * 2.0, Color(BEAM, 0.12 + 0.06 * sin(_angle * 2.0)))
	# Base.
	draw_rect(Rect2(c + Vector2(-r - 5, 0), Vector2((r + 5) * 2, 8)), BASE)
	draw_rect(Rect2(c + Vector2(-r - 5, 0), Vector2((r + 5) * 2, 8)), Color(0, 0, 0, 0.6), false, 1.0)
	# Dome: a half disc with a rounded top.
	var dome := PackedVector2Array()
	for k in 17:
		var t := PI + PI * k / 16.0
		dome.append(c + Vector2(cos(t) * r, sin(t) * r * 1.15))
	draw_colored_polygon(dome, DOME if active else DOME_OFF)
	if active:
		var spot_x := cos(_angle) * r * 0.6
		draw_circle(c + Vector2(spot_x, -r * 0.55), r * 0.38, Color(1.0, 0.85, 0.75, 0.9))
		draw_circle(c + Vector2(spot_x, -r * 0.55), r * 0.7, Color(1.0, 0.5, 0.4, 0.35))
	draw_polyline(dome, Color(0, 0, 0, 0.55), 1.2, true)
	draw_line(c + Vector2(-r * 0.45, -r * 0.85), c + Vector2(-r * 0.2, -r * 0.95), Color(1, 1, 1, 0.35), 2.0, true)
