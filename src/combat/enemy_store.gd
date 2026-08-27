class_name EnemyStore
extends RefCounted


const CAPACITY: int = 768

var entities: Array[EnemyEntity] = []
var overflow_count: int = 0

var _dense_index_by_entity_id: Dictionary[int, int] = {}


func try_spawn(
	state: RunState,
	enemy_type: GameTypes.EnemyType,
	definition: EnemyDefinition,
	position: Vector2,
	hp_multiplier: float,
	damage_multiplier: float,
	born_tick: int,
	summoned_by_boss: bool = false,
) -> EnemyEntity:
	if state == null or definition == null:
		return null
	if entities.size() >= CAPACITY:
		overflow_count += 1
		return null
	var entity_id: int = state.next_entity_id
	if _dense_index_by_entity_id.has(entity_id):
		return null
	var entity := EnemyEntity.new()
	entity.entity_id = entity_id
	entity.enemy_type = enemy_type
	entity.definition = definition
	entity.position = position
	entity.max_hp = definition.base_hp * hp_multiplier
	entity.hp = entity.max_hp
	entity.damage_multiplier = damage_multiplier
	entity.born_physics_tick = born_tick
	entity.alive = true
	entity.summoned_by_boss = summoned_by_boss
	_dense_index_by_entity_id[entity_id] = entities.size()
	entities.append(entity)
	state.next_entity_id += 1
	return entity


func remove(entity_id: int) -> bool:
	if not _dense_index_by_entity_id.has(entity_id):
		return false
	var dense_index: int = _dense_index_by_entity_id[entity_id]
	var last_index: int = entities.size() - 1
	var removed: EnemyEntity = entities[dense_index]
	if dense_index != last_index:
		var moved: EnemyEntity = entities[last_index]
		entities[dense_index] = moved
		_dense_index_by_entity_id[moved.entity_id] = dense_index
	entities.pop_back()
	_dense_index_by_entity_id.erase(entity_id)
	removed.alive = false
	return true


func get_by_id(entity_id: int) -> EnemyEntity:
	if not _dense_index_by_entity_id.has(entity_id):
		return null
	return entities[_dense_index_by_entity_id[entity_id]]


func has_entity(entity_id: int) -> bool:
	return _dense_index_by_entity_id.has(entity_id)


func active_count() -> int:
	return entities.size()


func free_count() -> int:
	return CAPACITY - entities.size()


func record_overflow() -> void:
	overflow_count += 1


func snapshot_ids_sorted() -> Array[int]:
	var entity_ids: Array[int] = []
	for entity_id: int in _dense_index_by_entity_id:
		entity_ids.append(entity_id)
	entity_ids.sort()
	return entity_ids


func clear() -> void:
	for entity: EnemyEntity in entities:
		entity.alive = false
	entities.clear()
	_dense_index_by_entity_id.clear()
