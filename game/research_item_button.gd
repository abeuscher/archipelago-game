## One research item on the research screen: a coloured bar with the
## item's name and price, its icon at the right, and a state line when it
## can't be started (researched, running in another lab, too expensive).
extends Button

const Icons = preload("res://game/research_icons.gd")
const INK := Color(0.10, 0.09, 0.08)

var item: String = ""
var title: String = ""
var detail: String = ""
var state: String = ""        ## shown instead of the detail when set
var font: Font


func _init() -> void:
	custom_minimum_size = Vector2(0, 50)
	focus_mode = Control.FOCUS_NONE
	for s in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		add_theme_stylebox_override(s, StyleBoxEmpty.new())
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)


func _draw() -> void:
	var col := Icons.color_of(item)
	if disabled:
		col = col.darkened(0.55)
	elif is_hovered():
		col = col.lightened(0.15)
	var box := StyleBoxFlat.new()
	box.bg_color = col
	box.border_color = INK
	box.set_border_width_all(2)
	box.set_corner_radius_all(8)
	draw_style_box(box, Rect2(Vector2.ZERO, size))
	# Icon in a lighter square at the right.
	var s := size.y - 12.0
	var icon_rect := Rect2(Vector2(size.x - s - 8.0, 6.0), Vector2(s, s))
	var sq := StyleBoxFlat.new()
	sq.bg_color = col.lightened(0.35)
	sq.border_color = INK
	sq.set_border_width_all(2)
	sq.set_corner_radius_all(6)
	draw_style_box(sq, icon_rect)
	Icons.draw(self, item, icon_rect.get_center(), s * 0.36, INK)
	var f: Font = font if font != null else get_theme_default_font()
	var text_ink := INK if not disabled else Color(0.18, 0.17, 0.16)
	draw_string(f, Vector2(14, 22), title.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, size.x - s - 40.0, 19, text_ink)
	draw_string(f, Vector2(14, 41), state if state != "" else detail, HORIZONTAL_ALIGNMENT_LEFT, size.x - s - 40.0, 13, text_ink)
