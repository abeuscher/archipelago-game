## Title screen: an island behind the game's title, with Start and Options.
## The island is a picture if assets/title/title.png exists; otherwise a
## generated island drawn in the map style, drifting slowly. Plays the
## island ambience. Continue carries on from the most recent save; Load Game
## lists every save.
extends Node2D

const GameData = preload("res://rules/game_data.gd")
const MatchState = preload("res://rules/match_state.gd")
const BoardView = preload("res://game/board_view.gd")
const OceanView = preload("res://game/ocean_view.gd")
const Palette = preload("res://game/palette.gd")
const Hud = preload("res://game/hud.gd")
const EscMenu = preload("res://game/esc_menu.gd")
const UserSettings = preload("res://game/user_settings.gd")
const RulesText = preload("res://game/rules_text.gd")
const Audio = preload("res://game/audio.gd")
const Textures = preload("res://game/textures.gd")
const SaveGame = preload("res://game/save_game.gd")
const Campaign = preload("res://game/campaign.gd")
const Cursors = preload("res://game/cursors.gd")

const PICTURE := "res://assets/title/title.png"
const MAIN_SCENE := "res://game/main.tscn"
const DRIFT := 40.0          ## how far the camera drifts, in pixels
const DRIFT_SECONDS := 14.0  ## one slow loop of the drift

var data
var prefs: Dictionary
var camera: Camera2D
var menu
var audio
var _centre: Vector2
var _time: float = 0.0


func _ready() -> void:
	Cursors.install(self)   # the gloved hand over buttons
	data = GameData.load_default()
	prefs = UserSettings.load_settings(data.settings)
	RenderingServer.set_default_clear_color(Palette.SEA)
	audio = Audio.new()
	add_child(audio)
	Audio.set_master_volume(float(prefs["volume"]))
	audio.start_ambient()
	audio.set_closeness(float(audio.sounds.get("ambient", {}).get("title_closeness", 0.4)))

	var ui := CanvasLayer.new()
	add_child(ui)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = Hud.make_theme()
	ui.add_child(root)

	var tex: Texture2D = Textures.load_texture(PICTURE) if FileAccess.file_exists(PICTURE) else null
	if tex != null:
		var pic := TextureRect.new()
		pic.texture = tex
		pic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(pic)
	else:
		_island()

	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 18)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(col)
	var title := Label.new()
	title.text = "ARCHIPELAGO"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", Hud.bold_font())
	title.add_theme_font_size_override("font_size", 96)
	title.add_theme_color_override("font_color", Color(0.98, 0.95, 0.85))
	title.add_theme_color_override("font_outline_color", Color(0.10, 0.09, 0.07))
	title.add_theme_constant_override("outline_size", 22)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	title.add_theme_constant_override("shadow_offset_y", 6)
	col.add_child(title)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 150)
	col.add_child(gap)
	var latest := SaveGame.most_recent()
	if latest != "":
		var cont := _button("CONTINUE", true, func(): _load(latest))
		cont.tooltip_text = SaveGame.describe(SaveGame.list()[0])
		col.add_child(cont)
	var start := _button("NEW GAME", latest == "", _start)
	col.add_child(start)
	col.add_child(_button("LOAD GAME", false, func(): menu.open_saves()))
	col.add_child(_button("OPTIONS", false, _options))

	menu = EscMenu.new()
	menu.options_only = true
	root.add_child(menu)
	menu.setup(data.settings, prefs)
	menu.rules_text = RulesText.build(data, int(prefs["build_clock_seconds"]), int(prefs["targeting_clock_seconds"]))
	menu.settings_changed.connect(func(s: Dictionary):
		prefs = s
		UserSettings.save_settings(prefs)
		menu.setup(data.settings, prefs))
	menu.quit_requested.connect(func(): get_tree().quit())
	menu.load_requested.connect(_load)


## A generated island in the map style, with sea round it.
func _island() -> void:
	var m = MatchState.create(data, int(Time.get_unix_time_from_system()) & 0x7FFFFFFF)
	var ocean = OceanView.new()
	add_child(ocean)
	var board = BoardView.new()
	board.setup(m.sides[0].island.grid)
	board.set_tiles(BoardView.own_tiles(m.sides[0], data))
	add_child(board)
	ocean.rebuild([board])
	camera = Camera2D.new()
	add_child(camera)
	var r: Rect2 = board.bounds()
	_centre = r.get_center()
	var vp := get_viewport_rect().size
	var z := minf(vp.x / r.size.x, vp.y / r.size.y) * 0.72   # sea all round
	camera.zoom = Vector2(z, z)
	camera.position = _centre


func _process(delta: float) -> void:
	if camera == null:
		return
	_time += delta
	var a := TAU * _time / DRIFT_SECONDS
	camera.position = _centre + Vector2(cos(a), sin(a) * 0.6) * DRIFT


func _button(text: String, primary: bool, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(260, 54)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_override("font", Hud.bold_font())
	b.add_theme_font_size_override("font_size", 22)
	if primary:
		b.add_theme_color_override("font_color", Color(1, 0.96, 0.9))
		b.add_theme_stylebox_override("normal", Hud._red_box(Color(0.86, 0.30, 0.20)))
		b.add_theme_stylebox_override("hover", Hud._red_box(Color(0.94, 0.40, 0.28)))
		b.add_theme_stylebox_override("pressed", Hud._red_box(Color(0.70, 0.22, 0.14)))
	b.pressed.connect(action)
	return b


## A new campaign from level 1. It autosaves to the default save.
func _start() -> void:
	Campaign.restart()
	SaveGame.current = SaveGame.default_path()
	SaveGame.pending = {}
	get_tree().change_scene_to_file(MAIN_SCENE)


## Carry on from a save; it becomes the one the game autosaves to.
func _load(path: String) -> void:
	var s := SaveGame.read(path)
	if s.is_empty():
		return
	SaveGame.pending = s
	SaveGame.current = path
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_SCENE)


func _options() -> void:
	menu.open_menu()   # opens straight on Options here
