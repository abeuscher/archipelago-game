## A character who talks to the player from the portrait space in the left
## toolbar, in a speech bubble beside it. Two kinds of message:
##   tip: stays until dismissed; "Don't show this again" at bottom left and
##     OK at bottom right. A tip with an anchor dims the screen around what
##     it points at. A tip marked pause also blocks the screen behind it.
##   announcement: round starts, incoming attacks. OK closes it, or it goes
##     after a few seconds. Announcements come before tips; a tip waiting
##     behind one shows when it is gone.
## The character pops out from the centre of the portrait space, then the
## bubble pops in. Characters (name, portrait) are in data/characters.json.
extends Control

const PATH := "res://data/characters.json"
const ANNOUNCE_SECONDS := 3.5
const POP_SECONDS := 0.12
const BUBBLE_POP_SECONDS := 0.08
const PORTRAIT_MAX := 150.0
const BUBBLE_W := 380.0
const CREAM := Color(0.98, 0.95, 0.85)
const INK := Color(0.12, 0.10, 0.08)
const DIM := Color(0, 0, 0, 0.55)
const SPOT_EDGE := Color(1.0, 0.85, 0.35)

signal tip_dismissed(id: String, forever: bool)

var slot: Control                 ## the portrait space in the toolbar
var anchor_rect: Callable         ## anchor name -> Rect2 on screen (empty if not shown)
var characters: Dictionary = {}
var default_character: String = ""

var _tip = null                   ## current tip, or null
var _queue: Array = []            ## announcements waiting: {"text", "character", "seconds"}
var _msg = null                   ## message on screen, or null
var _left: float = 0.0            ## seconds before an announcement closes itself
var _portraits: Dictionary = {}   ## character id -> Texture2D
var _speaker: String = ""

var _spot: Control
var _face: Control
var _bubble: PanelContainer
var _tail: Control
var _name: Label
var _text: Label
var _forever: CheckBox
var _ok: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_load_characters()

	_spot = Control.new()
	_spot.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_spot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spot.visible = false
	_spot.draw.connect(_draw_spot)
	add_child(_spot)

	_face = Control.new()
	_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_face.visible = false
	_face.draw.connect(_draw_face)
	add_child(_face)

	_bubble = PanelContainer.new()
	_bubble.visible = false
	var st := StyleBoxFlat.new()
	st.bg_color = CREAM
	st.border_color = INK
	st.set_border_width_all(3)
	st.set_corner_radius_all(14)
	st.content_margin_left = 16
	st.content_margin_right = 16
	st.content_margin_top = 10
	st.content_margin_bottom = 10
	_bubble.add_theme_stylebox_override("panel", st)
	add_child(_bubble)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_bubble.add_child(v)
	_name = Label.new()
	_name.add_theme_font_size_override("font_size", 13)
	_name.add_theme_color_override("font_color", Color(0.55, 0.30, 0.15))
	v.add_child(_name)
	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD
	_text.custom_minimum_size = Vector2(BUBBLE_W - 32, 0)
	_text.add_theme_font_size_override("font_size", 16)
	_text.add_theme_color_override("font_color", INK)
	v.add_child(_text)
	var row := HBoxContainer.new()
	v.add_child(row)
	_forever = CheckBox.new()
	_forever.text = "Don't show this again"
	_forever.focus_mode = Control.FOCUS_NONE
	_forever.button_pressed = true
	_forever.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_forever.add_theme_font_size_override("font_size", 12)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		_forever.add_theme_color_override(c, Color(0.30, 0.26, 0.22))
	_forever.add_theme_icon_override("checked", _box_icon(true))
	_forever.add_theme_icon_override("unchecked", _box_icon(false))
	row.add_child(_forever)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_ok = Button.new()
	_ok.text = "OK"
	_ok.focus_mode = Control.FOCUS_NONE
	_ok.custom_minimum_size = Vector2(64, 0)
	_ok.pressed.connect(_on_ok)
	row.add_child(_ok)

	# The tail goes over the bubble so it can cover the bubble's border where
	# they join, making one shape.
	_tail = Control.new()
	_tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tail.visible = false
	_tail.draw.connect(_draw_tail)
	add_child(_tail)


func _load_characters() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if parsed is Dictionary:
		characters = parsed.get("characters", {})
		default_character = String(parsed.get("default", ""))


# --- Messages --------------------------------------------------------------

## The tip to show when nothing is being announced (null for none).
func set_tip(tip) -> void:
	if tip == null and _tip == null:
		return
	if tip != null and _tip != null and String(tip["id"]) == String(_tip["id"]):
		_tip = tip
		return
	_tip = tip
	_refresh()


func announce(text: String, character: String = "", seconds: float = ANNOUNCE_SECONDS) -> void:
	_queue.append({"text": text, "character": character, "seconds": seconds})
	_refresh()


## Id of the tip on screen, or "".
func tip_showing() -> String:
	return String(_msg["tip"]["id"]) if _msg != null and _msg.has("tip") else ""


func announcing() -> bool:
	return _msg != null and not _msg.has("tip")


func _refresh() -> void:
	var want = null
	if not _queue.is_empty():
		want = _queue[0]
	elif _tip != null:
		want = {"tip": _tip, "text": String(_tip["text"]), "character": String(_tip.get("character", ""))}
	if _same(want, _msg):
		return
	_msg = want
	if _msg == null:
		_hide_all()
		return
	_show_msg()


static func _same(a, b) -> bool:
	if a == null or b == null:
		return a == b
	if a.has("tip") != b.has("tip"):
		return false
	if a.has("tip"):
		return String(a["tip"]["id"]) == String(b["tip"]["id"])
	return a == b


func _on_ok() -> void:
	if _msg == null:
		return
	if _msg.has("tip"):
		var id := String(_msg["tip"]["id"])
		var forever := _forever.button_pressed
		_tip = null
		_msg = null
		tip_dismissed.emit(id, forever)
		_refresh()
	else:
		_queue.pop_front()
		_msg = null
		_refresh()


func _process(delta: float) -> void:
	if _msg != null and not _msg.has("tip"):
		_left -= delta
		if _left <= 0.0:
			_on_ok()
	if _spot.visible:
		_spot.queue_redraw()   # anchors move when the toolbar is rebuilt


# --- Showing ---------------------------------------------------------------

func _show_msg() -> void:
	var who := String(_msg.get("character", ""))
	if who == "" or not characters.has(who):
		who = default_character
	var is_tip: bool = _msg.has("tip")
	_name.text = String(characters.get(who, {}).get("name", ""))
	_name.visible = _name.text != ""
	_text.text = String(_msg["text"])
	_forever.visible = is_tip
	_forever.button_pressed = true
	_left = float(_msg.get("seconds", ANNOUNCE_SECONDS))
	var tip: Dictionary = _msg.get("tip", {})
	var pause := bool(tip.get("pause", false))
	_spot.visible = is_tip and (pause or anchor_rect.is_valid() and anchor_rect.call(String(tip.get("anchor", ""))).has_area())
	_spot.mouse_filter = Control.MOUSE_FILTER_STOP if pause else Control.MOUSE_FILTER_IGNORE
	_spot.queue_redraw()
	_layout()
	var pop_face := not _face.visible or who != _speaker
	_speaker = who
	_face.queue_redraw()
	if pop_face:
		_face.visible = true
		_face.scale = Vector2(0.05, 0.05)
		_bubble.visible = false
		_tail.visible = false
		var t := _face.create_tween()
		t.tween_property(_face, "scale", Vector2.ONE, POP_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_callback(_pop_bubble)
	else:
		_pop_bubble()


func _pop_bubble() -> void:
	_layout()
	_bubble.visible = true
	_tail.visible = true
	_bubble.scale = Vector2(0.7, 0.7)
	_bubble.modulate.a = 0.0
	var t := _bubble.create_tween().set_parallel(true)
	t.tween_property(_bubble, "scale", Vector2.ONE, BUBBLE_POP_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_bubble, "modulate:a", 1.0, BUBBLE_POP_SECONDS)


func _hide_all() -> void:
	_bubble.visible = false
	_tail.visible = false
	_spot.visible = false
	if _face.visible:
		var t := _face.create_tween()
		t.tween_property(_face, "scale", Vector2(0.05, 0.05), POP_SECONDS * 0.7).set_ease(Tween.EASE_IN)
		t.tween_callback(func():
			if _msg == null:
				_face.visible = false)


## Portrait centred in the slot, bubble above and to its right
## with the tail pointing down at the face.
func _layout() -> void:
	if slot == null:
		return
	var r := slot.get_global_rect()
	var d := minf(PORTRAIT_MAX, minf(r.size.y, r.size.x) - 8.0)
	_face.size = Vector2(d, d)
	_face.position = Vector2(r.position.x + (r.size.x - d) / 2.0, r.position.y + (r.size.y - d) / 2.0)
	_face.pivot_offset = _face.size / 2.0
	_bubble.reset_size()
	var bs := _bubble.get_combined_minimum_size()
	var bx := _face.position.x + d * 0.72
	var bottom := _face.position.y + d * 0.30
	var by := maxf(8.0, bottom - bs.y)
	_bubble.position = Vector2(bx, by)
	_bubble.size = bs
	_bubble.pivot_offset = Vector2(24, bs.y)
	_tail.position = Vector2.ZERO
	_tail.size = get_viewport_rect().size
	_tail.queue_redraw()


# --- Drawing ---------------------------------------------------------------

func _draw_face() -> void:
	var d := _face.size.x
	var c := _face.size / 2.0
	var r := d / 2.0
	var tex := _portrait(_speaker)
	if tex != null:
		var circle: Array = characters[_speaker].get("circle", [tex.get_width() / 2.0, tex.get_height() / 2.0, tex.get_height() / 2.0])
		var cx := float(circle[0]) / tex.get_width()
		var cy := float(circle[1]) / tex.get_height()
		var rx := float(circle[2]) / tex.get_width()
		var ry := float(circle[2]) / tex.get_height()
		var pts := PackedVector2Array()
		var uvs := PackedVector2Array()
		for k in 48:
			var a := TAU * k / 48.0
			pts.append(c + Vector2(cos(a), sin(a)) * r)
			uvs.append(Vector2(cx + cos(a) * rx, cy + sin(a) * ry))
		draw_polygon_on(_face, pts, uvs, tex)
	else:
		_face.draw_circle(c, r, Color(0.25, 0.33, 0.42))
	_face.draw_arc(c, r - 1.5, 0.0, TAU, 64, INK, 3.0, true)
	_face.draw_arc(c, r + 1.5, 0.0, TAU, 64, Color(0.55, 0.60, 0.66, 0.8), 1.5, true)


static func draw_polygon_on(ci: CanvasItem, pts: PackedVector2Array, uvs: PackedVector2Array, tex: Texture2D) -> void:
	ci.draw_polygon(pts, PackedColorArray([Color.WHITE]), uvs, tex)


func _portrait(who: String) -> Texture2D:
	if not _portraits.has(who):
		var tex: Texture2D = null
		var path := String(characters.get(who, {}).get("portrait", ""))
		if path != "" and FileAccess.file_exists(path):
			var img := Image.load_from_file(ProjectSettings.globalize_path(path))
			if img != null and not img.is_empty():
				img.generate_mipmaps()
				tex = ImageTexture.create_from_image(img)
		_portraits[who] = tex
	return _portraits[who]


## The bubble's tail: from its lower-left edge down to the face.
func _draw_tail() -> void:
	if not _bubble.visible:
		return
	var b := Rect2(_bubble.position, _bubble.size)
	# The base sits just inside the bubble, above its 3 px border, so the
	# cream fill hides the border there; only the two sides are inked, from
	# the border's outer edge down to the tip.
	var inside := b.end.y - 5.0
	var edge := b.end.y
	var x0 := b.position.x + 20.0
	var x1 := b.position.x + 48.0
	var tip := _face.position + Vector2(_face.size.x * 0.80, _face.size.y * 0.42)
	_tail.draw_colored_polygon(PackedVector2Array([Vector2(x0, inside), Vector2(x1, inside), tip]), CREAM)
	var a := Vector2(x0 + (tip.x - x0) * (edge - inside) / maxf(tip.y - inside, 1.0), edge)
	var c := Vector2(x1 + (tip.x - x1) * (edge - inside) / maxf(tip.y - inside, 1.0), edge)
	_tail.draw_line(a, tip, INK, 3.0, true)
	_tail.draw_line(tip, c, INK, 3.0, true)


## Dims everything but the anchor of the tip on screen, which gets a bright
## edge. Without an anchor (a pausing tip) the whole screen dims.
func _draw_spot() -> void:
	var view := get_viewport_rect().size
	var hole := Rect2()
	if _msg != null and _msg.has("tip") and anchor_rect.is_valid():
		hole = anchor_rect.call(String(_msg["tip"].get("anchor", "")))
	if not hole.has_area():
		_spot.draw_rect(Rect2(Vector2.ZERO, view), DIM)
		return
	hole = hole.grow(6.0)
	_spot.draw_rect(Rect2(0, 0, view.x, hole.position.y), DIM)
	_spot.draw_rect(Rect2(0, hole.end.y, view.x, view.y - hole.end.y), DIM)
	_spot.draw_rect(Rect2(0, hole.position.y, hole.position.x, hole.size.y), DIM)
	_spot.draw_rect(Rect2(hole.end.x, hole.position.y, view.x - hole.end.x, hole.size.y), DIM)
	_spot.draw_rect(hole, SPOT_EDGE, false, 2.0)


## A plain check box drawn dark on the cream bubble.
static func _box_icon(checked: bool) -> Texture2D:
	var n := 16
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for i in n:
		for j in [0, 1, n - 2, n - 1]:
			img.set_pixel(i, j, INK)
			img.set_pixel(j, i, INK)
	for i in range(2, n - 2):
		for j in range(2, n - 2):
			img.set_pixel(i, j, Color(1, 1, 1, 0.9))
	if checked:
		var pts := [[4, 8], [5, 9], [6, 10], [7, 11], [8, 10], [9, 9], [10, 8], [11, 7], [12, 6], [12, 5]]
		for p in pts:
			for o in [[0, 0], [0, -1], [1, 0]]:
				img.set_pixel(p[0] + o[0], p[1] + o[1], INK)
	return ImageTexture.create_from_image(img)
