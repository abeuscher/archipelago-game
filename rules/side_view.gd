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
## Own hexes the enemy has revealed (hex -> true). A side sees where enemy
## missiles land on its own island, so this tells it nothing hidden; the
## player sees the same set drawn lighter on their island.
var own_seen_by_enemy: Dictionary
var boats: Array = [[], []]       ## boats at sea, both sides (visible in the channel)


## Sighting at a hex, or null if never seen.
func seen(hex: int):
	return enemy_knowledge.get(hex)


func enemy_bases_left() -> int:
	return enemy_bases_total - enemy_bases_destroyed.size()
