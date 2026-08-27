class_name VfxPool
extends RefCounted


const CAPACITY: int = 4096

var slots: Array[VfxState] = []
var overflow_count: int = 0


func _init() -> void:
	slots.resize(CAPACITY)
	for index: int in range(CAPACITY):
		var slot := VfxState.new()
		slot.pool_index = index
		slots[index] = slot


func acquire(
	position: Vector2,
	scale_m: float,
	lifetime: float,
	color: Color,
	born_physics_tick: int,
) -> VfxState:
	for slot: VfxState in slots:
		if slot.active:
			continue
		slot.generation += 1
		slot.activate(position, scale_m, lifetime, color, born_physics_tick)
		return slot
	overflow_count += 1
	return null


func release(pool_index: int, generation: int = -1) -> bool:
	if pool_index < 0 or pool_index >= CAPACITY:
		return false
	var slot: VfxState = slots[pool_index]
	if not slot.active or (generation >= 0 and slot.generation != generation):
		return false
	slot.deactivate()
	return true


func advance(delta: float, current_tick: int) -> void:
	for slot: VfxState in slots:
		if not slot.active or slot.born_physics_tick >= current_tick:
			continue
		slot.remaining_lifetime = maxf(0.0, slot.remaining_lifetime - delta)
		if slot.remaining_lifetime <= 0.0:
			slot.deactivate()


func active_count() -> int:
	var count: int = 0
	for slot: VfxState in slots:
		if slot.active:
			count += 1
	return count


func clear() -> void:
	for slot: VfxState in slots:
		if slot.active:
			slot.deactivate()
