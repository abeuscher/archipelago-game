## Screen interface, laid out per spec section 14.
##   Left toolbar: phase tools, with the scoreboard timer at its foot.
##   Top middle: rotate buttons, round indicator, and log events flashing
##   as they happen.
##   Top right: resources, the next-round earnings button and the log
##   history button.
##   Right side, toward the middle: the strip of research beakers and base
##   buttons, all the same size.
##   Bottom: info box, then the minimap at the right.
## Plus the research panel, tips, the Esc menu and the end-of-game overlay.
extends CanvasLayer

const Minimap = preload("res://game/minimap.gd")
const SevenSeg = preload("res://game/seven_seg.gd")
const StripButton = preload("res://game/strip_button.gd")
const ToolButton = preload("res://game/tool_button.gd")
const FuelPlanner = preload("res://game/fuel_planner.gd")
const ResearchPanel = preload("res://game/research_panel.gd")
const EscMenu = preload("res://game/esc_menu.gd")

signal rotate_requested(dir: int)
signal tip_dismissed(id: String)
signal tips_off_requested
signal earnings_requested

var minimap
var research_panel
var esc_menu
var _tool_title: Label
var _tools: VBoxContainer
var _timer
var _resources: Label
var _round: Label
var _flash: VBoxContainer
var _info: RichTextLabel
var _info_actions: VBoxContainer
var _log_panel: PanelContainer
var _log: RichTextLabel
var _log_button: Button
var _unread: int = 0
var _earn_panel: PanelContainer
var _earn_text: Label
var _earn_button: Button
var _strip: VBoxContainer
var _strip_title: PanelContainer
var _strip_title_text: Label
var _tip: PanelContainer
var _tip_text: Label
var _tip_id: String = ""
var _hover: PanelContainer
var _hover_text: Label
var _overlay: PanelContainer
var _overlay_text: Label
var _overlay_buttons: HBoxContainer

const TOOLBAR_W := 260
const INFO_W := 420
const MINIMAP_W := 300
const BOTTOM_H := 170
const STRIP_W := 64
const FLASH_SECONDS := 4.0
const FLASH_MAX := 4


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = make_theme()
	add_child(root)

	# Left toolbar.
	var left := PanelContainer.new()
	left.anchor_bottom = 1.0
	left.offset_right = TOOLBAR_W
	root.add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 8)
	left.add_child(lv)
	_tool_title = Label.new()
	_tool_title.add_theme_font_size_override("font_size", 20)
	lv.add_child(_tool_title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lv.add_child(scroll)
	_tools = VBoxContainer.new()
	_tools.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tools.add_theme_constant_override("separation", 4)
	scroll.add_child(_tools)
	_timer = SevenSeg.new()
	_timer.tooltip_text = "Time left in this phase. Black when the clock is off or not running."
	lv.add_child(_timer)

	# Top right: resources, then the earnings and log buttons.
	var tr := VBoxContainer.new()
	tr.anchor_left = 1.0
	tr.anchor_right = 1.0
	tr.offset_left = -520
	tr.offset_right = -16
	tr.offset_top = 8
	tr.alignment = BoxContainer.ALIGNMENT_BEGIN
	root.add_child(tr)
	_resources = Label.new()
	_resources.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_resources.add_theme_font_size_override("font_size", 20)
	tr.add_child(_resources)
	var trb := HBoxContainer.new()
	trb.alignment = BoxContainer.ALIGNMENT_END
	tr.add_child(trb)
	_earn_button = Button.new()
	_earn_button.text = "Next round"
	_earn_button.toggle_mode = true
	_earn_button.focus_mode = Control.FOCUS_NONE
	_earn_button.tooltip_text = "Show what next round's income will be"
	_earn_button.toggled.connect(_toggle_earnings)
	trb.add_child(_earn_button)
	_log_button = Button.new()
	_log_button.text = "Log"
	_log_button.toggle_mode = true
	_log_button.focus_mode = Control.FOCUS_NONE
	_log_button.tooltip_text = "Read back the game log"
	_log_button.toggled.connect(_toggle_log)
	trb.add_child(_log_button)
	_earn_panel = PanelContainer.new()
	_earn_panel.visible = false
	tr.add_child(_earn_panel)
	_earn_text = Label.new()
	_earn_text.autowrap_mode = TextServer.AUTOWRAP_WORD
	_earn_text.custom_minimum_size = Vector2(480, 0)
	_earn_panel.add_child(_earn_text)

	# Top middle: rotate buttons around the round indicator, flashes below.
	var top := VBoxContainer.new()
	top.anchor_left = 0.5
	top.anchor_right = 0.5
	top.offset_left = -260
	top.offset_right = 260
	top.offset_top = 8
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	var topr := HBoxContainer.new()
	topr.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_child(topr)
	var rl := Button.new()
	rl.text = "⟲"
	rl.focus_mode = Control.FOCUS_NONE
	rl.tooltip_text = "Rotate the board 60° (Q)"
	rl.pressed.connect(func(): rotate_requested.emit(-1))
	topr.add_child(rl)
	_round = Label.new()
	_round.add_theme_font_size_override("font_size", 20)
	_round.custom_minimum_size = Vector2(320, 0)
	_round.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	topr.add_child(_round)
	var rr := Button.new()
	rr.text = "⟳"
	rr.focus_mode = Control.FOCUS_NONE
	rr.tooltip_text = "Rotate the board 60° (E)"
	rr.pressed.connect(func(): rotate_requested.emit(1))
	topr.add_child(rr)
	_flash = VBoxContainer.new()
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_flash)

	# Log history, right side, left of the strip. Hidden until asked for.
	_log_panel = PanelContainer.new()
	_log_panel.anchor_left = 1.0
	_log_panel.anchor_right = 1.0
	_log_panel.anchor_bottom = 1.0
	_log_panel.offset_left = -STRIP_W - 24 - 400
	_log_panel.offset_right = -STRIP_W - 24
	_log_panel.offset_top = 80
	_log_panel.offset_bottom = -BOTTOM_H - 16
	_log_panel.visible = false
	root.add_child(_log_panel)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log_panel.add_child(_log)

	# Right strip: beakers, then bases. Centred vertically.
	_strip = VBoxContainer.new()
	_strip.anchor_left = 1.0
	_strip.anchor_right = 1.0
	_strip.anchor_top = 0.5
	_strip.anchor_bottom = 0.5
	_strip.offset_left = -STRIP_W - 12
	_strip.offset_right = -12
	_strip.offset_top = -200
	_strip.offset_bottom = 200
	_strip.alignment = BoxContainer.ALIGNMENT_CENTER
	_strip.add_theme_constant_override("separation", 6)
	root.add_child(_strip)
	_strip_title = PanelContainer.new()
	_strip_title.visible = false
	_strip_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_strip_title)
	_strip_title_text = Label.new()
	_strip_title_text.add_theme_font_size_override("font_size", 15)
	_strip_title.add_child(_strip_title_text)

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
	iscroll.custom_minimum_size = Vector2(170, 0)
	iscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
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
	minimap.tooltip_text = "Click to move the view. This is how you look at the other island."
	root.add_child(minimap)

	# Tip callout, top left of the board area.
	_tip = PanelContainer.new()
	_tip.visible = false
	var tstyle := StyleBoxFlat.new()
	tstyle.bg_color = Color(0.12, 0.2, 0.28, 0.95)
	tstyle.border_color = Color(0.45, 0.75, 0.95)
	tstyle.set_border_width_all(2)
	tstyle.set_corner_radius_all(6)
	tstyle.set_content_margin_all(10)
	_tip.add_theme_stylebox_override("panel", tstyle)
	root.add_child(_tip)
	var tv := VBoxContainer.new()
	_tip.add_child(tv)
	var th := Label.new()
	th.text = "Tip"
	th.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
	tv.add_child(th)
	_tip_text = Label.new()
	_tip_text.autowrap_mode = TextServer.AUTOWRAP_WORD
	_tip_text.custom_minimum_size = Vector2(356, 0)
	tv.add_child(_tip_text)
	var tb := HBoxContainer.new()
	tb.alignment = BoxContainer.ALIGNMENT_END
	tv.add_child(tb)
	var off := Button.new()
	off.text = "No more tips"
	off.focus_mode = Control.FOCUS_NONE
	off.pressed.connect(func(): tips_off_requested.emit())
	tb.add_child(off)
	var ok := Button.new()
	ok.text = "Got it"
	ok.focus_mode = Control.FOCUS_NONE
	ok.pressed.connect(func(): tip_dismissed.emit(_tip_id))
	tb.add_child(ok)

	# Hover text that follows the mouse over the board.
	_hover = PanelContainer.new()
	_hover.visible = false
	_hover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hover)
	_hover_text = Label.new()
	_hover.add_child(_hover_text)

	# Research panel, centred.
	research_panel = ResearchPanel.new()
	research_panel.anchor_left = 0.5
	research_panel.anchor_right = 0.5
	research_panel.anchor_top = 0.5
	research_panel.anchor_bottom = 0.5
	research_panel.offset_left = -330
	research_panel.offset_right = 330
	research_panel.offset_top = -220
	research_panel.offset_bottom = 120
	research_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	research_panel.visible = false
	root.add_child(research_panel)

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

	# Esc menu on top of everything; it keeps running while paused.
	esc_menu = EscMenu.new()
	root.add_child(esc_menu)


## Solid panels with a little padding, so text never sits on the board.
static func make_theme() -> Theme:
	var th := Theme.new()
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.09, 0.11, 0.14, 0.96)
	panel.border_color = Color(0.25, 0.29, 0.34)
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(4)
	panel.set_content_margin_all(10)
	th.set_stylebox("panel", "PanelContainer", panel)
	return th


# --- Top bar ---------------------------------------------------------------

func set_phase(phase_name: String, round_number: int) -> void:
	_round.text = phase_name if round_number <= 0 else "Round %d · %s" % [round_number, phase_name]
	_tool_title.text = phase_name


## seconds < 0 means the clock is off or not running: a plain black box.
func set_timer(seconds: float) -> void:
	_timer.set_time(seconds)


func set_resources(money: int, fuel: int, research: int) -> void:
	_resources.text = "Money %d    Fuel %d    Research +%d" % [money, fuel, research]


func set_earnings(lines: Array, next_round: int) -> void:
	_earn_text.text = "Projected for round %d\n%s" % [next_round, "\n".join(lines)]


func _toggle_earnings(on: bool) -> void:
	_earn_panel.visible = on
	if on:
		earnings_requested.emit()


func earnings_visible() -> bool:
	return _earn_panel.visible


# --- Log -------------------------------------------------------------------

## Adds an event to the history and flashes it at the top of the screen.
func add_log(text: String) -> void:
	_log.append_text(text + "\n")
	if not _log_panel.visible:
		_unread += 1
		_log_button.text = "Log (%d)" % _unread
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.scroll_active = false
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("normal_font_size", 17)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.text = "[center]%s[/center]" % text
	_flash.add_child(l)
	while _flash.get_child_count() > FLASH_MAX:
		var old := _flash.get_child(0)
		_flash.remove_child(old)
		old.queue_free()
	l.modulate = Color(1.6, 1.6, 1.2)
	# The tween belongs to the label, so it stops if the label goes first.
	var t := l.create_tween()
	t.tween_property(l, "modulate", Color.WHITE, 0.35)
	t.tween_interval(FLASH_SECONDS)
	t.tween_property(l, "modulate:a", 0.0, 0.6)
	t.tween_callback(l.queue_free)


func _toggle_log(on: bool) -> void:
	_log_panel.visible = on
	if on:
		_unread = 0
		_log_button.text = "Log"


# --- Left toolbar ----------------------------------------------------------

func clear_tools() -> void:
	for c in _tools.get_children():
		_tools.remove_child(c)
		c.queue_free()


func add_label(text: String, small: bool = false) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.add_theme_font_size_override("font_size", 13 if small else 16)
	if small:
		l.add_theme_color_override("font_color", Color(0.72, 0.75, 0.78))
	_tools.add_child(l)


func add_spacer(h: float = 8.0) -> void:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	_tools.add_child(c)


func add_tool_button(text: String, action: Callable, disabled: bool = false, pressed: bool = false, tooltip: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = disabled
	b.toggle_mode = pressed
	b.button_pressed = pressed
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 34)
	b.tooltip_text = tooltip
	b.pressed.connect(action)
	_tools.add_child(b)
	return b


## A button with a piece icon: piece_type may be "" for none.
func add_piece_button(piece_type: String, title: String, detail: String, note: String, action: Callable,
		disabled: bool, pressed: bool, tooltip: String) -> void:
	var b := ToolButton.new()
	b.piece_type = piece_type
	b.title = title
	b.detail = detail
	b.note = note
	b.disabled = disabled
	b.toggle_mode = pressed
	b.button_pressed = pressed
	b.tooltip_text = tooltip
	b.pressed.connect(action)
	_tools.add_child(b)


func add_fuel_planner(fuel: int, planned: int) -> void:
	var f := FuelPlanner.new()
	f.set_values(fuel, planned)
	f.tooltip_text = "Fuel used by the orders placed so far, out of the fuel you have."
	_tools.add_child(f)


# --- Right strip -----------------------------------------------------------

## items: Array of {"kind": "beaker"|"base", "fraction", "hits_left",
## "hits_max", "details", "action": Callable, "enabled": bool}.
func set_strip(items: Array) -> void:
	for c in _strip.get_children():
		_strip.remove_child(c)
		c.queue_free()
	_strip_title.visible = false
	var last_kind := ""
	for it in items:
		if last_kind != "" and it["kind"] != last_kind:
			var sep := Control.new()
			sep.custom_minimum_size = Vector2(0, 10)
			_strip.add_child(sep)
		last_kind = it["kind"]
		var b := StripButton.new()
		b.kind = it["kind"]
		b.fraction = float(it.get("fraction", 0.0))
		b.hits_left = float(it.get("hits_left", 0.0))
		b.hits_max = float(it.get("hits_max", 3.0))
		b.details = String(it.get("details", ""))
		var action: Callable = it.get("action", Callable())
		if action.is_valid():
			b.pressed.connect(action)
		b.disabled = not bool(it.get("enabled", true))
		b.mouse_entered.connect(_show_strip_title.bind(b))
		b.mouse_exited.connect(func(): _strip_title.visible = false)
		_strip.add_child(b)


func _show_strip_title(b) -> void:
	_strip_title_text.text = b.details
	_strip_title.reset_size()
	var r: Rect2 = b.get_global_rect()
	var sz: Vector2 = _strip_title.get_combined_minimum_size()
	_strip_title.position = Vector2(r.position.x - sz.x - 8, r.position.y + (r.size.y - sz.y) / 2.0)
	_strip_title.visible = true


# --- Info box, hover, tips -------------------------------------------------

func set_info(bbcode: String) -> void:
	_info.text = bbcode


func clear_info_actions() -> void:
	for c in _info_actions.get_children():
		_info_actions.remove_child(c)
		c.queue_free()


func add_info_action(text: String, action: Callable, disabled: bool = false, tooltip: String = "") -> void:
	var b := Button.new()
	b.text = text
	b.disabled = disabled
	b.tooltip_text = tooltip
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	_info_actions.add_child(b)


func add_info_text(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	_info_actions.add_child(l)


## Text beside the mouse; "" hides it.
func set_hover_text(text: String, screen_pos: Vector2) -> void:
	_hover.visible = text != ""
	if text == "":
		return
	_hover_text.text = text
	_hover.reset_size()
	_hover.position = screen_pos + Vector2(18, 14)


func show_tip(tip) -> void:
	if tip == null:
		_tip.visible = false
		_tip_id = ""
		return
	_tip_id = String(tip["id"])
	_tip_text.text = String(tip["text"])
	_tip.visible = true
	_place_tip.call_deferred()


## Bottom left of the board area, just right of the toolbar.
func _place_tip() -> void:
	_tip.reset_size()
	var sz := _tip.get_combined_minimum_size()
	var view := _tip.get_viewport_rect().size
	_tip.position = Vector2(TOOLBAR_W + 16, view.y - sz.y - 16)


func tip_showing() -> String:
	return _tip_id if _tip.visible else ""


# --- Overlay ---------------------------------------------------------------

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
