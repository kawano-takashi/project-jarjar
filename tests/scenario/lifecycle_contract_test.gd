extends RefCounted


const DELTA: float = 1.0 / 60.0


class TraceRng:
	extends RefCounted

	var float_values: Array[float] = []
	var range_values: Array[float] = []

	func randf() -> float:
		return float_values.pop_front() if not float_values.is_empty() else 0.99

	func randf_range(minimum: float, maximum: float) -> float:
		var unit_value: float = range_values.pop_front() if not range_values.is_empty() else 0.0
		return lerpf(minimum, maximum, unit_value)

	func randi_range(minimum: int, _maximum: int) -> int:
		return minimum


func test_names() -> PackedStringArray:
	return PackedStringArray([
		"projectile_stale_generation_resolver_contract",
		"boss_summon_full_born_tick_lifecycle_contract",
		"enemy_and_ally_projectile_born_tick_contract",
		"vfx_pool_lifecycle_and_overflow_contract",
		"multimesh_only_runtime_entity_contract",
	])


func run_test(test_name: String, assertions: Variant, context: Dictionary) -> void:
	match test_name:
		"projectile_stale_generation_resolver_contract":
			_test_projectile_stale_generation_resolver(assertions)
		"boss_summon_full_born_tick_lifecycle_contract":
			_test_boss_summon_full_born_tick_lifecycle(assertions)
		"enemy_and_ally_projectile_born_tick_contract":
			_test_enemy_and_ally_projectile_born_tick(assertions)
		"vfx_pool_lifecycle_and_overflow_contract":
			_test_vfx_pool_lifecycle_and_overflow(assertions)
		"multimesh_only_runtime_entity_contract":
			await _test_multimesh_only_runtime_entities(assertions, context)
		_:
			assertions.expect_true(false, "registered combat lifecycle test")


func _test_projectile_stale_generation_resolver(assertions: Variant) -> void:
	var simulation: CombatSimulation = _new_simulation(1)
	var target: EnemyEntity = simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.TRACKER,
		Vector2(0.7, 0.0),
	)
	_acquire_projectile(simulation.projectile_pool, Vector2(-10.0, 0.0), Vector2.ZERO, 10)
	_acquire_projectile(simulation.projectile_pool, Vector2(-9.0, 0.0), Vector2.ZERO, 10)
	var original: ProjectileState = _acquire_projectile(
		simulation.projectile_pool,
		Vector2.ZERO,
		Vector2(120.0, 0.0),
		10,
	)
	assertions.expect_equal(2, original.pool_index, "stale fixture starts at minimum free index 2")
	var original_generation: int = original.generation
	var old_entry := Vector2i(original.pool_index, original_generation)
	var old_snapshot: Array[Vector2i] = [old_entry]
	assertions.expect_true(
		simulation.projectile_pool.release(original.pool_index, original_generation),
		"old generation released during tick",
	)
	var replacement: ProjectileState = _acquire_projectile(
		simulation.projectile_pool,
		Vector2.ZERO,
		Vector2(120.0, 0.0),
		10,
	)
	assertions.expect_equal(2, replacement.pool_index, "same index is immediately reused")
	assertions.expect_equal(
		original_generation + 1,
		replacement.generation,
		"same-tick replacement increments generation",
	)

	var replacement_entry := Vector2i(replacement.pool_index, replacement.generation)
	var start_position: Vector2 = replacement.position
	# Process the stale entry after the born tick too, so generation—not the born guard—rejects it.
	simulation.weapon_system.move_snapshot_projectiles(old_snapshot, DELTA, 11)
	var stale_hits: Array[Dictionary] = simulation.weapon_system.resolve_ally_projectile(
		old_entry,
		simulation.enemy_system.enemy_store,
		simulation.enemy_system.uniform_grid,
		11,
	)
	assertions.expect_equal(start_position, replacement.position, "old generation cannot move replacement")
	assertions.expect_equal(0, stale_hits.size(), "old generation produces no hit on replacement")
	assertions.expect_true(replacement.active, "old generation cannot release replacement")
	assertions.expect_false(
		replacement.hit_entity_ids.has(target.entity_id),
		"old generation cannot mark replacement target history",
	)

	var fresh_snapshot: Array[Vector2i] = [replacement_entry]
	simulation.weapon_system.move_snapshot_projectiles(fresh_snapshot, DELTA, 11)
	assertions.expect_true(replacement.position.x > start_position.x, "new generation moves next tick")
	var fresh_hits: Array[Dictionary] = simulation.weapon_system.resolve_ally_projectile(
		replacement_entry,
		simulation.enemy_system.enemy_store,
		simulation.enemy_system.uniform_grid,
		11,
	)
	assertions.expect_equal(1, fresh_hits.size(), "new generation hits only from next tick")
	if not fresh_hits.is_empty():
		assertions.expect_equal(
			target.entity_id,
			int(fresh_hits[0].get("entity_id", -1)),
			"new generation resolver hits the intended target",
		)
	assertions.expect_false(replacement.active, "resolved bow generation releases after hit")


func _test_boss_summon_full_born_tick_lifecycle(assertions: Variant) -> void:
	var rng := TraceRng.new()
	rng.range_values = [0.0]
	rng.float_values = [0.99, 0.99, 0.99]
	var simulation: CombatSimulation = _new_simulation(8, rng)
	simulation.state.physics_tick = 359
	simulation.state.non_boss_spawned = 296
	var boss: EnemyEntity = _first_enemy_of_type(
		simulation.enemy_system.enemy_store,
		GameTypes.EnemyType.BOSS,
	)
	assertions.expect_true(boss != null, "W8 boss exists for summon lifecycle")
	if boss == null:
		return
	boss.summon_elapsed = boss.definition.summon_interval
	var tick_start_ids: Array[int] = simulation.enemy_system.snapshot_ids()
	var summoned: Array[EnemyEntity] = simulation.enemy_system.resolve_ready_boss_summons(
		tick_start_ids,
		Vector2.ZERO,
		360,
	)
	assertions.expect_equal(3, summoned.size(), "boss creates exactly the three remaining non-boss slots")
	if summoned.size() != 3:
		return
	assertions.expect_equal(
		summoned[0].entity_id + 1,
		summoned[1].entity_id,
		"summoned entity ids are consecutive first",
	)
	assertions.expect_equal(
		summoned[1].entity_id + 1,
		summoned[2].entity_id,
		"summoned entity ids are consecutive second",
	)

	var fixture_positions: Array[Vector2] = [
		Vector2(3.0, 0.0),
		Vector2(0.2, 0.0),
		Vector2(1.5, 0.0),
	]
	var summoned_ids: Array[int] = []
	for index: int in range(summoned.size()):
		var enemy: EnemyEntity = summoned[index]
		summoned_ids.append(enemy.entity_id)
		enemy.position = fixture_positions[index]
		assertions.expect_equal(360, enemy.born_physics_tick, "summon records current born tick")
		assertions.expect_equal(GameTypes.EnemyType.TRACKER, enemy.enemy_type, "injected type roll selects TRACKER")

	simulation.enemy_system.advance_snapshot(summoned_ids, Vector2.ZERO, DELTA, 360)
	for index: int in range(summoned.size()):
		assertions.expect_equal(
			fixture_positions[index],
			summoned[index].position,
			"summoned enemy %d does not move on born tick" % index,
		)
		assertions.expect_float(
			0.0,
			summoned[index].contact_elapsed,
			"summoned enemy %d timer does not advance on born tick" % index,
		)
		summoned[index].contact_elapsed = summoned[index].definition.contact_interval

	var born_contact: Array[Dictionary] = simulation.enemy_system.resolve_ready_enemy_damage_actions(
		summoned_ids,
		Vector2.ZERO,
		360,
	)
	assertions.expect_equal(0, born_contact.size(), "summoned enemies cannot contact on born tick")
	simulation.weapon_system.attack_elapsed = simulation.weapon_system.effective_interval()
	var projectiles_before_targeting: int = simulation.projectile_pool.active_count()
	var born_primary: Array[Dictionary] = simulation.weapon_system.try_primary_attack(
		Vector2.ZERO,
		simulation.enemy_system.enemy_store,
		simulation.enemy_system.uniform_grid,
		360,
	)
	assertions.expect_equal(0, born_primary.size(), "born summons are excluded from auto-target selection")
	assertions.expect_equal(
		projectiles_before_targeting,
		simulation.projectile_pool.active_count(),
		"born summons generate no primary attack",
	)

	simulation.enemy_system.advance_snapshot(summoned_ids, Vector2.ZERO, DELTA, 361)
	for index: int in range(summoned.size()):
		assertions.expect_true(summoned[index].is_targetable(361), "summoned enemy targetable next tick")
		assertions.expect_false(
			summoned[index].position == fixture_positions[index],
			"summoned enemy %d moves from next tick" % index,
		)
	var next_contact: Array[Dictionary] = simulation.enemy_system.resolve_ready_enemy_damage_actions(
		summoned_ids,
		Vector2.ZERO,
		361,
	)
	assertions.expect_equal(1, next_contact.size(), "overlapping summon contacts from next tick")
	if not next_contact.is_empty():
		assertions.expect_equal(
			summoned[1].entity_id,
			int(next_contact[0].get("source_entity_id", -1)),
			"only the overlapping summon resolves contact",
		)
	simulation.weapon_system.attack_elapsed = simulation.weapon_system.effective_interval()
	var next_primary: Array[Dictionary] = simulation.weapon_system.try_primary_attack(
		Vector2.ZERO,
		simulation.enemy_system.enemy_store,
		simulation.enemy_system.uniform_grid,
		361,
	)
	assertions.expect_equal(1, next_primary.size(), "summon participates in auto-attack next tick")
	if not next_primary.is_empty():
		assertions.expect_equal(
			summoned[1].entity_id,
			int(next_primary[0].get("entity_id", -1)),
			"auto-target selects nearest summoned entity",
		)


func _test_enemy_and_ally_projectile_born_tick(assertions: Variant) -> void:
	var enemy_simulation: CombatSimulation = _new_simulation(1)
	var ranged: EnemyEntity = enemy_simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.RANGED,
		Vector2(0.7, 0.0),
	)
	ranged.special_elapsed = ranged.definition.special_interval
	var enemy_tick_start: Array[Vector2i] = enemy_simulation.projectile_pool.snapshot_active()
	enemy_simulation.enemy_system.resolve_ready_enemy_special_actions(
		[ranged.entity_id],
		Vector2.ZERO,
		10,
		enemy_simulation.projectile_pool,
	)
	assertions.expect_equal(0, enemy_tick_start.size(), "enemy bullet absent from tick-start snapshot")
	var enemy_bullet: ProjectileState = _first_active_projectile(
		enemy_simulation.projectile_pool,
		ProjectileState.FACTION_ENEMY,
	)
	assertions.expect_true(enemy_bullet != null, "RANGED generates enemy bullet")
	if enemy_bullet != null:
		var enemy_entry := Vector2i(enemy_bullet.pool_index, enemy_bullet.generation)
		var forced_enemy_snapshot: Array[Vector2i] = [enemy_entry]
		var enemy_start: Vector2 = enemy_bullet.position
		enemy_simulation.weapon_system.move_snapshot_projectiles(forced_enemy_snapshot, DELTA, 10)
		var born_enemy_hits: Array[Dictionary] = enemy_simulation.weapon_system.resolve_enemy_projectiles(
			forced_enemy_snapshot,
			Vector2.ZERO,
			10,
		)
		assertions.expect_equal(enemy_start, enemy_bullet.position, "enemy bullet does not move on born tick")
		assertions.expect_equal(0, born_enemy_hits.size(), "enemy bullet cannot hit on born tick")
		assertions.expect_true(enemy_bullet.active, "enemy bullet remains pooled through born tick")
		enemy_simulation.weapon_system.move_snapshot_projectiles(forced_enemy_snapshot, DELTA, 11)
		assertions.expect_false(enemy_bullet.position == enemy_start, "enemy bullet moves next tick")
		var next_enemy_hits: Array[Dictionary] = enemy_simulation.weapon_system.resolve_enemy_projectiles(
			forced_enemy_snapshot,
			Vector2.ZERO,
			11,
		)
		assertions.expect_equal(1, next_enemy_hits.size(), "enemy bullet hits from next tick")
		assertions.expect_false(enemy_bullet.active, "enemy bullet releases after next-tick hit")

	var ally_simulation: CombatSimulation = _new_weapon_simulation(GameTypes.MainWeaponType.BOW)
	var ally_target: EnemyEntity = ally_simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.TRACKER,
		Vector2(0.7, 0.0),
	)
	var ally_tick_start: Array[Vector2i] = ally_simulation.projectile_pool.snapshot_active()
	ally_simulation.weapon_system.attack_elapsed = ally_simulation.weapon_system.effective_interval()
	ally_simulation.weapon_system.try_primary_attack(
		Vector2.ZERO,
		ally_simulation.enemy_system.enemy_store,
		ally_simulation.enemy_system.uniform_grid,
		20,
	)
	assertions.expect_equal(0, ally_tick_start.size(), "ally bullet absent from tick-start snapshot")
	var ally_bullet: ProjectileState = _first_active_projectile(
		ally_simulation.projectile_pool,
		ProjectileState.FACTION_ALLY,
	)
	assertions.expect_true(ally_bullet != null, "bow generates ally bullet")
	if ally_bullet != null:
		var ally_entry := Vector2i(ally_bullet.pool_index, ally_bullet.generation)
		var forced_ally_snapshot: Array[Vector2i] = [ally_entry]
		var ally_start: Vector2 = ally_bullet.position
		ally_simulation.weapon_system.move_snapshot_projectiles(forced_ally_snapshot, DELTA, 20)
		var born_ally_hits: Array[Dictionary] = ally_simulation.weapon_system.resolve_ally_projectile(
			ally_entry,
			ally_simulation.enemy_system.enemy_store,
			ally_simulation.enemy_system.uniform_grid,
			20,
		)
		assertions.expect_equal(ally_start, ally_bullet.position, "ally bullet does not move on born tick")
		assertions.expect_equal(0, born_ally_hits.size(), "ally bullet cannot hit on born tick")
		assertions.expect_true(ally_bullet.active, "ally bullet remains pooled through born tick")
		ally_simulation.weapon_system.move_snapshot_projectiles(forced_ally_snapshot, DELTA, 21)
		assertions.expect_false(ally_bullet.position == ally_start, "ally bullet moves next tick")
		var next_ally_hits: Array[Dictionary] = ally_simulation.weapon_system.resolve_ally_projectile(
			ally_entry,
			ally_simulation.enemy_system.enemy_store,
			ally_simulation.enemy_system.uniform_grid,
			21,
		)
		assertions.expect_equal(1, next_ally_hits.size(), "ally bullet hits from next tick")
		if not next_ally_hits.is_empty():
			assertions.expect_equal(
				ally_target.entity_id,
				int(next_ally_hits[0].get("entity_id", -1)),
				"next-tick ally hit resolves intended target",
			)
		assertions.expect_false(ally_bullet.active, "ally bullet releases after next-tick hit")


func _test_vfx_pool_lifecycle_and_overflow(assertions: Variant) -> void:
	var order_pool := VfxPool.new()
	assertions.expect_equal(4096, VfxPool.CAPACITY, "VFX pool fixed capacity")
	assertions.expect_equal(VfxPool.CAPACITY, order_pool.slots.size(), "VFX pool allocates every fixed slot")
	var free_indices: Array[int] = [2, 7, 9]
	for index: int in range(VfxPool.CAPACITY):
		order_pool.slots[index].active = not (index in free_indices)
	var first: VfxState = order_pool.acquire(Vector2.ZERO, 1.0, 1.0, Color.WHITE, 10)
	var second: VfxState = order_pool.acquire(Vector2.RIGHT, 1.0, 1.0, Color.WHITE, 10)
	var third: VfxState = order_pool.acquire(Vector2.UP, 1.0, 1.0, Color.WHITE, 10)
	assertions.expect_equal(2, first.pool_index, "VFX acquires minimum free index 2")
	assertions.expect_equal(7, second.pool_index, "VFX acquires next free index 7")
	assertions.expect_equal(9, third.pool_index, "VFX acquires next free index 9")
	assertions.expect_equal(null, order_pool.acquire(Vector2.ZERO, 1.0, 1.0, Color.WHITE, 10), "full VFX pool denies acquire")
	assertions.expect_equal(1, order_pool.overflow_count, "full VFX pool increments overflow counter")
	var first_generation: int = first.generation
	assertions.expect_true(order_pool.release(2, first_generation), "VFX generation releases exact slot")
	var replacement: VfxState = order_pool.acquire(Vector2.ZERO, 1.0, 1.0, Color.WHITE, 10)
	assertions.expect_equal(2, replacement.pool_index, "VFX reuses released minimum index")
	assertions.expect_equal(first_generation + 1, replacement.generation, "VFX generation increments on reuse")
	assertions.expect_false(order_pool.release(2, first_generation), "stale VFX generation cannot release replacement")
	assertions.expect_true(order_pool.release(2, replacement.generation), "current VFX generation releases replacement")

	var lifetime_pool := VfxPool.new()
	var lifetime_vfx: VfxState = lifetime_pool.acquire(Vector2.ZERO, 1.0, 1.0, Color.WHITE, 10)
	lifetime_pool.advance(0.25, 10)
	assertions.expect_true(lifetime_vfx.active, "VFX remains active on born tick")
	assertions.expect_float(1.0, lifetime_vfx.remaining_lifetime, "VFX lifetime does not advance on born tick")
	lifetime_pool.advance(0.25, 11)
	assertions.expect_float(0.75, lifetime_vfx.remaining_lifetime, "VFX lifetime advances next tick")
	lifetime_pool.advance(0.75, 12)
	assertions.expect_false(lifetime_vfx.active, "short-lived VFX returns to pool at expiry")


func _test_multimesh_only_runtime_entities(assertions: Variant, context: Dictionary) -> void:
	var simulation: CombatSimulation = _new_simulation(1)
	for index: int in range(64):
		simulation.spawn_fixture_enemy(
			GameTypes.EnemyType.TRACKER,
			Vector2(float(index % 8) - 3.5, float(index) / 8.0 - 3.5),
		)
		_acquire_projectile(
			simulation.projectile_pool,
			Vector2(float(index % 8), float(index) / 8.0),
			Vector2.ZERO,
			0,
		)
	for index: int in range(8):
		simulation.add_fixture_vfx(Vector2(float(index), 0.0), 1.0, Color.WHITE)

	var enemy_node_count: int = 0
	for enemy: EnemyEntity in simulation.enemy_system.enemy_store.entities:
		var enemy_value: Variant = enemy
		if enemy_value is Node:
			enemy_node_count += 1
	assertions.expect_equal(0, enemy_node_count, "logical enemies contain no Node instances")
	var projectile_node_count: int = 0
	for projectile: ProjectileState in simulation.projectile_pool.slots:
		if projectile.active:
			var projectile_value: Variant = projectile
			if projectile_value is Node:
				projectile_node_count += 1
	assertions.expect_equal(0, projectile_node_count, "logical projectiles contain no Node instances")

	var packed := ResourceLoader.load("res://scenes/gameplay/arena_combat.tscn") as PackedScene
	assertions.expect_true(packed != null, "pooled arena scene loads")
	if packed == null:
		return
	var arena := packed.instantiate() as ArenaPresenter
	var scene_node_count: int = _count_nodes(arena)
	var scene_node3d_count: int = _count_descendant_node3d(arena)
	assertions.expect_equal(13, scene_node3d_count, "arena has only fixed pooled/static Node3D descendants")
	arena.initialize(simulation)
	arena.set_simulation_paused(true)
	var tree: SceneTree = context["tree"] as SceneTree
	tree.root.add_child(arena)
	await tree.process_frame
	assertions.expect_equal(scene_node_count, _count_nodes(arena), "runtime entities add no Node of any name")
	assertions.expect_equal(13, _count_descendant_node3d(arena), "runtime entities add no Node3D of any name")
	assertions.expect_equal(4, _count_descendant_type(arena, MultiMeshInstance3D), "arena uses four pooled MultiMesh renderers after chest display is added")
	assertions.expect_equal(6, _count_descendant_type(arena, MeshInstance3D), "arena retains only six static MeshInstance3D nodes")
	var enemy_instances := arena.get_node("EnemyInstances") as MultiMeshInstance3D
	var projectile_instances := arena.get_node("ProjectileInstances") as MultiMeshInstance3D
	var vfx_instances := arena.get_node("VfxInstances") as MultiMeshInstance3D
	var chest_instances := arena.get_node("ChestInstances") as MultiMeshInstance3D
	assertions.expect_equal(64, enemy_instances.multimesh.visible_instance_count, "64 logical enemies render in one MultiMesh")
	assertions.expect_equal(64, projectile_instances.multimesh.visible_instance_count, "64 logical projectiles render in one MultiMesh")
	assertions.expect_equal(8, vfx_instances.multimesh.visible_instance_count, "8 logical VFX render in one MultiMesh")
	assertions.expect_equal(0, chest_instances.multimesh.visible_instance_count, "no chest fixture renders before acquisition")
	tree.root.remove_child(arena)
	arena.free()



func _catalog() -> DefinitionCatalog:
	var catalog := DefinitionCatalog.new()
	catalog.load_and_validate()
	return catalog


func _new_simulation(wave_number: int, rng_source: Variant = null) -> CombatSimulation:
	var catalog: DefinitionCatalog = _catalog()
	var state: RunState = RunStateFactory.create(20260827, catalog.wave(wave_number))
	state.wave_number = wave_number
	state.time_remaining = catalog.wave(wave_number).duration_seconds
	var simulation := CombatSimulation.new()
	simulation.initialize(state, catalog, rng_source)
	return simulation


func _new_weapon_simulation(weapon_type: GameTypes.MainWeaponType) -> CombatSimulation:
	var catalog: DefinitionCatalog = _catalog()
	var state: RunState = RunStateFactory.create(20260827, catalog.wave(1))
	var weapon := ItemInstance.new()
	weapon.item_id = "lifecycle-weapon"
	weapon.slot = GameTypes.EquipmentSlot.MAIN_WEAPON
	weapon.main_weapon_type = weapon_type
	weapon.rarity = GameTypes.Rarity.COMMON
	weapon.display_name = String(GameTypes.main_weapon_type_to_key(weapon_type))
	state.equipped[GameTypes.EquipmentSlot.MAIN_WEAPON] = weapon
	var simulation := CombatSimulation.new()
	simulation.initialize(state, catalog)
	return simulation


func _acquire_projectile(
	pool: ProjectilePool,
	position: Vector2,
	velocity: Vector2,
	born_tick: int,
) -> ProjectileState:
	return pool.acquire(
		ProjectileState.FACTION_ALLY,
		&"bow",
		-1,
		position,
		velocity,
		0.2,
		12.0,
		14.0,
		1.0,
		position + Vector2.RIGHT * 14.0,
		1,
		born_tick,
	)


func _first_active_projectile(pool: ProjectilePool, faction: StringName) -> ProjectileState:
	for projectile: ProjectileState in pool.slots:
		if projectile.active and projectile.faction == faction:
			return projectile
	return null


func _first_enemy_of_type(store: EnemyStore, enemy_type: GameTypes.EnemyType) -> EnemyEntity:
	for enemy: EnemyEntity in store.entities:
		if enemy.enemy_type == enemy_type:
			return enemy
	return null


func _count_nodes(root: Node) -> int:
	var count: int = 1
	for child: Node in root.get_children():
		count += _count_nodes(child)
	return count


func _count_descendant_node3d(root: Node) -> int:
	var count: int = 0
	for child: Node in root.get_children():
		if child is Node3D:
			count += 1
		count += _count_descendant_node3d(child)
	return count


func _count_descendant_type(root: Node, type: Variant) -> int:
	var count: int = 0
	for child: Node in root.get_children():
		if is_instance_of(child, type):
			count += 1
		count += _count_descendant_type(child, type)
	return count
