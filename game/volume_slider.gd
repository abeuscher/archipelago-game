## The slider on the comms set: the main volume. Drag the orange handle (or
## click anywhere in its slot); top is loudest, bottom is silent. Emits
## `changed` while it moves and `released` when let go.
extends Control

const ResearchPanel = preload("res://game/research_panel.gd")

signal changed(value: float)
signal released(value: float)

const SLOT := Color(0.18, 0.18, 0.17)
const HANDLE := Color(0.93, 0.55, 0.22)
const HANDLE_EDGE := Color(0.4, 0.2, 0.08)
const TICK := Color(0.2, 0.19, 0.16)
const END_PAD := 10.0   ## space above and below the handle's travel

var value: float = 1.0:   ## 0 = silent, 1 = full
	set(v):
		value = clampf(v, 0.0, 1.0)
		queue_redraw()
var _dragging := false


func _init() -> void:
	custom_minimum_size = Vector2(52, 92)
	mouse_default_cursor_shape = Control.CURSOR_VSIZE
	tooltip_text = "Volume"


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if event.pressed:
			_set_from(event.position.y)
		else:
			released.emit(value)
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_set_from(event.position.y)
		accept_event()
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		value += 0.05 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -0.05
		changed.emit(value)
		released.emit(value)
		accept_event()


func _set_from(y: float) -> void:
	value = 1.0 - (y - END_PAD) / maxf(size.y - END_PAD * 2.0, 1.0)
	changed.emit(value)


func _draw() -> void:
	var x := size.x / 2.0
	draw_style_box(ResearchPanel._box(SLOT, ResearchPanel.BEZEL_EDGE, 1, 4, [0, 0, 0, 0]),
		Rect2(x - 5, 4, 10, size.y - 8))
	for k in 6:
		var y := END_PAD + k * (size.y - END_PAD * 2.0) / 5.0
		draw_line(Vector2(x - 16, y), Vector2(x - 9, y), TICK, 1.0)
	var hy := END_PAD + (1.0 - value) * (size.y - END_PAD * 2.0)
	draw_style_box(ResearchPanel._box(HANDLE, HANDLE_EDGE, 2, 3, [0, 0, 0, 0]), Rect2(x - 11, hy - 7, 22, 14))
	draw_line(Vector2(x - 7, hy), Vector2(x + 7, hy), HANDLE_EDGE, 1.5)
