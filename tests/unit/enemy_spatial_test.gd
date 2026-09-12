extends RefCounted


func test_sparse_grid_queries_distant_cells_without_aliasing(a: Variant, _context: Dictionary) -> void:
	var grid := BalanceTestFixtures.grid()
	grid.insert(41, Vector2(5000, -3000))
	grid.insert(42, Vector2(200, -100))
	grid.insert(43, Vector2(-0.1, 0.1))
	a.expect_equal([41], grid.query_circle_candidates(Vector2(5000, -3000), 0.1, 0.0), "far cells do not alias nearer objects")
	a.expect_equal([43], grid.query_segment_candidates(Vector2(-0.2, 0.1), Vector2(0.2, 0.1), 0.0), "negative cells remain queryable across zero")
	grid.insert(43, Vector2(0.1, 0.1))
	a.expect_equal([43], grid.query_segment_candidates(Vector2(-0.2, 0.1), Vector2(0.2, 0.1), 0.0), "an identity inserted into multiple cells is returned only once")
	grid.clear()
	a.expect_true(grid.query_circle_candidates(Vector2(5000, -3000), 1.0, 0.0).is_empty(), "cleared cells return no stale IDs")
	for offset: int in 4:
		grid.insert(4294967311, Vector2(10000 + offset * 10, 20000))
		grid.insert(42, Vector2(10000 + offset * 10, 20000))
		grid.insert(42, Vector2(10000 + offset * 10 + 2, 20000))
		a.expect_equal([42, 4294967311], grid.query_circle_candidates(Vector2(10000 + offset * 10, 20000), 3.0, 0.0), "reused cells preserve full IDs, ordering and duplicate suppression")
		a.expect_true(grid.query_circle_candidates(Vector2(5000, -3000), 1.0, 0.0).is_empty(), "reused storage does not revive historical coordinates")
		grid.clear()


func test_enemy_entry_contract_and_pool_default(assertions: Variant, _context: Dictionary) -> void:
	for entry_ticks: int in [0, 17, 21]:
		_assert_entry_contract(assertions, entry_ticks)


func test_spawn_bodies_remain_offscreen_after_movement_and_resize(a: Variant, _context: Dictionary) -> void:
	var catalog: DefinitionCatalog = _catalog(a)
	var view := ArenaView.new()
	var system := EnemySystem.new()
	system.initialize(RunStateFactory.create(8103, catalog), catalog, view)
	for dimensions: Vector2i in [Vector2i(1920, 1080), Vector2i(1080, 1920), Vector2i(2560, 1080)]:
		view.viewport_size = dimensions
		view.reset(Vector2(950, -700))
		view.advance(Vector2(951, -699), 1.0 / 60.0)
		for type: GameTypes.EnemyType in [GameTypes.EnemyType.PURSUER, GameTypes.EnemyType.BULWARK, GameTypes.EnemyType.ELITE, GameTypes.EnemyType.BOSS]:
			var all_hidden: bool = true
			for sample: int in 64:
				var position: Vector2 = system._spawn_position_for_type(type)
				all_hidden = all_hidden and not _body_intersects_screen(view, position, catalog.enemy_for_type(type).body_radius)
			a.expect_true(all_hidden, "the complete body spawns outside the current camera at %s" % dimensions)
		var rng := RandomNumberGenerator.new()
		rng.seed = 88
		var before: Vector2 = view.sample_offscreen_position(rng, 2.0, 0.6)
		view.shift_origin(Vector2(1024, -1024))
		rng.seed = 88
		var after: Vector2 = view.sample_offscreen_position(rng, 2.0, 0.6)
		a.expect_true((before - Vector2(1024, -1024)).is_equal_approx(after), "origin changes preserve the spawn frame")


func test_far_enemies_despawn_or_reenter_without_rewards(a: Variant, _context: Dictionary) -> void:
	var catalog: DefinitionCatalog = _catalog(a)
	var sim := CombatSimulation.new()
	sim.initialize(RunStateFactory.create(8108, catalog), catalog)
	sim.player_position = Vector2(500, -400)
	sim.view.reset(sim.player_position)
	var normal: EnemyEntity = sim.spawn_fixture_enemy(GameTypes.EnemyType.PURSUER, Vector2.ZERO, -1)
	var normal_id: int = normal.entity_id
	var elite: EnemyEntity = sim.spawn_fixture_enemy(GameTypes.EnemyType.ELITE, Vector2.ZERO, -1)
	elite.elite_serial = 0
	elite.hp *= 0.5
	elite.telegraph_active = true
	var elite_id: int = elite.entity_id
	var hp: float = elite.hp
	var boss: EnemyEntity = sim.spawn_fixture_enemy(GameTypes.EnemyType.BOSS, Vector2.ZERO, -1)
	boss.boss_phase = 2
	boss.boss_charge_active = true
	var boss_id: int = boss.entity_id
	sim.enemy_system.advance_snapshot(sim.enemy_system.snapshot_ids(), sim.player_position, 1)
	a.expect_false(sim.enemy_system.enemy_store.has_entity(normal_id), "distant normal despawns")
	a.expect_equal(elite_id, elite.entity_id, "elite identity survives relocation")
	a.expect_equal(boss_id, boss.entity_id, "boss identity survives relocation")
	a.expect_float(hp, elite.hp, "wounded elite retains its HP")
	a.expect_equal(2, boss.boss_phase, "boss retains its phase")
	a.expect_false(elite.telegraph_active or boss.boss_charge_active, "relocation cancels pending attacks")
	a.expect_true(elite.is_materializing(1) and boss.is_materializing(1), "important enemies restart their entry grace")
	a.expect_false(sim.view.is_body_visible(elite.position, elite.body_radius()), "elite reappears offscreen near the current player")
	a.expect_equal(0, sim.state.total_kills, "relocation awards no kill")
	a.expect_equal(0, sim.xp_pickup_pool.total_value(), "relocation awards no XP")
	a.expect_true(sim.arena_object_system.pickups.is_empty(), "relocation creates no loot")
	var entry_tick: int = elite.activation_tick
	elite.position = sim.player_position + Vector2.RIGHT * 2.0
	sim.state.combat_tick = entry_tick
	var hit: CombatEvent = sim.event_router.create_primary(sim.state, &"weapon_hit", -1, &"homing_core", hp + 1.0)
	sim._apply_enemy_hit_records([{"entity_id": elite_id, "event": hit}])
	sim._process_pending_deaths(entry_tick)
	sim._process_pending_deaths(entry_tick)
	a.expect_equal(1, sim.arena_object_system.chest_transforms().size(), "the relocated elite leaves one chest on its actual death")


func test_enemy_retention_follows_body_radius_and_camera_changes(a: Variant, _context: Dictionary) -> void:
	var catalog: DefinitionCatalog = _catalog(a)
	catalog.enemy_for_type(GameTypes.EnemyType.PURSUER).body_radius = 0.25
	catalog.enemy_for_type(GameTypes.EnemyType.BULWARK).body_radius = 2.0
	var state: RunState = RunStateFactory.create(8110, catalog)
	state.stop_until_tick = 100
	var view := ArenaView.new()
	var system := EnemySystem.new()
	system.initialize(state, catalog, view)
	var margin: float = catalog.manifest().spawn.offscreen_band_width + catalog.manifest().spawn.despawn_margin
	# Reuse the system across translation, resize, origin shift and another resize.
	for frame: Array in [
		[Vector2i(1920, 1080), Vector2.ZERO, Vector2.ZERO],
		[Vector2i(1920, 1080), Vector2(120, -80), Vector2.ZERO],
		[Vector2i(1080, 1920), Vector2(120, -80), Vector2.ZERO],
		[Vector2i(1080, 1920), Vector2(120, -80), Vector2(1024, -1024)],
		[Vector2i(2560, 1080), Vector2(-400, 800), Vector2.ZERO],
	]:
		system.enemy_store.clear()
		view.viewport_size = frame[0]
		view.reset(frame[1])
		view.shift_origin(frame[2])
		var player: Vector2 = frame[1] - frame[2]
		var small_bounds: Rect2 = view.body_view_rect(0.25).grow(margin)
		var large_bounds: Rect2 = view.body_view_rect(2.0).grow(margin)
		var between_edges := Vector2((small_bounds.end.x + large_bounds.end.x) * 0.5, player.y)
		var ids: Array[int] = []
		for entry: Array in [
			[GameTypes.EnemyType.PURSUER, between_edges],
			[GameTypes.EnemyType.BULWARK, between_edges],
			[GameTypes.EnemyType.PURSUER, player],
		]:
			var kind: GameTypes.EnemyType = entry[0]
			var enemy: EnemyEntity = system.enemy_store.try_spawn(state, kind, catalog.enemy_for_type(kind), entry[1], 1.0, 1.0, 0)
			ids.append(enemy.entity_id)
		# Separate updates can occur at the same tick after changing the view.
		system.advance_snapshot(ids, player, 1)
		a.expect_false(system.enemy_store.has_entity(ids[0]), "a small body beyond its current retention edge despawns")
		a.expect_true(system.enemy_store.has_entity(ids[1]), "a larger body at the same position remains within its own edge")
		a.expect_true(system.enemy_store.has_entity(ids[2]), "another small body inside the view remains active")


func test_boss_charge_cadence_and_latches(assertions: Variant, _context: Dictionary) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	if catalog == null:
		return
	var state: RunState = RunStateFactory.create(8105, catalog)
	var system := EnemySystem.new()
	system.initialize(state, catalog)
	state.combat_tick = BalanceTestFixtures.catalog().boss_start_tick
	var spawned: Array[EnemyEntity] = system.resolve_stage_events(
		Vector2.ZERO,
		BalanceTestFixtures.catalog().boss_start_tick,
	)
	var boss: EnemyEntity = spawned[0]
	var spawn_position: Vector2 = boss.position
	var boss_ids: Array[int] = [boss.entity_id]
	var projectile_pool := ProjectilePool.new()
	projectile_pool.configure(catalog.manifest().combat.projectile_pool_capacity, system.enemy_store.world)
	var phase_one_interval: int = system._boss_action_interval_ticks(120, 1)
	var phase_two_interval: int = system._boss_action_interval_ticks(120, 2)
	var phase_three_interval: int = system._boss_action_interval_ticks(120, 3)
	assertions.expect_equal(110, phase_one_interval, "phase-one action rate rounds up to 110 ticks")
	assertions.expect_equal(82, phase_two_interval, "phase-two action rate rounds up to 82 ticks")
	assertions.expect_equal(62, phase_three_interval, "phase-three action rate rounds up to 62 ticks")

	state.combat_tick = boss.activation_tick - 1
	system.advance_snapshot(boss_ids, Vector2(6.0, 0.0), state.combat_tick)
	system.resolve_ready_enemy_special_actions(boss_ids, Vector2.ZERO, state.combat_tick, projectile_pool)
	assertions.expect_equal(spawn_position, boss.position, "boss stays at its entry position through the final inactive tick")
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
	assertions.expect_true(boss.position.distance_to(Vector2(6, 0)) < spawn_position.distance_to(Vector2(6, 0)), "active boss directly pursues the player while charging")
	var projectile_entries: PackedInt64Array = projectile_pool.snapshot_active()
	for offset: int in range(0, projectile_entries.size(), 2):
		var entry: PackedInt64Array = projectile_entries.slice(offset, offset + 2)
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
	var shifted_entry: PackedInt64Array = projectile_pool.snapshot_active().slice(16, 18)
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


func _assert_entry_contract(assertions: Variant, entry_ticks: int) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	if catalog == null:
		return
	var state: RunState = RunStateFactory.create(8101, catalog)
	var store := EnemyStore.new()
	store.configure(8)
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


func _body_intersects_screen(view: ArenaView, position: Vector2, body_radius: float) -> bool:
	var bounds := AABB(
		Vector3(position.x - body_radius, 0.0, position.y - body_radius),
		Vector3(body_radius * 2.0, body_radius * 2.0 + 1.0, body_radius * 2.0),
	)
	var points := PackedVector2Array()
	for index: int in 8:
		var point: Vector2 = view.project_position(bounds.get_endpoint(index))
		if not point.is_finite():
			return true
		points.append(point)
	var dimensions := Vector2(view.viewport_size)
	var screen := PackedVector2Array([
		Vector2.ZERO, Vector2(dimensions.x, 0.0), dimensions, Vector2(0.0, dimensions.y),
	])
	# The projected body's bounding rectangle can overlap a screen corner while
	# the entire body stays outside. Check its convex silhouette instead.
	return not Geometry2D.intersect_polygons(Geometry2D.convex_hull(points), screen).is_empty()


func _catalog(assertions: Variant) -> DefinitionCatalog:
	var catalog := DefinitionCatalog.new()
	assertions.expect_true(catalog.validate_manifest(BalanceTestFixtures.manifest()), "content catalog validates")
	return catalog if catalog.is_valid else null
