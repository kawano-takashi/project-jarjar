class_name VfxPool
extends RefCounted


const CAPACITY: int = 4096
const MAX_PRODUCTION_REQUESTS_PER_TICK: int = 64
const LOW_PRIORITY_FREE_THRESHOLD: int = 128
const IMPORTANT_RESERVED_SLOTS: int = 32
const NORMAL_KILL_FREE_THRESHOLD: int = IMPORTANT_RESERVED_SLOTS

const PRIORITY_GENERIC: int = 0
const PRIORITY_ATTACK: int = 1
const PRIORITY_HIT: int = 2
const PRIORITY_KILL: int = 3
const PRIORITY_IMPORTANT: int = 4
const PRIORITY_TERMINAL: int = 5

var slots: Array[VfxState] = []
var overflow_count: int = 0
var reuse_count: int = 0
var reduce_motion: bool = false
var reduce_flashes: bool = false
var request_count: int = 0
var admitted_count: int = 0
var generic_drop_count: int = 0
var important_drop_count: int = 0

var _free_indices: Array[int] = []
var _active_indices: Array[int] = []
var _active_position_by_pool_index: PackedInt32Array = PackedInt32Array()
var _request_tick: int = -1
var _admitted_this_tick: int = 0
var _ordinary_admitted_this_tick: int = 0
var _next_request_serial: int = 1


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
		false,
		PRIORITY_GENERIC,
		0,
		true,
	)


func request(
	position: Vector2,
	scale_m: float,
	lifetime: float,
	color: Color,
	born_tick: int,
	priority: int = PRIORITY_GENERIC,
	effect_kind: VfxState.EffectKind = VfxState.EffectKind.GENERIC,
	direction: Vector2 = Vector2.RIGHT,
	sweep_sign: float = 1.0,
	evolved: bool = false,
) -> VfxState:
	_prepare_request_tick(born_tick)
	request_count += 1
	var important: bool = priority >= PRIORITY_IMPORTANT
	var ordinary_limit: int = (
		MAX_PRODUCTION_REQUESTS_PER_TICK - IMPORTANT_RESERVED_SLOTS
	)
	if not important and _ordinary_admitted_this_tick >= ordinary_limit:
		_record_request_drop(false)
		return null
	if _admitted_this_tick >= MAX_PRODUCTION_REQUESTS_PER_TICK:
		_record_request_drop(important)
		return null
	var free_slots: int = _free_indices.size()
	if priority <= PRIORITY_HIT and free_slots <= LOW_PRIORITY_FREE_THRESHOLD:
		_record_request_drop(false)
		return null
	if priority == PRIORITY_KILL and free_slots <= NORMAL_KILL_FREE_THRESHOLD:
		_record_request_drop(false)
		return null
	if free_slots <= 0 and important:
		_replace_oldest_lower_priority(priority)
	if _free_indices.is_empty():
		_record_request_drop(important)
		return null
	var serial: int = _next_request_serial
	_next_request_serial += 1
	var admitted: VfxState = _acquire_state(
		position,
		scale_m,
		lifetime,
		color,
		born_tick,
		effect_kind,
		direction,
		sweep_sign,
		evolved,
		priority,
		serial,
		false,
	)
	if admitted == null:
		_record_request_drop(important)
		return null
	_admitted_this_tick += 1
	if not important:
		_ordinary_admitted_this_tick += 1
	admitted_count += 1
	return admitted


func _acquire_state(
	position: Vector2,
	scale_m: float,
	lifetime: float,
	color: Color,
	born_tick: int,
	effect_kind: VfxState.EffectKind,
	direction: Vector2,
	sweep_sign: float,
	evolved: bool,
	priority: int,
	request_serial: int,
	record_overflow: bool,
) -> VfxState:
	if _free_indices.is_empty():
		if record_overflow:
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
		evolved,
		priority,
		request_serial,
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
	_request_tick = -1
	_admitted_this_tick = 0
	_ordinary_admitted_this_tick = 0


func _prepare_request_tick(current_tick: int) -> void:
	if _request_tick == current_tick:
		return
	_request_tick = current_tick
	_admitted_this_tick = 0
	_ordinary_admitted_this_tick = 0


func _record_request_drop(important: bool) -> void:
	if important:
		important_drop_count += 1
	else:
		generic_drop_count += 1


func _replace_oldest_lower_priority(incoming_priority: int) -> void:
	var candidate: VfxState = null
	for pool_index: int in _active_indices:
		var slot: VfxState = slots[pool_index]
		if slot.priority >= incoming_priority:
			continue
		if (
			candidate == null
			or slot.priority < candidate.priority
			or (
				slot.priority == candidate.priority
				and slot.request_serial < candidate.request_serial
			)
		):
			candidate = slot
	if candidate != null:
		release(candidate.pool_index, candidate.generation)


## Native death batches omit ordinary effects after the existing per-tick cap.
## Preserve request/drop telemetry without allocating every omitted effect.
func record_suppressed_requests(count: int, born_tick: int) -> void:
	if count <= 0:
		return
	_prepare_request_tick(born_tick)
	request_count += count
	generic_drop_count += count
