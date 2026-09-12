class_name EnemyStore
extends RefCounted

## Native storage owns all numeric state. Slots are inspection/control views.
var world: RefCounted = CombatNative.create_world()
var slots: Array[EnemyEntity] = []
var capacity: int = 0
var overflow_count: int:
	get:
		return int(world.pool_stats(0).overflow)
var reuse_count: int:
	get:
		return int(world.pool_stats(0).reused)


func _configure_storage(count: int, shared_world: RefCounted = null) -> void:
	if shared_world != null:
		world = shared_world
	if not world.configure_pool(0, count):
		push_error("Capacity cannot discard active native handles")
		return
	capacity = count
	var previous_size: int = slots.size()
	slots.resize(capacity)
	for index: int in range(capacity):
		if index >= previous_size or slots[index] == null or slots[index]._world != world:
			var slot := EnemyEntity.new()
			slot.pool_index = index
			slot._world = world
			slots[index] = slot


func active_indices_snapshot() -> Array[int]:
	var result: Array[int] = []
	result.assign(world.pool_indices(0))
	return result


func active_count() -> int:
	return int(world.pool_stats(0).active)


func free_count() -> int:
	return int(world.pool_stats(0).free)


func reset_reuse_count() -> void:
	world.reset_reuse(0)


func orphan_count() -> int:
	return world.pool_orphans(0)


func clear() -> void:
	world.clear_pool(0)


func shift_origin(displacement: Vector2) -> void:
	world.shift_pool(0, displacement)


var entities: Array[EnemyEntity]:
	get:
		var result: Array[EnemyEntity] = []
		for index: int in active_indices_snapshot():
			result.append(slots[index])
		return result


func configure(count: int, shared_world: RefCounted = null) -> void:
	_configure_storage(count, shared_world)


func try_spawn(state: RunState, enemy_type: GameTypes.EnemyType, definition: EnemyDefinition,
	position: Vector2, hp_multiplier: float, damage_multiplier: float, spawn_tick: int,
	entry_ticks: int = 0) -> EnemyEntity:
	if state == null or definition == null:
		return null
	if free_count() == 0:
		record_overflow()
		return null
	var entity_id: int = state.allocate_entity_id()
	var index: int = world.spawn_enemy({
		"entity_id": entity_id, "enemy_type": enemy_type, "position": position,
		"max_hp": definition.base_hp * hp_multiplier, "hp": definition.base_hp * hp_multiplier,
		"damage_multiplier": damage_multiplier, "born_tick": spawn_tick, "spawn_tick": spawn_tick,
		"activation_tick": spawn_tick + maxi(0, entry_ticks), "radius": definition.body_radius,
		"move_speed": definition.move_speed, "contact_damage": definition.contact_damage,
		"xp_value": definition.xp_value, "special_interval": definition.special_interval_ticks,
		"telegraph_ticks": definition.telegraph_ticks,
	})
	if index < 0:
		return null
	var entity: EnemyEntity = slots[index]
	entity.definition = definition
	entity.rng = state.rng_streams.create_enemy_rng(entity_id) if state.rng_streams != null else null
	return entity


func remove(entity_id: int) -> bool:
	return world.remove_enemy(entity_id)


func get_by_id(entity_id: int) -> EnemyEntity:
	var index: int = world.enemy_slot(entity_id)
	return slots[index] if index >= 0 else null


func has_entity(entity_id: int) -> bool:
	return world.enemy_slot(entity_id) >= 0


func record_overflow() -> void:
	world.record_enemy_overflow()


func snapshot_ids_sorted() -> Array[int]:
	var result: Array[int] = []
	result.assign(world.enemy_ids())
	return result
