## A small drawn icon beside a resource value in the top right: a gold coin
## for money, a red barrel with white bands for fuel, a blue beaker for
## research.
extends Control

const GOLD := Color(0.95, 0.78, 0.30)
const GOLD_DARK := Color(0.62, 0.45, 0.10)
const BARREL := Color(0.86, 0.24, 0.20)
const BARREL_DARK := Color(0.50, 0.10, 0.08)
const BAND := Color(0.95, 0.94, 0.90)
const BEAKER := Color(0.40, 0.80, 0.95)
const GLASS := Color(0.85, 0.93, 0.97)
const EDGE := Color(0.05, 0.06, 0.08)

var kind: String = "money"


func _init(k: String = "money") -> void:
	kind = k
	custom_minimum_size = Vector2(20, 20)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_PASS


func _draw() -> void:
	var c := size / 2.0
	match kind:
		"money":
			draw_circle(c, 9.0, EDGE)
			draw_circle(c, 8.0, GOLD_DARK)
			draw_circle(c + Vector2(-0.5, -0.5), 7.0, GOLD)
			draw_arc(c + Vector2(-0.5, -0.5), 4.6, 0, TAU, 20, GOLD_DARK, 1.2, true)
			draw_line(c + Vector2(-3.5, -3.5), c + Vector2(-1.5, -5.0), Color(1, 1, 1, 0.7), 1.5, true)
		"fuel":
			var body := Rect2(c + Vector2(-6.5, -8.5), Vector2(13, 17))
			draw_rect(body.grow(1.0), EDGE)
			draw_rect(body, BARREL)
			draw_rect(Rect2(body.position + Vector2(body.size.x - 3.5, 0), Vector2(3.5, body.size.y)), BARREL_DARK)
			for y in [3.0, 13.0]:
				draw_rect(Rect2(body.position + Vector2(0, y - 1.0), Vector2(body.size.x, 2.2)), BAND)
			draw_rect(Rect2(c + Vector2(1.5, -10.5), Vector2(3, 2)), EDGE)
		"research":
			# A conical flask: narrow neck, wide base, liquid in the bottom half.
			var top := c.y - 9.0
			var neck := PackedVector2Array([Vector2(c.x - 2.5, top), Vector2(c.x + 2.5, top),
				Vector2(c.x + 2.5, c.y - 3.0), Vector2(c.x + 8.0, c.y + 8.0), Vector2(c.x - 8.0, c.y + 8.0),
				Vector2(c.x - 2.5, c.y - 3.0)])
			draw_colored_polygon(neck, GLASS)
			var liquid := PackedVector2Array([Vector2(c.x - 5.3, c.y + 2.5), Vector2(c.x + 5.3, c.y + 2.5),
				Vector2(c.x + 8.0, c.y + 8.0), Vector2(c.x - 8.0, c.y + 8.0)])
			draw_colored_polygon(liquid, BEAKER)
			var outline := neck.duplicate()
			outline.append(neck[0])
			draw_polyline(outline, EDGE, 1.4, true)
			draw_line(Vector2(c.x - 4.0, top), Vector2(c.x + 4.0, top), EDGE, 1.6, true)
