## The Esc menu (section 14): pauses the game and offers options and quit.
## Options holds the game settings. Clock changes apply from the next phase;
## decoys per side applies from the next game, since both sides have already
## been set up under the current value.
extends Control

const UserSettings = preload("res://game/user_settings.gd")
const DevicePanel = preload("res://game/device_panel.gd")

signal settings_changed(s: Dictionary)
signal quit_requested

var defaults: Dictionary
var settings: Dictionary
var _main_box: VBoxContainer
var _opts_box: VBoxContainer
var _build_clock: SpinBox
var _target_clock: SpinBox
var _build_off: CheckBox
var _target_off: CheckBox
var _decoys: SpinBox
var _tips: CheckBox
var _grid: CheckBox
var _reset_note: Label
var _rules_box: VBoxContainer
var _rules_label: RichTextLabel
var rules_text: String = ""      ## the Game Rules page, set by the game (rules_text.gd)
var options_only: bool = false   ## title screen: no pause menu; leaving Options closes it
var _plate_label: Label          ## the plate on top: PAUSED, OPTIONS or GAME RULES


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	# Fully black: the board stays hidden while paused, so the pause can't be
	# used to study the field with the clock stopped.
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 1.0)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	# A beige monitor like the rest of the hardware: a screwed-on plate on
	# top, lights down each side, the menu on its screen.
	var unit_col := VBoxContainer.new()
	unit_col.add_theme_constant_override("separation", -10)
	center.add_child(unit_col)
	var plate: Array = DevicePanel.title_plate()
	_plate_label = plate[2]
	plate[0].z_index = 1
	unit_col.add_child(plate[0])
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", DevicePanel.box(DevicePanel.BEZEL, DevicePanel.BEZEL_EDGE, 4, 22, [14, 22, 14, 12]))
	unit_col.add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	panel.add_child(body)
	var row_unit := HBoxContainer.new()
	row_unit.add_theme_constant_override("separation", 12)
	body.add_child(row_unit)
	row_unit.add_child(_light_column([DevicePanel.LEDS[0], DevicePanel.LEDS[1], DevicePanel.LEDS[2]]))
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 0)
	var screen := DevicePanel._screen(stack, 22)
	screen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_unit.add_child(screen)
	row_unit.add_child(_light_column([DevicePanel.LEDS[2], DevicePanel.LEDS[1], DevicePanel.LEDS[0]]))
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_END
	foot.add_child(DevicePanel._leds([DevicePanel.LEDS[0], DevicePanel.LEDS[1], DevicePanel.LEDS[2]]))
	body.add_child(foot)

	_main_box = VBoxContainer.new()
	_main_box.add_theme_constant_override("separation", 14)
	_main_box.custom_minimum_size = Vector2(300, 0)
	stack.add_child(_main_box)
	_main_box.add_child(_menu_key("RESUME", "play", Color(0.42, 0.80, 0.38), close_menu))
	_main_box.add_child(_menu_key("OPTIONS", "gear", Color(0.98, 0.82, 0.22), _show_options))
	_main_box.add_child(_menu_key("QUIT", "exit", Color(0.90, 0.36, 0.22), func(): quit_requested.emit()))

	_opts_box = VBoxContainer.new()
	_opts_box.add_theme_constant_override("separation", 8)
	_opts_box.visible = false
	stack.add_child(_opts_box)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	_opts_box.add_child(grid)
	_build_clock = _spin()
	_build_off = _check("Off")
	_row(grid, "Build and repair clock (seconds)", _build_clock, _build_off)
	_target_clock = _spin()
	_target_off = _check("Off")
	_row(grid, "Targeting clock (seconds)", _target_clock, _target_off)
	_decoys = SpinBox.new()
	_decoys.step = 1
	_row(grid, "Decoys per side", _decoys, Control.new())
	var tips_row := HBoxContainer.new()
	_opts_box.add_child(tips_row)
	_tips = _check("Show tips")
	_tips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tips_row.add_child(_tips)
	var reset := _button("Reset tips", _reset_tips)
	reset.tooltip_text = "Show every tip again from the beginning"
	reset.custom_minimum_size = Vector2(130, 38)
	tips_row.add_child(reset)
	_grid = _check("Show grid")
	_grid.tooltip_text = "Outline every hex. Off, only coasts and changes of height are outlined."
	_opts_box.add_child(_grid)
	_reset_note = Label.new()
	_reset_note.add_theme_font_size_override("font_size", 13)
	_reset_note.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
	_opts_box.add_child(_reset_note)
	var note := Label.new()
	note.text = "Clock changes apply from the next phase. Decoys per side applies from the next game."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD
	note.custom_minimum_size = Vector2(380, 0)
	note.add_theme_font_size_override("font_size", 13)
	_opts_box.add_child(note)
	var row := HBoxContainer.new()
	_opts_box.add_child(row)
	var rules_link := LinkButton.new()
	rules_link.text = "Game Rules"
	rules_link.underline = LinkButton.UNDERLINE_MODE_ALWAYS
	rules_link.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
	rules_link.add_theme_color_override("font_hover_color", Color(0.75, 0.93, 1.0))
	rules_link.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rules_link.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rules_link.tooltip_text = "How the game works, in detail"
	rules_link.pressed.connect(_show_rules)
	row.add_child(rules_link)
	row.add_child(_button("Cancel", _show_main))
	row.add_child(_button("Apply", _apply))

	# Game Rules: the full description, scrolling, with a way back.
	_rules_box = VBoxContainer.new()
	_rules_box.add_theme_constant_override("separation", 8)
	_rules_box.visible = false
	stack.add_child(_rules_box)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(680, 520)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_rules_box.add_child(scroll)
	_rules_label = RichTextLabel.new()
	_rules_label.bbcode_enabled = true
	_rules_label.fit_content = true
	_rules_label.scroll_active = false
	_rules_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rules_label.add_theme_font_size_override("normal_font_size", 15)
	_rules_label.add_theme_font_size_override("bold_font_size", 15)
	scroll.add_child(_rules_label)
	var rrow := HBoxContainer.new()
	rrow.alignment = BoxContainer.ALIGNMENT_END
	_rules_box.add_child(rrow)
	rrow.add_child(_button("Back", _show_options))


func setup(defaults_in: Dictionary, settings_in: Dictionary) -> void:
	defaults = defaults_in
	settings = settings_in.duplicate(true)
	for sb in [_build_clock, _target_clock]:
		sb.min_value = int(defaults["clock_seconds_step"])
		sb.max_value = int(defaults["clock_seconds_max"])
		sb.step = int(defaults["clock_seconds_step"])
	_decoys.min_value = int(defaults["decoys_per_side_min"])
	_decoys.max_value = int(defaults["decoys_per_side_max"])


func open_menu() -> void:
	visible = true
	# Fill the screen explicitly: a control first shown while the tree is
	# pausing may not have had its anchored size applied yet.
	position = Vector2.ZERO
	size = get_viewport_rect().size
	if options_only:
		_show_options()
	else:
		_show_main()
	get_tree().paused = true


func close_menu() -> void:
	visible = false
	get_tree().paused = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if not visible:
			open_menu()
		elif _rules_box.visible:
			_show_options()
		elif _opts_box.visible:
			_show_main()
		else:
			close_menu()
		get_viewport().set_input_as_handled()


func _show_main() -> void:
	if options_only:
		close_menu()
		return
	_plate_label.text = "PAUSED"
	_main_box.visible = true
	_opts_box.visible = false
	_rules_box.visible = false


func _show_rules() -> void:
	_rules_label.text = rules_text
	_plate_label.text = "GAME RULES"
	_main_box.visible = false
	_opts_box.visible = false
	_rules_box.visible = true


func _show_options() -> void:
	var off := int(defaults["clock_off_value"])
	_build_off.button_pressed = int(settings["build_clock_seconds"]) <= off
	_build_clock.value = int(defaults["build_clock_seconds"]) if _build_off.button_pressed else int(settings["build_clock_seconds"])
	_target_off.button_pressed = int(settings["targeting_clock_seconds"]) <= off
	_target_clock.value = int(defaults["targeting_clock_seconds"]) if _target_off.button_pressed else int(settings["targeting_clock_seconds"])
	_decoys.value = int(settings["decoys_per_side"])
	_tips.button_pressed = bool(settings["show_tips"])
	_grid.button_pressed = bool(settings["show_grid"])
	_reset_note.text = ""
	_plate_label.text = "OPTIONS"
	_rules_box.visible = false
	_main_box.visible = false
	_opts_box.visible = true


func _apply() -> void:
	var off := int(defaults["clock_off_value"])
	var s := settings.duplicate(true)
	s["build_clock_seconds"] = off if _build_off.button_pressed else int(_build_clock.value)
	s["targeting_clock_seconds"] = off if _target_off.button_pressed else int(_target_clock.value)
	s["decoys_per_side"] = int(_decoys.value)
	s["show_tips"] = _tips.button_pressed
	s["show_grid"] = _grid.button_pressed
	settings = UserSettings.sanitize(s, defaults)
	settings_changed.emit(settings.duplicate(true))
	_show_main()


## Takes effect at once: every tip becomes new again.
func _reset_tips() -> void:
	settings["tips_done"] = []
	settings_changed.emit(settings.duplicate(true))
	_reset_note.text = "Tips reset. They will show again from the beginning."


## A smaller key for the Options and Rules screens (Apply, Cancel, Back).
func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text.to_upper()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(96, 38)
	DevicePanel.style_key(b, DevicePanel.BEZEL)
	_key_text(b, 15)
	b.pressed.connect(action)
	return b


## A big coloured key on the pause screen, with its icon at the left.
func _menu_key(text: String, icon: String, color: Color, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(300, 56)
	DevicePanel.style_key(b, color)
	_key_text(b, 24)
	var glyph := Control.new()
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glyph.position = Vector2(12, 8)
	glyph.size = Vector2(36, 36)
	glyph.draw.connect(func(): _draw_icon(glyph, icon, glyph.size / 2.0, color))
	b.add_child(glyph)
	b.pressed.connect(action)
	return b


func _key_text(b: Button, size_px: int) -> void:
	var f := FontVariation.new()
	f.base_font = ThemeDB.fallback_font
	f.variation_embolden = 1.0
	f.spacing_glyph = 1
	b.add_theme_font_override("font", f)
	b.add_theme_font_size_override("font_size", size_px)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, DevicePanel.PLATE_INK)


## Icons on the menu keys: a play triangle, a gear, a door with an arrow.
static func _draw_icon(ci: CanvasItem, kind: String, c: Vector2, key_color: Color) -> void:
	var ink := DevicePanel.PLATE_INK
	match kind:
		"play":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-8, -11), c + Vector2(11, 0), c + Vector2(-8, 11)]), ink)
		"gear":
			for k in 8:
				var a := TAU * k / 8.0
				var d := Vector2(cos(a), sin(a))
				var side := Vector2(-d.y, d.x)
				ci.draw_colored_polygon(PackedVector2Array([c + d * 8 - side * 3, c + d * 13 - side * 2.5,
					c + d * 13 + side * 2.5, c + d * 8 + side * 3]), ink)
			ci.draw_circle(c, 9.5, ink)
			ci.draw_circle(c, 4.0, key_color)
		"exit":
			ci.draw_rect(Rect2(c + Vector2(-12, -12), Vector2(14, 24)), ink, false, 3.0)
			ci.draw_line(c + Vector2(-4, 0), c + Vector2(11, 0), ink, 3.5)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(13, 0), c + Vector2(6, -7), c + Vector2(6, 7)]), ink)


## A column of indicator lights beside the screen.
static func _light_column(colors: Array) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(22, 0)
	c.draw.connect(func():
		var step := 26.0
		var y0 := c.size.y / 2.0 - step * (colors.size() - 1) / 2.0
		for i in colors.size():
			var p := Vector2(c.size.x / 2.0, y0 + step * i)
			c.draw_circle(p, 8.0, Color(0.15, 0.15, 0.14))
			c.draw_circle(p, 6.0, colors[i])
			c.draw_circle(p + Vector2(-2, -2), 1.8, Color(1, 1, 1, 0.6)))
	c.resized.connect(c.queue_redraw)
	return c


func _spin() -> SpinBox:
	var sb := SpinBox.new()
	sb.custom_minimum_size = Vector2(110, 0)
	return sb


func _check(text: String) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	return c


func _row(grid: GridContainer, label: String, a: Control, b: Control) -> void:
	var l := Label.new()
	l.text = label
	grid.add_child(l)
	grid.add_child(a)
	grid.add_child(b)
