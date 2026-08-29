extends RefCounted


func test_names() -> PackedStringArray:
	return PackedStringArray([
		"uniform_grid_circle_and_clamp",
		"uniform_grid_segment_and_weapon_queries",
		"projectile_pool_generation_order",
		"combat_event_router_chain_contract",
	])


func run_test(test_name: String, assertions: Variant, _context: Dictionary) -> void:
	match test_name:
		"uniform_grid_circle_and_clamp":
			_test_uniform_grid_circle_and_clamp(assertions)
		"uniform_grid_segment_and_weapon_queries":
			_test_uniform_grid_segment_and_weapon_queries(assertions)
		"projectile_pool_generation_order":
			_test_projectile_pool_generation_order(assertions)
		"combat_event_router_chain_contract":
			_test_combat_event_router_chain_contract(assertions)
		_:
			assertions.expect_true(false, "registered combat core test")


func _test_uniform_grid_circle_and_clamp(assertions: Variant) -> void:
	var grid := UniformGrid.new()
	grid.insert(10, Vector2(4.1, 0.0))
	grid.insert(11, Vector2(4.11, 0.0))
	var keys: Array[int] = grid.occupied_keys_for_aabb(Vector2(-4.1, -4.1), Vector2(4.1, 4.1))
	assertions.expect_true(keys.size() > 9, "radius 4.1 query spans beyond fixed 3x3")
	var candidates: Array[int] = grid.query_circle_candidates(Vector2.ZERO, 4.1, 0.0)
	assertions.expect_true(10 in candidates, "4.1 boundary candidate included")
	assertions.expect_true(11 in candidates, "broad phase retains nearby non-hit candidate")
	assertions.expect_true(
		CombatGeometry.circle_intersects(Vector2.ZERO, 4.1, Vector2(4.1, 0.0), 0.0),
		"4.1 exact boundary included",
	)
	assertions.expect_false(
		CombatGeometry.circle_intersects(Vector2.ZERO, 4.1, Vector2(4.11, 0.0), 0.0),
		"4.11 exact point excluded",
	)
	var clamped: Rect2i = grid.clamped_cell_range(Vector2(-20.0, -12.0), Vector2(20.0, 12.0))
	assertions.expect_equal(Vector2i.ZERO, clamped.position, "outlying AABB minimum clamped")
	assertions.expect_equal(
		Vector2i(UniformGrid.COLUMN_COUNT, UniformGrid.ROW_COUNT),
		clamped.size,
		"outlying AABB maximum clamped",
	)
	assertions.expect_equal(
		Rect2i(),
		grid.clamped_cell_range(Vector2(15.01, -1.0), Vector2(18.0, 1.0)),
		"AABB wholly outside arena has an empty cell range",
	)
	assertions.expect_equal(
		[],
		grid.query_aabb_candidates(Vector2(15.01, -1.0), Vector2(18.0, 1.0)),
		"AABB wholly outside arena returns no boundary-cell candidates",
	)


func _test_uniform_grid_segment_and_weapon_queries(assertions: Variant) -> void:
	var line_grid := UniformGrid.new()
	line_grid.insert(9, Vector2(-14.9, -8.9))
	line_grid.insert(3, Vector2.ZERO)
	line_grid.insert(1, Vector2(14.9, 8.9))
	line_grid.insert(7, Vector2(-14.0, 8.0))
	var line_candidates: Array[int] = line_grid.query_segment_candidates(
		Vector2(-14.9, -8.9),
		Vector2(14.9, 8.9),
		0.0,
	)
	assertions.expect_equal([9, 3, 7, 1], line_candidates, "segment candidates use cell_key then entity_id order")
	var exact_hits: Array[int] = []
	var positions: Dictionary[int, Vector2] = {
		9: Vector2(-14.9, -8.9),
		3: Vector2.ZERO,
		7: Vector2(-14.0, 8.0),
		1: Vector2(14.9, 8.9),
	}
	for entity_id: int in line_candidates:
		if CombatGeometry.segment_circle_first_t(
			Vector2(-14.9, -8.9),
			Vector2(14.9, 8.9),
			positions[entity_id],
			0.2,
		) >= 0.0:
			exact_hits.append(entity_id)
	assertions.expect_equal([9, 3, 1], exact_hits, "exact segment-circle filters broad phase")

	var bow_grid := UniformGrid.new()
	bow_grid.insert(20, Vector2(13.9, 0.0))
	assertions.expect_true(
		20 in bow_grid.query_circle_candidates(Vector2.ZERO, 14.0, 1.25),
		"bow 14m search is not fixed 3x3",
	)

	var staff_grid := UniformGrid.new()
	staff_grid.insert(30, Vector2(5.75, 0.0))
	assertions.expect_true(
		30 in staff_grid.query_circle_candidates(Vector2.ZERO, 4.5, 1.25),
		"staff padded AABB reaches boss in another cell",
	)
	assertions.expect_true(
		Vector2(5.75, 0.0).x > 4.5,
		"boss center lies outside effect-only AABB",
	)
	assertions.expect_true(
		CombatGeometry.circle_intersects(Vector2.ZERO, 4.5, Vector2(5.75, 0.0), 1.25),
		"staff 4.5 plus boss 1.25 boundary hits",
	)
	assertions.expect_false(
		CombatGeometry.circle_intersects(Vector2.ZERO, 4.5, Vector2(5.7501, 0.0), 1.25),
		"staff boundary plus 0.0001 misses",
	)

	var fast_grid := UniformGrid.new()
	fast_grid.insert(40, Vector2(10.0, 0.0))
	assertions.expect_true(
		40 in fast_grid.query_segment_candidates(Vector2(-12.0, 0.0), Vector2(12.0, 0.0), 1.45),
		"fast projectile query crosses every traversed cell",
	)
	assertions.expect_true(
		CombatGeometry.segment_circle_first_t(Vector2(-5.0, 0.0), Vector2(5.0, 0.0), Vector2(0.0, 1.45), 0.2 + 1.25) >= 0.0,
		"ally arrow hits boss at 1.45 boundary",
	)
	assertions.expect_true(
		CombatGeometry.segment_circle_first_t(Vector2(-5.0, 0.0), Vector2(5.0, 0.0), Vector2(0.0, 1.4501), 0.2 + 1.25) < 0.0,
		"ally arrow misses boss beyond individual radius",
	)
	assertions.expect_true(
		CombatGeometry.segment_circle_first_t(Vector2(-5.0, 0.0), Vector2(5.0, 0.0), Vector2(0.0, 0.70), 0.25 + 0.45) >= 0.0,
		"enemy projectile hits player at 0.70 boundary",
	)
	assertions.expect_true(
		CombatGeometry.segment_circle_first_t(Vector2(-5.0, 0.0), Vector2(5.0, 0.0), Vector2(0.0, 0.7001), 0.25 + 0.45) < 0.0,
		"enemy projectile misses player beyond individual radius",
	)


func _test_projectile_pool_generation_order(assertions: Variant) -> void:
	var pool := ProjectilePool.new()
	for index: int in range(ProjectilePool.CAPACITY):
		pool.slots[index].active = not index in [2, 7, 9]
	var first: ProjectileState = _acquire_fixture_projectile(pool, 10)
	var second: ProjectileState = _acquire_fixture_projectile(pool, 10)
	var third: ProjectileState = _acquire_fixture_projectile(pool, 10)
	assertions.expect_equal(2, first.pool_index, "projectile first lowest free index")
	assertions.expect_equal(7, second.pool_index, "projectile second lowest free index")
	assertions.expect_equal(9, third.pool_index, "projectile third lowest free index")
	var old_generation: int = first.generation
	var old_snapshot := Vector2i(first.pool_index, old_generation)
	assertions.expect_true(pool.release(2, old_generation), "snapshot generation released")
	var replacement: ProjectileState = _acquire_fixture_projectile(pool, 10)
	assertions.expect_equal(2, replacement.pool_index, "released minimum index reused")
	assertions.expect_equal(old_generation + 1, replacement.generation, "generation increments before reuse")
	assertions.expect_equal(null, pool.resolve_snapshot_entry(old_snapshot), "old snapshot cannot resolve new generation")
	assertions.expect_equal(10, replacement.born_physics_tick, "replacement records born tick")
	assertions.expect_false(replacement.born_physics_tick < 10, "replacement excluded during born tick")
	assertions.expect_true(replacement.born_physics_tick < 11, "replacement eligible next tick")


func _test_combat_event_router_chain_contract(assertions: Variant) -> void:
	var state := RunState.new()
	var router := CombatEventRouter.new()
	var primary: CombatEvent = router.create_primary(
		state,
		&"damage",
		1,
		&"weapon:bow",
		12.0,
	)
	assertions.expect_true(primary.is_primary, "primary marker")
	assertions.expect_equal(&"", primary.proc_effect_id, "primary proc empty")
	assertions.expect_equal(PackedStringArray(), primary.effect_chain, "primary chain empty")
	assertions.expect_equal(0, primary.chain_depth, "primary depth zero")
	var echo: CombatEvent = router.create_secondary(
		state,
		primary,
		&"damage",
		1,
		&"weapon:bow",
		&"unique:echo_gauntlet",
		12.0,
	)
	assertions.expect_true(echo != null, "same source effect allowed for secondary")
	assertions.expect_equal(PackedStringArray(["unique:echo_gauntlet"]), echo.effect_chain, "secondary stores proc only")
	var duplicate: CombatEvent = router.create_secondary(
		state,
		echo,
		&"damage",
		1,
		&"different:payload",
		&"unique:echo_gauntlet",
		12.0,
	)
	assertions.expect_equal(null, duplicate, "duplicate proc rejected regardless of source")
	var cursor: CombatEvent = echo
	for depth: int in range(2, 17):
		cursor = router.create_secondary(
			state,
			cursor,
			&"damage",
			depth,
			StringName("payload:%d" % depth),
			StringName("proc:%d" % depth),
			1.0,
		)
		assertions.expect_true(cursor != null, "secondary depth %d accepted" % depth)
	assertions.expect_equal(16, cursor.chain_depth, "depth 16 event exists")
	var too_deep: CombatEvent = router.create_secondary(
		state,
		cursor,
		&"damage",
		99,
		&"payload:deep",
		&"proc:deep",
		1.0,
	)
	assertions.expect_equal(null, too_deep, "depth 16 refuses additional generation")
	assertions.expect_equal(1, router.chain_depth_overflow_count, "depth overflow counter")


func _acquire_fixture_projectile(pool: ProjectilePool, born_tick: int) -> ProjectileState:
	return pool.acquire(
		ProjectileState.FACTION_ALLY,
		&"bow",
		-1,
		Vector2.ZERO,
		Vector2.RIGHT,
		0.2,
		12.0,
		14.0,
		1.0,
		Vector2.RIGHT,
		1,
		born_tick,
	)
