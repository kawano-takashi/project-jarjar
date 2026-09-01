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
var contact_elapsed_ticks: float = 0.0
var special_elapsed_ticks: float = 0.0
var summon_elapsed_ticks: float = 0.0
var telegraph_elapsed_ticks: float = 0.0
var telegraph_active: bool = false
var telegraph_position: Vector2 = Vector2.ZERO
var barrage_alternate: bool = false
var alive: bool = true
var summoned_by_boss: bool = false
var elite_serial: int = -1
var boss_phase: int = 0
var rng: RandomNumberGenerator = null


func body_radius() -> float:
	return definition.body_radius if definition != null else 0.0


func is_targetable(current_tick: int) -> bool:
	return alive and born_tick < current_tick


func activate(
	p_entity_id: int,
	p_enemy_type: GameTypes.EnemyType,
	p_definition: EnemyDefinition,
	p_position: Vector2,
	hp_multiplier: float,
	p_damage_multiplier: float,
	p_born_tick: int,
	p_summoned_by_boss: bool,
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
	born_tick = p_born_tick
	contact_elapsed_ticks = 0.0
	special_elapsed_ticks = 0.0
	summon_elapsed_ticks = 0.0
	telegraph_elapsed_ticks = 0.0
	telegraph_active = false
	telegraph_position = Vector2.ZERO
	barrage_alternate = false
	alive = true
	summoned_by_boss = p_summoned_by_boss
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
	contact_elapsed_ticks = 0.0
	special_elapsed_ticks = 0.0
	summon_elapsed_ticks = 0.0
	telegraph_elapsed_ticks = 0.0
	telegraph_active = false
	telegraph_position = Vector2.ZERO
	barrage_alternate = false
	alive = false
	summoned_by_boss = false
	elite_serial = -1
	boss_phase = 0
	rng = null
