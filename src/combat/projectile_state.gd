class_name ProjectileState
extends RefCounted


const FACTION_ALLY: StringName = &"ally"
const FACTION_ENEMY: StringName = &"enemy"
const BASE_VISUAL_HEIGHT: float = 0.35
const ARC_APEX_BONUS_HEIGHT: float = 1.8

enum MovementKind { STRAIGHT, HOMING, ARC, RETURNING }

var pool_index: int = -1
var generation: int = 0
var active: bool = false
var faction: StringName = &""
var weapon_id: StringName = &""
var source_entity_id: int = -1
var position: Vector2 = Vector2.ZERO
var previous_position: Vector2 = Vector2.ZERO
var velocity: Vector2 = Vector2.ZERO
var radius: float = 0.0
var damage: float = 0.0
var remaining_distance: float = 0.0
var previous_remaining_distance: float = 0.0
var outbound_distance_remaining: float = 0.0
var remaining_lifetime: float = 0.0
var target_position: Vector2 = Vector2.ZERO
var pierce_remaining: int = 0
var born_tick: int = 0
var hit_entity_ids: Dictionary[int, bool] = {}
var hit_node_sites: Dictionary[int, bool] = {}
var source_effect_id: StringName = &""
var movement_kind: MovementKind = MovementKind.STRAIGHT
var target_entity_id: int = -1
var speed: float = 0.0
var elapsed_ticks: float = 0.0
var total_lifetime_ticks: int = 0
var return_after_ticks: int = 0
var return_phase_started: bool = false
var explosion_radius: float = 0.0
var stop_time_scale: float = 0.0
var expired_this_tick: bool = false


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


func activate(
	p_faction: StringName,
	p_weapon_id: StringName,
	p_source_entity_id: int,
	p_position: Vector2,
	p_velocity: Vector2,
	p_radius: float,
	p_damage: float,
	p_remaining_distance: float,
	p_remaining_lifetime: float,
	p_target_position: Vector2,
	p_pierce_remaining: int,
	p_born_tick: int,
	p_source_effect_id: StringName = &"",
	p_movement_kind: MovementKind = MovementKind.STRAIGHT,
	p_target_entity_id: int = -1,
	p_total_lifetime_ticks: int = 0,
	p_return_after_ticks: int = 0,
	p_explosion_radius: float = 0.0,
	p_stop_time_scale: float = 0.0,
) -> void:
	active = true
	faction = p_faction
	weapon_id = p_weapon_id
	source_entity_id = p_source_entity_id
	position = p_position
	previous_position = p_position
	velocity = p_velocity
	radius = p_radius
	damage = p_damage
	remaining_distance = p_remaining_distance
	previous_remaining_distance = p_remaining_distance
	outbound_distance_remaining = 0.0
	remaining_lifetime = p_remaining_lifetime
	target_position = p_target_position
	pierce_remaining = p_pierce_remaining
	born_tick = p_born_tick
	hit_entity_ids.clear()
	hit_node_sites.clear()
	source_effect_id = p_source_effect_id
	movement_kind = p_movement_kind
	target_entity_id = p_target_entity_id
	speed = p_velocity.length()
	elapsed_ticks = 0.0
	total_lifetime_ticks = p_total_lifetime_ticks
	return_after_ticks = p_return_after_ticks
	return_phase_started = false
	explosion_radius = maxf(0.0, p_explosion_radius)
	stop_time_scale = clampf(p_stop_time_scale, 0.0, 1.0)
	expired_this_tick = false


func deactivate() -> void:
	active = false
	faction = &""
	weapon_id = &""
	source_entity_id = -1
	position = Vector2.ZERO
	previous_position = Vector2.ZERO
	velocity = Vector2.ZERO
	radius = 0.0
	damage = 0.0
	remaining_distance = 0.0
	previous_remaining_distance = 0.0
	outbound_distance_remaining = 0.0
	remaining_lifetime = 0.0
	target_position = Vector2.ZERO
	pierce_remaining = 0
	born_tick = 0
	hit_entity_ids.clear()
	hit_node_sites.clear()
	source_effect_id = &""
	movement_kind = MovementKind.STRAIGHT
	target_entity_id = -1
	speed = 0.0
	elapsed_ticks = 0.0
	total_lifetime_ticks = 0
	return_after_ticks = 0
	return_phase_started = false
	explosion_radius = 0.0
	stop_time_scale = 0.0
	expired_this_tick = false
