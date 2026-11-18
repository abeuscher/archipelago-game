## Map colours and the small painted details shared by the boards, the sea
## around them and the minimap: bright sea with lighter shallows and wave
## marks, white surf on the coast, olive lowland, tan hills and pale sand on
## the top level, all with dark ink outlines. Presentation only.
extends RefCounted

const SEA := Color(0.17, 0.48, 0.74)
const SEA_SHALLOW := Color(0.36, 0.70, 0.86)
const SEA_LINE := Color(0.30, 0.60, 0.84, 0.55)
const WAVE := Color(0.88, 0.96, 1.0, 0.55)
const SURF := Color(0.93, 0.98, 1.0, 0.95)
const SURF_OUTER := Color(0.62, 0.86, 0.96, 0.75)
const LAND_TOP := [Color(0.60, 0.61, 0.27), Color(0.80, 0.61, 0.34), Color(0.91, 0.76, 0.54)]
const WALL := [Color(0.45, 0.36, 0.18), Color(0.55, 0.38, 0.21), Color(0.64, 0.46, 0.29)]
const INK := Color(0.17, 0.12, 0.07, 0.9)
const GRASS := Color(0.36, 0.42, 0.15)
const SPECK := [Color(0.0, 0.0, 0.0, 0.0), Color(0.62, 0.43, 0.22, 0.8), Color(0.74, 0.58, 0.38, 0.8)]


static func hash_i(i: int) -> int:
	return ((i + 1) * 2654435761) & 0x7FFFFFFF


static func next_h(h: int) -> int:
	return (h * 1103515245 + 12345) & 0x7FFFFFFF


## Hash for a lattice hex given by its screen centre, so marks stay put.
static func hash_v(c: Vector2) -> int:
	return hash_i(roundi(c.x) * 7919 + roundi(c.y) * 104729)


## A small "~" wave mark on about one sea hex in three.
static func draw_wave(ci: CanvasItem, c: Vector2, h: int) -> void:
	if h % 3 != 0:
		return
	var h2 := next_h(h)
	var o := c + Vector2(float(h2 % 17) - 8.0, float((h2 / 17) % 9) - 4.0)
	var pts := PackedVector2Array()
	for k in 9:
		var t := float(k) / 8.0
		pts.append(o + Vector2((t - 0.5) * 14.0, -sin(t * TAU) * 2.0))
	ci.draw_polyline(pts, WAVE, 1.4, true)


## A couple of grass tufts on lowland, or a few specks on higher ground.
static func draw_ground_marks(ci: CanvasItem, c: Vector2, level: int, h: int) -> void:
	var n := 2 if level == 0 else 1
	for k in n:
		h = next_h(h)
		var o := c + Vector2(float(h % 31) - 15.0, float((h / 31) % 13) - 6.0)
		if level == 0:
			for dx in [-3.0, 0.0, 3.0]:
				ci.draw_line(o, o + Vector2(dx * 0.9, -4.0 - absf(dx) * -0.3), GRASS, 1.2, true)
		elif h % 2 == 0:
			ci.draw_line(o, o + Vector2(4, 0), SPECK[clampi(level, 0, 2)], 1.4, true)
