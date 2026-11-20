## Everything one side owns: its island, buildings, resources and research.
## Every rule that only touches one side's own island lives here, so the AI
## can run the same checks on its own copy.
extends RefCounted

const Building = preload("res://rules/building.gd")

var side: int
var island
var money: int
var fuel: int
var buildings: Dictionary = {}   ## hex -> Building
var next_building_id: int = 1
var unlocked: Dictionary = {}    ## research item -> true
## Research points on hand: labs add to them every round, research spends them.
var research: int = 0
var setup_done: bool = false


func _init(side_index: int = 0, isl = null, data = null) -> void:
	side = side_index
	island = isl
	if data != null:
		money = data.integer("economy", "start_money")
		fuel = data.integer("economy", "start_fuel")


func duplicate_state():
	var c = get_script().new(side, island, null)
	c.money = money
	c.fuel = fuel
	for h in buildings:
		c.buildings[h] = buildings[h].duplicate_building()
	c.next_building_id = next_building_id
	c.unlocked = unlocked.duplicate()
	c.research = research
	c.setup_done = setup_done
	return c


# --- Queries ---------------------------------------------------------------

func building_at(hex: int) -> Variant:
	return buildings.get(hex)


func building_by_id(id: int) -> Variant:
	for b in buildings.values():
		if b.id == id:
			return b
	return null


func buildings_sorted() -> Array:
	var out := buildings.values()
	out.sort_custom(func(a, b): return a.id < b.id)
	return out


func count_role(data, role: String) -> int:
	var n := 0
	for b in buildings.values():
		if data.role(b.type) == role:
			n += 1
	return n


func of_role(data, role: String) -> Array:
	var out: Array = []
	for b in buildings_sorted():
		if data.role(b.type) == role:
			out.append(b)
	return out


func bases_alive(data) -> int:
	return count_role(data, "base")


## Everything that shoots at incoming missiles: anti-air buildings and the
## guns mounted on strongholds, oldest first.
func anti_air_guns(data) -> Array:
	var out: Array = []
	for b in buildings_sorted():
		if data.role(b.type) == "anti_air" or data.mounts_anti_air(b.type):
			out.append(b)
	return out


func is_unlocked(item: String) -> bool:
	return unlocked.has(item)


func is_half_strength(b, data) -> bool:
	if data.is_weapon(b.type) or data.is_base_like(b.type):
		return false
	if b.repairing:
		return not out_for_repair(b, data)
	return data.flag("damage", "half_strength_when_damaged") and b.hp < data.max_hp(b.type)


## A building under repair is out of action for the round of the repair:
## weapons don't fire or defend, and nothing else produces or covers. With
## damage.repair_takes_building_out off, non-weapons work at half strength
## instead (the spec's section 9 rule).
func out_for_repair(b, data) -> bool:
	if not b.repairing or data.is_base_like(b.type):
		return false
	return data.is_weapon(b.type) or data.flag("damage", "repair_takes_building_out")


## What a building adds of one resource this round: nothing while out for
## repair, half while at half strength, otherwise the full amount.
func output_of(b, value: int, data) -> int:
	if out_for_repair(b, data):
		return 0
	if is_half_strength(b, data):
		return half_income(value, data)
	return value


## A weapon that can fire or defend this round.
func weapon_active(b) -> bool:
	return not b.disabled and not b.repairing


func half_income(value: int, data) -> int:
	if String(data.section("damage")["half_strength_income_rounding"]) == "up":
		return ceili(value / 2.0)
	return floori(value / 2.0)


func radar_range(b, data) -> int:
	var ranges: Array = data.section("radar")["range_by_level"]
	var lvl: int = clampi(island.level[b.hex], 0, ranges.size() - 1)
	var r := int(ranges[lvl])
	if out_for_repair(b, data):
		return 0
	if is_half_strength(b, data):
		r = maxi(int(data.section("damage")["radar_half_range_min"]), r / 2)
	return r


func anti_air_engagements(data) -> int:
	var aa: Dictionary = data.section("anti_air")
	if is_unlocked(String(aa["capacity_research"])):
		return int(aa["engagements_upgraded"])
	return int(aa["engagements"])


func building_unlocked(type: String, data) -> bool:
	var def: Dictionary = data.building(type)
	if not bool(def.get("buildable", true)):
		return false
	if def.has("requires") and not is_unlocked(String(def["requires"])):
		return false
	return true


func missile_unlocked(missile: String, data) -> bool:
	var def: Dictionary = data.missile(missile)
	return not def.has("requires") or is_unlocked(String(def["requires"]))


func repair_cost(type: String, data) -> int:
	var def: Dictionary = data.building(type)
	if def.has("repair_cost"):
		return int(def["repair_cost"])
	return roundi(data.cost(type) * data.num("damage", "repair_cost_fraction"))


## Bases and decoys can't be repaired; a stronghold can, to bring its gun
## back after a missile hit.
func can_be_repaired(type: String, data) -> bool:
	return data.is_missile_proof(type) or not data.is_base_like(type)


func needs_repair(b, data) -> bool:
	if not can_be_repaired(b.type, data) or b.repairing:
		return false
	return b.disabled or b.hp < data.max_hp(b.type)


## Money, fuel and research the side will receive at the next round start.
func compute_income(data) -> Dictionary:
	var eco: Dictionary = data.section("economy")
	var inc := {
		"money": int(eco["baseline_money"]),
		"fuel": int(eco["baseline_fuel"]),
		"research": int(eco["baseline_research"]),
	}
	for b in buildings_sorted():
		var produces := produces_of(b.type, data)
		for res in produces:
			inc[res] += output_of(b, int(produces[res]), data)
	return inc


## What a building of this type makes a round at full strength: its
## upgraded amounts once the upgrade's research is done.
func produces_of(type: String, data) -> Dictionary:
	var def: Dictionary = data.building(type)
	var up: Dictionary = def.get("upgrade", {})
	if not up.is_empty() and is_unlocked(String(up["research"])):
		return up["produces"]
	return def.get("produces", {})


# --- Placement checks ------------------------------------------------------

func _base_spacing_error(hex: int, data) -> String:
	if not data.flag("bases", "no_adjacent_bases_or_decoys"):
		return ""
	for n in island.grid.neighbors(hex):
		var other = buildings.get(n)
		if other != null and data.is_base_like(other.type):
			return "Too close to another base or decoy"
	return ""


func _hex_error(hex: int) -> String:
	if not island.grid.is_valid(hex):
		return "Off the map"
	if not island.is_land(hex):
		return "Not land"
	if buildings.has(hex):
		return "Hex is occupied"
	return ""


## Whether a base or decoy may stand on this hex (ignores money and limits).
func can_place_base_like(hex: int, data) -> String:
	var e := _hex_error(hex)
	if e != "":
		return e
	return _base_spacing_error(hex, data)


func can_build(type: String, hex: int, data, settings: Dictionary) -> String:
	if not data.has_building(type):
		return "Unknown building"
	if not building_unlocked(type, data):
		return "Not available yet"
	var e := _hex_error(hex)
	if e != "":
		return e
	if bool(data.building(type).get("coastal", false)) and not island.is_coastal(hex):
		return "Must be built on the coast"
	if data.role(type) == "decoy":
		if count_role(data, "decoy") >= int(settings["decoys_per_side"]):
			return "Decoy limit reached"
		e = _base_spacing_error(hex, data)
		if e != "":
			return e
	if money < data.cost(type):
		return "Not enough money"
	return ""


func _add_building(type: String, hex: int, data, round_number: int) -> Variant:
	var b := Building.new()
	b.id = next_building_id
	next_building_id += 1
	b.type = type
	b.hex = hex
	b.hp = data.max_hp(type)
	b.built_round = round_number
	# A silo starts empty: its first nuke is built like a replacement.
	var ms: Array = data.building(type).get("missiles", [])
	if not ms.is_empty() and bool(data.missile(String(ms[0])).get("spent_on_launch", false)):
		b.carrier_lost = true
	buildings[hex] = b
	return b


## Place the three bases and any decoys before round 1. The first
## bases.strongholds_per_side of base_hexes are strongholds.
func setup(base_hexes: Array, decoy_hexes: Array, data, settings: Dictionary) -> String:
	if setup_done:
		return "Setup already done"
	var per_side: int = data.integer("bases", "per_side")
	if base_hexes.size() != per_side:
		return "Place exactly %d bases" % per_side
	if decoy_hexes.size() > int(settings["decoys_per_side"]):
		return "Too many decoys"
	var trial = duplicate_state()
	var strongholds := strongholds_per_side(data)
	for k in base_hexes.size():
		var h := int(base_hexes[k])
		var e: String = trial._hex_error(h)
		if e == "":
			e = trial._base_spacing_error(h, data)
		if e != "":
			return e
		trial._add_building("stronghold" if k < strongholds else "base", h, data, 0)
	for h in decoy_hexes:
		var e: String = trial.can_build("decoy", int(h), data, settings)
		if e != "":
			return e
		trial.money -= data.cost("decoy")
		trial._add_building("decoy", int(h), data, 0)
	_copy_from(trial)
	setup_done = true
	return ""


static func strongholds_per_side(data) -> int:
	return int(data.section("bases").get("strongholds_per_side", 0))


func build(type: String, hex: int, data, settings: Dictionary, round_number: int) -> String:
	var e := can_build(type, hex, data, settings)
	if e != "":
		return e
	money -= data.cost(type)
	_add_building(type, hex, data, round_number)
	return ""


func can_repair(hex: int, data) -> String:
	var b = buildings.get(hex)
	if b == null:
		return "Nothing to repair"
	if not can_be_repaired(b.type, data):
		return "Bases and decoys cannot be repaired"
	if b.repairing:
		return "Already under repair"
	if not needs_repair(b, data):
		return "Not damaged"
	if money < repair_cost(b.type, data):
		return "Not enough money"
	return ""


## Repair restores full HP now. The building is out for this round (see
## out_for_repair) and returns fully next round.
func repair(hex: int, data) -> String:
	var e := can_repair(hex, data)
	if e != "":
		return e
	var b = buildings[hex]
	money -= repair_cost(b.type, data)
	b.hp = data.max_hp(b.type)
	b.repairing = true
	return ""


# --- Research --------------------------------------------------------------
# Research points are a resource like money and fuel: labs add to the pool
# every round, and an item is bought outright with its money and points.

## Items this side could buy now, money and points aside.
func research_available(data) -> Array:
	var out: Array = []
	for item in data.research_items():
		if research_block(item, data) == "":
			out.append(item)
	return out


## Why an item can't be researched at all yet ("" if it can, money and
## points aside).
func research_block(item: String, data) -> String:
	if not data.rules["research"].has(item):
		return "Unknown research"
	if is_unlocked(item):
		return "Already researched"
	if not bool(data.research_item(item).get("available", true)):
		return "Coming soon"
	var needs := int(data.research_item(item).get("needs_researched", 0))
	if researched_count() < needs:
		return "Needs %d research done first (%d/%d)" % [needs, researched_count(), needs]
	return ""


func can_research(item: String, data) -> String:
	var e := research_block(item, data)
	if e != "":
		return e
	if money < int(data.research_item(item)["cost"]):
		return "Not enough money"
	if research < int(data.research_item(item)["points"]):
		return "Not enough research"
	return ""


## Pays the item's money and points and unlocks it now.
func do_research(item: String, data) -> String:
	var e := can_research(item, data)
	if e != "":
		return e
	money -= int(data.research_item(item)["cost"])
	research -= int(data.research_item(item)["points"])
	unlocked[item] = true
	return ""


## How many research items this side has finished.
func researched_count() -> int:
	return unlocked.size()


# --- Round flow ------------------------------------------------------------

## Nukes being built get a round closer to ready.
func _advance_loading() -> void:
	for b in buildings.values():
		if b.loading > 0:
			b.loading -= 1


func _finish_repairs() -> void:
	for b in buildings.values():
		if b.repairing:
			b.repairing = false
			b.disabled = false


## Pay income if this round earns it and finish last round's repairs.
## Income is what the side made over the last round, so a building that
## spent it out for repair adds nothing; with repair_takes_building_out off,
## repairs finish first and pay in full as before.
## Returns {"income": Dictionary or {}}.
func begin_round(round_number: int, data) -> Dictionary:
	var out_first: bool = data.flag("damage", "repair_takes_building_out")
	if not out_first:
		_finish_repairs()
	_advance_loading()
	var result := {"income": {}}
	if round_number >= data.integer("economy", "income_from_round"):
		var inc := compute_income(data)
		money += int(inc["money"])
		fuel += int(inc["fuel"])
		research += int(inc["research"])
		result["income"] = inc
	if out_first:
		_finish_repairs()
	return result


func remove_building(hex: int, data) -> void:
	var b = buildings.get(hex)
	if b == null:
		return
	buildings.erase(hex)


# --- Launch checks ---------------------------------------------------------

## orders: Array of {"launcher": hex, "missile": String, "target": hex},
## plus "dir" (an index into HexGrid.AXIAL_DIRS, the march direction) for a
## transport. A launcher here is a missile launcher or an airport.
## `target_count` is the number of hexes in the opposing space.
func validate_launches(orders: Array, data, target_count: int) -> String:
	var used := {}
	var total_fuel := 0
	var total_money := 0
	for o in orders:
		var hex := int(o["launcher"])
		var b = buildings.get(hex)
		if b == null or not (data.role(b.type) in LAUNCH_ROLES):
			return "No launcher there"
		if used.has(hex):
			return "Launcher already has an order"
		used[hex] = true
		if not weapon_active(b):
			return "Launcher is out of action"
		if b.carrier_lost:
			return {"airport": "Transport lost", "silo": "No nuke"}.get(data.role(b.type), "Boat lost")
		if b.boat_out:
			return "Boat at sea"
		if b.loading > 0:
			return "Nuke not ready"
		var m := String(o["missile"])
		if not data.building(b.type)["missiles"].has(m):
			return "That launcher cannot fire that missile"
		if not missile_unlocked(m, data):
			return "Missile not researched"
		var t := int(o["target"])
		if t < 0 or t >= target_count:
			return "Target off the map"
		if data.missile(m).has("carries"):
			var d := int(o.get("dir", -1))
			if d < 0 or d > 5:
				return "Choose a direction to march"
		total_fuel += int(data.missile(m)["fuel"])
		total_money += int(data.missile(m).get("money", 0))
	if total_fuel > fuel:
		return "Not enough fuel"
	if total_money > money:
		return "Not enough money"
	return ""


const LAUNCH_ROLES := ["launcher", "airport", "docks", "silo"]


func launch_money(orders: Array, data) -> int:
	var total := 0
	for o in orders:
		total += int(data.missile(String(o["missile"])).get("money", 0))
	return total


## What a new transport or boat costs for this airport or docks.
func carrier_cost(b, data) -> int:
	var ms: Array = data.building(b.type).get("missiles", [])
	return int(data.missile(String(ms[0])).get("replace_money", 0)) if not ms.is_empty() else 0


func can_replace_carrier(hex: int, data) -> String:
	var b = buildings.get(hex)
	if b == null or not b.carrier_lost:
		return "Nothing to replace"
	if data.role(b.type) == "silo" and not weapon_active(b):
		return "Repair the silo first"
	if money < carrier_cost(b, data):
		return "Not enough money"
	return ""


## Buys a new transport or boat for an airport or docks that lost its last.
func replace_carrier(hex: int, data) -> String:
	var e := can_replace_carrier(hex, data)
	if e != "":
		return e
	var b = buildings[hex]
	money -= carrier_cost(b, data)
	b.carrier_lost = false
	var ms: Array = data.building(b.type).get("missiles", [])
	b.loading = int(data.missile(String(ms[0])).get("build_rounds", 0)) if not ms.is_empty() else 0
	return ""


func launch_fuel(orders: Array, data) -> int:
	var total := 0
	for o in orders:
		total += int(data.missile(String(o["missile"]))["fuel"])
	return total


func _copy_from(other) -> void:
	money = other.money
	fuel = other.fuel
	buildings = other.buildings
	next_building_id = other.next_building_id
	unlocked = other.unlocked
	research = other.research
