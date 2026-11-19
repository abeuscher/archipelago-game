## Plays sound effects and music, each only if its file exists. The game
## generates no audio; data/sounds.json says which file plays when, and every
## file is listed in data/required_assets.txt.
extends Node

const SOUNDS_PATH := "res://data/sounds.json"
const MUSIC_FADE := 0.8

var sounds: Dictionary = {}
var _players: Dictionary = {}
var _music: AudioStreamPlayer
var _music_path: String = ""
var _fade: Tween


func _ready() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(SOUNDS_PATH))
	sounds = parsed if parsed is Dictionary else {}
	_music = AudioStreamPlayer.new()
	_music.volume_db = -6.0
	add_child(_music)


## A named effect from sounds.json ("missile_fire", ...).
func effect(name: String) -> void:
	var path := String(sounds.get("effects", {}).get(name, ""))
	if path != "":
		play(path)


## The sound for a building going up, if it has one.
func built(type: String) -> void:
	var path := String(sounds.get("build", {}).get(type, ""))
	if path != "":
		play(path)


func play(path: String) -> void:
	var stream := _load(path)
	if stream == null:
		return
	var full := _full(path)
	var p: AudioStreamPlayer = _players.get(full)
	if p == null:
		p = AudioStreamPlayer.new()
		add_child(p)
		_players[full] = p
	p.stream = stream
	p.play()


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
			if stream is AudioStreamOggVorbis:
				stream.loop = true
			_music.stream = stream
			_music.volume_db = -40.0
			_music.play())
	_fade.tween_property(_music, "volume_db", -6.0, MUSIC_FADE)


static func _full(path: String) -> String:
	return path if path.begins_with("res://") else "res://" + path


static func _load(path: String) -> AudioStream:
	var full := _full(path)
	if ResourceLoader.exists(full):
		return load(full)
	if FileAccess.file_exists(full) and full.ends_with(".ogg"):
		return AudioStreamOggVorbis.load_from_file(full)
	return null
