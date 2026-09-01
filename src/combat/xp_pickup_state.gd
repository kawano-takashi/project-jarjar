class_name XpPickupState
extends RefCounted


var pool_index: int = -1
var generation: int = 0
var active: bool = false
var position: Vector2 = Vector2.ZERO
var value: int = 0
var born_tick: int = 0


func activate(p_position: Vector2, p_value: int, p_born_tick: int) -> void:
	active = true
	position = p_position
	value = maxi(1, p_value)
	born_tick = p_born_tick


func deactivate() -> void:
	active = false
	position = Vector2.ZERO
	value = 0
	born_tick = 0
