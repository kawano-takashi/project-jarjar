class_name EnemyEntity
extends RefCounted


var pool_index: int = -1
var generation: int = 0
var entity_id: int = -1
var enemy_type: GameTypes.EnemyType = GameTypes.EnemyType.PURSUER
var definition: EnemyDefinition = null
var position: Vector2 = Vector2.ZERO
var hp: float = 0.0
var max_hp: float = 0.0
var damage_multiplier: float = 1.0
var born_tick: int = 0
var spawn_tick: int = 0
var activation_tick: int = 0
var contact_elapsed_ticks: float = 0.0
var special_elapsed_ticks: float = 0.0
var telegraph_elapsed_ticks: float = 0.0
var telegraph_active: bool = false
var telegraph_position: Vector2 = Vector2.ZERO
var barrage_alternate: bool = false
var boss_charge_active: bool = false
var boss_charge_elapsed_ticks: float = 0.0
var boss_charge_interval_ticks: int = 0
var boss_charge_spoke_count: int = 0
var boss_charge_half_step: bool = false
var boss_action_age_ticks: float = 0.0
var hit_flash_until_tick: int = -1
var alive: bool = true
var elite_serial: int = -1
var boss_phase: int = 0
var rng: RandomNumberGenerator = null


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
		boss_charge_elapsed_ticks / float(CombatEnvelope.BOSS_CHARGE_TICKS),
		0.0,
		1.0,
	)


func is_hit_flashing(current_tick: int) -> bool:
	return alive and current_tick < hit_flash_until_tick


func activate(
	p_entity_id: int,
	p_enemy_type: GameTypes.EnemyType,
	p_definition: EnemyDefinition,
	p_position: Vector2,
	hp_multiplier: float,
	p_damage_multiplier: float,
	p_spawn_tick: int,
	p_entry_ticks: int,
	p_rng: RandomNumberGenerator,
) -> void:
	generation += 1
	entity_id = p_entity_id
	enemy_type = p_enemy_type
	definition = p_definition
	position = p_position
	max_hp = p_definition.base_hp * hp_multiplier
	hp = max_hp
	damage_multiplier = p_damage_multiplier
	born_tick = p_spawn_tick
	spawn_tick = p_spawn_tick
	activation_tick = p_spawn_tick + maxi(0, p_entry_ticks)
	contact_elapsed_ticks = 0.0
	special_elapsed_ticks = 0.0
	telegraph_elapsed_ticks = 0.0
	telegraph_active = false
	telegraph_position = Vector2.ZERO
	barrage_alternate = false
	boss_charge_active = false
	boss_charge_elapsed_ticks = 0.0
	boss_charge_interval_ticks = 0
	boss_charge_spoke_count = 0
	boss_charge_half_step = false
	boss_action_age_ticks = 0.0
	hit_flash_until_tick = -1
	alive = true
	elite_serial = -1
	boss_phase = 0
	rng = p_rng


func deactivate() -> void:
	entity_id = -1
	enemy_type = GameTypes.EnemyType.PURSUER
	definition = null
	position = Vector2.ZERO
	hp = 0.0
	max_hp = 0.0
	damage_multiplier = 1.0
	born_tick = 0
	spawn_tick = 0
	activation_tick = 0
	contact_elapsed_ticks = 0.0
	special_elapsed_ticks = 0.0
	telegraph_elapsed_ticks = 0.0
	telegraph_active = false
	telegraph_position = Vector2.ZERO
	barrage_alternate = false
	boss_charge_active = false
	boss_charge_elapsed_ticks = 0.0
	boss_charge_interval_ticks = 0
	boss_charge_spoke_count = 0
	boss_charge_half_step = false
	boss_action_age_ticks = 0.0
	hit_flash_until_tick = -1
	alive = false
	elite_serial = -1
	boss_phase = 0
	rng = null
