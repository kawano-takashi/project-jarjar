class_name ProjectilePool
extends RefCounted


const CAPACITY: int = 4096

var slots: Array[ProjectileState] = []
var overflow_count: int = 0
var reuse_count: int = 0

var _free_indices: Array[int] = []
var _active_indices: Array[int] = []
var _active_position_by_pool_index: PackedInt32Array = PackedInt32Array()


func _init() -> void:
	slots.resize(CAPACITY)
	_active_position_by_pool_index.resize(CAPACITY)
	for index: int in range(CAPACITY):
		var slot := ProjectileState.new()
		slot.pool_index = index
		slots[index] = slot
		_active_position_by_pool_index[index] = -1
	for index: int in range(CAPACITY - 1, -1, -1):
		_free_indices.append(index)


func acquire(
	faction: StringName,
	weapon_id: StringName,
	source_entity_id: int,
	position: Vector2,
	velocity: Vector2,
	radius: float,
	damage: float,
	remaining_distance: float,
	remaining_lifetime: float,
	target_position: Vector2,
	pierce_remaining: int,
	born_tick: int,
	source_effect_id: StringName = &"",
	movement_kind: ProjectileState.MovementKind = ProjectileState.MovementKind.STRAIGHT,
	target_entity_id: int = -1,
	total_lifetime_ticks: int = 0,
	return_after_ticks: int = 0,
	explosion_radius: float = 0.0,
	stop_time_scale: float = 0.0,
) -> ProjectileState:
	if _free_indices.is_empty():
		overflow_count += 1
		return null
	var pool_index: int = _free_indices.pop_back()
	var slot: ProjectileState = slots[pool_index]
	if slot.generation > 0:
		reuse_count += 1
	slot.generation += 1
	slot.activate(
		faction,
		weapon_id,
		source_entity_id,
		position,
		velocity,
		radius,
		damage,
		remaining_distance,
		remaining_lifetime,
		target_position,
		pierce_remaining,
		born_tick,
		source_effect_id,
		movement_kind,
		target_entity_id,
		total_lifetime_ticks,
		return_after_ticks,
		explosion_radius,
		stop_time_scale,
	)
	_active_position_by_pool_index[pool_index] = _active_indices.size()
	_active_indices.append(pool_index)
	return slot


func release(pool_index: int, generation: int = -1) -> bool:
	if pool_index < 0 or pool_index >= CAPACITY:
		return false
	var slot: ProjectileState = slots[pool_index]
	if not slot.active or (generation >= 0 and slot.generation != generation):
		return false
	slot.deactivate()
	var active_position: int = _active_position_by_pool_index[pool_index]
	if active_position < 0 or active_position >= _active_indices.size():
		return false
	var last_position: int = _active_indices.size() - 1
	if active_position != last_position:
		var moved_pool_index: int = _active_indices[last_position]
		_active_indices[active_position] = moved_pool_index
		_active_position_by_pool_index[moved_pool_index] = active_position
	_active_indices.pop_back()
	_active_position_by_pool_index[pool_index] = -1
	_free_indices.append(pool_index)
	return true


func snapshot_active() -> Array[Vector2i]:
	var snapshot: Array[Vector2i] = []
	snapshot.resize(_active_indices.size())
	for active_position: int in range(_active_indices.size()):
		var pool_index: int = _active_indices[active_position]
		var slot: ProjectileState = slots[pool_index]
		snapshot[active_position] = Vector2i(pool_index, slot.generation)
	return snapshot


func active_indices_snapshot() -> Array[int]:
	return _active_indices.duplicate()


func resolve_snapshot_entry(entry: Vector2i) -> ProjectileState:
	if entry.x < 0 or entry.x >= CAPACITY:
		return null
	var slot: ProjectileState = slots[entry.x]
	if not slot.active or slot.generation != entry.y:
		return null
	return slot


func active_count() -> int:
	return _active_indices.size()


func free_count() -> int:
	return _free_indices.size()


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
		if (
			not slots[pool_index].active
			or _active_position_by_pool_index[pool_index] != active_position
		):
			invalid_count += 1
	for pool_index: int in _free_indices:
		if pool_index < 0 or pool_index >= CAPACITY:
			invalid_count += 1
			continue
		if seen[pool_index] != 0:
			invalid_count += 1
		seen[pool_index] = 1
		if slots[pool_index].active or _active_position_by_pool_index[pool_index] != -1:
			invalid_count += 1
	for pool_index: int in range(CAPACITY):
		if seen[pool_index] == 0:
			invalid_count += 1
	return invalid_count


func clear() -> void:
	for pool_index: int in _active_indices:
		slots[pool_index].deactivate()
		_active_position_by_pool_index[pool_index] = -1
	_active_indices.clear()
	_free_indices.clear()
	for index: int in range(CAPACITY - 1, -1, -1):
		_free_indices.append(index)
