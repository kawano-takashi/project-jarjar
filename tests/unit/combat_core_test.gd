extends RefCounted


func test_names() -> PackedStringArray:
	return PackedStringArray([
		"survival_pool_active_free_index_contract",
		"xp_pool_overflow_merges_without_loss",
		"forty_meter_grid_boundaries",
		"segment_tick_boundaries",
		"arena_nodes_hold_four_active_and_respawn",
		"all_weapon_behaviors_generate_attacks",
		"resonance_wave_sweeps_both_sides_and_amount_adds_damage",
		"arc_projectile_snapshot_follows_a_parabolic_lob",
		"homing_volley_focuses_nearest_and_retargets_residuals",
		"arc_projectile_explodes_once_on_first_impact",
		"arc_node_damage_uses_single_resolved_impact",
		"mass_projectile_requires_an_in_range_target",
		"directional_projectile_preserves_last_nonzero_move_direction",
		"returning_ring_reaches_nine_meters_and_hits_on_return",
		"orbital_outer_reach_is_monotonic_and_bounded",
		"infinite_homing_one_tick_cadence_stays_within_pool",
		"orbital_active_window_uses_duration_and_has_real_gaps",
		"evolutions_are_flagged_and_keep_their_base_lineage",
	])


func run_test(test_name: String, assertions: Variant, _context: Dictionary) -> void:
	match test_name:
		"survival_pool_active_free_index_contract":
			_test_pool_active_free_indices(assertions)
		"xp_pool_overflow_merges_without_loss":
			_test_xp_overflow_merge(assertions)
		"forty_meter_grid_boundaries":
			_test_grid_boundaries(assertions)
		"segment_tick_boundaries":
			_test_segment_boundaries(assertions)
		"arena_nodes_hold_four_active_and_respawn":
			_test_arena_node_respawn(assertions)
		"all_weapon_behaviors_generate_attacks":
			_test_all_weapon_behaviors(assertions)
		"resonance_wave_sweeps_both_sides_and_amount_adds_damage":
			_test_resonance_wave_amount(assertions)
		"arc_projectile_snapshot_follows_a_parabolic_lob":
			_test_arc_visual_lob(assertions)
		"homing_volley_focuses_nearest_and_retargets_residuals":
			_test_homing_focus_and_retarget(assertions)
		"arc_projectile_explodes_once_on_first_impact":
			_test_arc_impact_explosion(assertions)
		"arc_node_damage_uses_single_resolved_impact":
			_test_arc_node_impact_order(assertions)
		"mass_projectile_requires_an_in_range_target":
			_test_mass_range_gate(assertions)
		"directional_projectile_preserves_last_nonzero_move_direction":
			_test_directional_move_targeting(assertions)
		"returning_ring_reaches_nine_meters_and_hits_on_return":
			_test_returning_ring_rehit(assertions)
		"orbital_outer_reach_is_monotonic_and_bounded":
			_test_orbital_outer_reach(assertions)
		"infinite_homing_one_tick_cadence_stays_within_pool":
			_test_infinite_homing_pool(assertions)
		"orbital_active_window_uses_duration_and_has_real_gaps":
			_test_orbital_active_window(assertions)
		"evolutions_are_flagged_and_keep_their_base_lineage":
			_test_evolution_identity(assertions)
		_:
			assertions.expect_true(false, "registered survival combat core test")


func _test_pool_active_free_indices(assertions: Variant) -> void:
	var pool := ProjectilePool.new()
	var first: ProjectileState = _fixture_projectile(pool, Vector2.ZERO)
	var second: ProjectileState = _fixture_projectile(pool, Vector2.RIGHT)
	var third: ProjectileState = _fixture_projectile(pool, Vector2.DOWN)
	assertions.expect_equal(3, pool.active_count(), "three acquired projectile slots are active")
	assertions.expect_equal(ProjectilePool.CAPACITY - 3, pool.free_count(), "free count is constant-time active complement")
	var released_generation: int = second.generation
	assertions.expect_true(pool.release(second.pool_index, released_generation), "middle active slot releases by handle")
	assertions.expect_equal(2, pool.active_count(), "release removes one active index")
	assertions.expect_true(not pool.release(second.pool_index, released_generation), "stale generation cannot release a recycled slot")
	var recycled: ProjectileState = _fixture_projectile(pool, Vector2.LEFT)
	assertions.expect_equal(second.pool_index, recycled.pool_index, "free-index stack immediately reuses the released slot")
	assertions.expect_true(recycled.generation > released_generation, "recycled slot increments its generation")
	assertions.expect_equal(3, pool.snapshot_active().size(), "snapshot traverses active handles only")
	assertions.expect_true(first.active and third.active, "swap removal keeps neighboring slots active")

	var catalog: DefinitionCatalog = _catalog(assertions)
	if catalog == null:
		return
	var state: RunState = RunStateFactory.create(7001, catalog)
	var enemy_pool := EnemyStore.new()
	var enemy_definition: EnemyDefinition = catalog.enemy(&"pursuer")
	var first_enemy: EnemyEntity = enemy_pool.try_spawn(
		state,
		GameTypes.EnemyType.PURSUER,
		enemy_definition,
		Vector2.RIGHT,
		1.0,
		1.0,
		0,
	)
	var first_enemy_pool_index: int = first_enemy.pool_index
	var first_enemy_generation: int = first_enemy.generation
	assertions.expect_equal(1, enemy_pool.active_count(), "enemy pool tracks one dense active index")
	assertions.expect_equal(EnemyStore.CAPACITY - 1, enemy_pool.free_count(), "enemy pool consumes one preallocated free index")
	assertions.expect_true(enemy_pool.remove(first_enemy.entity_id), "enemy pool releases by stable entity ID")
	var recycled_enemy: EnemyEntity = enemy_pool.try_spawn(
		state,
		GameTypes.EnemyType.PURSUER,
		enemy_definition,
		Vector2.LEFT,
		1.0,
		1.0,
		1,
	)
	assertions.expect_equal(first_enemy_pool_index, recycled_enemy.pool_index, "enemy pool reuses the released free index")
	assertions.expect_true(recycled_enemy.generation > first_enemy_generation, "enemy pool generation advances on reuse")
	assertions.expect_equal(1, enemy_pool.active_indices_snapshot().size(), "enemy snapshot traverses active indices only")


func _test_xp_overflow_merge(assertions: Variant) -> void:
	var pool := XpPickupPool.new()
	for index: int in range(XpPickupPool.CAPACITY):
		pool.acquire(Vector2(float(index % 40), float(floori(float(index) / 40.0))), 1, 0, Vector2.ZERO)
	var total_before: int = pool.total_value()
	var merged: XpPickupState = pool.acquire(Vector2(19.0, 19.0), 17, 1, Vector2.ZERO)
	assertions.expect_true(merged != null, "overflow resolves to a far pickup")
	assertions.expect_equal(XpPickupPool.CAPACITY, pool.active_count(), "overflow does not exceed the 2048 crystal cap")
	assertions.expect_equal(total_before + 17, pool.total_value(), "overflow XP is merged without losing value")
	assertions.expect_equal(1, pool.overflow_merge_count, "overflow merge is observable")


func _test_grid_boundaries(assertions: Variant) -> void:
	var grid := UniformGrid.new()
	assertions.expect_equal(Vector2(-20.0, -20.0), UniformGrid.ARENA_MIN, "grid begins at the 40m arena corner")
	assertions.expect_equal(Vector2(20.0, 20.0), UniformGrid.ARENA_MAX, "grid ends at the 40m arena corner")
	assertions.expect_equal(Vector2i.ZERO, grid.cell_indices_for_position(Vector2(-100.0, -100.0)), "outside negative positions clamp to first cell")
	assertions.expect_equal(Vector2i(19, 19), grid.cell_indices_for_position(Vector2(100.0, 100.0)), "outside positive positions clamp to last cell")
	assertions.expect_equal(400, UniformGrid.CELL_COUNT, "2m cells cover the complete 40 by 40 arena")


func _test_segment_boundaries(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	if catalog == null:
		return
	var ticks: PackedInt32Array = PackedInt32Array([0, 3599, 3600, 35999, 36000])
	var expected: PackedInt32Array = PackedInt32Array([0, 0, 1, 9, 9])
	for index: int in range(ticks.size()):
		var segment: EnemySegmentDefinition = catalog.segment_for_tick(ticks[index])
		assertions.expect_equal(expected[index], segment.segment_index, "tick %d resolves the expected time-only segment" % ticks[index])


func _test_arena_node_respawn(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	if catalog == null:
		return
	var state: RunState = RunStateFactory.create(7201, catalog)
	var nodes := ArenaObjectSystem.new()
	nodes.initialize(state, catalog)
	assertions.expect_equal(4, nodes.active_node_count(), "four of eight geometric node sites begin active")
	var destroyed: int = nodes.damage_nodes_circle(
		ArenaObjectSystem.NODE_SITE_POSITIONS[0],
		1.0,
		ArenaObjectSystem.NODE_MAX_HP,
		1,
	)
	assertions.expect_equal(1, destroyed, "weapon damage destroys one arena node")
	assertions.expect_equal(3, nodes.active_node_count(), "destroyed node leaves three active during respawn delay")
	nodes.advance(catalog.manifest().node_respawn_ticks)
	assertions.expect_equal(3, nodes.active_node_count(), "node does not respawn one tick early")
	nodes.advance(catalog.manifest().node_respawn_ticks + 1)
	assertions.expect_equal(4, nodes.active_node_count(), "node respawns at an empty site after thirty seconds")


func _test_all_weapon_behaviors(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	if catalog == null:
		return
	var weapon_ids: Array[StringName] = catalog.basic_weapon_ids()
	weapon_ids.append_array(catalog.evolved_weapon_ids())
	for weapon_id: StringName in weapon_ids:
		var state: RunState = RunStateFactory.create(7000 + weapon_ids.find(weapon_id), catalog)
		state.weapons.clear()
		var definition: WeaponDefinition = catalog.weapon(weapon_id)
		var runtime := RunWeapon.create(
			weapon_id,
			definition.lineage_id,
			definition.is_evolved,
			state.rng_streams.create_weapon_rng(definition.lineage_id, 0),
		)
		runtime.level = definition.max_level
		state.weapons.append(runtime)
		var simulation := CombatSimulation.new()
		simulation.initialize(state, catalog)
		simulation.spawn_fixture_enemy(GameTypes.EnemyType.BULWARK, Vector2(2.0, 0.0), -1)
		var attacks: Array[Dictionary] = simulation.weapon_system.advance_and_fire(
			Vector2.ZERO,
			simulation.enemy_system.enemy_store,
			simulation.enemy_system.uniform_grid,
			1,
		)
		assertions.expect_equal(1, attacks.size(), "%s generates its mapped automatic attack" % weapon_id)


func _test_evolution_identity(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	if catalog == null:
		return
	for base_weapon_id: StringName in catalog.basic_weapon_ids():
		var mapping: EvolutionDefinition = catalog.evolution_for_weapon(base_weapon_id)
		var base: WeaponDefinition = catalog.weapon(base_weapon_id)
		var evolved: WeaponDefinition = catalog.weapon(mapping.evolved_weapon_id)
		assertions.expect_true(evolved.is_evolved, "%s evolution is flagged as evolved" % base_weapon_id)
		assertions.expect_equal(base.lineage_id, evolved.lineage_id, "%s evolution preserves damage lineage" % base_weapon_id)


func _test_resonance_wave_amount(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	if catalog == null:
		return
	var state: RunState = RunStateFactory.create(7301, catalog)
	state.weapons.clear()
	var definition: WeaponDefinition = catalog.weapon(&"resonance_wave")
	state.weapons.append(RunWeapon.create(
		definition.weapon_id,
		definition.lineage_id,
		false,
		state.rng_streams.create_weapon_rng(definition.lineage_id, 0),
	))
	var simulation := CombatSimulation.new()
	simulation.initialize(state, catalog)
	var right_enemy: EnemyEntity = simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.BULWARK,
		Vector2(1.5, 0.0),
		-1,
	)
	var left_enemy: EnemyEntity = simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.BULWARK,
		Vector2(-1.5, 0.0),
		-1,
	)
	var runtime: RunWeapon = state.weapon_for_lineage(&"resonance_wave")
	var level_one_attacks: Array[Dictionary] = simulation.weapon_system.advance_and_fire(
		Vector2.ZERO,
		simulation.enemy_system.enemy_store,
		simulation.enemy_system.uniform_grid,
		1,
	)
	var level_one_hits: Array[Dictionary] = []
	level_one_hits.assign(level_one_attacks[0].get("hits", []))
	assertions.expect_equal(1, _hit_count_for(level_one_hits, right_enemy.entity_id), "level one sweeps the right side once")
	assertions.expect_equal(1, _hit_count_for(level_one_hits, left_enemy.entity_id), "level one also sweeps the left side once")
	runtime.level = 2
	runtime.cooldown_remaining_ticks = 0
	var level_two_attacks: Array[Dictionary] = simulation.weapon_system.advance_and_fire(
		Vector2.ZERO,
		simulation.enemy_system.enemy_store,
		simulation.enemy_system.uniform_grid,
		2,
	)
	var level_two_hits: Array[Dictionary] = []
	level_two_hits.assign(level_two_attacks[0].get("hits", []))
	assertions.expect_equal(2, _hit_count_for(level_two_hits, right_enemy.entity_id), "the third wave adds a second real hit on its side")
	assertions.expect_equal(1, _hit_count_for(level_two_hits, left_enemy.entity_id), "the opposite sweep remains active")


func _test_arc_visual_lob(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	if catalog == null:
		return
	var state: RunState = RunStateFactory.create(7302, catalog)
	var simulation := CombatSimulation.new()
	simulation.initialize(state, catalog)
	var projectile: ProjectileState = simulation.projectile_pool.acquire(
		ProjectileState.FACTION_ALLY,
		&"arc_crystal",
		-1,
		Vector2.ZERO,
		Vector2.RIGHT,
		0.2,
		1.0,
		10.0,
		1.0,
		Vector2.RIGHT * 10.0,
		0,
		-1,
		&"arc_crystal",
		ProjectileState.MovementKind.ARC,
		-1,
		60,
	)
	var start_height: float = simulation.build_snapshot().projectile_transforms[0].origin.y
	projectile.elapsed_ticks = 30.0
	var midpoint_height: float = simulation.build_snapshot().projectile_transforms[0].origin.y
	projectile.elapsed_ticks = 60.0
	var landing_height: float = simulation.build_snapshot().projectile_transforms[0].origin.y
	assertions.expect_true(midpoint_height > start_height, "arc projectile rises above its launch height at midpoint")
	assertions.expect_float(start_height, landing_height, "arc projectile returns to launch height at landing")


func _test_homing_focus_and_retarget(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	if catalog == null:
		return
	var state: RunState = RunStateFactory.create(7304, catalog)
	state.weapons.clear()
	var definition: WeaponDefinition = catalog.weapon(&"homing_core")
	var runtime := RunWeapon.create(
		definition.weapon_id,
		definition.lineage_id,
		false,
		state.rng_streams.create_weapon_rng(definition.lineage_id, 0),
	)
	runtime.level = 2
	state.weapons.append(runtime)
	var simulation := CombatSimulation.new()
	simulation.initialize(state, catalog)
	var nearest: EnemyEntity = simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.BULWARK,
		Vector2(0.65, 0.0),
		-1,
	)
	nearest.max_hp = 1.0
	nearest.hp = nearest.max_hp
	var nearest_id: int = nearest.entity_id
	var residual_target: EnemyEntity = simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.BULWARK,
		Vector2(4.0, 1.0),
		-1,
	)
	assertions.expect_true(simulation.advance_tick(Vector2.ZERO), "production tick fires the homing volley")
	var entries: Array[Vector2i] = simulation.projectile_pool.snapshot_active()
	assertions.expect_equal(2, entries.size(), "level two homing volley creates two projectiles")
	for entry: Vector2i in entries:
		var projectile: ProjectileState = simulation.projectile_pool.resolve_snapshot_entry(entry)
		assertions.expect_equal(nearest_id, projectile.target_entity_id, "every homing projectile focuses the nearest target")
	assertions.expect_true(simulation.advance_tick(Vector2.ZERO), "production tick resolves the focused volley")
	assertions.expect_true(
		not simulation.enemy_system.enemy_store.has_entity(nearest_id),
		"the first homing projectile kills the low-HP nearest target",
	)
	var residual_entries: Array[Vector2i] = simulation.projectile_pool.snapshot_active()
	assertions.expect_equal(1, residual_entries.size(), "the same-tick residual projectile does not spend pierce on the dead target")
	if residual_entries.size() != 1:
		return
	var residual: ProjectileState = simulation.projectile_pool.resolve_snapshot_entry(
		residual_entries[0]
	)
	assertions.expect_equal(0, residual.pierce_remaining, "skipping a zero-HP collision preserves residual pierce")
	assertions.expect_true(simulation.advance_tick(Vector2.ZERO), "next production tick advances the residual projectile")
	residual = simulation.projectile_pool.resolve_snapshot_entry(residual_entries[0])
	assertions.expect_true(residual != null, "residual homing projectile remains active after retargeting")
	if residual != null:
		assertions.expect_equal(residual_target.entity_id, residual.target_entity_id, "residual homing projectile retargets the nearest living enemy on the next tick")


func _test_arc_impact_explosion(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	if catalog == null:
		return
	var state: RunState = RunStateFactory.create(7305, catalog)
	state.weapons.clear()
	var definition: WeaponDefinition = catalog.weapon(&"arc_crystal")
	state.weapons.append(RunWeapon.create(
		definition.weapon_id,
		definition.lineage_id,
		false,
		state.rng_streams.create_weapon_rng(definition.lineage_id, 0),
	))
	var simulation := CombatSimulation.new()
	simulation.initialize(state, catalog)
	var first_enemy: EnemyEntity = simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.BULWARK,
		Vector2(2.0, 0.0),
		-1,
	)
	var second_enemy: EnemyEntity = simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.BULWARK,
		Vector2(2.0, 0.75),
		-1,
	)
	simulation.weapon_system.advance_and_fire(
		Vector2.ZERO,
		simulation.enemy_system.enemy_store,
		simulation.enemy_system.uniform_grid,
		1,
	)
	var entries: Array[Vector2i] = simulation.projectile_pool.snapshot_active()
	assertions.expect_equal(1, entries.size(), "level one arc crystal creates one projectile")
	simulation.weapon_system.move_snapshot_projectiles(
		entries,
		simulation.enemy_system.enemy_store,
		Vector2.ZERO,
		2,
		false,
	)
	var records: Array[Dictionary] = simulation.weapon_system.resolve_ally_projectile(
		entries[0],
		simulation.enemy_system.enemy_store,
		simulation.enemy_system.uniform_grid,
		2,
	)
	assertions.expect_equal(1, _hit_count_for(records, first_enemy.entity_id), "first impact enemy receives one explosion hit")
	assertions.expect_equal(1, _hit_count_for(records, second_enemy.entity_id), "nearby enemy receives the same explosion once")
	assertions.expect_equal(0, simulation.projectile_pool.active_count(), "arc projectile is released after its single explosion")
	var repeated_records: Array[Dictionary] = simulation.weapon_system.resolve_ally_projectile(
		entries[0],
		simulation.enemy_system.enemy_store,
		simulation.enemy_system.uniform_grid,
		2,
	)
	assertions.expect_equal(0, repeated_records.size(), "released arc projectile cannot deal a double hit")


func _test_arc_node_impact_order(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	if catalog == null:
		return
	var node_position: Vector2 = ArenaObjectSystem.NODE_SITE_POSITIONS[4]

	var collision_simulation: CombatSimulation = _node_projectile_simulation(
		catalog,
		7351,
	)
	var collision_node: ArenaNodeState = collision_simulation.arena_object_system.nodes[4]
	var blocker: EnemyEntity = collision_simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.BULWARK,
		Vector2(8.0, node_position.y),
		-1,
	)
	blocker.max_hp = 1_000_000.0
	blocker.hp = blocker.max_hp
	_acquire_node_probe(
		collision_simulation,
		ProjectileState.MovementKind.ARC,
		Vector2(0.0, node_position.y),
		Vector2(900.0, 0.0),
		15.0,
		5.0,
		0.25,
	)
	assertions.expect_true(
		collision_simulation.advance_tick(Vector2.ZERO),
		"production tick resolves an arc collision",
	)
	assertions.expect_float(
		ArenaObjectSystem.NODE_MAX_HP,
		collision_node.hp,
		"arc flight through a later node deals no segment damage before enemy impact",
	)
	assertions.expect_true(blocker.hp < blocker.max_hp, "the earlier enemy receives the resolved arc explosion")
	assertions.expect_equal(0, collision_simulation.projectile_pool.active_count(), "enemy impact consumes the arc projectile")

	var impact_simulation: CombatSimulation = _node_projectile_simulation(
		catalog,
		7354,
	)
	var impact_node: ArenaNodeState = impact_simulation.arena_object_system.nodes[4]
	var impact_height: float = node_position.y - 0.7
	var impact_blocker: EnemyEntity = impact_simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.BULWARK,
		Vector2(node_position.x + 0.68, impact_height),
		-1,
	)
	impact_blocker.max_hp = 1_000_000.0
	impact_blocker.hp = impact_blocker.max_hp
	_acquire_node_probe(
		impact_simulation,
		ProjectileState.MovementKind.ARC,
		Vector2(0.0, impact_height),
		Vector2(900.0, 0.0),
		15.0,
		10.0,
		0.3,
	)
	assertions.expect_true(
		impact_simulation.advance_tick(Vector2.ZERO),
		"production tick resolves an arc impact beside a node",
	)
	assertions.expect_true(impact_node.active, "one enemy-impact explosion leaves the node active")
	assertions.expect_float(
		8.0,
		impact_node.hp,
		"enemy collision applies node AoE at the resolved impact rather than the flight segment",
	)
	assertions.expect_true(impact_blocker.hp < impact_blocker.max_hp, "impact fixture confirms the enemy collision occurred")

	var landing_simulation: CombatSimulation = _node_projectile_simulation(
		catalog,
		7352,
	)
	var landing_node: ArenaNodeState = landing_simulation.arena_object_system.nodes[4]
	_acquire_node_probe(
		landing_simulation,
		ProjectileState.MovementKind.ARC,
		Vector2(0.0, node_position.y),
		Vector2(780.0, 0.0),
		13.0,
		10.0,
		0.25,
	)
	assertions.expect_true(
		landing_simulation.advance_tick(Vector2.ZERO),
		"production tick resolves a natural arc landing",
	)
	assertions.expect_true(landing_node.active, "one arc impact does not destroy an eighteen-HP node")
	assertions.expect_float(
		8.0,
		landing_node.hp,
		"natural landing applies exactly one node explosion at the resolved impact",
	)
	assertions.expect_equal(0, landing_simulation.projectile_pool.active_count(), "natural landing consumes the arc projectile")

	var straight_simulation: CombatSimulation = _node_projectile_simulation(
		catalog,
		7353,
	)
	var straight_node: ArenaNodeState = straight_simulation.arena_object_system.nodes[4]
	_acquire_node_probe(
		straight_simulation,
		ProjectileState.MovementKind.STRAIGHT,
		Vector2(0.0, node_position.y),
		Vector2(900.0, 0.0),
		15.0,
		5.0,
		0.0,
	)
	assertions.expect_true(
		straight_simulation.advance_tick(Vector2.ZERO),
		"production tick resolves a straight projectile",
	)
	assertions.expect_float(
		13.0,
		straight_node.hp,
		"non-arc projectiles retain segment-based node damage",
	)
	assertions.expect_equal(0, straight_simulation.projectile_pool.active_count(), "expired straight projectile still recycles")


func _test_mass_range_gate(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	if catalog == null:
		return
	var state: RunState = RunStateFactory.create(7306, catalog)
	state.weapons.clear()
	var definition: WeaponDefinition = catalog.weapon(&"mass_projectile")
	var runtime := RunWeapon.create(
		definition.weapon_id,
		definition.lineage_id,
		false,
		state.rng_streams.create_weapon_rng(definition.lineage_id, 0),
	)
	state.weapons.append(runtime)
	var simulation := CombatSimulation.new()
	simulation.initialize(state, catalog)
	simulation.spawn_fixture_enemy(GameTypes.EnemyType.BULWARK, Vector2(24.0, 0.0), -1)
	var missed_attacks: Array[Dictionary] = simulation.weapon_system.advance_and_fire(
		Vector2.ZERO,
		simulation.enemy_system.enemy_store,
		simulation.enemy_system.uniform_grid,
		1,
	)
	assertions.expect_equal(0, missed_attacks.size(), "mass projectile does not fire at an out-of-range target")
	assertions.expect_equal(0, runtime.cooldown_remaining_ticks, "no eligible mass target consumes no cooldown")
	var near_enemy: EnemyEntity = simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.BULWARK,
		Vector2(10.0, 0.0),
		-1,
	)
	var attacks: Array[Dictionary] = simulation.weapon_system.advance_and_fire(
		Vector2.ZERO,
		simulation.enemy_system.enemy_store,
		simulation.enemy_system.uniform_grid,
		2,
	)
	assertions.expect_equal(1, attacks.size(), "mass projectile fires when an eligible target enters range")
	assertions.expect_equal(definition.cooldown_ticks_at(1), runtime.cooldown_remaining_ticks, "eligible mass shot starts its cooldown")
	var projectile: ProjectileState = simulation.projectile_pool.resolve_snapshot_entry(
		simulation.projectile_pool.snapshot_active()[0]
	)
	assertions.expect_equal(near_enemy.entity_id, projectile.target_entity_id, "mass projectile excludes the farther target")


func _test_directional_move_targeting(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	if catalog == null:
		return
	var state: RunState = RunStateFactory.create(7308, catalog)
	state.weapons.clear()
	var definition: WeaponDefinition = catalog.weapon(&"directional_needle")
	state.weapons.append(RunWeapon.create(
		definition.weapon_id,
		definition.lineage_id,
		false,
		state.rng_streams.create_weapon_rng(definition.lineage_id, 0),
	))
	var simulation := CombatSimulation.new()
	simulation.initialize(state, catalog)
	simulation.spawn_fixture_enemy(GameTypes.EnemyType.BULWARK, Vector2(2.0, 0.0), -1)
	simulation.weapon_system.update_move_direction(Vector2.UP)
	simulation.weapon_system.advance_and_fire(
		Vector2.ZERO,
		simulation.enemy_system.enemy_store,
		simulation.enemy_system.uniform_grid,
		1,
	)
	var projectile: ProjectileState = simulation.projectile_pool.resolve_snapshot_entry(
		simulation.projectile_pool.snapshot_active()[0]
	)
	assertions.expect_equal(Vector2.UP, projectile.velocity.normalized(), "directional needle follows the last nonzero move direction")


func _test_returning_ring_rehit(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	if catalog == null:
		return
	var state: RunState = RunStateFactory.create(7307, catalog)
	state.weapons.clear()
	var definition: WeaponDefinition = catalog.weapon(&"returning_ring")
	var runtime := RunWeapon.create(
		definition.weapon_id,
		definition.lineage_id,
		false,
		state.rng_streams.create_weapon_rng(definition.lineage_id, 0),
	)
	state.weapons.append(runtime)
	var outward_reach: float = (
		definition.projectile_speed_at(1)
		* float(definition.duration_ticks_at(1))
		/ float(RunState.TICKS_PER_SECOND)
		* 0.5
	)
	assertions.expect_true(outward_reach >= 9.0, "level one returning ring reaches at least nine meters outward")
	var simulation := CombatSimulation.new()
	simulation.initialize(state, catalog)
	var target: EnemyEntity = simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.BULWARK,
		Vector2(9.0, 0.0),
		-1,
	)
	simulation.weapon_system.advance_and_fire(
		Vector2.ZERO,
		simulation.enemy_system.enemy_store,
		simulation.enemy_system.uniform_grid,
		1,
	)
	var outward_hit_count: int = 0
	var return_hit_count: int = 0
	var moving_player_position := Vector2.ZERO
	var return_start_tick: int = floori(float(definition.duration_ticks_at(1)) / 2.0)
	for current_tick: int in range(2, definition.duration_ticks_at(1) + 4):
		if current_tick > return_start_tick:
			moving_player_position += Vector2(0.0, 0.04)
		var entries: Array[Vector2i] = simulation.projectile_pool.snapshot_active()
		simulation.weapon_system.move_snapshot_projectiles(
			entries,
			simulation.enemy_system.enemy_store,
			moving_player_position,
			current_tick,
			false,
		)
		for entry: Vector2i in entries:
			var projectile: ProjectileState = simulation.projectile_pool.resolve_snapshot_entry(entry)
			var returning: bool = projectile != null and projectile.return_phase_started
			var records: Array[Dictionary] = simulation.weapon_system.resolve_ally_projectile(
				entry,
				simulation.enemy_system.enemy_store,
				simulation.enemy_system.uniform_grid,
				current_tick,
			)
			var target_hit_count: int = _hit_count_for(records, target.entity_id)
			if returning:
				return_hit_count += target_hit_count
			else:
				outward_hit_count += target_hit_count
	assertions.expect_equal(1, outward_hit_count, "returning ring hits the target once on the outward phase")
	assertions.expect_equal(1, return_hit_count, "moving the player during return does not repeatedly clear the returning hit set")


func _test_orbital_outer_reach(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	if catalog == null:
		return
	var base: WeaponDefinition = catalog.weapon(&"orbital_array")
	var evolved: WeaponDefinition = catalog.weapon(&"eternal_orbit")
	var level_one_outer: float = _orbital_outer_reach(base.area_at(1))
	var level_eight_outer: float = _orbital_outer_reach(base.area_at(8))
	var evolved_outer: float = _orbital_outer_reach(evolved.area_at(1))
	assertions.expect_true(level_one_outer >= 1.8 and level_one_outer <= 2.4, "level one orbital outer reach stays in the approved band")
	assertions.expect_true(level_eight_outer >= 3.2 and level_eight_outer <= 3.8, "level eight orbital outer reach stays in the approved band")
	assertions.expect_true(evolved_outer >= 4.2 and evolved_outer <= 4.8, "evolved orbital outer reach stays in the approved band")
	assertions.expect_true(level_one_outer < level_eight_outer and level_eight_outer < evolved_outer, "orbital outer reach grows monotonically through evolution")


func _orbital_outer_reach(area: float) -> float:
	var orbit_radius: float = maxf(1.0, area)
	return orbit_radius + maxf(0.35, orbit_radius * WeaponSystem.ORBIT_HIT_RADIUS_MULTIPLIER)


func _test_infinite_homing_pool(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	if catalog == null:
		return
	var state: RunState = RunStateFactory.create(7303, catalog)
	state.weapons.clear()
	var definition: WeaponDefinition = catalog.weapon(&"infinite_homing")
	state.weapons.append(RunWeapon.create(
		definition.weapon_id,
		definition.lineage_id,
		true,
		state.rng_streams.create_weapon_rng(definition.lineage_id, 0),
	))
	var simulation := CombatSimulation.new()
	simulation.initialize(state, catalog)
	var target: EnemyEntity = simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.BOSS,
		Vector2(18.0, 18.0),
		-1,
	)
	target.max_hp = 1_000_000.0
	target.hp = target.max_hp
	var generated_count: int = 0
	for current_tick: int in range(1, 601):
		var entries: Array[Vector2i] = simulation.projectile_pool.snapshot_active()
		simulation.weapon_system.move_snapshot_projectiles(
			entries,
			simulation.enemy_system.enemy_store,
			Vector2.ZERO,
			current_tick,
			false,
		)
		for entry: Vector2i in entries:
			simulation.weapon_system.resolve_ally_projectile(
				entry,
				simulation.enemy_system.enemy_store,
				simulation.enemy_system.uniform_grid,
				current_tick,
			)
		generated_count += simulation.weapon_system.advance_and_fire(
			Vector2.ZERO,
			simulation.enemy_system.enemy_store,
			simulation.enemy_system.uniform_grid,
			current_tick,
		).size()
	assertions.expect_equal(600, generated_count, "infinite homing emits on every simulation tick")
	assertions.expect_equal(0, simulation.projectile_pool.overflow_count, "one-tick homing cadence does not overflow the projectile pool")
	assertions.expect_true(simulation.projectile_pool.active_count() < ProjectilePool.CAPACITY, "expired homing projectiles recycle active slots")


func _test_orbital_active_window(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	if catalog == null:
		return
	var base_setup: Dictionary = _orbital_fixture(catalog, &"orbital_array", 8, 0)
	var base_simulation: CombatSimulation = base_setup["simulation"]
	var base_runtime: RunWeapon = base_setup["runtime"]
	var base_definition: WeaponDefinition = catalog.weapon(&"orbital_array")
	var first_pulse: Array[Dictionary] = base_simulation.weapon_system.advance_and_fire(
		Vector2.ZERO,
		base_simulation.enemy_system.enemy_store,
		base_simulation.enemy_system.uniform_grid,
		1,
	)
	var base_duration: int = base_definition.duration_ticks_at(base_runtime.level)
	assertions.expect_equal(1 + base_duration, base_simulation.weapon_system.orbital_active_until_tick(&"orbital_array"), "base orbit duration establishes an exclusive active deadline")
	assertions.expect_equal(1, first_pulse.size(), "orbit activation produces its first damage pulse")
	assertions.expect_equal(5, base_simulation.weapon_system.orbital_transforms(Vector2.ZERO, base_duration).size(), "orbit visuals remain visible through the final active tick")
	var gap_tick: int = 1 + base_duration
	var gap_pulse: Array[Dictionary] = base_simulation.weapon_system.advance_and_fire(
		Vector2.ZERO,
		base_simulation.enemy_system.enemy_store,
		base_simulation.enemy_system.uniform_grid,
		gap_tick,
	)
	assertions.expect_equal(0, gap_pulse.size(), "base orbit deals no damage when its active window closes")
	assertions.expect_equal(0, base_simulation.weapon_system.orbital_transforms(Vector2.ZERO, gap_tick).size(), "base orbit visuals disappear during cooldown")
	var reactivation_tick: int = gap_tick + base_definition.cooldown_ticks_at(8)
	for current_tick: int in range(gap_tick + 1, reactivation_tick + 1):
		base_simulation.weapon_system.advance_and_fire(
			Vector2.ZERO,
			base_simulation.enemy_system.enemy_store,
			base_simulation.enemy_system.uniform_grid,
			current_tick,
		)
	assertions.expect_true(base_simulation.weapon_system.orbital_is_active(&"orbital_array", reactivation_tick), "base orbit reactivates only after a real cooldown gap")
	var passive_setup: Dictionary = _orbital_fixture(catalog, &"orbital_array", 8, 5)
	var passive_simulation: CombatSimulation = passive_setup["simulation"]
	passive_simulation.weapon_system.advance_and_fire(
		Vector2.ZERO,
		passive_simulation.enemy_system.enemy_store,
		passive_simulation.enemy_system.uniform_grid,
		1,
	)
	assertions.expect_equal(1 + roundi(float(base_duration) * 1.5), passive_simulation.weapon_system.orbital_active_until_tick(&"orbital_array"), "duration passive extends the actual orbit active window")
	var evolved_setup: Dictionary = _orbital_fixture(catalog, &"eternal_orbit", 1, 5)
	var evolved_simulation: CombatSimulation = evolved_setup["simulation"]
	evolved_simulation.weapon_system.advance_and_fire(
		Vector2.ZERO,
		evolved_simulation.enemy_system.enemy_store,
		evolved_simulation.enemy_system.uniform_grid,
		1,
	)
	assertions.expect_equal(-1, evolved_simulation.weapon_system.orbital_active_until_tick(&"orbital_array"), "eternal orbit uses no finite active deadline")
	assertions.expect_true(evolved_simulation.weapon_system.orbital_is_active(&"orbital_array", RunState.BOSS_START_TICK * 2), "eternal orbit has no gameplay or visual gap through an unlimited boss fight")
	assertions.expect_equal(8, evolved_simulation.weapon_system.orbital_transforms(Vector2.ZERO, RunState.BOSS_START_TICK * 2).size(), "eternal orbit continuously renders every evolved orb")
	var long_run_tick: int = 2_000_000
	var long_run_pulse: Array[Dictionary] = evolved_simulation.weapon_system.advance_and_fire(
		Vector2.ZERO,
		evolved_simulation.enemy_system.enemy_store,
		evolved_simulation.enemy_system.uniform_grid,
		long_run_tick,
	)
	assertions.expect_equal(1, long_run_pulse.size(), "eternal orbit still pulses after the former finite duration plus passive window")
	assertions.expect_true(evolved_simulation.weapon_system.orbital_is_active(&"orbital_array", long_run_tick), "eternal orbit remains strictly continuous at long-run ticks")
	assertions.expect_equal(8, evolved_simulation.weapon_system.orbital_transforms(Vector2.ZERO, long_run_tick).size(), "eternal orbit keeps rendering without a long-run gap")


func _orbital_fixture(
	catalog: DefinitionCatalog,
	weapon_id: StringName,
	level: int,
	duration_passive_level: int,
) -> Dictionary:
	var state: RunState = RunStateFactory.create(7390 + level + duration_passive_level, catalog)
	state.weapons.clear()
	var definition: WeaponDefinition = catalog.weapon(weapon_id)
	var runtime: RunWeapon = RunWeapon.create(
		definition.weapon_id,
		definition.lineage_id,
		definition.is_evolved,
		state.rng_streams.create_weapon_rng(definition.lineage_id, 0),
	)
	runtime.level = level
	state.weapons.append(runtime)
	if duration_passive_level > 0:
		var passive := RunPassive.create(&"duration_ring")
		passive.level = duration_passive_level
		state.passives.append(passive)
	var simulation := CombatSimulation.new()
	simulation.initialize(state, catalog)
	var enemy: EnemyEntity = simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.BULWARK,
		Vector2.RIGHT,
		-1,
	)
	enemy.max_hp = 1_000_000.0
	enemy.hp = enemy.max_hp
	return {"simulation": simulation, "runtime": runtime}


func _hit_count_for(records: Array[Dictionary], entity_id: int) -> int:
	var count: int = 0
	for record: Dictionary in records:
		if int(record.get("entity_id", -1)) == entity_id:
			count += 1
	return count


func _node_projectile_simulation(
	catalog: DefinitionCatalog,
	run_seed: int,
) -> CombatSimulation:
	var state: RunState = RunStateFactory.create(run_seed, catalog)
	state.spawn_credit = -100.0
	state.stop_until_tick = 100
	for runtime: RunWeapon in state.weapons:
		runtime.ready_on_resume = false
		runtime.cooldown_remaining_ticks = 10_000
	var simulation := CombatSimulation.new()
	simulation.initialize(state, catalog)
	return simulation


func _acquire_node_probe(
	simulation: CombatSimulation,
	movement_kind: ProjectileState.MovementKind,
	position: Vector2,
	velocity: Vector2,
	remaining_distance: float,
	damage: float,
	explosion_radius: float,
) -> ProjectileState:
	return simulation.projectile_pool.acquire(
		ProjectileState.FACTION_ALLY,
		&"arc_node_probe",
		-1,
		position,
		velocity,
		0.1,
		damage,
		remaining_distance,
		10.0,
		position + velocity.normalized() * remaining_distance,
		0,
		0,
		&"arc_crystal",
		movement_kind,
		-1,
		60,
		0,
		explosion_radius,
	)


func _fixture_projectile(pool: ProjectilePool, position: Vector2) -> ProjectileState:
	return pool.acquire(
		ProjectileState.FACTION_ALLY,
		&"fixture",
		-1,
		position,
		Vector2.RIGHT,
		0.1,
		1.0,
		10.0,
		10.0,
		position + Vector2.RIGHT * 10.0,
		0,
		0,
	)


func _catalog(assertions: Variant) -> DefinitionCatalog:
	var catalog := DefinitionCatalog.new()
	assertions.expect_true(catalog.load_and_validate(), "survival content catalog validates")
	return catalog if catalog.is_valid else null
