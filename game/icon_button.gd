## A square map-control button with a drawn icon: rotate left or right, or
## a magnifying glass with + or - for zoom. The name goes in the tooltip.
extends Button

const SIZE := Vector2(40, 36)
const INK := Color(0.9, 0.93, 0.96)

var icon_kind: String = ""   ## "rotate_left", "rotate_right", "zoom_in", "zoom_out"


func _init(kind: String = "", tip: String = "") -> void:
	icon_kind = kind
	tooltip_text = tip
	custom_minimum_size = SIZE
	focus_mode = Control.FOCUS_NONE


func _draw() -> void:
	var c := size / 2.0
	var ink := INK if not disabled else Color(0.45, 0.47, 0.5)
	match icon_kind:
		"rotate_left":
			_rotate_arrow(c, 1.0, ink)
		"rotate_right":
			_rotate_arrow(c, -1.0, ink)
		"zoom_in", "zoom_out":
			_magnifier(c, icon_kind == "zoom_in", ink)


## An open circle with an arrowhead at the top: dir +1 reads anticlockwise,
## -1 clockwise.
func _rotate_arrow(c: Vector2, dir: float, ink: Color) -> void:
	var r := 9.0
	var gap_mid := -PI / 2.0          # the gap sits at the top
	var a0 := gap_mid + dir * 0.55
	var a1 := gap_mid + dir * (TAU - 0.55)
	draw_arc(c, r, minf(a0, a1), maxf(a0, a1), 28, ink, 2.0, true)
	var tip := c + Vector2(cos(a0), sin(a0)) * r
	var tangent := Vector2(-sin(a0), cos(a0)) * -dir
	var side := tangent.orthogonal()
	draw_colored_polygon(PackedVector2Array([tip + tangent * 5.0, tip - tangent * 1.0 + side * 4.5,
		tip - tangent * 1.0 - side * 4.5]), ink)


func _magnifier(c: Vector2, plus: bool, ink: Color) -> void:
	var lens := c + Vector2(-2.5, -2.5)
	draw_arc(lens, 7.5, 0.0, TAU, 28, ink, 2.0, true)
	draw_line(lens + Vector2(5.5, 5.5), lens + Vector2(11.5, 11.5), ink, 3.0, true)
	draw_line(lens + Vector2(-3.5, 0), lens + Vector2(3.5, 0), ink, 2.0)
	if plus:
		draw_line(lens + Vector2(0, -3.5), lens + Vector2(0, 3.5), ink, 2.0)
