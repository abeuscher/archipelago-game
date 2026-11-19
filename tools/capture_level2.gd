## Development aid: starts level 2 (as the debug skip does), muted, and saves
## screenshots of the stronghold's introduction, setup, and the Admiral's
## warning when a missile gives the enemy's stronghold away.
##   godot --path . -s tools/capture_level2.gd -- <output_dir> [seed]
extends SceneTree

const SimpleAI = preload("res://ai/simple_ai.gd")
const Campaign = preload("res://game/campaign.gd")

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
	Campaign.restart()
	Campaign.advance()   # level 2, with level 1's award
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
	root.get_viewport().get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
	print("saved ", name)


func _free_hexes() -> Array:
	var free: Array = []
	for h in main.m.sides[0].island.land_hexes():
		if main.m.sides[0].building_at(h) == null:
			free.append(h)
	return free


func _ok() -> void:
	if main.hud.announcing():
		main.hud.announcer._ok.pressed.emit()
		await create_timer(0.3).timeout


func _run() -> void:
	AudioServer.set_bus_mute(0, true)
	await _frames(10)
	await _shot("L2_01_intro")
	await _ok()
	var ai = SimpleAI.new(0, main.data, 99)
	var setup: Dictionary = ai.choose_setup(main.m.view_for(0))
	main._setup_click(setup["bases"][0])
	main._refresh()
	main.selected = Vector2i(0, setup["bases"][0])
	main._refresh()
	await _shot("L2_02_stronghold_placed")
	for k in range(1, setup["bases"].size()):
		main._setup_click(setup["bases"][k])
		main._refresh()
	main.selected = Vector2i(-1, -1)
	main._refresh()
	await _shot("L2_02b_all_placed")
	await _ok()
	main._start_setup_game()
	await create_timer(1.1).timeout
	while main.hud.announcing():
		await _ok()
	# A launcher aimed at the enemy's stronghold.
	var st = main.m.sides[0]
	st.fuel += 20
	var lau_hex: int = _free_hexes()[30]
	st._add_building("basic_launcher", lau_hex, main.data, main.m.round_number)
	for k in 5:   # a crowded weapons list
		st._add_building("basic_launcher", _free_hexes()[50 + k * 9], main.data, main.m.round_number)
	st.unlocked["airport"] = true
	st._add_building("airport", _free_hexes()[12], main.data, main.m.round_number)
	main._refresh()
	main._end_build()
	await create_timer(1.2).timeout
	await _ok()
	await _shot("L2_02c_targeting_tiles")
	main._attack_pressed()   # nothing aimed: Ginger's warning
	await create_timer(0.4).timeout
	await _shot("L2_02d_attack_warning")
	await _ok()
	var fort: int = -1
	for b in main.m.sides[1].buildings.values():
		if b.type == "stronghold":
			fort = b.hex
	main.active_launcher = lau_hex
	main._target_click(fort)
	main._refresh()
	main._attack()
	# Through the playout, answering each announcement, until the next round.
	var n := 0
	for k in 240:
		await create_timer(0.25).timeout
		if main.hud.announcing():
			var t: String = main.hud.announcer._text.text
			print("announcing: ", t.left(90))
			if t.contains("stronghold") or t.contains("battle summary"):
				await _shot("L2_04_announce_%d" % n)
				n += 1
			await _ok()
		elif main.ui == main.Ui.BUILD and k > 8:
			break
	await _shot("L2_03_after_hit")
	main.selected = Vector2i(1, fort)
	main._fly_to(1, 0.0)
	main._refresh()
	await create_timer(0.3).timeout
	await _shot("L2_05_enemy_stronghold_selected")
	main.hud.toggle_debug(100, false)
	await _shot("L2_06_debug_panel")
	quit(0)
