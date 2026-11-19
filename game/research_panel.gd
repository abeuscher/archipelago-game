## The research screen (section 14), styled as an old mainframe monitor.
## It covers everything right of the toolbar, so the island is hidden while
## it is open and the toolbar stays usable. One lab per page, with a pager
## when there are several. The screen shows the lab, its project (or what it
## is helping), and every research item as a coloured button with an icon:
## pressing one starts the lab on it. Belongs to the build and repair phase;
## outside it the screen is read-only.
extends Control

const Pieces = preload("res://game/pieces.gd")
const Earnings = preload("res://game/earnings.gd")
const Icons = preload("res://game/research_icons.gd")
const ItemButton = preload("res://game/research_item_button.gd")

signal start_requested(lab_id: int, item: String)
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

var lab_index: int = 0
var _font: Font
var _bold: Font
var _title: Label
var _lab_line: Label
var _status: Label
var _project: VBoxContainer
var _items: VBoxContainer
var _prev: Button
var _next: Button
var _pager: Label
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
	_prev = _flat_button("<", func(): _page(-1))
	_prev.tooltip_text = "Previous lab"
	head.add_child(_prev)
	_pager = _label("", 15, TEXT, true)
	_pager.custom_minimum_size = Vector2(96, 0)
	_pager.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(_pager)
	_next = _flat_button(">", func(): _page(1))
	_next.tooltip_text = "Next lab"
	head.add_child(_next)
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
	_project = VBoxContainer.new()
	_project.add_theme_constant_override("separation", 4)
	v.add_child(_project)
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

func _page(d: int) -> void:
	if _st == null:
		return
	var n: int = _st.of_role(_data, "lab").size()
	if n > 0:
		lab_index = (lab_index + d + n) % n
	show_state(_st, _data, _editable)


## Open on the lab with this building id.
func open_lab(st, data, lab_id: int, editable: bool) -> void:
	var labs: Array = st.of_role(data, "lab")
	for i in labs.size():
		if labs[i].id == lab_id:
			lab_index = i
	visible = true
	show_state(st, data, editable)


func show_state(st, data, editable: bool) -> void:
	_st = st
	_data = data
	_editable = editable
	_style_tabs()
	for c in _project.get_children() + _items.get_children():
		c.queue_free()
	var labs: Array = st.of_role(data, "lab")
	_prev.visible = labs.size() > 1
	_next.visible = labs.size() > 1
	if labs.is_empty():
		_pager.text = ""
		_lab_line.text = "MONEY %d" % st.money
		_status.text = "NO LABS. BUILD A LAB TO RESEARCH."
		return
	lab_index = clampi(lab_index, 0, labs.size() - 1)
	var lab = labs[lab_index]
	_pager.text = "LAB %d OF %d" % [lab_index + 1, labs.size()]
	var pts: int = st.output_of(lab, int(data.building(lab.type)["produces"].get("research", 0)), data)
	var note := ""
	if st.out_for_repair(lab, data):
		note = ", UNDER REPAIR"
	elif st.is_half_strength(lab, data):
		note = ", DAMAGED"
	_lab_line.text = "LAB %d (HP %d/%d, +%d PTS/ROUND%s)    MONEY %d" % [lab_index + 1, lab.hp, data.max_hp(lab.type), pts, note, st.money]

	var own = st.project_for_lab(lab.id)
	var oldest = st.oldest_project()
	if own != null:
		_status.text = "RESEARCHING:"
		_project_block(st, data, String(own["item"]))
	elif oldest != null:
		_status.text = "NO PROJECT OF ITS OWN. HELPING:"
		_project_block(st, data, String(oldest["item"]))
	else:
		_status.text = "NO ACTIVE PROJECT!"
	if own == null:
		var prompt := _label("START RESEARCH: _" if editable else "CHOOSE RESEARCH IN THE BUILD AND REPAIR PHASE.", 16, ALERT, true)
		_items.add_child(prompt)
	for item in data.research_items():
		if String(data.research_item(item).get("tab", "upgrades")) == _tab:
			_items.add_child(_item_button(st, data, lab, item, own != null))


func _item_button(st, data, lab, item: String, lab_busy: bool) -> Control:
	var def: Dictionary = data.research_item(item)
	var b := ItemButton.new()
	b.font = _bold
	b.item = item
	b.title = Pieces.research_name(item)
	var p = st.project_for_item(item)
	b.detail = "%s, %d points" % ["resume free" if p != null else "%d money" % int(def["cost"]), int(def["points"])]
	if p != null and int(p["progress"]) > 0:
		b.detail += "  (%d done)" % int(p["progress"])
	var err: String = st.can_start_research(lab.id, item, data)
	if not bool(def.get("available", true)):
		b.state = "COMING SOON"
	elif st.is_unlocked(item):
		b.state = "RESEARCHED"
	elif p != null and int(p["lab_id"]) != -1 and int(p["lab_id"]) != lab.id:
		b.state = "IN PROGRESS IN ANOTHER LAB"
	elif p != null and int(p["lab_id"]) == lab.id:
		b.state = "IN PROGRESS HERE"
	elif not lab_busy and err != "":
		b.state = err.to_upper()
	b.disabled = not _editable or lab_busy or err != ""
	b.tooltip_text = Pieces.RESEARCH_TEXT.get(item, "")
	var lab_id: int = lab.id
	b.pressed.connect(func(): start_requested.emit(lab_id, item))
	return b


func _project_block(st, data, item: String) -> void:
	var p = st.project_for_item(item)
	var need := int(data.research_item(item)["points"])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_project.add_child(row)
	var icon := Control.new()
	icon.custom_minimum_size = Vector2(40, 40)
	icon.draw.connect(func():
		icon.draw_style_box(_box(Icons.color_of(item), Color(0.1, 0.09, 0.08), 2, 6, [0, 0, 0, 0]), Rect2(Vector2.ZERO, icon.size))
		Icons.draw(icon, item, icon.size / 2.0, 13.0, Color(0.1, 0.09, 0.08)))
	row.add_child(icon)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	col.add_child(_label(Pieces.research_name(item).to_upper(), 20, TEXT, true))
	var bar := Control.new()
	bar.custom_minimum_size = Vector2(0, 14)
	var frac := clampf(float(p["progress"]) / maxf(need, 1.0), 0.0, 1.0)
	bar.draw.connect(func():
		bar.draw_rect(Rect2(Vector2.ZERO, bar.size), Color(0.06, 0.09, 0.08))
		bar.draw_rect(Rect2(Vector2.ZERO, Vector2(bar.size.x * frac, bar.size.y)), Icons.color_of(item))
		bar.draw_rect(Rect2(Vector2.ZERO, bar.size), DIM_TEXT, false, 1.0))
	col.add_child(bar)
	var left := Earnings.rounds_left(st, data, item)
	var eta := "STALLED: NO LAB IS WORKING ON IT" if left < 0 else "%d ROUND%s LEFT" % [left, "" if left == 1 else "S"]
	col.add_child(_label("%d / %d POINTS, %s" % [int(p["progress"]), need, eta], 14, DIM_TEXT))


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
