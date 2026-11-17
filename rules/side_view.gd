## What one side is allowed to know: its own island in full, and the
## opposing space only as its own strikes have revealed it. The AI receives
## nothing else, so it cannot cheat. Everything here is a copy.
extends RefCounted

var side: int
var round_number: int
var phase: int
var data
var settings: Dictionary
var own                       ## SideState copy
var enemy_width: int
var enemy_height: int
var enemy_knowledge: Dictionary   ## hex -> sighting (see MatchState.record_sighting)
var enemy_bases_destroyed: Array  ## hexes where this side has destroyed an enemy base
var enemy_bases_total: int


## Sighting at a hex, or null if never seen.
func seen(hex: int):
	return enemy_knowledge.get(hex)


func enemy_bases_left() -> int:
	return enemy_bases_total - enemy_bases_destroyed.size()
