class_name ProjectilePool
extends RefCounted

## Native storage owns all numeric state. Slots are inspection/control views.
var world: RefCounted = CombatNative.create_world()
var slots: Array[ProjectileState] = []
var capacity: int = 0
var overflow_count: int:
	get:
		return int(world.pool_stats(1).overflow)
var reuse_count: int:
	get:
		return int(world.pool_stats(1).reused)


func _configure_storage(count: int, shared_world: RefCounted = null) -> void:
	if shared_world != null:
		world = shared_world
	if not world.configure_pool(1, count):
		push_error("Capacity cannot discard active native handles")
		return
	capacity = count
	var previous_size: int = slots.size()
	slots.resize(capacity)
	for index: int in range(capacity):
		if index >= previous_size or slots[index] == null or slots[index]._world != world:
			var slot := ProjectileState.new()
			slot.pool_index = index
			slot._world = world
			slots[index] = slot


func active_indices_snapshot() -> Array[int]:
	var result: Array[int] = []
	result.assign(world.pool_indices(1))
	return result


func active_count() -> int:
	return int(world.pool_stats(1).active)


func free_count() -> int:
	return int(world.pool_stats(1).free)


func reset_reuse_count() -> void:
	world.reset_reuse(1)


func orphan_count() -> int:
	return world.pool_orphans(1)


func clear() -> void:
	world.clear_pool(1)


func shift_origin(displacement: Vector2) -> void:
	world.shift_pool(1, displacement)


func configure(count: int, shared_world: RefCounted = null) -> void:
	_configure_storage(count, shared_world)


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
	var index: int = world.spawn_projectile({
		"faction": faction, "weapon_id": weapon_id, "source_entity_id": source_entity_id,
		"position": position, "previous_position": position, "velocity": velocity,
		"radius": radius, "damage": damage, "remaining_distance": remaining_distance,
		"previous_remaining_distance": remaining_distance, "remaining_lifetime": remaining_lifetime,
		"target_position": target_position, "pierce_remaining": pierce_remaining, "born_tick": born_tick,
		"source_effect_id": source_effect_id, "movement_kind": movement_kind,
		"target_entity_id": target_entity_id, "speed": velocity.length(),
		"total_lifetime_ticks": total_lifetime_ticks, "return_after_ticks": return_after_ticks,
		"explosion_radius": maxf(0.0, explosion_radius), "stop_time_scale": clampf(stop_time_scale, 0.0, 1.0),
	})
	return slots[index] if index >= 0 else null


func release(pool_index: int, generation: int = -1) -> bool:
	return world.release_projectile(pool_index, generation)


## Independent tick-start pairs: [slot, generation, ...], with 64-bit values.
func snapshot_active() -> PackedInt64Array:
	return world.projectile_handles()


func resolve_snapshot_entry(entry: PackedInt64Array) -> ProjectileState:
	if entry.size() != 2 or entry[1] <= 0:
		return null
	return slots[entry[0]] if world.projectile_valid(entry[0], entry[1]) else null
