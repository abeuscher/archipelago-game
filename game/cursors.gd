## The pointing-hand cursor: a gloved hand (tools/sprites/render_cursor.py)
## over everything that can be clicked: every button, check box and slider,
## and the minimap. It squeezes down a little while the mouse button is held.
## Text boxes keep the text cursor; a control that has chosen another shape
## (the volume slider's up-down arrows) keeps it.
##
## install() once per scene: it sets the cursor's pictures (at double size
## when the interface is drawn at 1.5 times or more, as on a Retina Mac) and
## gives the hand to every clickable control in the tree, now and as they
## are added.
extends Node

const Textures = preload("res://game/textures.gd")

const HAND := "res://assets/ui/cursor_hand%s.png"
const HOTSPOT := Vector2(12, 1)   ## the fingertip, at the 32 px size
const DESIGN_SIZE := Vector2(1600, 900)
const DOUBLE_AT := 1.5            ## interface scale from which the 64 px pictures are used

var _big := false
var _pressed := false


## Adds the cursor keeper to the scene `root`.
static func install(root: Node) -> void:
	var c = load("res://game/cursors.gd").new()
	c.name = "Cursors"
	root.add_child(c)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # the pause menu has buttons too
	var tree := get_tree()
	tree.node_added.connect(_on_node_added)
	_walk(tree.root)
	tree.root.size_changed.connect(_set_pictures)
	_set_pictures()


## True for controls that take a click: they get the hand.
static func wants_hand(n: Node) -> bool:
	if not (n is Control):
		return false
	if (n as Control).mouse_default_cursor_shape != Control.CURSOR_ARROW:
		return false   # a shape of its own, kept
	return n is BaseButton or n is Slider or n.get_script() == load("res://game/minimap.gd")


func _on_node_added(n: Node) -> void:
	if wants_hand(n):
		(n as Control).mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _walk(n: Node) -> void:
	_on_node_added(n)
	for c in n.get_children():
		_walk(c)


func _set_pictures() -> void:
	var win := Vector2(get_tree().root.size)
	_big = minf(win.x / DESIGN_SIZE.x, win.y / DESIGN_SIZE.y) >= DOUBLE_AT
	_apply()


func _apply() -> void:
	var tag := ("_pressed" if _pressed else "") + ("_2x" if _big else "")
	var tex: Texture2D = Textures.load_texture(HAND % tag)
	if tex == null:
		return
	Input.set_custom_mouse_cursor(tex, Input.CURSOR_POINTING_HAND, HOTSPOT * (2.0 if _big else 1.0))


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed != _pressed:
		_pressed = event.pressed
		_apply()


## Lets go of the pictures when the scene closes (the next scene sets them
## again), so none are held at exit.
func _exit_tree() -> void:
	Input.set_custom_mouse_cursor(null, Input.CURSOR_POINTING_HAND)
