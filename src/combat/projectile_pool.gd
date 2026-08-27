class_name ProjectilePool
extends RefCounted


const CAPACITY: int = 4096

var slots: Array[ProjectileState] = []
var overflow_count: int = 0


func _init() -> void:
	slots.resize(CAPACITY)
	for index: int in range(CAPACITY):
		var slot := ProjectileState.new()
		slot.pool_index = index
		slots[index] = slot


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
	born_physics_tick: int,
) -> ProjectileState:
	for slot: ProjectileState in slots:
		if slot.active:
			continue
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
			born_physics_tick,
		)
		return slot
	overflow_count += 1
	return null


func release(pool_index: int, generation: int = -1) -> bool:
	if pool_index < 0 or pool_index >= CAPACITY:
		return false
	var slot: ProjectileState = slots[pool_index]
	if not slot.active or (generation >= 0 and slot.generation != generation):
		return false
	slot.deactivate()
	return true


func snapshot_active() -> Array[Vector2i]:
	var snapshot: Array[Vector2i] = []
	for slot: ProjectileState in slots:
		if slot.active:
			snapshot.append(Vector2i(slot.pool_index, slot.generation))
	return snapshot


func resolve_snapshot_entry(entry: Vector2i) -> ProjectileState:
	if entry.x < 0 or entry.x >= CAPACITY:
		return null
	var slot: ProjectileState = slots[entry.x]
	if not slot.active or slot.generation != entry.y:
		return null
	return slot


func active_count() -> int:
	var count: int = 0
	for slot: ProjectileState in slots:
		if slot.active:
			count += 1
	return count


func free_count() -> int:
	return CAPACITY - active_count()


func clear() -> void:
	for slot: ProjectileState in slots:
		if slot.active:
			slot.deactivate()
