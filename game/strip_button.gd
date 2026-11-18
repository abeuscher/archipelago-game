## One button in the right-hand strip (section 14). All buttons are the same
## size. kind "beaker": a research item in progress, filling as it advances.
## kind "base": one of our bases, coloured by the hits it has left.
extends Button

const SIZE := Vector2(64, 64)
const GREEN := Color(0.30, 0.80, 0.35)
const YELLOW := Color(0.95, 0.80, 0.20)
const RED := Color(0.90, 0.25, 0.20)
const DEAD := Color(0.30, 0.30, 0.33)

var kind: String = "beaker"
var fraction: float = 0.0      ## beaker: progress 0..1
var hits_left: float = 3.0     ## base
var hits_max: float = 3.0
var details: String = ""       ## shown in the strip's title bar on hover


func _init() -> void:
	custom_minimum_size = SIZE
	focus_mode = Control.FOCUS_NONE


static func base_color(left: float) -> Color:
	if left <= 0.0:
		return DEAD
	if left >= 3.0:
		return GREEN
	if left >= 2.0:
		return YELLOW
	return RED


func _draw() -> void:
	var c := size / 2.0
	if kind == "beaker":
		_draw_beaker(c)
	else:
		_draw_base(c)


func _draw_beaker(c: Vector2) -> void:
	# A conical flask: neck on top, wide bottom.
	var top := c.y - 22.0
	var neck := c.y - 8.0
	var bot := c.y + 20.0
	var outline := PackedVector2Array([
		Vector2(c.x - 6, top), Vector2(c.x + 6, top), Vector2(c.x + 6, neck),
		Vector2(c.x + 20, bot), Vector2(c.x - 20, bot), Vector2(c.x - 6, neck)])
	draw_colored_polygon(outline, Color(0.12, 0.16, 0.2))
	var level := bot - (bot - top) * clampf(fraction, 0.0, 1.0)
	var liquid := _clip_below(outline, level)
	if liquid.size() >= 3:
		draw_colored_polygon(liquid, Color(0.35, 0.85, 0.95))
	var closed := outline.duplicate()
	closed.append(outline[0])
	draw_polyline(closed, Color(0.85, 0.9, 0.95), 2.0)


func _draw_base(c: Vector2) -> void:
	var col := base_color(hits_left)
	var shield := PackedVector2Array([
		Vector2(c.x - 18, c.y - 20), Vector2(c.x + 18, c.y - 20), Vector2(c.x + 18, c.y + 2),
		Vector2(c.x, c.y + 22), Vector2(c.x - 18, c.y + 2)])
	draw_colored_polygon(shield, col)
	var closed := shield.duplicate()
	closed.append(shield[0])
	draw_polyline(closed, col.darkened(0.6), 2.0)
	var font := get_theme_default_font()
	var txt := "X" if hits_left <= 0.0 else _fmt(hits_left)
	var fs := 20
	var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, Vector2(c.x - tw / 2.0, c.y + 6), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.05, 0.05, 0.05))


static func _fmt(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, roundf(v)) else "%.1f" % v


## The part of a convex polygon at or below screen height y.
static func _clip_below(poly: PackedVector2Array, y: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var a_in := a.y >= y
		var b_in := b.y >= y
		if a_in:
			out.append(a)
		if a_in != b_in:
			var t := (y - a.y) / (b.y - a.y)
			out.append(a.lerp(b, t))
	return out
