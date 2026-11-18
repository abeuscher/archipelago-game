## Research panel (section 14). One lab per page, with a pager when there
## are several labs. Left: the selected lab. Right: its research, or, for a
## lab with no project of its own, what it is helping and the research it
## could start. Choosing an item starts that lab on it. Belongs to the build
## and repair phase; outside it the panel is read-only.
extends PanelContainer

const Pieces = preload("res://game/pieces.gd")
const Earnings = preload("res://game/earnings.gd")

signal start_requested(lab_id: int, item: String)
signal closed

var lab_index: int = 0
var _title: Label
var _prev: Button
var _next: Button
var _left: VBoxContainer
var _right: VBoxContainer


func _ready() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var t := Label.new()
	t.text = "Research"
	t.add_theme_font_size_override("font_size", 22)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	_prev = Button.new()
	_prev.text = "◀"
	_prev.tooltip_text = "Previous lab"
	_prev.pressed.connect(func(): _page(-1))
	head.add_child(_prev)
	_title = Label.new()
	_title.custom_minimum_size = Vector2(120, 0)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(_title)
	_next = Button.new()
	_next.text = "▶"
	_next.tooltip_text = "Next lab"
	_next.pressed.connect(func(): _page(1))
	head.add_child(_next)
	var x := Button.new()
	x.text = "Close"
	x.pressed.connect(func(): visible = false; closed.emit())
	head.add_child(x)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	box.add_child(body)
	_left = VBoxContainer.new()
	_left.custom_minimum_size = Vector2(190, 0)
	body.add_child(_left)
	body.add_child(VSeparator.new())
	_right = VBoxContainer.new()
	_right.custom_minimum_size = Vector2(380, 0)
	_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(_right)


var _st
var _data
var _editable: bool = false


func _page(d: int) -> void:
	if _st == null:
		return
	var n: int = _st.of_role(_data, "lab").size()
	if n > 0:
		lab_index = (lab_index + d + n) % n
	show_state(_st, _data, _editable)


## Open on the lab with this building id.
func open_lab(st, data, lab_id: int, editable: bool) -> void:
	var labs: Array = st.of_role(data, "lab")
	for i in labs.size():
		if labs[i].id == lab_id:
			lab_index = i
	visible = true
	show_state(st, data, editable)


func show_state(st, data, editable: bool) -> void:
	_st = st
	_data = data
	_editable = editable
	for c in _left.get_children() + _right.get_children():
		c.queue_free()
	var labs: Array = st.of_role(data, "lab")
	_prev.visible = labs.size() > 1
	_next.visible = labs.size() > 1
	if labs.is_empty():
		_title.text = ""
		_add(_left, "No labs.", 16)
		_add(_right, "Build a lab to research. Projects without a lab keep their progress.", 14)
		return
	lab_index = clampi(lab_index, 0, labs.size() - 1)
	_title.text = "Lab %d of %d" % [lab_index + 1, labs.size()]
	var lab = labs[lab_index]

	# Left: the lab itself.
	_add(_left, "Lab %d" % (lab_index + 1), 20)
	_add(_left, "HP %d / %d" % [lab.hp, data.max_hp(lab.type)], 14)
	var pts := int(data.building(lab.type)["produces"].get("research", 0))
	if st.is_half_strength(lab, data):
		pts = st.half_income(pts, data)
		_add(_left, "Under repair" if lab.repairing else "Damaged: half strength", 14, Color(1.0, 0.75, 0.4))
	_add(_left, "%d research point%s a round" % [pts, "" if pts == 1 else "s"], 14)

	# Right: its research.
	var own = st.project_for_lab(lab.id)
	if own != null:
		_project_block(st, data, String(own["item"]), "Researching")
		return
	var oldest = st.oldest_project()
	if oldest != null:
		_add(_right, "No project of its own. Working on another lab's project:", 14, Color(0.75, 0.8, 0.85))
		_project_block(st, data, String(oldest["item"]), "Helping")
	else:
		_add(_right, "No project of its own, and nothing to help.", 14, Color(0.75, 0.8, 0.85))
	var avail: Array = st.research_available(data)
	if avail.is_empty():
		_add(_right, "Everything available has been researched.", 14)
		return
	_add(_right, "Start research:" if editable else "Research available (choose in the build and repair phase):", 16)
	for item in avail:
		var def: Dictionary = data.research_item(item)
		var p = st.project_for_item(item)
		var resumed: bool = p != null
		var label := "%s    %s, %d points" % [Pieces.research_name(item),
			"resume free" if resumed else "%d money" % int(def["cost"]), int(def["points"])]
		if resumed:
			label += "  (%d done)" % int(p["progress"])
		var b := Button.new()
		b.text = label
		var err: String = st.can_start_research(lab.id, item, data)
		b.disabled = not editable or err != ""
		b.tooltip_text = Pieces.RESEARCH_TEXT.get(item, "") + ("" if err == "" else "\n" + err)
		var lab_id: int = lab.id
		var it: String = item
		b.pressed.connect(func(): start_requested.emit(lab_id, it))
		_right.add_child(b)


func _project_block(st, data, item: String, verb: String) -> void:
	var p = st.project_for_item(item)
	var need := int(data.research_item(item)["points"])
	_add(_right, "%s: %s" % [verb, Pieces.research_name(item)], 18)
	_add(_right, Pieces.RESEARCH_TEXT.get(item, ""), 13, Color(0.75, 0.8, 0.85))
	var bar := ProgressBar.new()
	bar.max_value = need
	bar.value = int(p["progress"])
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 18)
	_right.add_child(bar)
	var left := Earnings.rounds_left(st, data, item)
	var eta := "stalled: no lab is working on it" if left < 0 else "about %d round%s to go" % [left, "" if left == 1 else "s"]
	_add(_right, "%d / %d points, %s" % [int(p["progress"]), need, eta], 14)


func _add(parent: Control, text: String, size_px: int, color: Color = Color(0.92, 0.94, 0.96)) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
