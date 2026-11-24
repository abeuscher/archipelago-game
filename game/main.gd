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
const Palette = preload("res://game/palette.gd")
const Pieces = preload("res://game/pieces.gd")
const Audio = preload("res://game/audio.gd")
const BattleReport = preload("res://game/battle_report.gd")
const Hud = preload("res://game/hud.gd")
const UserSettings = preload("res://game/user_settings.gd")
const Tips = preload("res://game/tips.gd")
const Earnings = preload("res://game/earnings.gd")
const RulesText = preload("res://game/rules_text.gd")
const Levels = preload("res://rules/levels.gd")
const Campaign = preload("res://game/campaign.gd")
const SideState = preload("res://rules/side_state.gd")

const CHANNEL_ROWS := 4        ## rows of open sea between the two islands
const FLY_SECONDS := 0.9       ## camera move between islands at a phase change
const FIT_MARGIN := 0.92       ## share of the free screen an island fills when fitted
const ZOOM_MIN := 0.3
const ZOOM_MAX := 3.0
const PAN_SPEED := 700.0
const ZOOM_STEP := 1.25        ## per press of a zoom button
const ENEMY_TURN_PAUSE := 1.2  ## seconds on our island after the enemy's strikes, before ours
const ALARM_TURNS := 1.0       ## the siren turns this many times before the warning

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
var lines: Dictionary = {}           ## the characters' lines (dialogue.json "announcements")

var ui: int = Ui.SETUP
var viewing: int = 0
var rot: int = 0
var battle_report: Array = []   ## the last attack's summary, "label: n" lines, in the comms screen until the next attack
var clock_left: float = 0.0
var clock_running: bool = false
var tool: String = ""
var setup_mode: String = "base"
var setup_trial                     ## SideState copy used to preview setup
var setup_history: Array = []       ## hexes placed during setup, oldest first, for Undo
var orders: Array = []
var active_launcher: int = -1
var pending_drop: Dictionary = {}   ## transport aimed but no direction yet: {"launcher", "target"}
var missile_choice: Dictionary = {} ## launcher hex -> missile type
var selected: Vector2i = Vector2i(-1, -1)   ## (side, hex)
var hovered: Vector2i = Vector2i(-1, -1)
var _drag_from: Vector2
var _dragging: bool = false
var _drag_moved: float = 0.0
var ocean
var _cam_tween: Tween
var debug_no_fog: bool = false       ## debug tool: show the enemy island as it really is
var level: Dictionary = {}           ## this match's level (data/levels.json)
var unaimed_warned: bool = false   ## Ginger's "target your weapons" said this game (a new game reloads the scene)
var first_base_line_said: bool = false   ## the level's line for losing our first base, once
var enemy_stronghold_seen: bool = false   ## set when a missile gives the enemy's stronghold away


func _ready() -> void:
	level = Levels.level(Campaign.level)
	data = Levels.data_for(GameData.load_default(), Campaign.level)
	if has_meta("settings_path"):
		prefs_path = String(get_meta("settings_path"))
	prefs = UserSettings.load_settings(data.settings, prefs_path)
	tips = Tips.load_tips(data)
	lines = Tips.load_lines()
	seed_value = _seed_from_args()
	m = MatchState.create(data, seed_value, UserSettings.match_overrides(prefs))
	# The last win's award; the enemy gets the same, so it buys a head start
	# for the player's plans rather than an edge.
	m.sides[MatchState.PLAYER].money += Campaign.award_money
	m.sides[MatchState.ENEMY].money += Campaign.award_money
	enemy_ai = StrongAI.new(MatchState.ENEMY, data, seed_value)

	# Beyond the drawn sea hexes the screen is plain sea, so there is never
	# a black edge. Then the sea, the enemy island (north, further back),
	# then ours.
	RenderingServer.set_default_clear_color(Palette.SEA)
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
	hud.announcer.speak = audio.speak   # tips play their recorded line, if there is one
	hud.minimap.setup(own_board, enemy_board, ocean, camera)
	# The comms slider is the main volume, kept with the settings.
	Audio.set_master_volume(float(prefs["volume"]))
	hud.volume_slider.value = float(prefs["volume"])
	hud.volume_changed.connect(func(v: float, done: bool):
		Audio.set_master_volume(v)
		prefs["volume"] = v
		if done:
			_save_prefs())
	hud.minimap.view_requested.connect(_on_minimap)
	hud.choice_menu_closed.connect(_update_blasts)
	hud.rotate_requested.connect(_rotate)
	hud.zoom_requested.connect(func(dir: int): _zoom_at(ZOOM_STEP if dir > 0 else 1.0 / ZOOM_STEP, get_viewport_rect().size / 2.0))
	hud.debug_add_money.connect(_debug_add_money)
	hud.debug_toggle_fog.connect(_debug_toggle_fog)
	hud.debug_next_level.connect(_debug_next_level)
	hud.hex_anchor = _hex_anchor
	hud.earnings_requested.connect(_update_earnings)
	hud.tip_dismissed.connect(_on_tip_dismissed)
	hud.research_panel.start_requested.connect(_start_research)
	hud.research_panel.use_stored_requested.connect(_use_stored_research)
	hud.research_panel.closed.connect(_refresh)
	hud.esc_menu.setup(data.settings, prefs)
	_update_rules_text()
	hud.esc_menu.settings_changed.connect(_on_settings_changed)
	hud.esc_menu.quit_requested.connect(func(): get_tree().quit())

	var es: Dictionary = enemy_ai.choose_setup(m.view_for(MatchState.ENEMY))
	var e: String = m.setup_side(MatchState.ENEMY, es["bases"], es["decoys"])
	assert(e == "", "Enemy setup failed: " + e)
	hud.add_log("[b]%s[/b]. Seed %d." % [String(level.get("name", "")), seed_value])
	if Campaign.award_money > 0:
		hud.add_log("Command's award for your last victory: +%d money to start." % Campaign.award_money)
	_enter_setup()


func _seed_from_args() -> int:
	if has_meta("seed_override"):
		return int(get_meta("seed_override"))
	var args := OS.get_cmdline_user_args()
	var i := args.find("--seed")
	if i >= 0 and i + 1 < args.size():
		return int(args[i + 1])
	return int(Time.get_unix_time_from_system() * 1000.0) & 0x7FFFFFFF


## Both islands lie on one plane: ours at the origin, the enemy's straight
## north of it across a channel of CHANNEL_ROWS rows of sea in the base view.
## Rotating the view turns the whole plane about our island, so the enemy
## island swings round with it. Both centres sit on the shared hex lattice
## (see iso.gd), which a 60-degree turn maps onto itself, so the sea lines up
## with both in every view.
func _layout_boards() -> void:
	own_board.position = Vector2.ZERO
	# The gap is measured in the base view, where the enemy is due north.
	var steps_now: int = own_board.iso.rotation_step
	own_board.iso.rotation_step = 0
	enemy_board.iso.rotation_step = 0
	var own_top: float = -own_board.iso.plane_extent().position.y
	var enemy_bottom: float = enemy_board.iso.plane_extent().end.y
	own_board.iso.rotation_step = steps_now
	enemy_board.iso.rotation_step = steps_now
	var need := own_top + enemy_bottom + (CHANNEL_ROWS + 1) * Iso.ROW_H
	# Straight north on the lattice is axial (1, -2): two rows up per step.
	var steps := ceili(need / (2.0 * Iso.ROW_H))
	var offset := Vector2(0, -steps * 2.0 * Iso.ROW_H).rotated(rot * PI / 3.0)   # on the board plane
	enemy_board.position = Vector2(offset.x, offset.y * Iso.SQUASH)
	ocean.rebuild([own_board, enemy_board])


# --- Phases ----------------------------------------------------------------

func _enter_setup() -> void:
	ui = Ui.SETUP
	tips_snoozed = []
	setup_trial = m.sides[0].duplicate_state()
	setup_history = []
	setup_mode = "stronghold" if SideState.strongholds_per_side(data) > 0 else "base"
	hud.set_alarm(false)
	_reset_rotation()
	_fly_to(0, 0.0)
	hud.set_phase("Setup", 0)
	audio.start_ambient()
	audio.set_music("main")   # the main theme, in setup and build and repair
	_set_clock(0)
	var strongholds := SideState.strongholds_per_side(data)
	if strongholds > 0:
		hud.add_log("Place your stronghold and bases. Bases and decoys may not touch each other.")
	else:
		hud.add_log("Place your three bases. Bases and decoys may not touch each other.")
	var intro := String(level.get("intro", ""))
	if intro != "" and lines.has(intro):
		_say(intro)
	_refresh()


func _start_setup_game() -> void:
	var bases: Array = []
	var decoys: Array = []
	for b in setup_trial.buildings_sorted():
		if b.type == "stronghold":
			bases.push_front(b.hex)   # setup makes the first bases strongholds
		elif b.type == "base":
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
	# The character reports what came in (from round 2, when there is
	# income); the clock runs underneath. The log keeps the plain record
	# without flashing it. Last round's battle summary is listed in the comms
	# screen (and the log), not said.
	if not battle_report.is_empty():
		hud.add_log("Battle summary: " + "; ".join(battle_report) + ".", false)
	var income_said := ""
	for ev in events:
		if ev["type"] == "round_start":
			hud.add_log("[b]Round %d[/b]" % m.round_number, false)
		elif ev["type"] == "income" and ev.get("side", -1) == MatchState.PLAYER:
			var inc: Dictionary = ev["income"]
			var fill := {"n": m.round_number, "money": inc["money"], "fuel": inc["fuel"], "research": inc["research"]}
			income_said = _line_text("income").format(fill)
			hud.add_log("Income: +%d money, +%d fuel, +%d research." % [inc["money"], inc["fuel"], inc["research"]], false)
		else:
			_log_event(ev)
	if income_said != "":
		_say("income", income_said, false, true)   # the build clock runs while it is read
	if m.boats[MatchState.ENEMY].any(func(bt): return int(bt["lands_round"]) == m.round_number):
		_say("boat_spotted")
	# The enemy commits its build for the round from its own view.
	for a in enemy_ai.choose_build(m.view_for(MatchState.ENEMY)):
		m.build_action(MatchState.ENEMY, a)
	hud.set_alarm(false)
	ui = Ui.BUILD
	audio.set_music("main")
	tool = ""
	tips_snoozed = []
	orders = []   # last round's aim markers don't carry over
	selected = Vector2i(-1, -1)
	_reset_rotation()
	_fly_to(0)
	hud.set_phase("Build and repair", m.round_number)
	_set_clock(int(prefs["build_clock_seconds"]))
	_refresh()


func _end_build() -> void:
	if ui != Ui.BUILD:
		return
	m.end_build_phase()
	audio.stop_effect("countdown")   # Done pressed with the countdown running
	hud.research_panel.visible = false
	var eo: Array = enemy_ai.choose_targets(m.view_for(MatchState.ENEMY))
	if m.set_launch_orders(MatchState.ENEMY, eo) != "":
		m.set_launch_orders(MatchState.ENEMY, [])
	audio.set_music("very_fast")   # targeting has its own, faster theme
	if _next_free_launcher() < 0:
		# Nothing to fire: our attack turn is skipped.
		no_weapons_turn = true   # said when our strikes would have gone in
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
	pending_drop = {}
	selected = Vector2i(-1, -1)
	active_launcher = _next_free_launcher()
	_reset_rotation()
	_fly_to(1)
	hud.set_phase("Targeting", m.round_number)
	_set_clock(int(prefs["targeting_clock_seconds"]))
	_refresh()


## A map hex a tip points at, as a rect on screen: "damaged" is our first
## building waiting for repair, "targeted_launcher" the launcher the enemy
## keeps hitting, "suspected_base" an enemy potential base with hits on it. Empty when there is none, or it is off screen.
func _hex_anchor(what: String) -> Rect2:
	var board = null
	var hex := -1
	match what:
		"damaged":
			board = own_board
			for b in m.sides[0].buildings_sorted():
				if m.sides[0].needs_repair(b, data):
					hex = b.hex
					break
		"targeted_launcher":
			# The launcher the enemy keeps hitting: out of action, hit at
			# least twice (as the tip's condition), the most-hit first.
			board = own_board
			var most := 1
			for b in m.sides[0].of_role(data, "launcher"):
				var n := int(m.bombed[0].get(b.hex, {}).get("count", 0))
				if b.disabled and n >= 2 and n > most:
					most = n
					hex = b.hex
		"suspected_base":
			board = enemy_board
			for h in m.knowledge[0]:
				var kb = m.knowledge[0][h]["building"]
				if kb != null and String(kb["type"]) == "suspected_base" and float(kb["hits"]) > 0.0:
					hex = h
					break
	if board == null or hex < 0:
		return Rect2()
	var xf: Transform2D = board.get_global_transform_with_canvas()
	var c: Vector2 = xf * board.tile_center(hex)
	var half := Vector2(Iso.HEX_SIZE * 0.9, Iso.HEX_SIZE * 0.7) * camera.zoom.x
	var r := Rect2(c - half - Vector2(0, half.y * 0.6), half * 2.0 + Vector2(0, half.y * 0.6))
	return r if get_viewport_rect().intersects(r) else Rect2()


## The Done button. The first time it is pressed with nothing that can fire,
## a yes/no box asks whether to go on to the attack (once ever, kept with the
## finished tips). The clock running out goes on without asking.
func _done_pressed() -> void:
	var key := "no_weapons_confirm"
	if ui == Ui.BUILD and _next_free_launcher() < 0 and not prefs["tips_done"].has(key) and lines.has(key):
		prefs["tips_done"].append(key)
		_save_prefs()
		hud.confirm(_line_text(key), _end_build)
		return
	_end_build()


## The first time the build clock runs out, Ginger reminds the player to
## watch it (once ever, kept with the finished tips; only with tips on).
## Said as targeting starts, holding its clock. Not for the targeting clock.
func _build_timeout_tip() -> void:
	var key := "build_timeout"
	if prefs["tips_done"].has(key) or not bool(prefs["show_tips"]) or not lines.has(key):
		return
	prefs["tips_done"].append(key)
	_save_prefs()
	_say(key)


## The Attack button. Pressed with nothing aimed at all (and something
## that could fire), Ginger warns instead of attacking, once a game: after
## that, Attack goes ahead even with nothing aimed, so the player is helped
## once but not stopped. The clock holds while she talks; the clock running
## out attacks without asking.
func _attack_pressed() -> void:
	var warn := "attack_unaimed"
	if ui == Ui.TARGETING and orders.is_empty() and not unaimed_warned and _next_free_launcher(true) >= 0 and lines.has(warn):
		unaimed_warned = true
		_say(warn)
		return
	_attack()


var no_weapons_turn := false   ## we had nothing to fire this round: told after the enemy's strikes


func _attack() -> void:
	if ui != Ui.TARGETING:
		return
	_set_clock(0)
	audio.set_music("")   # the attack plays out with no music
	battle_report = []    # this attack's summary replaces it
	ui = Ui.PLAYOUT
	_reset_rotation()
	hud.set_phase("Playout", m.round_number)
	_refresh()
	_run_playout()


func _after_playout() -> void:
	if m.phase == MatchState.Phase.COIN_FLIP:
		ui = Ui.COIN
		hud.show_overlay("Coin flip", "Both sides lost their last base this round, with equal money.\nThe enemy calls %s." % String(m.coin["call"]).to_upper(),
			[["Flip the coin", _flip_coin]])
	elif m.is_over():
		_show_game_over()
	else:
		# The first sight of the enemy's stronghold: the Admiral's warning,
		# once a match.
		if enemy_stronghold_seen and lines.has("enemy_stronghold"):
			_say("enemy_stronghold")
			lines.erase("enemy_stronghold")
		enemy_stronghold_seen = false
		# The round's battle report, if anything happened; the next round's
		# clock waits for it.
		# The battle report waits for the next round's income: the Pilot
		# gives both together (see _start_round).
		_start_round()


func _flip_coin() -> void:
	for ev in m.resolve_coin_flip():
		_log_event(ev)
	_show_game_over()


func _show_game_over() -> void:
	ui = Ui.OVER
	var won: bool = m.winner == MatchState.PLAYER
	audio.stop_ambient()
	audio.set_music("")
	audio.effect("you_win" if won else "you_lose")
	var why := {"bases": "All three enemy bases destroyed." if won else "All three of your bases were destroyed.",
		"money": "Both sides fell together; %s more money." % ("you had" if won else "the enemy had"),
		"coin": "Coin: enemy called %s, it landed %s." % [m.coin.get("call", ""), m.coin.get("flip", "")]}
	var text := String(why.get(m.end_reason, ""))
	var buttons: Array = []
	if won and Campaign.has_next():
		var award := int(level.get("win_award_money", 0))
		if award > 0:
			text += "\nCommand awards you %d money toward your next battle." % award
		buttons.append(["On to %s" % String(Levels.level(Campaign.level + 1).get("name", "")), func():
			Campaign.advance()
			get_tree().reload_current_scene()])
	elif won:
		text += "\nThat was the last level for now."
		buttons.append(["Play it again", func(): get_tree().reload_current_scene()])
		buttons.append(["Back to %s" % String(Levels.level(1).get("name", "")), func():
			Campaign.restart()
			get_tree().reload_current_scene()])
	else:
		buttons.append(["Try again", func(): get_tree().reload_current_scene()])
	buttons.append(["Quit", func(): get_tree().quit()])
	hud.show_overlay("Island taken" if won else "Defeat", text, buttons, String(audio.sounds.get("end_videos", {}).get("victory" if won else "defeat", "")))
	_refresh()


# --- Clock -----------------------------------------------------------------

func _set_clock(seconds: int) -> void:
	clock_left = float(seconds)
	clock_running = seconds > int(data.settings["clock_off_value"])
	hud.set_timer(clock_left if clock_running else -1.0)


func _process(delta: float) -> void:
	var clock_ticking: bool = clock_running and not hud.overlay_visible() and not hud.confirm_visible() and not _tip_holds_clock()
	audio.pause_effect("countdown", not clock_ticking)   # the countdown holds when the clock does
	if clock_ticking:
		var warn := float(audio.sounds.get("countdown_seconds", 5))
		clock_left -= delta
		hud.set_timer(maxf(clock_left, 0.0))
		# The build clock running low: the fast theme.
		if ui == Ui.BUILD and clock_left < float(audio.sounds.get("theme", {}).get("fast_under_seconds", 20)):
			audio.set_music("fast")
		# The last seconds of the build clock count down out loud.
		if ui == Ui.BUILD and clock_left <= warn and clock_left + delta > warn:
			audio.effect("countdown")
		if clock_left <= 0.0:
			clock_running = false
			if ui == Ui.BUILD:
				_end_build()
				_build_timeout_tip()
			elif ui == Ui.TARGETING:
				_attack()   # orders placed so far are launched
	# The ambience swells as the view moves in and fades as it pulls out.
	audio.set_closeness(inverse_lerp(log(ZOOM_MIN), log(ZOOM_MAX), log(camera.zoom.x)))
	var pan := Vector2(Input.get_axis("ui_left", "ui_right"), Input.get_axis("ui_up", "ui_down"))
	if pan != Vector2.ZERO:
		_stop_flight()
		camera.position += pan * PAN_SPEED * delta / camera.zoom.x
		_update_viewing()


# --- Input -----------------------------------------------------------------

## A right-click over the toolbar or another panel puts the building tool
## down too (on the map, _unhandled_input does it, leaving right-drag panning
## alone).
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT \
			and ui == Ui.BUILD and tool != "" and not hud.choice_menu_open() \
			and get_viewport().gui_get_hovered_control() != null:
		_cancel()


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
					if not _unaim_at(_pick(get_global_mouse_position())):
						_cancel()
		elif mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			# No zooming under an open window: the wheel is for its scrolling.
			if not hud.modal_open():
				_zoom_at(1.12 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.12, mb.position)
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
			if ui == Ui.BUILD and tool != "":
				_update_ranges(_own_state())   # the reach preview follows the mouse
			if ui == Ui.TARGETING:
				_update_blasts()
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


## Every phase starts in the base view: our island at the bottom, the
## enemy's at the top.
func _reset_rotation() -> void:
	if rot == 0:
		return
	rot = 0
	own_board.set_rotation_step(0)
	enemy_board.set_rotation_step(0)
	_layout_boards()
	_focus(viewing)


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
	free.end = Vector2(vp.x - Hud.STRIP_W - 28, vp.y - Hud.BOTTOM_CLEAR - 8)
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


## Which island the view is over: whichever centre is nearer.
func _update_viewing() -> void:
	viewing = 1 if camera.position.distance_squared_to(enemy_board.position) < camera.position.distance_squared_to(own_board.position) else 0


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
			if side == 0 and tool != "" and m.sides[0].building_at(hex) == null:
				var e: String = m.build_action(MatchState.PLAYER, {"action": "build", "type": tool, "hex": hex})
				if e == "":
					hud.add_log("Built %s." % Pieces.display_name(tool))
					audio.built(tool)
					if m.sides[0].money < data.cost(tool):
						tool = ""
				else:
					_rules_error(e)
			else:
				# One of our buildings clicked: the building tool is put down
				# and its actions (repair, research...) pop up beside it.
				if side == 0:
					tool = ""
				selected = Vector2i(side, hex)
				if side == 0:
					_refresh()
					_building_menu(hex)
					return
		Ui.TARGETING:
			if side == 1:
				_target_click(hex)
			else:
				var b = m.sides[0].building_at(hex)
				if b != null and data.role(b.type) in SideLaunchRoles:
					if not m.sides[0].weapon_active(b):
						hud.show_notice(Hud.NOTICE_SILO)
					elif _carrier_block(b) != "":
						hud.show_notice(_carrier_block(b))
					else:
						active_launcher = b.hex
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
		"Transport lost":
			hud.show_notice(Hud.NOTICE_TRANSPORT)
		"Boat lost":
			hud.show_notice(Hud.NOTICE_BOAT_LOST)
		"Boat at sea":
			hud.show_notice(Hud.NOTICE_BOAT_OUT)
		"No nuke":
			hud.show_notice(Hud.NOTICE_NO_NUKE)
		"Nuke not ready":
			hud.show_notice(Hud.NOTICE_NUKE_LOADING)
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
	if setup_mode == "base" or setup_mode == "stronghold":
		var forts_needed := SideState.strongholds_per_side(data)
		var room: int = forts_needed - _count_type(setup_trial, "stronghold") if setup_mode == "stronghold" \
			else data.integer("bases", "per_side") - forts_needed - _count_type(setup_trial, "base")
		if room <= 0:
			hud.add_log("All placed. Click one to move it.")
			return
		setup_trial._add_building(setup_mode, hex, data, 0)
		setup_history.append(hex)
		audio.built(setup_mode)
	else:
		var err: String = setup_trial.can_build("decoy", hex, data, m.settings)
		if err != "":
			hud.add_log("[color=salmon]%s[/color]" % err)
			return
		setup_trial.money -= data.cost("decoy")
		setup_trial._add_building("decoy", hex, data, 0)
		setup_history.append(hex)
		audio.built("decoy")


func _count_type(st, type: String) -> int:
	var n := 0
	for b in st.buildings.values():
		if b.type == type:
			n += 1
	return n


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
	var options := _missile_options(active_launcher)
	if options.size() > 1 and pending_drop.is_empty():
		_missile_menu(active_launcher, hex, options)
		return
	_aim(hex, _missile_for(active_launcher))


## The missiles a launcher can fire now (researched ones).
func _missile_options(launcher_hex: int) -> Array:
	var b = m.sides[0].building_at(launcher_hex)
	if b == null:
		return []
	return data.building(b.type)["missiles"].filter(func(mt): return _can_fly(b, mt))


## Whether this weapon can launch this missile type now as far as research
## and its carrier go: an airport that lost its transport can still send the
## spy in his own helicopter.
func _can_fly(b, mt: String) -> bool:
	if not m.sides[0].missile_unlocked(mt, data):
		return false
	return not b.carrier_lost or bool(data.missile(mt).get("own_aircraft", false))


## A launcher with a choice of missiles: a pop-up at the click with a key
## for each, greyed where the fuel left can't pay for it.
var menu_target: int = -1   ## the hex the missile pop-up is aiming at


func _missile_menu(launcher_hex: int, hex: int, options: Array) -> void:
	var fuel_left: int = m.sides[0].fuel - _fuel_planned()
	for o in orders:
		if int(o["launcher"]) == launcher_hex:
			fuel_left += int(data.missile(String(o["missile"]))["fuel"])   # re-aiming frees its own fuel
	var choices: Array = []
	var money_left: int = m.sides[0].money - _money_planned()
	for o in orders:
		if int(o["launcher"]) == launcher_hex:
			money_left += int(data.missile(String(o["missile"])).get("money", 0))
	for mt in options:
		var f := int(data.missile(mt)["fuel"])
		var cash := int(data.missile(mt).get("money", 0))
		var missile: String = mt
		var text := "%s  -  %d fuel" % [Pieces.MISSILE_NAMES.get(mt, mt), f]
		if cash > 0:
			text += ", %d money" % cash
		choices.append({"text": text,
			"color": MISSILE_KEY_COLORS.get(mt, Color(0.97, 0.80, 0.25)),
			"disabled": f > fuel_left or cash > money_left, "why": Hud.NOTICE_FUEL if f > fuel_left else Hud.NOTICE_MONEY,
			"action": func():
				missile_choice[launcher_hex] = missile
				active_launcher = launcher_hex
				_aim(hex, missile)
				_refresh()})
	menu_target = hex
	hud.choice_menu(get_viewport().get_mouse_position(), "Fire", choices)
	_update_blasts()


const MISSILE_KEY_COLORS := {"basic": Color(0.96, 0.58, 0.28), "scouting": Color(0.56, 0.78, 0.96),
	"transport": Color(0.66, 0.64, 0.94), "spy": Color(0.80, 0.82, 0.88)}


func _aim(hex: int, mt: String) -> void:
	var order := {"launcher": active_launcher, "missile": mt, "target": hex}
	if data.missile(mt).has("carries"):
		# Two clicks: the landing hex, then a neighbouring hex for the march.
		var g = m.sides[1].island.grid
		if pending_drop.is_empty() or int(pending_drop["launcher"]) != active_launcher:
			pending_drop = {"launcher": active_launcher, "target": hex}
			hud.add_log("Now click a hex next to the landing point to choose which way the platoon marches.")
			return
		var dir: int = g.direction_to(int(pending_drop["target"]), hex)
		if dir < 0:
			pending_drop["target"] = hex   # a new landing point
			return
		order["target"] = int(pending_drop["target"])
		order["dir"] = dir
	var new_orders := orders.filter(func(o): return o["launcher"] != active_launcher)
	new_orders.append(order)
	var e: String = m.set_launch_orders(MatchState.PLAYER, new_orders)
	if e != "":
		_rules_error(e)
		return
	orders = new_orders
	pending_drop = {}
	active_launcher = _next_free_launcher(true)


## Takes back a weapon's order, if it has one, so its target leaves the map,
## and selects the weapon ready to aim again.
func _take_back(launcher_hex: int) -> void:
	var kept := orders.filter(func(o): return int(o["launcher"]) != launcher_hex)
	if kept.size() != orders.size():
		orders = kept
		m.set_launch_orders(MatchState.PLAYER, orders)
	if int(pending_drop.get("launcher", -1)) != launcher_hex:
		pending_drop = {}   # a half-placed drop from another weapon
	active_launcher = launcher_hex
	_refresh()


## Right-click in targeting on a hex an order is aimed at: takes that shot
## back, as the weapon's tile does. Returns whether there was one.
func _unaim_at(hit: Vector2i) -> bool:
	if ui != Ui.TARGETING or hit.x != 1 or hit.y < 0:
		return false
	for k in range(orders.size() - 1, -1, -1):
		if int(orders[k]["target"]) == hit.y:
			_take_back(int(orders[k]["launcher"]))
			return true
	return false


func _undo() -> void:
	pending_drop = {}
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
		if _can_fly(b, mt):
			return mt
	return ""


## The first weapon not yet aimed that could fire: working, with its
## carrier, and its launch money affordable after the other orders. With
## need_fuel, also only one whose missile the fuel left after the other
## orders can pay for (for picking the next weapon to aim and for Ginger's
## reminder; the end of the build phase counts weapons regardless of fuel).
func _next_free_launcher(need_fuel: bool = false) -> int:
	var used := {}
	for o in orders:
		used[o["launcher"]] = true
	var money_left: int = m.sides[0].money - _money_planned()
	var fuel_left: int = m.sides[0].fuel - _fuel_planned()
	for b in _attackers(m.sides[0]):
		if not m.sides[0].weapon_active(b) or _carrier_block(b) != "" or used.has(b.hex):
			continue
		var mdef: Dictionary = data.missile(_missile_for(b.hex))
		if int(mdef.get("money", 0)) > money_left:
			continue
		if need_fuel and _cheapest_fuel(b.hex) > fuel_left:
			continue   # not even its cheapest missile (a scout) fits
		return b.hex
	return -1


## The least fuel any missile this launcher can fire costs.
func _cheapest_fuel(launcher_hex: int) -> int:
	var least := -1
	for mt in _missile_options(launcher_hex):
		var f := int(data.missile(mt)["fuel"])
		if least < 0 or f < least:
			least = f
	return maxi(least, 0)


const SideLaunchRoles := ["launcher", "airport", "docks", "silo"]


## Everything that can attack: missile launchers, airports, docks, silos.
func _attackers(st) -> Array:
	return st.of_role(data, "launcher") + st.of_role(data, "airport") + st.of_role(data, "docks") + st.of_role(data, "silo")


## Why an airport, docks or silo can't launch now, as a notice ("" if it can).
func _carrier_block(b) -> String:
	if b.carrier_lost and _missile_options(b.hex).is_empty():
		return {"airport": Hud.NOTICE_TRANSPORT, "silo": Hud.NOTICE_NO_NUKE}.get(data.role(b.type), Hud.NOTICE_BOAT_LOST)
	if b.boat_out:
		return Hud.NOTICE_BOAT_OUT
	if b.loading > 0:
		return Hud.NOTICE_NUKE_LOADING
	return ""


## The few words on a weapon tile that can't launch (see _carrier_block).
func _carrier_block_short(b) -> String:
	if b.boat_out:
		return "Boat at sea"
	if b.loading > 0:
		return "Nuke being built"
	return {"airport": "Transport lost", "silo": "No nuke"}.get(data.role(b.type), "Boat lost")


## Money the orders placed so far will spend at the playout (troop launches).
func _money_planned() -> int:
	var total := 0
	for o in orders:
		total += int(data.missile(String(o["missile"])).get("money", 0))
	return total


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
	enemy_board.drops = []
	for o in orders:
		if o.has("dir"):
			enemy_board.drops.append({"target": int(o["target"]), "dir": int(o["dir"])})
		else:
			enemy_board.markers[o["target"]] = Color(1, 0.25, 0.2)
	if not pending_drop.is_empty():
		enemy_board.drops.append({"target": int(pending_drop["target"]), "dir": -1})
	_update_blasts()
	_update_placement_hints(own_state)
	_update_ranges(own_state)
	if ui != Ui.PLAYOUT:
		_show_boats()
	hud.minimap.queue_redraw()
	var next_income: Dictionary = Earnings.project(own_state, data, m.round_number)["income"]
	if next_income.is_empty() and ui != Ui.OVER:
		next_income = own_state.compute_income(data)   # before income starts: what a round makes
	hud.set_resources(own_state.money, own_state.fuel, own_state.stored_research,
		int(next_income["money"]) if next_income.has("money") else -1,
		own_state.fuel - _fuel_planned() if ui == Ui.TARGETING else -1,
		int(next_income["fuel"]) if next_income.has("fuel") else -1,
		int(next_income["research"]) if next_income.has("research") else -1)
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


## Boats at sea, drawn in the channel off the coast they are heading for,
## so the defender can see roughly where a landing is coming.
func _show_boats() -> void:
	effects.sea_boats.clear()
	for s in [0, 1]:
		for bt in m.boats[s]:
			effects.sea_boats.append(_sea_boat(s, int(bt["target"])))


func _channel_point(s: int, target: int) -> Vector2:
	var dest_board = enemy_board if s == 0 else own_board
	var dest: Vector2 = dest_board.position + dest_board.tile_center(target)
	# The point on the channel's middle line level with the target, whichever
	# way the view is turned.
	var mid: Vector2 = (own_board.position + enemy_board.position) / 2.0
	var across: Vector2 = (enemy_board.position - own_board.position).normalized()
	return dest - across * (dest - mid).dot(across)


func _sea_boat(s: int, target: int):
	var dest_board = enemy_board if s == 0 else own_board
	var at := _channel_point(s, target)
	var dest: Vector2 = dest_board.position + dest_board.tile_center(target)
	return effects.make_boat(at, effects.facing_for(dest - at), "player" if s == 0 else "enemy")


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


## Jumps straight to the next level, with the award a win would have given.
func _debug_next_level() -> void:
	if not Campaign.has_next():
		hud.add_log("[color=gray]Debug: this is the last level.[/color]")
		return
	Campaign.advance()
	get_tree().reload_current_scene()


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
	own_board.range_fill = {}
	own_board.range_shade = {}
	if ui == Ui.SETUP:
		return
	# Placing anti-air: what our radar covers is darkened, so the gun can go
	# where it will hit far more often.
	if ui == Ui.BUILD and tool != "" and data.role(tool) == "anti_air":
		for r in st.of_role(data, "radar"):
			for h in st.island.grid.within(r.hex, st.radar_range(r, data)):
				own_board.range_shade[h] = RADAR_SHADE
	# Placing a building: shade what it would reach from the hex under the
	# mouse, if it can go there.
	if ui == Ui.BUILD and tool != "" and hovered.x == 0 and hovered.y >= 0 \
			and st.can_build(tool, hovered.y, data, m.settings) == "":
		var reach: Array = _reach(st, tool, hovered.y)
		if not reach.is_empty():
			var shade: Color = reach[1]
			shade.a = 0.28
			for h in reach[0]:
				own_board.range_fill[h] = shade
	if selected.x != 0:
		return
	var b = st.building_at(selected.y)
	if b == null:
		return
	var r: Array = _reach(st, b.type, b.hex, b)
	if not r.is_empty():
		own_board.range_rings = [{"hexes": r[0], "color": r[1]}]


const RADAR_SHADE := Color(0.16, 0.04, 0.26, 0.34)
const BLAST_TINT := Color(1.0, 0.45, 0.35, 0.30)    ## where a shot does damage
const VIEW_TINT := Color(0.75, 0.9, 1.0, 0.24)      ## what a scouting missile will see
const CENTRE_TINT := Color(0.85, 0.22, 0.16, 0.48)  ## the impact hex, when several missiles are previewed


## Lightens where each aimed shot lands on the enemy island (its blast; a
## scouting missile's view), over the fog too, and the same for the hex
## under the mouse with the weapon being aimed.
func _update_blasts() -> void:
	enemy_board.blast_fill = {}
	if ui != Ui.TARGETING:
		enemy_board.queue_redraw()
		return
	var shots: Array = []
	for o in orders:
		shots.append([String(o["missile"]), int(o["target"])])
	# The preview: the hex under the mouse, or the one the missile pop-up is
	# for while it is open. A launcher with a choice shows every missile's
	# area at once, its centre a shade darker, so the choice is easy to read.
	var at := menu_target if hud.choice_menu_open() else (hovered.y if hovered.x == 1 else -1)
	var centre := -1
	if active_launcher >= 0 and at >= 0 and pending_drop.is_empty():
		var options := _missile_options(active_launcher)
		if options.size() > 1:
			centre = at
			for mt in options:
				shots.append([mt, at])
		else:
			shots.append([_missile_for(active_launcher), at])
	var g = m.sides[1].island.grid
	for s in shots:
		var mdef: Dictionary = data.missile(String(s[0]))
		if mdef.has("carries"):
			continue   # troops show their drop arrow instead
		var r := int(mdef["blast_radius"])
		var tint := BLAST_TINT
		if r < 0:
			r = int(mdef["view_radius"])
			tint = VIEW_TINT
		for h in g.within(int(s[1]), r):
			if not enemy_board.blast_fill.has(h) or tint == BLAST_TINT:
				enemy_board.blast_fill[h] = tint
	if centre >= 0:
		enemy_board.blast_fill[centre] = CENTRE_TINT
	enemy_board.queue_redraw()


## [hexes, colour] a building of `type` on `hex` covers (anti-air, radar,
## bunker, coastal cannon); [] for buildings with no reach. `b` is the
## building itself when it stands (a radar under repair covers nothing, a
## damaged one half).
func _reach(st, type: String, hex: int, b = null) -> Array:
	var g = st.island.grid
	if data.mounts_anti_air(type) or data.role(type) == "anti_air":
		return [g.within(hex, int(data.section("anti_air")["radius"])), Color(0.4, 1.0, 0.5, 0.6)]
	match data.role(type):
		"radar":
			var r: int
			if b != null:
				if st.out_for_repair(b, data):
					return []
				r = st.radar_range(b, data)
			else:
				var ranges: Array = data.section("radar")["range_by_level"]
				r = int(ranges[clampi(st.island.level[hex], 0, ranges.size() - 1)])
			return [g.within(hex, r), Color(0.8, 0.5, 1.0, 0.7)]
		"bunker":
			return [g.within(hex, int(data.section("troops")["bunker_range"])), Color(0.85, 0.85, 0.75, 0.7)]
		"coastal_cannon":
			return [g.within(hex, int(data.section("troops")["cannon_range"])), Color(0.55, 0.75, 1.0, 0.7)]
	return []


func _building_tooltip(type: String) -> String:
	var lines: Array = [Pieces.display_name(type), Pieces.BUILDING_TEXT.get(type, "")]
	var def: Dictionary = data.building(type)
	lines.append("Cost %d" % data.cost(type))
	if data.is_missile_proof(type):
		lines.append("Only troops can destroy it")
	elif def.has("hp"):
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
			var forts_needed := SideState.strongholds_per_side(data)
			var forts := _count_type(st, "stronghold")
			var plain := placed - forts
			var decoys: int = st.count_role(data, "decoy")
			var max_decoys := int(m.settings["decoys_per_side"])
			hud.add_label("Place your bases on your island. Bases and decoys may not touch each other.", true)
			var forts_full := forts >= forts_needed
			var bases_full := plain >= per_side - forts_needed
			var decoys_full := decoys >= max_decoys
			# A full piece greys out; the mode moves on to one still to place.
			var full := {"stronghold": forts_full, "base": bases_full, "decoy": decoys_full}
			if full.get(setup_mode, true):
				for mode in ["stronghold", "base", "decoy"]:
					if not full[mode]:
						setup_mode = mode
						break
			if forts_needed > 0:
				hud.add_piece_button("stronghold", "Stronghold", "%d/%d" % [forts, forts_needed], "Placed" if forts_full else "Free",
					func(): setup_mode = "stronghold"; _refresh(), forts_full, setup_mode == "stronghold" and not forts_full, _building_tooltip("stronghold"))
			hud.add_piece_button("base", "Base", "%d/%d" % [plain, per_side - forts_needed], "All placed" if bases_full else "Free",
				func(): setup_mode = "base"; _refresh(), bases_full, setup_mode == "base" and not bases_full, _building_tooltip("base"))
			hud.add_piece_button("decoy", "Decoy (optional)", "%d/%d" % [decoys, max_decoys], "%d money" % data.cost("decoy"),
				func(): setup_mode = "decoy"; _refresh(), decoys_full, setup_mode == "decoy" and not decoys_full, _building_tooltip("decoy"))
			hud.add_label("Click a placed piece to remove it.", true)
			hud.add_spacer()
			hud.add_tool_button("Undo", _setup_undo, setup_history.is_empty(), false, "Take back the last piece placed", "undo")
			hud.add_tool_button("Start", _start_setup_game, placed != per_side, false,
				"Begin round 1" if placed == per_side else "Place all %d bases first" % per_side, "start", true)
		Ui.BUILD:
			for type in data.building_types():
				var def: Dictionary = data.building(type)
				if not bool(def.get("buildable", true)):
					continue
				var unlocked: bool = st.building_unlocked(type, data)
				if not unlocked:
					continue   # appears once researched
				var note := ""
				var at_limit := false
				if not unlocked:
					note = "Research first"
				elif type == "decoy" and st.count_role(data, "decoy") >= int(m.settings["decoys_per_side"]):
					note = "Limit reached"
					at_limit = true
				elif st.money < data.cost(type):
					note = "Not enough money"
				var t: String = type
				var broke: bool = unlocked and not at_limit and st.money < data.cost(type)
				# Pressed again, the chosen building is put down and the mouse is free.
				var pick := func(): tool = "" if tool == t else t; selected = Vector2i(-1, -1); _refresh()
				var tag := "LOCKED" if not unlocked else ("LIMIT" if at_limit else "")
				hud.add_piece_button(type, Pieces.display_name(type), str(data.cost(type)), note,
					(func(): hud.show_notice(Hud.NOTICE_MONEY)) if broke else pick,
					not unlocked or at_limit, tool == type, _building_tooltip(type), broke, true, tag)
			hud.add_spacer()
			hud.add_tool_button("Done", _done_pressed, false, false, "End the build and repair phase now", "", true)
		Ui.TARGETING:
			hud.add_fuel_planner(st.fuel, _fuel_planned())
			var launchers: Array = _attackers(st)
			if launchers.is_empty():
				hud.add_label("No launchers. Build one in the build and repair phase.", true)
			# Weapons as tiles, two across: the sprite and the fuel cost. The
			# details are in each tile's tooltip.
			for b in launchers:
				var name := Pieces.display_name(b.type)
				var hx: int = b.hex
				if not st.weapon_active(b):
					hud.add_piece_button(b.type, name, "", "Under repair" if b.repairing else "Out of action",
						func(): hud.show_notice(Hud.NOTICE_SILO), false, false, "Repair it in the build and repair phase.",
						false, true, "", false, true)
					continue
				if _carrier_block(b) != "":
					var why: String = _carrier_block(b)
					var short: String = _carrier_block_short(b)
					hud.add_piece_button(b.type, name, "", short, func(): hud.show_notice(why), false, false, why,
						false, true, "", false, true)
					continue
				var mt := _missile_for(b.hex)
				var aimed := false
				for o in orders:
					if o["launcher"] == b.hex:
						aimed = true
				var mdef: Dictionary = data.missile(mt)
				var troop := mdef.has("carries")
				var note: String = Pieces.MISSILE_NAMES.get(mt, mt) + ", %d fuel" % int(mdef["fuel"])
				if int(mdef.get("money", 0)) > 0:
					note += ", %d money" % int(mdef.get("money", 0))
				if aimed:
					note += " (aimed)"
				var options: Array = _missile_options(b.hex)
				var tip := "Select it, click the landing hex, then a hex next to it for the march direction." if troop \
					else "Select this launcher, then click an enemy hex to aim it."
				if options.size() > 1:
					tip += "\nYou choose the missile when you click the target."
				# A weapon that costs money to fire (troops) can't be picked
				# without the money, counting what the other orders spend.
				var cost := int(mdef.get("money", 0))
				if cost > 0 and not aimed and st.money - _money_planned() < cost:
					hud.add_piece_button(b.type, name, str(int(mdef["fuel"])), note + " (not enough money)",
						func(): hud.show_notice(Hud.NOTICE_MONEY), false, false, tip, false, true, "", false, true)
					continue
				var pick := func(): _take_back(hx)
				hud.add_piece_button(b.type, name, str(int(mdef["fuel"])), note, pick, false, active_launcher == b.hex,
					tip, false, true, "", aimed)
			hud.add_spacer()
			hud.add_tool_button("Undo", _undo, orders.is_empty(), false, "Take back the last order. Free.", "undo")
			hud.add_tool_button("Attack", _attack_pressed, false, false, "Launch the orders placed and end targeting", "", true)
		Ui.PLAYOUT:
			hud.add_label("Missiles in flight.", true)


## The right-hand strip: a beaker per research project. Also sets the status
## gauge (our bases' hits left) on the comms set.
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
	# The status gauge: hits our bases can still take before we lose.
	var hits_left := 0.0
	for b in bases:
		# A stronghold doesn't wear down; it stands at full until troops take it.
		hits_left += max_hits if data.is_missile_proof(b.type) else max_hits - float(b.hits)
	if ui == Ui.SETUP:
		hits_left = per_side * max_hits   # bases still being placed: all to come
	hud.status_gauge.set_hits(hits_left, per_side * max_hits)
	hud.set_strip(items)


func _open_research(lab_id: int) -> void:
	if ui != Ui.BUILD:
		return
	hud.research_panel.open_lab(m.sides[0], data, lab_id, true)
	_update_tips()   # the Scientist explains research the first time


func _start_research(lab_id: int, item: String) -> void:
	if ui != Ui.BUILD:
		return
	var e: String = m.build_action(MatchState.PLAYER, {"action": "research", "lab": lab_id, "item": item})
	if e != "":
		_rules_error(e)
	else:
		hud.add_log("Research started: %s." % Pieces.research_name(item))
	_refresh()


func _use_stored_research(item: String) -> void:
	if ui != Ui.BUILD:
		return
	var e: String = m.build_action(MatchState.PLAYER, {"action": "use_stored_research", "item": item})
	if e != "":
		_rules_error(e)
	elif m.sides[0].is_unlocked(item):
		hud.add_log("Research complete: %s, with stored points." % Pieces.research_name(item))
		audio.effect("research_complete")
	else:
		hud.add_log("Stored points put into %s." % Pieces.research_name(item))
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
	# A launcher out of action that the enemy has hit more than once: they
	# are keeping it down, and a new one out of sight is the answer.
	var targeted := false
	for b in st.of_role(data, "launcher"):
		if b.disabled and int(m.bombed[0].get(b.hex, {}).get("count", 0)) >= 2:
			targeted = true
	var need_fuel := 0
	for b in st.of_role(data, "launcher"):
		if st.weapon_active(b):
			var mt := _missile_for(b.hex)
			if mt != "":
				need_fuel += int(data.missile(mt)["fuel"])
	var setup_complete := false
	if ui == Ui.SETUP and setup_trial != null:
		setup_complete = setup_trial.bases_alive(data) >= data.integer("bases", "per_side") \
			and setup_trial.count_role(data, "decoy") >= int(m.settings["decoys_per_side"])
	return {
		"phase": phase,
		"round": m.round_number,
		"has_lab": st.count_role(data, "lab") > 0,
		"troop_selected": ui == Ui.TARGETING and active_launcher >= 0 and st.building_at(active_launcher) != null \
			and data.role(st.building_at(active_launcher).type) in ["airport", "docks"] \
			and data.missile(_missile_for(active_launcher)).has("carries"),
		"research_open": hud.research_panel.visible,
		"setup_complete": setup_complete,
		"clock_on": clock_running,
		"has_launcher": st.count_role(data, "launcher") > 0,
		"has_anti_air": st.count_role(data, "anti_air") > 0,
		"radar_started": st.is_unlocked("radar") or st.project_for_item("radar") != null,
		"suspected_base_seen": seen,
		"own_damaged": damaged,
		"launcher_targeted": targeted,
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


## The phase clock holds while a tip is up, or an announcement that holds
## it (the income report doesn't), until it is dismissed.
func _tip_holds_clock() -> bool:
	return hud.announcer.holds_clock() or hud.tip_showing() != ""


## A character's line; one of its "endings", picked at random, goes after it.
func _line_text(key: String) -> String:
	var line: Dictionary = lines.get(key, {})
	var text := String(line.get("text", ""))
	var endings: Array = line.get("endings", [])
	if not endings.is_empty():
		text += " " + String(endings[randi() % endings.size()])
	return text


func _line_character(key: String) -> String:
	return String(lines.get(key, {}).get("character", ""))


## Says line `key` (or `text` in its place) with a "Don't show this again"
## box, unless the player has hidden it. Hidden lines are kept with the
## finished tips (as "line:<group or key>"), so resetting tips brings them
## back. group: lines hidden together (all the incoming warnings).
func _say(key: String, text: String = "", hold: bool = true, click_away: bool = false, group: String = "") -> void:
	var id := "line:" + (group if group != "" else key)
	if prefs["tips_done"].has(id):
		return
	hud.announce(text if text != "" else _line_text(key), id, 0.0, true, _line_character(key), hold, click_away)


func _on_tip_dismissed(id: String, forever: bool) -> void:
	if id.begins_with("line:"):
		# A character's line (see _say), not a tip.
		if forever and not prefs["tips_done"].has(id):
			prefs["tips_done"].append(id)
			_save_prefs()
		return
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
	_update_rules_text()
	current_tip = null
	_refresh()


## The Game Rules page, with the player's clocks.
func _update_rules_text() -> void:
	hud.esc_menu.rules_text = RulesText.build(data, int(prefs["build_clock_seconds"]), int(prefs["targeting_clock_seconds"]))


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
		# Nothing pointed at: the last attack's summary, until the next one.
		var show_report: bool = not battle_report.is_empty() and ui in [Ui.BUILD, Ui.TARGETING]
		hud.set_info("[b]Battle summary, round %d[/b]\n%s" % [m.round_number - 1, "\n".join(battle_report)] if show_report else "")
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
			if data.is_missile_proof(b.type):
				lines.append("Only enemy troops can destroy it. Bunkers nearby protect it.")
				if b.repairing:
					lines.append("[color=orange]Gun under repair: back next round[/color]")
				elif b.disabled:
					lines.append("[color=salmon]Gun out of action until repaired[/color]")
				else:
					lines.append("Gun covers %d hexes around it, %d missiles a round" % [int(data.section("anti_air")["radius"]), st.anti_air_engagements(data)])
				if b.hits > 0.0:
					lines.append("The enemy knows it is a stronghold")
			elif data.is_base_like(b.type):
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
				var proof: bool = data.has_building(String(b["type"])) and data.is_missile_proof(String(b["type"]))
				if proof:
					lines.append("Missiles only knock out its gun. Land troops on it to take it.")
				if b["disabled"]:
					lines.append("Gun out of action" if proof else "Out of action")
				elif b["damaged"]:
					lines.append("Damaged")
		elif String(e["destroyed"]) != "":
			lines.push_front("[b]Destroyed %s[/b]" % Pieces.display_name(String(e["destroyed"])))
		hud.set_info("\n".join(lines))


## "2/6 points, 2 rounds left" for a research item in progress.
func _research_progress(st, item: String) -> String:
	var p = st.project_for_item(item)
	var need := int(data.research_item(item)["points"])
	var left := Earnings.rounds_left(st, data, item)
	var eta := "stalled" if left < 0 else "%d round%s left" % [left, "" if left == 1 else "s"]
	return "%d/%d points, %s" % [int(p["progress"]), need, eta]


## What a building does right now, for the info box.
func _building_detail_lines(st, b) -> Array:
	var out: Array = []
	var produces: Dictionary = st.produces_of(b.type, data)
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
		"airport":
			var t: Dictionary = data.missile("transport")
			out.append("One air transport a round: %d fuel, %d money" % [int(t["fuel"]), int(t.get("money", 0))])
			if b.carrier_lost:
				out.append("[color=salmon]Transport lost: replace it to launch again[/color]")
		"bunker":
			out.append("Wipes out platoons within %d hexes" % int(data.section("troops")["bunker_range"]))
		"docks":
			var bm: Dictionary = data.missile("boat")
			out.append("One boat at a time: %d fuel, %d money; lands the round after" % [int(bm["fuel"]), int(bm.get("money", 0))])
			if b.boat_out:
				out.append("Boat at sea")
			if b.carrier_lost:
				out.append("[color=salmon]Boat lost: replace it to launch again[/color]")
		"silo":
			var nk: Dictionary = data.missile("nuke")
			out.append("One nuke at a time: %d money to build, ready the round after; %d fuel to fire" % [int(nk.get("replace_money", 0)), int(nk["fuel"])])
			match Pieces.nuke_state(b):
				"none": out.append("[color=salmon]Empty: build a nuke to fire[/color]")
				"loading": out.append("Nuke being built: ready next round")
				_: out.append("Nuke ready to fire")
		"coastal_cannon":
			out.append("Fires on boats landing within %d hexes, hitting %d%% of the time" % [int(data.section("troops")["cannon_range"]),
				roundi(float(data.section("troops")["cannon_accuracy"]) * 100.0)])
		"lab":
			var p = st.project_for_lab(b.id)
			var oldest = st.oldest_project()
			if p != null:
				out.append("Researching %s" % Pieces.research_name(String(p["item"])))
				out.append(_research_progress(st, String(p["item"])))
			elif oldest != null:
				out.append("Helping %s" % Pieces.research_name(String(oldest["item"])))
				out.append(_research_progress(st, String(oldest["item"])))
			else:
				out.append("Idle: choose research")
	return out


const ACTION_KEY_COLORS := {"repair": Color(0.97, 0.80, 0.25), "carrier": Color(0.42, 0.80, 0.38), "research": Color(0.56, 0.78, 0.96)}


## The pop-up menu of what can be done with one of our buildings in the
## build and repair phase, beside the mouse (the missile menu's design).
## Nothing pops up for a building with nothing to do.
func _building_menu(hex: int) -> void:
	var st = _own_state()
	var b = st.building_at(hex)
	if b == null:
		return
	var choices: Array = _building_actions(st, b)
	if not choices.is_empty():
		hud.choice_menu(get_viewport().get_mouse_position(), Pieces.display_name(b.type), choices)


## [{"text", "color", "disabled", "why", "action"}] for _building_menu.
func _building_actions(st, b) -> Array:
	var out: Array = []
	if st.needs_repair(b, data):
		var cost: int = st.repair_cost(b.type, data)
		var hx: int = b.hex
		var type: String = b.type
		var do_repair := func():
			var e: String = m.build_action(MatchState.PLAYER, {"action": "repair", "hex": hx})
			if e != "":
				hud.add_log("[color=salmon]%s[/color]" % e)
			else:
				audio.effect("repair")
				hud.add_log("Repairing %s." % Pieces.display_name(type))
			_refresh()
		var err: String = st.can_repair(b.hex, data)
		out.append({"text": "Repair (%d)" % cost, "color": ACTION_KEY_COLORS["repair"], "disabled": err != "", "why": err, "action": do_repair})
	if b.carrier_lost:
		var hx2: int = b.hex
		var cost2: int = st.carrier_cost(b, data)
		var err2: String = st.can_replace_carrier(b.hex, data)
		var silo: bool = data.role(b.type) == "silo"
		var label: String = "Build nuke (%d)" % cost2 if silo else "Replace %s (%d)" % ["transport" if data.role(b.type) == "airport" else "boat", cost2]
		out.append({"text": label, "color": ACTION_KEY_COLORS["carrier"], "disabled": err2 != "", "why": err2, "action": func():
			var e: String = m.build_action(MatchState.PLAYER, {"action": "replace_carrier", "hex": hx2})
			if e != "":
				_rules_error(e)
			else:
				hud.add_log("Building a nuke: ready next round." if silo else "Replacement ready.")
			_refresh()})
	if data.role(b.type) == "lab":
		# Always open: a busy lab shows its project's progress, and stored
		# points can be spent on it there.
		var lab_id: int = b.id
		out.append({"text": "Research...", "color": ACTION_KEY_COLORS["research"], "action": func(): _open_research(lab_id)})
	return out


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
	enemy_board.drops = []
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
	var arrivals := [events.filter(func(e): return e["type"] == "boat_arrive" and e["side"] == 0),
		events.filter(func(e): return e["type"] == "boat_arrive" and e["side"] == 1)]
	var sailings: Array = events.filter(func(e): return e["type"] == "boat_launch" and e["side"] == 0)
	for e in events:
		if e["type"] == "cannon_fire":
			if not by_id.has(e["id"]):
				by_id[e["id"]] = {}
			if not by_id[e["id"]].has("cannon_shots"):
				by_id[e["id"]]["cannon_shots"] = []
			by_id[e["id"]]["cannon_shots"].append(e)

	# Our missiles launch. The enemy's launches are not shown: its missiles
	# are only seen arriving, with the view staying on our island.
	_fly_to(0, 0.6)
	await _wait(0.7)
	for k in launches[0].size():
		var lm: Dictionary = data.missile(String(launches[0][k]["missile"]))
		if lm.has("carries") or lm.has("finds_roles"):
			_take_off(int(launches[0][k]["launcher"]), k * 0.15, "helicopter" if lm.has("finds_roles") else "transport")
		else:
			_rise(own_board, int(launches[0][k]["launcher"]), Color(1, 0.9, 0.5), k * 0.15)
	for k in sailings.size():
		_sail_out(sailings[k], k * 0.2)
	await _wait(0.9 + maxf(launches[0].size() * 0.15, sailings.size() * 0.2 + 0.3))

	# Enemy strikes land on our island, then damage shows.
	if not launches[1].is_empty() or not arrivals[1].is_empty():
		# Warning first: the siren turns once, then the character warns of the
		# attack; the missiles land only once the player has pressed OK.
		var n: int = launches[1].size()
		var key := "incoming_one" if n == 1 else "incoming_many"
		var spies_only: bool = n > 0 and arrivals[1].is_empty() and launches[1].all(func(e): return data.missile(String(e["missile"])).has("finds_roles"))
		if spies_only and lines.has("incoming_spy"):
			key = "incoming_spy"
		elif launches[1].any(func(e): return String(e["missile"]) == "nuke") and lines.has("incoming_nuke"):
			key = "incoming_nuke"
		elif launches[1].any(func(e): return data.missile(String(e["missile"])).has("carries")):
			key = "incoming_troops"
		elif not arrivals[1].is_empty():
			key = "incoming_boat"
		var incoming := _line_text(key).format({"n": n})
		hud.set_alarm(true)
		audio.effect("siren")
		audio.set_music("battle")   # loops until our strikes are in
		hud.add_log("Enemy helicopter incoming." if spies_only else "%d enemy missile%s incoming." % [n, "" if n == 1 else "s"], false)
		await _wait(hud.alarm_seconds(ALARM_TURNS))
		_say(key, incoming, true, false, "incoming")
		while hud.announcing():
			await get_tree().process_frame
		await _wait(0.25)
		var longest := 0.0
		for k in arrivals[1].size():
			longest = maxf(longest, _ashore(own_board, m.sides[0].island, arrivals[1][k], by_id, Color(1, 0.4, 0.4), k * 0.4, []))
		var off := longest
		for k in launches[1].size():
			longest = maxf(longest, _land(own_board, m.sides[0].island, launches[1][k], by_id, Color(1, 0.4, 0.4), off + k * 0.35, []))
		await _wait(longest)
	own_board.set_tiles(BoardView.own_tiles(m.sides[0], data, m.knowledge[1], m.bombed[0]))
	_mark_fired(launches[0].map(func(e): return int(e["launcher"])))
	for ev in events:
		if ev.get("side", -1) == 0 and ev["type"] in ["destroyed", "disabled", "damaged", "decoy_revealed", "stronghold_revealed"]:
			_log_event(ev)
		elif ev.get("side", -1) == 1 and ev["type"] in ["platoon", "carrier_lost", "boat_sunk", "boat_no_landing", "spy", "spy_lost", "launcher_revealed"]:
			_log_event(ev)
	# Our first base just fell: the level's line (Ginger in level 1), right
	# away, before our own strikes go in. Every match; skipped if two fell at
	# once or the game is over.
	var lost_line := String(level.get("first_base_lost", ""))
	var lost: int = data.integer("bases", "per_side") - m.sides[0].bases_alive(data)
	if not first_base_line_said and lost >= 1 and lost_line != "" and lines.has(lost_line):
		first_base_line_said = true
		if lost == 1 and not m.is_over():
			_say(lost_line)
			while hud.announcing():
				await get_tree().process_frame

	# Nothing of ours to fire this round: said now, where our strikes would go.
	if no_weapons_turn:
		no_weapons_turn = false
		if not launches[1].is_empty() or not arrivals[1].is_empty():
			await _wait(ENEMY_TURN_PAUSE)
		hud.show_notice(Hud.NOTICE_NO_WEAPONS)
		await _wait(1.5)
	# Our strikes land on the enemy island, after a beat on ours to take in
	# what the enemy did.
	if not launches[0].is_empty() or not arrivals[0].is_empty():
		if not launches[1].is_empty() or not arrivals[1].is_empty():
			await _wait(ENEMY_TURN_PAUSE)
		_fly_to(1, 0.6)
		await _wait(0.7)
		var longest := 0.0
		for k in arrivals[0].size():
			longest = maxf(longest, _ashore(enemy_board, null, arrivals[0][k], by_id, Color(1, 0.9, 0.5), k * 0.4, post_enemy))
		var off := longest
		for k in launches[0].size():
			longest = maxf(longest, _land(enemy_board, null, launches[0][k], by_id, Color(1, 0.9, 0.5), off + k * 0.35, post_enemy))
		await _wait(longest)
	audio.set_music("")   # our missiles are down: the battle theme fades out
	enemy_board.set_tiles(_enemy_tiles())
	for ev in events:
		if ev.get("side", -1) == 1 and ev["type"] in ["destroyed", "disabled", "damaged", "decoy_revealed", "stronghold_revealed"]:
			_log_event(ev)
		elif ev.get("side", -1) == 0 and ev["type"] in ["platoon", "carrier_lost", "boat_sunk", "boat_no_landing", "boat_launch", "spy", "spy_lost", "launcher_revealed"]:
			_log_event(ev)
		elif ev["type"] in ["game_over", "coin_flip_needed"]:
			_log_event(ev)
	await _wait(0.8)
	effects.clear()
	battle_report = BattleReport.stat_lines(events, lines.get("battle_report", {}).get("stats", {}))
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


func _aa_sound() -> void:
	audio.effect("anti_air_fire")


## Our transport takes off from its airport and climbs away toward the
## enemy, at the same time as the missiles go up.
func _take_off(hex: int, delay: float, kind: String = "transport") -> void:
	await _wait(delay)
	audio.effect("transport_engine")
	var start: Vector2 = own_board.position + own_board.tile_center(hex)
	var toward: Vector2 = (enemy_board.position - own_board.position).normalized()
	var plane = effects.add_plane(start, 4.0, toward.angle(), Color(1, 0.9, 0.5), "player")
	plane.kind = kind
	var t := create_tween().set_parallel(true)
	t.tween_property(plane, "ground", start + toward * 620.0, 1.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(plane, "alt", 150.0, 1.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await t.finished
	effects.remove_plane(plane)


func _rise(board, hex: int, color: Color, delay: float, offset: Vector2 = Vector2.ZERO) -> void:
	await _wait(delay)
	if board == own_board:
		_mark_fired([hex])
		audio.effect("missile_fire")
	var ms = effects.add_missile(board.position + board.tile_center(hex) + offset, 0.0, color)
	var t := create_tween()
	t.tween_property(ms, "alt", 700.0, 0.8).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	await t.finished
	effects.remove_missile(ms)


## Our boat leaves its docks and heads out into the channel.
func _sail_out(ev: Dictionary, delay: float) -> void:
	await _wait(delay)
	var from: Vector2 = own_board.position + own_board.tile_center(int(ev["launcher"]))
	var to := _channel_point(0, int(ev["target"]))
	var bt = _sea_boat(0, int(ev["target"]))
	bt.ground = from
	effects.sea_boats.append(bt)
	var t := create_tween()
	t.tween_property(bt, "ground", to, 1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## A boat comes ashore from the channel: coastal cannons fire at it as it
## nears the landing hex; it sinks, turns back for want of a beach, or lands
## its platoon. Returns how long it will take.
func _ashore(board, isl, ev: Dictionary, by_id: Dictionary, color: Color, delay: float, reveal_tiles: Array) -> float:
	var info: Dictionary = by_id.get(ev["id"], {})
	_ashore_anim(board, isl, ev, info, color, delay, reveal_tiles)
	var path: Array = info.get("platoon", {}).get("path", [])
	return delay + 1.6 + MARCH_SECONDS * path.size() + 0.8


func _ashore_anim(board, isl, ev: Dictionary, info: Dictionary, color: Color, delay: float, reveal_tiles: Array) -> void:
	await _wait(delay)
	var s := int(ev["side"])
	var side := "player" if s == 0 else "enemy"
	var target := int(ev["target"])
	var ground: Vector2 = board.position + board.tile_center(target)
	var bt = null
	for b in effects.sea_boats:
		if b.ground.distance_to(_channel_point(s, target)) < 2.0:
			bt = b
			break
	if bt == null:
		bt = _sea_boat(s, target)
		effects.sea_boats.append(bt)
	var t := create_tween()
	t.tween_property(bt, "ground", ground, 1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	for shot in info.get("cannon_shots", []):
		await _wait(0.25)
		var src: Vector2 = board.position + board.tile_center(int(shot["cannon"])) - Vector2(0, 16) if isl != null else ground + Vector2(70, -20)
		audio.effect("cannon_shot")
		effects.tracer(src, bt.ground)
		effects.explosion(bt.ground, 14.0, Color(0.85, 0.9, 1.0) if not shot["hit"] else Color(1.0, 0.55, 0.15))
	await t.finished
	if info.has("boat_sunk"):
		effects.explosion(ground, 26.0, Color(0.7, 0.85, 1.0))
		audio.effect("missile_explode", -6.0)
		effects.float_text(ground, "Sunk", Color(0.85, 0.92, 1.0))
		effects.sea_boats.erase(bt)
		return
	if info.has("boat_no_landing"):
		effects.float_text(ground, "No beach", Color(0.85, 0.92, 1.0))
		var back := create_tween()
		back.tween_property(bt, "ground", _channel_point(s, target), 0.8)
		back.tween_callback(func(): effects.sea_boats.erase(bt))
		return
	effects.sea_boats.erase(bt)
	var p: Dictionary = info.get("platoon", {})
	if p.is_empty():
		return
	await _march(board, p, ground, color, side, reveal_tiles)


## Plays one launch arriving: a missile strike, or a transport drop. Starts
## it and returns how long it will take, so the caller can wait for all.
func _land(board, isl, launch: Dictionary, by_id: Dictionary, color: Color, delay: float, reveal_tiles: Array) -> float:
	var info: Dictionary = by_id.get(launch["id"], {})
	if data.missile(String(launch["missile"])).has("finds_roles"):
		_spy_flight(board, isl, info, int(launch["target"]), color, delay, reveal_tiles)
		return delay + SPY_SECONDS
	if data.missile(String(launch["missile"])).has("carries"):
		_drop(board, isl, info, int(launch["target"]), color, delay, reveal_tiles)
		var path: Array = info.get("platoon", {}).get("path", [])
		return delay + DROP_SECONDS + MARCH_SECONDS * path.size() + 0.6
	_strike(board, isl, info, int(launch["target"]), color, delay, reveal_tiles)
	return delay + 1.4


const DROP_SECONDS := 2.2      ## transport flying in and the parachutes coming down
const MARCH_SECONDS := 0.45    ## a platoon moving one hex


## A transport flies in from the attacker's side, may be shot down, drops
## its platoon by parachute, then the platoon marches along its path:
## buildings it overruns explode, and a bunker in range wipes it out.
func _drop(board, isl, info: Dictionary, target: int, color: Color, delay: float, reveal_tiles: Array = []) -> void:
	await _wait(delay)
	var ground: Vector2 = board.position + board.tile_center(target)
	var attacker = own_board if board == enemy_board else enemy_board
	var from: Vector2 = (attacker.position - board.position).normalized()   # the attacker's island side
	var side := "player" if board == enemy_board else "enemy"
	var alt := 150.0
	var plane = effects.add_plane(ground + from * 650.0, alt, (-from).angle(), color, side)
	var t := create_tween()
	t.tween_property(plane, "ground", ground, 1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await t.finished
	if info.has("engage"):
		var eng: Dictionary = info["engage"]
		var src: Vector2 = board.position + board.tile_center(int(eng["anti_air"])) - Vector2(0, 20) if isl != null else ground + Vector2(-60, 30)
		_aa_sound()
		effects.tracer(src, ground - Vector2(0, alt))
		await _wait(0.15)
		if eng["hit"]:
			effects.burst(ground - Vector2(0, alt))
			effects.explosion(ground - Vector2(0, alt), 26.0, Color(1.0, 0.55, 0.15))
			audio.effect("anti_air_hit")
			effects.remove_plane(plane)
			return
	# Eight parachutes, while the plane flies on and away.
	plane.door_open = true
	var chutes: Array = []
	for k in BattleReport.SOLDIERS_PER_PLATOON:
		var off := Vector2(float(k % 4) * 9.0 - 13.5, float(k / 4) * 6.0 - 3.0)
		chutes.append(effects.add_chute(ground + off, alt - 10.0 - k * 3.0, color, side))
	var away := create_tween()
	away.tween_property(plane, "ground", ground - from * 650.0, 1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	away.tween_callback(func(): effects.remove_plane(plane))
	var fall := create_tween().set_parallel(true)
	for c in chutes:
		fall.tween_property(c, "alt", 0.0, 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await fall.finished
	for c in chutes:
		effects.remove_chute(c)
	var p: Dictionary = info.get("platoon", {})
	if p.is_empty():
		return
	if bool(p["lost_at_sea"]):
		effects.explosion(ground, 18.0, Color(0.6, 0.85, 1.0))
		effects.float_text(ground, "Lost at sea", Color(0.8, 0.9, 1.0))
		return
	await _march(board, p, ground, color, side, reveal_tiles)


const SPY_SECONDS := 4.4       ## the helicopter in, the spy's look round, and away


## The spy's helicopter flies in from the attacker's side and may be shot
## down. If not, it sets down on its hex and the spy steps out; each silo he
## finds is revealed and marked; he climbs back in and the helicopter flies
## home the way it came.
func _spy_flight(board, isl, info: Dictionary, target: int, color: Color, delay: float, reveal_tiles: Array = []) -> void:
	await _wait(delay)
	var ground: Vector2 = board.position + board.tile_center(target)
	var attacker = own_board if board == enemy_board else enemy_board
	var from: Vector2 = (attacker.position - board.position).normalized()
	var side := "player" if board == enemy_board else "enemy"
	var alt := 120.0
	var heli = effects.add_plane(ground + from * 650.0, alt, (-from).angle(), color, side)
	heli.kind = "helicopter"
	var t := create_tween()
	t.tween_property(heli, "ground", ground, 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await t.finished
	if info.has("engage"):
		var eng: Dictionary = info["engage"]
		var src: Vector2 = board.position + board.tile_center(int(eng["anti_air"])) - Vector2(0, 20) if isl != null else ground + Vector2(-60, 30)
		_aa_sound()
		effects.tracer(src, ground - Vector2(0, alt))
		await _wait(0.15)
		if eng["hit"]:
			effects.burst(ground - Vector2(0, alt))
			effects.explosion(ground - Vector2(0, alt), 22.0, Color(1.0, 0.55, 0.15))
			audio.effect("anti_air_hit")
			effects.remove_plane(heli)
			return
	t = create_tween()
	t.tween_property(heli, "alt", 6.0, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await t.finished
	var spy = effects.add_agent(ground + Vector2(14, 6), side)
	spy.pose = 1
	await _wait(0.3)
	spy.pose = 2   # reporting in
	var found: Array = info.get("spy", {}).get("found", [])
	for h in found:
		if not reveal_tiles.is_empty():
			board.tiles[int(h)] = reveal_tiles[int(h)]
		else:
			board.tiles[int(h)]["enemy_seen"] = true
		var fb = m.sides[1 if board == enemy_board else 0].building_at(int(h))
		effects.float_text(board.position + board.tile_center(int(h)), "%s found" % (Pieces.display_name(fb.type) if fb != null else "Target"), Color(1.0, 0.86, 0.3))
	if found.is_empty():
		effects.float_text(ground, "Nothing found", Color(0.85, 0.9, 1.0))
	board.queue_redraw()
	await _wait(0.9)
	spy.pose = 1
	await _wait(0.2)
	effects.remove_agent(spy)
	heli.heading = from.angle()
	t = create_tween().set_parallel(true)
	t.tween_property(heli, "alt", alt, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.tween_property(heli, "ground", ground + from * 650.0, 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN).set_delay(0.2)
	await t.finished
	effects.remove_plane(heli)


## A landed platoon walks its path: each hex it reaches is revealed, a
## building it overruns explodes after a moment of fighting, and a bunker in
## range wipes it out.
func _march(board, p: Dictionary, ground: Vector2, color: Color, side: String, reveal_tiles: Array) -> void:
	var squad = effects.add_squad(ground, color, side)
	var path: Array = p["path"]
	if path.size() > 1:
		squad.facing = effects.facing_for(board.tile_center(int(path[1])) - board.tile_center(int(path[0])))
	for i in path.size():
		var h: int = int(path[i])
		var pos: Vector2 = board.position + board.tile_center(h)
		if i > 0:
			squad.walking = true
			var mv := create_tween()
			mv.tween_property(squad, "ground", pos, MARCH_SECONDS)
			await mv.finished
			squad.walking = false
		if not reveal_tiles.is_empty():
			board.tiles[h] = reveal_tiles[h]
		else:
			board.tiles[h]["enemy_seen"] = true
		board.queue_redraw()
		if i == path.size() - 1 and int(p["stopped_by"]) >= 0:
			var bk := int(p["stopped_by"])
			if not reveal_tiles.is_empty():
				board.tiles[bk] = reveal_tiles[bk]
			audio.effect("bunker_fire")
			effects.tracer(board.position + board.tile_center(bk) - Vector2(0, 14), pos - Vector2(0, 6))
			await _wait(0.12)
			effects.burst(pos - Vector2(0, 6))
			effects.float_text(pos, "Wiped out", Color(1, 1, 1))
			squad.wiped = true
			await _wait(0.7)
			effects.remove_squad(squad)
			return
		if p["destroyed"].has(h):
			await _wait(0.25)   # a moment of fighting on the hex
			effects.explosion(pos, 32.0, Color(1.0, 0.55, 0.15))
			audio.effect("missile_explode", -4.0)
			if reveal_tiles.is_empty() and board.tiles[h].get("building") != null:
				board.tiles[h]["destroyed"] = String(board.tiles[h]["building"]["type"])
				board.tiles[h]["building"] = null
	await _wait(0.3)
	effects.remove_squad(squad)


## One incoming missile: falls toward its aimed hex, may be engaged by
## anti-air, may seek, then explodes. `isl` is the defender's island when we
## can show anti-air positions (our own); null when it is the enemy's.
## `reveal_tiles`, when given, holds the after-playout tiles for the enemy
## space; the hexes this impact reveals switch to them as it lands. On our
## own island the revealed hexes are marked as seen by the enemy.
## A nuke going off: a white flash and a big fireball on the centre, then
## the ring of hexes around it bursting a beat later.
func _nuke_blast(board, centre: int, ground: Vector2) -> void:
	effects.explosion(ground, 46.0, Color(1.0, 0.97, 0.85))
	effects.explosion(ground, 95.0, Color(1.0, 0.5, 0.12))
	audio.effect("missile_explode", 4.0)
	var ring: Array = Array(board.iso.grid.neighbors(centre))
	await _wait(0.12)
	for n in ring:
		effects.explosion(board.position + board.tile_center(int(n)), 34.0, Color(1.0, 0.6, 0.18))
	audio.effect("missile_explode")


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
			_aa_sound()
			effects.tracer(board.position + board.tile_center(int(eng["anti_air"])) - Vector2(0, 20), ground - Vector2(0, ms.alt))
		else:
			_aa_sound()
			effects.tracer(ground + Vector2(-60, 30), ground - Vector2(0, ms.alt))
		await _wait(0.15)
		if eng["hit"]:
			effects.burst(ground - Vector2(0, ms.alt))
			audio.effect("anti_air_hit")
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
	if String(imp.get("missile", "")) == "nuke":
		_nuke_blast(board, int(imp.get("hex", target)), ground)
	else:
		effects.explosion(ground, 18.0 if is_scout else 40.0, Color(0.6, 0.8, 1.0) if is_scout else Color(1.0, 0.55, 0.15))
		audio.effect("missile_explode", -10.0 if is_scout else 0.0)
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
				audio.effect("research_complete")
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
		"stronghold_revealed":
			if mine:
				hud.add_log("[color=salmon]The enemy has found our stronghold.[/color]")
			else:
				hud.add_log("[color=orange]That base is a stronghold: missiles only knock out its gun.[/color]")
				enemy_stronghold_seen = true
		"platoon":
			var n_kill: int = ev["destroyed"].size()
			if bool(ev["lost_at_sea"]):
				hud.add_log("Our platoon was lost at sea." if mine else "An enemy platoon was lost at sea.")
			elif int(ev["stopped_by"]) >= 0:
				hud.add_log(("Our platoon was wiped out by a bunker" if mine else "[color=lightgreen]Our bunker wiped out an enemy platoon") +
					(" after destroying %d." % n_kill if n_kill > 0 else ".") + ("" if mine else "[/color]"))
			else:
				hud.add_log(("[color=lightgreen]Our platoon destroyed %d building%s.[/color]" if mine else "[color=salmon]An enemy platoon destroyed %d building%s.[/color]")
					% [n_kill, "" if n_kill == 1 else "s"])
		"spy":
			var n_found: int = ev["found"].size()
			if mine:
				hud.add_log("[color=lightgreen]Our spy is back: %s.[/color]" % (
					"no banks, labs or refineries" if n_found == 0 else ("%d bank%s, lab%s and refiner%s found" % [n_found, "" if n_found == 1 else "s", "" if n_found == 1 else "s", "y" if n_found == 1 else "ies"])))
			elif n_found > 0:
				hud.add_log("[color=salmon]An enemy spy found %d of our banks, labs and refineries.[/color]" % n_found)
			else:
				hud.add_log("An enemy spy landed and flew off again.")
		"launcher_revealed":
			hud.add_log("[color=salmon]Our nuke launch gave away our silo.[/color]" if mine else "[color=lightgreen]The enemy's nuke launch gave away its silo.[/color]")
		"spy_lost":
			hud.add_log("[color=salmon]Our spy's helicopter was shot down.[/color]" if mine else "[color=lightgreen]We shot down an enemy helicopter.[/color]")
		"carrier_lost":
			hud.add_log("[color=salmon]Our transport was shot down.[/color]" if mine else "[color=lightgreen]Enemy transport shot down.[/color]")
		"boat_launch":
			if mine:
				hud.add_log("Our boat puts to sea.")
		"boat_sunk":
			hud.add_log("[color=salmon]Our boat was sunk.[/color]" if mine else "[color=lightgreen]Our coastal guns sank an enemy boat.[/color]")
		"boat_no_landing":
			hud.add_log("Our boat found no beach and turned back." if mine else "An enemy boat found no beach and turned back.")
		"coin_flip_needed":
			hud.add_log("Both sides lost their last base. Money is equal: coin flip.")
		"coin_flip":
			hud.add_log("The enemy called %s. The coin shows %s." % [ev["call"], ev["flip"]])
		"game_over":
			hud.add_log("[b]%s[/b]" % ("Victory." if ev["winner"] == MatchState.PLAYER else "Defeat."))
