class_name EnemyStore
extends RefCounted


const CAPACITY: int = 768

var slots: Array[EnemyEntity] = []
var entities: Array[EnemyEntity] = []
var overflow_count: int = 0
var reuse_count: int = 0

var _free_indices: Array[int] = []
var _active_indices: Array[int] = []
var _active_position_by_pool_index: PackedInt32Array = PackedInt32Array()
var _dense_index_by_entity_id: Dictionary[int, int] = {}
var _pool_index_by_entity_id: Dictionary[int, int] = {}


func _init() -> void:
	slots.resize(CAPACITY)
	_active_position_by_pool_index.resize(CAPACITY)
	for pool_index: int in range(CAPACITY):
		var entity := EnemyEntity.new()
		entity.pool_index = pool_index
		entity.deactivate()
		slots[pool_index] = entity
		_active_position_by_pool_index[pool_index] = -1
	for pool_index: int in range(CAPACITY - 1, -1, -1):
		_free_indices.append(pool_index)


func try_spawn(
	state: RunState,
	enemy_type: GameTypes.EnemyType,
	definition: EnemyDefinition,
	position: Vector2,
	hp_multiplier: float,
	damage_multiplier: float,
	spawn_tick: int,
	entry_ticks: int = 0,
) -> EnemyEntity:
	if state == null or definition == null:
		return null
	if _free_indices.is_empty():
		overflow_count += 1
		return null
	var entity_id: int = state.allocate_entity_id()
	if _dense_index_by_entity_id.has(entity_id):
		return null
	var pool_index: int = _free_indices.pop_back()
	var entity: EnemyEntity = slots[pool_index]
	if entity.generation > 0:
		reuse_count += 1
	var entity_rng: RandomNumberGenerator = null
	if state.rng_streams != null:
		entity_rng = state.rng_streams.create_enemy_rng(entity_id)
	entity.activate(
		entity_id,
		enemy_type,
		definition,
		position,
		hp_multiplier,
		damage_multiplier,
		spawn_tick,
		entry_ticks,
		entity_rng,
	)
	var active_position: int = entities.size()
	_dense_index_by_entity_id[entity_id] = active_position
	_pool_index_by_entity_id[entity_id] = pool_index
	_active_position_by_pool_index[pool_index] = active_position
	_active_indices.append(pool_index)
	entities.append(entity)
	return entity


func remove(entity_id: int) -> bool:
	if not _dense_index_by_entity_id.has(entity_id):
		return false
	var dense_index: int = _dense_index_by_entity_id[entity_id]
	var pool_index: int = _pool_index_by_entity_id[entity_id]
	var last_index: int = entities.size() - 1
	var removed: EnemyEntity = entities[dense_index]
	if dense_index != last_index:
		var moved: EnemyEntity = entities[last_index]
		var moved_pool_index: int = _active_indices[last_index]
		entities[dense_index] = moved
		_active_indices[dense_index] = moved_pool_index
		_dense_index_by_entity_id[moved.entity_id] = dense_index
		_active_position_by_pool_index[moved_pool_index] = dense_index
	entities.pop_back()
	_active_indices.pop_back()
	_dense_index_by_entity_id.erase(entity_id)
	_pool_index_by_entity_id.erase(entity_id)
	_active_position_by_pool_index[pool_index] = -1
	removed.deactivate()
	_free_indices.append(pool_index)
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
	return _free_indices.size()


func active_indices_snapshot() -> Array[int]:
	return _active_indices.duplicate()


func reset_reuse_count() -> void:
	reuse_count = 0


func orphan_count() -> int:
	var invalid_count: int = 0
	if slots.size() != CAPACITY or _active_position_by_pool_index.size() != CAPACITY:
		return CAPACITY
	if _active_indices.size() + _free_indices.size() != CAPACITY:
		invalid_count += absi(
			_active_indices.size() + _free_indices.size() - CAPACITY
		)
	if entities.size() != _active_indices.size():
		invalid_count += absi(entities.size() - _active_indices.size())
	if (
		_dense_index_by_entity_id.size() != entities.size()
		or _pool_index_by_entity_id.size() != entities.size()
	):
		invalid_count += 1
	var seen := PackedByteArray()
	seen.resize(CAPACITY)
	seen.fill(0)
	for active_position: int in range(_active_indices.size()):
		var pool_index: int = _active_indices[active_position]
		if pool_index < 0 or pool_index >= CAPACITY:
			invalid_count += 1
			continue
		if seen[pool_index] != 0:
			invalid_count += 1
		seen[pool_index] = 1
		var entity: EnemyEntity = slots[pool_index]
		if (
			not entity.alive
			or entity.pool_index != pool_index
			or _active_position_by_pool_index[pool_index] != active_position
			or entities[active_position] != entity
			or int(_dense_index_by_entity_id.get(entity.entity_id, -1)) != active_position
			or int(_pool_index_by_entity_id.get(entity.entity_id, -1)) != pool_index
		):
			invalid_count += 1
	for pool_index: int in _free_indices:
		if pool_index < 0 or pool_index >= CAPACITY:
			invalid_count += 1
			continue
		if seen[pool_index] != 0:
			invalid_count += 1
		seen[pool_index] = 1
		if slots[pool_index].alive or _active_position_by_pool_index[pool_index] != -1:
			invalid_count += 1
	for pool_index: int in range(CAPACITY):
		if seen[pool_index] == 0:
			invalid_count += 1
	return invalid_count


func record_overflow() -> void:
	overflow_count += 1


func snapshot_ids_sorted() -> Array[int]:
	var entity_ids: Array[int] = []
	for entity_id: int in _dense_index_by_entity_id:
		entity_ids.append(entity_id)
	entity_ids.sort()
	return entity_ids


func clear() -> void:
	for pool_index: int in _active_indices:
		slots[pool_index].deactivate()
		_active_position_by_pool_index[pool_index] = -1
	entities.clear()
	_active_indices.clear()
	_dense_index_by_entity_id.clear()
	_pool_index_by_entity_id.clear()
	_free_indices.clear()
	for pool_index: int in range(CAPACITY - 1, -1, -1):
		_free_indices.append(pool_index)
