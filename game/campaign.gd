## Where the player is in the campaign, kept for as long as the game runs
## (static, so it survives reloading the match scene). Saving it to disk
## comes later.
extends RefCounted

const Levels = preload("res://rules/levels.gd")

static var level: int = 1
## Money awarded by the last win, added to the starting money of the level
## it unlocked.
static var award_money: int = 0


static func has_next() -> bool:
	return level < Levels.count()


## Moves on to the next level, carrying the award for the one just won.
static func advance() -> void:
	award_money = int(Levels.level(level).get("win_award_money", 0))
	level = mini(level + 1, Levels.count())


static func restart() -> void:
	level = 1
	award_money = 0
