class_name XpPickupState
extends RefCounted

var _world: RefCounted
var pool_index: int = -1
var generation: int:
	get:
		return int(_world.xp_get(pool_index, &"generation"))
	set(value):
		_world.xp_set(pool_index, &"generation", value)
var active: bool:
	get:
		return bool(_world.xp_get(pool_index, &"active"))
	set(value):
		_world.xp_set(pool_index, &"active", value)
var position: Vector2:
	get:
		return _world.xp_get(pool_index, &"position")
	set(value):
		_world.xp_set(pool_index, &"position", value)
var value: int:
	get:
		return int(_world.xp_get(pool_index, &"value"))
	set(value):
		_world.xp_set(pool_index, &"value", value)
var born_tick: int:
	get:
		return int(_world.xp_get(pool_index, &"born_tick"))
	set(value):
		_world.xp_set(pool_index, &"born_tick", value)

var visual_transform: Transform3D:
	get:
		return _world.xp_transform(pool_index)
