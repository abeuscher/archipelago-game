## Retro hardware for the bottom-right corner, in the same beige plastic as
## the research mainframe: a radar monitor round the minimap, with chunky
## coloured keys beneath, and a comms set round the info screen, with the
## status gauge (our bases' hits left) on one side and the volume slider on
## the other. The builders only frame content; the content itself (the
## minimap, the info text, the gauge and slider) is made by hud.gd.
extends RefCounted

const ResearchPanel = preload("res://game/research_panel.gd")

const BEZEL := ResearchPanel.BEZEL
const BEZEL_EDGE := ResearchPanel.BEZEL_EDGE
const SCREEN := ResearchPanel.SCREEN
const SCREEN_EDGE := ResearchPanel.SCREEN_EDGE
const TEXT := ResearchPanel.TEXT
const DIM_TEXT := ResearchPanel.DIM_TEXT
const PLATE_INK := Color(0.2, 0.19, 0.16)
const KNOB_DARK := Color(0.25, 0.25, 0.24)
const KNOB := Color(0.55, 0.55, 0.52)
const LEDS := [Color(0.95, 0.25, 0.2), Color(0.98, 0.85, 0.25), Color(0.35, 0.9, 0.35), Color(0.98, 0.55, 0.2)]
## Key colours for the map keys, by icon.
const KEY_COLORS := {
	"rotate_left": Color(0.98, 0.82, 0.22),
	"rotate_right": Color(0.98, 0.58, 0.22),
	"zoom_in": Color(0.42, 0.80, 0.38),
	"zoom_out": Color(0.40, 0.62, 0.95),
}


static func box(bg: Color, edge: Color, width: int, radius: int, margins: Array) -> StyleBoxFlat:
	return ResearchPanel._box(bg, edge, width, radius, margins)


static func font(weight: int = 700) -> Font:
	return ResearchPanel._terminal_font(weight)


## The radar monitor: a name plate with lights, the screen holding
## `content`, and a row of `keys` beneath.
static func radar(content: Control, keys: Array) -> PanelContainer:
	var unit := PanelContainer.new()
	unit.add_theme_stylebox_override("panel", box(BEZEL, BEZEL_EDGE, 3, 18, [12, 8, 12, 10]))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 7)
	unit.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	v.add_child(head)
	head.add_child(_leds(LEDS.slice(0, 2)))
	var plate := _plate("RADAR")
	plate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(plate)
	head.add_child(_leds(LEDS.slice(2, 4)))
	v.add_child(_screen(content, 5))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	for k in keys:
		row.add_child(k)
	v.add_child(row)
	return unit


## The comms set: the gauge, the screen holding `content`, the slider.
static func comms(content: Control, screen_size: Vector2, gauge: Control, slider: Control) -> PanelContainer:
	var unit := PanelContainer.new()
	unit.add_theme_stylebox_override("panel", box(BEZEL, BEZEL_EDGE, 3, 18, [12, 10, 12, 10]))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	unit.add_child(row)
	row.add_child(_status_column(gauge))
	var scr := _screen(content, 10)
	scr.custom_minimum_size = screen_size
	scr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(scr)
	row.add_child(_comms_column(slider))
	return unit


## A chunky plastic key in its colour, sunk a little when pressed.
static func style_key(b: Button, color: Color) -> void:
	var edge := color.darkened(0.45)
	var normal := box(color, edge, 2, 7, [0, 0, 0, 0])
	normal.border_width_bottom = 5
	var hover := box(color.lightened(0.15), edge, 2, 7, [0, 0, 0, 0])
	hover.border_width_bottom = 5
	var pressed := box(color.darkened(0.12), edge, 2, 7, [0, 0, 0, 0])
	pressed.border_width_top = 4
	pressed.border_width_bottom = 2
	for s in [["normal", normal], ["hover", hover], ["pressed", pressed], ["hover_pressed", pressed],
			["disabled", normal], ["focus", StyleBoxEmpty.new()]]:
		b.add_theme_stylebox_override(s[0], s[1])


# --- Parts -------------------------------------------------------------------

## A dark glass screen round `content`, with a faint sheen and scan lines
## drawn over it (they let the mouse through).
static func _screen(content: Control, pad: int) -> PanelContainer:
	var scr := PanelContainer.new()
	scr.add_theme_stylebox_override("panel", box(SCREEN, SCREEN_EDGE, 5, 12, [pad, pad, pad, pad]))
	scr.add_child(content)
	var glass := Control.new()
	glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glass.draw.connect(func():
		var sz := glass.size
		for y in range(0, int(sz.y), 3):
			glass.draw_line(Vector2(0, y), Vector2(sz.x, y), Color(0, 0, 0, 0.06))
		glass.draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(sz.x * 0.55, 0),
			Vector2(0, sz.y * 0.45)]), Color(1, 1, 1, 0.05)))
	glass.resized.connect(glass.queue_redraw)
	scr.add_child(glass)
	return scr


static func _plate(text: String) -> Control:
	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override("panel", box(BEZEL.darkened(0.08), BEZEL_EDGE, 2, 5, [8, 1, 8, 1]))
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", font(700))
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", PLATE_INK)
	plate.add_child(l)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return plate


static func _leds(colors: Array) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(20 * colors.size(), 22)
	c.draw.connect(func():
		for i in colors.size():
			var p := Vector2(10 + 20 * i, c.size.y / 2.0)
			c.draw_circle(p, 7.0, Color(0.15, 0.15, 0.14))
			c.draw_circle(p, 5.0, colors[i])
			c.draw_circle(p + Vector2(-1.5, -1.5), 1.6, Color(1, 1, 1, 0.6)))
	return c


static func _label(text: String, size_px: int = 12) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", font(700))
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", PLATE_INK)
	return l


## Left of the comms screen: the gauge over its label.
static func _status_column(gauge: Control) -> Control:
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 4)
	col.custom_minimum_size = Vector2(62, 0)
	col.add_child(gauge)
	col.add_child(_label("STATUS"))
	return col


## Right of the comms screen: its label over the slider.
static func _comms_column(slider: Control) -> Control:
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 4)
	col.custom_minimum_size = Vector2(52, 0)
	col.add_child(_label("COMMS"))
	col.add_child(slider)
	return col
