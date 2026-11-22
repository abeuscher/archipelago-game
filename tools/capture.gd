## Development aid: runs the real main scene in a window, drives it through
## setup, build, research, targeting and one playout, and saves screenshots.
##   godot --path . -s tools/capture.gd -- <output_dir> [seed]
## Uses its own settings file in the output folder, so it never touches the
## player's saved settings or tips.
extends SceneTree

const SimpleAI = preload("res://ai/simple_ai.gd")

var out_dir := "user://captures"
var main


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	var seed_arg := "7" if args.size() < 2 else args[1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	var settings_path := out_dir.path_join("capture_settings.json")
	if FileAccess.file_exists(settings_path):
		DirAccess.remove_absolute(settings_path)
	var scene: PackedScene = load("res://game/main.tscn")
	main = scene.instantiate()
	main.set_meta("seed_override", int(seed_arg))
	main.set_meta("settings_path", settings_path)
	root.add_child(main)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await _frames(3)
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("saved ", name)


## The incoming warning must still be up a while after it appears.
func check_still_up() -> void:
	print("warning still up after 1.4 s: ", main.hud.announcing())


## Troops: give the player an airport, aim a drop at an enemy base, attack,
## and catch the transport, the parachutes and the march.
func _troops() -> void:
	var st = main.m.sides[0]
	st.unlocked["airport"] = true
	st.money += 300
	st.fuel += 20
	var port_hex: int = _free_hexes()[40]
	st._add_building("airport", port_hex, main.data, main.m.round_number)
	main._refresh()
	main._end_build()
	await create_timer(1.2).timeout
	var enemy = main.m.sides[1]
	var target: int = enemy.of_role(main.data, "base")[0].hex
	var g = enemy.island.grid
	var next := -1
	for d in 6:
		var n: int = g.step(target, d)
		if n >= 0 and enemy.island.is_land(n):
			next = n
			break
	main.active_launcher = port_hex
	main._target_click(target)
	main._refresh()
	await _shot("21a_drop_landing_chosen")
	main._target_click(next)
	main._refresh()
	await _shot("21b_drop_planned")
	main._attack()
	for k in 12:
		await create_timer(0.15).timeout
		if not main.effects.planes.is_empty():
			await _shot("21c_take_off")
			break
	var got := {}
	while main.ui == main.Ui.PLAYOUT:
		if main.hud.announcing():
			main.hud.announcer._ok.pressed.emit()
		var fx = main.effects
		if not got.has("plane") and not fx.planes.is_empty() and main.viewing == 1:
			got["plane"] = true
			await create_timer(0.6).timeout
			await _shot("22_transport")
		elif not got.has("chutes") and not fx.chutes.is_empty():
			got["chutes"] = true
			await create_timer(0.5).timeout
			await _shot("23_parachutes")
		elif not got.has("squad") and not fx.squads.is_empty():
			got["squad"] = true
			await create_timer(0.5).timeout
			await _shot("24_platoon_march")
		await process_frame
	await create_timer(0.3).timeout
	await _shot("25_after_drop")
	await _boats()


## Boats: docks on our coast, a boat sent at an enemy coastal hex; it shows
## in the channel through the next round, then comes ashore.
func _boats() -> void:
	if main.hud.announcing():
		main.hud.announcer._ok.pressed.emit()
	var st = main.m.sides[0]
	st.unlocked["docks"] = true
	st.money += 300
	st.fuel += 20
	var dock_hex := -1
	for h in st.island.land_hexes():
		if st.island.is_coastal(h) and st.building_at(h) == null:
			dock_hex = h
			break
	st._add_building("docks", dock_hex, main.data, main.m.round_number)
	var enemy = main.m.sides[1]
	var target := -1
	for b in enemy.buildings_sorted():
		if enemy.island.is_coastal(b.hex):
			target = b.hex
			break
	if target < 0:
		target = enemy.island.land_hexes()[0]
	main._refresh()
	main._end_build()
	await create_timer(1.2).timeout
	main.active_launcher = dock_hex
	main._target_click(target)
	main._target_click(enemy.island.grid.neighbors(target)[0])
	main._attack()
	while main.ui == main.Ui.PLAYOUT:
		if main.hud.announcing():
			main.hud.announcer._ok.pressed.emit()
		await process_frame
	await create_timer(0.4).timeout
	while main.hud.announcing():
		main.hud.announcer._ok.pressed.emit()
		await create_timer(0.3).timeout
	main._focus(1)
	main.camera.position.y += 260
	await create_timer(0.3).timeout
	await _shot("26_boat_in_channel")
	main._end_build()
	await create_timer(1.2).timeout
	main._attack()
	var shot := false
	while main.ui == main.Ui.PLAYOUT:
		if main.hud.announcing():
			main.hud.announcer._ok.pressed.emit()
		if not shot and not main.effects.sea_boats.is_empty() and main.viewing == 1:
			shot = true
			await create_timer(0.7).timeout
			await _shot("27_boat_ashore")
		await process_frame
	await create_timer(0.3).timeout
	await _shot("28_after_landing")


func _free_hexes() -> Array:
	var free: Array = []
	for h in main.m.sides[0].island.land_hexes():
		if main.m.sides[0].building_at(h) == null:
			free.append(h)
	return free


func _run() -> void:
	await _frames(10)
	await _shot("01_setup")
	var ai = SimpleAI.new(0, main.data, 99)
	var setup: Dictionary = ai.choose_setup(main.m.view_for(0))
	for h in setup["bases"]:
		main._setup_click(h)
	main.setup_mode = "decoy"
	for h in setup["decoys"]:
		main._setup_click(h)
	main._refresh()
	await _shot("02_setup_placed")
	main.hud.announcer._ok.pressed.emit()   # the Admiral's tip
	await create_timer(0.4).timeout
	await _shot("02b_setup_done_tip")
	main._start_setup_game()
	await create_timer(1.1).timeout   # camera flight
	await _shot("03_build_tip")
	main.hud.announcer._ok.pressed.emit()   # the real OK button
	await create_timer(0.3).timeout
	await _shot("03b_launcher_tip")
	main.tool = "anti_air"
	main._refresh()
	await _shot("04_build_tool")
	var free := _free_hexes()
	main._click(0, free[60])
	main.tool = "basic_launcher"
	main._click(0, free[90])
	main.m.sides[0].money += 60   # capture only: afford the lab as well
	main.tool = "lab"
	main._click(0, free[20])
	main.tool = ""
	var lab = main.m.sides[0].building_at(free[20])
	main._click(0, free[20])
	await _shot("05_lab_selected")
	main._open_research(lab.id)
	await _shot("06_research_panel")
	main.hud.research_panel._tab = "upgrades"
	main.hud.research_panel.show_state(main.m.sides[0], main.data, true)
	await _shot("06b_research_upgrades")
	main.hud.research_panel._tab = "buildings"
	main.hud.research_panel.show_state(main.m.sides[0], main.data, true)
	main._start_research(lab.id, "radar")
	await _shot("07_research_started")
	# Stored research offered on the running project (then put back).
	main.m.sides[0].stored_research = 4
	main._refresh()
	await _shot("07b_stored_points")
	main.m.sides[0].stored_research = 0
	main._refresh()
	main.hud.research_panel.visible = false
	main.hud.status_gauge.set_hits(2.5, 6)   # a battered gauge, for the record
	await _shot("07c_status_gauge")
	main._refresh()
	main.hud._earn_button.button_pressed = true
	main._refresh()
	await _shot("08_earnings")
	main.hud._earn_button.button_pressed = false
	main.hud.show_notice(main.hud.NOTICE_MONEY)
	await _shot("08b_notice")
	main._rotate(1)
	await _shot("09_rotated")
	main._rotate(-1)
	main._end_build()
	await create_timer(0.4).timeout
	await _shot("10a_flight")
	await create_timer(0.8).timeout
	await _shot("10_targeting")
	main._target_click(main.m.sides[1].island.grid.center_index())
	main._refresh()
	await _shot("11_target_set")
	main.hud.esc_menu.open_menu()
	print("esc menu rect ", main.hud.esc_menu.get_global_rect())
	await _shot("12_esc_menu")
	main.hud.esc_menu._show_options()
	await _shot("13_options")
	main.hud.esc_menu._show_rules()
	await _shot("13b_game_rules")
	main.hud.esc_menu.close_menu()
	main._attack()
	await create_timer(2.2).timeout
	await _shot("14a_siren")
	while not main.hud.announcing():
		await process_frame
	await create_timer(0.4).timeout
	await _shot("14_incoming_warning")
	await create_timer(1.0).timeout
	check_still_up()
	main.hud.announcer._ok.pressed.emit()
	await create_timer(0.75).timeout
	await _shot("14b_missile_falling")
	await create_timer(0.35).timeout
	await _shot("14c_explosion")
	while main.ui == main.Ui.PLAYOUT:
		await process_frame
	await create_timer(0.3).timeout
	await _shot("15a_income_report")
	main.hud.announcer._ok.pressed.emit()   # round 2 income report
	main.hud._log_button.button_pressed = true
	await _shot("15_round2_log")
	main.hud._log_button.button_pressed = false
	var hit: Array = main.m.bombed[0].keys()
	if not hit.is_empty():
		main.tool = ""
		main._click(0, int(hit[0]))
		await _shot("16_hit_hex_selected")
	# Capture only: damage two buildings to show the damaged sprites.
	for h in [free[60], free[90]]:
		var b = main.m.sides[0].building_at(h)
		if b != null:
			b.hp = 10
			b.disabled = true
	main.tool = ""
	main.selected = Vector2i(-1, -1)
	main._refresh()
	await _shot("16b_damaged")
	main._focus(1)
	await create_timer(1.0).timeout
	await _shot("17_fog")
	main.hud.toggle_debug(int(main.data.settings["debug_money"]), false)
	main._debug_toggle_fog(true)
	await _shot("18_debug_no_fog")
	main.hud.toggle_debug(0, true)
	main._debug_toggle_fog(false)
	main._focus(0)
	main.hud.zoom_requested.emit(1)
	main.hud.zoom_requested.emit(1)
	await _shot("19_zoomed")
	main.prefs["show_grid"] = true
	main._apply_grid()
	await _shot("20_grid_on")
	main.prefs["show_grid"] = false
	main._apply_grid()
	await _troops()
	quit()
