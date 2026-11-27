## Saved games. Each save is one file in `dir`, written with
## FileAccess.store_var, so every value keeps its type. A save holds the
## campaign level, the match (MatchState.to_save, or null for the start of a
## level), the enemy AI's state and a few things the screen remembers.
##
## The running game always has a current save (`current`): the default
## "Autosave" for a new game, the one loaded, or the last "save as new".
## The game autosaves to it at the start of every build and repair phase,
## just after the battle summary, and when a level is won.
extends RefCounted

const VERSION := 1
const EXT := ".sav"
const DEFAULT_FILE := "autosave"
const DEFAULT_NAME := "Autosave"

static var dir: String = "user://saves/"
## The save the running game writes to (autosaves too). "" until a game starts.
static var current: String = ""
## A save to start from, set just before the match scene loads; read once.
static var pending: Dictionary = {}


static func default_path() -> String:
	return dir.path_join(DEFAULT_FILE + EXT)


## A new file for a save called `name`, not used by any other save.
static func new_path(name: String) -> String:
	var slug := ""
	for ch in name.to_lower():
		slug += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") else "_"
	slug = slug.strip_edges().left(32)
	var stamp := int(Time.get_unix_time_from_system())
	var p := dir.path_join("%s_%d%s" % [slug, stamp, EXT])
	var k := 2
	while FileAccess.file_exists(p):
		p = dir.path_join("%s_%d_%d%s" % [slug, stamp, k, EXT])
		k += 1
	return p


## Writes a save; "" on success, else what went wrong. Written to a
## temporary file first, so a failed write never spoils the old save.
static func write(path: String, save: Dictionary) -> String:
	DirAccess.make_dir_recursive_absolute(dir)
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return "Could not write the save (%s)" % error_string(FileAccess.get_open_error())
	var out := save.duplicate(true)
	out["version"] = VERSION
	out["saved_at"] = int(Time.get_unix_time_from_system())
	f.store_var(out)
	f.close()
	var e := DirAccess.rename_absolute(tmp, path)
	if e != OK:
		return "Could not write the save (%s)" % error_string(e)
	return ""


## A save, or {} if the file is missing, unreadable or from another version.
static func read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var v = f.get_var(false)
	f.close()
	if not (v is Dictionary) or int(v.get("version", -1)) != VERSION:
		return {}
	return v


## Every readable save, newest first: {"path", "name", "level", "level_name",
## "round", "saved_at"}.
static func list() -> Array:
	var out: Array = []
	var da := DirAccess.open(dir)
	if da == null:
		return out
	for file in da.get_files():
		if not file.ends_with(EXT):
			continue
		var p := dir.path_join(file)
		var s := read(p)
		if s.is_empty():
			continue
		out.append({"path": p, "name": String(s.get("name", file.get_basename())), "level": int(s.get("level", 1)),
			"level_name": String(s.get("level_name", "")), "round": int(s.get("round", 0)),
			"saved_at": int(s.get("saved_at", 0))})
	out.sort_custom(func(a, b): return a["saved_at"] > b["saved_at"] or (a["saved_at"] == b["saved_at"] and a["path"] < b["path"]))
	return out


## The most recently written save's path, or "" if there are none.
static func most_recent() -> String:
	var all := list()
	return String(all[0]["path"]) if not all.is_empty() else ""


static func remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	if path == current:
		current = default_path()


## The name a save file goes by, or the default name for the autosave.
static func name_of(path: String) -> String:
	var s := read(path)
	if not s.is_empty():
		return String(s.get("name", DEFAULT_NAME))
	return DEFAULT_NAME if path == default_path() else path.get_file().get_basename()


## One line about a save for the list: "Level 3, round 12 · Nov 27, 14:05".
static func describe(entry: Dictionary) -> String:
	var where := String(entry["level_name"]) if String(entry["level_name"]) != "" else "Level %d" % int(entry["level"])
	if int(entry["round"]) > 0:
		where += ", round %d" % int(entry["round"])
	else:
		where += ", start"
	var t := Time.get_datetime_dict_from_unix_time(int(entry["saved_at"]) + _utc_offset())
	const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	return "%s · %s %d, %02d:%02d" % [where, MONTHS[int(t["month"]) - 1], int(t["day"]), int(t["hour"]), int(t["minute"])]


static func _utc_offset() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60
