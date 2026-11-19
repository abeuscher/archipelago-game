## A rectangular space of pointy-top hexes in "odd-r" offset layout.
## Hexes are addressed by index = row * width + col. Distances and
## neighbours use axial coordinates (q, r).
extends RefCounted

const AXIAL_DIRS := [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]

var width: int
var height: int
var count: int
var _axial: Array[Vector2i] = []
var _neighbors: Array[PackedInt32Array] = []


func _init(w: int, h: int) -> void:
	width = w
	height = h
	count = w * h
	for i in count:
		_axial.append(offset_to_axial(col_of(i), row_of(i)))
	for i in count:
		var n := PackedInt32Array()
		for d in AXIAL_DIRS:
			var j := axial_to_index(_axial[i] + d)
			if j >= 0:
				n.append(j)
		_neighbors.append(n)


func col_of(index: int) -> int:
	return index % width


func row_of(index: int) -> int:
	return index / width


func index_of(col: int, row: int) -> int:
	if col < 0 or row < 0 or col >= width or row >= height:
		return -1
	return row * width + col


func is_valid(index: int) -> bool:
	return index >= 0 and index < count


func axial_of(index: int) -> Vector2i:
	return _axial[index]


static func offset_to_axial(col: int, row: int) -> Vector2i:
	return Vector2i(col - (row - (row & 1)) / 2, row)


func axial_to_index(a: Vector2i) -> int:
	var row := a.y
	var col := a.x + (row - (row & 1)) / 2
	return index_of(col, row)


func distance(a: int, b: int) -> int:
	var d := _axial[a] - _axial[b]
	return (absi(d.x) + absi(d.x + d.y) + absi(d.y)) / 2


## The hex one step from `index` in direction d (an index into
## AXIAL_DIRS), or -1 off the space.
func step(index: int, d: int) -> int:
	return axial_to_index(_axial[index] + AXIAL_DIRS[posmod(d, 6)])


## The direction (index into AXIAL_DIRS) from a to its neighbour b, or -1
## if they aren't neighbours.
func direction_to(a: int, b: int) -> int:
	return AXIAL_DIRS.find(_axial[b] - _axial[a])


func neighbors(index: int) -> PackedInt32Array:
	return _neighbors[index]


## All valid hexes within `radius` of `index`, including itself, in index order.
func within(index: int, radius: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if radius < 0:
		return out
	var c := _axial[index]
	for dq in range(-radius, radius + 1):
		for dr in range(maxi(-radius, -dq - radius), mini(radius, -dq + radius) + 1):
			var j := axial_to_index(c + Vector2i(dq, dr))
			if j >= 0:
				out.append(j)
	out.sort()
	return out


func center_index() -> int:
	return index_of(width / 2, height / 2)
