## The simple AI and the headless match runner.
extends "res://tests/test_case.gd"

const SimpleAI = preload("res://ai/simple_ai.gd")
const MatchRunner = preload("res://ai/match_runner.gd")
const SideView = preload("res://rules/side_view.gd")


func _play(seed_in: int) -> Dictionary:
	var d = data()
	return MatchRunner.play(d, seed_in, [SimpleAI.new(0, d, seed_in), SimpleAI.new(1, d, seed_in)], 300)


func test_ai_match_is_deterministic() -> void:
	var a := _play(31)
	var b := _play(31)
	eq(a["fingerprint"], b["fingerprint"], "same seed, same match")
	eq(a["rounds"], b["rounds"], "rounds")


func test_ai_matches_finish_without_rejected_actions() -> void:
	for s in [1, 2, 3]:
		var r := _play(s)
		check(not r["timed_out"], "seed %d timed out" % s)
		eq(r["errors"].size(), 0, "seed %d rejected actions %s" % [s, str(r["errors"].slice(0, 3))])


func test_ai_setup_respects_spacing() -> void:
	var d = data()
	var m = MatchState.create(d, 8)
	var ai = SimpleAI.new(0, d, 8)
	var setup: Dictionary = ai.choose_setup(m.view_for(0))
	eq(setup["bases"].size(), 3, "three bases")
	eq(setup["decoys"].size(), 1, "one decoy by default")
	ok(m.setup_side(0, setup["bases"], setup["decoys"]))


func test_ai_only_receives_a_side_view() -> void:
	# The AI's entry points take a SideView; a SideView exposes no opponent state.
	var d = data()
	var m = MatchState.create(d, 4)
	var v = m.view_for(1)
	check(v is SideView, "view type")
	for prop in v.get_property_list():
		var n: String = prop["name"]
		check(n != "sides" and n != "knowledge" and n != "dice", "view leaks %s" % n)


func test_ai_opening_follows_build_order() -> void:
	var d = data()
	var m = MatchState.create(d, 12)
	var ai = SimpleAI.new(0, d, 12)
	var setup: Dictionary = ai.choose_setup(m.view_for(0))
	ok(m.setup_side(0, setup["bases"], setup["decoys"]))
	var view = m.view_for(0)
	view.round_number = 1
	var actions: Array = ai.choose_build(view)
	var built: Array = actions.filter(func(a): return a["action"] == "build").map(func(a): return a["type"])
	var spent := 0
	for t in built:
		spent += d.cost(t)
	check(spent <= m.sides[0].money, "spends no more than it has")
	check(built.size() >= 2 and built[0] == "basic_launcher" and built[1] == "bank", "opens launcher, then bank: %s" % str(built))
	var left: int = m.sides[0].money - spent
	check(built.size() < 11, "stops at the build order's end or when money runs out (%d left)" % left)
