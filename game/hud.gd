## Screen interface, laid out per spec section 14: left toolbar with the
## timer at its foot, resources top right, info box bottom middle, minimap
## bottom right, plus round indicator, rotate buttons and game log.
extends CanvasLayer

const Minimap = preload("res://game/minimap.gd")

signal rotate_requested(dir: int)

var minimap
var _tools: VBoxContainer
var _timer: Label
var _timer_box: PanelContainer
var _resources: Label
var _round: Label
var _info: RichTextLabel
var _info_actions: VBoxContainer
var _log: RichTextLabel
var _overlay: PanelContainer
var _overlay_text: Label
var _overlay_buttons: HBoxContainer

const TOOLBAR_W := 250
const INFO_W := 380
const MINIMAP_W := 300
const BOTTOM_H := 170


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Left toolbar.
	var left := PanelContainer.new()
	left.anchor_bottom = 1.0
	left.offset_right = TOOLBAR_W
	root.add_child(left)
	var lv := VBoxContainer.new()
	left.add_child(lv)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lv.add_child(scroll)
	_tools = VBoxContainer.new()
	_tools.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_tools)
	_timer_box = PanelContainer.new()
	var tstyle := StyleBoxFlat.new()
	tstyle.bg_color = Color(0, 0, 0)
	tstyle.set_content_margin_all(8)
	_timer_box.add_theme_stylebox_override("panel", tstyle)
	lv.add_child(_timer_box)
	_timer = Label.new()
	_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer.add_theme_font_size_override("font_size", 34)
	_timer.add_theme_color_override("font_color", Color(1.0, 0.25, 0.15))
	_timer.custom_minimum_size = Vector2(0, 48)
	_timer_box.add_child(_timer)

	# Resources, top right.
	_resources = Label.new()
	_resources.anchor_left = 1.0
	_resources.anchor_right = 1.0
	_resources.offset_left = -420
	_resources.offset_right = -16
	_resources.offset_top = 10
	_resources.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_resources.add_theme_font_size_override("font_size", 20)
	root.add_child(_resources)

	# Round indicator and rotate buttons, top middle.
	var top := HBoxContainer.new()
	top.anchor_left = 0.5
	top.anchor_right = 0.5
	top.offset_left = -220
	top.offset_right = 220
	top.offset_top = 8
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(top)
	var rl := Button.new()
	rl.text = "⟲"
	rl.tooltip_text = "Rotate the board (Q)"
	rl.pressed.connect(func(): rotate_requested.emit(-1))
	top.add_child(rl)
	_round = Label.new()
	_round.add_theme_font_size_override("font_size", 18)
	_round.custom_minimum_size = Vector2(300, 0)
	_round.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(_round)
	var rr := Button.new()
	rr.text = "⟳"
	rr.tooltip_text = "Rotate the board (E)"
	rr.pressed.connect(func(): rotate_requested.emit(1))
	top.add_child(rr)

	# Game log, right side.
	var log_panel := PanelContainer.new()
	log_panel.anchor_left = 1.0
	log_panel.anchor_right = 1.0
	log_panel.anchor_bottom = 1.0
	log_panel.offset_left = -330
	log_panel.offset_right = -8
	log_panel.offset_top = 48
	log_panel.offset_bottom = -BOTTOM_H - 16
	root.add_child(log_panel)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	log_panel.add_child(_log)

	# Info box, bottom middle (left of the minimap).
	var info_panel := PanelContainer.new()
	info_panel.anchor_left = 1.0
	info_panel.anchor_right = 1.0
	info_panel.anchor_top = 1.0
	info_panel.anchor_bottom = 1.0
	info_panel.offset_left = -MINIMAP_W - INFO_W - 24
	info_panel.offset_right = -MINIMAP_W - 16
	info_panel.offset_top = -BOTTOM_H - 8
	info_panel.offset_bottom = -8
	root.add_child(info_panel)
	var ih := HBoxContainer.new()
	info_panel.add_child(ih)
	_info = RichTextLabel.new()
	_info.bbcode_enabled = true
	_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ih.add_child(_info)
	var iscroll := ScrollContainer.new()
	iscroll.custom_minimum_size = Vector2(190, 0)
	ih.add_child(iscroll)
	_info_actions = VBoxContainer.new()
	_info_actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	iscroll.add_child(_info_actions)

	# Minimap, bottom right.
	minimap = Minimap.new()
	minimap.anchor_left = 1.0
	minimap.anchor_right = 1.0
	minimap.anchor_top = 1.0
	minimap.anchor_bottom = 1.0
	minimap.offset_left = -MINIMAP_W - 8
	minimap.offset_right = -8
	minimap.offset_top = -BOTTOM_H - 8
	minimap.offset_bottom = -8
	root.add_child(minimap)

	# Centre overlay for the coin flip and the end of the game.
	_overlay = PanelContainer.new()
	_overlay.anchor_left = 0.5
	_overlay.anchor_right = 0.5
	_overlay.anchor_top = 0.5
	_overlay.anchor_bottom = 0.5
	_overlay.offset_left = -260
	_overlay.offset_right = 260
	_overlay.offset_top = -110
	_overlay.offset_bottom = 110
	_overlay.visible = false
	root.add_child(_overlay)
	var ov := VBoxContainer.new()
	ov.alignment = BoxContainer.ALIGNMENT_CENTER
	_overlay.add_child(ov)
	_overlay_text = Label.new()
	_overlay_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_text.autowrap_mode = TextServer.AUTOWRAP_WORD
	_overlay_text.add_theme_font_size_override("font_size", 20)
	ov.add_child(_overlay_text)
	_overlay_buttons = HBoxContainer.new()
	_overlay_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	ov.add_child(_overlay_buttons)


func set_phase(phase_name: String, round_number: int) -> void:
	_round.text = phase_name if round_number <= 0 else "Round %d · %s" % [round_number, phase_name]


## seconds < 0 means the clock is off: a plain black box.
func set_timer(seconds: float) -> void:
	if seconds < 0.0:
		_timer.text = ""
		return
	var s := ceili(seconds)
	_timer.text = "%d:%02d" % [s / 60, s % 60]


func set_resources(money: int, fuel: int, research: int) -> void:
	_resources.text = "Money %d    Fuel %d    Research +%d" % [money, fuel, research]


func add_log(text: String) -> void:
	_log.append_text(text + "\n")


func clear_tools() -> void:
	for c in _tools.get_children():
		c.queue_free()


func add_label(text: String, small: bool = false) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	if not small:
		l.add_theme_font_size_override("font_size", 18)
	_tools.add_child(l)


func add_tool_button(text: String, action: Callable, disabled: bool = false, pressed: bool = false) -> void:
	var b := Button.new()
	b.text = text
	b.disabled = disabled
	b.toggle_mode = pressed
	b.button_pressed = pressed
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(action)
	_tools.add_child(b)


func set_info(bbcode: String) -> void:
	_info.text = bbcode


func clear_info_actions() -> void:
	for c in _info_actions.get_children():
		c.queue_free()


func add_info_action(text: String, action: Callable, disabled: bool = false) -> void:
	var b := Button.new()
	b.text = text
	b.disabled = disabled
	b.pressed.connect(action)
	_info_actions.add_child(b)


func add_info_text(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	_info_actions.add_child(l)


func show_overlay(text: String, buttons: Array) -> void:
	_overlay_text.text = text
	for c in _overlay_buttons.get_children():
		c.queue_free()
	for spec in buttons:
		var b := Button.new()
		b.text = spec[0]
		var action: Callable = spec[1]
		b.pressed.connect(func():
			_overlay.visible = false
			action.call())
		_overlay_buttons.add_child(b)
	_overlay.visible = true


func overlay_visible() -> bool:
	return _overlay.visible
