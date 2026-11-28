## The Esc menu's way out (main menu or quit, asking to save first) and the
## unsaved-progress check behind it.
extends "res://tests/test_case.gd"

const EscMenu = preload("res://game/esc_menu.gd")


## An Esc menu with its controls built (_ready), already showing (so it
## needn't pause a tree), and the signals it sends counted in `sent`.
func _menu(unsaved: Array, can_save: bool, sent: Array):
	var menu = EscMenu.new()
	menu._ready()
	menu.visible = true
	menu.setup(data().settings, {"build_clock_seconds": 45, "targeting_clock_seconds": 60,
		"decoys_per_side": 2, "show_tips": true, "show_grid": false, "tips_done": []})
	menu.can_save = can_save
	menu.current_save = "Autosave"
	menu.is_unsaved = func(): return unsaved[0]
	menu.main_menu_requested.connect(func(): sent.append("main_menu"))
	menu.quit_requested.connect(func(): sent.append("quit"))
	menu.save_requested.connect(func(_as_new, _name): sent.append("save"))
	return menu


func _done(menu) -> void:
	menu.free()


func test_leaving_with_nothing_unsaved_goes_straight_away() -> void:
	var sent: Array = []
	var menu = _menu([false], true, sent)
	menu.request_leave("main_menu")
	eq(sent, ["main_menu"], "main menu at once")
	check(not menu._leave_box.visible, "no question")
	menu.request_leave("quit")
	eq(sent, ["main_menu", "quit"], "quit at once")
	_done(menu)


func test_leaving_unsaved_in_build_offers_to_save_first() -> void:
	var sent: Array = []
	var unsaved := [true]
	var menu = _menu(unsaved, true, sent)
	menu.request_leave("main_menu")
	eq(sent, [], "asks before leaving")
	check(menu._leave_box.visible, "the question shows")
	check(menu._leave_save.visible, "with a save key")
	# A save that fails keeps the player here.
	menu._save_and_leave()
	eq(sent, ["save"], "tried to save, stayed")
	# A save that works leaves.
	menu.save_requested.connect(func(_a, _n): unsaved[0] = false)
	menu._save_and_leave()
	eq(sent, ["save", "save", "main_menu"], "saved, then left")
	_done(menu)


func test_leaving_outside_build_warns_and_can_still_leave_or_stay() -> void:
	var sent: Array = []
	var menu = _menu([true], false, sent)
	menu.request_leave("quit")
	check(menu._leave_box.visible, "the question shows")
	check(not menu._leave_save.visible, "no save key: saving only in build and repair")
	menu._show_main()
	check(not menu._leave_box.visible and menu._main_box.visible, "cancel goes back to the pause menu")
	eq(sent, [], "stayed")
	menu.request_leave("quit")
	menu._leave()
	eq(sent, ["quit"], "left without saving")
	_done(menu)


## The game tells unsaved progress by comparing the save it would write now
## with the last one written: the same game gives the same bytes, a change
## gives different ones.
func test_a_save_snapshot_changes_only_when_the_game_does() -> void:
	var m = flat_match()
	m.begin_round()
	var a := var_to_bytes(m.to_save())
	eq(var_to_bytes(m.to_save()), a, "same game, same snapshot")
	put(m, 0, "bank", 3, 3)
	check(var_to_bytes(m.to_save()) != a, "a new building changes it")
