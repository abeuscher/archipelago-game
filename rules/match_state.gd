## One island duel between side 0 (the player) and side 1 (the enemy).
## Pure rules: no scenes, no rendering, no clocks. The presentation and the
## batch runner drive it through the same calls.
##
## Flow: create -> setup_side x2 -> [begin_round -> build_action* ->
## end_build_phase -> set_launch_orders x2 -> resolve_playout] repeated until
## phase == GAME_OVER (or COIN_FLIP, then resolve_coin_flip).
extends RefCounted

const Rng = preload("res://rules/rng.gd")
const Island = preload("res://rules/island.gd")
const SideState = preload("res://rules/side_state.gd")
const SideView = preload("res://rules/side_view.gd")
const Resolver = preload("res://rules/resolver.gd")

enum Phase { SETUP, BUILD, TARGETING, ROUND_OVER, COIN_FLIP, GAME_OVER }

const PLAYER := 0
const ENEMY := 1
## The enemy's strikes land on the player first, then the player's land.
const LAUNCH_ORDER := [ENEMY, PLAYER]
const COIN_FACES := ["heads", "tails"]

var data
var settings: Dictionary
var seed_value: int
var dice
var sides: Array = []
var knowledge: Array = [{}, {}]            ## side -> hex -> sighting of the opposing space
var bases_destroyed_by: Array = [[], []]   ## side -> hexes of enemy bases it destroyed
## side -> hex -> {"count", "last_round"}: missiles that landed on this side's
## island (where they finally exploded, after any seeking).
var bombed: Array = [{}, {}]
## side -> boats at sea: {"id", "side", "launcher", "target", "dir", "lands_round"}.
## Both sides can see them in the channel.
var boats: Array = [[], []]
## side -> how many enemy boats have come ashore (or been sunk) at its coast.
## The defender sees every one arrive, so its AI may know it.
var boats_arrived_at: Array = [0, 0]
## side -> its foreign agents on the enemy island: {"id", "missile", "hex",
## "enclave" (building id), "landed_round"}. Only that side knows where they are.
var spies: Array = [[], []]
## side -> its domestic agents on its own island: {"id", "enclave", "hex"}.
var agents: Array = [[], []]
## side -> hexes of its island where enemy agents were seen landing, until a
## patrol gets there.
var spy_sightings: Array = [[], []]
## side -> hex -> round a domestic agent was last there.
var patrolled: Array = [{}, {}]
## side -> enclave id -> first round a new domestic agent may muster there
## (after one was killed by a stealth missile).
var agent_respawn: Array = [{}, {}]
var round_number: int = 0
var phase: int = Phase.SETUP
var orders: Array = [[], []]
var winner: int = -1
var end_reason: String = ""
var coin: Dictionary = {}
var history: Array = []                    ## every event, in order, with its round
var stats: Array = []
var _destroyed_this_round: Dictionary = {}   ## Vector2i(side, hex) -> building type


static func create(game_data, seed_in: int, settings_override: Dictionary = {}):
	var script: GDScript = load("res://rules/match_state.gd")
	var m = script.new()
	m.data = game_data
	m.settings = game_data.settings.duplicate(true)
	for k in settings_override:
		m.settings[k] = settings_override[k]
	m.seed_value = seed_in
	m.dice = Rng.derive(seed_in, "dice")
	for s in 2:
		var isl = Island.generate(game_data, Rng.derive(seed_in, "island_%d" % s))
		m.sides.append(SideState.new(s, isl, game_data))
		m.stats.append({"fired": 0, "intercepted": 0})
	return m


func opponent(side: int) -> int:
	return 1 - side


func _log(event: Dictionary) -> void:
	event["round"] = round_number
	history.append(event)


# --- Setup -----------------------------------------------------------------

func setup_side(side: int, base_hexes: Array, decoy_hexes: Array) -> String:
	if phase != Phase.SETUP:
		return "Not in setup"
	var e: String = sides[side].setup(base_hexes, decoy_hexes, data, settings)
	if e == "":
		_log({"type": "setup", "side": side})
	return e


# --- Round flow ------------------------------------------------------------

func begin_round() -> Array:
	assert(phase == Phase.SETUP or phase == Phase.ROUND_OVER, "begin_round called mid-round")
	assert(sides[0].setup_done and sides[1].setup_done, "Both sides must finish setup")
	round_number += 1
	phase = Phase.BUILD
	orders = [[], []]
	_destroyed_this_round.clear()
	var events: Array = []
	for s in 2:
		var r: Dictionary = sides[s].begin_round(round_number, data)
		if not r["income"].is_empty():
			events.append({"type": "income", "side": s, "income": r["income"]})
		for item in r["research_completed"]:
			events.append({"type": "research_done", "side": s, "item": item})
	events.push_front({"type": "round_start"})
	for ev in events:
		_log(ev)
	return events


## action: {"action": "build", "type": String, "hex": int}
##       | {"action": "repair", "hex": int}
##       | {"action": "research", "lab": building id, "item": String}
##       | {"action": "use_stored_research", "item": String}
func build_action(side: int, action: Dictionary) -> String:
	if phase != Phase.BUILD:
		return "Not in the build and repair phase"
	var st = sides[side]
	var e := ""
	match String(action.get("action", "")):
		"build":
			e = st.build(String(action["type"]), int(action["hex"]), data, settings, round_number)
		"repair":
			e = st.repair(int(action["hex"]), data)
		"research":
			e = st.start_research(int(action["lab"]), String(action["item"]), data)
		"use_stored_research":
			e = st.use_stored_research(String(action["item"]), data)
		"replace_carrier":
			e = st.replace_carrier(int(action["hex"]), data)
		_:
			e = "Unknown action"
	if e == "":
		var ev := action.duplicate()
		ev["type"] = "build_action"
		ev["side"] = side
		_log(ev)
	return e


func end_build_phase() -> void:
	assert(phase == Phase.BUILD)
	phase = Phase.TARGETING


## Replaces the side's launch orders for this round. Fuel is checked here
## and spent at playout, so any order can be undone at no cost.
func set_launch_orders(side: int, new_orders: Array) -> String:
	if phase != Phase.TARGETING:
		return "Not in the targeting phase"
	var target_count: int = sides[opponent(side)].island.grid.count
	var e: String = sides[side].validate_launches(new_orders, data, target_count)
	if e != "":
		return e
	for o in new_orders:
		if data.missile(String(o["missile"])).has("walks") and agent_out(side, int(o["launcher"])):
			return "This enclave's agent is still on the enemy island"
	orders[side] = new_orders.duplicate(true)
	return ""


## Whether the enclave at this hex has a foreign agent on the enemy island.
func agent_out(side: int, enclave_hex: int) -> bool:
	var b = sides[side].building_at(enclave_hex)
	return b != null and spies[side].any(func(sp): return int(sp["enclave"]) == b.id)


func resolve_playout() -> Array:
	assert(phase == Phase.TARGETING)
	var events: Array = Resolver.resolve(self)
	events.append_array(_check_outcome())
	for ev in events:
		_log(ev)
	if phase == Phase.TARGETING:
		phase = Phase.ROUND_OVER
	return events


func _check_outcome() -> Array:
	var alive := [sides[0].bases_alive(data), sides[1].bases_alive(data)]
	if alive[0] > 0 and alive[1] > 0:
		return []
	if alive[0] == 0 and alive[1] == 0:
		if sides[0].money != sides[1].money:
			_finish(PLAYER if sides[0].money > sides[1].money else ENEMY, "money")
		else:
			phase = Phase.COIN_FLIP
			coin = {"call": dice.pick(COIN_FACES), "flip": ""}
			return [{"type": "coin_flip_needed", "call": coin["call"]}]
	else:
		_finish(PLAYER if alive[0] > 0 else ENEMY, "bases")
	return [{"type": "game_over", "winner": winner, "reason": end_reason}]


## The enemy called when the tie happened (coin["call"]); the player's click
## triggers this flip. Both come from the seeded dice.
func resolve_coin_flip() -> Array:
	assert(phase == Phase.COIN_FLIP)
	var call: String = coin["call"]
	var flip: String = dice.pick(COIN_FACES)
	coin["flip"] = flip
	_finish(ENEMY if call == flip else PLAYER, "coin")
	var events := [
		{"type": "coin_flip", "call": call, "flip": flip},
		{"type": "game_over", "winner": winner, "reason": end_reason},
	]
	for ev in events:
		_log(ev)
	return events


func _finish(w: int, reason: String) -> void:
	winner = w
	end_reason = reason
	phase = Phase.GAME_OVER


func is_over() -> bool:
	return phase == Phase.GAME_OVER


# --- Fog and knowledge -----------------------------------------------------

## Records what `viewer` now sees at `hex` in the opposing space.
func record_sighting(viewer: int, hex: int) -> void:
	var target = sides[opponent(viewer)]
	var isl = target.island
	var old: Dictionary = knowledge[viewer].get(hex, {})
	var entry := {
		"seen_round": round_number,
		"land": isl.is_land(hex),
		"level": isl.level[hex],
		"building": null,
		"destroyed": "",
	}
	var b = target.building_at(hex)
	if b != null:
		entry["building"] = _public_building(b)
	elif old.get("building") == null and String(old.get("destroyed", "")) != "":
		entry["destroyed"] = old["destroyed"]
	if b == null and _destroyed_this_round.has(Vector2i(opponent(viewer), hex)):
		entry["destroyed"] = _destroyed_this_round[Vector2i(opponent(viewer), hex)]
	knowledge[viewer][hex] = entry


func note_bombed(side: int, hex: int) -> void:
	var e: Dictionary = bombed[side].get(hex, {"count": 0, "last_round": 0})
	e["count"] = int(e["count"]) + 1
	e["last_round"] = round_number
	bombed[side][hex] = e


func note_destroyed(side: int, hex: int, type: String) -> void:
	_destroyed_this_round[Vector2i(side, hex)] = type
	if data.role(type) == "base":
		bases_destroyed_by[opponent(side)].append(hex)


## How a building looks to the other side. Bases and decoys look the same
## until a decoy survives enough hits to give itself away.
func _public_building(b) -> Dictionary:
	var shown: String = b.type
	if data.is_base_like(b.type):
		shown = "suspected_base"
		var bdef: Dictionary = data.building(b.type)
		if data.is_missile_proof(b.type) and b.hits > 0.0:
			shown = b.type   # a missile hit gave the stronghold away
		if bdef.has("reveals_as_decoy_at_hits") and b.hits >= float(bdef["reveals_as_decoy_at_hits"]):
			shown = "decoy"
	var out := {
		"type": shown,
		"hits": b.hits,
		"damaged": b.hp < data.max_hp(b.type),
		"disabled": b.disabled,
		"repairing": b.repairing,
	}
	if data.role(b.type) == "silo":
		# Whoever sees a silo sees its lid: open (empty or loading) or shut (armed).
		out["nuke"] = "none" if b.carrier_lost else ("loading" if b.loading > 0 else "armed")
	return out


func view_for(side: int):
	var v := SideView.new()
	v.side = side
	v.round_number = round_number
	v.phase = phase
	v.data = data
	v.settings = settings.duplicate(true)
	v.own = sides[side].duplicate_state()
	var g = sides[opponent(side)].island.grid
	v.enemy_width = g.width
	v.enemy_height = g.height
	v.enemy_knowledge = knowledge[side].duplicate(true)
	v.enemy_bases_destroyed = bases_destroyed_by[side].duplicate()
	v.enemy_bases_total = data.integer("bases", "per_side")
	v.own_seen_by_enemy = {}
	v.boats = boats.duplicate(true)
	v.enemy_boats_arrived = boats_arrived_at[side]
	v.own_spies = spies[side].duplicate(true)
	v.own_agents = agents[side].duplicate(true)
	for h in knowledge[opponent(side)]:
		v.own_seen_by_enemy[h] = true
	return v


## A stable fingerprint of the full match state, for determinism tests.
func fingerprint() -> String:
	var parts: Array = [round_number, phase, winner, end_reason, dice.get_state()]
	for s in sides:
		var bl: Array = []
		for b in s.buildings_sorted():
			bl.append(b.to_dict())
		parts.append([s.money, s.fuel, bl, s.unlocked.keys(), s.projects, s.stored_research])
	parts.append(knowledge)
	parts.append(spies)
	parts.append(agents)
	return str(parts).sha256_text()
