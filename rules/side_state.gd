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
## Each project: {"item": String, "progress": int, "order": int, "lab_id": int}
## lab_id is -1 when the lab that started it has been destroyed.
var projects: Array = []
var next_project_order: int = 1
## Research points earned with no project to go into, and any left over when
## a project finishes. Spent on a project at will to speed it up or finish it.
var stored_research: int = 0
var setup_done: bool = false


func _init(side_index: int = 0, isl = null, data = null) -> void:
	side = side_index
	island = isl
	if data != null:
		money = data.integer("economy", "start_money")
		fuel = data.integer("economy", "start_fuel")
		for item in starting_research(data):
			unlocked[item] = true


func duplicate_state():
	var c = get_script().new(side, island, null)
	c.money = money
	c.fuel = fuel
	for h in buildings:
		c.buildings[h] = buildings[h].duplicate_building()
	c.next_building_id = next_building_id
	c.unlocked = unlocked.duplicate()
	c.projects = projects.duplicate(true)
	c.next_project_order = next_project_order
	c.stored_research = stored_research
	c.setup_done = setup_done
	return c


## Research both sides start a level with, carried over from the levels
## before it (start_researched in data/levels.json's "set").
static func starting_research(data) -> Array:
	var out: Array = []
	for item in data.research_items():
		var def = data.rules["research"][item]
		if def is Dictionary and bool(def.get("start_researched", false)) and bool(def.get("available", true)):
			out.append(item)
	out.sort()
	return out


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
	if not bool(def.get("buildable", true)) or not bool(def.get("available", true)):
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

func project_for_lab(lab_id: int) -> Variant:
	for p in projects:
		if int(p["lab_id"]) == lab_id:
			return p
	return null


func project_for_item(item: String) -> Variant:
	for p in projects:
		if String(p["item"]) == item:
			return p
	return null


func oldest_project() -> Variant:
	var best = null
	for p in projects:
		if best == null or int(p["order"]) < int(best["order"]):
			best = p
	return best


## Items this side could start now (ignoring money).
func research_available(data) -> Array:
	var out: Array = []
	for item in data.research_items():
		if is_unlocked(item) or not bool(data.research_item(item).get("available", true)) \
				or researched_count() < int(data.research_item(item).get("needs_researched", 0)):
			continue
		var first := String(data.research_item(item).get("needs", ""))
		if first != "" and not is_unlocked(first):
			continue
		var p = project_for_item(item)
		if p != null and int(p["lab_id"]) != -1:
			continue
		out.append(item)
	return out


func can_start_research(lab_id: int, item: String, data) -> String:
	var lab = building_by_id(lab_id)
	if lab == null or data.role(lab.type) != "lab":
		return "No such lab"
	if project_for_lab(lab_id) != null:
		return "Lab is already researching"
	if not data.rules["research"].has(item):
		return "Unknown research"
	if is_unlocked(item):
		return "Already researched"
	if not bool(data.research_item(item).get("available", true)):
		return "Coming soon"
	var first := String(data.research_item(item).get("needs", ""))
	if first != "" and not is_unlocked(first):
		return "Needs %s research first" % first.capitalize()
	var needs := int(data.research_item(item).get("needs_researched", 0))
	if researched_count() < needs:
		return "Needs %d research done first (%d/%d)" % [needs, researched_count(), needs]
	var p = project_for_item(item)
	if p != null:
		if int(p["lab_id"]) != -1:
			return "Another lab is researching that"
		return ""   # Resuming an orphaned project is free.
	if money < int(data.research_item(item)["cost"]):
		return "Not enough money"
	return ""


## How many research items this side has finished.
func researched_count() -> int:
	return unlocked.size()


func start_research(lab_id: int, item: String, data) -> String:
	var e := can_start_research(lab_id, item, data)
	if e != "":
		return e
	var p = project_for_item(item)
	if p != null:
		p["lab_id"] = lab_id
		return ""
	money -= int(data.research_item(item)["cost"])
	projects.append({"item": item, "progress": 0, "order": next_project_order, "lab_id": lab_id})
	next_project_order += 1
	return ""


## Spends stored research points on a running project: as many as it still
## needs, or all of them. A project that reaches its total finishes now.
func can_use_stored_research(item: String, data) -> String:
	if project_for_item(item) == null:
		return "No such project"
	if stored_research <= 0:
		return "No stored research"
	return ""


func use_stored_research(item: String, data) -> String:
	var e := can_use_stored_research(item, data)
	if e != "":
		return e
	var p = project_for_item(item)
	var need := int(data.research_item(item)["points"]) - int(p["progress"])
	var spend := mini(need, stored_research)
	stored_research -= spend
	p["progress"] = int(p["progress"]) + spend
	if int(p["progress"]) >= int(data.research_item(item)["points"]):
		unlocked[item] = true
		projects.erase(p)
	return ""


func _accrue_research(data, points_baseline: int) -> Array:
	var completed: Array = []
	if projects.is_empty():
		# Nothing to work on: the labs' points are stored for later.
		stored_research += points_baseline
		for lab in of_role(data, "lab"):
			stored_research += output_of(lab, int(data.building(lab.type)["produces"].get("research", 0)), data)
		return completed
	var oldest = oldest_project()
	if oldest != null:
		oldest["progress"] = int(oldest["progress"]) + points_baseline
	for lab in of_role(data, "lab"):
		var pts := output_of(lab, int(data.building(lab.type)["produces"].get("research", 0)), data)
		var target = project_for_lab(lab.id)
		if target == null:
			target = oldest_project()
		if target != null:
			target["progress"] = int(target["progress"]) + pts
	for p in projects.duplicate():
		var need := int(data.research_item(String(p["item"]))["points"])
		if int(p["progress"]) >= need:
			stored_research += int(p["progress"]) - need   # points past the total are kept
			unlocked[String(p["item"])] = true
			projects.erase(p)
			completed.append(String(p["item"]))
	return completed


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
## Returns {"income": Dictionary or {}, "research_completed": Array}.
func begin_round(round_number: int, data) -> Dictionary:
	var out_first: bool = data.flag("damage", "repair_takes_building_out")
	if not out_first:
		_finish_repairs()
	_advance_loading()
	var result := {"income": {}, "research_completed": []}
	if round_number >= data.integer("economy", "income_from_round"):
		var inc := compute_income(data)
		money += int(inc["money"])
		fuel += int(inc["fuel"])
		result["income"] = inc
		result["research_completed"] = _accrue_research(data, data.integer("economy", "baseline_research"))
	if out_first:
		_finish_repairs()
	return result


func remove_building(hex: int, data) -> void:
	var b = buildings.get(hex)
	if b == null:
		return
	if data.role(b.type) == "lab":
		var p = project_for_lab(b.id)
		if p != null:
			p["lab_id"] = -1
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
		var m := String(o["missile"])
		if b.carrier_lost and not bool(data.missile(m).get("own_aircraft", false)):
			return {"airport": "Transport lost", "silo": "No nuke"}.get(data.role(b.type), "Boat lost")
		if b.boat_out:
			return "Boat at sea"
		if b.loading > 0:
			return "Nuke not ready"
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


const LAUNCH_ROLES := ["launcher", "airport", "docks", "silo", "enclave"]


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
	projects = other.projects
	next_project_order = other.next_project_order
	stored_research = other.stored_research
