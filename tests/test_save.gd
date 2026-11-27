## Saved games: a match saved and loaded plays on exactly as if it had never
## stopped, and the save files themselves (list, newest first, delete).
extends "res://tests/test_case.gd"

const Levels = preload("res://rules/levels.gd")
const StrongAI = preload("res://ai/strong_ai.gd")
const SaveGame = preload("res://game/save_game.gd")

const TEST_DIR := "user://test_saves/"


func _clear_dir() -> void:
	var da := DirAccess.open(TEST_DIR)
	if da != null:
		for f in da.get_files():
			DirAccess.remove_absolute(TEST_DIR.path_join(f))


func _use_test_dir() -> void:
	SaveGame.dir = TEST_DIR
	_clear_dir()


## Both sides set up by the strong AI, then `rounds` full rounds played.
func _start(d, seed_in: int):
	var m = MatchState.create(d, seed_in)
	var ais := [StrongAI.new(0, d, seed_in), StrongAI.new(1, d, seed_in + 50)]
	for s in 2:
		var su: Dictionary = ais[s].choose_setup(m.view_for(s))
		ok(m.setup_side(s, su["bases"], su["decoys"]), "setup side %d" % s)
	return [m, ais]


func _build(m, ais) -> void:
	m.begin_round()
	for s in 2:
		for a in ais[s].choose_build(m.view_for(s)):
			m.build_action(s, a)


func _fight(m, ais) -> void:
	m.end_build_phase()
	for s in 2:
		var o: Array = ais[s].choose_targets(m.view_for(s))
		if m.set_launch_orders(s, o) != "":
			m.set_launch_orders(s, [])
	m.resolve_playout()
	if m.phase == MatchState.Phase.COIN_FLIP:
		m.resolve_coin_flip()


## Saved in build and repair (as the game saves), through a real file.
func _save_and_load(d, m, ais) -> Array:
	var path := SaveGame.new_path("test")
	ok(SaveGame.write(path, {"name": "test", "level": 5, "round": m.round_number,
		"match": m.to_save(), "ai": [ais[0].to_save(), ais[1].to_save()]}), "written")
	var s := SaveGame.read(path)
	check(not s.is_empty(), "read back")
	var m2 = MatchState.from_save(d, s["match"])
	var ais2 := [StrongAI.new(0, d, m2.seed_value), StrongAI.new(1, d, m2.seed_value + 50)]
	for k in 2:
		ais2[k].load_save(s["ai"][k])
	return [m2, ais2]


func test_a_loaded_match_plays_on_exactly_as_if_it_never_stopped() -> void:
	_use_test_dir()
	for lvl in [1, 4, 5]:
		var d = Levels.data_for(data(), lvl)
		var r = _start(d, 21 + lvl)
		var m = r[0]
		var ais: Array = r[1]
		for k in 6:
			_build(m, ais)
			_fight(m, ais)
		_build(m, ais)   # the game saves at the start of build and repair
		var l = _save_and_load(d, m, ais)
		var m2 = l[0]
		var ais2: Array = l[1]
		eq(m2.fingerprint(), m.fingerprint(), "level %d: the same match after loading" % lvl)
		for k in 8:
			if m.is_over():
				break
			_fight(m, ais)
			_fight(m2, ais2)
			eq(m2.fingerprint(), m.fingerprint(), "level %d: still the same %d rounds on" % [lvl, k + 1])
			if m.is_over():
				break
			_build(m, ais)
			_build(m2, ais2)
		eq(m2.is_over(), m.is_over(), "level %d: over at the same time" % lvl)
	_clear_dir()


func test_a_save_keeps_agents_spies_boats_and_research_in_progress() -> void:
	_use_test_dir()
	var d = Levels.data_for(data(), 5)
	var m = flat_match(d)
	var enc = put(m, 0, "enclave", 0, 0)
	var their = put(m, 1, "enclave", 6, 6)
	m.sides[0].fuel = 40
	m.sides[0].money = 400
	play_round(m, [{"launcher": enc.hex, "missile": "spy", "target": hex(m, 10, 10)}])
	var lab = put(m, 0, "lab", 2, 0)
	m.begin_round()
	ok(m.build_action(0, {"action": "research", "lab": lab.id, "item": "logistics"}))
	check(not m.spies[0].is_empty() and not m.agents[1].is_empty(), "a spy out and their agent on patrol")
	var path := SaveGame.new_path("agents")
	ok(SaveGame.write(path, {"name": "agents", "match": m.to_save()}))
	var m2 = MatchState.from_save(d, SaveGame.read(path)["match"])
	eq(m2.spies, m.spies, "our spy where he was")
	eq(m2.agents, m.agents, "their agents where they were")
	eq(m2.patrolled, m.patrolled, "where they have patrolled")
	eq(m2.spy_sightings, m.spy_sightings, "where they saw our spy land")
	eq(m2.sides[0].projects, m.sides[0].projects, "research in progress")
	eq(m2.knowledge[0].keys().size(), m.knowledge[0].keys().size(), "what we have seen")
	eq(m2.phase, MatchState.Phase.BUILD, "in build and repair")
	eq(m2.sides[1].building_at(their.hex).type, "enclave", "their buildings")
	check(m2.sides[0].island.land == m.sides[0].island.land and m2.sides[0].island.level == m.sides[0].island.level, "the island itself")
	_clear_dir()


func test_save_files_list_newest_first_and_delete() -> void:
	_use_test_dir()
	eq(SaveGame.list().size(), 0, "none to start with")
	eq(SaveGame.most_recent(), "", "nothing to continue")
	var a := SaveGame.new_path("First game")
	ok(SaveGame.write(a, {"name": "First game", "level": 2, "level_name": "Level 2", "round": 7}))
	var b := SaveGame.new_path("First game")
	check(b != a, "a second save of the same name gets its own file")
	ok(SaveGame.write(b, {"name": "Second", "level": 3, "level_name": "Level 3", "round": 0}))
	# Make the first one older.
	var old := SaveGame.read(a)
	old["saved_at"] = 1
	var f := FileAccess.open(a, FileAccess.WRITE)
	f.store_var(old)
	f.close()
	var all := SaveGame.list()
	eq(all.size(), 2, "two saves")
	eq(String(all[0]["name"]), "Second", "newest first")
	eq(SaveGame.most_recent(), b, "continue picks the newest")
	check(SaveGame.describe(all[0]).begins_with("Level 3, start"), "a level start: %s" % SaveGame.describe(all[0]))
	check(SaveGame.describe(all[1]).begins_with("Level 2, round 7"), "a round: %s" % SaveGame.describe(all[1]))
	SaveGame.current = b
	SaveGame.remove(b)
	eq(SaveGame.list().size(), 1, "one left")
	eq(SaveGame.current, SaveGame.default_path(), "deleting the current save goes back to the autosave")
	_clear_dir()


func test_a_save_from_another_version_is_not_read() -> void:
	_use_test_dir()
	var p := SaveGame.new_path("old")
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_var({"version": SaveGame.VERSION + 1, "name": "old"})
	f.close()
	eq(SaveGame.read(p), {}, "skipped")
	eq(SaveGame.list().size(), 0, "and not listed")
	_clear_dir()
