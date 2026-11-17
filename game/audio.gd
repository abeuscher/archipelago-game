## Plays a sound only if its file exists. The game generates no audio; every
## sound it wants is listed in data/required_assets.txt.
extends Node

var _players: Dictionary = {}


func play(path: String) -> void:
	var full := path if path.begins_with("res://") else "res://" + path
	var stream: AudioStream = null
	if ResourceLoader.exists(full):
		stream = load(full)
	elif FileAccess.file_exists(full) and full.ends_with(".ogg"):
		stream = AudioStreamOggVorbis.load_from_file(full)
	if stream == null:
		return
	var p: AudioStreamPlayer = _players.get(full)
	if p == null:
		p = AudioStreamPlayer.new()
		add_child(p)
		_players[full] = p
	p.stream = stream
	p.play()
