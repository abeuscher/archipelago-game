## Projections for the interface: what the next round start will pay, and how
## fast each research project is moving. Uses only the rules' own state
## methods on a copy, so it can't disagree with what actually happens.
extends RefCounted


## What begin_round would do next round, without touching `st`.
## Returns {"income": {money, fuel, research} or {}, "lines": Array[String],
## "research_completed": Array, "round": int}.
static func project(st, data, current_round: int) -> Dictionary:
	var future = st.duplicate_state()
	var next_round := current_round + 1
	var res: Dictionary = future.begin_round(next_round, data)
	var out := {"income": res["income"], "lines": [], "research_completed": res["research_completed"], "round": next_round}
	if res["income"].is_empty():
		out["lines"].append("No income until round %d." % data.integer("economy", "income_from_round"))
		return out
	# `future` now has last round's repairs finished, so its buildings are in
	# the state income was paid from.
	var eco: Dictionary = data.section("economy")
	var rows := {}
	for res_name in ["money", "fuel", "research"]:
		rows[res_name] = []
		var base := int(eco["baseline_" + res_name])
		if base != 0:
			rows[res_name].append("%d baseline" % base)
	var groups := {}
	for b in future.buildings_sorted():
		var produces: Dictionary = data.building(b.type).get("produces", {})
		for res_name in produces:
			var v := int(produces[res_name])
			var half: bool = future.is_half_strength(b, data)
			if half:
				v = future.half_income(v, data)
			var key := "%s|%s|%d|%s" % [res_name, b.type, v, half]
			if not groups.has(key):
				groups[key] = {"res": res_name, "type": b.type, "each": v, "half": half, "n": 0}
			groups[key]["n"] += 1
	for key in groups:
		var g: Dictionary = groups[key]
		rows[g["res"]].append("%d × %d %s%s" % [g["n"], g["each"], String(g["type"]).replace("_", " "), " (half strength)" if g["half"] else ""])
	var inc: Dictionary = res["income"]
	var labels := {"money": "Money", "fuel": "Fuel", "research": "Research"}
	for res_name in ["money", "fuel", "research"]:
		var detail := ", ".join(rows[res_name])
		out["lines"].append("%s +%d%s" % [labels[res_name], int(inc[res_name]), ("   (" + detail + ")") if detail != "" else ""])
	if future.count_role(data, "lab") == 0 and st.projects.is_empty():
		out["lines"].append("Research points need a lab.")
	for item in res["research_completed"]:
		out["lines"].append("Research completes: %s." % String(item).replace("_", " ").capitalize())
	return out


## Points per round going to `item` at the next round start, as things stand
## (repairs ordered this round count as finished, as they will be by then).
static func research_rate(st_now, data, item: String) -> int:
	var st = st_now.duplicate_state()
	for b in st.buildings.values():
		if b.repairing:
			b.repairing = false
			b.disabled = false
	var p = st.project_for_item(item)
	if p == null:
		return 0
	var oldest = st.oldest_project()
	var is_oldest: bool = oldest != null and oldest["item"] == item
	var rate := 0
	if is_oldest:
		rate += data.integer("economy", "baseline_research")
	for lab in st.of_role(data, "lab"):
		var own = st.project_for_lab(lab.id)
		var helps: bool = (own != null and own["item"] == item) or (own == null and is_oldest)
		if helps:
			var pts := int(data.building(lab.type)["produces"].get("research", 0))
			if st.is_half_strength(lab, data):
				pts = st.half_income(pts, data)
			rate += pts
	return rate


## Rounds until `item` completes at the current rate, or -1 if it is stalled.
static func rounds_left(st, data, item: String) -> int:
	var p = st.project_for_item(item)
	if p == null:
		return -1
	var rate := research_rate(st, data, item)
	if rate <= 0:
		return -1
	var need := int(data.research_item(item)["points"]) - int(p["progress"])
	return maxi(1, ceili(need / float(rate)))
