class_name VfxState
extends RefCounted


var pool_index: int = -1
var generation: int = 0
var active: bool = false
var position: Vector2 = Vector2.ZERO
var scale_m: float = 1.0
var remaining_lifetime: float = 0.0
var color: Color = Color.WHITE
var born_physics_tick: int = 0


func activate(
	p_position: Vector2,
	p_scale_m: float,
	p_lifetime: float,
	p_color: Color,
	p_born_physics_tick: int,
) -> void:
	active = true
	position = p_position
	scale_m = p_scale_m
	remaining_lifetime = p_lifetime
	color = p_color
	born_physics_tick = p_born_physics_tick


func deactivate() -> void:
	active = false
	position = Vector2.ZERO
	scale_m = 1.0
	remaining_lifetime = 0.0
	color = Color.WHITE
	born_physics_tick = 0
