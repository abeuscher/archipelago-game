## A left-toolbar button with the building's sprite drawn at its
## left, then its name and a right-aligned cost or detail. In compact mode
## (two buttons across) it is a coloured tile with no words: the sprite in
## the middle, the price on a badge in the corner (red when it can't be
## afforded), and a small tag when it is locked or at its limit. The name is
## in the tooltip.
extends Button

const Pieces = preload("res://game/pieces.gd")

var piece_type: String = ""
var title: String = ""
var detail: String = ""
var note: String = ""
var dimmed: bool = false   ## looks disabled but still clickable
var compact: bool = false
var broke: bool = false      ## the price is more than the money on hand
var tag: String = ""         ## "LOCKED", "LIMIT" or ""
var marked: bool = false     ## a weapon already aimed: a small crosshair on the tile
var out: bool = false        ## a weapon that can't fire this round: greyed, no words


func _init() -> void:
	custom_minimum_size = Vector2(0, 44)
	focus_mode = Control.FOCUS_NONE
	clip_contents = true


func _draw() -> void:
	if compact:
		_draw_tile()
		return
	var font := get_theme_default_font()
	var grey := disabled or dimmed
	var col := Color(0.92, 0.94, 0.96) if not grey else Color(0.5, 0.52, 0.55)
	var x := 10.0
	if piece_type != "":
		if not Pieces.draw_sheet(self, Pieces.sheet_name({"type": piece_type}), Vector2(25, size.y / 2.0 + 9), 0, 0.82):
			Pieces.draw_piece(self, font, Vector2(24, size.y / 2.0 + 10), {"type": piece_type})
		if grey:
			draw_rect(Rect2(6, 4, 36, size.y - 8), Color(0.1, 0.11, 0.13, 0.6))
		x = 46.0
	var y := size.y / 2.0 + (1.0 if note == "" else -5.0)
	draw_string(_bold(), Vector2(x, y + 5), title, HORIZONTAL_ALIGNMENT_LEFT, size.x - x - 60, 15, col)
	if note != "":
		draw_string(font, Vector2(x, y + 20), note, HORIZONTAL_ALIGNMENT_LEFT, size.x - x - 10, 11, Color(0.7, 0.72, 0.75))
	if detail != "":
		draw_string(_bold(), Vector2(size.x - 64, size.y / 2.0 + 6), detail, HORIZONTAL_ALIGNMENT_RIGHT, 56, 15, col)


const INK := Color(0.12, 0.11, 0.10)
const LOCKED_FILL := Color(0.42, 0.43, 0.42)


func _draw_tile() -> void:
	var font := get_theme_default_font()
	var locked := tag != "" or out
	var fill: Color = Pieces.TILE_COLORS.get(piece_type, Color(0.7, 0.72, 0.75))
	if locked:
		fill = LOCKED_FILL
	elif is_hovered():
		fill = fill.lightened(0.12)
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = Color(1.0, 0.86, 0.3) if button_pressed else INK
	box.set_border_width_all(4 if button_pressed else 2)
	box.set_corner_radius_all(8)
	box.shadow_color = Color(0, 0, 0, 0.35)
	box.shadow_size = 2
	box.shadow_offset = Vector2(0, 2)
	draw_style_box(box, Rect2(Vector2(2, 2), size - Vector2(4, 6)))
	# The building in the middle.
	if piece_type != "":
		var at := Vector2(size.x * 0.42, size.y * 0.66)
		var tint := Color(0.55, 0.55, 0.55, 0.9) if locked else Color.WHITE
		if not Pieces.draw_sheet(self, Pieces.sheet_name({"type": piece_type}), at, 0, 0.95, tint):
			Pieces.draw_piece(self, font, at, {"type": piece_type})
	# Price badge, top right.
	if detail != "":
		var w := _bold().get_string_size(detail, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 10.0
		var badge := Rect2(Vector2(size.x - w - 6, 6), Vector2(w, 20))
		var bb := StyleBoxFlat.new()
		bb.bg_color = Color(0.13, 0.13, 0.15, 0.92)
		bb.set_corner_radius_all(5)
		draw_style_box(bb, badge)
		var price_col := Color(0.6, 0.6, 0.6) if locked else (Color(1.0, 0.45, 0.40) if broke else Color(1.0, 0.86, 0.38))
		draw_string(_bold(), Vector2(badge.position.x + 5, badge.position.y + 15), detail, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, price_col)
	# Aimed: a green crosshair, bottom left.
	if marked:
		var c := Vector2(16, size.y - 18)
		draw_circle(c, 9.0, Color(0.13, 0.13, 0.15, 0.85))
		draw_arc(c, 6.0, 0, TAU, 20, Color(0.45, 0.95, 0.5), 2.0, true)
		for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			draw_line(c + d * 3.0, c + d * 8.5, Color(0.45, 0.95, 0.5), 2.0)
	# Locked or at its limit: a small tag, bottom left.
	if tag != "":
		var t := Rect2(Vector2(6, size.y - 24), Vector2(_bold().get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 10, 16))
		var tb := StyleBoxFlat.new()
		tb.bg_color = Color(0.13, 0.13, 0.15, 0.85)
		tb.set_corner_radius_all(4)
		draw_style_box(tb, t)
		draw_string(_bold(), Vector2(t.position.x + 5, t.position.y + 12), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.85, 0.85, 0.8))


static var _bold_font: Font


static func _bold() -> Font:
	if _bold_font == null:
		var f := FontVariation.new()
		f.base_font = ThemeDB.fallback_font
		f.variation_embolden = 0.6
		_bold_font = f
	return _bold_font
