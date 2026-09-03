extends RefCounted


func test_names() -> PackedStringArray:
	return PackedStringArray([
		"revision_five_envelope_and_grid",
		"enemy_entry_contract_and_pool_default",
		"boundary_and_center_spawn_contracts",
		"boss_charge_cadence_and_latches",
	])


func run_test(test_name: String, assertions: Variant, _context: Dictionary) -> void:
	match test_name:
		"revision_five_envelope_and_grid":
			_test_envelope_and_grid(assertions)
		"enemy_entry_contract_and_pool_default":
			_test_entry_contract(assertions)
		"boundary_and_center_spawn_contracts":
			_test_spawn_contracts(assertions)
		"boss_charge_cadence_and_latches":
			_test_boss_charge(assertions)
		_:
			assertions.expect_true(false, "registered revision five enemy-spatial test")


func _test_envelope_and_grid(assertions: Variant) -> void:
	assertions.expect_float(15.0, CombatEnvelope.ARENA_HALF_EXTENT, "arena half extent is fifteen meters")
	assertions.expect_float(14.55, CombatEnvelope.PLAYER_CENTER_LIMIT, "player center retains its body-radius margin")
	assertions.expect_float(8.0, CombatEnvelope.TARGET_CENTER_RADIUS, "weapon acquisition center is capped at eight meters")
	assertions.expect_float(9.0, CombatEnvelope.EFFECT_OUTER_RADIUS, "weapon effect outer edge is capped at nine meters")
	assertions.expect_float(10.0, CombatEnvelope.DAMAGE_CENTER_RADIUS, "damage center stays in the ten-meter safe envelope")
	assertions.expect_float(10.0, CombatEnvelope.BOT_AWARENESS_RADIUS, "bot awareness matches the safe envelope")
	assertions.expect_equal(21, CombatEnvelope.NORMAL_ENTRY_TICKS, "normal entry lasts twenty-one ticks")
	assertions.expect_equal(36, CombatEnvelope.ELITE_ENTRY_TICKS, "elite entry lasts thirty-six ticks")
	assertions.expect_equal(60, CombatEnvelope.BOSS_ENTRY_TICKS, "boss entry lasts sixty ticks")
	assertions.expect_float(18.0, CombatEnvelope.CAMERA_SIZE, "camera uses the fixed eighteen-meter size")
	assertions.expect_float(0.12, CombatEnvelope.CAMERA_FOLLOW_TAU_SECONDS, "camera follow smoothing uses the locked tau")
	var grid := UniformGrid.new()
	assertions.expect_equal(Vector2(-15.0, -15.0), UniformGrid.ARENA_MIN, "grid begins at the thirty-meter arena corner")
	assertions.expect_equal(Vector2(15.0, 15.0), UniformGrid.ARENA_MAX, "grid ends at the thirty-meter arena corner")
	assertions.expect_equal(Vector2i(14, 14), grid.cell_indices_for_position(Vector2(100.0, 100.0)), "positive overflow clamps to the final cell")
	assertions.expect_equal(225, UniformGrid.CELL_COUNT, "two-meter cells cover the complete thirty-meter arena")
	for site_position: Vector2 in ArenaObjectSystem.NODE_SITE_POSITIONS:
		assertions.expect_true(
			absf(site_position.x) <= CombatEnvelope.PLAYER_CENTER_LIMIT
			and absf(site_position.y) <= CombatEnvelope.PLAYER_CENTER_LIMIT,
			"arena node remains reachable inside the player-center bounds",
		)


func _test_entry_contract(assertions: Variant) -> void:
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
		CombatEnvelope.NORMAL_ENTRY_TICKS,
	)
	assertions.expect_equal(1, store.active_count(), "materializing enemy occupies an active pool slot")
	assertions.expect_true(materializing.is_materializing(100), "entry begins inactive on its spawn tick")
	assertions.expect_false(materializing.is_targetable(120), "normal remains inactive through tick twenty")
	assertions.expect_true(materializing.is_targetable(121), "normal activates exactly after twenty-one ticks")
	assertions.expect_float(0.0, materializing.materialization_progress(100), "entry progress starts at zero")
	assertions.expect_float(1.0, materializing.materialization_progress(121), "entry progress completes at activation")
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
	var first_state: RunState = RunStateFactory.create(8102, catalog)
	var first_system := EnemySystem.new()
	first_system.initialize(first_state, catalog)
	first_state.spawn_credit = float(EnemySystem.MAXIMUM_SPAWNS_PER_TICK)
	var first_spawns: Array[EnemyEntity] = first_system.resolve_normal_spawns(
		Vector2(CombatEnvelope.PLAYER_CENTER_LIMIT, 0.0),
		0,
	)
	assertions.expect_true(not first_spawns.is_empty(), "normal spawn credit produces boundary enemies")
	assertions.expect_equal(first_spawns.size(), first_system._normal_enemy_count(), "materializing normals count toward the active target")
	for enemy: EnemyEntity in first_spawns:
		var center_limit: float = CombatEnvelope.enemy_center_limit(enemy.body_radius())
		assertions.expect_true(
			is_equal_approx(absf(enemy.position.x), center_limit)
			or is_equal_approx(absf(enemy.position.y), center_limit),
			"normal center lies exactly on its type-radius perimeter",
		)
		assertions.expect_true(
			enemy.position.distance_to(Vector2(CombatEnvelope.PLAYER_CENTER_LIMIT, 0.0))
			>= CombatEnvelope.NORMAL_SPAWN_MIN_DISTANCE,
			"normal boundary spawn respects the nine-meter player distance",
		)
		assertions.expect_equal(21, enemy.activation_tick - enemy.spawn_tick, "normal receives the production entry delay")

	var second_state: RunState = RunStateFactory.create(8102, catalog)
	var second_system := EnemySystem.new()
	second_system.initialize(second_state, catalog)
	second_state.spawn_credit = float(EnemySystem.MAXIMUM_SPAWNS_PER_TICK)
	var second_spawns: Array[EnemyEntity] = second_system.resolve_normal_spawns(
		Vector2(CombatEnvelope.PLAYER_CENTER_LIMIT, 0.0),
		0,
	)
	assertions.expect_equal(first_spawns.size(), second_spawns.size(), "same seed produces the same boundary spawn count")
	for index: int in range(first_spawns.size()):
		assertions.expect_equal(first_spawns[index].enemy_type, second_spawns[index].enemy_type, "same seed preserves normal type order")
		assertions.expect_equal(first_spawns[index].position, second_spawns[index].position, "same seed preserves normal perimeter positions")
	var boundary_players: Array[Vector2] = [
		Vector2(CombatEnvelope.PLAYER_CENTER_LIMIT, CombatEnvelope.PLAYER_CENTER_LIMIT),
		Vector2(-CombatEnvelope.PLAYER_CENTER_LIMIT, CombatEnvelope.PLAYER_CENTER_LIMIT),
		Vector2(-CombatEnvelope.PLAYER_CENTER_LIMIT, -CombatEnvelope.PLAYER_CENTER_LIMIT),
		Vector2(CombatEnvelope.PLAYER_CENTER_LIMIT, -CombatEnvelope.PLAYER_CENTER_LIMIT),
	]
	var later_enemy_types: Array[GameTypes.EnemyType] = [
		GameTypes.EnemyType.BULWARK,
		GameTypes.EnemyType.SHOOTER,
	]
	for enemy_type: GameTypes.EnemyType in later_enemy_types:
		var definition: EnemyDefinition = catalog.enemy_for_type(enemy_type)
		var center_limit: float = CombatEnvelope.enemy_center_limit(definition.body_radius)
		for player_position: Vector2 in boundary_players:
			var spawn_position: Vector2 = first_system._choose_normal_spawn_position(
				player_position,
				enemy_type,
			)
			assertions.expect_true(
				is_equal_approx(absf(spawn_position.x), center_limit)
				or is_equal_approx(absf(spawn_position.y), center_limit),
				"later enemy type %d uses its body-radius perimeter at every player corner"
				% int(enemy_type),
			)
			assertions.expect_true(
				spawn_position.distance_to(player_position)
				>= CombatEnvelope.NORMAL_SPAWN_MIN_DISTANCE,
				"later enemy type %d keeps the nine-meter spawn distance at every player corner"
				% int(enemy_type),
			)
	var fallback_system := EnemySystem.new()
	var fallback_state: RunState = RunStateFactory.create(8102, catalog)
	fallback_system.initialize(fallback_state, catalog)
	fallback_system._spawn_rng = null
	var fallback_radius: float = catalog.enemy_for_type(
		GameTypes.EnemyType.SHOOTER
	).body_radius
	var fallback_limit: float = CombatEnvelope.enemy_center_limit(fallback_radius)
	assertions.expect_equal(
		Vector2(-fallback_limit, -fallback_limit),
		fallback_system._choose_normal_spawn_position(
			Vector2(
				CombatEnvelope.PLAYER_CENTER_LIMIT,
				CombatEnvelope.PLAYER_CENTER_LIMIT,
			),
			GameTypes.EnemyType.SHOOTER,
		),
		"failed spawn search falls back deterministically to the farthest perimeter corner",
	)

	var tracked: EnemyEntity = first_spawns[0]
	var tracked_position: Vector2 = tracked.position
	first_state.combat_tick = 20
	first_system.advance_snapshot(first_system.snapshot_ids(), Vector2.ZERO, 20)
	assertions.expect_equal(tracked_position, tracked.position, "materializing normal does not move")
	assertions.expect_float(0.0, tracked.contact_elapsed_ticks, "materializing normal does not advance contact time")
	assertions.expect_true(
		first_system.uniform_grid.query_aabb_candidates(CombatEnvelope.ARENA_MIN, CombatEnvelope.ARENA_MAX).is_empty(),
		"materializing enemies are absent from the collision grid",
	)
	assertions.expect_true(
		first_system.resolve_ready_enemy_damage_actions(first_system.snapshot_ids(), tracked.position, 20).is_empty(),
		"materializing enemy cannot damage the player",
	)
	first_state.combat_tick = 21
	first_system.advance_snapshot(first_system.snapshot_ids(), Vector2.ZERO, 21)
	assertions.expect_true(tracked.is_targetable(21), "normal becomes active on its activation tick")
	assertions.expect_true(tracked.position != tracked_position, "active normal begins direct pursuit")

	var elite_state: RunState = RunStateFactory.create(8103, catalog)
	var elite_system := EnemySystem.new()
	elite_system.initialize(elite_state, catalog)
	var elite_tick: int = catalog.manifest().elite_spawn_ticks[0]
	elite_state.combat_tick = elite_tick
	var elites: Array[EnemyEntity] = elite_system.resolve_scheduled_spawns(Vector2(9.0, 9.0), elite_tick)
	assertions.expect_equal(1, elites.size(), "first elite schedule creates one elite")
	assertions.expect_equal(Vector2.ZERO, elites[0].position, "elite portal is exactly at arena center")
	assertions.expect_equal(36, elites[0].activation_tick - elite_tick, "elite receives its thirty-six-tick entry")

	var boss_state: RunState = RunStateFactory.create(8104, catalog)
	var boss_system := EnemySystem.new()
	boss_system.initialize(boss_state, catalog)
	boss_system._elite_spawned.fill(1)
	boss_state.combat_tick = RunState.BOSS_START_TICK
	var bosses: Array[EnemyEntity] = boss_system.resolve_scheduled_spawns(
		Vector2(9.0, -9.0),
		RunState.BOSS_START_TICK,
	)
	assertions.expect_equal(1, bosses.size(), "boss schedule creates one final boss")
	assertions.expect_equal(Vector2.ZERO, bosses[0].position, "boss portal is exactly at arena center")
	assertions.expect_equal(60, bosses[0].activation_tick - RunState.BOSS_START_TICK, "boss receives its sixty-tick entry")


func _test_boss_charge(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	if catalog == null:
		return
	var state: RunState = RunStateFactory.create(8105, catalog)
	var system := EnemySystem.new()
	system.initialize(state, catalog)
	system._elite_spawned.fill(1)
	state.combat_tick = RunState.BOSS_START_TICK
	var spawned: Array[EnemyEntity] = system.resolve_scheduled_spawns(
		Vector2.ZERO,
		RunState.BOSS_START_TICK,
	)
	var boss: EnemyEntity = spawned[0]
	var boss_ids: Array[int] = [boss.entity_id]
	var projectile_pool := ProjectilePool.new()
	var phase_one_interval: int = system._boss_action_interval_ticks(120, 1)
	var phase_two_interval: int = system._boss_action_interval_ticks(120, 2)
	var phase_three_interval: int = system._boss_action_interval_ticks(120, 3)
	assertions.expect_equal(110, phase_one_interval, "revision eight phase-one action rate rounds up to 110 ticks")
	assertions.expect_equal(82, phase_two_interval, "revision eight phase-two action rate rounds up to 82 ticks")
	assertions.expect_equal(62, phase_three_interval, "revision eight phase-three action rate rounds up to 62 ticks")

	state.combat_tick = boss.activation_tick - 1
	system.advance_snapshot(boss_ids, Vector2(6.0, 0.0), state.combat_tick)
	system.resolve_ready_enemy_special_actions(boss_ids, Vector2.ZERO, state.combat_tick, projectile_pool)
	assertions.expect_equal(Vector2.ZERO, boss.position, "boss stays centered through the final inactive tick")
	assertions.expect_float(0.0, boss.special_elapsed_ticks, "boss action clock is frozen during entry")
	var phase_one_idle_ticks: int = phase_one_interval - CombatEnvelope.BOSS_CHARGE_TICKS
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
	var phase_two_idle_ticks: int = phase_two_interval - CombatEnvelope.BOSS_CHARGE_TICKS
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
	for charge_index: int in range(CombatEnvelope.BOSS_CHARGE_TICKS):
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
		catalog.manifest().boss_enrage_interval_ticks - 2
	)
	state.combat_tick = phase_two_charge_tick + CombatEnvelope.BOSS_CHARGE_TICKS
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


func _catalog(assertions: Variant) -> DefinitionCatalog:
	var catalog := DefinitionCatalog.new()
	assertions.expect_true(catalog.load_and_validate(), "revision five content catalog validates")
	return catalog if catalog.is_valid else null
