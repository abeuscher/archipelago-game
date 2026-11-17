## Every tunable number, loaded from the JSON files in res://data.
## JSON numbers arrive as floats; accessors cast where an int is meant.
extends RefCounted

const RULES_PATH := "res://data/rules.json"
const SETTINGS_PATH := "res://data/settings.json"
const AI_PATH := "res://data/ai.json"

var rules: Dictionary
var settings: Dictionary
var ai: Dictionary


static func load_default():
	var script: GDScript = load("res://rules/game_data.gd")
	var d = script.new()
	d.rules = _read_json(RULES_PATH)
	d.settings = _read_json(SETTINGS_PATH)
	d.ai = _read_json(AI_PATH) if FileAccess.file_exists(AI_PATH) else {}
	return d


static func _read_json(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	assert(parsed is Dictionary, "Could not parse %s" % path)
	return parsed


func duplicate_data():
	var d = get_script().new()
	d.rules = rules.duplicate(true)
	d.settings = settings.duplicate(true)
	d.ai = ai.duplicate(true)
	return d


## Set a value by dotted path, e.g. "rules.anti_air.engagements" = 1.
## Used by tests and the batch runner for experiments, never by the game.
func set_path(path: String, value) -> void:
	var parts := path.split(".")
	var node
	match parts[0]:
		"rules": node = rules
		"settings": node = settings
		"ai": node = ai
		_: assert(false, "Unknown data root in %s" % path)
	for i in range(1, parts.size() - 1):
		node = node[parts[i]]
	assert(node.has(parts[-1]), "Unknown data key %s" % path)
	node[parts[-1]] = value


func get_path(path: String):
	var parts := path.split(".")
	var node
	match parts[0]:
		"rules": node = rules
		"settings": node = settings
		"ai": node = ai
	for i in range(1, parts.size()):
		node = node[parts[i]]
	return node


# --- Convenience accessors -------------------------------------------------

func section(name: String) -> Dictionary:
	return rules[name]


func num(section_name: String, key: String) -> float:
	return float(rules[section_name][key])


func integer(section_name: String, key: String) -> int:
	return int(rules[section_name][key])


func flag(section_name: String, key: String) -> bool:
	return bool(rules[section_name][key])


func building(type: String) -> Dictionary:
	return rules["buildings"][type]


func has_building(type: String) -> bool:
	return rules["buildings"].has(type)


func building_types() -> Array:
	return rules["buildings"].keys()


func role(type: String) -> String:
	return String(building(type)["role"])


func cost(type: String) -> int:
	return int(building(type)["cost"])


func max_hp(type: String) -> int:
	return int(building(type).get("hp", 0))


func is_weapon(type: String) -> bool:
	return bool(building(type).get("weapon", false))


func is_base_like(type: String) -> bool:
	var r := role(type)
	return r == "base" or r == "decoy"


func missile(type: String) -> Dictionary:
	return rules["missiles"][type]


func missile_types() -> Array:
	return rules["missiles"].keys()


func research_item(item: String) -> Dictionary:
	return rules["research"][item]


func research_items() -> Array:
	return rules["research"].keys()


func setting_int(key: String) -> int:
	return int(settings[key])
