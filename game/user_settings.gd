## The player's game settings (section 14): the two clocks, decoys per side
## and whether tips show. Defaults and ranges come from data/settings.json;
## the player's choices are kept in user://settings.json.
extends RefCounted

const PATH := "user://settings.json"
const KEYS := ["build_clock_seconds", "targeting_clock_seconds", "decoys_per_side", "show_tips", "tips_done"]


## Defaults from data, overlaid with whatever the player saved, then clamped.
static func load_settings(defaults: Dictionary, path: String = PATH) -> Dictionary:
	var saved := {}
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			saved = parsed
	return sanitize(saved, defaults)


static func save_settings(s: Dictionary, path: String = PATH) -> void:
	var out := {}
	for k in KEYS:
		if s.has(k):
			out[k] = s[k]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(out, "  "))


## Keeps only known keys, fills gaps from the defaults and clamps each value
## to its range. A clock of clock_off_value means the clock is off.
static func sanitize(s: Dictionary, defaults: Dictionary) -> Dictionary:
	var out := {
		"build_clock_seconds": clock_value(s.get("build_clock_seconds", defaults["build_clock_seconds"]), defaults),
		"targeting_clock_seconds": clock_value(s.get("targeting_clock_seconds", defaults["targeting_clock_seconds"]), defaults),
		"decoys_per_side": clampi(int(s.get("decoys_per_side", defaults["decoys_per_side"])),
			int(defaults["decoys_per_side_min"]), int(defaults["decoys_per_side_max"])),
		"show_tips": bool(s.get("show_tips", defaults.get("show_tips", true))),
		"tips_done": [],
	}
	var done = s.get("tips_done", [])
	if done is Array:
		for id in done:
			out["tips_done"].append(String(id))
	return out


static func clock_value(v, defaults: Dictionary) -> int:
	var off := int(defaults["clock_off_value"])
	var step := maxi(1, int(defaults["clock_seconds_step"]))
	var secs := int(v)
	if secs <= off:
		return off
	secs = clampi(secs, step, int(defaults["clock_seconds_max"]))
	return int(round(secs / float(step))) * step


## The settings the rules need when a match is created.
static func match_overrides(s: Dictionary) -> Dictionary:
	return {"decoys_per_side": int(s["decoys_per_side"])}
