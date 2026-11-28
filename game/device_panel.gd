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


## The title at the top middle: a screwed-on beige plate in big dark
## letters (the round, or SETUP before round 1). The small line above is
## kept hidden. Returns [plate, small label, title label].
static func title_plate() -> Array:
	var plate := PanelContainer.new()
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var st := box(BEZEL, BEZEL_EDGE, 4, 12, [34, 6, 34, 8])
	st.border_width_bottom = 6
	st.shadow_color = Color(0, 0, 0, 0.35)
	st.shadow_size = 4
	st.shadow_offset = Vector2(0, 3)
	plate.add_theme_stylebox_override("panel", st)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", -2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(col)
	var round_l := _label("", 13)
	round_l.add_theme_color_override("font_color", PLATE_INK.lightened(0.3))
	round_l.visible = false   # unused for now; shown, it would push the title down
	col.add_child(round_l)
	var phase := Label.new()
	phase.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var heavy := FontVariation.new()
	heavy.base_font = ThemeDB.fallback_font
	heavy.variation_embolden = 1.1
	heavy.spacing_glyph = 2
	phase.add_theme_font_override("font", heavy)
	phase.add_theme_font_size_override("font_size", 29)
	phase.add_theme_color_override("font_color", PLATE_INK)
	phase.add_theme_color_override("font_shadow_color", Color(1, 1, 1, 0.4))
	phase.add_theme_constant_override("shadow_offset_x", 0)
	phase.add_theme_constant_override("shadow_offset_y", 2)
	col.add_child(phase)
	# A screw in each corner of the plate.
	plate.draw.connect(func():
		var w := plate.size.x
		var h := plate.size.y
		for p in [Vector2(14, 13), Vector2(w - 14, 13), Vector2(14, h - 15), Vector2(w - 14, h - 15)]:
			plate.draw_circle(p, 5.0, BEZEL_EDGE)
			plate.draw_circle(p, 3.8, Color(0.68, 0.66, 0.58))
			plate.draw_line(p + Vector2(-2.6, -1.3), p + Vector2(2.6, 1.3), BEZEL_EDGE, 1.3))
	return [plate, round_l, phase]


## The log monitor: a name plate with a red CLOSE button, the screen
## holding `content`, and a row of lights beneath.
static func log_unit(content: Control, on_close: Callable) -> PanelContainer:
	var unit := PanelContainer.new()
	unit.add_theme_stylebox_override("panel", box(BEZEL, BEZEL_EDGE, 3, 18, [14, 10, 14, 10]))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	unit.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	v.add_child(head)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(72, 0)
	head.add_child(spacer)
	var plate := _plate("LOG / RECORDS")
	plate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(plate)
	head.add_child(close_button(on_close))
	var scr := _screen(content, 14)
	scr.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scr)
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	foot.add_child(_leds(LEDS))
	v.add_child(foot)
	return unit


## The red pill-shaped CLOSE button of the mainframe screens.
static func close_button(on_close: Callable) -> Button:
	var close := Button.new()
	close.text = "CLOSE"
	close.focus_mode = Control.FOCUS_NONE
	close.custom_minimum_size = Vector2(72, 30)
	close.add_theme_font_override("font", font(700))
	close.add_theme_font_size_override("font_size", 13)
	close.add_theme_color_override("font_color", Color(1, 0.95, 0.9))
	close.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	var edge := Color(0.35, 0.10, 0.06)
	close.add_theme_stylebox_override("normal", box(Color(0.88, 0.32, 0.18), edge, 3, 15, [8, 3, 8, 3]))
	close.add_theme_stylebox_override("hover", box(Color(0.96, 0.42, 0.24), edge, 3, 15, [8, 3, 8, 3]))
	close.add_theme_stylebox_override("pressed", box(Color(0.70, 0.24, 0.14), edge, 3, 15, [8, 3, 8, 3]))
	close.pressed.connect(on_close)
	return close


const BOOK_HALF := Vector2(9, 11)   ## half the book's cover, from the icon's centre to its top-right corner
const BOOK_OUTLINE := 1.5           ## the dark outline round the cover


## How much the book is scaled in a control of `size` when it fills the
## height (book_icon's fit): the cover and its outline exactly as tall.
static func book_scale(size: Vector2) -> float:
	return size.y / (2.0 * (BOOK_HALF.y + BOOK_OUTLINE))


## A small book, for the log button. shadow: a soft drop shadow under it,
## for when it sits on the panel without a key. fit: scaled so the book is
## exactly as tall as the control (otherwise drawn at its own size).
static func book_icon(shadow := false, fit := false) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.draw.connect(func():
		var m := Vector2.ZERO
		if fit:
			var k := book_scale(c.size)
			c.draw_set_transform(c.size / 2.0 + Vector2(0, 0.5 * k), 0.0, Vector2(k, k))
		else:
			m = c.size / 2.0
		var cover := Rect2(m + Vector2(-9, -11), Vector2(18, 21))
		if shadow:
			c.draw_rect(Rect2(cover.position + Vector2(2.5, 2.5), cover.size).grow(1.5), Color(0, 0, 0, 0.35))
		c.draw_rect(cover.grow(1.5), PLATE_INK)
		c.draw_rect(cover, Color(0.55, 0.25, 0.12))
		c.draw_rect(Rect2(cover.position + Vector2(3, 0), Vector2(15, 18)), Color(0.96, 0.93, 0.84))
		c.draw_rect(Rect2(cover.position + Vector2(3, 0), Vector2(15, 18)), PLATE_INK, false, 1.0)
		c.draw_rect(Rect2(cover.position, Vector2(4, cover.size.y)), Color(0.42, 0.18, 0.08))
		for y in [5.0, 9.0, 13.0]:
			c.draw_line(cover.position + Vector2(7, y), cover.position + Vector2(15, y), Color(0.55, 0.52, 0.45), 1.2))
	return c


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
