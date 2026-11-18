## Screen interface, laid out per spec section 14.
##   Left toolbar: phase tools, with the scoreboard timer at its foot.
##   Top middle: round indicator, and log events flashing as they happen.
##   Top right: resources (money with next round's income in brackets),
##   the next-round earnings button and the log history button.
##   Right side, toward the middle: the strip of research beakers and base
##   buttons, all the same size.
##   Bottom: info box, then the minimap at the right, both raised
##   MAP_BAR_H off the bottom; the rotate and zoom buttons sit beneath the
##   minimap.
## Plus the research panel, tips, the Esc menu, the end-of-game overlay and
## the debug panel (the ` key).
extends CanvasLayer

const Minimap = preload("res://game/minimap.gd")
const SevenSeg = preload("res://game/seven_seg.gd")
const StripButton = preload("res://game/strip_button.gd")
const ToolButton = preload("res://game/tool_button.gd")
const FuelPlanner = preload("res://game/fuel_planner.gd")
const IconButton = preload("res://game/icon_button.gd")
const Beacon = preload("res://game/beacon.gd")
const Announcer = preload("res://game/announcer.gd")
const ResearchPanel = preload("res://game/research_panel.gd")
const EscMenu = preload("res://game/esc_menu.gd")

signal rotate_requested(dir: int)
signal zoom_requested(dir: int)
signal tip_dismissed(id: String, forever: bool)
signal earnings_requested
signal debug_add_money
signal debug_toggle_fog(on: bool)

var minimap
var research_panel
var esc_menu
var _tool_title: Label
var _tools: VBoxContainer
var _timer
var _timer_label: RichTextLabel
var _beacon
var announcer
var _portrait_slot: Control
var _money_val: Label
var _money_next: Label
var _fuel_val: Label
var _research_val: Label
var _round: Label
var _flash: VBoxContainer
var _notice: PanelContainer
var _notice_text: Label
var _notice_tween: Tween
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
var _hover: PanelContainer
var _hover_text: Label
var _overlay: PanelContainer
var _overlay_text: Label
var _overlay_buttons: HBoxContainer
var _debug: PanelContainer
var _debug_money: Button
var _debug_fog: CheckBox

const TOOLBAR_W := 260
const INFO_W := 420
const MINIMAP_W := 230
const MINIMAP_H := 250        ## taller than wide: the islands are stacked north and south
const BOTTOM_H := 170
const PORTRAIT_SLOT_H := 160  ## the character's space above the alarm light
const MAP_BAR_H := 44         ## gap under the minimap and info box, holding the map controls
const STRIP_W := 64
const FLASH_SECONDS := 4.0
const FLASH_MAX := 4
const NOTICE_SECONDS := 3.5
## Player notices: why an action can't be done. Shown under the round title.
const NOTICE_MONEY := "Out of money. Build more banks."
const NOTICE_FUEL := "Out of fuel. Build more refineries."
const NOTICE_SILO := "Missile silo damaged. Repair during build phase."
const NOTICE_NO_WEAPONS := "Player has no weapons to attack with."


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
	_tool_title.add_theme_font_override("font", bold_font())
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
	# The space where characters appear to talk to the player (announcer.gd),
	# then the alarm light, the "Round Timer" label (shown while the clock
	# runs) and the timer itself.
	_portrait_slot = Control.new()
	_portrait_slot.custom_minimum_size = Vector2(0, PORTRAIT_SLOT_H)
	_portrait_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lv.add_child(_portrait_slot)
	_beacon = Beacon.new()
	lv.add_child(_beacon)
	_timer_label = RichTextLabel.new()
	_timer_label.bbcode_enabled = true
	_timer_label.fit_content = true
	_timer_label.scroll_active = false
	_timer_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_timer_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_timer_label.add_theme_font_override("normal_font", tracked_font(1))
	_timer_label.add_theme_color_override("default_color", Color(1.0, 0.72, 0.35))
	_timer_label.text = "[center]%s[/center]" % small_caps("Round Timer", 15, 11)
	_timer_label.visible = false
	lv.add_child(_timer_label)
	_timer = SevenSeg.new()
	_timer.tooltip_text = "Time left in this phase. Black when the clock is off or not running."
	lv.add_child(_timer)

	# Top right: resources, then the earnings and log buttons.
	var tr := VBoxContainer.new()
	tr.anchor_left = 1.0
	tr.anchor_right = 1.0
	tr.offset_left = -520
	tr.offset_right = -12
	tr.offset_top = 8
	tr.alignment = BoxContainer.ALIGNMENT_BEGIN
	tr.add_theme_constant_override("separation", 6)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tr)
	tr.add_child(_build_resources())
	var trb := HBoxContainer.new()
	trb.alignment = BoxContainer.ALIGNMENT_END
	trb.add_theme_constant_override("separation", 6)
	trb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.add_child(trb)
	_earn_button = Button.new()
	_earn_button.text = "Next round"
	_earn_button.toggle_mode = true
	_earn_button.focus_mode = Control.FOCUS_NONE
	_earn_button.tooltip_text = "Show what next round's income will be"
	_earn_button.toggled.connect(_toggle_earnings)
	_small_button(_earn_button)
	trb.add_child(_earn_button)
	_log_button = Button.new()
	_log_button.text = "Log"
	_log_button.toggle_mode = true
	_log_button.focus_mode = Control.FOCUS_NONE
	_log_button.tooltip_text = "Read back the game log"
	_log_button.toggled.connect(_toggle_log)
	_small_button(_log_button)
	trb.add_child(_log_button)
	_earn_panel = PanelContainer.new()
	_earn_panel.visible = false
	_earn_panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	tr.add_child(_earn_panel)
	_earn_text = Label.new()
	_earn_text.autowrap_mode = TextServer.AUTOWRAP_WORD
	_earn_text.custom_minimum_size = Vector2(480, 0)
	_earn_panel.add_child(_earn_text)

	# Top middle: the round indicator, flashes below.
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
	_round = Label.new()
	_round.add_theme_font_size_override("font_size", 20)
	_round.custom_minimum_size = Vector2(320, 0)
	_round.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	topr.add_child(_round)
	_notice = PanelContainer.new()
	_notice.visible = false
	_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notice.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var nst := StyleBoxFlat.new()
	nst.bg_color = Color(0.42, 0.06, 0.07, 0.96)
	nst.border_color = Color(0.75, 0.2, 0.2)
	nst.set_border_width_all(1)
	nst.set_corner_radius_all(4)
	nst.content_margin_left = 16
	nst.content_margin_right = 16
	nst.content_margin_top = 7
	nst.content_margin_bottom = 7
	_notice.add_theme_stylebox_override("panel", nst)
	top.add_child(_notice)
	_notice_text = Label.new()
	_notice_text.add_theme_font_override("font", bold_font())
	_notice_text.add_theme_font_size_override("font_size", 16)
	_notice_text.add_theme_color_override("font_color", Color(1, 1, 1))
	_notice_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice.add_child(_notice_text)
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
	_log_panel.offset_bottom = -MINIMAP_H - MAP_BAR_H - 8
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
	_strip.offset_top = -250
	_strip.offset_bottom = 150
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
	info_panel.offset_top = -BOTTOM_H - MAP_BAR_H
	info_panel.offset_bottom = -MAP_BAR_H
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
	minimap.offset_top = -MINIMAP_H - MAP_BAR_H
	minimap.offset_bottom = -MAP_BAR_H
	minimap.tooltip_text = "Click or drag to move the view. This is how you look at the other island."
	root.add_child(minimap)

	# Map controls beneath the minimap: rotate, then zoom.
	var bar := HBoxContainer.new()
	bar.anchor_left = 1.0
	bar.anchor_right = 1.0
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_left = -MINIMAP_W - 8
	bar.offset_right = -8
	bar.offset_top = -MAP_BAR_H + 4
	bar.offset_bottom = -4
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 6)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar)
	_map_button(bar, "rotate_left", "Rotate left (Q)", func(): rotate_requested.emit(-1))
	_map_button(bar, "rotate_right", "Rotate right (E)", func(): rotate_requested.emit(1))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(14, 0)
	bar.add_child(gap)
	_map_button(bar, "zoom_out", "Zoom out", func(): zoom_requested.emit(-1))
	_map_button(bar, "zoom_in", "Zoom in", func(): zoom_requested.emit(1))

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

	# The character and speech bubble, above the board and panels.
	announcer = Announcer.new()
	announcer.slot = _portrait_slot
	announcer.anchor_rect = _anchor_rect
	announcer.tip_dismissed.connect(func(id: String, forever: bool): tip_dismissed.emit(id, forever))
	announcer.announcement_dismissed.connect(func(id: String, forever: bool): tip_dismissed.emit(id, forever))
	root.add_child(announcer)

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

	# Debug panel, top left of the board area. Toggled with the ` key.
	_debug = PanelContainer.new()
	_debug.visible = false
	_debug.position = Vector2(TOOLBAR_W + 16, 16)
	root.add_child(_debug)
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 6)
	_debug.add_child(dv)
	var dt := Label.new()
	dt.text = "Debug  ( ` to close )"
	dt.add_theme_color_override("font_color", Color(1.0, 0.7, 0.4))
	dv.add_child(dt)
	_debug_money = Button.new()
	_debug_money.focus_mode = Control.FOCUS_NONE
	_debug_money.pressed.connect(func(): debug_add_money.emit())
	dv.add_child(_debug_money)
	_debug_fog = CheckBox.new()
	_debug_fog.text = "Clear fog of war"
	_debug_fog.focus_mode = Control.FOCUS_NONE
	_debug_fog.toggled.connect(func(on: bool): debug_toggle_fog.emit(on))
	dv.add_child(_debug_fog)

	# Esc menu on top of everything; it keeps running while paused.
	esc_menu = EscMenu.new()
	root.add_child(esc_menu)


## Solid panels with a little padding, so text never sits on the board.
static func make_theme() -> Theme:
	var th := Theme.new()
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.13, 0.15, 0.18, 0.97)
	panel.border_color = Color(0.30, 0.32, 0.36)
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(4)
	panel.set_content_margin_all(10)
	th.set_stylebox("panel", "PanelContainer", panel)
	# Buttons look like buttons: filled, bordered, padded, text centred.
	th.set_stylebox("normal", "Button", _button_box(Color(0.23, 0.25, 0.29), Color(0.40, 0.42, 0.47)))
	th.set_stylebox("hover", "Button", _button_box(Color(0.29, 0.31, 0.36), Color(0.58, 0.61, 0.67)))
	th.set_stylebox("pressed", "Button", _button_box(Color(0.20, 0.36, 0.52), Color(0.50, 0.78, 1.0)))
	th.set_stylebox("hover_pressed", "Button", _button_box(Color(0.24, 0.42, 0.60), Color(0.60, 0.85, 1.0)))
	th.set_stylebox("disabled", "Button", _button_box(Color(0.16, 0.17, 0.20), Color(0.25, 0.27, 0.30)))
	th.set_font("font", "Button", bold_font())
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_color("font_color", "Button", Color(0.93, 0.95, 0.97))
	th.set_color("font_hover_color", "Button", Color(1, 1, 1))
	th.set_color("font_pressed_color", "Button", Color(1, 1, 1))
	th.set_color("font_hover_pressed_color", "Button", Color(1, 1, 1))
	th.set_color("font_disabled_color", "Button", Color(0.48, 0.5, 0.54))
	# Check boxes would otherwise inherit the button look.
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		var e := StyleBoxEmpty.new()
		e.set_content_margin_all(4)
		th.set_stylebox(state, "CheckBox", e)
	return th


static func _button_box(bg: Color, border: Color) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.border_color = border
	b.set_border_width_all(1)
	b.border_width_bottom = 2
	b.set_corner_radius_all(4)
	b.content_margin_left = 14
	b.content_margin_right = 14
	b.content_margin_top = 6
	b.content_margin_bottom = 6
	return b


# --- Top bar ---------------------------------------------------------------

func set_phase(phase_name: String, round_number: int) -> void:
	_round.text = phase_name if round_number <= 0 else "Round %d · %s" % [round_number, phase_name]
	_tool_title.text = phase_name


## seconds < 0 means the clock is off or not running: a plain black box.
func set_timer(seconds: float) -> void:
	_timer.set_time(seconds)
	_timer_label.visible = seconds >= 0.0


## The alarm light: on from the moment the battle begins.
func set_alarm(on: bool) -> void:
	_beacon.set_active(on)


func alarm_on() -> bool:
	return _beacon.active


## money_next: next round's money income, or -1 when there is none to show
## (setup, before round 1).
func set_resources(money: int, fuel: int, research: int, money_next: int = -1) -> void:
	_money_val.text = str(money)
	_money_next.visible = money_next >= 0
	_money_next.text = "(+%d)" % maxi(money_next, 0)
	_money_next.tooltip_text = "Next round: %d" % (money + maxi(money_next, 0))
	_fuel_val.text = str(fuel)
	_research_val.text = "+%d" % research


func _map_button(parent: Control, kind: String, tip: String, action: Callable) -> void:
	var ib := IconButton.new(kind, tip)
	ib.pressed.connect(action)
	parent.add_child(ib)


# --- Resource panel --------------------------------------------------------

const RES_CAPTION := Color(0.62, 0.68, 0.76)
const RES_VALUE := Color(0.97, 0.98, 1.0)
const RES_NEXT := Color(0.55, 0.85, 0.55)
const RES_ACCENT := {"money": Color(0.95, 0.78, 0.30), "fuel": Color(0.95, 0.55, 0.25), "research": Color(0.40, 0.80, 0.95)}


## A compact strip: three stats, each a small-caps caption over a bold
## value with a thin colour key, split by dividers.
func _build_resources() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.07, 0.09, 0.12, 0.9)
	st.border_color = Color(0.22, 0.26, 0.31)
	st.set_border_width_all(1)
	st.set_corner_radius_all(6)
	st.content_margin_left = 14
	st.content_margin_right = 14
	st.content_margin_top = 5
	st.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", st)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)
	var money := _stat(row, "Money", "money", "Money to build and repair with. Next round's income is in brackets.")
	_money_val = money[0]
	_money_next = Label.new()
	_money_next.add_theme_font_size_override("font_size", 13)
	_money_next.add_theme_color_override("font_color", RES_NEXT)
	_money_next.size_flags_vertical = Control.SIZE_SHRINK_END
	_money_next.mouse_filter = Control.MOUSE_FILTER_PASS
	money[1].add_child(_money_next)
	row.add_child(_divider())
	_fuel_val = _stat(row, "Fuel", "fuel", "Fuel launches missiles.")[0]
	row.add_child(_divider())
	_research_val = _stat(row, "Research", "research", "Research points your labs make each round.")[0]
	return panel


## Adds one stat block; returns [value label, value row].
func _stat(parent: Control, caption: String, key: String, tip: String) -> Array:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.tooltip_text = tip
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(box)
	var cap := RichTextLabel.new()
	cap.bbcode_enabled = true
	cap.fit_content = true
	cap.scroll_active = false
	cap.autowrap_mode = TextServer.AUTOWRAP_OFF
	cap.mouse_filter = Control.MOUSE_FILTER_PASS
	cap.add_theme_color_override("default_color", RES_CAPTION)
	cap.add_theme_font_override("normal_font", tracked_font(1))
	cap.text = small_caps(caption, 12, 9)
	box.add_child(cap)
	var vrow := HBoxContainer.new()
	vrow.add_theme_constant_override("separation", 5)
	vrow.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(vrow)
	var key_bar := ColorRect.new()
	key_bar.color = RES_ACCENT[key]
	key_bar.custom_minimum_size = Vector2(3, 16)
	key_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	key_bar.mouse_filter = Control.MOUSE_FILTER_PASS
	vrow.add_child(key_bar)
	var val := Label.new()
	val.add_theme_font_override("font", bold_font())
	val.add_theme_font_size_override("font_size", 19)
	val.add_theme_color_override("font_color", RES_VALUE)
	val.mouse_filter = Control.MOUSE_FILTER_PASS
	vrow.add_child(val)
	return [val, vrow]


static func _divider() -> Control:
	var d := ColorRect.new()
	d.color = Color(0.25, 0.29, 0.34)
	d.custom_minimum_size = Vector2(1, 30)
	d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return d


## Small caps from the default font, which has no small-caps glyphs: the
## first letter of each word at full size, the rest upper case and smaller.
static func small_caps(text: String, big: int, small: int) -> String:
	var words: Array = []
	for w in text.split(" ", false):
		words.append("[font_size=%d]%s[/font_size][font_size=%d]%s[/font_size]" % [big, w.left(1).to_upper(), small, w.substr(1).to_upper()])
	return " ".join(words)


static func bold_font() -> Font:
	var f := FontVariation.new()
	f.base_font = ThemeDB.fallback_font
	f.variation_embolden = 0.6
	return f


static func tracked_font(spacing: int) -> Font:
	var f := FontVariation.new()
	f.base_font = ThemeDB.fallback_font
	f.spacing_glyph = spacing
	return f


## Smaller text and height for the buttons under the resources.
static func _small_button(b: Button) -> void:
	b.add_theme_font_size_override("font_size", 13)
	b.custom_minimum_size = Vector2(0, 28)


func set_earnings(lines: Array, next_round: int) -> void:
	_earn_text.text = "Projected for round %d\n%s" % [next_round, "\n".join(lines)]


func _toggle_earnings(on: bool) -> void:
	_earn_panel.visible = on
	if on:
		earnings_requested.emit()


func earnings_visible() -> bool:
	return _earn_panel.visible


# --- Notices ---------------------------------------------------------------

## A short warning under the round title: white on dark red, fading after a
## few seconds. A new notice replaces the one showing.
func show_notice(text: String) -> void:
	if _notice_tween != null and _notice_tween.is_valid():
		_notice_tween.kill()
	_notice_text.text = text
	_notice.modulate = Color.WHITE
	_notice.visible = true
	_notice_tween = _notice.create_tween()
	_notice_tween.tween_interval(NOTICE_SECONDS)
	_notice_tween.tween_property(_notice, "modulate:a", 0.0, 0.5)
	_notice_tween.tween_callback(func(): _notice.visible = false)


func notice_showing() -> String:
	return _notice_text.text if _notice.visible else ""


# --- Log -------------------------------------------------------------------

## Adds an event to the history and flashes it at the top of the screen.
## flash false: into the history only (for lines the character says).
func add_log(text: String, flash: bool = true) -> void:
	_log.append_text(text + "\n")
	if not _log_panel.visible:
		_unread += 1
		_log_button.text = "Log (%d)" % _unread
	if not flash:
		return
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


## icon: an IconButton icon kind ("undo", "start") drawn at the left.
func add_tool_button(text: String, action: Callable, disabled: bool = false, pressed: bool = false, tooltip: String = "",
		icon: String = "") -> Button:
	var b := Button.new()
	b.text = text
	if icon != "":
		var glyph := Control.new()
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		glyph.position = Vector2(8, 4)
		glyph.size = Vector2(24, 28)
		var kind := icon
		glyph.draw.connect(func():
			IconButton.draw_icon(glyph, kind, glyph.size / 2.0, Color(0.9, 0.93, 0.96) if not b.disabled else Color(0.45, 0.47, 0.5)))
		b.add_child(glyph)
	b.disabled = disabled
	b.toggle_mode = pressed
	b.button_pressed = pressed
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 36)
	b.tooltip_text = tooltip
	b.pressed.connect(action)
	_tools.add_child(b)
	return b


## A button with a piece icon: piece_type may be "" for none.
## dimmed: drawn greyed out but still clickable, so the action can explain
## why it can't be done.
func add_piece_button(piece_type: String, title: String, detail: String, note: String, action: Callable,
		disabled: bool, pressed: bool, tooltip: String, dimmed: bool = false) -> void:
	var b := ToolButton.new()
	b.dimmed = dimmed
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


## Tips are spoken by the announcer; null clears the current tip.
func show_tip(tip) -> void:
	announcer.set_tip(tip)


## A line from the character. It stays until OK unless `seconds` > 0.
## id/can_hide: see announcer.gd.
func announce(text: String, id: String = "", seconds: float = 0.0, can_hide: bool = true, character: String = "") -> void:
	announcer.announce(text, id, seconds, can_hide, character)


## How long the alarm light takes to turn `turns` times.
func alarm_seconds(turns: float) -> float:
	return turns * TAU / Beacon.SPIN


func announcing() -> bool:
	return announcer.announcing()


## Where a tip's anchor is on screen: "timer" for the round timer,
## "tool:<type>" for a toolbar building button, "button:<label>" for a
## toolbar button by its label. Empty if it isn't shown.
func _anchor_rect(anchor: String) -> Rect2:
	if anchor.begins_with("button:"):
		var label := anchor.substr(7)
		for c in _tools.get_children():
			if c is Button and not (c is ToolButton) and c.text == label and not c.is_queued_for_deletion():
				return c.get_global_rect()
		return Rect2()
	if anchor == "timer":
		return _timer.get_global_rect()
	if anchor.begins_with("tool:"):
		var type := anchor.substr(5)
		for c in _tools.get_children():
			if c is ToolButton and c.piece_type == type and not c.is_queued_for_deletion():
				return c.get_global_rect()
	return Rect2()


func tip_showing() -> String:
	return announcer.tip_showing()


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


# --- Debug panel -----------------------------------------------------------

func toggle_debug(money_amount: int, fog_cleared: bool) -> void:
	_debug.visible = not _debug.visible
	_debug_money.text = "Add %d money" % money_amount
	_debug_fog.set_pressed_no_signal(fog_cleared)


func debug_visible() -> bool:
	return _debug.visible


func overlay_visible() -> bool:
	return _overlay.visible
