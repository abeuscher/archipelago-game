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
	return b


func to_dict() -> Dictionary:
	return {
		"id": id, "type": type, "hex": hex, "hp": hp, "hits": hits,
		"disabled": disabled, "repairing": repairing, "built_round": built_round, "carrier_lost": carrier_lost, "boat_out": boat_out,
	}
