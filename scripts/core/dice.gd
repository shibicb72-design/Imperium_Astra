class_name Dice
extends RefCounted
## Two six-sided dice. Tests queue exact rolls with force().

signal rolled(d1: int, d2: int)

var d1: int = 0
var d2: int = 0
var rng := RandomNumberGenerator.new()
var _forced: Array[Vector2i] = []


func force(a: int, b: int) -> void:
	_forced.append(Vector2i(a, b))


func roll() -> void:
	if _forced.is_empty():
		d1 = rng.randi_range(1, 6)
		d2 = rng.randi_range(1, 6)
	else:
		var f: Vector2i = _forced.pop_front()
		d1 = f.x
		d2 = f.y
	rolled.emit(d1, d2)


func total() -> int:
	return d1 + d2


func is_doubles() -> bool:
	return d1 == d2
