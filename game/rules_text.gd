## The Game Rules page (Options): the prose in data/game_rules.txt with its
## numbers and lists filled in from the rules data, so it always matches the
## game as configured.
extends RefCounted

const PATH := "res://data/game_rules.txt"
const Pieces = preload("res://game/pieces.gd")


## build_clock / targeting_clock: the player's clocks in seconds (0 = off).
static func build(data, build_clock: int, targeting_clock: int) -> String:
	var text := FileAccess.get_file_as_string(PATH)
	return text.format(values(data, build_clock, targeting_clock))


static func values(data, build_clock: int, targeting_clock: int) -> Dictionary:
	var eco: Dictionary = data.section("economy")
	var aa: Dictionary = data.section("anti_air")
	var ranges: Array = data.section("radar")["range_by_level"]
	return {
		"bases": data.integer("bases", "per_side"),
		"decoy_cost": data.cost("decoy"),
		"start_money": int(eco["start_money"]),
		"start_fuel": int(eco["start_fuel"]),
		"income_from": int(eco["income_from_round"]),
		"baseline_money": int(eco["baseline_money"]),
		"baseline_fuel": int(eco["baseline_fuel"]),
		"build_clock": _clock(build_clock),
		"targeting_clock": _clock(targeting_clock),
		"base_hits": int(data.building("base")["hits_to_destroy"]),
		"decoy_hits": int(data.building("decoy")["hits_to_destroy"]),
		"aa_radius": int(aa["radius"]),
		"aa_engagements": int(aa["engagements"]),
		"aa_engagements_up": int(aa["engagements_upgraded"]),
		"acc": roundi(float(aa["accuracy"]) * 100.0),
		"acc_radar": roundi(float(aa["accuracy_with_radar"]) * 100.0),
		"radar_ranges": ", ".join(ranges.map(func(r): return str(int(r)))),
		"repair_pct": roundi(data.num("damage", "repair_cost_fraction") * 100.0),
		"lab_points": int(data.building("lab")["produces"]["research"]),
		"building_list": _buildings(data),
		"missile_list": _missiles(data),
		"research_list": _research(data),
	}


static func _clock(secs: int) -> String:
	return "no time limit" if secs <= 0 else "%d seconds" % secs


static func _buildings(data) -> String:
	var out: Array = []
	for type in data.building_types():
		if type == "base":
			continue
		var def: Dictionary = data.building(type)
		var bits: Array = ["%d money" % int(def["cost"])]
		var produces: Dictionary = def.get("produces", {})
		for res in produces:
			bits.append("makes %d %s a round" % [int(produces[res]), res])
		if def.has("requires"):
			bits.append("needs %s research" % Pieces.research_name(String(def["requires"])))
		out.append("[b]%s[/b] (%s). %s" % [Pieces.display_name(type), ", ".join(bits), Pieces.BUILDING_TEXT.get(type, "")])
	return "\n".join(out)


static func _missiles(data) -> String:
	var out: Array = []
	for name in data.section("missiles"):
		var m: Dictionary = data.missile(name)
		var bits: Array = ["%d fuel" % int(m["fuel"])]
		if int(m["damage_max"]) > 0:
			bits.append("%d to %d damage" % [int(m["damage_min"]), int(m["damage_max"])])
		else:
			bits.append("no damage")
		match int(m["blast_radius"]):
			0: bits.append("hits one hex")
			-1: pass
			_: bits.append("blast of %d hex around" % int(m["blast_radius"]))
		bits.append("sees %d hex%s around" % [int(m["view_radius"]), "" if int(m["view_radius"]) == 1 else "es"])
		if m.has("requires"):
			bits.append("needs %s research" % Pieces.research_name(String(m["requires"])))
		out.append("[b]%s[/b]: %s." % [Pieces.MISSILE_NAMES.get(name, name), ", ".join(bits)])
	return "\n".join(out)


static func _research(data) -> String:
	var out: Array = []
	for item in data.section("research"):
		var r: Dictionary = data.research_item(item)
		if not bool(r.get("available", true)):
			continue
		out.append("[b]%s[/b] (%d money, %d points). %s" % [Pieces.research_name(item), int(r["cost"]), int(r["points"]),
			Pieces.RESEARCH_TEXT.get(item, "")])
	return "\n".join(out)
