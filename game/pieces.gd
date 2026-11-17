## Placeholder pieces. Each building is one upright piece on one hex that
## always faces the camera. If a sprite exists at
## res://assets/sprites/<type>.png it is used instead of the placeholder.
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

static var _sprites: Dictionary = {}


static func display_name(type: String) -> String:
	return NAMES.get(type, type.capitalize())


static func sprite(type: String) -> Texture2D:
	if not _sprites.has(type):
		var path := "res://assets/sprites/%s.png" % type
		_sprites[type] = load(path) if ResourceLoader.exists(path) else null
	return _sprites[type]


## b: {"type", "hits", "damaged", "disabled", "repairing"}. The decoy is
## drawn exactly like a base on the owner's side too, except for a small dot,
## so the owner can tell them apart.
static func draw_piece(ci: CanvasItem, font: Font, c: Vector2, b: Dictionary) -> void:
	var type := String(b["type"])
	var tex := sprite(type)
	var w := 22.0
	var h := 26.0
	var base_y := c.y + 4.0
	if tex != null:
		var sz := tex.get_size()
		ci.draw_texture(tex, Vector2(c.x - sz.x / 2.0, base_y - sz.y))
	else:
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


static func draw_rubble(ci: CanvasItem, c: Vector2, _type: String) -> void:
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
