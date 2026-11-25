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
		"stronghold_repair": int(data.building("stronghold").get("repair_cost", 0)),
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
		"transport_fuel": int(data.missile("transport")["fuel"]),
		"transport_money": int(data.missile("transport").get("money", 0)),
		"transport_replace": int(data.missile("transport")["replace_money"]),
		"march": int(data.section("troops")["platoon_march"]),
		"march_total": int(data.section("troops")["platoon_march"]) + 1,
		"bunker_range": int(data.section("troops")["bunker_range"]),
		"boat_fuel": int(data.missile("boat")["fuel"]),
		"boat_money": int(data.missile("boat").get("money", 0)),
		"boat_replace": int(data.missile("boat")["replace_money"]),
		"cannon_range": int(data.section("troops")["cannon_range"]),
		"cannon_pct": roundi(float(data.section("troops")["cannon_accuracy"]) * 100.0),
	}


static func _clock(secs: int) -> String:
	return "no time limit" if secs <= 0 else "%d seconds" % secs


static func _buildings(data) -> String:
	var out: Array = []
	for type in data.building_types():
		if not bool(data.building(type).get("buildable", true)):
			continue   # bases and strongholds are placed in setup
		var def: Dictionary = data.building(type)
		if def.has("requires") and not bool(data.research_item(String(def["requires"])).get("available", true)):
			continue   # not in this level
		if not bool(def.get("available", true)):
			continue
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
		if m.has("carries"):
			continue   # the transport is described under Troops
		if name == "nuke":
			if bool(data.research_item("nuclear_silo").get("available", true)):
				out.append("[b]Nuke[/b]: fired from a nuclear silo, %d fuel; a nuke costs %d money and takes a round to build. %d to %d damage on the hex it hits and %d to %d on each hex around it (2 hits and 1 hit on a base); it can destroy a stronghold. Firing it shows the enemy where its silo is. Anti-air hits it %d%% of the time, %d%% with radar." % [
					int(m["fuel"]), int(m.get("replace_money", 0)), int(m["damage_min"] * m.get("centre_factor", 1.0)), int(m["damage_max"] * m.get("centre_factor", 1.0)),
					int(m["damage_min"]), int(m["damage_max"]), roundi(float(m["anti_air_accuracy"]) * 100), roundi(float(m["anti_air_accuracy_with_radar"]) * 100)])
			continue
		if m.has("walks"):
			if bool(data.building("enclave").get("available", true)):
				var ag: Dictionary = data.section("agents")
				out.append("[b]Foreign agent[/b]: sent from an enclave, %d fuel and %d money; one per enclave on the enemy island at a time. He flies in by helicopter and lands on any hex you choose (the enemy sees where), then stays: every round he walks %d hexes, uncovering each, heading for any silo we have seen with a nuke in it, otherwise for ground we haven't seen. He disarms every nuke within %d hex of him; the silo needs a new one. An enemy domestic agent within %d hex kills him. Anti-air hits his helicopter %d%% of the time, %d%% with radar." % [
					int(m["fuel"]), int(m.get("money", 0)), int(m["walks"]), int(m.get("disarm_range", 0)), int(ag["catch_range"]),
					roundi(float(m["anti_air_accuracy"]) * 100), roundi(float(m["anti_air_accuracy_with_radar"]) * 100)])
				out.append("[b]Domestic agent[/b]: each enclave keeps %d on patrol on our island, from the round it is built. He walks %d or %d hexes a round, first to where an enemy agent was seen landing, otherwise to the ground patrolled longest ago, and kills any enemy agent within %d hex of him. Radar and bunkers don't catch agents." % [
					int(ag["domestic_per_enclave"]), int(ag["domestic_walks_min"]), int(ag["domestic_walks_max"]), int(ag["catch_range"])])
			continue
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
