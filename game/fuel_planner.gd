## The fuel planner at the top of the targeting toolbar (section 14): one
## cell per unit of fuel, filled as orders use it.
extends Control

const MAX_CELLS := 24

var fuel: int = 0
var planned: int = 0


func _init() -> void:
	custom_minimum_size = Vector2(0, 58)


func set_values(fuel_in: int, planned_in: int) -> void:
	fuel = fuel_in
	planned = planned_in
	queue_redraw()


func _draw() -> void:
	var font := get_theme_default_font()
	draw_string(font, Vector2(0, 16), "Fuel planned", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.85, 0.88, 0.9))
	var txt := "%d / %d" % [planned, fuel]
	draw_string(font, Vector2(0, 16), txt, HORIZONTAL_ALIGNMENT_RIGHT, size.x, 15,
		Color(1.0, 0.75, 0.3) if planned < fuel else Color(1.0, 0.45, 0.3))
	var area := Rect2(0, 26, size.x, 24)
	if fuel <= 0:
		draw_rect(area, Color(0.15, 0.15, 0.17))
		draw_string(font, Vector2(6, area.position.y + 17), "No fuel", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.6, 0.6, 0.62))
		return
	if fuel > MAX_CELLS:
		draw_rect(area, Color(0.15, 0.15, 0.17))
		draw_rect(Rect2(area.position, Vector2(area.size.x * planned / float(fuel), area.size.y)), Color(1.0, 0.6, 0.15))
		draw_rect(area, Color(0.5, 0.5, 0.55), false, 1.0)
		return
	var gap := 3.0
	var w := (area.size.x - gap * (fuel - 1)) / fuel
	for i in fuel:
		var r := Rect2(area.position.x + i * (w + gap), area.position.y, w, area.size.y)
		draw_rect(r, Color(1.0, 0.6, 0.15) if i < planned else Color(0.15, 0.15, 0.17))
		draw_rect(r, Color(0.5, 0.5, 0.55), false, 1.0)
