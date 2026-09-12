class_name XpPickupPool
extends RefCounted

## Native storage owns all numeric state. Slots are inspection/control views.
var world: RefCounted = CombatNative.create_world()
var slots: Array[XpPickupState] = []
var capacity: int = 0
var overflow_count: int:
	get:
		return int(world.pool_stats(2).overflow)
var reuse_count: int:
	get:
		return int(world.pool_stats(2).reused)


func _configure_storage(count: int, shared_world: RefCounted = null) -> void:
	if shared_world != null:
		world = shared_world
	if not world.configure_pool(2, count):
		push_error("Capacity cannot discard active native handles")
		return
	capacity = count
	var previous_size: int = slots.size()
	slots.resize(capacity)
	for index: int in range(capacity):
		if index >= previous_size or slots[index] == null or slots[index]._world != world:
			var slot := XpPickupState.new()
			slot.pool_index = index
			slot._world = world
			slots[index] = slot


func active_indices_snapshot() -> Array[int]:
	var result: Array[int] = []
	result.assign(world.pool_indices(2))
	return result


func active_count() -> int:
	return int(world.pool_stats(2).active)


func free_count() -> int:
	return int(world.pool_stats(2).free)


func reset_reuse_count() -> void:
	world.reset_reuse(2)


func orphan_count() -> int:
	return world.pool_orphans(2)


func clear() -> void:
	world.clear_pool(2)


func shift_origin(displacement: Vector2) -> void:
	world.shift_pool(2, displacement)


var attract_radius: float = 0.0
var collect_radius: float = 0.0
var attract_speed: float = 0.0
var overflow_merge_count: int:
	get:
		return int(world.pool_stats(2).overflow_merges)


func configure(balance: ProgressionBalanceDefinition, shared_world: RefCounted = null) -> void:
	_configure_storage(balance.xp_pool_capacity, shared_world)
	attract_radius = balance.xp_pickup_attract_radius
	collect_radius = balance.xp_pickup_collect_radius
	attract_speed = balance.xp_pickup_speed
	world.configure_xp(attract_radius, collect_radius, attract_speed)


func acquire(position: Vector2, value: int, born_tick: int, player_position: Vector2) -> XpPickupState:
	var index: int = world.spawn_xp(position, value, born_tick, player_position)
	return slots[index] if index >= 0 else null


func advance_and_collect(player_position: Vector2, delta: float, current_tick: int) -> int:
	return world.collect_xp(player_position, delta, current_tick)


func release(pool_index: int, generation: int = -1) -> bool:
	return world.release_xp(pool_index, generation)


func transforms() -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	result.assign(world.xp_transforms())
	return result


func visual_columns_by_slot() -> PackedVector3Array:
	return world.xp_columns()


func visual_slot_indices() -> PackedInt32Array:
	return PackedInt32Array(world.pool_indices(2))


static func visual_transform(pickup: XpPickupState) -> Transform3D:
	return pickup.visual_transform


func begin_vacuum() -> void:
	world.vacuum_xp()


func total_value() -> int:
	return world.xp_total_value()
