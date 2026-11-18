## Interface logic that needs no rendering: settings, tips, the earnings
## projection, research rates, the timer readout and base button colours.
extends "res://tests/test_case.gd"

const UserSettings = preload("res://game/user_settings.gd")
const Tips = preload("res://game/tips.gd")
const Earnings = preload("res://game/earnings.gd")
const SevenSeg = preload("res://game/seven_seg.gd")
const StripButton = preload("res://game/strip_button.gd")


func test_settings_defaults_and_clamping() -> void:
	var d = data()
	var s: Dictionary = UserSettings.sanitize({}, d.settings)
	eq(s["build_clock_seconds"], 120, "default build clock")
	eq(s["targeting_clock_seconds"], 60, "default targeting clock")
	eq(s["decoys_per_side"], 1, "default decoys")
	eq(s["show_tips"], true, "tips on by default")
	s = UserSettings.sanitize({"decoys_per_side": 9, "build_clock_seconds": 7, "targeting_clock_seconds": 5000, "junk": 1}, d.settings)
	eq(s["decoys_per_side"], 3, "decoys clamped to max")
	eq(s["build_clock_seconds"], 10, "clock rounded to the step")
	eq(s["targeting_clock_seconds"], 600, "clock clamped to max")
	check(not s.has("junk"), "unknown keys dropped")
	s = UserSettings.sanitize({"build_clock_seconds": 0, "decoys_per_side": 0}, d.settings)
	eq(s["build_clock_seconds"], 0, "0 means off")
	eq(s["decoys_per_side"], 1, "decoys clamped to min")
	eq(UserSettings.match_overrides(s), {"decoys_per_side": 1}, "only rules settings go to the match")


func test_settings_round_trip() -> void:
	var d = data()
	var path := "user://test_settings_round_trip.json"
	var s: Dictionary = UserSettings.sanitize({"build_clock_seconds": 90, "decoys_per_side": 2, "show_tips": false,
		"tips_done": ["aim"]}, d.settings)
	UserSettings.save_settings(s, path)
	var back: Dictionary = UserSettings.load_settings(d.settings, path)
	eq(back, s, "loaded settings")
	DirAccess.remove_absolute(path)
	eq(UserSettings.load_settings(d.settings, path)["build_clock_seconds"], 120, "missing file gives defaults")


func test_tips_load_with_numbers_from_data() -> void:
	var d = data()
	var tips: Array = Tips.load_tips(d)
	check(tips.size() >= 2, "tips loaded")
	eq(tips[0]["id"], "build_anti_air", "first tip")
	eq(tips[1]["id"], "research_radar", "second tip")
	for t in tips:
		check(not String(t["text"]).contains("{"), "placeholders filled in " + t["id"])
	check(String(tips[1]["text"]).contains("90%"), "radar accuracy from data")
	d.set_path("rules.anti_air.accuracy_with_radar", 0.8)
	check(String(Tips.load_tips(d)[1]["text"]).contains("80%"), "follows the data")


func test_tips_order_and_completion() -> void:
	var tips: Array = Tips.load_tips(data())
	var ctx := {"phase": "build", "has_anti_air": false, "radar_started": false}
	var r: Dictionary = Tips.update(tips, ctx, [], null)
	eq(r["current"]["id"], "build_anti_air", "anti-air first")
	ctx["has_anti_air"] = true
	r = Tips.update(tips, ctx, r["done"], r["current"])
	check(r["done"].has("build_anti_air"), "anti-air tip done once built")
	eq(r["current"]["id"], "research_radar", "then radar")
	# Losing the anti-air later doesn't bring the tip back.
	ctx["has_anti_air"] = false
	r = Tips.update(tips, ctx, r["done"], r["current"])
	eq(r["current"]["id"], "research_radar", "anti-air tip stays done")
	# Dismissed tips stay gone.
	var done: Array = r["done"].duplicate()
	done.append("research_radar")
	r = Tips.update(tips, {"phase": "build", "has_anti_air": true, "radar_started": false}, done, null)
	eq(r["current"], null, "nothing left for this phase")
	r = Tips.update(tips, {"phase": "targeting"}, done, null)
	eq(r["current"]["id"], "aim", "targeting tip")
	r = Tips.update(tips, {"phase": "setup"}, [], null)
	eq(r["current"], null, "no tip during setup")


func test_earnings_projection_matches_next_round() -> void:
	var m = flat_match()
	put(m, 0, "bank", 1, 1)
	put(m, 0, "refinery", 2, 1)
	var damaged = put(m, 0, "bank", 3, 1)
	damaged.hp = 10
	var lab = put(m, 0, "lab", 4, 1)
	ok(m.sides[0].start_research(lab.id, "radar", m.data), "start radar")
	m.begin_round()
	var money_before: int = m.sides[0].money
	var p: Dictionary = Earnings.project(m.sides[0], m.data, m.round_number)
	eq(p["round"], 2, "projects round 2")
	eq(p["income"]["money"], 20 + 15 + 8, "baseline + bank + half bank")
	eq(p["income"]["fuel"], 3 + 3, "baseline + refinery")
	eq(p["income"]["research"], 2, "one lab")
	eq(m.sides[0].money, money_before, "projection leaves the state alone")
	eq(m.sides[0].project_for_item("radar")["progress"], 0, "projection leaves research alone")
	m.end_build_phase()
	ok(m.set_launch_orders(0, []))
	ok(m.set_launch_orders(1, []))
	m.resolve_playout()
	m.begin_round()
	eq(m.sides[0].money, money_before + int(p["income"]["money"]), "actual income matches projection")


func test_earnings_counts_repairs_as_finished() -> void:
	var m = flat_match()
	var bank = put(m, 0, "bank", 1, 1)
	bank.hp = 10
	m.begin_round()
	ok(m.sides[0].repair(bank.hex, m.data), "repair")
	var p: Dictionary = Earnings.project(m.sides[0], m.data, m.round_number)
	eq(p["income"]["money"], 20 + 15, "repaired bank pays in full next round")


func test_earnings_round_one_has_no_income_before_round_two() -> void:
	var m = flat_match()
	var p: Dictionary = Earnings.project(m.sides[0], m.data, 0)
	check(p["income"].is_empty(), "setup projects round 1: no income")


func test_research_rate_and_rounds_left() -> void:
	var m = flat_match()
	var d = m.data
	var st = m.sides[0]
	var lab1 = put(m, 0, "lab", 1, 1)
	ok(st.start_research(lab1.id, "radar", d), "radar")
	eq(Earnings.research_rate(st, d, "radar"), 2, "one lab")
	eq(Earnings.rounds_left(st, d, "radar"), 3, "6 points at 2 a round")
	put(m, 0, "lab", 2, 1)
	eq(Earnings.research_rate(st, d, "radar"), 4, "idle lab helps the oldest project")
	eq(Earnings.rounds_left(st, d, "radar"), 2, "twice as fast")
	st.remove_building(lab1.hex, d)
	eq(Earnings.research_rate(st, d, "radar"), 2, "orphaned project still helped by the idle lab")
	st.remove_building(st.of_role(d, "lab")[0].hex, d)
	eq(Earnings.rounds_left(st, d, "radar"), -1, "stalled without labs")


func test_timer_readout() -> void:
	eq(SevenSeg.text_for(120), " 200", "2:00")
	eq(SevenSeg.text_for(5), " 005", "0:05")
	eq(SevenSeg.text_for(600), "1000", "10:00")
	for ch in SevenSeg.text_for(754):
		check(SevenSeg.DIGITS.has(ch), "every digit drawable")


func test_base_button_colours() -> void:
	eq(StripButton.base_color(3.0), StripButton.GREEN, "3 left")
	eq(StripButton.base_color(2.5), StripButton.YELLOW, "2.5 left")
	eq(StripButton.base_color(2.0), StripButton.YELLOW, "2 left")
	eq(StripButton.base_color(1.0), StripButton.RED, "1 left")
	eq(StripButton.base_color(0.5), StripButton.RED, "half a hit left")
	eq(StripButton.base_color(0.0), StripButton.DEAD, "destroyed")
