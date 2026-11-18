## The playable loop: setup, then rounds of build/repair, targeting and
## playout against the AI. Drives MatchState only through its public calls.
extends Node2D

const GameData = preload("res://rules/game_data.gd")
const MatchState = preload("res://rules/match_state.gd")
const StrongAI = preload("res://ai/strong_ai.gd")
const BoardView = preload("res://game/board_view.gd")
const Effects = preload("res://game/effects.gd")
const Minimap = preload("res://game/minimap.gd")
const OceanView = preload("res://game/ocean_view.gd")
const Iso = preload("res://game/iso.gd")
const Pieces = preload("res://game/pieces.gd")
const Audio = preload("res://game/audio.gd")
const Hud = preload("res://game/hud.gd")
const UserSettings = preload("res://game/user_settings.gd")
const Tips = preload("res://game/tips.gd")
const Earnings = preload("res://game/earnings.gd")

const REPAIR_SOUND := "assets/audio/repair_work_crew.ogg"
const CHANNEL_ROWS := 4        ## rows of open sea between the two islands
const FLY_SECONDS := 0.9       ## camera move between islands at a phase change
const FIT_MARGIN := 0.92       ## share of the free screen an island fills when fitted
const ZOOM_MIN := 0.3
const ZOOM_MAX := 3.0
const PAN_SPEED := 700.0
const ZOOM_STEP := 1.25        ## per press of a zoom button

enum Ui { SETUP, BUILD, TARGETING, PLAYOUT, COIN, OVER }

var data
var m
var enemy_ai
var seed_value: int
var own_board
var enemy_board
var effects
var camera: Camera2D
var audio
var hud
var prefs: Dictionary                ## the player's settings (user_settings.gd)
var prefs_path: String = UserSettings.PATH
var tips: Array = []
var current_tip = null
var tips_snoozed: Array = []         ## hidden for the rest of this phase

var ui: int = Ui.SETUP
var viewing: int = 0
var rot: int = 0
var clock_left: float = 0.0
var clock_running: bool = false
var tool: String = ""
var setup_mode: String = "base"
var setup_trial                     ## SideState copy used to preview setup
var setup_history: Array = []       ## hexes placed during setup, oldest first, for Undo
var orders: Array = []
var active_launcher: int = -1
var missile_choice: Dictionary = {} ## launcher hex -> missile type
var selected: Vector2i = Vector2i(-1, -1)   ## (side, hex)
var hovered: Vector2i = Vector2i(-1, -1)
var _drag_from: Vector2
var _dragging: bool = false
var _drag_moved: float = 0.0
var ocean
var _cam_tween: Tween
var debug_no_fog: bool = false       ## debug tool: show the enemy island as it really is


func _ready() -> void:
	data = GameData.load_default()
	if has_meta("settings_path"):
		prefs_path = String(get_meta("settings_path"))
	prefs = UserSettings.load_settings(data.settings, prefs_path)
	tips = Tips.load_tips(data)
	seed_value = _seed_from_args()
	m = MatchState.create(data, seed_value, UserSettings.match_overrides(prefs))
	enemy_ai = StrongAI.new(MatchState.ENEMY, data, seed_value)

	# Sea first, then the enemy island (north, further back), then ours.
	ocean = OceanView.new()
	add_child(ocean)
	enemy_board = BoardView.new()
	enemy_board.setup(m.sides[1].island.grid)
	enemy_board.show_hits = true
	add_child(enemy_board)
	own_board = BoardView.new()
	own_board.setup(m.sides[0].island.grid)
	add_child(own_board)
	_layout_boards()
	_apply_grid()
	effects = Effects.new()
	effects.z_index = 10
	add_child(effects)
	camera = Camera2D.new()
	add_child(camera)
	audio = Audio.new()
	add_child(audio)

	hud = Hud.new()
	add_child(hud)
	hud.minimap.setup(own_board, enemy_board, ocean, camera)
	hud.minimap.view_requested.connect(_on_minimap)
	hud.rotate_requested.connect(_rotate)
	hud.zoom_requested.connect(func(dir: int): _zoom_at(ZOOM_STEP if dir > 0 else 1.0 / ZOOM_STEP, get_viewport_rect().size / 2.0))
	hud.debug_add_money.connect(_debug_add_money)
	hud.debug_toggle_fog.connect(_debug_toggle_fog)
	hud.earnings_requested.connect(_update_earnings)
	hud.tip_dismissed.connect(_on_tip_dismissed)
	hud.research_panel.start_requested.connect(_start_research)
	hud.esc_menu.setup(data.settings, prefs)
	hud.esc_menu.settings_changed.connect(_on_settings_changed)
	hud.esc_menu.quit_requested.connect(func(): get_tree().quit())

	var es: Dictionary = enemy_ai.choose_setup(m.view_for(MatchState.ENEMY))
	var e: String = m.setup_side(MatchState.ENEMY, es["bases"], es["decoys"])
	assert(e == "", "Enemy setup failed: " + e)
	hud.add_log("New game. Seed %d." % seed_value)
	_enter_setup()


func _seed_from_args() -> int:
	if has_meta("seed_override"):
		return int(get_meta("seed_override"))
	var args := OS.get_cmdline_user_args()
	var i := args.find("--seed")
	if i >= 0 and i + 1 < args.size():
		return int(args[i + 1])
	return int(Time.get_unix_time_from_system() * 1000.0) & 0x7FFFFFFF


## Our island at the origin, the enemy's straight north across a channel of
## CHANNEL_ROWS rows of sea, for the current rotation. Both centres sit on
## the shared hex lattice (see iso.gd), so the sea lines up with both.
func _layout_boards() -> void:
	own_board.position = Vector2.ZERO
	var own_top: float = -own_board.iso.plane_extent().position.y
	var enemy_bottom: float = enemy_board.iso.plane_extent().end.y
	var need := own_top + enemy_bottom + (CHANNEL_ROWS + 1) * Iso.ROW_H
	# Straight north on the lattice is axial (1, -2): two rows up per step.
	var steps := ceili(need / (2.0 * Iso.ROW_H))
	enemy_board.position = Vector2(0, -steps * 2.0 * Iso.ROW_H * Iso.SQUASH)
	ocean.rebuild([own_board, enemy_board])


# --- Phases ----------------------------------------------------------------

func _enter_setup() -> void:
	ui = Ui.SETUP
	tips_snoozed = []
	setup_trial = m.sides[0].duplicate_state()
	setup_history = []
	setup_mode = "base"
	hud.set_alarm(false)
	_fly_to(0, 0.0)
	hud.set_phase("Setup", 0)
	_set_clock(0)
	hud.add_log("Place your three bases. Bases and decoys may not touch each other.")
	_refresh()


func _start_setup_game() -> void:
	var bases: Array = []
	var decoys: Array = []
	for b in setup_trial.buildings_sorted():
		if b.type == "base":
			bases.append(b.hex)
		elif b.type == "decoy":
			decoys.append(b.hex)
	var e: String = m.setup_side(MatchState.PLAYER, bases, decoys)
	if e != "":
		hud.add_log("[color=salmon]%s[/color]" % e)
		return
	setup_trial = null
	_start_round()


func _start_round() -> void:
	var events: Array = m.begin_round()
	for ev in events:
		_log_event(ev)
	# The enemy commits its build for the round from its own view.
	for a in enemy_ai.choose_build(m.view_for(MatchState.ENEMY)):
		m.build_action(MatchState.ENEMY, a)
	hud.set_alarm(false)
	ui = Ui.BUILD
	tool = ""
	tips_snoozed = []
	orders = []   # last round's aim markers don't carry over
	selected = Vector2i(-1, -1)
	_fly_to(0)
	hud.set_phase("Build and repair", m.round_number)
	_set_clock(int(prefs["build_clock_seconds"]))
	_refresh()


func _end_build() -> void:
	if ui != Ui.BUILD:
		return
	m.end_build_phase()
	hud.research_panel.visible = false
	var eo: Array = enemy_ai.choose_targets(m.view_for(MatchState.ENEMY))
	if m.set_launch_orders(MatchState.ENEMY, eo) != "":
		m.set_launch_orders(MatchState.ENEMY, [])
	if _next_free_launcher() < 0:
		# Nothing to fire: our attack turn is skipped.
		hud.show_notice(Hud.NOTICE_NO_WEAPONS)
		m.set_launch_orders(MatchState.PLAYER, [])
		orders = []
		ui = Ui.TARGETING
		_attack()
		return
	ui = Ui.TARGETING
	tips_snoozed = []
	tool = ""
	orders = []
	missile_choice = {}
	selected = Vector2i(-1, -1)
	active_launcher = _next_free_launcher()
	_fly_to(1)
	hud.set_phase("Targeting", m.round_number)
	_set_clock(int(prefs["targeting_clock_seconds"]))
	_refresh()


func _attack() -> void:
	if ui != Ui.TARGETING:
		return
	_set_clock(0)
	ui = Ui.PLAYOUT
	hud.set_phase("Playout", m.round_number)
	_refresh()
	_run_playout()


func _after_playout() -> void:
	if m.phase == MatchState.Phase.COIN_FLIP:
		ui = Ui.COIN
		hud.show_overlay("Both sides lost their last base this round, with equal money.\nThe enemy calls %s." % String(m.coin["call"]).to_upper(),
			[["Flip the coin", _flip_coin]])
	elif m.is_over():
		_show_game_over()
	else:
		_start_round()


func _flip_coin() -> void:
	for ev in m.resolve_coin_flip():
		_log_event(ev)
	_show_game_over()


func _show_game_over() -> void:
	ui = Ui.OVER
	var won: bool = m.winner == MatchState.PLAYER
	var why := {"bases": "All three enemy bases destroyed." if won else "All three of your bases were destroyed.",
		"money": "Both sides fell together; %s more money." % ("you had" if won else "the enemy had"),
		"coin": "Coin: enemy called %s, it landed %s." % [m.coin.get("call", ""), m.coin.get("flip", "")]}
	hud.show_overlay(("ISLAND TAKEN\n" if won else "DEFEAT\n") + String(why.get(m.end_reason, "")),
		[["New game", func(): get_tree().reload_current_scene()], ["Quit", func(): get_tree().quit()]])
	_refresh()


# --- Clock -----------------------------------------------------------------

func _set_clock(seconds: int) -> void:
	clock_left = float(seconds)
	clock_running = seconds > int(data.settings["clock_off_value"])
	hud.set_timer(clock_left if clock_running else -1.0)


func _process(delta: float) -> void:
	if clock_running and not hud.overlay_visible() and not _tip_holds_clock():
		clock_left -= delta
		hud.set_timer(maxf(clock_left, 0.0))
		if clock_left <= 0.0:
			clock_running = false
			if ui == Ui.BUILD:
				_end_build()
			elif ui == Ui.TARGETING:
				_attack()   # orders placed so far are launched
	var pan := Vector2(Input.get_axis("ui_left", "ui_right"), Input.get_axis("ui_up", "ui_down"))
	if pan != Vector2.ZERO:
		_stop_flight()
		camera.position += pan * PAN_SPEED * delta / camera.zoom.x
		_update_viewing()


# --- Input -----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			if mb.pressed:
				_dragging = true
				_drag_from = mb.position
				_drag_moved = 0.0
			else:
				_dragging = false
				if mb.button_index == MOUSE_BUTTON_RIGHT and _drag_moved < 6.0:
					_cancel()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(1.12, mb.position)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(1.0 / 1.12, mb.position)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var hit := _pick(get_global_mouse_position())
			if hit.y >= 0:
				_click(hit.x, hit.y)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _dragging:
			_stop_flight()
			camera.position -= mm.relative / camera.zoom.x
			_drag_moved += mm.relative.length()
			_update_viewing()
		var hit := _pick(get_global_mouse_position())
		if hit == hovered:
			_update_hover_text()
		else:
			hovered = hit
			own_board.hover = hit.y if hit.x == 0 else -1
			enemy_board.hover = hit.y if hit.x == 1 else -1
			own_board.queue_redraw()
			enemy_board.queue_redraw()
			_update_info()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_Q: _rotate(-1)
			KEY_E: _rotate(1)
			KEY_QUOTELEFT: hud.toggle_debug(int(data.settings["debug_money"]), debug_no_fog)


func _zoom_at(factor: float, screen_pos: Vector2) -> void:
	_stop_flight()
	var before := get_canvas_transform().affine_inverse() * screen_pos
	var z := clampf(camera.zoom.x * factor, ZOOM_MIN, ZOOM_MAX)
	camera.zoom = Vector2(z, z)
	camera.force_update_scroll()
	var after := get_canvas_transform().affine_inverse() * screen_pos
	camera.position += before - after


func _pick(world: Vector2) -> Vector2i:
	for side in [0, 1]:
		var board = own_board if side == 0 else enemy_board
		var h: int = board.hex_at(world - board.position)
		if h >= 0:
			return Vector2i(side, h)
	return Vector2i(-1, -1)


func _rotate(dir: int) -> void:
	var center_side := viewing
	rot = (rot + dir + 6) % 6
	own_board.set_rotation_step(rot)
	enemy_board.set_rotation_step(rot)
	_layout_boards()
	_focus(center_side)


## Centres the view on an island at once, keeping the zoom.
func _focus(side: int) -> void:
	_stop_flight()
	var board = own_board if side == 0 else enemy_board
	camera.position = board.position + board.bounds().get_center()
	viewing = side


## Moves and zooms the view so the island fills the free part of the screen
## (between the toolbar, the strip, the top bar and the bottom panels). With seconds > 0 the
## camera glides there, so the player sees how the two islands sit.
func _fly_to(side: int, seconds: float = FLY_SECONDS) -> void:
	_stop_flight()
	viewing = side
	var board = own_board if side == 0 else enemy_board
	var island: Rect2 = board.bounds()
	island.position += board.position
	var vp := get_viewport_rect().size
	var free := Rect2(Vector2(Hud.TOOLBAR_W + 16, 70), Vector2.ZERO)
	free.end = Vector2(vp.x - Hud.STRIP_W - 28, vp.y - Hud.BOTTOM_H - Hud.MAP_BAR_H - 8)
	var z := clampf(minf(free.size.x / island.size.x, free.size.y / island.size.y) * FIT_MARGIN, ZOOM_MIN, ZOOM_MAX)
	var target := island.get_center() - (free.get_center() - vp / 2.0) / z
	if seconds <= 0.0:
		camera.zoom = Vector2(z, z)
		camera.position = target
		return
	_cam_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_cam_tween.tween_property(camera, "position", target, seconds)
	_cam_tween.tween_property(camera, "zoom", Vector2(z, z), seconds)


## Any manual pan or zoom takes over from a camera flight.
func _stop_flight() -> void:
	if _cam_tween != null and _cam_tween.is_valid():
		_cam_tween.kill()


func _on_minimap(world_pos: Vector2) -> void:
	_stop_flight()
	camera.position = world_pos
	_update_viewing()


## Which island the view is over: north of the channel's middle is the enemy's.
func _update_viewing() -> void:
	var mid: float = (own_board.position.y + enemy_board.position.y) / 2.0
	viewing = 1 if camera.position.y < mid else 0


func _cancel() -> void:
	tool = ""
	selected = Vector2i(-1, -1)
	_refresh()


func _click(side: int, hex: int) -> void:
	match ui:
		Ui.SETUP:
			if side == 0:
				_setup_click(hex)
		Ui.BUILD:
			if side == 0 and tool != "":
				var e: String = m.build_action(MatchState.PLAYER, {"action": "build", "type": tool, "hex": hex})
				if e == "":
					hud.add_log("Built %s." % Pieces.display_name(tool))
					if m.sides[0].money < data.cost(tool):
						tool = ""
				else:
					_rules_error(e)
			else:
				selected = Vector2i(side, hex)
		Ui.TARGETING:
			if side == 1:
				_target_click(hex)
			else:
				var b = m.sides[0].building_at(hex)
				if b != null and data.role(b.type) == "launcher":
					if m.sides[0].weapon_active(b):
						active_launcher = b.hex
					else:
						hud.show_notice(Hud.NOTICE_SILO)
				selected = Vector2i(side, hex)
		_:
			selected = Vector2i(side, hex)
	_refresh()


## A rules error from a player action: the common ones get a notice that
## says what to do; anything else goes to the log.
func _rules_error(e: String) -> void:
	match e:
		"Not enough money":
			hud.show_notice(Hud.NOTICE_MONEY)
		"Not enough fuel":
			hud.show_notice(Hud.NOTICE_FUEL)
		"Launcher is out of action":
			hud.show_notice(Hud.NOTICE_SILO)
		_:
			hud.add_log("[color=salmon]%s[/color]" % e)


func _setup_click(hex: int) -> void:
	var existing = setup_trial.building_at(hex)
	if existing != null:
		_setup_remove(hex)
		return
	var e: String = setup_trial.can_place_base_like(hex, data)
	if e != "":
		hud.add_log("[color=salmon]%s[/color]" % e)
		return
	if setup_mode == "base":
		if setup_trial.bases_alive(data) >= data.integer("bases", "per_side"):
			hud.add_log("All three bases are placed. Click one to move it.")
			return
		setup_trial._add_building("base", hex, data, 0)
		setup_history.append(hex)
	else:
		var err: String = setup_trial.can_build("decoy", hex, data, m.settings)
		if err != "":
			hud.add_log("[color=salmon]%s[/color]" % err)
			return
		setup_trial.money -= data.cost("decoy")
		setup_trial._add_building("decoy", hex, data, 0)
		setup_history.append(hex)


func _setup_remove(hex: int) -> void:
	var existing = setup_trial.building_at(hex)
	if existing == null:
		return
	if existing.type == "decoy":
		setup_trial.money += data.cost("decoy")
	setup_trial.remove_building(hex, data)
	setup_history.erase(hex)


## Takes back the last base or decoy placed.
func _setup_undo() -> void:
	if setup_history.is_empty():
		return
	_setup_remove(int(setup_history.back()))
	_refresh()


func _target_click(hex: int) -> void:
	if active_launcher < 0:
		hud.add_log("No launcher free. Undo an order or end with Attack.")
		return
	var new_orders := orders.filter(func(o): return o["launcher"] != active_launcher)
	new_orders.append({"launcher": active_launcher, "missile": _missile_for(active_launcher), "target": hex})
	var e: String = m.set_launch_orders(MatchState.PLAYER, new_orders)
	if e != "":
		_rules_error(e)
		return
	orders = new_orders
	active_launcher = _next_free_launcher()


func _undo() -> void:
	if orders.is_empty():
		return
	var last: Dictionary = orders.pop_back()
	m.set_launch_orders(MatchState.PLAYER, orders)
	active_launcher = int(last["launcher"])
	_refresh()


func _missile_for(launcher_hex: int) -> String:
	if missile_choice.has(launcher_hex):
		return missile_choice[launcher_hex]
	var b = m.sides[0].building_at(launcher_hex)
	for mt in data.building(b.type)["missiles"]:
		if m.sides[0].missile_unlocked(mt, data):
			return mt
	return ""


func _cycle_missile(launcher_hex: int) -> void:
	var b = m.sides[0].building_at(launcher_hex)
	var options: Array = data.building(b.type)["missiles"].filter(func(mt): return m.sides[0].missile_unlocked(mt, data))
	var cur := _missile_for(launcher_hex)
	var next: String = options[(options.find(cur) + 1) % options.size()]
	missile_choice[launcher_hex] = next
	for o in orders:
		if o["launcher"] == launcher_hex:
			o["missile"] = next
	if m.set_launch_orders(MatchState.PLAYER, orders) != "":
		missile_choice[launcher_hex] = cur
		for o in orders:
			if o["launcher"] == launcher_hex:
				o["missile"] = cur
		hud.show_notice(Hud.NOTICE_FUEL)
	active_launcher = launcher_hex
	_refresh()


func _next_free_launcher() -> int:
	var used := {}
	for o in orders:
		used[o["launcher"]] = true
	for b in m.sides[0].of_role(data, "launcher"):
		if m.sides[0].weapon_active(b) and not used.has(b.hex):
			return b.hex
	return -1


func _fuel_planned() -> int:
	return m.sides[0].launch_fuel(orders, data)


# --- Refresh ---------------------------------------------------------------

const LEVEL_NAMES := ["base level", "middle level", "top level"]


func _own_state():
	return setup_trial if ui == Ui.SETUP and setup_trial != null else m.sides[0]


func _refresh() -> void:
	var own_state = _own_state()
	if ui != Ui.PLAYOUT:
		own_board.set_tiles(BoardView.own_tiles(own_state, data, m.knowledge[1], m.bombed[0]))
		enemy_board.set_tiles(_enemy_tiles())
	own_board.selected = selected.y if selected.x == 0 else -1
	enemy_board.selected = selected.y if selected.x == 1 else -1
	if ui == Ui.TARGETING and active_launcher >= 0:
		own_board.selected = active_launcher
	enemy_board.markers = {}
	for o in orders:
		enemy_board.markers[o["target"]] = Color(1, 0.25, 0.2)
	_update_placement_hints(own_state)
	_update_ranges(own_state)
	hud.minimap.queue_redraw()
	var next_income: Dictionary = Earnings.project(own_state, data, m.round_number)["income"]
	hud.set_resources(own_state.money, own_state.fuel,
		own_state.compute_income(data)["research"] if own_state.count_role(data, "lab") > 0 else 0,
		int(next_income["money"]) if next_income.has("money") else -1)
	_build_toolbar(own_state)
	_build_strip(own_state)
	if hud.earnings_visible():
		_update_earnings()
	if hud.research_panel.visible:
		hud.research_panel.show_state(m.sides[0], data, ui == Ui.BUILD)
	_update_tips()
	_update_info()
	own_board.queue_redraw()
	enemy_board.queue_redraw()


## The opposing space as we know it, or as it really is with the debug
## fog tool on.
func _enemy_tiles() -> Array:
	if debug_no_fog:
		return BoardView.own_tiles(m.sides[1], data)
	return BoardView.enemy_tiles(m.knowledge[0], m.sides[1].island.grid, m.round_number)


# --- Debug tools (the ` key) -----------------------------------------------

func _debug_add_money() -> void:
	var amount := int(data.settings["debug_money"])
	m.sides[0].money += amount
	if setup_trial != null:
		setup_trial.money += amount
	hud.add_log("[color=gray]Debug: +%d money.[/color]" % amount)
	_refresh()


func _debug_toggle_fog(on: bool) -> void:
	debug_no_fog = on
	hud.add_log("[color=gray]Debug: fog of war %s.[/color]" % ("cleared" if on else "restored"))
	if ui == Ui.PLAYOUT:
		enemy_board.set_tiles(_enemy_tiles())
	_refresh()


func _update_placement_hints(st) -> void:
	var ok := {}
	if ui == Ui.SETUP:
		for h in st.island.land_hexes():
			if st.can_place_base_like(h, data) == "":
				ok[h] = true
	elif ui == Ui.BUILD and tool != "":
		for h in st.island.land_hexes():
			if st.can_build(tool, h, data, m.settings) == "":
				ok[h] = true
	own_board.placement_ok = ok


func _update_ranges(st) -> void:
	own_board.range_rings = []
	if selected.x != 0 or ui == Ui.SETUP:
		return
	var b = st.building_at(selected.y)
	if b == null:
		return
	var g = st.island.grid
	match data.role(b.type):
		"anti_air":
			own_board.range_rings = [{"hexes": g.within(b.hex, int(data.section("anti_air")["radius"])), "color": Color(0.4, 1.0, 0.5, 0.6)}]
		"radar":
			if not st.out_for_repair(b, data):
				own_board.range_rings = [{"hexes": g.within(b.hex, st.radar_range(b, data)), "color": Color(0.8, 0.5, 1.0, 0.7)}]


func _building_tooltip(type: String) -> String:
	var lines: Array = [Pieces.display_name(type), Pieces.BUILDING_TEXT.get(type, "")]
	var def: Dictionary = data.building(type)
	lines.append("Cost %d" % data.cost(type))
	if def.has("hp"):
		lines.append("%d HP" % int(def["hp"]))
	elif def.has("hits_to_destroy"):
		lines.append("Destroyed by %d hits" % int(def["hits_to_destroy"]))
	if def.has("requires"):
		lines.append("Needs research: %s" % Pieces.research_name(String(def["requires"])))
	return "\n".join(lines)


func _build_toolbar(st) -> void:
	hud.clear_tools()
	match ui:
		Ui.SETUP:
			var placed: int = st.bases_alive(data)
			var per_side: int = data.integer("bases", "per_side")
			var decoys: int = st.count_role(data, "decoy")
			var max_decoys := int(m.settings["decoys_per_side"])
			hud.add_label("Place your bases on your island. Bases and decoys may not touch each other.", true)
			var bases_full := placed >= per_side
			var decoys_full := decoys >= max_decoys
			# A full piece greys out; the mode moves to the other one if it can.
			if setup_mode == "base" and bases_full and not decoys_full:
				setup_mode = "decoy"
			elif setup_mode == "decoy" and decoys_full and not bases_full:
				setup_mode = "base"
			hud.add_piece_button("base", "Base", "%d/%d" % [placed, per_side], "All placed" if bases_full else "Free",
				func(): setup_mode = "base"; _refresh(), bases_full, setup_mode == "base" and not bases_full, _building_tooltip("base"))
			hud.add_piece_button("decoy", "Decoy (optional)", "%d/%d" % [decoys, max_decoys], "%d money" % data.cost("decoy"),
				func(): setup_mode = "decoy"; _refresh(), decoys_full, setup_mode == "decoy" and not decoys_full, _building_tooltip("decoy"))
			hud.add_label("Click a placed piece to remove it.", true)
			hud.add_spacer()
			hud.add_tool_button("Undo", _setup_undo, setup_history.is_empty(), false, "Take back the last piece placed", "undo")
			hud.add_tool_button("Start", _start_setup_game, placed != per_side, false,
				"Begin round 1" if placed == per_side else "Place all %d bases first" % per_side, "start")
		Ui.BUILD:
			for type in data.building_types():
				var def: Dictionary = data.building(type)
				if not bool(def.get("buildable", true)):
					continue
				var unlocked: bool = st.building_unlocked(type, data)
				var note := ""
				var at_limit := false
				if not unlocked:
					note = "Research %s first" % Pieces.research_name(String(def.get("requires", "")))
				elif type == "decoy" and st.count_role(data, "decoy") >= int(m.settings["decoys_per_side"]):
					note = "Limit reached"
					at_limit = true
				elif st.money < data.cost(type):
					note = "Not enough money"
				var t: String = type
				var broke: bool = unlocked and not at_limit and st.money < data.cost(type)
				var pick := func(): tool = t; selected = Vector2i(-1, -1); _refresh()
				hud.add_piece_button(type, Pieces.display_name(type), str(data.cost(type)), note,
					(func(): hud.show_notice(Hud.NOTICE_MONEY)) if broke else pick,
					not unlocked or at_limit, tool == type, _building_tooltip(type), broke)
			hud.add_label("Select a building to repair it. Select a lab, or click a beaker on the right, for research.", true)
			hud.add_spacer()
			hud.add_tool_button("Done", _end_build, false, false, "End the build and repair phase now")
		Ui.TARGETING:
			hud.add_fuel_planner(st.fuel, _fuel_planned())
			hud.add_label("Weapons")
			var launchers: Array = st.of_role(data, "launcher")
			if launchers.is_empty():
				hud.add_label("No launchers. Build one in the build and repair phase.", true)
			for b in launchers:
				var name := Pieces.display_name(b.type)
				var hx: int = b.hex
				if not st.weapon_active(b):
					hud.add_piece_button(b.type, name, "", "Under repair" if b.repairing else "Out of action",
						func(): hud.show_notice(Hud.NOTICE_SILO), false, false, "Repair it in the build and repair phase.", true)
					continue
				var mt := _missile_for(b.hex)
				var aimed := false
				for o in orders:
					if o["launcher"] == b.hex:
						aimed = true
				var note: String = Pieces.MISSILE_NAMES.get(mt, mt) + ("  · aimed" if aimed else "")
				hud.add_piece_button(b.type, name, "%d fuel" % int(data.missile(mt)["fuel"]), note,
					func(): active_launcher = hx; _refresh(), false, active_launcher == b.hex,
					"Select this launcher, then click an enemy hex to aim it.")
				var options: Array = data.building(b.type)["missiles"].filter(func(x): return st.missile_unlocked(x, data))
				if options.size() > 1:
					hud.add_tool_button("Switch missile", func(): _cycle_missile(hx), false, false,
						"Change what this launcher fires")
			hud.add_spacer()
			hud.add_tool_button("Undo", _undo, orders.is_empty(), false, "Take back the last order. Free.", "undo")
			hud.add_tool_button("Attack", _attack, false, false, "Launch the orders placed and end targeting")
		Ui.PLAYOUT:
			hud.add_label("Missiles in flight.", true)


## The right-hand strip: a beaker per research project, then a button per
## base. Destroyed bases stay as grey buttons.
func _build_strip(st) -> void:
	var items: Array = []
	var labs: Array = st.of_role(data, "lab")
	var projects: Array = st.projects.duplicate()
	projects.sort_custom(func(a, b): return int(a["order"]) < int(b["order"]))
	for p in projects:
		var item := String(p["item"])
		var need := int(data.research_item(item)["points"])
		var left := Earnings.rounds_left(st, data, item)
		var details := "%s: %d / %d points, %s" % [Pieces.research_name(item), int(p["progress"]), need,
			"stalled" if left < 0 else "about %d round%s left" % [left, "" if left == 1 else "s"]]
		if int(p["lab_id"]) == -1:
			details += " (its lab was destroyed)"
		var lab_id: int = int(p["lab_id"]) if int(p["lab_id"]) != -1 else (labs[0].id if not labs.is_empty() else -1)
		items.append({"kind": "beaker", "fraction": float(p["progress"]) / need, "details": details,
			"action": func(): _open_research(lab_id), "enabled": ui == Ui.BUILD and lab_id != -1})
	var per_side: int = data.integer("bases", "per_side")
	var max_hits := float(data.building("base")["hits_to_destroy"])
	var bases: Array = st.of_role(data, "base")
	for i in per_side:
		if i < bases.size():
			var b = bases[i]
			var left := max_hits - float(b.hits)
			var hx: int = b.hex
			items.append({"kind": "base", "hits_left": left, "hits_max": max_hits,
				"details": "Base %d: %s of %d hits left" % [i + 1, _fmt(left), int(max_hits)],
				"action": func(): _show_own_hex(hx), "enabled": true})
		elif ui != Ui.SETUP:
			items.append({"kind": "base", "hits_left": 0.0, "hits_max": max_hits,
				"details": "Base %d: destroyed" % (i + 1), "enabled": false})
	hud.set_strip(items)


func _show_own_hex(hex: int) -> void:
	camera.position = own_board.position + own_board.tile_center(hex)
	_update_viewing()
	selected = Vector2i(0, hex)
	_refresh()


func _open_research(lab_id: int) -> void:
	if ui != Ui.BUILD:
		return
	hud.research_panel.open_lab(m.sides[0], data, lab_id, true)


func _start_research(lab_id: int, item: String) -> void:
	if ui != Ui.BUILD:
		return
	var e: String = m.build_action(MatchState.PLAYER, {"action": "research", "lab": lab_id, "item": item})
	if e != "":
		hud.add_log("[color=salmon]%s[/color]" % e)
	else:
		hud.add_log("Research started: %s." % Pieces.research_name(item))
	_refresh()


func _update_earnings() -> void:
	var p: Dictionary = Earnings.project(_own_state(), data, m.round_number)
	hud.set_earnings(p["lines"], int(p["round"]))


# --- Tips ------------------------------------------------------------------

func _tip_context() -> Dictionary:
	var st = m.sides[0]
	var phase := ""
	match ui:
		Ui.SETUP: phase = "setup"
		Ui.BUILD: phase = "build"
		Ui.TARGETING: phase = "targeting"
	var seen := false
	for e in m.knowledge[0].values():
		if e["building"] != null and String(e["building"]["type"]) == "suspected_base":
			seen = true
			break
	var damaged := false
	for b in st.buildings_sorted():
		if st.needs_repair(b, data):
			damaged = true
			break
	var need_fuel := 0
	for b in st.of_role(data, "launcher"):
		if st.weapon_active(b):
			var mt := _missile_for(b.hex)
			if mt != "":
				need_fuel += int(data.missile(mt)["fuel"])
	return {
		"phase": phase,
		"clock_on": clock_running,
		"has_launcher": st.count_role(data, "launcher") > 0,
		"has_anti_air": st.count_role(data, "anti_air") > 0,
		"radar_started": st.is_unlocked("radar") or st.project_for_item("radar") != null,
		"suspected_base_seen": seen,
		"own_damaged": damaged,
		"fuel_short": need_fuel > st.fuel,
	}


func _update_tips() -> void:
	if not bool(prefs["show_tips"]) or ui in [Ui.PLAYOUT, Ui.COIN, Ui.OVER]:
		hud.show_tip(null)
		return
	var r: Dictionary = Tips.update(tips, _tip_context(), prefs["tips_done"], current_tip, tips_snoozed)
	current_tip = r["current"]
	if r["done"].size() != prefs["tips_done"].size():
		prefs["tips_done"] = r["done"]
		_save_prefs()
	var shown = current_tip
	if shown != null:
		shown = shown.duplicate()
		shown["text"] = String(shown["text"]).format({"build_clock": int(prefs["build_clock_seconds"])})
	hud.show_tip(shown)


## A tip marked "pause" holds the phase clock (and the board) until it is
## dismissed.
func _tip_holds_clock() -> bool:
	return current_tip != null and bool(current_tip.get("pause", false)) and hud.tip_showing() == String(current_tip["id"])


func _on_tip_dismissed(id: String, forever: bool) -> void:
	if id != "":
		if forever and not prefs["tips_done"].has(id):
			prefs["tips_done"].append(id)
			_save_prefs()
		elif not forever:
			tips_snoozed.append(id)
	current_tip = null
	_update_tips()


func _on_settings_changed(s: Dictionary) -> void:
	prefs = s
	_save_prefs()
	_apply_grid()
	current_tip = null
	_refresh()


## The "Show grid" option: every hex outlined, or only coasts and height
## changes.
func _apply_grid() -> void:
	var on := bool(prefs["show_grid"])
	for v in [own_board, enemy_board, ocean]:
		v.show_grid = on
		v.queue_redraw()


func _save_prefs() -> void:
	UserSettings.save_settings(prefs, prefs_path)
	hud.esc_menu.setup(data.settings, prefs)


# --- Info box --------------------------------------------------------------

func _level_text(level: int) -> String:
	return "Land, %s" % LEVEL_NAMES[clampi(level, 0, LEVEL_NAMES.size() - 1)]


func _update_info() -> void:
	var target := selected if selected.y >= 0 else hovered
	hud.clear_info_actions()
	_update_hover_text()
	if target.y < 0:
		hud.set_info("")
		return
	if target.x == 0:
		var st = _own_state()
		var isl = st.island
		var lines: Array = []
		lines.append(_level_text(isl.level[target.y]) if isl.is_land(target.y) else "Sea")
		lines.append_array(_enemy_intel_lines(target.y))
		var b = st.building_at(target.y)
		if b != null:
			lines.push_front("[b]%s[/b]" % Pieces.display_name(b.type))
			if data.is_base_like(b.type):
				var max_hits := float(data.building(b.type)["hits_to_destroy"])
				lines.append("Hits taken: %s of %s" % [_fmt(b.hits), _fmt(max_hits)])
			else:
				lines.append("HP %d / %d" % [b.hp, data.max_hp(b.type)])
				if b.repairing:
					lines.append("[color=orange]Under repair: out of action this round, back next round[/color]")
				elif b.disabled:
					lines.append("[color=salmon]Out of action until repaired[/color]")
				elif st.is_half_strength(b, data):
					lines.append("[color=orange]Half strength until repaired[/color]")
				lines.append_array(_building_detail_lines(st, b))
			if ui == Ui.BUILD and target == selected:
				_info_actions_for(st, b)
		hud.set_info("\n".join(lines))
	else:
		var e = m.knowledge[0].get(target.y)
		if e == null:
			hud.set_info("[b]Unexplored[/b]\nUnder fog. Nothing is known here.")
			return
		var lines: Array = [_level_text(int(e["level"])) if e["land"] else "Sea",
			"Last seen in round %d%s" % [e["seen_round"], "" if int(e["seen_round"]) == m.round_number else " (may have changed)"]]
		var b = e["building"]
		if b != null:
			if b["type"] == "suspected_base":
				lines.push_front("[b]Potential base: %s hits[/b]" % _fmt(float(b["hits"])))
			else:
				lines.push_front("[b]%s[/b]" % Pieces.display_name(String(b["type"])))
				if b["disabled"]:
					lines.append("Out of action")
				elif b["damaged"]:
					lines.append("Damaged")
		elif String(e["destroyed"]) != "":
			lines.push_front("[b]Destroyed %s[/b]" % Pieces.display_name(String(e["destroyed"])))
		hud.set_info("\n".join(lines))


## What a building does right now, for the info box.
func _building_detail_lines(st, b) -> Array:
	var out: Array = []
	var produces: Dictionary = data.building(b.type).get("produces", {})
	for res in produces:
		out.append("Makes %d %s a round" % [st.output_of(b, int(produces[res]), data), res])
	match data.role(b.type):
		"anti_air":
			out.append("Covers %d hexes around it, %d missiles a round" % [int(data.section("anti_air")["radius"]), st.anti_air_engagements(data)])
		"radar":
			out.append("Off while under repair" if st.out_for_repair(b, data) else "Range %d hexes" % st.radar_range(b, data))
		"launcher":
			var names: Array = []
			for mt in data.building(b.type)["missiles"]:
				if st.missile_unlocked(mt, data):
					names.append(Pieces.MISSILE_NAMES.get(mt, mt))
			out.append("Fires: %s" % ", ".join(names))
		"lab":
			var p = st.project_for_lab(b.id)
			if p != null:
				out.append("Researching %s" % Pieces.research_name(String(p["item"])))
			else:
				var oldest = st.oldest_project()
				out.append("Helping %s" % Pieces.research_name(String(oldest["item"])) if oldest != null else "Idle: choose research")
	return out


func _info_actions_for(st, b) -> void:
	if st.needs_repair(b, data):
		var cost: int = st.repair_cost(b.type, data)
		var hx: int = b.hex
		var type: String = b.type
		var do_repair := func():
			var e: String = m.build_action(MatchState.PLAYER, {"action": "repair", "hex": hx})
			if e != "":
				hud.add_log("[color=salmon]%s[/color]" % e)
			else:
				audio.play(REPAIR_SOUND)
				hud.add_log("Repairing %s." % Pieces.display_name(type))
			_refresh()
		var err: String = st.can_repair(b.hex, data)
		hud.add_info_action("Repair (%d)" % cost, do_repair, err != "", err)
	if data.role(b.type) == "lab":
		var lab_id: int = b.id
		hud.add_info_action("Research...", func(): _open_research(lab_id), false, "Open the research panel for this lab")


## What the enemy knows about one of our hexes: missiles that landed on it
## and when the enemy last saw it, so the player can tell whether that
## knowledge is current.
func _enemy_intel_lines(hex: int) -> Array:
	var out: Array = []
	var hit = m.bombed[0].get(hex)
	if hit != null:
		var n := int(hit["count"])
		out.append("[color=#%s]Hit %d time%s, last in round %d[/color]" % [BoardView.bombed_color(n).to_html(false),
			n, "" if n == 1 else "s", int(hit["last_round"])])
	var seen = m.knowledge[1].get(hex)
	if seen != null:
		var r := int(seen["seen_round"])
		var b = m.sides[0].building_at(hex)
		var current := true
		if b != null and int(b.built_round) > r:
			current = false
		out.append("Enemy last saw this hex in round %d%s" % [r, "" if current else ": it hasn't seen what's here now"])
	return out


## Hover text beside the mouse for potential enemy bases (section 5), and
## for our own hexes the enemy has hit.
func _update_hover_text() -> void:
	var text := ""
	if hovered.x == 0 and hovered.y >= 0 and ui != Ui.SETUP:
		var hit = m.bombed[0].get(hovered.y)
		if hit != null:
			var n := int(hit["count"])
			text = "Hit %d time%s, last in round %d" % [n, "" if n == 1 else "s", int(hit["last_round"])]
			var seen = m.knowledge[1].get(hovered.y)
			if seen != null:
				text += "
Enemy last saw it in round %d" % int(seen["seen_round"])
	if hovered.x == 1 and hovered.y >= 0:
		var e = m.knowledge[0].get(hovered.y)
		if e != null and e["building"] != null and String(e["building"]["type"]) == "suspected_base":
			text = "Potential base: %s hits" % _fmt(float(e["building"]["hits"]))
	hud.set_hover_text(text, get_viewport().get_mouse_position())


static func _fmt(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, roundf(v)) else "%.1f" % v


# --- Playout ---------------------------------------------------------------

func _run_playout() -> void:
	var pre_own: Array = BoardView.own_tiles(m.sides[0], data, m.knowledge[1], m.bombed[0])
	var pre_enemy: Array = _enemy_tiles()
	own_board.set_tiles(pre_own)
	enemy_board.set_tiles(pre_enemy)
	enemy_board.markers = {}
	var events: Array = m.resolve_playout()
	# What our strikes will have revealed, applied hex by hex as they land.
	var post_enemy: Array = _enemy_tiles()
	var by_id := {}
	for ev in events:
		if ev.has("id"):
			if not by_id.has(ev["id"]):
				by_id[ev["id"]] = {}
			by_id[ev["id"]][ev["type"]] = ev
	var launches := [events.filter(func(e): return e["type"] == "launch" and e["side"] == 0),
		events.filter(func(e): return e["type"] == "launch" and e["side"] == 1)]

	# Our missiles launch. The enemy's launches are not shown: its missiles
	# are only seen arriving, with the view staying on our island.
	_fly_to(0, 0.6)
	await _wait(0.7)
	for k in launches[0].size():
		_rise(own_board, int(launches[0][k]["launcher"]), Color(1, 0.9, 0.5), k * 0.15)
	await _wait(0.9 + launches[0].size() * 0.15)

	# Enemy strikes land on our island, then damage shows.
	if not launches[1].is_empty():
		# The enemy attack is announced in the log, and the alarm light
		# starts with it.
		hud.set_alarm(true)
		hud.add_log("%d enemy missile%s incoming!" % [launches[1].size(), "" if launches[1].size() == 1 else "s"])
		await _wait(0.3)
		for k in launches[1].size():
			_strike(own_board, m.sides[0].island, by_id[launches[1][k]["id"]], int(launches[1][k]["target"]), Color(1, 0.4, 0.4), k * 0.35)
		await _wait(1.4 + launches[1].size() * 0.35)
	own_board.set_tiles(BoardView.own_tiles(m.sides[0], data, m.knowledge[1], m.bombed[0]))
	_mark_fired(launches[0].map(func(e): return int(e["launcher"])))
	for ev in events:
		if ev.get("side", -1) == 0 and ev["type"] in ["destroyed", "disabled", "damaged", "decoy_revealed"]:
			_log_event(ev)

	# Our strikes land on the enemy island.
	if not launches[0].is_empty():
		_fly_to(1, 0.6)
		await _wait(0.7)
		for k in launches[0].size():
			_strike(enemy_board, null, by_id[launches[0][k]["id"]], int(launches[0][k]["target"]), Color(1, 0.9, 0.5), k * 0.35, post_enemy)
		await _wait(1.4 + launches[0].size() * 0.35)
	enemy_board.set_tiles(_enemy_tiles())
	for ev in events:
		if ev.get("side", -1) == 1 and ev["type"] in ["destroyed", "disabled", "damaged", "decoy_revealed"]:
			_log_event(ev)
		elif ev["type"] in ["game_over", "coin_flip_needed"]:
			_log_event(ev)
	await _wait(0.8)
	effects.clear()
	ui = Ui.BUILD   # placeholder until the next phase sets itself
	_after_playout()


## Launchers that fired this round show their empty sprite until the next
## round rebuilds the tiles.
func _mark_fired(hexes: Array) -> void:
	for h in hexes:
		var b = own_board.tiles[h].get("building")
		if b != null:
			b["empty"] = true
	own_board.queue_redraw()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, false).timeout


func _rise(board, hex: int, color: Color, delay: float, offset: Vector2 = Vector2.ZERO) -> void:
	await _wait(delay)
	if board == own_board:
		_mark_fired([hex])
	var ms = effects.add_missile(board.position + board.tile_center(hex) + offset, 0.0, color)
	var t := create_tween()
	t.tween_property(ms, "alt", 700.0, 0.8).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	await t.finished
	effects.remove_missile(ms)


## One incoming missile: falls toward its aimed hex, may be engaged by
## anti-air, may seek, then explodes. `isl` is the defender's island when we
## can show anti-air positions (our own); null when it is the enemy's.
## `reveal_tiles`, when given, holds the after-playout tiles for the enemy
## space; the hexes this impact reveals switch to them as it lands. On our
## own island the revealed hexes are marked as seen by the enemy.
func _strike(board, isl, info: Dictionary, target: int, color: Color, delay: float, reveal_tiles: Array = []) -> void:
	await _wait(delay)
	var ground: Vector2 = board.position + board.tile_center(target)
	var ms = effects.add_missile(ground, 700.0, color)
	var t := create_tween()
	t.tween_property(ms, "alt", 120.0, 0.6).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	await t.finished
	if info.has("engage"):
		var eng: Dictionary = info["engage"]
		if isl != null:
			effects.tracer(board.position + board.tile_center(int(eng["anti_air"])) - Vector2(0, 20), ground - Vector2(0, ms.alt))
		else:
			effects.tracer(ground + Vector2(-60, 30), ground - Vector2(0, ms.alt))
		await _wait(0.15)
		if eng["hit"]:
			effects.burst(ground - Vector2(0, ms.alt))
			effects.remove_missile(ms)
			return
	t = create_tween()
	t.tween_property(ms, "alt", 0.0, 0.2).set_ease(Tween.EASE_IN)
	await t.finished
	if info.has("seek"):
		var dest: Vector2 = board.position + board.tile_center(int(info["seek"]["to"]))
		ms.alt = 12.0
		t = create_tween()
		t.tween_property(ms, "ground", dest, 0.3)
		await t.finished
		ground = dest
	effects.remove_missile(ms)
	var imp: Dictionary = info.get("impact", {})
	var is_scout: bool = String(imp.get("missile", "")) == "scouting"
	effects.explosion(ground, 14.0 if is_scout else 26.0, Color(0.6, 0.8, 1.0) if is_scout else Color(1.0, 0.55, 0.15))
	for h in imp.get("revealed", []):
		if not reveal_tiles.is_empty():
			board.tiles[int(h)] = reveal_tiles[int(h)]
		else:
			board.tiles[int(h)]["enemy_seen"] = true
	if reveal_tiles.is_empty() and imp.has("hex"):
		var ih := int(imp["hex"])
		board.tiles[ih]["bombed"] = int(board.tiles[ih].get("bombed", 0)) + 1
	board.queue_redraw()
	for d in imp.get("damaged", []):
		# Our own buildings switch to their damaged look as they are hit; the
		# enemy's already show it through reveal_tiles.
		if reveal_tiles.is_empty():
			var hb = board.tiles[int(d["hex"])].get("building")
			if hb != null:
				if d.has("damage"):
					hb["damaged"] = true
				else:
					hb["hits"] = float(hb.get("hits", 0.0)) + float(d["hits"])
		var p: Vector2 = board.position + board.tile_center(int(d["hex"]))
		if d.has("damage"):
			effects.float_text(p, "-%d" % int(d["damage"]), Color(1, 0.8, 0.6))
		else:
			effects.float_text(p, "+%s hit" % _fmt(float(d["hits"])), Color(1, 1, 1))


# --- Log -------------------------------------------------------------------

func _log_event(ev: Dictionary) -> void:
	var mine: bool = ev.get("side", -1) == MatchState.PLAYER
	match String(ev["type"]):
		"round_start":
			hud.add_log("[b]Round %d[/b]" % m.round_number)
		"income":
			if mine:
				var inc: Dictionary = ev["income"]
				hud.add_log("Income: +%d money, +%d fuel, +%d research." % [inc["money"], inc["fuel"], inc["research"]])
		"research_done":
			if mine:
				hud.add_log("[color=lightgreen]Research complete: %s.[/color]" % String(ev["item"]).capitalize())
		"destroyed":
			if mine:
				hud.add_log("[color=salmon]Our %s was destroyed.[/color]" % Pieces.display_name(String(ev["building"])))
			else:
				var shown: String = "base" if ev["building"] == "base" else Pieces.display_name(String(ev["building"]))
				hud.add_log("[color=lightgreen]Enemy %s destroyed.[/color]" % shown)
		"disabled":
			hud.add_log(("Our %s is out of action." if mine else "Enemy %s knocked out.") % Pieces.display_name(String(ev["building"])))
		"damaged":
			hud.add_log(("Our %s was damaged." if mine else "Enemy %s damaged.") % Pieces.display_name(String(ev["building"])))
		"decoy_revealed":
			hud.add_log("Our decoy has been exposed." if mine else "[color=lightgreen]That base was a decoy.[/color]")
		"coin_flip_needed":
			hud.add_log("Both sides lost their last base. Money is equal: coin flip.")
		"coin_flip":
			hud.add_log("The enemy called %s. The coin shows %s." % [ev["call"], ev["flip"]])
		"game_over":
			hud.add_log("[b]%s[/b]" % ("Victory." if ev["winner"] == MatchState.PLAYER else "Defeat."))
