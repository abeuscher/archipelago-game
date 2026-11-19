## One button in the right-hand strip (section 14): a research item in
## progress, drawn as a beaker filling as it advances. (Our bases' strength
## is on the comms set's status gauge.)
extends Button

const SIZE := Vector2(64, 64)
var kind: String = "beaker"
var fraction: float = 0.0      ## beaker: progress 0..1
var details: String = ""       ## shown in the strip's title bar on hover


func _init() -> void:
	custom_minimum_size = SIZE
	focus_mode = Control.FOCUS_NONE


func _draw() -> void:
	_draw_beaker(size / 2.0)


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
