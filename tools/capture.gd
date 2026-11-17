## Development aid: runs the real main scene in a window, drives it through
## setup, build, targeting and one playout, and saves screenshots.
##   godot --path . -s tools/capture.gd -- <output_dir> [seed]
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
	# main.gd reads --seed from user args; pass it through.
	var scene: PackedScene = load("res://game/main.tscn")
	main = scene.instantiate()
	main.set_meta("seed_override", int(seed_arg))
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
	main._start_setup_game()
	await _shot("03_build")
	main.tool = "basic_launcher"
	main._refresh()
	await _shot("04_build_tool")
	var free: Array = []
	for h in main.m.sides[0].island.land_hexes():
		if main.m.sides[0].building_at(h) == null:
			free.append(h)
	main._click(0, free[20])
	main.tool = "anti_air"
	main._click(0, free[60])
	main.tool = ""
	main._click(0, free[60])
	await _shot("05_built_selected")
	main._rotate(1)
	await _shot("06_rotated")
	main._rotate(-1)
	main._end_build()
	await _shot("07_targeting")
	main._target_click(main.m.sides[1].island.grid.center_index())
	main._refresh()
	await _shot("08_target_set")
	main._attack()
	await create_timer(2.6).timeout
	await _shot("09_playout")
	while main.ui == main.Ui.PLAYOUT:
		await process_frame
	await _shot("10_round2")
	quit()
