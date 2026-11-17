## Base for test scripts: assertions record failures instead of stopping.
extends RefCounted

const GameData = preload("res://rules/game_data.gd")
const MatchState = preload("res://rules/match_state.gd")
const Island = preload("res://rules/island.gd")
const HexGrid = preload("res://rules/hex_grid.gd")
const Rng = preload("res://rules/rng.gd")

var failures: Array[String] = []


func check(cond: bool, msg: String = "check failed") -> void:
	if not cond:
		failures.append(msg)


func eq(actual, expected, msg: String = "") -> void:
	if typeof(actual) in [TYPE_INT, TYPE_FLOAT] and typeof(expected) in [TYPE_INT, TYPE_FLOAT]:
		if is_equal_approx(float(actual), float(expected)):
			return
	elif actual == expected:
		return
	failures.append("%s expected %s, got %s" % [msg, str(expected), str(actual)])


func ok(err: String, msg: String = "") -> void:
	if err != "":
		failures.append("%s unexpected error: %s" % [msg, err])


func err_contains(err: String, fragment: String, msg: String = "") -> void:
	if not err.contains(fragment):
		failures.append("%s expected error containing '%s', got '%s'" % [msg, fragment, err])


# --- Fixtures --------------------------------------------------------------

func data():
	return GameData.load_default()


## A match where both islands are flat, all land, at level 0, setup is
## skipped, and buildings can be dropped in directly. Use `put` to place.
## Unless `with_bases` is false, each side gets three bases tucked in the
## bottom-right corner so a match does not end on its own.
func flat_match(d = null, seed_in: int = 1, with_bases: bool = true):
	if d == null:
		d = data()
	var m = MatchState.create(d, seed_in)
	for s in m.sides:
		var g = s.island.grid
		var isl = Island.new(g)
		for i in g.count:
			isl.land[i] = 1
			isl.level[i] = 0
		s.island = isl
		s.setup_done = true
	if with_bases:
		for side in 2:
			for cr in [Vector2i(14, 14), Vector2i(12, 14), Vector2i(14, 12)]:
				put(m, side, "base", cr.x, cr.y)
	return m


func put(m, side: int, type: String, col: int, row: int):
	var st = m.sides[side]
	var hex: int = st.island.grid.index_of(col, row)
	return st._add_building(type, hex, m.data, 0)


func hex(m, col: int, row: int) -> int:
	return m.sides[0].island.grid.index_of(col, row)


## Run one round with no build actions and the given launch orders.
func play_round(m, orders0: Array = [], orders1: Array = []) -> Array:
	m.begin_round()
	m.end_build_phase()
	ok(m.set_launch_orders(0, orders0), "orders side 0")
	ok(m.set_launch_orders(1, orders1), "orders side 1")
	return m.resolve_playout()


func events_of(events: Array, type: String) -> Array:
	return events.filter(func(e): return e["type"] == type)
