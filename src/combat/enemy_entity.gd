class_name EnemyEntity
extends RefCounted


var entity_id: int = -1
var enemy_type: GameTypes.EnemyType = GameTypes.EnemyType.TRACKER
var definition: EnemyDefinition = null
var position: Vector2 = Vector2.ZERO
var hp: float = 0.0
var max_hp: float = 0.0
var damage_multiplier: float = 1.0
var born_physics_tick: int = 0
var contact_elapsed: float = 0.0
var special_elapsed: float = 0.0
var summon_elapsed: float = 0.0
var telegraph_elapsed: float = 0.0
var telegraph_active: bool = false
var telegraph_position: Vector2 = Vector2.ZERO
var barrage_alternate: bool = false
var alive: bool = true
var summoned_by_boss: bool = false


func body_radius() -> float:
	return definition.body_radius if definition != null else 0.0


func is_targetable(current_tick: int) -> bool:
	return alive and born_physics_tick < current_tick
