## Plays one full match between two AIs, headless. Used by the batch runner
## and by tests. No scenes, no clocks.
extends RefCounted

const MatchState = preload("res://rules/match_state.gd")


## ais: [ai for side 0, ai for side 1], each with choose_setup/build/targets.
static func play(game_data, seed_in: int, ais: Array, max_rounds: int, settings_override: Dictionary = {}) -> Dictionary:
	var m = MatchState.create(game_data, seed_in, settings_override)
	var errors: Array = []
	for s in 2:
		var setup: Dictionary = ais[s].choose_setup(m.view_for(s))
		var e: String = m.setup_side(s, setup["bases"], setup["decoys"])
		if e != "":
			errors.append("side %d setup: %s" % [s, e])
			return _result(m, seed_in, errors, false)
	while not m.is_over() and m.round_number < max_rounds:
		m.begin_round()
		var planned: Array = []
		for s in 2:
			planned.append(ais[s].choose_build(m.view_for(s)))
		for s in 2:
			for a in planned[s]:
				var e: String = m.build_action(s, a)
				if e != "":
					errors.append("round %d side %d %s: %s" % [m.round_number, s, str(a), e])
		m.end_build_phase()
		var orders: Array = []
		for s in 2:
			orders.append(ais[s].choose_targets(m.view_for(s)))
		for s in 2:
			var e: String = m.set_launch_orders(s, orders[s])
			if e != "":
				errors.append("round %d side %d orders: %s" % [m.round_number, s, e])
		m.resolve_playout()
		if m.phase == MatchState.Phase.COIN_FLIP:
			m.resolve_coin_flip()
	return _result(m, seed_in, errors, not m.is_over())


static func _result(m, seed_in: int, errors: Array, timed_out: bool) -> Dictionary:
	return {
		"seed": seed_in,
		"rounds": m.round_number,
		"winner": m.winner,
		"reason": m.end_reason if not timed_out else "timeout",
		"timed_out": timed_out,
		"fired": [m.stats[0]["fired"], m.stats[1]["fired"]],
		"intercepted": [m.stats[0]["intercepted"], m.stats[1]["intercepted"]],
		"fingerprint": m.fingerprint(),
		"errors": errors,
	}
