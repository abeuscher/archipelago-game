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


func test_earnings_counts_repair_round_as_out() -> void:
	var m = flat_match()
	var bank = put(m, 0, "bank", 1, 1)
	bank.hp = 10
	m.begin_round()
	ok(m.sides[0].repair(bank.hex, m.data), "repair")
	var p: Dictionary = Earnings.project(m.sides[0], m.data, m.round_number)
	eq(p["income"]["money"], 20, "bank under repair makes nothing this round")
	check(String(p["lines"][0]).contains("under repair"), "breakdown says why")


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
	eq(StripButton.base_color(2.0, 2.0), StripButton.GREEN, "2 of 2 left")
	eq(StripButton.base_color(1.5, 2.0), StripButton.YELLOW, "1.5 of 2 left")
	eq(StripButton.base_color(1.0, 2.0), StripButton.RED, "last hit left")


func test_tips_phase_change_and_snooze() -> void:
	var tips: Array = Tips.load_tips(data())
	var build := {"phase": "build", "has_anti_air": false, "radar_started": false}
	var r: Dictionary = Tips.update(tips, build, [], null)
	eq(r["current"]["id"], "build_anti_air", "shown in build")
	# Leaving the phase hides the tip without marking it done.
	r = Tips.update(tips, {"phase": "targeting"}, r["done"], r["current"])
	check(not r["done"].has("build_anti_air"), "phase change is not completion")
	r = Tips.update(tips, build, r["done"], null)
	eq(r["current"]["id"], "build_anti_air", "comes back next build phase")
	# Dismissed with the box unticked: skipped for now, not done.
	r = Tips.update(tips, build, r["done"], null, ["build_anti_air"])
	eq(r["current"]["id"], "research_radar", "snoozed tip skipped")
	check(not r["done"].has("build_anti_air"), "snoozed tip not done")


func test_bombed_hexes_counted_with_last_round() -> void:
	var m = flat_match()
	put(m, 1, "basic_launcher", 1, 1)
	m.sides[1].fuel = 30
	var target := hex(m, 7, 7)
	var launcher_hex := hex(m, 1, 1)
	play_round(m, [], [{"launcher": launcher_hex, "missile": "basic", "target": target}])
	eq(m.bombed[0].get(target, {}).get("count", 0), 1, "one hit")
	eq(m.bombed[0][target]["last_round"], 1, "round 1")
	play_round(m, [], [{"launcher": launcher_hex, "missile": "basic", "target": target}])
	eq(m.bombed[0][target]["count"], 2, "two hits")
	eq(m.bombed[0][target]["last_round"], 2, "last in round 2")
	check(m.bombed[1].is_empty(), "nothing landed on side 1")


func test_hit_outline_colours() -> void:
	const BoardView = preload("res://game/board_view.gd")
	check(BoardView.bombed_color(1) != BoardView.bombed_color(2), "1 and 2 differ")
	check(BoardView.bombed_color(2) != BoardView.bombed_color(3), "2 and 3 differ")
	eq(BoardView.bombed_color(5), BoardView.bombed_color(3), "red from 3 on")
	check(BoardView.bombed_color(1).g > BoardView.bombed_color(2).g and BoardView.bombed_color(2).g > BoardView.bombed_color(3).g, "yellow, orange, red")
	check(BoardView.SELECTED != BoardView.bombed_color(1), "selection never looks like a hit")


func test_sprite_sheet_choice() -> void:
	const Pieces = preload("res://game/pieces.gd")
	eq(Pieces.sheet_name({"type": "suspected_base"}), "base", "enemy sees a base")
	eq(Pieces.sheet_name({"type": "decoy"}), "decoy", "owner sees the decoy flag")
	eq(Pieces.sheet_name({"type": "basic_launcher"}), "missile_launcher", "loaded launcher")
	eq(Pieces.sheet_name({"type": "basic_launcher", "empty": true}), "missile_launcher_empty", "fired launcher")
	eq(Pieces.sheet_name({"type": "ballistic_launcher", "empty": true}), "ballistic_launcher_empty", "fired ballistic launcher")
	eq(Pieces.sheet_name({"type": "bank", "empty": true}), "bank", "only launchers empty")
	eq(Pieces.sheet_name({"type": "radar", "repairing": true}), "repair", "scaffolding while repairing")
	eq(Pieces.sheet_name({"type": "bank", "damaged": true}), "bank_damaged", "hit bank")
	eq(Pieces.sheet_name({"type": "basic_launcher", "disabled": true, "empty": true}), "missile_launcher_damaged", "damaged launcher has no empty version")
	eq(Pieces.sheet_name({"type": "suspected_base", "hits": 1.0}), "base_damaged", "hit potential base")
	eq(Pieces.sheet_name({"type": "decoy", "hits": 0.5}), "decoy_damaged", "hit decoy, owner's view")
	eq(Pieces.sheet_name({"type": "bank", "damaged": true, "repairing": true}), "repair", "repair beats damage")


func test_every_building_has_a_sprite_sheet() -> void:
	const Pieces = preload("res://game/pieces.gd")
	var meta: Dictionary = Pieces.sprite_meta()
	check(not meta.is_empty(), "sprites.json read")
	eq(int(meta["frames_per_sheet"]), 6, "one frame per rotation")
	var names: Array = Pieces.SHEET_FOR.values() + ["repair", "rubble", "missile_launcher_empty", "ballistic_launcher_empty"]
	for n in Pieces.DAMAGED_SHEETS:
		names.append(n + "_damaged")
	for n in names:
		var tex: Texture2D = Pieces.sheet(n)
		check(tex != null, "sheet loads: " + n)
		if tex != null:
			eq(tex.get_width(), int(meta["frame_width"]) * 6, "six frames wide: " + n)
	for type in data().section("buildings"):
		check(Pieces.SHEET_FOR.has(type), "sheet for building " + type)


func test_small_caps_caption() -> void:
	const Hud = preload("res://game/hud.gd")
	eq(Hud.small_caps("Money", 12, 9), "[font_size=12]M[/font_size][font_size=9]ONEY[/font_size]", "first letter large")
	check(Hud.small_caps("Next round", 12, 9).contains("[font_size=12]R[/font_size]"), "each word")


func test_next_round_money_matches_projection() -> void:
	var m = flat_match()
	put(m, 0, "bank", 1, 1)
	m.begin_round()
	var before: int = m.sides[0].money
	var shown := int(Earnings.project(m.sides[0], m.data, m.round_number)["income"]["money"])
	m.end_build_phase()
	ok(m.set_launch_orders(0, []))
	ok(m.set_launch_orders(1, []))
	m.resolve_playout()
	m.begin_round()
	eq(m.sides[0].money, before + shown, "bracketed income is what arrives")
