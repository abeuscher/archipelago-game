## Building pieces: rendered sprites (see draw_piece), with upright
## placeholder blocks as the fallback when a sheet is missing.
extends RefCounted

const Textures = preload("res://game/textures.gd")

const NAMES := {
	"base": "Base", "decoy": "Decoy", "suspected_base": "Potential base", "stronghold": "Stronghold",
	"bank": "Bank", "refinery": "Refinery", "lab": "Lab",
	"basic_launcher": "Missile launcher", "anti_air": "Anti-air", "radar": "Radar",
	"ballistic_launcher": "Ballistic launcher", "airport": "Airport", "bunker": "Bunker",
	"docks": "Docks", "coastal_cannon": "Coastal cannon", "nuclear_silo": "Nuclear silo",
	"enclave": "Enclave", "stealth_silo": "Stealth silo",
}
const SHORT := {
	"base": "BASE", "decoy": "BASE", "suspected_base": "?", "stronghold": "SH", "bank": "$", "refinery": "F",
	"lab": "R", "basic_launcher": "M", "anti_air": "AA", "radar": "RD", "ballistic_launcher": "BM",
	"airport": "AP", "bunker": "BK", "docks": "DK", "coastal_cannon": "CC", "nuclear_silo": "N",
	"enclave": "EN", "stealth_silo": "SS",
}
const COLORS := {
	"base": Color(0.85, 0.85, 0.9), "decoy": Color(0.85, 0.85, 0.9),
	"suspected_base": Color(0.85, 0.85, 0.9), "stronghold": Color(0.75, 0.72, 0.62),
	"bank": Color(0.95, 0.80, 0.25), "refinery": Color(0.85, 0.45, 0.20), "lab": Color(0.45, 0.75, 0.95),
	"basic_launcher": Color(0.85, 0.25, 0.25), "anti_air": Color(0.30, 0.75, 0.40),
	"radar": Color(0.70, 0.45, 0.90), "ballistic_launcher": Color(0.60, 0.15, 0.15),
	"airport": Color(0.62, 0.62, 0.92), "bunker": Color(0.62, 0.62, 0.58),
	"docks": Color(0.38, 0.72, 0.72), "coastal_cannon": Color(0.5, 0.6, 0.78),
	"nuclear_silo": Color(0.45, 0.36, 0.32), "enclave": Color(0.30, 0.32, 0.38),
	"stealth_silo": Color(0.22, 0.24, 0.30),
}
const MISSILE_NAMES := {"basic": "Basic missile", "scouting": "Scouting missile", "ballistic": "Ballistic missile",
	"transport": "Air transport", "boat": "Boat", "nuke": "Nuke", "spy": "Foreign agent", "stealth": "Stealth missile"}
## One-line descriptions for tooltips and the research panel. Numbers are
## not written here; they come from data where they are shown.
const BUILDING_TEXT := {
	"base": "Lose all three and you lose the island.",
	"stronghold": "A base that missiles can't destroy, with an anti-air gun on its roof. Only troops can take it. A missile hit knocks out the gun until repaired.",
	"decoy": "Looks exactly like a base to the enemy, but falls to a single hit.",
	"bank": "Produces money every round.",
	"refinery": "Produces fuel every round. Fuel launches missiles.",
	"lab": "Produces research points. Each lab works on one research item.",
	"basic_launcher": "Fires one basic missile a round, or a scouting missile once researched.",
	"anti_air": "Shoots at incoming missiles aimed near it. Uses no fuel.",
	"radar": "Anti-air inside its range hits far more often. Range grows with height.",
	"ballistic_launcher": "Fires one ballistic missile a round: less damage, wider blast.",
	"airport": "Sends one air transport a round. Its platoon destroys everything on three hexes unless a bunker is near.",
	"bunker": "Wipes out enemy platoons that land or march within range.",
	"docks": "Sends a boat with a platoon to the enemy coast. It lands in the round it sails. Built on the coast.",
	"coastal_cannon": "Fires on enemy boats coming ashore nearby. Built on the coast.",
	"enclave": "Sends foreign agents by helicopter to scout the enemy island and disarm their nukes, and keeps a domestic agent patrolling the ground around it who kills enemy spies. Place it where you most need guarding.",
	"stealth_silo": "Fires one stealth missile a round. Anti-air can't touch it, but it hits half as hard as a missile. It kills an enemy agent on the hex it hits.",
	"nuclear_silo": "Holds one nuke. Building a nuke takes a round; it hits its target twice as hard as a missile and every hex around it as hard as one. Anti-air rarely stops it, and it can take a stronghold.",
}
const RESEARCH_NAMES := {
	"radar": "Radar", "scouting_missile": "Scouting missile", "anti_air_capacity": "Anti-air capacity",
	"motion_sensor": "Motion sensor", "ballistic_launcher": "Ballistic launcher",
	"airport": "Airport", "bunker": "Bunker", "docks": "Docks", "coastal_cannon": "Coastal cannon",
	"nuclear_silo": "Nuclear silo", "bank_upgrade": "Bank upgrade",
	"refinery_upgrade": "Refinery upgrade", "logistics": "Logistics",
}
const RESEARCH_TEXT := {
	"radar": "Unlocks the radar building, which raises the accuracy of anti-air inside its range.",
	"scouting_missile": "Basic launchers can fire a cheap scouting missile that sees a wide area and does no damage.",
	"anti_air_capacity": "Each anti-air engages one more missile a round.",
	"motion_sensor": "A basic missile that lands on an empty hex moves to the nearest enemy building close by, on the same level.",
	"ballistic_launcher": "Unlocks the ballistic launcher.",
	"airport": "Unlocks the airport, which sends an air transport to drop a platoon on the enemy island.",
	"bunker": "Unlocks the bunker, which wipes out enemy platoons that land or march near it.",
	"docks": "Unlocks the docks, which send a boat carrying a platoon to the enemy coast.",
	"coastal_cannon": "Unlocks the coastal cannon, which fires on enemy boats landing nearby.",
	"nuclear_silo": "Unlocks the nuclear silo, which builds and fires nukes. Needs other research done first.",
	"bank_upgrade": "Every bank makes more money each round.",
	"refinery_upgrade": "Every refinery makes twice as much fuel each round.",
	"logistics": "Every anti-air gun reaches one hex farther, and every radar one hex farther.",
}


static func research_name(item: String) -> String:
	return RESEARCH_NAMES.get(item, item.replace("_", " ").capitalize())

## Building sprites: six-frame sheets rendered by tools/sprites (one frame
## per board rotation), described by assets/buildings/sprites.json. Drawn
## at the board's hex size; the art is rendered larger so it stays sharp
## when zoomed in. Loaded through textures.gd, which works in exports too.
const SPRITE_DIR := "res://assets/buildings/"
const BOARD_HEX_WIDTH := 30.0 * 1.7320508   ## Iso.HEX_SIZE * sqrt(3)
const SHEET_FOR := {
	"base": "base", "decoy": "decoy", "suspected_base": "base", "stronghold": "stronghold",
	"bank": "bank", "refinery": "refinery", "lab": "lab",
	"basic_launcher": "missile_launcher", "ballistic_launcher": "ballistic_launcher",
	"anti_air": "anti_air", "radar": "radar",
	"airport": "airport", "bunker": "bunker", "docks": "docks", "coastal_cannon": "coastal_cannon",
	"nuclear_silo": "nuclear_silo", "enclave": "enclave",
}
## Toolbar tile colours, one per building, so a tile reads without its name.
const TILE_COLORS := {
	"decoy": Color(0.66, 0.68, 0.70), "bank": Color(0.80, 0.64, 0.72), "refinery": Color(0.96, 0.84, 0.42),
	"lab": Color(0.56, 0.84, 0.82), "basic_launcher": Color(0.96, 0.58, 0.28), "anti_air": Color(0.58, 0.80, 0.42),
	"radar": Color(0.56, 0.78, 0.96), "ballistic_launcher": Color(0.88, 0.42, 0.36), "airport": Color(0.74, 0.72, 0.94),
	"bunker": Color(0.76, 0.66, 0.50), "docks": Color(0.42, 0.74, 0.86), "coastal_cannon": Color(0.95, 0.70, 0.30),
	"base": Color(0.86, 0.86, 0.82), "stronghold": Color(0.74, 0.70, 0.60),
	"nuclear_silo": Color(0.84, 0.74, 0.40), "enclave": Color(0.62, 0.64, 0.72),
	"stealth_silo": Color(0.58, 0.60, 0.70),
}


## Buildings drawn as placeholder blocks until their sprite sheets arrive
## (docs/troop_assets.md).
const ART_PENDING := ["stealth_silo"]
## Sheets with a separate frame set for a launcher that has fired.
const EMPTY_SHEETS := ["missile_launcher", "ballistic_launcher"]
## Sheets with a <name>_damaged version: hit and not yet repaired.
const DAMAGED_SHEETS := ["missile_launcher", "ballistic_launcher", "anti_air", "radar", "bank",
	"refinery", "lab", "base", "decoy", "airport", "bunker", "docks", "coastal_cannon", "stronghold",
	"nuclear_silo", "enclave"]

static var _sheets: Dictionary = {}
static var _meta = null


static func display_name(type: String) -> String:
	return NAMES.get(type, type.capitalize())


static func sprite_meta() -> Dictionary:
	if _meta == null:
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(SPRITE_DIR + "sprites.json"))
		_meta = parsed if parsed is Dictionary else {}
	return _meta


static func sheet(name: String) -> Texture2D:
	if name == "":
		return null   # no art yet: the caller draws a placeholder
	if not _sheets.has(name):
		_sheets[name] = Textures.load_texture(SPRITE_DIR + name + ".png")
	return _sheets[name]


## Sheet name for a building as drawn: scaffolding while under repair, the
## damaged version once hit (HP lost, out of action, or a hit on a base or
## decoy), otherwise the empty launcher once it has fired this round.
static func sheet_name(b: Dictionary) -> String:
	if b.get("repairing", false):
		return "repair"
	var n: String = SHEET_FOR.get(String(b["type"]), "")
	if n in DAMAGED_SHEETS and is_hit(b):
		return n + "_damaged"
	if n in EMPTY_SHEETS and b.get("empty", false):
		n += "_empty"
	if n == "nuclear_silo":
		# Lid open and empty, open with a nuke going in, or shut on an armed one.
		var nuke := "none" if b.get("empty", false) else String(b.get("nuke", "armed"))
		n = {"none": "nuclear_silo_open", "loading": "nuclear_silo_open_loaded"}.get(nuke, n)
	return n


## A silo's nuke: "none", "loading" (being built) or "armed".
static func nuke_state(b) -> String:
	if b.carrier_lost:
		return "none"
	return "loading" if b.loading > 0 else "armed"


static func is_hit(b: Dictionary) -> bool:
	if String(b.get("type", "")) == "stronghold":
		return bool(b.get("disabled", false))   # its hits only mark it as found
	return bool(b.get("damaged", false)) or bool(b.get("disabled", false)) or float(b.get("hits", 0.0)) > 0.0


## Draws one frame of a sheet with its anchor on `c` (the centre of the hex
## top face). `view` is the board rotation step. Returns false if the sheet
## is missing, so the caller can fall back to the placeholder.
static func draw_sheet(ci, name: String, c: Vector2, view: int, scale: float = 1.0,
		modulate: Color = Color.WHITE) -> bool:  # modulate tints the frame
	var tex := sheet(name)
	var meta := sprite_meta()
	if tex == null or meta.is_empty():
		return false
	var fw := float(meta["frame_width"])
	var fh := float(meta["frame_height"])
	var k := BOARD_HEX_WIDTH / float(meta["hex_width"]) * scale
	var anchor := Vector2(float(meta["anchor"][0]), float(meta["anchor"][1]))
	var frame := posmod(view, int(meta.get("frames_per_sheet", 6)))
	ci.draw_texture_rect_region(tex, Rect2(c - anchor * k, Vector2(fw, fh) * k),
		Rect2(frame * fw, 0, fw, fh), modulate)
	return true


## b: {"type", "hits", "damaged", "disabled", "repairing", "empty"}. The
## owner's decoy uses its own sheet (sandy tan) so the owner can tell it
## apart; the enemy sees a base. `view` is the board rotation step.
static func draw_piece(ci, font: Font, c: Vector2, b: Dictionary, view: int = 0, scale: float = 1.0) -> void:
	var type := String(b["type"])
	var w := 22.0
	var h := 26.0
	var base_y := c.y + 4.0
	# The sprite shows damage and repair itself; the marks below are for the
	# placeholder only.
	if draw_sheet(ci, sheet_name(b), c, view, scale):
		return
	var col: Color = COLORS.get(type, Color.WHITE)
	if b.get("disabled", false):
		col = col.darkened(0.55)
	ci.draw_colored_polygon(_ellipse(Vector2(c.x, base_y), 13, 5), Color(0, 0, 0, 0.35))
	var body := Rect2(c.x - w / 2.0, base_y - h, w, h)
	ci.draw_rect(body, col)
	ci.draw_rect(Rect2(body.position, Vector2(w, 5)), col.lightened(0.3))
	ci.draw_rect(body, col.darkened(0.5), false, 1.0)
	ci.draw_string(font, Vector2(body.position.x - 6, body.position.y + 19), SHORT.get(type, "?"),
		HORIZONTAL_ALIGNMENT_CENTER, w + 12, 11 if SHORT.get(type, "?").length() > 2 else 14, Color(0.08, 0.08, 0.1))
	if type == "decoy":
		ci.draw_circle(Vector2(body.end.x - 4, body.position.y + 9), 2.0, Color(0.2, 0.2, 0.2))
	var top := Vector2(c.x, base_y - h)
	if b.get("damaged", false) and not b.get("repairing", false):
		ci.draw_line(top + Vector2(-8, 6), top + Vector2(-2, 14), Color(0.15, 0.1, 0.05), 2.0)
		ci.draw_line(top + Vector2(-2, 14), top + Vector2(-6, 22), Color(0.15, 0.1, 0.05), 2.0)
	if b.get("disabled", false) and not b.get("repairing", false):
		ci.draw_line(top + Vector2(-9, 3), top + Vector2(9, 21), Color(1, 0.2, 0.2), 3.0)
		ci.draw_line(top + Vector2(9, 3), top + Vector2(-9, 21), Color(1, 0.2, 0.2), 3.0)
	if b.get("repairing", false):
		_draw_scaffold(ci, top, w, h)


## Common under-construction graphic for a hex under repair.
static func _draw_scaffold(ci, top: Vector2, w: float, h: float) -> void:
	var col := Color(0.95, 0.75, 0.2)
	var l := top.x - w / 2.0 - 3
	var r := top.x + w / 2.0 + 3
	for x in [l, r]:
		ci.draw_line(Vector2(x, top.y - 3), Vector2(x, top.y + h), col, 2.0)
	for y in [top.y + 4, top.y + 13, top.y + 22]:
		ci.draw_line(Vector2(l, y), Vector2(r, y), col, 2.0)
	ci.draw_line(Vector2(l, top.y + 4), Vector2(r, top.y + 13), col, 1.0)
	ci.draw_line(Vector2(r, top.y + 13), Vector2(l, top.y + 22), col, 1.0)


static func draw_rubble(ci, c: Vector2, _type: String, view: int = 0) -> void:
	if draw_sheet(ci, "rubble", c, view):
		return
	var col := Color(0.25, 0.22, 0.2)
	for p in [Vector2(-7, 0), Vector2(4, 2), Vector2(-1, -4), Vector2(8, -3)]:
		ci.draw_circle(c + p, 3.5, col)
	ci.draw_circle(c + Vector2(0, 1), 2.0, Color(0.9, 0.4, 0.1, 0.8))


static func _ellipse(c: Vector2, rx: float, ry: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in 16:
		var a := TAU * k / 16.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts
