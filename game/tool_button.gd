## A left-toolbar button with the building's sprite drawn at its
## left, then its name and a right-aligned cost or detail.
extends Button

const Pieces = preload("res://game/pieces.gd")

var piece_type: String = ""
var title: String = ""
var detail: String = ""
var note: String = ""
var dimmed: bool = false   ## looks disabled but still clickable


func _init() -> void:
	custom_minimum_size = Vector2(0, 44)
	focus_mode = Control.FOCUS_NONE
	clip_contents = true


func _draw() -> void:
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
	draw_string(font, Vector2(x, y + 5), title, HORIZONTAL_ALIGNMENT_LEFT, size.x - x - 60, 15, col)
	if note != "":
		draw_string(font, Vector2(x, y + 20), note, HORIZONTAL_ALIGNMENT_LEFT, size.x - x - 10, 11, Color(0.7, 0.72, 0.75))
	if detail != "":
		draw_string(font, Vector2(size.x - 64, size.y / 2.0 + 6), detail, HORIZONTAL_ALIGNMENT_RIGHT, 56, 15, col)
