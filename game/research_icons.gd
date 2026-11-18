## Small drawn icons for research items, and their colours, for the
## research screen. An unknown item gets a plain dot.
extends RefCounted

const COLORS := {
	"radar": Color(0.56, 0.82, 0.96),
	"scouting_missile": Color(0.96, 0.56, 0.22),
	"anti_air_capacity": Color(0.48, 0.80, 0.42),
	"motion_sensor": Color(0.96, 0.86, 0.32),
	"ballistic_launcher": Color(0.78, 0.38, 0.32),
}


static func color_of(item: String) -> Color:
	return COLORS.get(item, Color(0.7, 0.72, 0.75))


## Draws the icon for `item` centred on c, about 2r across.
static func draw(ci: CanvasItem, item: String, c: Vector2, r: float, ink: Color) -> void:
	match item:
		"radar":
			# A dish on a stand, with signal arcs.
			ci.draw_arc(c + Vector2(-r * 0.15, r * 0.05), r * 0.55, PI * 0.15, PI * 1.15, 16, ink, 2.0, true)
			ci.draw_line(c + Vector2(-r * 0.15, r * 0.05), c + Vector2(r * 0.25, -r * 0.35), ink, 2.0, true)
			ci.draw_line(c + Vector2(-r * 0.1, r * 0.35), c + Vector2(-r * 0.1, r * 0.8), ink, 2.0, true)
			ci.draw_line(c + Vector2(-r * 0.45, r * 0.8), c + Vector2(r * 0.25, r * 0.8), ink, 2.0, true)
			for k in 2:
				ci.draw_arc(c + Vector2(r * 0.25, -r * 0.35), r * (0.3 + 0.25 * k), -PI * 0.45, PI * 0.05, 10, ink, 1.6, true)
		"scouting_missile":
			# A small missile flying up and right, with fins and an eye trail.
			var d := Vector2(1, -1).normalized()
			var n := d.orthogonal()
			var tail := c - d * r * 0.75
			var nose := c + d * r * 0.8
			ci.draw_line(tail, nose - d * r * 0.25, ink, 4.0, true)
			ci.draw_colored_polygon(PackedVector2Array([nose, nose - d * r * 0.35 + n * r * 0.18, nose - d * r * 0.35 - n * r * 0.18]), ink)
			ci.draw_colored_polygon(PackedVector2Array([tail, tail + d * r * 0.35 + n * r * 0.35, tail + d * r * 0.25]), ink)
			ci.draw_colored_polygon(PackedVector2Array([tail, tail + d * r * 0.35 - n * r * 0.35, tail + d * r * 0.25]), ink)
		"anti_air_capacity":
			# A crosshair.
			ci.draw_arc(c, r * 0.65, 0.0, TAU, 24, ink, 2.0, true)
			ci.draw_arc(c, r * 0.25, 0.0, TAU, 16, ink, 2.0, true)
			for v in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				ci.draw_line(c + v * r * 0.35, c + v * r * 0.95, ink, 2.0, true)
		"motion_sensor":
			# A trace with a spike.
			var pts := PackedVector2Array([c + Vector2(-r, 0), c + Vector2(-r * 0.45, 0), c + Vector2(-r * 0.25, -r * 0.7),
				c + Vector2(0, r * 0.75), c + Vector2(r * 0.2, -r * 0.35), c + Vector2(r * 0.4, 0), c + Vector2(r, 0)])
			ci.draw_polyline(pts, ink, 2.2, true)
		"ballistic_launcher":
			# A tilted tube on a base.
			var d := Vector2(1, -1.2).normalized()
			var base := c + Vector2(-r * 0.2, r * 0.45)
			ci.draw_line(base, base + d * r * 1.1, ink, 5.0, true)
			ci.draw_rect(Rect2(c + Vector2(-r * 0.75, r * 0.45), Vector2(r * 1.3, r * 0.35)), ink)
		_:
			ci.draw_circle(c, r * 0.35, ink)
