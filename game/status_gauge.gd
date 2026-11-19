## The dial on the comms set: how many hits our bases can still take before
## we lose, counting down from all bases at full strength (6 with three bases
## of two hits each). The needle sweeps from full on the right to the red
## zone on the left; the number sits under the needle.
extends Control

const ResearchPanel = preload("res://game/research_panel.gd")

const FACE := Color(0.95, 0.93, 0.86)
const INK := Color(0.2, 0.19, 0.16)
const RED := Color(0.85, 0.22, 0.17)
const AMBER := Color(0.95, 0.68, 0.18)
const GREEN := Color(0.30, 0.66, 0.30)
const RADIUS := 25.0

var hits_left: float = 6.0
var hits_max: float = 6.0
var _font: Font


func _init() -> void:
	custom_minimum_size = Vector2(62, 50)
	_font = ResearchPanel._terminal_font(700)


func set_hits(left: float, most: float) -> void:
	hits_left = maxf(left, 0.0)
	hits_max = maxf(most, 1.0)
	tooltip_text = "Bases: %s of %d hits left before we lose" % [_fmt(hits_left), int(hits_max)]
	queue_redraw()


func _draw() -> void:
	var c := Vector2(size.x / 2.0, size.y - 16)
	# A half-round face with a flat bottom, edged like the bezel.
	var face := PackedVector2Array()
	for k in 25:
		var a := PI + PI * k / 24.0
		face.append(c + Vector2(cos(a), sin(a)) * RADIUS)
	draw_colored_polygon(face, FACE)
	face.append(face[0])
	draw_polyline(face, ResearchPanel.BEZEL_EDGE, 2.0, true)
	# Coloured bands: red for the last third, amber, then green.
	var bands := [[0.0, 1.0 / 3.0, RED], [1.0 / 3.0, 2.0 / 3.0, AMBER], [2.0 / 3.0, 1.0, GREEN]]
	for b in bands:
		draw_arc(c, RADIUS - 4, _angle(b[0]), _angle(b[1]), 12, b[2], 4.0)
	# A tick per hit.
	var n := int(hits_max)
	for k in n + 1:
		var a := _angle(float(k) / n)
		draw_line(c + Vector2(cos(a), sin(a)) * (RADIUS - 10), c + Vector2(cos(a), sin(a)) * (RADIUS - 7), INK, 1.5)
	var a_needle := _angle(hits_left / hits_max)
	draw_line(c, c + Vector2(cos(a_needle), sin(a_needle)) * (RADIUS - 6), RED, 2.0, true)
	draw_circle(c, 3.0, INK)
	# The count, on the bezel just under the face.
	var txt := _fmt(hits_left)
	var w := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	draw_string(_font, Vector2(c.x - w / 2.0, c.y + 15), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
		RED if hits_left <= hits_max / 3.0 else INK)


## 0 (no hits left) is up on the left, 1 (untouched) up on the right; the
## needle never lies flat along the bottom.
static func _angle(f: float) -> float:
	return PI + 0.4 + (PI - 0.8) * clampf(f, 0.0, 1.0)


static func _fmt(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, roundf(v)) else "%.1f" % v
