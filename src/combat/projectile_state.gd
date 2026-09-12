class_name ProjectileState
extends RefCounted

## A view of native storage; numeric state has one owner.
var _world: RefCounted


const FACTION_ALLY: StringName = &"ally"
const FACTION_ENEMY: StringName = &"enemy"
const BASE_VISUAL_HEIGHT: float = 0.35
const ARC_APEX_BONUS_HEIGHT: float = 1.8

enum MovementKind { STRAIGHT, HOMING, ARC, RETURNING }

var pool_index: int = -1
var generation: int:
	get:
		return int(_world.projectile_get(pool_index, &"generation"))
	set(value):
		_world.projectile_set(pool_index, &"generation", value)
var active: bool:
	get:
		return bool(_world.projectile_get(pool_index, &"active"))
	set(value):
		_world.projectile_set(pool_index, &"active", value)
var faction: StringName:
	get:
		return _world.projectile_get(pool_index, &"faction")
	set(value):
		_world.projectile_set(pool_index, &"faction", value)
var weapon_id: StringName:
	get:
		return _world.projectile_get(pool_index, &"weapon_id")
	set(value):
		_world.projectile_set(pool_index, &"weapon_id", value)
var source_entity_id: int:
	get:
		return int(_world.projectile_get(pool_index, &"source_entity_id"))
	set(value):
		_world.projectile_set(pool_index, &"source_entity_id", value)
var position: Vector2:
	get:
		return _world.projectile_get(pool_index, &"position")
	set(value):
		_world.projectile_set(pool_index, &"position", value)
var previous_position: Vector2:
	get:
		return _world.projectile_get(pool_index, &"previous_position")
	set(value):
		_world.projectile_set(pool_index, &"previous_position", value)
var velocity: Vector2:
	get:
		return _world.projectile_get(pool_index, &"velocity")
	set(value):
		_world.projectile_set(pool_index, &"velocity", value)
var radius: float:
	get:
		return float(_world.projectile_get(pool_index, &"radius"))
	set(value):
		_world.projectile_set(pool_index, &"radius", value)
var damage: float:
	get:
		return float(_world.projectile_get(pool_index, &"damage"))
	set(value):
		_world.projectile_set(pool_index, &"damage", value)
var remaining_distance: float:
	get:
		return float(_world.projectile_get(pool_index, &"remaining_distance"))
	set(value):
		_world.projectile_set(pool_index, &"remaining_distance", value)
var previous_remaining_distance: float:
	get:
		return float(_world.projectile_get(pool_index, &"previous_remaining_distance"))
	set(value):
		_world.projectile_set(pool_index, &"previous_remaining_distance", value)
var outbound_distance_remaining: float:
	get:
		return float(_world.projectile_get(pool_index, &"outbound_distance_remaining"))
	set(value):
		_world.projectile_set(pool_index, &"outbound_distance_remaining", value)
var remaining_lifetime: float:
	get:
		return float(_world.projectile_get(pool_index, &"remaining_lifetime"))
	set(value):
		_world.projectile_set(pool_index, &"remaining_lifetime", value)
var target_position: Vector2:
	get:
		return _world.projectile_get(pool_index, &"target_position")
	set(value):
		_world.projectile_set(pool_index, &"target_position", value)
var pierce_remaining: int:
	get:
		return int(_world.projectile_get(pool_index, &"pierce_remaining"))
	set(value):
		_world.projectile_set(pool_index, &"pierce_remaining", value)
var born_tick: int:
	get:
		return int(_world.projectile_get(pool_index, &"born_tick"))
	set(value):
		_world.projectile_set(pool_index, &"born_tick", value)
var source_effect_id: StringName:
	get:
		return _world.projectile_get(pool_index, &"source_effect_id")
	set(value):
		_world.projectile_set(pool_index, &"source_effect_id", value)
var movement_kind: MovementKind:
	get:
		return int(_world.projectile_get(pool_index, &"movement_kind")) as MovementKind
	set(value):
		_world.projectile_set(pool_index, &"movement_kind", value)
var target_entity_id: int:
	get:
		return int(_world.projectile_get(pool_index, &"target_entity_id"))
	set(value):
		_world.projectile_set(pool_index, &"target_entity_id", value)
var speed: float:
	get:
		return float(_world.projectile_get(pool_index, &"speed"))
	set(value):
		_world.projectile_set(pool_index, &"speed", value)
var elapsed_ticks: float:
	get:
		return float(_world.projectile_get(pool_index, &"elapsed_ticks"))
	set(value):
		_world.projectile_set(pool_index, &"elapsed_ticks", value)
## Flight age limit in combat ticks (60 ticks/second), also used for the lob height.
## Positive values expire at this age; zero uses only remaining_lifetime and range.
var total_lifetime_ticks: int:
	get:
		return int(_world.projectile_get(pool_index, &"total_lifetime_ticks"))
	set(value):
		_world.projectile_set(pool_index, &"total_lifetime_ticks", value)
var return_after_ticks: int:
	get:
		return int(_world.projectile_get(pool_index, &"return_after_ticks"))
	set(value):
		_world.projectile_set(pool_index, &"return_after_ticks", value)
var return_phase_started: bool:
	get:
		return bool(_world.projectile_get(pool_index, &"return_phase_started"))
	set(value):
		_world.projectile_set(pool_index, &"return_phase_started", value)
var explosion_radius: float:
	get:
		return float(_world.projectile_get(pool_index, &"explosion_radius"))
	set(value):
		_world.projectile_set(pool_index, &"explosion_radius", value)
var stop_time_scale: float:
	get:
		return float(_world.projectile_get(pool_index, &"stop_time_scale"))
	set(value):
		_world.projectile_set(pool_index, &"stop_time_scale", value)
var expired_this_tick: bool:
	get:
		return bool(_world.projectile_get(pool_index, &"expired_this_tick"))
	set(value):
		_world.projectile_set(pool_index, &"expired_this_tick", value)


func visual_height() -> float:
	if movement_kind != MovementKind.ARC or total_lifetime_ticks <= 0:
		return BASE_VISUAL_HEIGHT
	var progress: float = clampf(
		elapsed_ticks / float(total_lifetime_ticks),
		0.0,
		1.0,
	)
	return (
		BASE_VISUAL_HEIGHT
		+ ARC_APEX_BONUS_HEIGHT * 4.0 * progress * (1.0 - progress)
	)


func mark_hit_enemy(entity_id: int) -> void:
	_world.projectile_mark_hit(pool_index, entity_id)
