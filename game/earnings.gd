## Projections for the interface: what the next round start will pay, and how
## long until research points cover an item. Uses only the rules' own state
## methods on a copy, so it can't disagree with what actually happens.
extends RefCounted


## What begin_round would do next round, without touching `st`.
## Returns {"income": {money, fuel, research} or {}, "lines": Array[String],
## "round": int}.
static func project(st, data, current_round: int) -> Dictionary:
	var future = st.duplicate_state()
	var next_round := current_round + 1
	var res: Dictionary = future.begin_round(next_round, data)
	var out := {"income": res["income"], "lines": [], "round": next_round}
	if res["income"].is_empty():
		out["lines"].append("No income until round %d." % data.integer("economy", "income_from_round"))
		return out
	var eco: Dictionary = data.section("economy")
	var rows := {}
	for res_name in ["money", "fuel", "research"]:
		rows[res_name] = []
		var base := int(eco["baseline_" + res_name])
		if base != 0:
			rows[res_name].append("%d baseline" % base)
	# Income is paid from the buildings as they stood over this round: with
	# repairs taking buildings out, that is before the repairs finish.
	var basis = st.duplicate_state() if data.flag("damage", "repair_takes_building_out") else future
	var groups := {}
	for b in basis.buildings_sorted():
		var produces: Dictionary = basis.produces_of(b.type, data)
		for res_name in produces:
			var v: int = basis.output_of(b, int(produces[res_name]), data)
			var state := "out" if basis.out_for_repair(b, data) else ("half" if basis.is_half_strength(b, data) else "")
			var key := "%s|%s|%d|%s" % [res_name, b.type, v, state]
			if not groups.has(key):
				groups[key] = {"res": res_name, "type": b.type, "each": v, "state": state, "n": 0}
			groups[key]["n"] += 1
	var notes := {"out": " (under repair)", "half": " (half strength)", "": ""}
	for key in groups:
		var g: Dictionary = groups[key]
		rows[g["res"]].append("%d × %d %s%s" % [g["n"], g["each"], String(g["type"]).replace("_", " "), notes[g["state"]]])
	var inc: Dictionary = res["income"]
	var labels := {"money": "Money", "fuel": "Fuel", "research": "Research"}
	for res_name in ["money", "fuel", "research"]:
		var detail := ", ".join(rows[res_name])
		out["lines"].append("%s +%d%s" % [labels[res_name], int(inc[res_name]), ("   (" + detail + ")") if detail != "" else ""])
	if future.count_role(data, "lab") == 0:
		out["lines"].append("Research points need a lab.")
	return out


## Rounds until the research points on hand, plus each round's points as
## things stand, cover `item`: 0 if they already do, -1 if no points are
## coming in.
static func rounds_to_afford(st, data, item: String) -> int:
	var need: int = int(data.research_item(item)["points"]) - int(st.research)
	if need <= 0:
		return 0
	var rate := int(st.compute_income(data)["research"])
	if rate <= 0:
		return -1
	return ceili(need / float(rate))
