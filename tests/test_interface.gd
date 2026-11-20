## Interface logic that needs no rendering: settings, tips, the earnings
## projection, research rates, the timer readout and the battle report.
extends "res://tests/test_case.gd"

const UserSettings = preload("res://game/user_settings.gd")
const Tips = preload("res://game/tips.gd")
const Earnings = preload("res://game/earnings.gd")
const SevenSeg = preload("res://game/seven_seg.gd")
const BattleReport = preload("res://game/battle_report.gd")


func test_settings_defaults_and_clamping() -> void:
	var d = data()
	var s: Dictionary = UserSettings.sanitize({}, d.settings)
	eq(s["build_clock_seconds"], 45, "default build clock")
	eq(s["targeting_clock_seconds"], 60, "default targeting clock")
	eq(s["decoys_per_side"], 1, "default decoys")
	eq(s["show_tips"], true, "tips on by default")
	eq(s["show_grid"], false, "grid off by default")
	s = UserSettings.sanitize({"settings_version": 3, "decoys_per_side": 9, "build_clock_seconds": 7, "targeting_clock_seconds": 5000, "junk": 1}, d.settings)
	eq(s["decoys_per_side"], 3, "decoys clamped to max")
	eq(s["build_clock_seconds"], 5, "clock rounded to the step")
	eq(s["targeting_clock_seconds"], 600, "clock clamped to max")
	check(not s.has("junk"), "unknown keys dropped")
	s = UserSettings.sanitize({"settings_version": 3, "build_clock_seconds": 0, "decoys_per_side": 0}, d.settings)
	eq(s["build_clock_seconds"], 0, "0 means off")
	eq(s["decoys_per_side"], 1, "decoys clamped to min")
	eq(UserSettings.match_overrides(s), {"decoys_per_side": 1}, "only rules settings go to the match")


func test_settings_round_trip() -> void:
	var d = data()
	var path := "user://test_settings_round_trip.json"
	var s: Dictionary = UserSettings.sanitize({"settings_version": 3, "build_clock_seconds": 90, "decoys_per_side": 2, "show_tips": false,
		"tips_done": ["aim"]}, d.settings)
	UserSettings.save_settings(s, path)
	var back: Dictionary = UserSettings.load_settings(d.settings, path)
	eq(back, s, "loaded settings")
	DirAccess.remove_absolute(path)
	eq(UserSettings.load_settings(d.settings, path)["build_clock_seconds"], 45, "missing file gives defaults")


func test_old_settings_take_the_new_default_clocks() -> void:
	var d = data()
	var s: Dictionary = UserSettings.sanitize({"build_clock_seconds": 120, "targeting_clock_seconds": 90, "decoys_per_side": 2}, d.settings)
	eq(s["build_clock_seconds"], 45, "old saved clock replaced by the new default")
	eq(s["targeting_clock_seconds"], int(d.settings["targeting_clock_seconds"]), "both clocks")
	eq(s["decoys_per_side"], 2, "other choices kept")
	eq(s["settings_version"], 3, "now current")
	s = UserSettings.sanitize({"settings_version": 2, "build_clock_seconds": 30}, d.settings)
	eq(s["build_clock_seconds"], 45, "the 30-second default from version 2 moves to 45")


func test_tips_load_with_numbers_from_data() -> void:
	var d = data()
	var tips: Array = _game_tips(d)
	check(tips.size() >= 2, "tips loaded")
	eq(tips[0]["id"], "place_bases", "first tip, in setup")
	eq(tips[0]["anchor"], "tool:base", "points at the base button")
	eq(tips[1]["id"], "setup_done", "then setup complete")
	eq(tips[1]["anchor"], "button:Undo", "points at Undo")
	eq(tips[2]["id"], "round_timer", "then the timer")
	eq(tips[2]["anchor"], "timer", "points at the timer")
	check(tips[2]["pause"], "blocks the screen")
	check(String(tips[2]["text"]).contains("{build_clock}"), "clock filled in when shown")
	eq(tips[3]["id"], "research_intro", "the Scientist when research first opens")
	eq(tips[3]["character"], "scientist", "said by the Scientist")
	eq(tips[4]["id"], "repair", "damage comes straight after, when there is any")
	eq(tips[4]["character"], "mechanic", "the Mechanic reports damage")
	eq(tips[5]["id"], "rebuild_launcher", "then a launcher kept down")
	eq(tips[6]["id"], "build_launcher", "then the launcher")
	eq(tips[6]["anchor"], "tool:basic_launcher", "points at the launcher button")
	eq(tips[7]["id"], "build_anti_air", "then anti-air")
	for t in tips:
		check(not String(t["text"]).replace("{build_clock}", "").contains("{"), "placeholders filled in " + t["id"])
	var radar: Dictionary = tips.filter(func(t): return t["id"] == "research_radar")[0]
	check(String(radar["text"]).contains("90%"), "radar accuracy from data")
	d.set_path("rules.anti_air.accuracy_with_radar", 0.8)
	check(String(_game_tips(d).filter(func(t): return t["id"] == "research_radar")[0]["text"]).contains("80%"), "follows the data")


func test_tips_order_and_completion() -> void:
	var tips: Array = _game_tips(data())
	var ctx := {"phase": "build", "round": 2, "has_lab": true, "has_launcher": true, "has_anti_air": false, "radar_started": false}
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
	r = Tips.update(tips, {"phase": "build", "round": 2, "has_lab": true, "has_launcher": true, "has_anti_air": true, "radar_started": false}, done, null)
	eq(r["current"], null, "nothing left for this phase")
	r = Tips.update(tips, {"phase": "targeting"}, done, null)
	eq(r["current"]["id"], "aim", "targeting tip")
	r = Tips.update(tips, {"phase": "setup"}, [], null)
	eq(r["current"]["id"], "place_bases", "base tip during setup")


func test_earnings_projection_matches_next_round() -> void:
	var m = flat_match()
	put(m, 0, "bank", 1, 1)
	put(m, 0, "refinery", 2, 1)
	var damaged = put(m, 0, "bank", 3, 1)
	damaged.hp = 10
	put(m, 0, "lab", 4, 1)
	m.begin_round()
	var money_before: int = m.sides[0].money
	var p: Dictionary = Earnings.project(m.sides[0], m.data, m.round_number)
	eq(p["round"], 2, "projects round 2")
	eq(p["income"]["money"], m.data.integer("economy", "baseline_money") + 15 + 8, "baseline + bank + half bank")
	eq(p["income"]["fuel"], 3 + 3, "baseline + refinery")
	eq(p["income"]["research"], 2, "one lab")
	eq(m.sides[0].money, money_before, "projection leaves the state alone")
	eq(m.sides[0].research, 0, "projection leaves research alone")
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
	eq(p["income"]["money"], m.data.integer("economy", "baseline_money"), "bank under repair makes nothing this round")
	check(String(p["lines"][0]).contains("under repair"), "breakdown says why")


func test_earnings_round_one_has_no_income_before_round_two() -> void:
	var m = flat_match()
	var p: Dictionary = Earnings.project(m.sides[0], m.data, 0)
	check(p["income"].is_empty(), "setup projects round 1: no income")


func test_rounds_to_afford_research() -> void:
	var m = flat_match()
	var d = m.data
	var st = m.sides[0]
	eq(Earnings.rounds_to_afford(st, d, "radar"), -1, "no labs: never")
	put(m, 0, "lab", 1, 1)
	eq(Earnings.rounds_to_afford(st, d, "radar"), 3, "6 points at 2 a round")
	put(m, 0, "lab", 2, 1)
	eq(Earnings.rounds_to_afford(st, d, "radar"), 2, "two labs: twice as fast")
	st.research = 6
	eq(Earnings.rounds_to_afford(st, d, "radar"), 0, "already affordable")


func test_timer_readout() -> void:
	eq(SevenSeg.text_for(120), " 200", "2:00")
	eq(SevenSeg.text_for(5), " 005", "0:05")
	eq(SevenSeg.text_for(600), "1000", "10:00")
	for ch in SevenSeg.text_for(754):
		check(SevenSeg.DIGITS.has(ch), "every digit drawable")




func test_tips_phase_change_and_snooze() -> void:
	var tips: Array = _game_tips(data())
	var build := {"phase": "build", "round": 2, "has_lab": true, "has_launcher": true, "has_anti_air": false, "radar_started": false}
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
		check(Pieces.SHEET_FOR.has(type) or Pieces.ART_PENDING.has(type), "sheet for building " + type)


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


func test_first_build_tips_timer_then_launcher() -> void:
	var tips: Array = _game_tips(data())
	var ctx := {"phase": "build", "round": 2, "has_lab": true, "clock_on": true, "has_launcher": false, "has_anti_air": false, "radar_started": false}
	var r: Dictionary = Tips.update(tips, ctx, [], null)
	eq(r["current"]["id"], "round_timer", "timer tip first while the clock runs")
	var done: Array = ["round_timer"]
	r = Tips.update(tips, ctx, done, null)
	eq(r["current"]["id"], "build_launcher", "then the launcher")
	ctx["has_launcher"] = true
	r = Tips.update(tips, ctx, r["done"], r["current"])
	check(r["done"].has("build_launcher"), "done once a launcher is built")
	ctx["clock_on"] = false
	r = Tips.update(tips, ctx, [], null)
	check(r["current"]["id"] != "round_timer", "no timer tip with the clock off")


func test_characters_data() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/characters.json"))
	check(parsed is Dictionary, "characters.json parses")
	var chars: Dictionary = parsed["characters"]
	check(chars.has(String(parsed["default"])), "default character exists")
	for id in chars:
		var c: Dictionary = chars[id]
		check(FileAccess.file_exists(String(c["portrait"])), "portrait file for " + id)
		eq(c["circle"].size(), 3, "circle is [x, y, radius] for " + id)


func test_every_line_has_a_known_speaker() -> void:
	var chars: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/characters.json"))["characters"]
	for t in _game_tips(data()):
		check(chars.has(t["character"]), "tip %s spoken by a known character" % t["id"])
	var lines: Dictionary = Tips.load_lines()
	for key in lines:
		if key.begins_with("_"):
			continue
		check(chars.has(String(lines[key]["character"])), "line %s spoken by a known character" % key)
	eq(_game_tips(data())[0]["character"], "admiral", "the Admiral asks for careful base placement")


func test_setup_done_tip_after_bases_and_decoys() -> void:
	var tips: Array = _game_tips(data())
	var r: Dictionary = Tips.update(tips, {"phase": "setup", "setup_complete": false}, ["place_bases"], null)
	eq(r["current"], null, "nothing while still placing")
	r = Tips.update(tips, {"phase": "setup", "setup_complete": true}, ["place_bases"], null)
	eq(r["current"]["id"], "setup_done", "once everything is placed")
	eq(r["current"]["character"], "ginger", "Ginger says it")


func test_game_rules_page_filled_from_data() -> void:
	const RulesText = preload("res://game/rules_text.gd")
	var d = data()
	var text: String = RulesText.build(d, 45, 0)
	check(text.length() > 500, "rules text built")
	var plain := text
	for tag in ["[b]", "[/b]", "[/font_size]", "[font_size=20]"]:
		plain = plain.replace(tag, "")
	check(not plain.contains("{"), "every placeholder filled")
	check(text.contains("45 seconds"), "player's build clock")
	check(text.contains("no time limit"), "clock off")
	check(text.contains("30%"), "repair cost from data")
	check(text.contains("Missile launcher"), "building list")
	d.set_path("rules.damage.repair_cost_fraction", 0.5)
	check(RulesText.build(d, 45, 60).contains("50%"), "follows the data")


func test_damage_tip_cost_from_data() -> void:
	var t: Array = _game_tips(data()).filter(func(x): return x["id"] == "repair")
	check(String(t[0]["text"]).contains("30% of their original cost"), "repair cost filled in")
	eq(t[0]["character"], "mechanic", "said by the Mechanic")


func test_rebuild_tip_when_a_launcher_is_kept_down() -> void:
	var tips: Array = _game_tips(data())
	var done: Array = ["place_bases", "setup_done", "round_timer", "repair"]
	var ctx := {"phase": "build", "round": 2, "has_lab": true, "has_launcher": true, "has_anti_air": true, "radar_started": true, "own_damaged": true}
	var r: Dictionary = Tips.update(tips, ctx, done, null)
	check(r["current"] == null or r["current"]["id"] != "rebuild_launcher", "not without repeated hits")
	ctx["launcher_targeted"] = true
	r = Tips.update(tips, ctx, done, null)
	eq(r["current"]["id"], "rebuild_launcher", "shown when a launcher is kept down")
	eq(r["current"]["character"], "mechanic", "the Mechanic says it")


func test_anti_air_tip_from_round_two() -> void:
	var tips: Array = _game_tips(data())
	var done: Array = ["place_bases", "setup_done", "round_timer"]
	var ctx := {"phase": "build", "round": 1, "has_launcher": true, "has_anti_air": false, "has_lab": false}
	var r: Dictionary = Tips.update(tips, ctx, done, null)
	check(r["current"] == null or r["current"]["id"] != "build_anti_air", "not in round 1")
	ctx["round"] = 2
	r = Tips.update(tips, ctx, done, null)
	eq(r["current"]["id"], "build_anti_air", "round 2 with no anti-air")
	ctx["has_anti_air"] = true
	r = Tips.update(tips, ctx, done, null)
	check(r["current"] == null or r["current"]["id"] != "build_anti_air", "not once anti-air is built")


func test_radar_tip_after_first_lab() -> void:
	var tips: Array = _game_tips(data())
	var done: Array = ["place_bases", "setup_done", "round_timer", "build_anti_air"]
	var ctx := {"phase": "build", "round": 2, "has_launcher": true, "has_anti_air": true, "has_lab": false, "radar_started": false}
	var r: Dictionary = Tips.update(tips, ctx, done, null)
	check(r["current"] == null or r["current"]["id"] != "research_radar", "not without a lab")
	ctx["has_lab"] = true
	r = Tips.update(tips, ctx, done, null)
	eq(r["current"]["id"], "research_radar", "once there is a lab")


func test_scientist_explains_research_when_it_first_opens() -> void:
	var tips: Array = _game_tips(data())
	var done: Array = ["place_bases", "setup_done", "round_timer"]
	var ctx := {"phase": "build", "round": 1, "has_launcher": true, "has_anti_air": true, "has_lab": true, "radar_started": true}
	var r: Dictionary = Tips.update(tips, ctx, done, null)
	check(r["current"] == null or r["current"]["id"] != "research_intro", "not until research is opened")
	ctx["research_open"] = true
	r = Tips.update(tips, ctx, done, null)
	eq(r["current"]["id"], "research_intro", "when the research screen opens")


func test_battle_report_counts_and_skips_zeros() -> void:
	eq(BattleReport.sentences([], Tips.load_lines()["battle_report"]["parts"]), [], "a quiet round gives no report")
	var ev := [
		# The enemy (side 1) attacks us: two missiles land, one is shot down,
		# one transport is shot down. Hex 5 is hit twice and survives; hex 9
		# is destroyed.
		{"type": "impact", "side": 1, "id": 1, "damaged": [{"hex": 5, "damage": 10}, {"hex": 9, "damage": 30}]},
		{"type": "impact", "side": 1, "id": 2, "damaged": [{"hex": 5, "damage": 10}]},
		{"type": "engage", "side": 0, "id": 3, "hit": true},
		{"type": "engage", "side": 0, "id": 4, "hit": true},
		{"type": "carrier_lost", "side": 1, "id": 4},
		{"type": "engage", "side": 0, "id": 6, "hit": false},
		{"type": "destroyed", "side": 0, "hex": 9, "building": "bank"},
		# We attack: one missile lands on a base without destroying it, one is
		# shot down; our platoon is wiped out by a bunker.
		{"type": "impact", "side": 0, "id": 10, "damaged": [{"hex": 3, "hits": 1.0}]},
		{"type": "engage", "side": 1, "id": 11, "hit": true},
		{"type": "platoon", "side": 0, "id": 12, "lost_at_sea": false, "stopped_by": 4, "destroyed": []},
	]
	var parts: Dictionary = Tips.load_lines()["battle_report"]["parts"]
	eq(BattleReport.sentences(ev, parts), [
		"Two enemy missiles got through to us.",
		"One of our buildings was damaged.",
		"We lost one building.",
		"Our anti-air shot down one of their missiles.",
		"We brought down one of their transports.",
		"One of our missiles found its target.",
		"They shot down one of our missiles.",
		"We damaged one enemy building.",
		"We lost eight soldiers.",
		"We stopped eight of their soldiers.",
	], "the Admiral's sentences")


## The tips after the opening walkthrough (Ginger's intro_* tips, which come
## first in setup).
func _game_tips(d) -> Array:
	return Tips.load_tips(d).filter(func(t): return not String(t["id"]).begins_with("intro_"))


func test_walkthrough_comes_first_and_points_at_the_controls() -> void:
	var tips: Array = Tips.load_tips(data())
	var ids: Array = tips.map(func(t): return String(t["id"]))
	eq(ids.slice(0, 7), ["intro_welcome", "intro_toolbar", "intro_resources", "intro_minimap", "intro_info", "intro_comms", "intro_done"], "in order, before anything else")
	for t in tips.slice(0, 7):
		eq(t["character"], "ginger", "Ginger walks through " + t["id"])
		eq(t["when"], "setup", "in setup")
	eq(tips[1]["anchor"], "toolbar", "the toolbar, spotlit like the admiral's tip")
	eq(tips[2]["anchor"], "resources", "the whole resource strip stays lit while the arrow moves")
	eq(tips[2]["arrows"].map(func(a): return a[0]), ["res:money", "res:fuel", "res:research"], "the resources, one after another")
	eq(tips[5]["arrows"].map(func(a): return a[0]), ["volume", "status"], "volume, then base health")
	# OK on each brings the next.
	var done: Array = []
	var r: Dictionary = Tips.update(tips, {"phase": "setup"}, done, null)
	for k in 7:
		eq(r["current"]["id"], ids[k], "step %d" % (k + 1))
		done.append(ids[k])
		r = Tips.update(tips, {"phase": "setup"}, done, null)
	eq(r["current"]["id"], "place_bases", "then the Admiral on placing bases")
