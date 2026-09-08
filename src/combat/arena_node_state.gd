class_name ArenaNodeState
extends RefCounted


var node_id: int = -1
var position: Vector2 = Vector2.ZERO
var hp: float = 0.0
var active: bool = false


func activate(p_node_id: int, p_position: Vector2, max_hp: float) -> void:
	node_id = p_node_id
	position = p_position
	hp = maxf(1.0, max_hp)
	active = true


func deactivate() -> void:
	hp = 0.0
	active = false
