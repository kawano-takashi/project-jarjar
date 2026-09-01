class_name VfxPool
extends RefCounted


const CAPACITY: int = 4096

var slots: Array[VfxState] = []
var overflow_count: int = 0
var reuse_count: int = 0
var reduce_motion: bool = false
var reduce_flashes: bool = false

var _free_indices: Array[int] = []
var _active_indices: Array[int] = []
var _active_position_by_pool_index: PackedInt32Array = PackedInt32Array()


func _init() -> void:
	slots.resize(CAPACITY)
	_active_position_by_pool_index.resize(CAPACITY)
	for index: int in range(CAPACITY):
		var slot := VfxState.new()
		slot.pool_index = index
		slots[index] = slot
		_active_position_by_pool_index[index] = -1
	for index: int in range(CAPACITY - 1, -1, -1):
		_free_indices.append(index)


func acquire(
	position: Vector2,
	scale_m: float,
	lifetime: float,
	color: Color,
	born_tick: int,
) -> VfxState:
	return _acquire_state(
		position,
		scale_m,
		lifetime,
		color,
		born_tick,
		VfxState.EffectKind.GENERIC,
		Vector2.RIGHT,
		1.0,
	)


func _acquire_state(
	position: Vector2,
	scale_m: float,
	lifetime: float,
	color: Color,
	born_tick: int,
	effect_kind: VfxState.EffectKind,
	direction: Vector2,
	sweep_sign: float,
) -> VfxState:
	if _free_indices.is_empty():
		overflow_count += 1
		return null
	var pool_index: int = _free_indices.pop_back()
	var slot: VfxState = slots[pool_index]
	if slot.generation > 0:
		reuse_count += 1
	slot.generation += 1
	slot.activate(
		position,
		scale_m,
		lifetime,
		color,
		born_tick,
		effect_kind,
		direction,
		sweep_sign,
	)
	_active_position_by_pool_index[pool_index] = _active_indices.size()
	_active_indices.append(pool_index)
	return slot


func release(pool_index: int, generation: int = -1) -> bool:
	if pool_index < 0 or pool_index >= CAPACITY:
		return false
	var slot: VfxState = slots[pool_index]
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


func advance(delta: float, current_tick: int) -> void:
	var active_position: int = 0
	while active_position < _active_indices.size():
		var pool_index: int = _active_indices[active_position]
		var slot: VfxState = slots[pool_index]
		if slot.born_tick >= current_tick:
			active_position += 1
			continue
		slot.remaining_lifetime = maxf(0.0, slot.remaining_lifetime - delta)
		if slot.remaining_lifetime <= 0.0:
			release(pool_index, slot.generation)
		else:
			active_position += 1


func active_indices_snapshot() -> Array[int]:
	return _active_indices.duplicate()


func active_count() -> int:
	return _active_indices.size()


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
