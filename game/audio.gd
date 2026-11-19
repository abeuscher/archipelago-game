## Plays sound effects, the island ambience and music, each only if its file
## exists. data/sounds.json says which file plays when, and every file is
## listed in data/required_assets.txt.
##
## The ambience is a few looping layers (the sea, the island) plus the odd
## gull call now and then. Each layer has a volume for zoomed right out and
## one for zoomed right in; set_closeness() moves between them.
extends Node

const SOUNDS_PATH := "res://data/sounds.json"
const MUSIC_FADE := 0.8
const AMBIENT_GLIDE := 3.0   ## how quickly ambient volumes follow the zoom, per second
const SILENT_DB := -60.0

var sounds: Dictionary = {}
var _players: Dictionary = {}
var _music: AudioStreamPlayer
var _music_path: String = ""
var _fade: Tween

var _ambient_on := false
var _loops: Dictionary = {}       # layer name -> AudioStreamPlayer
var _closeness := 0.5
var _call_player: AudioStreamPlayer
var _call_wait := 0.0
var _ambient_fade := 0.0          # 0..1, eases the ambience in when it starts

var _theme: AudioStreamPlayer     # the main theme (sounds.json "theme")
var _theme_wanted := false        # the game is in a phase that has it
var _theme_level := 0.0           # 0..1, how far faded in
var _theme_resting := false       # taking a break between plays
var _theme_timer := 0.0           # seconds left of this play or rest


func _ready() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(SOUNDS_PATH))
	sounds = parsed if parsed is Dictionary else {}
	_music = AudioStreamPlayer.new()
	_music.volume_db = -6.0
	add_child(_music)
	# Every button clicks: those there now and any made later.
	get_tree().node_added.connect(_hook_button)
	_hook_all.call_deferred(get_tree().root)


func _hook_all(n: Node) -> void:
	_hook_button(n)
	for c in n.get_children():
		_hook_all(c)


func _hook_button(n: Node) -> void:
	if n is BaseButton and not n.pressed.is_connected(_click):
		n.pressed.connect(_click)


func _click() -> void:
	effect("click")


## A named effect from sounds.json ("missile_fire", ...), optionally quieter.
func effect(name: String, volume_db: float = 0.0) -> void:
	var path := String(sounds.get("effects", {}).get(name, ""))
	if path != "":
		play(path, volume_db)


## The sound for a building going up: its own, or the shared construction
## sound ("default").
func built(type: String) -> void:
	var b: Dictionary = sounds.get("build", {})
	var path := String(b.get(type, b.get("default", "")))
	if path != "":
		play(path)


## Pauses or resumes a named effect that is playing (the countdown).
func pause_effect(name: String, paused: bool) -> void:
	var p: AudioStreamPlayer = _players.get(_full(String(sounds.get("effects", {}).get(name, "-"))))
	if p != null:
		p.stream_paused = paused


func stop_effect(name: String) -> void:
	var p: AudioStreamPlayer = _players.get(_full(String(sounds.get("effects", {}).get(name, "-"))))
	if p != null:
		p.stop()


func play(path: String, volume_db: float = 0.0) -> void:
	var stream := _load(path)
	if stream == null:
		return
	var full := _full(path)
	var p: AudioStreamPlayer = _players.get(full)
	if p == null:
		p = AudioStreamPlayer.new()
		p.max_polyphony = 6   # several missiles can land at once
		add_child(p)
		_players[full] = p
	p.stream = stream
	p.volume_db = volume_db + float(sounds.get("effects_db", 0.0))   # the effects' overall level
	p.stream_paused = false
	p.play()


## The main volume, 0 (silent) to 1 (full), on the master bus.
static func set_master_volume(v: float) -> void:
	AudioServer.set_bus_mute(0, v <= 0.001)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(v, 0.001)))


# --- Ambience ----------------------------------------------------------------

## Starts the looping ambience layers and the occasional calls, easing in.
func start_ambient() -> void:
	if _ambient_on:
		return
	_ambient_on = true
	_ambient_fade = 0.0
	var amb: Dictionary = sounds.get("ambient", {})
	for layer in amb.get("loops", {}):
		var spec: Dictionary = amb["loops"][layer]
		var stream := _load(String(spec.get("file", "")))
		if stream == null:
			continue
		_set_loop(stream)
		var p := AudioStreamPlayer.new()
		p.stream = stream
		p.volume_db = SILENT_DB
		add_child(p)
		p.play(randf() * stream.get_length())   # don't always start at the same wave
		_loops[layer] = p
	_call_player = AudioStreamPlayer.new()
	add_child(_call_player)
	_call_wait = randf_range(2.0, 6.0)


func stop_ambient() -> void:
	_ambient_on = false
	for p in _loops.values():
		p.queue_free()
	_loops.clear()
	if _call_player != null:
		_call_player.queue_free()
		_call_player = null


## How close the view is: 0 = zoomed right out, 1 = zoomed right in.
func set_closeness(c: float) -> void:
	_closeness = clampf(c, 0.0, 1.0)


func _process(delta: float) -> void:
	_update_theme(delta)
	if not _ambient_on:
		return
	_ambient_fade = minf(1.0, _ambient_fade + delta / 2.5)
	var amb: Dictionary = sounds.get("ambient", {})
	for layer in _loops:
		var p: AudioStreamPlayer = _loops[layer]
		var target := _ambient_db(amb["loops"][layer])
		p.volume_db = lerpf(p.volume_db, target, minf(1.0, delta * AMBIENT_GLIDE))
	var calls: Dictionary = amb.get("calls", {})
	var files: Array = calls.get("files", [])
	if files.is_empty() or _call_player == null:
		return
	_call_wait -= delta
	if _call_wait <= 0.0:
		var gap: Array = calls.get("every_seconds", [12, 30])
		_call_wait = randf_range(float(gap[0]), float(gap[1]))
		var stream := _load(String(files[randi() % files.size()]))
		if stream != null:
			_call_player.stream = stream
			_call_player.pitch_scale = randf_range(0.9, 1.1)
			_call_player.volume_db = _ambient_db(calls) + randf_range(-4.0, 0.0)
			_call_player.play()


## A layer's volume at the current zoom, faded in at the start.
func _ambient_db(spec: Dictionary) -> float:
	var db := lerpf(float(spec.get("far_db", -20)), float(spec.get("near_db", -12)), _closeness)
	return lerpf(SILENT_DB, db, _ambient_fade)


# --- Main theme ------------------------------------------------------------------

## Whether the phase wants the main theme. It fades in or out, never cuts,
## and picks up where it left off when it comes back.
func set_theme(on: bool) -> void:
	_theme_wanted = on
	if not on or _theme != null:
		return
	var cfg: Dictionary = sounds.get("theme", {})
	var stream := _load(String(cfg.get("file", "")))
	if stream == null:
		return
	_set_loop(stream)
	_theme = AudioStreamPlayer.new()
	_theme.stream = stream
	_theme.volume_db = SILENT_DB
	add_child(_theme)
	_theme.play()
	_theme_resting = false
	_theme_timer = _theme_range("play_seconds", [150, 240])


func _update_theme(delta: float) -> void:
	if _theme == null:
		return
	var cfg: Dictionary = sounds.get("theme", {})
	# Plays for a while, then rests a while, then plays again.
	_theme_timer -= delta
	if _theme_timer <= 0.0:
		_theme_resting = not _theme_resting
		_theme_timer = _theme_range("rest_seconds" if _theme_resting else "play_seconds",
			[45, 90] if _theme_resting else [150, 240])
	var target := 1.0 if _theme_wanted and not _theme_resting else 0.0
	var step := delta / maxf(float(cfg.get("fade_seconds", 4.0)), 0.1)
	_theme_level = move_toward(_theme_level, target, step)
	# Faded right out, it holds its place; faded in again, it carries on.
	_theme.stream_paused = _theme_level <= 0.0 and target <= 0.0
	_theme.volume_db = float(cfg.get("volume_db", -12)) + linear_to_db(maxf(_theme_level * _theme_level, 0.0001))


func _theme_range(key: String, fallback: Array) -> float:
	var r: Array = sounds.get("theme", {}).get(key, fallback)
	return randf_range(float(r[0]), float(r[1]))


# --- Music ---------------------------------------------------------------------

## Starts a theme from sounds.json ("intro", "build", "battle"), fading
## between tracks; the same theme carries on without restarting.
func music(theme: String) -> void:
	var path := String(sounds.get("music", {}).get(theme, ""))
	if path == _music_path:
		return
	_music_path = path
	var stream := _load(path) if path != "" else null
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = create_tween()
	if _music.playing:
		_fade.tween_property(_music, "volume_db", -40.0, MUSIC_FADE)
	_fade.tween_callback(func():
		_music.stop()
		if stream != null:
			_set_loop(stream)
			_music.stream = stream
			_music.volume_db = -40.0
			_music.play())
	_fade.tween_property(_music, "volume_db", -6.0, MUSIC_FADE)


static func _set_loop(stream: AudioStream) -> void:
	if stream is AudioStreamOggVorbis:
		stream.loop = true
	elif stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = int(round(stream.get_length() * stream.mix_rate))


static func _full(path: String) -> String:
	return path if path.begins_with("res://") else "res://" + path


static func _load(path: String) -> AudioStream:
	if path == "":
		return null
	var full := _full(path)
	if ResourceLoader.exists(full):
		return load(full)
	if FileAccess.file_exists(full) and full.ends_with(".ogg"):
		return AudioStreamOggVorbis.load_from_file(full)
	return null
