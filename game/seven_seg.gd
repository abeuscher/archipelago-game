## The phase timer (section 14): a seven-segment readout like a digital
## watch or an old scoreboard counter. When the clock is not running it is
## a plain black box.
extends Control

const LIT := Color(1.0, 0.22, 0.12)
const UNLIT := Color(0.09, 0.025, 0.02)
const URGENT_SECONDS := 10

## Segments a..g: top, top-right, bottom-right, bottom, bottom-left,
## top-left, middle.
const DIGITS := {
	"0": "abcdef", "1": "bc", "2": "abged", "3": "abgcd", "4": "fgbc",
	"5": "afgcd", "6": "afgedc", "7": "abc", "8": "abcdefg", "9": "abcdfg", " ": "",
}

var running: bool = false
var seconds: int = 0
var _blink: float = 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(0, 64)


func set_time(secs: float) -> void:
	var was := running
	running = secs >= 0.0
	var s := ceili(maxf(secs, 0.0)) if running else 0
	if s != seconds or was != running:
		seconds = s
		queue_redraw()


func _process(delta: float) -> void:
	if running and seconds <= URGENT_SECONDS:
		_blink += delta
		queue_redraw()


static func text_for(secs: int) -> String:
	var m := mini(secs / 60, 99)
	return "%2d%02d" % [m, secs % 60]


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.18, 0.18, 0.2), false, 2.0)
	if not running:
		return
	var txt := text_for(seconds)
	var h := size.y * 0.7
	var w := h * 0.55
	var gap := w * 0.6
	var colon := w * 0.7
	var total := w * 4 + gap * 3 + colon
	var x := (size.x - total) / 2.0
	var y := (size.y - h) / 2.0
	var lit := LIT
	if seconds <= URGENT_SECONDS and fmod(_blink, 1.0) > 0.6:
		lit = LIT.darkened(0.5)
	for i in 4:
		_digit(Vector2(x, y), w, h, txt[i], lit)
		x += w + gap
		if i == 1:
			var r := w * 0.11
			var cx := x + colon / 2.0 - gap / 2.0
			draw_circle(Vector2(cx, y + h * 0.3), r, lit)
			draw_circle(Vector2(cx, y + h * 0.7), r, lit)
			x += colon


func _digit(o: Vector2, w: float, h: float, ch: String, lit: Color) -> void:
	var on: String = DIGITS.get(ch, "")
	var t := w * 0.22
	var hh := h / 2.0
	var segs := {
		"a": [Vector2(o.x + t, o.y), Vector2(o.x + w - t, o.y), true],
		"g": [Vector2(o.x + t, o.y + hh), Vector2(o.x + w - t, o.y + hh), true],
		"d": [Vector2(o.x + t, o.y + h), Vector2(o.x + w - t, o.y + h), true],
		"f": [Vector2(o.x, o.y + t), Vector2(o.x, o.y + hh - t), false],
		"b": [Vector2(o.x + w, o.y + t), Vector2(o.x + w, o.y + hh - t), false],
		"e": [Vector2(o.x, o.y + hh + t), Vector2(o.x, o.y + h - t), false],
		"c": [Vector2(o.x + w, o.y + hh + t), Vector2(o.x + w, o.y + h - t), false],
	}
	for k in segs:
		var s: Array = segs[k]
		_segment(s[0], s[1], t, lit if on.contains(k) else UNLIT)


## A segment with pointed ends, from p to q, thickness t.
func _segment(p: Vector2, q: Vector2, t: float, col: Color) -> void:
	var d := (q - p).normalized()
	var n := Vector2(-d.y, d.x) * t / 2.0
	var e := d * t / 2.0
	draw_colored_polygon(PackedVector2Array([p, p + e + n, q - e + n, q, q - e - n, p + e - n]), col)
