class_name SwarmWarningState
extends RefCounted


var anchor: Vector2 = Vector2.ZERO
var direction: Vector2 = Vector2.ZERO
var spawn_distance: float = 0.0
var start_tick: int = 0
var spawn_tick: int = 0
var hp_multiplier: float = 0.0
var damage_multiplier: float = 0.0


func progress(current_tick: int) -> float:
	return clampf(float(current_tick - start_tick) / float(maxi(1, spawn_tick - start_tick)), 0.0, 1.0)
