## Collects flat-coloured shapes for one canvas item into a single triangle
## list, sent as one draw command, instead of one command (and one GPU
## buffer) per polygon or polyline. Thousands of small polygons a redraw
## stalled the frame on macOS, where Vulkan runs through MoltenVK.
##
## It offers the CanvasItem draw calls the boards use, under the same names,
## so drawing code can take either. Polygons, lines, polylines and arcs are
## turned into triangles here with the same geometry Godot 4.7 builds for
## them (renderer_canvas_cull.cpp), so they look the same. Anything else
## (textures, text, transforms, circles, hairlines) first sends what has been
## collected, then goes straight to the canvas item, so the drawing order
## never changes.
extends RefCounted

const FEATHER := 1.25        ## Godot's FEATHER_SIZE for antialiased edges
const EPS := 0.00001         ## Godot's CMP_EPSILON

var ci: CanvasItem
var _pts := PackedVector2Array()
var _cols := PackedColorArray()


func _init(item: CanvasItem) -> void:
	ci = item


## Sends what has been collected as one draw command.
func flush() -> void:
	if _pts.is_empty():
		return
	RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), PackedInt32Array(), _pts, _cols)
	_pts = PackedVector2Array()
	_cols = PackedColorArray()


# --- Collected shapes ------------------------------------------------------

func draw_colored_polygon(points: PackedVector2Array, color: Color) -> void:
	var idx := Geometry2D.triangulate_polygon(points)
	for k in idx:
		_pts.append(points[k])
		_cols.append(color)


func draw_line(from: Vector2, to: Vector2, color: Color, width: float = -1.0, antialiased: bool = false) -> void:
	if width < 0.0:
		flush()
		ci.draw_line(from, to, color, width, antialiased)
		return
	if antialiased:
		width = _compensated(width)
	var diff := from - to
	var dir := diff.orthogonal().normalized()
	var t := dir * width * 0.5
	var bl := from + t
	var br := from - t
	var el := to + t
	var er := to - t
	_quad(bl, br, er, el, color, color, color, color)
	if not antialiased:
		return
	var border_size := FEATHER
	if width < 1.0:
		border_size *= width
	var border := dir * border_size
	var border2 := diff.normalized() * border_size
	var clear := Color(color, 0.0)
	_quad(bl, bl + border, el + border, el, color, clear, clear, color)
	_quad(br, br - border, er - border, er, color, clear, clear, color)
	_quad(bl, bl + border2, br + border2, br, color, clear, clear, color)
	_quad(el, el - border2, er - border2, er, color, clear, clear, color)
	_quad(bl, bl + border2, bl + border + border2, bl + border, color, clear, clear, clear)
	_quad(br, br + border2, br - border + border2, br - border, color, clear, clear, clear)
	_quad(el, el - border2, el + border - border2, el + border, color, clear, clear, clear)
	_quad(er, er - border2, er - border - border2, er - border, color, clear, clear, clear)


func draw_polyline(points: PackedVector2Array, color: Color, width: float = -1.0, antialiased: bool = false) -> void:
	if width < 0.0 or points.size() < 2:
		flush()
		ci.draw_polyline(points, color, width, antialiased)
		return
	if antialiased:
		width = _compensated(width)
	var n := points.size()
	var loop := points[0].is_equal_approx(points[n - 1])
	var first_dir := Vector2.ZERO
	for i in range(1, n):
		first_dir = (points[i] - points[i - 1]).normalized()
		if not first_dir.is_zero_approx():
			break
	var last_dir := Vector2.ZERO
	for i in range(n - 1, 0, -1):
		last_dir = (points[i] - points[i - 1]).normalized()
		if not last_dir.is_zero_approx():
			break
	var extra := 2 if (antialiased and not loop) else 0
	var mid := PackedVector2Array()
	var mid_c := PackedColorArray()
	mid.resize(n * 2 + extra * 2)
	mid_c.resize(n * 2 + extra * 2)
	var clear := Color(color, 0.0)
	var left := PackedVector2Array()
	var left_c := PackedColorArray()
	var right := PackedVector2Array()
	var right_c := PackedColorArray()
	var border_size := FEATHER
	if antialiased:
		if width < 1.0:
			border_size *= width
		var side := n * 2 + (0 if loop else 5)
		left.resize(side)
		left_c.resize(side)
		right.resize(side)
		right_c.resize(side)
	var prev_dir := Vector2.ZERO
	for i in n:
		var is_first := i == 0
		var is_last := i == n - 1
		var seg_dir := _segment_dir(points, i, prev_dir)
		if is_first and loop:
			prev_dir = last_dir
		elif is_last and loop:
			prev_dir = first_dir
		var base_off: Vector2
		if is_first and not loop:
			base_off = first_dir.orthogonal()
		elif is_last and not loop:
			base_off = last_dir.orthogonal()
		else:
			base_off = _edge_offset(seg_dir, prev_dir)
		var off := base_off * (width * 0.5)
		var pos := points[i]
		if not antialiased:
			mid[i * 2] = pos + off
			mid[i * 2 + 1] = pos - off
			mid_c[i * 2] = color
			mid_c[i * 2 + 1] = color
			prev_dir = seg_dir
			continue
		var border := base_off * border_size
		var j := i * 2 + (0 if loop else 2)
		mid[j] = pos + off
		mid[j + 1] = pos - off
		left[j] = pos + off
		left[j + 1] = pos + off + border
		right[j] = pos - off
		right[j + 1] = pos - off - border
		mid_c[j] = color
		mid_c[j + 1] = color
		left_c[j] = color
		left_c[j + 1] = clear
		right_c[j] = color
		right_c[j + 1] = clear
		if is_first and not loop:
			var bb := -seg_dir * border_size
			mid[0] = pos + off + bb
			mid[1] = pos - off + bb
			mid_c[0] = clear
			mid_c[1] = clear
			left[0] = pos + off + bb
			left[1] = pos + off + bb + border
			left_c[0] = clear
			left_c[1] = clear
			right[0] = pos - off + bb
			right[1] = pos - off + bb - border
			right_c[0] = clear
			right_c[1] = clear
		if is_last and not loop:
			var eb := prev_dir * border_size
			var e := n * 2 + 2
			mid[e] = pos + off + eb
			mid[e + 1] = pos - off + eb
			mid_c[e] = clear
			mid_c[e + 1] = clear
			left[e] = pos + off
			left[e + 1] = pos + off + eb + border
			left[e + 2] = pos + off + eb
			left_c[e] = color
			left_c[e + 1] = clear
			left_c[e + 2] = clear
			right[e] = pos - off
			right[e + 1] = pos - off + eb - border
			right[e + 2] = pos - off + eb
			right_c[e] = color
			right_c[e + 1] = clear
			right_c[e + 2] = clear
		prev_dir = seg_dir
	# Godot draws the middle strip, then the left and right feathers.
	_strip(mid, mid_c)
	if antialiased:
		_strip(left, left_c)
		_strip(right, right_c)


func draw_arc(center: Vector2, radius: float, start_angle: float, end_angle: float, point_count: int,
		color: Color, width: float = -1.0, antialiased: bool = false) -> void:
	var pts := PackedVector2Array()
	pts.resize(point_count)
	var delta := clampf(end_angle - start_angle, -TAU, TAU)
	for i in point_count:
		var theta := (i / (point_count - 1.0)) * delta + start_angle
		pts[i] = center + Vector2(radius * cos(theta), radius * sin(theta))
	draw_polyline(pts, color, width, antialiased)


# --- Passed straight through, after what has been collected ---------------

func draw_circle(position: Vector2, radius: float, color: Color, filled: bool = true, width: float = -1.0, antialiased: bool = false) -> void:
	flush()
	ci.draw_circle(position, radius, color, filled, width, antialiased)


func draw_rect(rect: Rect2, color: Color, filled: bool = true, width: float = -1.0, antialiased: bool = false) -> void:
	flush()
	ci.draw_rect(rect, color, filled, width, antialiased)


func draw_texture_rect_region(texture: Texture2D, rect: Rect2, src_rect: Rect2, modulate: Color = Color(1, 1, 1),
		transpose: bool = false, clip_uv: bool = true) -> void:
	flush()
	ci.draw_texture_rect_region(texture, rect, src_rect, modulate, transpose, clip_uv)


func draw_string(font: Font, pos: Vector2, text: String, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT,
		width: float = -1, font_size: int = 16, modulate: Color = Color(1, 1, 1)) -> void:
	flush()
	ci.draw_string(font, pos, text, alignment, width, font_size, modulate)


func draw_set_transform(position: Vector2, rotation: float = 0.0, scale: Vector2 = Vector2.ONE) -> void:
	flush()
	ci.draw_set_transform(position, rotation, scale)


# --- Geometry --------------------------------------------------------------

func _quad(a: Vector2, b: Vector2, c: Vector2, d: Vector2, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	_pts.append(a)
	_pts.append(b)
	_pts.append(c)
	_pts.append(a)
	_pts.append(c)
	_pts.append(d)
	_cols.append(ca)
	_cols.append(cb)
	_cols.append(cc)
	_cols.append(ca)
	_cols.append(cc)
	_cols.append(cd)


## A triangle strip as separate triangles.
func _strip(p: PackedVector2Array, c: PackedColorArray) -> void:
	for k in p.size() - 2:
		_pts.append(p[k])
		_pts.append(p[k + 1])
		_pts.append(p[k + 2])
		_cols.append(c[k])
		_cols.append(c[k + 1])
		_cols.append(c[k + 2])


static func _compensated(w: float) -> float:
	if w <= 0.0:
		return w
	if w <= FEATHER * 2.0 + EPS:
		return w * 0.5
	if w <= FEATHER * 4.0 + EPS:
		return remap(w, FEATHER * 2.0, FEATHER * 4.0, w * 0.5, w - FEATHER * 0.5)
	return w - FEATHER * 0.5


static func _segment_dir(p: PackedVector2Array, i: int, prev: Vector2) -> Vector2:
	if i == p.size() - 1:
		return prev
	var d := (p[i + 1] - p[i]).normalized()
	return prev if d.is_zero_approx() else d


static func _edge_offset(seg: Vector2, prev: Vector2) -> Vector2:
	var length := 1.0
	var bisector := (prev * seg.length() - seg * prev.length()).normalized()
	var angle := atan2(bisector.cross(prev), bisector.dot(prev))
	var s := sin(angle)
	if not is_zero_approx(s) and not seg.is_equal_approx(prev):
		length = clampf(1.0 / s, -3.0, 3.0)
	else:
		bisector = seg.orthogonal()
	if bisector.is_zero_approx():
		bisector = seg.orthogonal()
	return bisector * length
