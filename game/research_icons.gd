## Small drawn icons for research items, and their colours, for the
## research screen. An unknown item gets a plain dot.
extends RefCounted

const COLORS := {
	"radar": Color(0.56, 0.82, 0.96),
	"scouting_missile": Color(0.96, 0.56, 0.22),
	"anti_air_capacity": Color(0.48, 0.80, 0.42),
	"motion_sensor": Color(0.96, 0.86, 0.32),
	"ballistic_launcher": Color(0.78, 0.38, 0.32),
	"airport": Color(0.66, 0.64, 0.94),
	"bunker": Color(0.72, 0.71, 0.66),
	"docks": Color(0.38, 0.78, 0.76),
	"coastal_cannon": Color(0.60, 0.70, 0.86),
	"nuclear_silo": Color(0.91, 0.76, 0.18),
	"bank_upgrade": Color(0.80, 0.64, 0.72),
	"spy": Color(0.62, 0.66, 0.74),
	"refinery_upgrade": Color(0.90, 0.52, 0.30),
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
		"airport":
			# A plane seen from above, nose up and right.
			var d := Vector2(1, -1).normalized()
			var n := d.orthogonal()
			ci.draw_line(c - d * r * 0.85, c + d * r * 0.85, ink, 4.0, true)
			ci.draw_colored_polygon(PackedVector2Array([c + d * r * 0.15, c - d * r * 0.25 + n * r * 0.8, c - d * r * 0.35 + n * r * 0.7, c - d * r * 0.2,
				c - d * r * 0.35 - n * r * 0.7, c - d * r * 0.25 - n * r * 0.8]), ink)
			ci.draw_colored_polygon(PackedVector2Array([c - d * r * 0.6, c - d * r * 0.85 + n * r * 0.35, c - d * r * 0.85 - n * r * 0.35]), ink)
		"bunker":
			# A low pillbox with a gun slit.
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.85, r * 0.55), c + Vector2(-r * 0.6, -r * 0.25),
				c + Vector2(r * 0.6, -r * 0.25), c + Vector2(r * 0.85, r * 0.55)]), ink)
			ci.draw_rect(Rect2(c + Vector2(-r * 0.4, -r * 0.02), Vector2(r * 0.8, r * 0.16)), Color(1, 1, 1, 0.85))
		"docks":
			# An anchor.
			ci.draw_line(c + Vector2(0, -r * 0.6), c + Vector2(0, r * 0.75), ink, 2.4, true)
			ci.draw_arc(c + Vector2(0, -r * 0.75), r * 0.17, 0.0, TAU, 12, ink, 2.0, true)
			ci.draw_line(c + Vector2(-r * 0.4, -r * 0.3), c + Vector2(r * 0.4, -r * 0.3), ink, 2.2, true)
			ci.draw_arc(c + Vector2(0, r * 0.1), r * 0.65, PI * 0.15, PI * 0.85, 14, ink, 2.4, true)
		"coastal_cannon":
			# A heavy barrel on a round turret.
			ci.draw_arc(c + Vector2(-r * 0.15, r * 0.25), r * 0.5, PI, TAU, 14, ink, 3.0, true)
			ci.draw_line(c + Vector2(-r * 0.65, r * 0.25), c + Vector2(r * 0.35, r * 0.25), ink, 3.0, true)
			ci.draw_line(c + Vector2(-r * 0.05, -r * 0.05), c + Vector2(r * 0.85, -r * 0.6), ink, 5.0, true)
		"nuclear_silo":
			# The radiation trefoil: three blades round a hub.
			for k in 3:
				var a := -PI / 2.0 + TAU * k / 3.0
				var pts := PackedVector2Array([c])
				for j in 7:
					var t := a - 0.52 + 1.04 * j / 6.0
					pts.append(c + Vector2(cos(t), sin(t)) * r * 0.85)
				ci.draw_colored_polygon(pts, ink)
			ci.draw_circle(c, r * 0.3, COLORS["nuclear_silo"])
			ci.draw_circle(c, r * 0.18, ink)
		"bank_upgrade":
			# A stack of coins with an up arrow.
			for k in 3:
				var y := r * (0.65 - 0.3 * k)
				ci.draw_rect(Rect2(c + Vector2(-r * 0.75, y - r * 0.12), Vector2(r * 0.8, r * 0.24)), ink, false, 2.0)
			ci.draw_line(c + Vector2(r * 0.55, r * 0.7), c + Vector2(r * 0.55, -r * 0.6), ink, 2.4, true)
			ci.draw_line(c + Vector2(r * 0.55, -r * 0.7), c + Vector2(r * 0.25, -r * 0.3), ink, 2.4, true)
			ci.draw_line(c + Vector2(r * 0.55, -r * 0.7), c + Vector2(r * 0.85, -r * 0.3), ink, 2.4, true)
		"spy":
			# A man in a tuxedo: hat brim and crown, head, lapels and a bow tie.
			ci.draw_rect(Rect2(c + Vector2(-r * 0.6, -r * 0.62), Vector2(r * 1.2, r * 0.12)), ink)
			ci.draw_rect(Rect2(c + Vector2(-r * 0.34, -r * 0.95), Vector2(r * 0.68, r * 0.36)), ink)
			ci.draw_arc(c + Vector2(0, -r * 0.3), r * 0.28, 0.0, TAU, 16, ink, 2.0, true)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.75, r * 0.95), c + Vector2(-r * 0.6, r * 0.15),
				c + Vector2(-r * 0.12, r * 0.12), c + Vector2(0, r * 0.95)]), ink)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.75, r * 0.95), c + Vector2(r * 0.6, r * 0.15),
				c + Vector2(r * 0.12, r * 0.12), c + Vector2(0, r * 0.95)]), ink)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, r * 0.22), c + Vector2(-r * 0.24, r * 0.1),
				c + Vector2(-r * 0.24, r * 0.34)]), ink)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, r * 0.22), c + Vector2(r * 0.24, r * 0.1),
				c + Vector2(r * 0.24, r * 0.34)]), ink)
		"refinery_upgrade":
			# A fuel drop with an up arrow.
			var drop := PackedVector2Array([c + Vector2(-r * 0.25, -r * 0.8)])
			for j in 13:
				var t := PI * j / 12.0
				drop.append(c + Vector2(-r * 0.25, r * 0.35) + Vector2(cos(t) * r * 0.5, sin(t) * r * 0.5))
			drop.append(c + Vector2(-r * 0.25, -r * 0.8))
			ci.draw_polyline(drop, ink, 2.2, true)
			ci.draw_line(c + Vector2(r * 0.6, r * 0.7), c + Vector2(r * 0.6, -r * 0.6), ink, 2.4, true)
			ci.draw_line(c + Vector2(r * 0.6, -r * 0.7), c + Vector2(r * 0.3, -r * 0.3), ink, 2.4, true)
			ci.draw_line(c + Vector2(r * 0.6, -r * 0.7), c + Vector2(r * 0.9, -r * 0.3), ink, 2.4, true)
		_:
			ci.draw_circle(c, r * 0.35, ink)
