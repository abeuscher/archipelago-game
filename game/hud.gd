## Screen interface, laid out per spec section 14.
##   Left toolbar: phase tools, with the scoreboard timer at its foot.
##   Top middle: round indicator, and log events flashing as they happen.
##   Top right: resources (money with next round's income in brackets),
##   the next-round earnings button and the log history button.
##   Right side, toward the middle: the strip of research beakers and base
##   buttons, all the same size.
##   Bottom right: the radar monitor (the minimap, with coloured keys for
##   rotate and zoom) in the corner and the comms set (the info screen) to
##   its left, in the research mainframe's beige plastic (device_panel.gd).
## Plus the research panel, tips, the Esc menu, the end-of-game overlay and
## the debug panel (the ` key).
extends CanvasLayer

const Minimap = preload("res://game/minimap.gd")
const DevicePanel = preload("res://game/device_panel.gd")
const StatusGauge = preload("res://game/status_gauge.gd")
const VolumeSlider = preload("res://game/volume_slider.gd")
const SevenSeg = preload("res://game/seven_seg.gd")
const StripButton = preload("res://game/strip_button.gd")
const ToolButton = preload("res://game/tool_button.gd")
const FuelPlanner = preload("res://game/fuel_planner.gd")
const IconButton = preload("res://game/icon_button.gd")
const Beacon = preload("res://game/beacon.gd")
const ResourceIcon = preload("res://game/resource_icon.gd")
const Announcer = preload("res://game/announcer.gd")
const ResearchPanel = preload("res://game/research_panel.gd")
const EscMenu = preload("res://game/esc_menu.gd")

signal rotate_requested(dir: int)
signal zoom_requested(dir: int)
signal volume_changed(value: float, done: bool)   ## done: the slider was let go
signal tip_dismissed(id: String, forever: bool)
signal earnings_requested
signal debug_add_money
signal debug_toggle_fog(on: bool)
signal debug_next_level

var minimap
var status_gauge     ## our bases' hits left
var volume_slider    ## the main volume
var research_panel
var esc_menu
var _tool_title: Label
var _tools: VBoxContainer
var _tools_head: VBoxContainer   ## above the scrolling tools, always in view (the fuel gauge)
var _timer
var _beacon
var announcer
var _portrait_slot: Control
var _money_val: Label
var _money_next: Label
var _tray: Control           ## the toolbar's tool tray (a tip can point at it)
var _res_rows: Dictionary = {}   ## "money", "fuel", "research" -> the stat's row
var _radar_unit: Control
var _fuel_left: Label     ## in targeting: the fuel the aimed shots leave
var _fuel_next: Label
var _research_next: Label
var _fuel_val: Label
var _research_val: Label
var _round: Label          ## the phase, big on the title plate
var _round_no: Label       ## "ROUND 2", small above it
var _log_badge: Control    ## unread count on the log key
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
var _overlay: Control              ## the coin flip and end-of-game unit, centred
var _overlay_title: Label
var _overlay_video: VideoStreamPlayer   ## full-screen loop behind the end-of-game box
var hex_anchor: Callable         ## "hex:<what>" tip anchors -> Rect2 on screen (set by the game)
var _confirm: Control            ## a yes/no question in the middle of the screen
var _confirm_text: Label
var _confirm_yes: Callable
var _confirm_no: Callable
var _confirm_yes_key: Button
signal choice_menu_closed
var _ui_root: Control
var _menu: Control                ## the missile choice pop-up (with a click catcher behind it), or null
var _overlay_text: Label
var _overlay_buttons: HBoxContainer
var _debug: PanelContainer
var _debug_money: Button
var _debug_fog: CheckBox

const TOOLBAR_W := 260
const INFO_W := 400           ## the comms screen
const INFO_H := 150
const MINIMAP_W := 230
const MINIMAP_H := 220        ## a little taller than wide: the islands are stacked north and south
const RADAR_W := MINIMAP_W + 34   ## the radar monitor round the minimap
const RADAR_H := MINIMAP_H + 100
const BOTTOM_CLEAR := INFO_H + 40 ## screen height the comms set takes at the bottom
const PANEL_METAL := Color(0.47, 0.48, 0.43)
const PANEL_EDGE := Color(0.20, 0.20, 0.18)
const TRAY := Color(0.20, 0.21, 0.20)
const PORTRAIT_SLOT_H := 160  ## the character's space above the alarm light
const STRIP_W := 64
const FLASH_SECONDS := 4.0
const FLASH_MAX := 4
const NOTICE_SECONDS := 3.5
## Player notices: why an action can't be done. Shown under the round title.
const NOTICE_MONEY := "Out of money. Build more banks."
const NOTICE_FUEL := "Out of fuel. Build more refineries."
const NOTICE_SILO := "Missile silo damaged. Repair during build phase."
const NOTICE_NO_WEAPONS := "Player has no weapons to attack with."
const NOTICE_TRANSPORT := "Transport lost. Replace it during the build phase."
const NOTICE_BOAT_LOST := "Boat lost. Replace it during the build phase."
const NOTICE_BOAT_OUT := "Our boat is at sea. The docks can launch again once it has landed."
const NOTICE_NO_NUKE := "No nuke in the silo. Build one during the build phase."
const NOTICE_AGENT_OUT := "Our agent from this enclave is still on the enemy island. It can send another once he is caught."
const NOTICE_NUKE_LOADING := "The nuke is still being built. It can fire next round."


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = make_theme()
	add_child(root)
	_ui_root = root

	# Left toolbar.
	# An olive metal panel: a name plate, a dark tray holding the tools, then
	# the character's space, the alarm light and the timer.
	var left := PanelContainer.new()
	left.anchor_bottom = 1.0
	left.offset_right = TOOLBAR_W
	left.add_theme_stylebox_override("panel", _plate_box(PANEL_METAL, PANEL_EDGE, 3, 10, 10))
	root.add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 8)
	left.add_child(lv)
	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override("panel", _plate_box(Color(0.84, 0.82, 0.72), PANEL_EDGE, 2, 6, 4))
	plate.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	lv.add_child(plate)
	_tool_title = Label.new()
	_tool_title.add_theme_font_override("font", bold_font())
	_tool_title.add_theme_font_size_override("font_size", 16)
	_tool_title.add_theme_color_override("font_color", Color(0.16, 0.15, 0.12))
	plate.add_child(_tool_title)
	var tray := PanelContainer.new()
	_tray = tray
	tray.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tray.add_theme_stylebox_override("panel", _plate_box(TRAY, Color(0.12, 0.12, 0.11), 3, 8, 6))
	lv.add_child(tray)
	var tray_col := VBoxContainer.new()
	tray_col.add_theme_constant_override("separation", 6)
	tray.add_child(tray_col)
	_tools_head = VBoxContainer.new()
	tray_col.add_child(_tools_head)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tray_col.add_child(scroll)
	_tools = VBoxContainer.new()
	_tools.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tools.add_theme_constant_override("separation", 4)
	scroll.add_child(_tools)
	# The space where characters appear to talk to the player (announcer.gd),
	# then the alarm light sitting right on top of the timer.
	_portrait_slot = Control.new()
	_portrait_slot.custom_minimum_size = Vector2(0, PORTRAIT_SLOT_H)
	_portrait_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lv.add_child(_portrait_slot)
	var alarm_stack := VBoxContainer.new()
	alarm_stack.add_theme_constant_override("separation", 0)
	lv.add_child(alarm_stack)
	_beacon = Beacon.new()
	alarm_stack.add_child(_beacon)
	_timer = SevenSeg.new()
	_timer.tooltip_text = "Time left in this phase. Black when the clock is off or not running."
	alarm_stack.add_child(_timer)

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
	_key_button(_earn_button, Color(0.42, 0.80, 0.38))
	_earn_button.custom_minimum_size = Vector2(116, 38)
	trb.add_child(_earn_button)
	_log_button = Button.new()
	_log_button.toggle_mode = true
	_log_button.focus_mode = Control.FOCUS_NONE
	_log_button.tooltip_text = "Read back the game log"
	_log_button.toggled.connect(_toggle_log)
	_key_button(_log_button, Color(0.98, 0.58, 0.22))
	_log_button.custom_minimum_size = Vector2(44, 38)
	_log_button.add_child(DevicePanel.book_icon())
	_log_badge = Control.new()
	_log_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log_badge.position = Vector2(30, -8)
	_log_badge.size = Vector2(22, 18)
	_log_badge.visible = false
	_log_badge.draw.connect(func():
		var t := str(_unread) if _unread < 100 else "99+"
		var f := bold_font()
		var w := maxf(18.0, f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 10.0)
		var r := Rect2(Vector2(0, 0), Vector2(w, 18))
		_log_badge.draw_style_box(DevicePanel.box(Color(0.85, 0.15, 0.12), Color(0.3, 0.05, 0.04), 2, 9, [0, 0, 0, 0]), r)
		_log_badge.draw_string(f, Vector2(5, 13.5), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1)))
	_log_button.add_child(_log_badge)
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
	var title: Array = DevicePanel.title_plate()
	_round_no = title[1]
	_round = title[2]
	topr.add_child(title[0])
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
	var log_col := VBoxContainer.new()
	log_col.add_theme_constant_override("separation", 6)
	var log_head := Label.new()
	log_head.text = "TRANSMISSIONS"
	log_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	log_head.add_theme_font_override("font", DevicePanel.font(700))
	log_head.add_theme_font_size_override("font_size", 18)
	log_head.add_theme_color_override("font_color", ResearchPanel.ALERT)
	log_col.add_child(log_head)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.add_theme_font_override("normal_font", DevicePanel.font(500))
	_log.add_theme_font_override("bold_font", DevicePanel.font(800))
	_log.add_theme_font_size_override("normal_font_size", 14)
	_log.add_theme_font_size_override("bold_font_size", 14)
	_log.add_theme_color_override("default_color", DevicePanel.TEXT)
	log_col.add_child(_log)
	_log_panel = DevicePanel.log_unit(log_col, func(): _log_button.button_pressed = false)
	_log_panel.anchor_left = 0.5
	_log_panel.anchor_right = 0.5
	_log_panel.anchor_top = 0.5
	_log_panel.anchor_bottom = 0.5
	_log_panel.offset_left = -330
	_log_panel.offset_right = 330
	_log_panel.offset_top = -230
	_log_panel.offset_bottom = 190
	_log_panel.visible = false
	root.add_child(_log_panel)

	# Right strip: a beaker per research project. Centred vertically.
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

	# Bottom right: the radar monitor (the minimap, with the map keys under
	# it) in the corner, and the comms set (the info screen) to its left.
	_info = RichTextLabel.new()
	_info.bbcode_enabled = true
	_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info.add_theme_font_override("normal_font", DevicePanel.font(500))
	_info.add_theme_font_override("bold_font", DevicePanel.font(700))
	_info.add_theme_font_size_override("normal_font_size", 14)
	_info.add_theme_font_size_override("bold_font_size", 15)
	_info.add_theme_color_override("default_color", DevicePanel.TEXT)
	var ih := HBoxContainer.new()
	ih.add_theme_constant_override("separation", 8)
	ih.add_child(_info)
	var iscroll := ScrollContainer.new()
	iscroll.custom_minimum_size = Vector2(160, 0)
	iscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ih.add_child(iscroll)
	_info_actions = VBoxContainer.new()
	_info_actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	iscroll.add_child(_info_actions)

	minimap = Minimap.new()
	minimap.custom_minimum_size = Vector2(MINIMAP_W, MINIMAP_H)
	minimap.tooltip_text = "Click or drag to move the view. This is how you look at the other island."
	var keys: Array = []
	for k in [["rotate_left", "Rotate left (Q)", func(): rotate_requested.emit(-1)],
			["rotate_right", "Rotate right (E)", func(): rotate_requested.emit(1)],
			["zoom_out", "Zoom out", func(): zoom_requested.emit(-1)],
			["zoom_in", "Zoom in", func(): zoom_requested.emit(1)]]:
		keys.append(_map_key(k[0], k[1], k[2]))
	var radar := DevicePanel.radar(minimap, keys)
	_radar_unit = radar
	_corner(radar, 8)
	root.add_child(radar)

	status_gauge = StatusGauge.new()
	volume_slider = VolumeSlider.new()
	volume_slider.changed.connect(func(v: float): volume_changed.emit(v, false))
	volume_slider.released.connect(func(v: float): volume_changed.emit(v, true))
	var comms := DevicePanel.comms(ih, Vector2(INFO_W, INFO_H), status_gauge, volume_slider)
	_corner(comms, 8 + RADAR_W + 10)
	root.add_child(comms)

	# Hover text that follows the mouse over the board.
	_hover = PanelContainer.new()
	_hover.visible = false
	_hover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hover)
	_hover_text = Label.new()
	_hover.add_child(_hover_text)

	# Research panel, centred.
	# Research screen: covers everything right of the toolbar.
	research_panel = ResearchPanel.new()
	research_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	research_panel.offset_left = TOOLBAR_W
	research_panel.visible = false
	root.add_child(research_panel)

	# The character and speech bubble, above the board and panels.
	announcer = Announcer.new()
	announcer.slot = _portrait_slot
	announcer.anchor_rect = _anchor_rect
	announcer.tip_dismissed.connect(func(id: String, forever: bool): tip_dismissed.emit(id, forever))
	announcer.announcement_dismissed.connect(func(id: String, forever: bool): tip_dismissed.emit(id, forever))
	root.add_child(announcer)

	# Confirmation box: a small beige unit with the question on its screen
	# and YES / NO keys. Holds the clock while it is up.
	var cfill := Control.new()
	cfill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cfill.mouse_filter = Control.MOUSE_FILTER_STOP   # nothing behind it can be clicked
	cfill.visible = false
	root.add_child(cfill)
	var ccenter := CenterContainer.new()
	ccenter.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cfill.add_child(ccenter)
	var cunit := PanelContainer.new()
	cunit.add_theme_stylebox_override("panel", DevicePanel.box(DevicePanel.BEZEL, DevicePanel.BEZEL_EDGE, 4, 18, [16, 12, 16, 14]))
	ccenter.add_child(cunit)
	var ccol := VBoxContainer.new()
	ccol.add_theme_constant_override("separation", 12)
	cunit.add_child(ccol)
	var cplate := DevicePanel._plate("CONFIRM")
	ccol.add_child(cplate)
	_confirm_text = Label.new()
	_confirm_text.autowrap_mode = TextServer.AUTOWRAP_WORD
	_confirm_text.custom_minimum_size = Vector2(380, 0)
	_confirm_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm_text.add_theme_font_override("font", DevicePanel.font(600))
	_confirm_text.add_theme_font_size_override("font_size", 17)
	_confirm_text.add_theme_color_override("font_color", DevicePanel.TEXT)
	ccol.add_child(DevicePanel._screen(_confirm_text, 18))
	var ckeys := HBoxContainer.new()
	ckeys.alignment = BoxContainer.ALIGNMENT_CENTER
	ckeys.add_theme_constant_override("separation", 18)
	ccol.add_child(ckeys)
	for spec in [["YES", Color(0.42, 0.80, 0.38), true], ["NO", Color(0.90, 0.36, 0.22), false]]:
		var kb := Button.new()
		kb.text = spec[0]
		kb.focus_mode = Control.FOCUS_NONE
		kb.custom_minimum_size = Vector2(120, 44)
		_key_button(kb, spec[1])
		kb.add_theme_font_size_override("font_size", 18)
		var yes: bool = spec[2]
		if yes:
			_confirm_yes_key = kb
		kb.pressed.connect(func():
			_confirm.visible = false
			var cb: Callable = _confirm_yes if yes else _confirm_no
			if cb.is_valid():
				cb.call())
		ckeys.add_child(kb)
	_confirm = cfill

	# Centre overlay for the coin flip and the end of the game, with the
	# victory or defeat video looping full screen behind it.
	_overlay_video = VideoStreamPlayer.new()
	_overlay_video.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay_video.expand = true
	_overlay_video.loop = true
	_overlay_video.mouse_filter = Control.MOUSE_FILTER_STOP   # the map behind can't be clicked
	_overlay_video.visible = false
	root.add_child(_overlay_video)
	# A beige unit like the confirm box: a name plate, the recap on its
	# screen, and coloured keys.
	_overlay = CenterContainer.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.visible = false
	root.add_child(_overlay)
	var ounit := PanelContainer.new()
	ounit.add_theme_stylebox_override("panel", DevicePanel.box(DevicePanel.BEZEL, DevicePanel.BEZEL_EDGE, 4, 18, [16, 12, 16, 14]))
	_overlay.add_child(ounit)
	var ov := VBoxContainer.new()
	ov.add_theme_constant_override("separation", 12)
	ounit.add_child(ov)
	var oplate := DevicePanel._plate("")
	_overlay_title = oplate.get_child(0)
	_overlay_title.add_theme_font_size_override("font_size", 18)
	ov.add_child(oplate)
	_overlay_text = Label.new()
	_overlay_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_text.autowrap_mode = TextServer.AUTOWRAP_WORD
	_overlay_text.custom_minimum_size = Vector2(420, 0)
	_overlay_text.add_theme_font_override("font", DevicePanel.font(600))
	_overlay_text.add_theme_font_size_override("font_size", 17)
	_overlay_text.add_theme_color_override("font_color", DevicePanel.TEXT)
	ov.add_child(DevicePanel._screen(_overlay_text, 18))
	_overlay_buttons = HBoxContainer.new()
	_overlay_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_overlay_buttons.add_theme_constant_override("separation", 14)
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
	var skip := Button.new()
	skip.text = "Skip to next level"
	skip.focus_mode = Control.FOCUS_NONE
	skip.tooltip_text = "Start the next level now, with the award a win gives"
	skip.pressed.connect(func(): debug_next_level.emit())
	dv.add_child(skip)

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
	# The plate shows the round once play starts (the toolbar names the
	# phase), and the phase only before round 1 (setup).
	_round.text = "ROUND %d" % round_number if round_number > 0 else phase_name.to_upper()
	_round_no.visible = false
	_tool_title.text = phase_name.to_upper().replace(" AND ", " & ")


## seconds < 0 means the clock is off or not running: a plain black box.
func set_timer(seconds: float) -> void:
	_timer.set_time(seconds)


## The alarm light: on from the moment the battle begins.
func set_alarm(on: bool) -> void:
	_beacon.set_active(on)


func alarm_on() -> bool:
	return _beacon.active


## money_next: next round's money income, or -1 when there is none to show
## (setup, before round 1). fuel_left: in targeting, the fuel the aimed shots
## leave, or -1 to hide it. fuel_next, research_next: next round's income of
## each, -1 to hide.
func set_resources(money: int, fuel: int, research: int, money_next: int = -1, fuel_left: int = -1,
		fuel_next: int = -1, research_next: int = -1) -> void:
	_fuel_left.visible = fuel_left >= 0
	_fuel_left.text = "(%d left)" % maxi(fuel_left, 0)
	_fuel_next.visible = fuel_next >= 0 and fuel_left < 0
	_fuel_next.text = "(+%d)" % maxi(fuel_next, 0)
	_research_next.visible = research_next >= 0
	_research_next.text = "(+%d)" % maxi(research_next, 0)
	_money_val.text = str(money)
	_money_next.visible = money_next >= 0
	_money_next.text = "(+%d)" % maxi(money_next, 0)
	_fuel_val.text = str(fuel)
	_research_val.text = str(research)


## A chunky coloured key on the radar for rotating or zooming the view.
func _map_key(kind: String, tip: String, action: Callable) -> Button:
	var ib := IconButton.new(kind, tip)
	ib.ink = Color(0.12, 0.11, 0.10)
	DevicePanel.style_key(ib, DevicePanel.KEY_COLORS[kind])
	ib.pressed.connect(action)
	return ib


## Pins a device to the bottom-right corner, `right` pixels in from the
## right edge; it grows up and left to its own size.
static func _corner(c: Control, right: float) -> void:
	c.anchor_left = 1.0
	c.anchor_right = 1.0
	c.anchor_top = 1.0
	c.anchor_bottom = 1.0
	c.offset_left = -right
	c.offset_right = -right
	c.offset_top = -8
	c.offset_bottom = -8
	c.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	c.grow_vertical = Control.GROW_DIRECTION_BEGIN


# --- Resource panel --------------------------------------------------------

const RES_VALUE := Color(0.97, 0.98, 1.0)
const RES_NEXT := Color(0.55, 0.85, 0.55)


## A compact strip: three stats, each an icon (coin, barrel, flask) and a
## bold value, split by dividers.
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
	_res_rows["resources"] = panel   # the whole strip
	var money := _stat(row, "Money", "money")
	_res_rows["money"] = money[1]
	_money_val = money[0]
	_money_next = Label.new()
	_money_next.add_theme_font_size_override("font_size", 13)
	_money_next.add_theme_color_override("font_color", RES_NEXT)
	_money_next.size_flags_vertical = Control.SIZE_SHRINK_END
	_money_next.mouse_filter = Control.MOUSE_FILTER_PASS
	money[1].add_child(_money_next)
	row.add_child(_divider())
	var fuel := _stat(row, "Fuel", "fuel")
	_res_rows["fuel"] = fuel[1]
	_fuel_val = fuel[0]
	_fuel_left = Label.new()
	_fuel_left.add_theme_font_size_override("font_size", 13)
	_fuel_left.add_theme_color_override("font_color", RES_NEXT)
	_fuel_left.size_flags_vertical = Control.SIZE_SHRINK_END
	_fuel_left.mouse_filter = Control.MOUSE_FILTER_PASS
	_fuel_left.visible = false
	fuel[1].add_child(_fuel_left)
	_fuel_next = _next_label()
	fuel[1].add_child(_fuel_next)
	row.add_child(_divider())
	var res := _stat(row, "Research: points stored for later, made while no project was running (in brackets, what the labs make a round)", "research")
	_res_rows["research"] = res[1]
	_research_val = res[0]
	_research_next = _next_label()
	res[1].add_child(_research_next)
	return panel


## The small green "(+N)" beside a resource.
func _next_label() -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", RES_NEXT)
	l.size_flags_vertical = Control.SIZE_SHRINK_END
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	l.visible = false
	return l


## Adds one stat: its icon and value, named only in the tooltip. Returns
## [value label, value row].
func _stat(parent: Control, caption: String, key: String) -> Array:
	var vrow := HBoxContainer.new()
	vrow.add_theme_constant_override("separation", 5)
	vrow.tooltip_text = caption
	vrow.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(vrow)
	vrow.add_child(ResourceIcon.new(key))
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
	d.custom_minimum_size = Vector2(1, 22)
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


## The log in capitals, like the mainframe's screens; BBCode tags are left
## alone.
static func _terminal_case(text: String) -> String:
	var out := ""
	var in_tag := false
	for ch in text:
		if ch == "[":
			in_tag = true
		elif ch == "]":
			in_tag = false
		out += ch if in_tag else ch.to_upper()
	return out


## A top-right button as a chunky coloured key with dark lettering.
static func _key_button(b: Button, color: Color) -> void:
	DevicePanel.style_key(b, color)
	b.add_theme_font_override("font", bold_font())
	b.add_theme_font_size_override("font_size", 15)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(c, DevicePanel.PLATE_INK)


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
	_log.append_text("* " + _terminal_case(text) + "\n")
	if not _log_panel.visible:
		_unread += 1
		_log_badge.visible = true
		_log_badge.queue_redraw()
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
		_log_badge.visible = false


# --- Left toolbar ----------------------------------------------------------

func clear_tools() -> void:
	for box in [_tools, _tools_head]:
		for c in box.get_children():
			box.remove_child(c)
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
## primary: the big red button that moves the game on (Start, Done, Attack).
func add_tool_button(text: String, action: Callable, disabled: bool = false, pressed: bool = false, tooltip: String = "",
		icon: String = "", primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	if primary:
		b.text = text.to_upper()
		b.custom_minimum_size = Vector2(0, 44)
		b.add_theme_font_size_override("font_size", 18)
		b.add_theme_color_override("font_color", Color(1, 0.96, 0.9))
		b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
		b.add_theme_color_override("font_disabled_color", Color(0.75, 0.68, 0.66))
		b.add_theme_stylebox_override("normal", _red_box(Color(0.86, 0.30, 0.20)))
		b.add_theme_stylebox_override("hover", _red_box(Color(0.94, 0.40, 0.28)))
		b.add_theme_stylebox_override("pressed", _red_box(Color(0.70, 0.22, 0.14)))
		b.add_theme_stylebox_override("disabled", _red_box(Color(0.48, 0.30, 0.27)))
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
static func _red_box(bg: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = Color(0.32, 0.08, 0.05)
	s.set_border_width_all(2)
	s.border_width_bottom = 4
	s.set_corner_radius_all(8)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s


static func _plate_box(bg: Color, edge: Color, width: int, radius: int, margin: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = edge
	s.set_border_width_all(width)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	return s


## dimmed: drawn greyed out but still clickable, so the action can explain
## why it can't be done.
## compact: a tile in a two-across grid (consecutive compact buttons share
## one grid).
func add_piece_button(piece_type: String, title: String, detail: String, note: String, action: Callable,
		disabled: bool, pressed: bool, tooltip: String, dimmed: bool = false, compact: bool = false, tag: String = "",
		marked: bool = false, out: bool = false) -> void:
	var b := ToolButton.new()
	b.marked = marked
	b.out = out
	b.dimmed = dimmed
	b.compact = compact
	b.broke = dimmed
	b.tag = tag
	b.piece_type = piece_type
	b.title = title
	b.detail = detail
	b.note = note
	b.disabled = disabled
	b.toggle_mode = pressed
	b.button_pressed = pressed
	b.tooltip_text = tooltip
	b.pressed.connect(action)
	if compact:
		b.custom_minimum_size = Vector2(0, 74)
		if note != "":
			b.tooltip_text = (title + " — " + note + "\n" + tooltip) if tooltip != "" else title + " — " + note
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var grid: GridContainer = null
		var n := _tools.get_child_count()
		if n > 0 and _tools.get_child(n - 1) is GridContainer and not _tools.get_child(n - 1).is_queued_for_deletion():
			grid = _tools.get_child(n - 1)
		if grid == null:
			grid = GridContainer.new()
			grid.columns = 2
			grid.add_theme_constant_override("h_separation", 4)
			grid.add_theme_constant_override("v_separation", 4)
			_tools.add_child(grid)
		grid.add_child(b)
	else:
		_tools.add_child(b)


func add_fuel_planner(fuel: int, planned: int) -> void:
	var f := FuelPlanner.new()
	f.set_values(fuel, planned)
	f.tooltip_text = "Fuel used by the orders placed so far, out of the fuel you have."
	_tools_head.add_child(f)


# --- Right strip -----------------------------------------------------------

## items: Array of {"kind": "beaker", "fraction", "details",
## "action": Callable, "enabled": bool}.
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
	_info_actions.get_parent().visible = false   # the text gets the whole screen


func add_info_action(text: String, action: Callable, disabled: bool = false, tooltip: String = "") -> void:
	var b := Button.new()
	b.text = text
	b.disabled = disabled
	b.tooltip_text = tooltip
	b.focus_mode = Control.FOCUS_NONE
	# Terminal buttons on the comms screen.
	b.add_theme_font_override("font", DevicePanel.font(700))
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_color_override("font_color", DevicePanel.TEXT)
	b.add_theme_color_override("font_hover_color", Color(1, 1, 0.9))
	b.add_theme_color_override("font_disabled_color", DevicePanel.DIM_TEXT.darkened(0.3))
	var screen := DevicePanel.SCREEN
	b.add_theme_stylebox_override("normal", DevicePanel.box(screen.lightened(0.06), DevicePanel.DIM_TEXT, 1, 4, [8, 4, 8, 4]))
	b.add_theme_stylebox_override("hover", DevicePanel.box(screen.lightened(0.14), DevicePanel.TEXT, 1, 4, [8, 4, 8, 4]))
	b.add_theme_stylebox_override("pressed", DevicePanel.box(screen.darkened(0.2), DevicePanel.TEXT, 1, 4, [8, 4, 8, 4]))
	b.add_theme_stylebox_override("disabled", DevicePanel.box(screen, DevicePanel.DIM_TEXT.darkened(0.4), 1, 4, [8, 4, 8, 4]))
	b.pressed.connect(action)
	_info_actions.add_child(b)
	_info_actions.get_parent().visible = true


func add_info_text(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.add_theme_font_override("font", DevicePanel.font(500))
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", DevicePanel.DIM_TEXT)
	_info_actions.add_child(l)
	_info_actions.get_parent().visible = true


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
func announce(text: String, id: String = "", seconds: float = 0.0, can_hide: bool = true, character: String = "",
		hold: bool = true, click_away: bool = false) -> void:
	announcer.announce(text, id, seconds, can_hide, character, hold, click_away)


## How long the alarm light takes to turn `turns` times.
func alarm_seconds(turns: float) -> float:
	return turns * TAU / Beacon.SPIN


func announcing() -> bool:
	return announcer.announcing()


## Where a tip's anchor is on screen: "timer" for the round timer,
## "tool:<type>" for a toolbar building button, "button:<label>" for a
## toolbar button by its label, "weapons" for the first weapon in
## targeting, "hex:<what>" for a hex on the map (asked of the game through
## hex_anchor). Empty if it isn't shown.
func _anchor_rect(anchor: String) -> Rect2:
	if anchor.begins_with("hex:"):
		return hex_anchor.call(anchor.substr(4)) if hex_anchor.is_valid() else Rect2()
	if anchor == "weapons":
		for c in _tools.get_children():
			if c is GridContainer:
				for t in c.get_children():
					if t is ToolButton and not t.is_queued_for_deletion():
						return t.get_global_rect()
		return Rect2()
	if anchor.begins_with("button:"):
		var label := anchor.substr(7)
		for c in _tools.get_children():
			if c is Button and not (c is ToolButton) and c.text == label and not c.is_queued_for_deletion():
				return c.get_global_rect()
		return Rect2()
	if anchor == "timer":
		return _timer.get_global_rect()
	if anchor.begins_with("res:"):
		var row = _res_rows.get(anchor.substr(4))
		return row.get_global_rect() if row != null else Rect2()
	match anchor:
		"toolbar": return _tray.get_global_rect()
		"resources": return _res_rows["resources"].get_global_rect()
		"minimap": return _radar_unit.get_global_rect()
		"info": return _info.get_global_rect()
		"volume": return volume_slider.get_global_rect()
		"status": return status_gauge.get_global_rect()
	if anchor.begins_with("tool:"):
		var type := anchor.substr(5)
		var found: Array = []
		for c in _tools.get_children():
			found.append(c)
			if c is GridContainer:
				found.append_array(c.get_children())
		for c in found:
			if c is ToolButton and c.piece_type == type and not c.is_queued_for_deletion():
				return c.get_global_rect()
	return Rect2()


func tip_showing() -> String:
	return announcer.tip_showing()


# --- Overlay ---------------------------------------------------------------

## title: on the unit's name plate. video: a res:// path (or one under
## res://) to loop full screen behind the box; "" for none. Keys: the first
## is green, Quit red, any others yellow.
func show_overlay(title: String, text: String, buttons: Array, video: String = "") -> void:
	_overlay_title.text = title.to_upper()
	_overlay_text.text = text
	_set_overlay_video(video)
	for c in _overlay_buttons.get_children():
		c.queue_free()
	for i in buttons.size():
		var spec: Array = buttons[i]
		var b := Button.new()
		b.text = String(spec[0]).to_upper()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(maxf(130.0, 16.0 + 12.0 * String(spec[0]).length()), 44)
		var col := Color(0.42, 0.80, 0.38) if i == 0 else (Color(0.90, 0.36, 0.22) if spec[0] == "Quit" else Color(0.97, 0.80, 0.25))
		_key_button(b, col)
		b.add_theme_font_size_override("font_size", 17)
		var action: Callable = spec[1]
		b.pressed.connect(func():
			_overlay.visible = false
			_set_overlay_video("")
			action.call())
		_overlay_buttons.add_child(b)
	_overlay.visible = true


func _set_overlay_video(path: String) -> void:
	var full := path if path == "" or path.begins_with("res://") else "res://" + path
	var stream: VideoStream = load(full) if full != "" and ResourceLoader.exists(full) else null
	if stream == null:
		_overlay_video.stop()
		_overlay_video.visible = false
		return
	_overlay_video.stream = stream
	_overlay_video.visible = true
	_overlay_video.play()


# --- Debug panel -----------------------------------------------------------

func toggle_debug(money_amount: int, fog_cleared: bool) -> void:
	_debug.visible = not _debug.visible
	_debug_money.text = "Add %d money" % money_amount
	_debug_fog.set_pressed_no_signal(fog_cleared)


func debug_visible() -> bool:
	return _debug.visible


## A window over the map is open (log, research, next-round projection or
## an end-of-game overlay): the mouse wheel shouldn't zoom the map then.
func modal_open() -> bool:
	return _log_panel.visible or research_panel.visible or _earn_panel.visible or _overlay.visible or _confirm.visible \
		or _menu != null


## A yes/no question in a box of its own (not a character's speech): YES
## calls on_yes, NO calls on_no. The clock holds while it is up.
func confirm(text: String, on_yes: Callable, on_no: Callable = Callable()) -> void:
	_confirm_text.text = text
	_confirm_yes = on_yes
	_confirm_no = on_no
	_confirm.visible = true


## A small beige pop-up at screen_pos with a key per choice, for picking
## which missile a launcher fires at the hex just clicked. choices:
## [{"text", "color", "disabled", "why", "action"}]. A click anywhere else,
## right-click or Escape closes it without choosing.
func choice_menu(screen_pos: Vector2, title: String, choices: Array) -> void:
	close_choice_menu()
	var catcher := Control.new()
	catcher.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	catcher.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed:
			close_choice_menu())
	_ui_root.add_child(catcher)
	var unit := PanelContainer.new()
	unit.add_theme_stylebox_override("panel", DevicePanel.box(DevicePanel.BEZEL, DevicePanel.BEZEL_EDGE, 3, 12, [10, 8, 10, 10]))
	catcher.add_child(unit)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	unit.add_child(col)
	col.add_child(DevicePanel._plate(title.to_upper()))
	for ch in choices:
		var b := Button.new()
		b.text = String(ch["text"]).to_upper()
		b.focus_mode = Control.FOCUS_NONE
		_key_button(b, ch["color"])
		# Room for the text plus a margin each side, the key's edges being tight.
		var font: Font = b.get_theme_font("font")
		var fs: int = b.get_theme_font_size("font_size")
		b.custom_minimum_size = Vector2(maxf(230.0, font.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 32.0), 40)
		if bool(ch.get("disabled", false)):
			b.disabled = true
			b.modulate = Color(1, 1, 1, 0.45)
			b.tooltip_text = String(ch.get("why", ""))
		var act: Callable = ch["action"]
		b.pressed.connect(func():
			close_choice_menu()
			act.call())
		col.add_child(b)
	_menu = catcher
	# Beside the click, kept on screen.
	unit.reset_size()
	var view := _ui_root.get_viewport_rect().size
	var sz := unit.get_combined_minimum_size()
	var at := screen_pos + Vector2(14, 10)
	at.x = clampf(at.x, 4.0, view.x - sz.x - 4.0)
	at.y = clampf(at.y, 4.0, view.y - sz.y - 4.0)
	unit.position = at


func close_choice_menu() -> void:
	if _menu != null:
		_menu.queue_free()
		_menu = null
		choice_menu_closed.emit()


func choice_menu_open() -> bool:
	return _menu != null


func _input(event: InputEvent) -> void:
	# Enter is the OK key: YES on a question, the first key of the coin flip
	# or end-of-game box, otherwise OK on the character's message.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ENTER, KEY_KP_ENTER] \
			and _menu == null and not esc_menu.visible:
		var pressed := false
		if _confirm.visible:
			_confirm_yes_key.pressed.emit()
			pressed = true
		elif _overlay.visible and _overlay_buttons.get_child_count() > 0:
			(_overlay_buttons.get_child(0) as Button).pressed.emit()
			pressed = true
		else:
			pressed = announcer.press_ok()
		if pressed:
			get_viewport().set_input_as_handled()
			return
	if _menu == null:
		return
	if (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE) \
			or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT):
		close_choice_menu()
		get_viewport().set_input_as_handled()


func confirm_visible() -> bool:
	return _confirm.visible


func overlay_visible() -> bool:
	return _overlay.visible
