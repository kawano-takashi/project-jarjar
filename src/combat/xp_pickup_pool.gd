class_name XpPickupPool
extends RefCounted



var slots: Array[XpPickupState] = []
var overflow_merge_count: int = 0
var reuse_count: int = 0
var capacity: int = 0
var attract_radius: float = 0
var collect_radius: float = 0
var attract_speed: float = 0

var _free_indices: Array[int] = []
var _active_indices: Array[int] = []
var _active_position_by_pool_index: PackedInt32Array = PackedInt32Array()





func configure(balance: ProgressionBalanceDefinition) -> void:
	attract_radius = balance.xp_pickup_attract_radius
	collect_radius = balance.xp_pickup_collect_radius
	attract_speed = balance.xp_pickup_speed
	if balance.xp_pool_capacity != capacity:
		capacity = balance.xp_pool_capacity
		_rebuild_storage()


func _rebuild_storage() -> void:
	slots.clear()
	_free_indices.clear()
	_active_indices.clear()
	_active_position_by_pool_index = PackedInt32Array()
	slots.resize(capacity)
	_active_position_by_pool_index.resize(capacity)
	for index: int in range(capacity):
		var slot := XpPickupState.new()
		slot.pool_index = index
		slots[index] = slot
		_active_position_by_pool_index[index] = -1
	for index: int in range(capacity - 1, -1, -1):
		_free_indices.append(index)
	overflow_merge_count = 0
	reuse_count = 0


func acquire(position: Vector2, value: int, born_tick: int, player_position: Vector2) -> XpPickupState:
	if value <= 0:
		return null
	if _free_indices.is_empty():
		var merge_target: XpPickupState = _farthest_from(player_position)
		if merge_target != null:
			merge_target.value += value
			overflow_merge_count += 1
		return merge_target
	var pool_index: int = _free_indices.pop_back()
	var pickup: XpPickupState = slots[pool_index]
	if pickup.generation > 0:
		reuse_count += 1
	pickup.generation += 1
	pickup.activate(position, value, born_tick)
	_active_position_by_pool_index[pool_index] = _active_indices.size()
	_active_indices.append(pool_index)
	return pickup


func advance_and_collect(
	player_position: Vector2,
	delta: float,
	current_tick: int,
	vacuum_active: bool = false,
) -> int:
	var collected_xp: int = 0
	var active_position: int = 0
	var attract_radius_squared: float = attract_radius * attract_radius
	var collect_radius_squared: float = collect_radius * collect_radius
	while active_position < _active_indices.size():
		var pool_index: int = _active_indices[active_position]
		var pickup: XpPickupState = slots[pool_index]
		if pickup.born_tick >= current_tick:
			active_position += 1
			continue
		var distance_squared: float = pickup.position.distance_squared_to(player_position)
		if vacuum_active or distance_squared <= attract_radius_squared:
			pickup.position = pickup.position.move_toward(
				player_position,
				attract_speed * maxf(0.0, delta),
			)
			distance_squared = pickup.position.distance_squared_to(player_position)
		if distance_squared <= collect_radius_squared:
			collected_xp += pickup.value
			release(pool_index, pickup.generation)
		else:
			active_position += 1
	return collected_xp


func release(pool_index: int, generation: int = -1) -> bool:
	if pool_index < 0 or pool_index >= capacity:
		return false
	var pickup: XpPickupState = slots[pool_index]
	if not pickup.active or (generation >= 0 and pickup.generation != generation):
		return false
	var active_position: int = _active_position_by_pool_index[pool_index]
	if active_position < 0 or active_position >= _active_indices.size():
		return false
	pickup.deactivate()
	var last_position: int = _active_indices.size() - 1
	if active_position != last_position:
		var moved_pool_index: int = _active_indices[last_position]
		_active_indices[active_position] = moved_pool_index
		_active_position_by_pool_index[moved_pool_index] = active_position
	_active_indices.pop_back()
	_active_position_by_pool_index[pool_index] = -1
	_free_indices.append(pool_index)
	return true


func transforms() -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	result.resize(_active_indices.size())
	for active_position: int in range(_active_indices.size()):
		var pickup: XpPickupState = slots[_active_indices[active_position]]
		result[active_position] = visual_transform(pickup)
	return result


static func visual_transform(pickup: XpPickupState) -> Transform3D:
	var value_scale: float = 1.0 + minf(1.0, log(float(maxi(1, pickup.value))) * 0.08)
	return Transform3D(
		Basis.IDENTITY.scaled(Vector3.ONE * value_scale),
		Vector3(pickup.position.x, 0.22, pickup.position.y),
	)


func active_count() -> int:
	return _active_indices.size()


func active_indices_snapshot() -> Array[int]:
	return _active_indices.duplicate()


func reset_reuse_count() -> void:
	reuse_count = 0


func orphan_count() -> int:
	var invalid_count: int = 0
	if slots.size() != capacity or _active_position_by_pool_index.size() != capacity:
		return capacity
	if _active_indices.size() + _free_indices.size() != capacity:
		invalid_count += absi(
			_active_indices.size() + _free_indices.size() - capacity
		)
	var seen := PackedByteArray()
	seen.resize(capacity)
	seen.fill(0)
	for active_position: int in range(_active_indices.size()):
		var pool_index: int = _active_indices[active_position]
		if pool_index < 0 or pool_index >= capacity:
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
		if pool_index < 0 or pool_index >= capacity:
			invalid_count += 1
			continue
		if seen[pool_index] != 0:
			invalid_count += 1
		seen[pool_index] = 1
		if slots[pool_index].active or _active_position_by_pool_index[pool_index] != -1:
			invalid_count += 1
	for pool_index: int in range(capacity):
		if seen[pool_index] == 0:
			invalid_count += 1
	return invalid_count


func total_value() -> int:
	var total: int = 0
	for pool_index: int in _active_indices:
		total += slots[pool_index].value
	return total


func clear() -> void:
	for pool_index: int in _active_indices:
		slots[pool_index].deactivate()
		_active_position_by_pool_index[pool_index] = -1
	_active_indices.clear()
	_free_indices.clear()
	for index: int in range(capacity - 1, -1, -1):
		_free_indices.append(index)
	overflow_merge_count = 0


func _farthest_from(player_position: Vector2) -> XpPickupState:
	var farthest: XpPickupState = null
	var farthest_distance_squared: float = -1.0
	for pool_index: int in _active_indices:
		var pickup: XpPickupState = slots[pool_index]
		var distance_squared: float = pickup.position.distance_squared_to(player_position)
		if distance_squared > farthest_distance_squared:
			farthest = pickup
			farthest_distance_squared = distance_squared
	return farthest
