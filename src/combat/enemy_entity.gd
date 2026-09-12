class_name EnemyEntity
extends RefCounted

## A view of native storage; numeric state has one owner.
var _world: RefCounted


enum MovementKind {
	SEEK_PLAYER,
	FIXED_DIRECTION,
}


var pool_index: int = -1
var generation: int:
	get:
		return int(_world.enemy_get(pool_index, &"generation"))
	set(value):
		_world.enemy_set(pool_index, &"generation", value)
var entity_id: int:
	get:
		return int(_world.enemy_get(pool_index, &"entity_id"))
	set(value):
		_world.enemy_set(pool_index, &"entity_id", value)
var enemy_type: GameTypes.EnemyType:
	get:
		return int(_world.enemy_get(pool_index, &"enemy_type")) as GameTypes.EnemyType
	set(value):
		_world.enemy_set(pool_index, &"enemy_type", value)
var definition: EnemyDefinition = null
var position: Vector2:
	get:
		return _world.enemy_get(pool_index, &"position")
	set(value):
		_world.enemy_set(pool_index, &"position", value)
var hp: float:
	get:
		return float(_world.enemy_get(pool_index, &"hp"))
	set(value):
		_world.enemy_set(pool_index, &"hp", value)
var max_hp: float:
	get:
		return float(_world.enemy_get(pool_index, &"max_hp"))
	set(value):
		_world.enemy_set(pool_index, &"max_hp", value)
var damage_multiplier: float:
	get:
		return float(_world.enemy_get(pool_index, &"damage_multiplier"))
	set(value):
		_world.enemy_set(pool_index, &"damage_multiplier", value)
var born_tick: int:
	get:
		return int(_world.enemy_get(pool_index, &"born_tick"))
	set(value):
		_world.enemy_set(pool_index, &"born_tick", value)
var spawn_tick: int:
	get:
		return int(_world.enemy_get(pool_index, &"spawn_tick"))
	set(value):
		_world.enemy_set(pool_index, &"spawn_tick", value)
var activation_tick: int:
	get:
		return int(_world.enemy_get(pool_index, &"activation_tick"))
	set(value):
		_world.enemy_set(pool_index, &"activation_tick", value)
var special_elapsed_ticks: float:
	get:
		return float(_world.enemy_get(pool_index, &"special_elapsed_ticks"))
	set(value):
		_world.enemy_set(pool_index, &"special_elapsed_ticks", value)
var telegraph_elapsed_ticks: float:
	get:
		return float(_world.enemy_get(pool_index, &"telegraph_elapsed_ticks"))
	set(value):
		_world.enemy_set(pool_index, &"telegraph_elapsed_ticks", value)
var telegraph_active: bool:
	get:
		return bool(_world.enemy_get(pool_index, &"telegraph_active"))
	set(value):
		_world.enemy_set(pool_index, &"telegraph_active", value)
var telegraph_position: Vector2:
	get:
		return _world.enemy_get(pool_index, &"telegraph_position")
	set(value):
		_world.enemy_set(pool_index, &"telegraph_position", value)
var barrage_alternate: bool:
	get:
		return bool(_world.enemy_get(pool_index, &"barrage_alternate"))
	set(value):
		_world.enemy_set(pool_index, &"barrage_alternate", value)
var boss_charge_active: bool:
	get:
		return bool(_world.enemy_get(pool_index, &"boss_charge_active"))
	set(value):
		_world.enemy_set(pool_index, &"boss_charge_active", value)
var boss_charge_elapsed_ticks: float:
	get:
		return float(_world.enemy_get(pool_index, &"boss_charge_elapsed_ticks"))
	set(value):
		_world.enemy_set(pool_index, &"boss_charge_elapsed_ticks", value)
var boss_charge_interval_ticks: int:
	get:
		return int(_world.enemy_get(pool_index, &"boss_charge_interval_ticks"))
	set(value):
		_world.enemy_set(pool_index, &"boss_charge_interval_ticks", value)
var boss_charge_spoke_count: int:
	get:
		return int(_world.enemy_get(pool_index, &"boss_charge_spoke_count"))
	set(value):
		_world.enemy_set(pool_index, &"boss_charge_spoke_count", value)
var boss_charge_half_step: bool:
	get:
		return bool(_world.enemy_get(pool_index, &"boss_charge_half_step"))
	set(value):
		_world.enemy_set(pool_index, &"boss_charge_half_step", value)
var boss_action_age_ticks: float:
	get:
		return float(_world.enemy_get(pool_index, &"boss_action_age_ticks"))
	set(value):
		_world.enemy_set(pool_index, &"boss_action_age_ticks", value)
var hit_flash_until_tick: int:
	get:
		return int(_world.enemy_get(pool_index, &"hit_flash_until_tick"))
	set(value):
		_world.enemy_set(pool_index, &"hit_flash_until_tick", value)
var alive: bool:
	get:
		return bool(_world.enemy_get(pool_index, &"alive"))
	set(value):
		_world.enemy_set(pool_index, &"alive", value)
var elite_serial: int:
	get:
		return int(_world.enemy_get(pool_index, &"elite_serial"))
	set(value):
		_world.enemy_set(pool_index, &"elite_serial", value)
var boss_phase: int:
	get:
		return int(_world.enemy_get(pool_index, &"boss_phase"))
	set(value):
		_world.enemy_set(pool_index, &"boss_phase", value)
var rng: RandomNumberGenerator = null
var movement_kind: MovementKind:
	get:
		return int(_world.enemy_get(pool_index, &"movement_kind")) as MovementKind
	set(value):
		_world.enemy_set(pool_index, &"movement_kind", value)
var swarm_group_id: int:
	get:
		return int(_world.enemy_get(pool_index, &"swarm_group_id"))
	set(value):
		_world.enemy_set(pool_index, &"swarm_group_id", value)
var fixed_direction: Vector2:
	get:
		return _world.enemy_get(pool_index, &"fixed_direction")
	set(value):
		_world.enemy_set(pool_index, &"fixed_direction", value)
var remaining_travel_distance: float:
	get:
		return float(_world.enemy_get(pool_index, &"remaining_travel_distance"))
	set(value):
		_world.enemy_set(pool_index, &"remaining_travel_distance", value)
var swarm_red_variant: bool:
	get:
		return bool(_world.enemy_get(pool_index, &"swarm_red_variant"))
	set(value):
		_world.enemy_set(pool_index, &"swarm_red_variant", value)
var is_swarm_event: bool:
	get:
		return bool(_world.enemy_get(pool_index, &"is_swarm_event"))
	set(value):
		_world.enemy_set(pool_index, &"is_swarm_event", value)
var encounter_owner_id: int:
	get:
		return int(_world.enemy_get(pool_index, &"encounter_owner_id"))
	set(value):
		_world.enemy_set(pool_index, &"encounter_owner_id", value)


func body_radius() -> float:
	return definition.body_radius if definition != null else 0.0


func is_targetable(current_tick: int) -> bool:
	return alive and current_tick >= activation_tick


func is_materializing(current_tick: int) -> bool:
	return alive and current_tick < activation_tick


func materialization_progress(current_tick: int) -> float:
	var duration_ticks: int = activation_tick - spawn_tick
	if not alive:
		return 0.0
	if duration_ticks <= 0:
		return 1.0
	return clampf(
		float(current_tick - spawn_tick) / float(duration_ticks),
		0.0,
		1.0,
	)


func boss_charge_progress() -> float:
	if not boss_charge_active:
		return 0.0
	return clampf(
		boss_charge_elapsed_ticks / float(definition.telegraph_ticks),
		0.0,
		1.0,
	)


func is_hit_flashing(current_tick: int) -> bool:
	return alive and current_tick < hit_flash_until_tick


func configure_swarm_event(
	p_group_id: int,
	p_fixed_direction: Vector2,
	p_travel_distance: float,
	p_red_variant: bool,
) -> void:
	movement_kind = MovementKind.FIXED_DIRECTION
	swarm_group_id = p_group_id
	fixed_direction = p_fixed_direction.normalized()
	remaining_travel_distance = maxf(0.0, p_travel_distance)
	swarm_red_variant = p_red_variant
	is_swarm_event = true
