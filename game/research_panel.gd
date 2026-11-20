## The research screen (section 14), styled as an old mainframe monitor.
## It covers everything right of the toolbar, so the island is hidden while
## it is open and the toolbar stays usable. It shows the research points and
## money on hand, and every research item as a coloured button with an icon:
## pressing one buys it with its money and points, done at once. Belongs to
## the build and repair phase; outside it the screen is read-only.
extends Control

const Pieces = preload("res://game/pieces.gd")
const Earnings = preload("res://game/earnings.gd")
const Icons = preload("res://game/research_icons.gd")
const ItemButton = preload("res://game/research_item_button.gd")

signal research_requested(item: String)
signal closed

const BACKDROP := Color(0.05, 0.07, 0.09, 1.0)
const BEZEL := Color(0.80, 0.78, 0.69)
const BEZEL_EDGE := Color(0.36, 0.35, 0.31)
const SCREEN := Color(0.15, 0.21, 0.19)
const SCREEN_EDGE := Color(0.07, 0.09, 0.08)
const TEXT := Color(0.86, 0.95, 0.82)
const DIM_TEXT := Color(0.58, 0.68, 0.58)
const ALERT := Color(1.0, 0.88, 0.35)
const LED_COLORS := [Color(0.95, 0.25, 0.2), Color(0.35, 0.9, 0.35), Color(0.98, 0.85, 0.25)]

var _font: Font
var _bold: Font
var _title: Label
var _lab_line: Label
var _status: Label
var _items: VBoxContainer
var _tab: String = "buildings"         ## "buildings" or "upgrades"
var _tab_buttons: Dictionary = {}
var _st
var _data
var _editable: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP   # nothing reaches the board behind
	_font = _terminal_font(500)
	_bold = _terminal_font(700)
	var back := ColorRect.new()
	back.color = BACKDROP
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var monitor := PanelContainer.new()
	monitor.add_theme_stylebox_override("panel", _box(BEZEL, BEZEL_EDGE, 4, 34, [26, 22, 26, 22]))
	center.add_child(monitor)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	monitor.add_child(row)
	row.add_child(_side_panel(true))

	var screen := PanelContainer.new()
	screen.custom_minimum_size = Vector2(620, 470)
	screen.add_theme_stylebox_override("panel", _box(SCREEN, SCREEN_EDGE, 7, 22, [22, 16, 22, 16]))
	row.add_child(screen)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	screen.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	_title = _label("RESEARCH", 26, TEXT, true)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	var close := Button.new()
	close.text = "CLOSE"
	close.focus_mode = Control.FOCUS_NONE
	close.custom_minimum_size = Vector2(72, 34)
	close.add_theme_font_override("font", _bold)
	close.add_theme_font_size_override("font_size", 13)
	close.add_theme_color_override("font_color", Color(1, 0.95, 0.9))
	close.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	close.add_theme_stylebox_override("normal", _box(Color(0.88, 0.32, 0.18), Color(0.35, 0.10, 0.06), 3, 17, [8, 4, 8, 4]))
	close.add_theme_stylebox_override("hover", _box(Color(0.96, 0.42, 0.24), Color(0.35, 0.10, 0.06), 3, 17, [8, 4, 8, 4]))
	close.add_theme_stylebox_override("pressed", _box(Color(0.70, 0.24, 0.14), Color(0.35, 0.10, 0.06), 3, 17, [8, 4, 8, 4]))
	close.pressed.connect(func(): visible = false; closed.emit())
	head.add_child(close)
	# Tabs: new building types, or upgrades to what the side already has.
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	v.add_child(tabs)
	for t in [["buildings", "BUILDINGS"], ["upgrades", "UPGRADES"]]:
		var tb := Button.new()
		tb.text = t[1]
		tb.focus_mode = Control.FOCUS_NONE
		tb.custom_minimum_size = Vector2(140, 30)
		tb.add_theme_font_override("font", _bold)
		tb.add_theme_font_size_override("font_size", 15)
		var key: String = t[0]
		tb.pressed.connect(func(): _tab = key; show_state(_st, _data, _editable))
		tabs.add_child(tb)
		_tab_buttons[key] = tb
	_lab_line = _label("", 14, DIM_TEXT)
	v.add_child(_lab_line)
	_status = _label("", 16, ALERT, true)
	v.add_child(_status)
	_items = VBoxContainer.new()
	_items.add_theme_constant_override("separation", 7)
	v.add_child(_items)

	row.add_child(_side_panel(false))


## The bezel either side of the screen: status lights, a label plate on the
## left, knobs on the right. Decoration only.
func _side_panel(left: bool) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.custom_minimum_size = Vector2(40, 0)
	for c in LED_COLORS:
		var led := Control.new()
		led.custom_minimum_size = Vector2(40, 18)
		var lc: Color = c
		led.draw.connect(func():
			var p := led.size / 2.0
			led.draw_circle(p, 8.0, Color(0.15, 0.15, 0.14))
			led.draw_circle(p, 6.0, lc)
			led.draw_circle(p + Vector2(-2, -2), 2.0, Color(1, 1, 1, 0.6)))
		col.add_child(led)
	var plate := Control.new()
	plate.custom_minimum_size = Vector2(40, 150 if left else 110)
	plate.draw.connect(func():
		var r := Rect2(Vector2(6, 4), plate.size - Vector2(12, 8))
		plate.draw_style_box(_box(BEZEL.darkened(0.08), BEZEL_EDGE, 2, 6, [0, 0, 0, 0]), r)
		if left:
			plate.draw_set_transform(r.get_center() + Vector2(6, 52), -PI / 2.0, Vector2.ONE)
			plate.draw_string(_bold, Vector2.ZERO, "MAINFRAME", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.2, 0.19, 0.16))
			plate.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			for k in 2:
				var kc := Vector2(r.get_center().x, r.position.y + 26 + k * 50)
				plate.draw_circle(kc, 13.0, Color(0.25, 0.25, 0.24))
				plate.draw_circle(kc, 10.0, Color(0.55, 0.55, 0.52))
				plate.draw_line(kc, kc + Vector2(0, -9).rotated(0.6 + k * 1.4), Color(0.15, 0.15, 0.14), 2.0))
	col.add_child(plate)
	return col


# --- State -----------------------------------------------------------------

## Opens the screen (from any lab; they all share the side's points).
func open_lab(st, data, _lab_id: int, editable: bool) -> void:
	visible = true
	show_state(st, data, editable)


func show_state(st, data, editable: bool) -> void:
	_st = st
	_data = data
	_editable = editable
	_style_tabs()
	for c in _items.get_children():
		c.queue_free()
	var rate := int(st.compute_income(data)["research"])
	_lab_line.text = "RESEARCH POINTS %d (+%d A ROUND)    MONEY %d" % [st.research, rate, st.money]
	if st.count_role(data, "lab") == 0:
		_status.text = "NO LABS. BUILD A LAB TO EARN RESEARCH POINTS."
	elif not editable:
		_status.text = "RESEARCH IN THE BUILD AND REPAIR PHASE."
	else:
		_status.text = "CHOOSE RESEARCH: _"
	for item in data.research_items():
		if not bool(data.research_item(item).get("available", true)):
			continue   # not in this level
		if String(data.research_item(item).get("tab", "upgrades")) == _tab:
			_items.add_child(_item_button(st, data, item))


func _item_button(st, data, item: String) -> Control:
	var def: Dictionary = data.research_item(item)
	var b := ItemButton.new()
	b.font = _bold
	b.item = item
	b.title = Pieces.research_name(item)
	b.detail = "%d money, %d points" % [int(def["cost"]), int(def["points"])]
	var err: String = st.can_research(item, data)
	if st.is_unlocked(item):
		b.state = "RESEARCHED"
	elif err == "Not enough research":
		var left := Earnings.rounds_to_afford(st, data, item)
		var more: int = int(def["points"]) - st.research
		b.state = "NEEDS %d MORE POINTS%s" % [more, "" if left < 0 else " (ABOUT %d ROUND%s)" % [left, "" if left == 1 else "S"]]
	elif err != "":
		b.state = err.to_upper()
	b.disabled = not _editable or err != ""
	b.tooltip_text = Pieces.RESEARCH_TEXT.get(item, "")
	b.pressed.connect(func(): research_requested.emit(item))
	return b


# --- Bits ------------------------------------------------------------------

## The selected tab is lit (screen-coloured text on a bright block); the
## other is an outline.
func _style_tabs() -> void:
	for key in _tab_buttons:
		var tb: Button = _tab_buttons[key]
		var on: bool = key == _tab
		var fill := TEXT if on else SCREEN
		var edge := TEXT if on else DIM_TEXT
		for s in ["normal", "hover", "pressed", "hover_pressed"]:
			tb.add_theme_stylebox_override(s, _box(fill if s != "hover" or on else SCREEN.lightened(0.08), edge, 2, 4, [10, 3, 10, 3]))
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
			tb.add_theme_color_override(c, SCREEN if on else TEXT)


func _label(text: String, size_px: int, color: Color, bold: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _bold if bold else _font)
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	return l


func _flat_button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", _bold)
	b.add_theme_color_override("font_color", TEXT)
	for s in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(s, StyleBoxEmpty.new())
	b.pressed.connect(action)
	return b


static func _box(bg: Color, edge: Color, width: int, radius: int, margins: Array) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = edge
	s.set_border_width_all(width)
	s.set_corner_radius_all(radius)
	s.content_margin_left = margins[0]
	s.content_margin_top = margins[1]
	s.content_margin_right = margins[2]
	s.content_margin_bottom = margins[3]
	return s


## A monospaced system font for the terminal look (Consolas on Windows),
## falling back to the default font where none is found.
static func _terminal_font(weight: int) -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Consolas", "Lucida Console", "DejaVu Sans Mono", "Courier New", "monospace"])
	f.font_weight = weight
	return f
