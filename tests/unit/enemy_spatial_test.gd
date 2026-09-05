extends RefCounted


func test_names() -> PackedStringArray:
	return PackedStringArray([
		"combat_envelope_and_exterior_grid",
		"enemy_entry_contract_and_pool_default",
		"player_relative_spawn_frame_is_translation_invariant",
		"outside_entry_and_normal_far_despawn_contracts",
		"boss_charge_cadence_and_latches",
	])


func run_test(test_name: String, assertions: Variant, _context: Dictionary) -> void:
	match test_name:
		"combat_envelope_and_exterior_grid":
			_test_envelope_and_grid(assertions)
		"enemy_entry_contract_and_pool_default":
			_test_entry_contract(assertions)
		"player_relative_spawn_frame_is_translation_invariant":
			_test_spawn_contracts(assertions)
		"outside_entry_and_normal_far_despawn_contracts":
			_test_outside_entry_and_far_despawn(assertions)
		"boss_charge_cadence_and_latches":
			_test_boss_charge(assertions)
		_:
			assertions.expect_true(false, "registered enemy-spatial test")


func _test_envelope_and_grid(assertions: Variant) -> void:
	var grid := BalanceTestFixtures.grid()
	assertions.expect_equal(Vector2(-16.0, -16.0), grid.arena_min, "grid begins at the thirty-two-meter arena corner")
	assertions.expect_equal(Vector2(16.0, 16.0), grid.arena_max, "grid ends at the thirty-two-meter arena corner")
	assertions.expect_equal(Vector2i(15, 15), grid.cell_indices_for_position(Vector2(100.0, 100.0)), "positive overflow clamps to the final cell")
	assertions.expect_equal(256, grid.cell_count, "two-meter cells cover the complete thirty-two-meter arena")
	grid.insert(41, Vector2(18.0, 0.0))
	assertions.expect_equal(
		[41],
		grid.query_circle_candidates(Vector2(18.0, 0.0), 0.1, 0.0),
		"a wholly exterior query reaches the clamped boundary cell",
	)
	for site_position: Vector2 in BalanceTestFixtures.catalog().manifest().arena.node_site_positions:
		assertions.expect_true(
			absf(site_position.x) <= BalanceTestFixtures.catalog().envelope.player_center_max.x
			and absf(site_position.y) <= BalanceTestFixtures.catalog().envelope.player_center_max.x,
			"arena node remains reachable inside the player-center bounds",
		)


func _test_entry_contract(assertions: Variant) -> void:
	for entry_ticks: int in [0, 17, 21]:
		_assert_entry_contract(assertions, entry_ticks)


func _assert_entry_contract(assertions: Variant, entry_ticks: int) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	if catalog == null:
		return
	var state: RunState = RunStateFactory.create(8101, catalog)
	var store := EnemyStore.new()
	var definition: EnemyDefinition = catalog.enemy(&"pursuer")
	var materializing: EnemyEntity = store.try_spawn(
		state,
		GameTypes.EnemyType.PURSUER,
		definition,
		Vector2.ZERO,
		1.0,
		1.0,
		100,
		entry_ticks,
	)
	assertions.expect_equal(1, store.active_count(), "materializing enemy occupies an active pool slot")
	var activation_tick: int = 100 + entry_ticks
	assertions.expect_equal(entry_ticks > 0, materializing.is_materializing(100), "only a positive entry delay begins inactive")
	if entry_ticks > 0:
		assertions.expect_false(materializing.is_targetable(activation_tick - 1), "enemy remains inactive until the configured delay elapses")
	assertions.expect_true(materializing.is_targetable(activation_tick), "enemy activates exactly after the configured delay")
	assertions.expect_float(0.0 if entry_ticks > 0 else 1.0, materializing.materialization_progress(100), "entry progress reflects the configured delay")
	assertions.expect_float(1.0, materializing.materialization_progress(activation_tick), "entry progress completes at activation")
	materializing.hit_flash_until_tick = 125
	assertions.expect_true(materializing.is_hit_flashing(124), "hit flash is active before its exclusive deadline")
	assertions.expect_false(materializing.is_hit_flashing(125), "hit flash ends on its exclusive deadline")
	var immediate: EnemyEntity = store.try_spawn(
		state,
		GameTypes.EnemyType.PURSUER,
		definition,
		Vector2.RIGHT,
		1.0,
		1.0,
		100,
	)
	assertions.expect_true(immediate.is_targetable(100), "direct fixture spawn activates immediately by default")


func _test_spawn_contracts(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	if catalog == null:
		return
	var distribution_state: RunState = RunStateFactory.create(8102, catalog)
	var distribution_system := EnemySystem.new()
	distribution_system.initialize(distribution_state, catalog)
	var side_counts := PackedInt32Array([0, 0, 0, 0])
	var lateral_quartile_counts := PackedInt32Array([0, 0, 0, 0])
	var sample_count: int = 4096
	var all_samples_in_frame: bool = true
	var all_lateral_samples_in_side: bool = true
	for _sample_index: int in range(sample_count):
		var relative: Vector2 = distribution_system._choose_normal_spawn_position(Vector2.ZERO)
		var screen_coordinates: Vector2 = _screen_coordinates(relative)
		var side_index: int = _spawn_side_index(screen_coordinates)
		var distance: float = (
			absf(screen_coordinates.x)
			if side_index >= 2
			else absf(screen_coordinates.y)
		)
		var lateral: float = (
			screen_coordinates.y
			if side_index >= 2
			else screen_coordinates.x
		)
		all_samples_in_frame = all_samples_in_frame and (
			distance >= BalanceTestFixtures.catalog().envelope.spawn_inner_half_extent - 0.0001
			and distance <= BalanceTestFixtures.catalog().envelope.spawn_outer_half_extent + 0.0001
		)
		all_lateral_samples_in_side = (
			all_lateral_samples_in_side
			and absf(lateral) <= distance + 0.0001
		)
		side_counts[side_index] += 1
		var normalized_lateral: float = clampf(lateral / distance, -1.0, 1.0)
		var quartile_index: int = mini(3, floori((normalized_lateral + 1.0) * 2.0))
		lateral_quartile_counts[quartile_index] += 1
	assertions.expect_true(
		all_samples_in_frame,
		"every normal sample lies on the ten-to-twelve-metre frame",
	)
	assertions.expect_true(
		all_lateral_samples_in_side,
		"every normal sample stays within its selected side",
	)
	for count: int in side_counts:
		assertions.expect_true(
			count >= floori(float(sample_count) * 0.20)
			and count <= ceili(float(sample_count) * 0.30),
			"each screen side is sampled with a twenty-five-percent distribution",
		)
	for count: int in lateral_quartile_counts:
		assertions.expect_true(
			count >= floori(float(sample_count) * 0.20)
			and count <= ceili(float(sample_count) * 0.30),
			"the lateral side coordinate is uniformly distributed",
		)

	var baseline_state: RunState = RunStateFactory.create(8103, catalog)
	var baseline_system := EnemySystem.new()
	baseline_system.initialize(baseline_state, catalog)
	var baseline_offsets: Array[Vector2] = []
	for _sample_index: int in range(64):
		baseline_offsets.append(baseline_system._choose_normal_spawn_position(Vector2.ZERO))
	var player_positions: Array[Vector2] = [
		Vector2.ZERO,
		Vector2(BalanceTestFixtures.catalog().envelope.player_center_max.x, 0.0),
		Vector2(-BalanceTestFixtures.catalog().envelope.player_center_max.x, 0.0),
		Vector2(0.0, BalanceTestFixtures.catalog().envelope.player_center_max.x),
		Vector2(0.0, -BalanceTestFixtures.catalog().envelope.player_center_max.x),
		Vector2(BalanceTestFixtures.catalog().envelope.player_center_max.x, BalanceTestFixtures.catalog().envelope.player_center_max.x),
		Vector2(-BalanceTestFixtures.catalog().envelope.player_center_max.x, BalanceTestFixtures.catalog().envelope.player_center_max.x),
		Vector2(-BalanceTestFixtures.catalog().envelope.player_center_max.x, -BalanceTestFixtures.catalog().envelope.player_center_max.x),
		Vector2(BalanceTestFixtures.catalog().envelope.player_center_max.x, -BalanceTestFixtures.catalog().envelope.player_center_max.x),
	]
	var translation_invariant: bool = true
	for player_position: Vector2 in player_positions:
		var translated_state: RunState = RunStateFactory.create(8103, catalog)
		var translated_system := EnemySystem.new()
		translated_system.initialize(translated_state, catalog)
		for sample_index: int in range(baseline_offsets.size()):
			var translated_offset: Vector2 = (
				translated_system._choose_normal_spawn_position(player_position)
				- player_position
			)
			translation_invariant = (
				translation_invariant
				and translated_offset.is_equal_approx(baseline_offsets[sample_index])
			)
	assertions.expect_true(
		translation_invariant,
		"center, side, and corner players receive the same relative spawn sequence",
	)



func _test_outside_entry_and_far_despawn(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	if catalog == null:
		return
	var entry_state: RunState = RunStateFactory.create(8106, catalog)
	var entry_system := EnemySystem.new()
	entry_system.initialize(entry_state, catalog)
	var entering: EnemyEntity = entry_system._spawn_enemy(
		GameTypes.EnemyType.PURSUER,
		Vector2(17.0, 0.0),
		0,
	)
	var entering_id: int = entering.entity_id
	assertions.expect_equal(
		Vector2(17.0, 0.0),
		entering.position,
		"production normal spawn remains outside the arena",
	)
	entry_state.combat_tick = 20
	entry_system.advance_snapshot([entering_id], Vector2.ZERO, 20)
	assertions.expect_equal(
		Vector2(17.0, 0.0),
		entering.position,
		"outside normal waits through the final materialization tick",
	)
	assertions.expect_true(
		entry_system.uniform_grid.query_circle_candidates(
			entering.position,
			0.1,
			0.0,
		).is_empty(),
		"materializing outside normal is absent from targeting queries",
	)
	entry_state.combat_tick = 21
	entry_system.advance_snapshot([entering_id], Vector2.ZERO, 21)
	assertions.expect_true(
		entering.position.x < 17.0 and entering.position.x > 16.0,
		"active outside normal begins continuous pursuit without teleporting",
	)
	assertions.expect_equal(
		[entering_id],
		entry_system.uniform_grid.query_circle_candidates(entering.position, 0.1, 0.0),
		"active outside normal is available to exterior targeting queries",
	)
	var previous_position: Vector2 = entering.position
	var movement_was_continuous: bool = true
	for tick: int in range(22, 70):
		entry_state.combat_tick = tick
		entry_system.advance_snapshot([entering_id], Vector2.ZERO, tick)
		movement_was_continuous = movement_was_continuous and (
			entering.position.distance_to(previous_position)
			<= entering.definition.move_speed / 60.0 + 0.0001
		)
		previous_position = entering.position
	assertions.expect_true(
		movement_was_continuous,
		"outside normal crosses the boundary without a position jump",
	)
	assertions.expect_true(
		entry_system._is_enemy_center_inside_arena(entering.position, entering.body_radius()),
		"outside normal eventually enters the arena",
	)
	var entering_limit: float = BalanceTestFixtures.catalog().envelope.enemy_center_limit(entering.body_radius()).x
	entering.position = Vector2(entering_limit, 0.0)
	entry_state.combat_tick = 70
	entry_system.advance_snapshot([entering_id], Vector2(20.0, 0.0), 70)
	assertions.expect_float(
		entering_limit,
		entering.position.x,
		"normal boundary restriction resumes after the enemy has entered",
	)

	var contact_enemy: EnemyEntity = entry_system.enemy_store.try_spawn(
		entry_state,
		GameTypes.EnemyType.PURSUER,
		catalog.enemy(&"pursuer"),
		Vector2(16.0, 0.0),
		1.0,
		1.0,
		69,
	)
	var outside_player := Vector2(BalanceTestFixtures.catalog().envelope.player_center_max.x, 0.0)
	var contact_records: Array[Dictionary] = entry_system.resolve_contact_damage_candidates(
		[contact_enemy.entity_id],
		outside_player,
		70,
	)
	assertions.expect_equal(
		1,
		contact_records.size(),
		"active outside normal can resolve contact damage",
	)

	var weapon_state: RunState = RunStateFactory.create(8107, catalog)
	weapon_state.weapons.clear()
	var weapon_definition: WeaponDefinition = catalog.weapon(&"resonance_wave")
	weapon_state.weapons.append(RunWeapon.create(
		weapon_definition.weapon_id,
		catalog.lineage_for_weapon(weapon_definition.weapon_id),
		false,
		weapon_state.rng_streams.create_weapon_rng(catalog.lineage_for_weapon(weapon_definition.weapon_id), 0),
	))
	var weapon_simulation := CombatSimulation.new()
	weapon_simulation.initialize(weapon_state, catalog)
	var outside_target: EnemyEntity = weapon_simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.BULWARK,
		Vector2(16.2, 0.0),
		-1,
		false,
		true,
	)
	weapon_simulation.weapon_system.update_move_direction(Vector2.RIGHT)
	var attacks: Array[Dictionary] = weapon_simulation.weapon_system.advance_and_fire(
		outside_player,
		weapon_simulation.enemy_system.enemy_store,
		weapon_simulation.enemy_system.uniform_grid,
		1,
	)
	var hits: Array[Dictionary] = []
	if not attacks.is_empty():
		hits.assign(attacks[0].get("hits", []))
	var outside_hit: bool = false
	for hit: Dictionary in hits:
		outside_hit = outside_hit or int(hit.get("entity_id", -1)) == outside_target.entity_id
	assertions.expect_true(
		outside_hit,
		"weapon damage can acquire an active enemy outside the arena",
	)

	var cull_state: RunState = RunStateFactory.create(8108, catalog)
	var cull_system := EnemySystem.new()
	cull_system.initialize(cull_state, catalog)
	var pursuer: EnemyDefinition = catalog.enemy(&"pursuer")
	var exact: EnemyEntity = cull_system.enemy_store.try_spawn(
		cull_state,
		GameTypes.EnemyType.PURSUER,
		pursuer,
		EnemySystem.SCREEN_RIGHT_WORLD * 18.0,
		1.0,
		1.0,
		0,
		100,
	)
	var materializing_far: EnemyEntity = cull_system.enemy_store.try_spawn(
		cull_state,
		GameTypes.EnemyType.PURSUER,
		pursuer,
		EnemySystem.SCREEN_RIGHT_WORLD * 18.01,
		1.0,
		1.0,
		0,
		100,
	)
	var active_far: EnemyEntity = cull_system.enemy_store.try_spawn(
		cull_state,
		GameTypes.EnemyType.PURSUER,
		pursuer,
		EnemySystem.SCREEN_DOWN_WORLD * 18.01,
		1.0,
		1.0,
		0,
	)
	var swarm: EnemyEntity = cull_system.enemy_store.try_spawn(
		cull_state,
		GameTypes.EnemyType.SWARMER,
		catalog.enemy(&"swarmer"),
		EnemySystem.SCREEN_RIGHT_WORLD * 25.0,
		1.0,
		1.0,
		0,
	)
	swarm.configure_swarm_event(1, Vector2.LEFT, 10.0, false)
	var elite: EnemyEntity = cull_system.enemy_store.try_spawn(
		cull_state,
		GameTypes.EnemyType.ELITE,
		catalog.enemy_for_type(GameTypes.EnemyType.ELITE),
		EnemySystem.SCREEN_DOWN_WORLD * 25.0,
		1.0,
		1.0,
		0,
		100,
	)
	var boss: EnemyEntity = cull_system.enemy_store.try_spawn(
		cull_state,
		GameTypes.EnemyType.BOSS,
		catalog.enemy_for_type(GameTypes.EnemyType.BOSS),
		-EnemySystem.SCREEN_DOWN_WORLD * 25.0,
		1.0,
		1.0,
		0,
		100,
	)
	var exact_id: int = exact.entity_id
	var materializing_far_id: int = materializing_far.entity_id
	var active_far_id: int = active_far.entity_id
	var swarm_id: int = swarm.entity_id
	var elite_id: int = elite.entity_id
	var boss_id: int = boss.entity_id
	cull_state.stop_until_tick = 100
	cull_state.combat_tick = 1
	cull_system.advance_snapshot(cull_system.snapshot_ids(), Vector2.ZERO, 1)
	assertions.expect_true(
		cull_system.enemy_store.has_entity(exact_id),
		"normal at exactly eighteen metres remains",
	)
	assertions.expect_false(
		cull_system.enemy_store.has_entity(materializing_far_id),
		"materializing normal beyond eighteen metres is removed",
	)
	assertions.expect_false(
		cull_system.enemy_store.has_entity(active_far_id),
		"STOP-frozen normal beyond eighteen metres is removed",
	)
	assertions.expect_true(
		cull_system.enemy_store.has_entity(swarm_id),
		"swarm member is excluded from normal far despawn",
	)
	assertions.expect_true(
		cull_system.enemy_store.has_entity(elite_id),
		"elite is excluded from normal far despawn",
	)
	assertions.expect_true(
		cull_system.enemy_store.has_entity(boss_id),
		"boss is excluded from normal far despawn",
	)
	assertions.expect_equal(
		2,
		cull_state.normal_far_despawn_count,
		"far-despawn telemetry counts only removed normals",
	)
	assertions.expect_equal(0, cull_state.total_kills, "far despawn grants no kill")
	assertions.expect_equal(0, cull_state.xp, "far despawn grants no XP")
	assertions.expect_equal(0, cull_state.kill_chain_count, "far despawn grants no kill chain")
	assertions.expect_float(
		0.0,
		cull_state.spawn_credit,
		"far despawn does not refund spawn credit directly",
	)
	cull_system.accrue_spawn_credit()
	assertions.expect_true(
		cull_state.spawn_credit > 0.0 and cull_state.spawn_credit < 1.0,
		"existing deficit replenishment begins in the same tick",
	)

	var boss_tick_state: RunState = RunStateFactory.create(8109, catalog)
	var boss_tick_system := EnemySystem.new()
	boss_tick_system.initialize(boss_tick_state, catalog)
	var boss_tick_normal: EnemyEntity = boss_tick_system.enemy_store.try_spawn(
		boss_tick_state,
		GameTypes.EnemyType.PURSUER,
		pursuer,
		EnemySystem.SCREEN_RIGHT_WORLD * 25.0,
		1.0,
		1.0,
		BalanceTestFixtures.catalog().boss_start_tick,
		100,
	)
	var boss_tick_normal_id: int = boss_tick_normal.entity_id
	boss_tick_state.combat_tick = BalanceTestFixtures.catalog().boss_start_tick
	boss_tick_system.advance_snapshot(
		boss_tick_system.snapshot_ids(),
		Vector2.ZERO,
		BalanceTestFixtures.catalog().boss_start_tick,
	)
	assertions.expect_true(
		boss_tick_system.enemy_store.has_entity(boss_tick_normal_id),
		"boss boundary disables far despawn for boss absorption",
	)
	assertions.expect_equal(
		0,
		boss_tick_state.normal_far_despawn_count,
		"boss transition owns boss-boundary removal telemetry",
	)


func _test_boss_charge(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	if catalog == null:
		return
	var state: RunState = RunStateFactory.create(8105, catalog)
	var system := EnemySystem.new()
	system.initialize(state, catalog)
	system._elite_spawned.fill(1)
	state.combat_tick = BalanceTestFixtures.catalog().boss_start_tick
	var spawned: Array[EnemyEntity] = system.resolve_scheduled_spawns(
		Vector2.ZERO,
		BalanceTestFixtures.catalog().boss_start_tick,
	)
	var boss: EnemyEntity = spawned[0]
	var boss_ids: Array[int] = [boss.entity_id]
	var projectile_pool := ProjectilePool.new()
	var phase_one_interval: int = system._boss_action_interval_ticks(120, 1)
	var phase_two_interval: int = system._boss_action_interval_ticks(120, 2)
	var phase_three_interval: int = system._boss_action_interval_ticks(120, 3)
	assertions.expect_equal(110, phase_one_interval, "phase-one action rate rounds up to 110 ticks")
	assertions.expect_equal(82, phase_two_interval, "phase-two action rate rounds up to 82 ticks")
	assertions.expect_equal(62, phase_three_interval, "phase-three action rate rounds up to 62 ticks")

	state.combat_tick = boss.activation_tick - 1
	system.advance_snapshot(boss_ids, Vector2(6.0, 0.0), state.combat_tick)
	system.resolve_ready_enemy_special_actions(boss_ids, Vector2.ZERO, state.combat_tick, projectile_pool)
	assertions.expect_equal(Vector2.ZERO, boss.position, "boss stays centered through the final inactive tick")
	assertions.expect_float(0.0, boss.special_elapsed_ticks, "boss action clock is frozen during entry")
	var phase_one_idle_ticks: int = phase_one_interval - BalanceTestFixtures.catalog().enemy_for_type(GameTypes.EnemyType.BOSS).telegraph_ticks
	for action_index: int in range(phase_one_interval):
		var current_tick: int = boss.activation_tick + action_index
		state.combat_tick = current_tick
		system.advance_snapshot(boss_ids, Vector2(6.0, 0.0), current_tick)
		system.resolve_ready_enemy_special_actions(boss_ids, Vector2.ZERO, current_tick, projectile_pool)
		if action_index == phase_one_idle_ticks - 2:
			assertions.expect_false(boss.boss_charge_active, "phase one stays idle until its calibrated charge boundary")
		elif action_index == phase_one_idle_ticks - 1:
			assertions.expect_true(boss.boss_charge_active, "phase one charge begins at its calibrated boundary")
			assertions.expect_equal(phase_one_interval, boss.boss_charge_interval_ticks, "charge latches the current interval")
			assertions.expect_equal(8, boss.boss_charge_spoke_count, "phase one charge latches eight spokes")
			assertions.expect_false(boss.boss_charge_half_step, "first volley latches the unshifted pattern")
	assertions.expect_equal(8, projectile_pool.active_count(), "thirty action ticks of charge emit eight projectiles")
	assertions.expect_true(boss.position.x > 0.0, "active boss directly pursues the player while charging")
	for entry: Vector2i in projectile_pool.snapshot_active():
		var projectile: ProjectileState = projectile_pool.resolve_snapshot_entry(entry)
		assertions.expect_equal(boss.position, projectile.position, "volley projectile originates at the moving boss fire position")

	boss.hp = boss.max_hp * 0.5
	var phase_two_idle_ticks: int = phase_two_interval - BalanceTestFixtures.catalog().enemy_for_type(GameTypes.EnemyType.BOSS).telegraph_ticks
	for action_index: int in range(phase_two_idle_ticks):
		var phase_two_tick: int = boss.activation_tick + phase_one_interval + action_index
		state.combat_tick = phase_two_tick
		system.advance_snapshot(boss_ids, Vector2(6.0, 0.0), phase_two_tick)
		system.resolve_ready_enemy_special_actions(boss_ids, Vector2.ZERO, phase_two_tick, projectile_pool)
	assertions.expect_true(boss.boss_charge_active, "phase two begins its charge at the calibrated idle boundary")
	assertions.expect_equal(12, boss.boss_charge_spoke_count, "phase two charge latches twelve spokes")
	assertions.expect_true(boss.boss_charge_half_step, "second volley latches the half-step offset")
	boss.hp = boss.max_hp * 0.2
	var phase_two_charge_tick: int = (
		boss.activation_tick + phase_one_interval + phase_two_idle_ticks
	)
	for charge_index: int in range(BalanceTestFixtures.catalog().enemy_for_type(GameTypes.EnemyType.BOSS).telegraph_ticks):
		var phase_change_tick: int = phase_two_charge_tick + charge_index
		state.combat_tick = phase_change_tick
		system.advance_snapshot(boss_ids, Vector2(6.0, 0.0), phase_change_tick)
		system.resolve_ready_enemy_special_actions(boss_ids, Vector2.ZERO, phase_change_tick, projectile_pool)
		if charge_index == 0:
			assertions.expect_equal(12, boss.boss_charge_spoke_count, "phase change does not mutate a latched charge")
	assertions.expect_equal(20, projectile_pool.active_count(), "latched phase-two charge emits twelve additional projectiles")
	var shifted_entry: Vector2i = projectile_pool.snapshot_active()[8]
	var shifted_projectile: ProjectileState = projectile_pool.resolve_snapshot_entry(shifted_entry)
	assertions.expect_true(
		shifted_projectile.velocity.normalized().dot(Vector2.from_angle(PI / 12.0)) > 0.9999,
		"second volley applies its latched half-step angle",
	)

	boss.boss_action_age_ticks = float(
		catalog.manifest().combat.boss_enrage_interval_ticks - 2
	)
	state.combat_tick = phase_two_charge_tick + BalanceTestFixtures.catalog().enemy_for_type(GameTypes.EnemyType.BOSS).telegraph_ticks
	system.advance_snapshot(boss_ids, Vector2(6.0, 0.0), state.combat_tick)
	assertions.expect_equal(0, state.boss_enrage_stacks, "boss enrage remains zero at 1799 accumulated action ticks")
	state.combat_tick += 1
	system.advance_snapshot(boss_ids, Vector2(6.0, 0.0), state.combat_tick)
	assertions.expect_equal(1, state.boss_enrage_stacks, "boss enrage begins at exactly 1800 accumulated action ticks")

	projectile_pool.clear()
	system._start_boss_charge(boss, 68)
	state.stop_until_tick = state.combat_tick + 1000
	for stop_index: int in range(59):
		state.combat_tick += 1
		system.advance_snapshot(boss_ids, Vector2(6.0, 0.0), state.combat_tick)
		system.resolve_ready_enemy_special_actions(boss_ids, Vector2.ZERO, state.combat_tick, projectile_pool)
	assertions.expect_equal(0, projectile_pool.active_count(), "stop-scaled charge does not fire after fifty-nine combat updates")
	state.combat_tick += 1
	system.advance_snapshot(boss_ids, Vector2(6.0, 0.0), state.combat_tick)
	system.resolve_ready_enemy_special_actions(boss_ids, Vector2.ZERO, state.combat_tick, projectile_pool)
	assertions.expect_equal(16, projectile_pool.active_count(), "stop-scaled charge fires after sixty combat updates")


func _screen_coordinates(relative_position: Vector2) -> Vector2:
	return Vector2(
		relative_position.dot(EnemySystem.SCREEN_RIGHT_WORLD),
		relative_position.dot(EnemySystem.SCREEN_DOWN_WORLD),
	)


func _spawn_side_index(screen_coordinates: Vector2) -> int:
	if absf(screen_coordinates.x) >= absf(screen_coordinates.y):
		return 3 if screen_coordinates.x >= 0.0 else 2
	return 1 if screen_coordinates.y >= 0.0 else 0


func _catalog(assertions: Variant) -> DefinitionCatalog:
	var catalog := DefinitionCatalog.new()
	assertions.expect_true(catalog.validate_manifest(BalanceTestFixtures.manifest()), "content catalog validates")
	return catalog if catalog.is_valid else null
