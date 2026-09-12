class_name ArenaNodeState
extends RefCounted

var _world: RefCounted
var pool_index: int = -1
var node_id: int:
	get:
		return int(_world.node_get(pool_index, &"node_id"))
	set(value):
		_world.node_set(pool_index, &"node_id", value)
var position: Vector2:
	get:
		return _world.node_get(pool_index, &"position")
	set(value):
		_world.node_set(pool_index, &"position", value)
var hp: float:
	get:
		return float(_world.node_get(pool_index, &"hp"))
	set(value):
		_world.node_set(pool_index, &"hp", value)
var active: bool:
	get:
		return bool(_world.node_get(pool_index, &"active"))
	set(value):
		_world.node_set(pool_index, &"active", value)


func activate(p_node_id: int, p_position: Vector2, max_hp: float) -> void:
	node_id = p_node_id
	position = p_position
	hp = maxf(1.0, max_hp)
	active = true


func deactivate() -> void:
	hp = 0.0
	active = false
