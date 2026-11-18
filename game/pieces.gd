## Building pieces: rendered sprites (see draw_piece), with upright
## placeholder blocks as the fallback when a sheet is missing.
extends RefCounted

const NAMES := {
	"base": "Base", "decoy": "Decoy", "suspected_base": "Potential base",
	"bank": "Bank", "refinery": "Refinery", "lab": "Lab",
	"basic_launcher": "Missile launcher", "anti_air": "Anti-air", "radar": "Radar",
	"ballistic_launcher": "Ballistic launcher",
}
const SHORT := {
	"base": "BASE", "decoy": "BASE", "suspected_base": "?", "bank": "$", "refinery": "F",
	"lab": "R", "basic_launcher": "M", "anti_air": "AA", "radar": "RD", "ballistic_launcher": "BM",
}
const COLORS := {
	"base": Color(0.85, 0.85, 0.9), "decoy": Color(0.85, 0.85, 0.9),
	"suspected_base": Color(0.85, 0.85, 0.9),
	"bank": Color(0.95, 0.80, 0.25), "refinery": Color(0.85, 0.45, 0.20), "lab": Color(0.45, 0.75, 0.95),
	"basic_launcher": Color(0.85, 0.25, 0.25), "anti_air": Color(0.30, 0.75, 0.40),
	"radar": Color(0.70, 0.45, 0.90), "ballistic_launcher": Color(0.60, 0.15, 0.15),
}
const MISSILE_NAMES := {"basic": "Basic missile", "scouting": "Scouting missile", "ballistic": "Ballistic missile"}
## One-line descriptions for tooltips and the research panel. Numbers are
## not written here; they come from data where they are shown.
const BUILDING_TEXT := {
	"base": "Lose all three and you lose the island.",
	"decoy": "Looks exactly like a base to the enemy, and takes one more hit to destroy.",
	"bank": "Produces money every round.",
	"refinery": "Produces fuel every round. Fuel launches missiles.",
	"lab": "Produces research points. Each lab works on one research item.",
	"basic_launcher": "Fires one basic missile a round, or a scouting missile once researched.",
	"anti_air": "Shoots at incoming missiles aimed near it. Uses no fuel.",
	"radar": "Anti-air inside its range hits far more often. Range grows with height.",
	"ballistic_launcher": "Fires one ballistic missile a round: less damage, wider blast.",
}
const RESEARCH_NAMES := {
	"radar": "Radar", "scouting_missile": "Scouting missile", "anti_air_capacity": "Anti-air capacity",
	"motion_sensor": "Motion sensor", "ballistic_launcher": "Ballistic launcher",
}
const RESEARCH_TEXT := {
	"radar": "Unlocks the radar building, which raises the accuracy of anti-air inside its range.",
	"scouting_missile": "Basic launchers can fire a cheap scouting missile that sees a wide area and does no damage.",
	"anti_air_capacity": "Each anti-air engages one more missile a round.",
	"motion_sensor": "A basic missile that lands on an empty hex moves to the nearest enemy building close by, on the same level.",
	"ballistic_launcher": "Unlocks the ballistic launcher.",
}


static func research_name(item: String) -> String:
	return RESEARCH_NAMES.get(item, item.replace("_", " ").capitalize())

## Building sprites: six-frame sheets rendered by tools/sprites (one frame
## per board rotation), described by assets/buildings/sprites.json. Drawn
## at the board's hex size; the art is rendered larger so it stays sharp
## when zoomed in. Images are read straight from the files, so the game runs
## from a fresh checkout without an editor import step.
const SPRITE_DIR := "res://assets/buildings/"
const BOARD_HEX_WIDTH := 30.0 * 1.7320508   ## Iso.HEX_SIZE * sqrt(3)
const SHEET_FOR := {
	"base": "base", "decoy": "decoy", "suspected_base": "base",
	"bank": "bank", "refinery": "refinery", "lab": "lab",
	"basic_launcher": "missile_launcher", "ballistic_launcher": "ballistic_launcher",
	"anti_air": "anti_air", "radar": "radar",
}
## Sheets with a separate frame set for a launcher that has fired.
const EMPTY_SHEETS := ["missile_launcher", "ballistic_launcher"]

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
	if not _sheets.has(name):
		var tex: Texture2D = null
		var path: String = SPRITE_DIR + name + ".png"
		if FileAccess.file_exists(path):
			var img := Image.load_from_file(ProjectSettings.globalize_path(path))
			if img != null and not img.is_empty():
				img.generate_mipmaps()
				tex = ImageTexture.create_from_image(img)
		_sheets[name] = tex
	return _sheets[name]


## Sheet name for a building as drawn: scaffolding while under repair, the
## empty launcher once it has fired this round.
static func sheet_name(b: Dictionary) -> String:
	if b.get("repairing", false):
		return "repair"
	var n: String = SHEET_FOR.get(String(b["type"]), "")
	if n in EMPTY_SHEETS and b.get("empty", false):
		n += "_empty"
	return n


## Draws one frame of a sheet with its anchor on `c` (the centre of the hex
## top face). `view` is the board rotation step. Returns false if the sheet
## is missing, so the caller can fall back to the placeholder.
static func draw_sheet(ci: CanvasItem, name: String, c: Vector2, view: int, scale: float = 1.0,
		modulate: Color = Color.WHITE) -> bool:
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
## owner's decoy uses its own sheet (a grey flag) so the owner can tell it
## apart; the enemy sees a base. `view` is the board rotation step.
static func draw_piece(ci: CanvasItem, font: Font, c: Vector2, b: Dictionary, view: int = 0, scale: float = 1.0) -> void:
	var type := String(b["type"])
	var w := 22.0
	var h := 26.0
	var base_y := c.y + 4.0
	var tint := Color(0.5, 0.5, 0.55) if b.get("disabled", false) and not b.get("repairing", false) else Color.WHITE
	var drawn := draw_sheet(ci, sheet_name(b), c, view, scale, tint)
	if drawn and b.get("repairing", false):
		return
	if not drawn:
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
static func _draw_scaffold(ci: CanvasItem, top: Vector2, w: float, h: float) -> void:
	var col := Color(0.95, 0.75, 0.2)
	var l := top.x - w / 2.0 - 3
	var r := top.x + w / 2.0 + 3
	for x in [l, r]:
		ci.draw_line(Vector2(x, top.y - 3), Vector2(x, top.y + h), col, 2.0)
	for y in [top.y + 4, top.y + 13, top.y + 22]:
		ci.draw_line(Vector2(l, y), Vector2(r, y), col, 2.0)
	ci.draw_line(Vector2(l, top.y + 4), Vector2(r, top.y + 13), col, 1.0)
	ci.draw_line(Vector2(r, top.y + 13), Vector2(l, top.y + 22), col, 1.0)


static func draw_rubble(ci: CanvasItem, c: Vector2, _type: String, view: int = 0) -> void:
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
