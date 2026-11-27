## One building on one hex.
extends RefCounted

var id: int
var type: String
var hex: int
var hp: int            ## Buildings with HP. Bases and decoys use `hits` instead.
var hits: float        ## Hits taken by a base or decoy.
var disabled: bool     ## A weapon put out of action by a hit, until repaired.
var repairing: bool    ## Repair ordered this round; finishes at the next round start.
var built_round: int
var carrier_lost: bool ## An airport or docks whose carrier was lost, until it is replaced.
var boat_out: bool     ## Docks whose boat is at sea, until it has landed.
var loading: int       ## A silo's nuke being built: rounds until it can be fired (0: none being built).


func duplicate_building():
	var b = get_script().new()
	b.id = id
	b.type = type
	b.hex = hex
	b.hp = hp
	b.hits = hits
	b.disabled = disabled
	b.repairing = repairing
	b.built_round = built_round
	b.carrier_lost = carrier_lost
	b.boat_out = boat_out
	b.loading = loading
	return b


## A building from to_dict() (a saved game).
static func from_dict(d: Dictionary):
	var b = load("res://rules/building.gd").new()
	b.id = int(d["id"])
	b.type = String(d["type"])
	b.hex = int(d["hex"])
	b.hp = int(d["hp"])
	b.hits = float(d["hits"])
	b.disabled = bool(d["disabled"])
	b.repairing = bool(d["repairing"])
	b.built_round = int(d["built_round"])
	b.carrier_lost = bool(d["carrier_lost"])
	b.boat_out = bool(d["boat_out"])
	b.loading = int(d["loading"])
	return b


func to_dict() -> Dictionary:
	return {
		"id": id, "type": type, "hex": hex, "hp": hp, "hits": hits,
		"disabled": disabled, "repairing": repairing, "built_round": built_round, "carrier_lost": carrier_lost, "boat_out": boat_out,
		"loading": loading,
	}
