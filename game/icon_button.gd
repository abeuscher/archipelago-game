## A square button with a drawn icon: rotate left or right, or a magnifying
## glass with + or - for zoom. The name goes in the tooltip. The icons are
## also drawn on toolbar buttons (undo, start) through draw_icon.
extends Button

const SIZE := Vector2(40, 36)
const INK := Color(0.9, 0.93, 0.96)

var icon_kind: String = ""   ## "rotate_left", "rotate_right", "zoom_in", "zoom_out", "undo", "start"


func _init(kind: String = "", tip: String = "") -> void:
	icon_kind = kind
	tooltip_text = tip
	custom_minimum_size = SIZE
	focus_mode = Control.FOCUS_NONE


func _draw() -> void:
	draw_icon(self, icon_kind, size / 2.0, INK if not disabled else Color(0.45, 0.47, 0.5))


static func draw_icon(ci: CanvasItem, kind: String, c: Vector2, ink: Color) -> void:
	match kind:
		"rotate_left":
			_rotate_arrow(ci, c, 1.0, ink)
		"rotate_right":
			_rotate_arrow(ci, c, -1.0, ink)
		"zoom_in", "zoom_out":
			_magnifier(ci, c, kind == "zoom_in", ink)
		"undo":
			_undo_arrow(ci, c, ink)
		"start":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-5, -7), c + Vector2(7, 0), c + Vector2(-5, 7)]), ink)


## An open circle with an arrowhead at the top: dir +1 reads anticlockwise,
## -1 clockwise.
static func _rotate_arrow(ci: CanvasItem, c: Vector2, dir: float, ink: Color) -> void:
	var r := 9.0
	var gap_mid := -PI / 2.0          # the gap sits at the top
	var a0 := gap_mid + dir * 0.55
	var a1 := gap_mid + dir * (TAU - 0.55)
	ci.draw_arc(c, r, minf(a0, a1), maxf(a0, a1), 28, ink, 2.0, true)
	var tip := c + Vector2(cos(a0), sin(a0)) * r
	var tangent := Vector2(-sin(a0), cos(a0)) * -dir
	var side := tangent.orthogonal()
	ci.draw_colored_polygon(PackedVector2Array([tip + tangent * 5.0, tip - tangent * 1.0 + side * 4.5,
		tip - tangent * 1.0 - side * 4.5]), ink)


static func _magnifier(ci: CanvasItem, c: Vector2, plus: bool, ink: Color) -> void:
	var lens := c + Vector2(-2.5, -2.5)
	ci.draw_arc(lens, 7.5, 0.0, TAU, 28, ink, 2.0, true)
	ci.draw_line(lens + Vector2(5.5, 5.5), lens + Vector2(11.5, 11.5), ink, 3.0, true)
	ci.draw_line(lens + Vector2(-3.5, 0), lens + Vector2(3.5, 0), ink, 2.0)
	if plus:
		ci.draw_line(lens + Vector2(0, -3.5), lens + Vector2(0, 3.5), ink, 2.0)


## A hook arrow curling back to the left.
static func _undo_arrow(ci: CanvasItem, c: Vector2, ink: Color) -> void:
	ci.draw_arc(c + Vector2(1, 1), 6.5, -PI / 2.0, PI / 2.0, 16, ink, 2.0, true)
	ci.draw_line(c + Vector2(1, 7.5), c + Vector2(-5, 7.5), ink, 2.0, true)
	var tip := c + Vector2(-7, -5.5)
	ci.draw_line(c + Vector2(1, -5.5), tip + Vector2(3, 0), ink, 2.0, true)
	ci.draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(5, -4), tip + Vector2(5, 4)]), ink)
