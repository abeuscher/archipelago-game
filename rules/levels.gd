## The campaign's levels (data/levels.json): what each one changes in the
## data, the money a win carries into the next, and the line that opens it.
extends RefCounted

const PATH := "res://data/levels.json"

static var _levels: Array = []


static func all() -> Array:
	if _levels.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		assert(parsed is Dictionary, "Could not parse " + PATH)
		_levels = parsed["levels"]
	return _levels


static func count() -> int:
	return all().size()


## Level n (1-based), clamped to the levels there are.
static func level(n: int) -> Dictionary:
	return all()[clampi(n, 1, count()) - 1]


## A copy of game_data with level n's changes applied.
static func data_for(game_data, n: int):
	var d = game_data.duplicate_data()
	var changes: Dictionary = level(n).get("set", {})
	for path in changes:
		d.set_path(path, changes[path])
	return d
