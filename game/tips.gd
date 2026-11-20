## Tips that introduce the game as the player goes (section 14). The list,
## order, wording and speaker are in data/dialogue.json; the conditions are
## named here.
## One tip shows at a time. A tip is done when the player dismisses it with
## "Don't show this again" ticked, or when its condition stops holding in the
## same phase it was shown in (for example, the anti-air tip once anti-air is
## built). Done tips never come back until tips are reset. Dismissing with
## the box unticked only hides the tip for the rest of that phase.
extends RefCounted

const PATH := "res://data/dialogue.json"


static func load_tips(data, path: String = PATH) -> Array:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	var out: Array = []
	if not (parsed is Dictionary):
		return out
	var fill := placeholders(data)
	for t in parsed.get("tips", []):
		out.append({"id": String(t["id"]), "when": String(t["when"]), "text": String(t["text"]).format(fill),
			"anchor": String(t.get("anchor", "")), "arrow": String(t.get("arrow", "")), "arrows": Array(t.get("arrows", [])), "pause": bool(t.get("pause", false)),
			"character": String(t.get("character", "")), "from_round": int(t.get("from_round", 0))})
	return out


## The characters' lines for game moments ("announcements" in
## dialogue.json): key -> {"character", "text"}.
static func load_lines(path: String = PATH) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return parsed.get("announcements", {})
	return {}


static func placeholders(data) -> Dictionary:
	var aa: Dictionary = data.section("anti_air")
	return {
		"aa_radius": int(aa["radius"]),
		"aa_engagements": int(aa["engagements"]),
		"acc": roundi(float(aa["accuracy"]) * 100.0),
		"acc_radar": roundi(float(aa["accuracy_with_radar"]) * 100.0),
		"base_hits": int(data.building("base")["hits_to_destroy"]),
		"decoy_hits": int(data.building("decoy")["hits_to_destroy"]),
		"refinery_fuel": int(data.building("refinery")["produces"]["fuel"]),
		"repair_pct": roundi(data.num("damage", "repair_cost_fraction") * 100.0),
	}


## ctx keys: phase ("setup", "build", "targeting", ...), round, setup_complete, clock_on,
## has_lab, research_open,
## has_launcher, has_anti_air, radar_started, suspected_base_seen,
## own_damaged, launcher_targeted, fuel_short.
static func holds(when: String, ctx: Dictionary) -> bool:
	var phase := String(ctx.get("phase", ""))
	match when:
		"setup":
			return phase == "setup"
		"setup_complete":
			return phase == "setup" and ctx.get("setup_complete", false)
		"build_clock_running":
			return phase == "build" and ctx.get("clock_on", false)
		"build_without_launcher":
			return phase == "build" and not ctx.get("has_launcher", true)
		"build_without_anti_air":
			return phase == "build" and not ctx.get("has_anti_air", false)
		"troop_selected":
			return phase == "targeting" and ctx.get("troop_selected", false)
		"research_open":
			return phase == "build" and ctx.get("research_open", false)
		"radar_not_started":
			# Once there is a lab to research with.
			return phase == "build" and ctx.get("has_lab", false) and not ctx.get("radar_started", false)
		"targeting":
			return phase == "targeting"
		"suspected_base_seen":
			return phase in ["build", "targeting"] and ctx.get("suspected_base_seen", false)
		"launcher_targeted":
			return phase == "build" and ctx.get("launcher_targeted", false)
		"own_damaged":
			return phase == "build" and ctx.get("own_damaged", false)
		"fuel_short":
			return phase == "targeting" and ctx.get("fuel_short", false)
	return false


## Returns {"current": tip or null, "done": Array of ids}. `current` is the
## tip on screen before this update (or null). `skip` lists tips hidden for
## now but not done.
static func update(tips: Array, ctx: Dictionary, done: Array, current, skip: Array = []) -> Dictionary:
	var new_done := done.duplicate()
	var phase := String(ctx.get("phase", ""))
	if current != null and not holds(String(current["when"]), ctx) 			and String(current.get("shown_in", "")) == phase and not new_done.has(current["id"]):
		new_done.append(current["id"])
	for t in tips:
		if new_done.has(t["id"]) or skip.has(t["id"]):
			continue
		if int(ctx.get("round", 0)) < int(t.get("from_round", 0)):
			continue
		if holds(String(t["when"]), ctx):
			var shown: Dictionary = t.duplicate()
			shown["shown_in"] = phase
			return {"current": shown, "done": new_done}
	return {"current": null, "done": new_done}
