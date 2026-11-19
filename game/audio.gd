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


func _ready() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(SOUNDS_PATH))
	sounds = parsed if parsed is Dictionary else {}
	_music = AudioStreamPlayer.new()
	_music.volume_db = -6.0
	add_child(_music)


## A named effect from sounds.json ("missile_fire", ...), optionally quieter.
func effect(name: String, volume_db: float = 0.0) -> void:
	var path := String(sounds.get("effects", {}).get(name, ""))
	if path != "":
		play(path, volume_db)


## The sound for a building going up, if it has one.
func built(type: String) -> void:
	var path := String(sounds.get("build", {}).get(type, ""))
	if path != "":
		play(path)


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
	p.volume_db = volume_db
	p.play()


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
