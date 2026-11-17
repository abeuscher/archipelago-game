## The only source of randomness in the game.
##
## xoshiro128** on 32-bit words, written with plain integer maths so the
## sequence never depends on the engine version or platform. A match has one
## root seed; separate streams (island generation, dice, each AI) are derived
## from that seed by name so that changing one consumer does not shift the
## numbers the others see.
extends RefCounted

const MASK := 0xFFFFFFFF

var _s0: int
var _s1: int
var _s2: int
var _s3: int


func _init(seed_value: int = 0) -> void:
	seed_with(seed_value)


## A new generator whose seed is derived from a root seed and a stream name.
static func derive(root_seed: int, stream: String):
	var script: GDScript = load("res://rules/rng.gd")
	return script.new(_mix(root_seed & MASK, _fnv1a(stream)) ^ ((root_seed >> 32) & MASK))


func seed_with(seed_value: int) -> void:
	var state := (seed_value & MASK) ^ ((seed_value >> 32) & MASK)
	var out: Array[int] = []
	for i in 4:
		state = (state + 0x9E3779B9) & MASK
		out.append(_fmix32(state))
	_s0 = out[0]
	_s1 = out[1]
	_s2 = out[2]
	_s3 = out[3]
	if (_s0 | _s1 | _s2 | _s3) == 0:
		_s0 = 1


func next_u32() -> int:
	var result := (_rotl((_s1 * 5) & MASK, 7) * 9) & MASK
	var t := (_s1 << 9) & MASK
	_s2 ^= _s0
	_s3 ^= _s1
	_s1 ^= _s2
	_s0 ^= _s3
	_s2 ^= t
	_s3 = _rotl(_s3, 11)
	return result


## Uniform float in [0, 1).
## (Named rand_* so a bare call can never fall through to the engine's
## global, unseeded randf()/randi_range().)
func rand_float() -> float:
	return float(next_u32()) / 4294967296.0


## Uniform integer in [lo, hi], inclusive, without modulo bias.
func rand_int(lo: int, hi: int) -> int:
	if hi <= lo:
		return lo
	var span := hi - lo + 1
	var limit := (0x100000000 / span) * span
	var r := next_u32()
	while r >= limit:
		r = next_u32()
	return lo + (r % span)


func chance(p: float) -> bool:
	return rand_float() < p


func pick(items: Array):
	if items.is_empty():
		return null
	return items[rand_int(0, items.size() - 1)]


## Fisher-Yates shuffle in place.
func shuffle(items: Array) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := rand_int(0, i)
		var tmp = items[i]
		items[i] = items[j]
		items[j] = tmp


func get_state() -> Array[int]:
	return [_s0, _s1, _s2, _s3]


func set_state(state: Array) -> void:
	_s0 = int(state[0])
	_s1 = int(state[1])
	_s2 = int(state[2])
	_s3 = int(state[3])


func copy():
	var c = get_script().new(0)
	c.set_state(get_state())
	return c


static func _rotl(x: int, k: int) -> int:
	return ((x << k) | (x >> (32 - k))) & MASK


## 32-bit multiply modulo 2^32 that never overflows a 64-bit int.
static func _mul32(a: int, b: int) -> int:
	return (a * (b & 0xFFFF) + (((a * (b >> 16)) & 0xFFFF) << 16)) & MASK


static func _fmix32(h: int) -> int:
	h = _mul32(h ^ (h >> 16), 0x85EBCA6B)
	h = _mul32(h ^ (h >> 13), 0xC2B2AE35)
	return h ^ (h >> 16)


static func _mix(a: int, b: int) -> int:
	return _fmix32((a ^ _mul32(b, 0x9E3779B1)) & MASK)


static func _fnv1a(text: String) -> int:
	var h := 0x811C9DC5
	for byte in text.to_utf8_buffer():
		h = ((h ^ byte) * 16777619) & MASK
	return h
