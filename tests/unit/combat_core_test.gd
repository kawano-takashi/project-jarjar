extends RefCounted


func test_survival_pool_active_free_index_contract(assertions: Variant, _context: Dictionary) -> void:
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
	var first_enemy_id: int = first_enemy.entity_id
	var retained_ids: Array[int] = enemy_pool.snapshot_ids_sorted()
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
	assertions.expect_equal([first_enemy_id], retained_ids, "spawn and removal cannot rewrite a retained tick-start snapshot")


func test_xp_pool_overflow_merges_without_loss(assertions: Variant, _context: Dictionary) -> void:
	var pool := BalanceTestFixtures.xp_pool()
	for index: int in range(pool.capacity):
		pool.acquire(Vector2(float(index % 40), float(floori(float(index) / 40.0))), 1, 0, Vector2.ZERO)
	var total_before: int = pool.total_value()
	var merged: XpPickupState = pool.acquire(Vector2(19.0, 19.0), 17, 1, Vector2.ZERO)
	assertions.expect_true(merged != null, "overflow resolves to a far pickup")
	assertions.expect_equal(pool.capacity, pool.active_count(), "overflow does not exceed the 2048 crystal cap")
	assertions.expect_equal(total_before + 17, pool.total_value(), "overflow XP is merged without losing value")
	assertions.expect_equal(1, pool.overflow_merge_count, "overflow merge is observable")


func test_xp_collection_keeps_swap_order_and_tracks_relocated_pickups(a: Variant, _context: Dictionary) -> void:
	var balance: ProgressionBalanceDefinition = BalanceTestFixtures.manifest().progression
	balance.xp_pool_capacity = 4
	balance.xp_pickup_attract_radius = 2.0
	balance.xp_pickup_collect_radius = 0.1
	balance.xp_pickup_speed = 1.0
	var pool := XpPickupPool.new()
	pool.configure(balance)
	var first: XpPickupState = pool.acquire(Vector2.ZERO, 1, 0, Vector2.ZERO)
	var remote: XpPickupState = pool.acquire(Vector2(100.0, 0.0), 2, 0, Vector2.ZERO)
	pool.acquire(Vector2(2.0, 0.0), 4, 0, Vector2.ZERO)
	var last: XpPickupState = pool.acquire(Vector2.ZERO, 8, 0, Vector2.ZERO)
	var last_index: int = last.pool_index
	a.expect_equal(9, pool.advance_and_collect(Vector2.ZERO, 0.0, 1), "collection includes the last slot swapped into the first position")
	a.expect_false(first.active or last.active, "both collected handles are released")
	var reused: XpPickupState = pool.acquire(Vector2(1.0, 0.0), 16, 2, Vector2.ZERO)
	a.expect_equal(last_index, reused.pool_index, "collection retains the original free-slot reuse order")
	remote.position = Vector2.ZERO
	a.expect_equal(2, pool.advance_and_collect(Vector2.ZERO, 0.0, 2), "direct relocation is reflected in the collection candidates")
	a.expect_equal(Vector2(1.0, 0.0), reused.position, "a newly born pickup is not advanced")
	pool.advance_and_collect(Vector2.ZERO, 0.5, 3)
	a.expect_equal(Vector2(0.5, 0.0), reused.position, "a swapped survivor moves once per tick")
	pool.begin_vacuum()
	a.expect_equal(20, pool.advance_and_collect(Vector2.ZERO, 100.0, 4), "vacuum collection reaches every remaining slot")
	a.expect_equal(0, pool.orphan_count(), "spatial collection preserves active/free pool ownership")





func test_segment_tick_boundaries(assertions: Variant, _context: Dictionary) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	if catalog == null:
		return
	for index: int in range(catalog.segment_end_ticks.size()):
		var start_tick: int = catalog.segment_start_ticks[index]
		var end_tick: int = catalog.segment_end_ticks[index]
		assertions.expect_equal(catalog.segment(index), catalog.segment_for_tick(start_tick), "segment begins on its configured first tick")
		assertions.expect_equal(catalog.segment(index), catalog.segment_for_tick(end_tick - 1), "segment owns the tick before its exclusive end")
		assertions.expect_equal(index + 1 if index + 1 < catalog.segments.size() else -1, catalog.segment_index_for_tick(end_tick), "exclusive end selects the next segment or boss phase")


func test_node_spawning_replaces_only_hidden_objects_and_uses_unique_ids(a: Variant, _context: Dictionary) -> void:
	var content: SurvivalContentManifest = BalanceTestFixtures.manifest()
	content.arena.node_initial_count = 2
	content.arena.node_capacity = 3
	content.arena.node_spawn_interval_ticks = 3
	content.arena.node_spawn_chance = 1.0
	content.arena.node_spawn_chance_max = 1.0
	var catalog := DefinitionCatalog.new()
	a.expect_true(catalog.validate_manifest(content), catalog.error_text)
	var state: RunState = RunStateFactory.create(7201, catalog)
	var nodes := ArenaObjectSystem.new()
	nodes.initialize(state, catalog)
	var reward_rng: int = state.rng_streams.powerup_rng.state
	nodes.advance(2)
	a.expect_equal(2, nodes.active_node_count(), "no attempt occurs before its tick interval")
	nodes.advance(3)
	a.expect_equal(3, nodes.active_node_count(), "a successful timed attempt fills the remaining capacity")
	for index: int in nodes.nodes.size():
		nodes.nodes[index].position = Vector2(index * 2.0, 0)
	var ids: Array[int] = []
	for node: ArenaNodeState in nodes.nodes:
		ids.append(node.node_id)
	nodes.advance(6)
	for index: int in ids.size():
		a.expect_equal(ids[index], nodes.nodes[index].node_id, "visible objects are never replaced at capacity")
	nodes.nodes[0].position = Vector2(100, 0)
	nodes.nodes[1].position = Vector2(200, 0)
	nodes.advance(9)
	a.expect_equal(ids[0], nodes.nodes[0].node_id, "nearer hidden object stays")
	a.expect_not_equal(ids[1], nodes.nodes[1].node_id, "farthest hidden object is replaced")
	a.expect_equal(0, nodes.destroyed_node_count, "replacement is not destruction")
	a.expect_equal(reward_rng, state.rng_streams.powerup_rng.state, "spawning consumes no drop RNG")
	var node: ArenaNodeState = nodes.nodes[1]
	node.position = Vector2.ZERO
	var hits: Dictionary[int, bool] = {node.node_id: true}
	nodes.damage_nodes_circle(Vector2.ZERO, 0.0, content.arena.node_max_hp, 10)
	nodes.advance(12)
	var fresh: ArenaNodeState = nodes.nodes[1]
	fresh.position = Vector2(50, 50)
	var hp: float = fresh.hp
	nodes.damage_nodes_segment(Vector2(49, 50), Vector2(51, 50), 0.1, 1.0, 13, hits)
	a.expect_float(hp - 1.0, fresh.hp, "a projectile can hit a new individual in a reused slot")
	var spawn_rng: int = state.rng_streams.node_spawn_rng.state
	state.phase = GameTypes.RunPhase.LEVEL_UP
	nodes.advance(15)
	a.expect_equal(spawn_rng, state.rng_streams.node_spawn_rng.state, "selection screens do not advance spawn RNG")


func test_all_weapon_behaviors_generate_attacks(assertions: Variant, _context: Dictionary) -> void:
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
			catalog.lineage_for_weapon(definition.weapon_id),
			definition.is_evolved,
			state.rng_streams.create_weapon_rng(catalog.lineage_for_weapon(definition.weapon_id), 0),
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


func test_resonance_wave_sweeps_both_sides_and_amount_adds_damage(assertions: Variant, _context: Dictionary) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	if catalog == null:
		return
	var state: RunState = RunStateFactory.create(7301, catalog)
	state.weapons.clear()
	var definition: WeaponDefinition = catalog.weapon(&"resonance_wave")
	state.weapons.append(RunWeapon.create(
		definition.weapon_id,
		catalog.lineage_for_weapon(definition.weapon_id),
		false,
		state.rng_streams.create_weapon_rng(catalog.lineage_for_weapon(definition.weapon_id), 0),
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


func test_arc_projectile_snapshot_follows_a_parabolic_lob(assertions: Variant, _context: Dictionary) -> void:
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


func test_homing_core_levels_emit_sequential_straight_bursts(assertions: Variant, _context: Dictionary) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	if catalog == null:
		return
	var definition: WeaponDefinition = catalog.weapon(&"homing_core")
	var levels := PackedInt32Array([1, 2, 4, 6, 8])
	var expected_amounts := PackedInt32Array([1, 2, 3, 4, 5])
	for level_index: int in range(levels.size()):
		var level: int = levels[level_index]
		var expected_amount: int = expected_amounts[level_index]
		var setup: Dictionary = _homing_fixture(catalog, 7304 + level, &"homing_core", level)
		var simulation: CombatSimulation = setup["simulation"]
		var runtime: RunWeapon = setup["runtime"]
		var target: EnemyEntity = simulation.spawn_fixture_enemy(
			GameTypes.EnemyType.BOSS,
			Vector2(4.0, 0.0),
			-1,
		)
		target.max_hp = 1_000_000.0
		target.hp = target.max_hp
		var expected_ticks := PackedInt32Array()
		for shot_index: int in range(expected_amount):
			expected_ticks.append(1 + shot_index * BalanceTestFixtures.catalog().manifest().combat.homing_burst_interval_ticks)
		var observed_ticks := PackedInt32Array()
		var final_tick: int = expected_ticks[expected_ticks.size() - 1]
		for current_tick: int in range(1, final_tick + 1):
			var attacks: Array[Dictionary] = simulation.weapon_system.advance_and_fire(
				Vector2.ZERO,
				simulation.enemy_system.enemy_store,
				simulation.enemy_system.uniform_grid,
				current_tick,
			)
			if not attacks.is_empty():
				observed_ticks.append(current_tick)
			if current_tick == 1:
				assertions.expect_equal(
					definition.cooldown_ticks_at(level),
					runtime.cooldown_remaining_ticks,
					"level %d cooldown starts with its first shot" % level,
				)
		assertions.expect_equal(
			expected_ticks,
			observed_ticks,
			"level %d emits its amount as one shot every six ticks" % level,
		)
		assertions.expect_equal(
			expected_amount,
			simulation.projectile_pool.active_count(),
			"level %d creates exactly its configured projectile amount" % level,
		)
		assertions.expect_equal(
			maxi(0, definition.cooldown_ticks_at(level) - final_tick + 1),
			runtime.cooldown_remaining_ticks,
			"level %d cooldown continues while later shots are emitted" % level,
		)
		for entry: Vector2i in simulation.projectile_pool.snapshot_active():
			var projectile: ProjectileState = (
				simulation.projectile_pool.resolve_snapshot_entry(entry)
			)
			assertions.expect_equal(
				ProjectileState.MovementKind.STRAIGHT,
				projectile.movement_kind,
				"base homing core projectiles become straight flights",
			)
			assertions.expect_equal(
				target.entity_id,
				projectile.target_entity_id,
				"a valid burst target remains locked across later shots",
			)


func test_homing_core_burst_locks_and_reacquires_before_launch(assertions: Variant, _context: Dictionary) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	if catalog == null:
		return
	var setup: Dictionary = _homing_fixture(catalog, 7314, &"homing_core", 8)
	var simulation: CombatSimulation = setup["simulation"]
	var first_target: EnemyEntity = simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.BULWARK,
		Vector2(3.0, 0.0),
		-1,
	)
	var closer_later: EnemyEntity = simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.BULWARK,
		Vector2(5.0, 2.0),
		-1,
	)
	var death_replacement: EnemyEntity = simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.BULWARK,
		Vector2(-5.0, 0.0),
		-1,
	)
	var burst_targets: Array[EnemyEntity] = [
		first_target,
		closer_later,
		death_replacement,
	]
	for enemy: EnemyEntity in burst_targets:
		enemy.max_hp = 1_000_000.0
		enemy.hp = enemy.max_hp
	simulation.weapon_system.advance_and_fire(
		Vector2.ZERO,
		simulation.enemy_system.enemy_store,
		simulation.enemy_system.uniform_grid,
		1,
	)
	var first_shot: ProjectileState = _projectile_born_at(simulation, 1)
	assertions.expect_equal(first_target.entity_id, first_shot.target_entity_id, "burst starts on the nearest target")
	closer_later.position = Vector2(1.0, 0.5)
	for current_tick: int in range(2, 8):
		simulation.weapon_system.advance_and_fire(
			Vector2(1.0, 0.0),
			simulation.enemy_system.enemy_store,
			simulation.enemy_system.uniform_grid,
			current_tick,
		)
	var locked_shot: ProjectileState = _projectile_born_at(simulation, 7)
	assertions.expect_equal(first_target.entity_id, locked_shot.target_entity_id, "a closer enemy does not replace a living in-range burst target")
	assertions.expect_equal(Vector2(1.0, 0.0), locked_shot.position, "later shots use the current player position")
	first_target.position = Vector2(20.0, 0.0)
	closer_later.position = Vector2(2.0, 2.0)
	for current_tick: int in range(8, 14):
		simulation.weapon_system.advance_and_fire(
			Vector2(2.0, 0.0),
			simulation.enemy_system.enemy_store,
			simulation.enemy_system.uniform_grid,
			current_tick,
		)
	var range_retargeted_shot: ProjectileState = _projectile_born_at(simulation, 13)
	assertions.expect_equal(closer_later.entity_id, range_retargeted_shot.target_entity_id, "an out-of-range target is replaced before the next shot")
	assertions.expect_equal(Vector2.DOWN, range_retargeted_shot.velocity.normalized(), "reacquired target direction is sampled at launch")
	closer_later.hp = 0.0
	death_replacement.position = Vector2.ZERO
	for current_tick: int in range(14, 20):
		simulation.weapon_system.advance_and_fire(
			Vector2(3.0, 0.0),
			simulation.enemy_system.enemy_store,
			simulation.enemy_system.uniform_grid,
			current_tick,
		)
	var death_retargeted_shot: ProjectileState = _projectile_born_at(simulation, 19)
	assertions.expect_equal(death_replacement.entity_id, death_retargeted_shot.target_entity_id, "a dead target is replaced before the next shot")
	var last_target_direction: Vector2 = death_retargeted_shot.velocity.normalized()
	death_replacement.hp = 0.0
	for current_tick: int in range(20, 26):
		simulation.weapon_system.advance_and_fire(
			Vector2(4.0, 0.0),
			simulation.enemy_system.enemy_store,
			simulation.enemy_system.uniform_grid,
			current_tick,
		)
	var no_target_shot: ProjectileState = _projectile_born_at(simulation, 25)
	assertions.expect_equal(-1, no_target_shot.target_entity_id, "remaining shots do not wait when every target disappears")
	assertions.expect_equal(last_target_direction, no_target_shot.velocity.normalized(), "remaining shots preserve the last nonzero aim direction")

	var empty_setup: Dictionary = _homing_fixture(catalog, 7315, &"homing_core", 8)
	var empty_simulation: CombatSimulation = empty_setup["simulation"]
	var empty_runtime: RunWeapon = empty_setup["runtime"]
	var empty_attacks: Array[Dictionary] = empty_simulation.weapon_system.advance_and_fire(
		Vector2.ZERO,
		empty_simulation.enemy_system.enemy_store,
		empty_simulation.enemy_system.uniform_grid,
		1,
	)
	assertions.expect_equal(0, empty_attacks.size(), "a burst waits when activation has no target")
	assertions.expect_equal(0, empty_runtime.cooldown_remaining_ticks, "waiting for an initial target consumes no cooldown")
	empty_simulation.spawn_fixture_enemy(GameTypes.EnemyType.BULWARK, Vector2.RIGHT, -1)
	var resumed_attacks: Array[Dictionary] = empty_simulation.weapon_system.advance_and_fire(
		Vector2.ZERO,
		empty_simulation.enemy_system.enemy_store,
		empty_simulation.enemy_system.uniform_grid,
		2,
	)
	assertions.expect_equal(1, resumed_attacks.size(), "the waiting burst starts immediately when a target appears")


func test_homing_core_projectile_flies_straight_and_hits_once(assertions: Variant, _context: Dictionary) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	if catalog == null:
		return
	var setup: Dictionary = _homing_fixture(catalog, 7316, &"homing_core", 1)
	var simulation: CombatSimulation = setup["simulation"]
	var original_target: EnemyEntity = simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.BULWARK,
		Vector2(3.0, 0.0),
		-1,
	)
	simulation.weapon_system.advance_and_fire(
		Vector2.ZERO,
		simulation.enemy_system.enemy_store,
		simulation.enemy_system.uniform_grid,
		1,
	)
	var entry: Vector2i = simulation.projectile_pool.snapshot_active()[0]
	var projectile: ProjectileState = simulation.projectile_pool.resolve_snapshot_entry(entry)
	var launch_velocity: Vector2 = projectile.velocity
	var launch_damage: float = projectile.damage
	original_target.hp = 0.0
	original_target.position = Vector2(0.0, 4.0)
	var interceptor: EnemyEntity = simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.BULWARK,
		Vector2(1.2, 0.0),
		-1,
	)
	var farther_enemy: EnemyEntity = simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.BULWARK,
		Vector2(2.2, 0.0),
		-1,
	)
	var records: Array[Dictionary] = []
	var moving_entries: Array[Vector2i] = [entry]
	for current_tick: int in range(2, 20):
		if simulation.projectile_pool.resolve_snapshot_entry(entry) == null:
			break
		simulation.weapon_system.move_snapshot_projectiles(
			moving_entries,
			simulation.enemy_system.enemy_store,
			Vector2.ZERO,
			current_tick,
			false,
		)
		projectile = simulation.projectile_pool.resolve_snapshot_entry(entry)
		assertions.expect_equal(launch_velocity, projectile.velocity, "launched homing core projectile never bends after target movement or death")
		records.append_array(simulation.weapon_system.resolve_ally_projectile(
			entry,
			simulation.enemy_system.enemy_store,
			simulation.enemy_system.uniform_grid,
			Vector2.ZERO,
			current_tick,
		))
	assertions.expect_equal(1, _hit_count_for(records, interceptor.entity_id), "the first enemy on the trajectory is hit exactly once")
	assertions.expect_equal(0, _hit_count_for(records, farther_enemy.entity_id), "the projectile does not bounce through to a later enemy")
	assertions.expect_equal(1, records.size(), "one homing core projectile emits one damage record")
	if not records.is_empty():
		var event: CombatEvent = records[0]["event"]
		assertions.expect_float(launch_damage, event.damage_snapshot, "the first contact receives the projectile's full launch damage")
	assertions.expect_equal(0, simulation.projectile_pool.active_count(), "the projectile disappears after its first valid contact")
	assertions.expect_equal(
		0,
		simulation.weapon_system.resolve_ally_projectile(
			entry,
			simulation.enemy_system.enemy_store,
			simulation.enemy_system.uniform_grid,
			Vector2.ZERO,
			20,
		).size(),
		"a consumed projectile cannot hit again",
	)


func test_homing_core_upgrades_restart_or_preserve_the_burst(assertions: Variant, _context: Dictionary) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	if catalog == null:
		return
	var passive_setup: Dictionary = _homing_fixture(catalog, 7317, &"homing_core", 2)
	var passive_simulation: CombatSimulation = passive_setup["simulation"]
	var passive_state: RunState = passive_setup["state"]
	passive_simulation.spawn_fixture_enemy(GameTypes.EnemyType.BOSS, Vector2(4.0, 0.0), -1)
	passive_simulation.weapon_system.advance_and_fire(
		Vector2.ZERO,
		passive_simulation.enemy_system.enemy_store,
		passive_simulation.enemy_system.uniform_grid,
		1,
	)
	var first_damage: float = _projectile_born_at(passive_simulation, 1).damage
	var amplifier := RunPassive.create(&"amplifier_core")
	amplifier.level = 1
	passive_state.passives.append(amplifier)
	for current_tick: int in range(2, 8):
		passive_simulation.weapon_system.advance_and_fire(
			Vector2.ZERO,
			passive_simulation.enemy_system.enemy_store,
			passive_simulation.enemy_system.uniform_grid,
			current_tick,
		)
	var upgraded_damage: float = _projectile_born_at(passive_simulation, 7).damage
	assertions.expect_float(first_damage * 1.1, upgraded_damage, "other upgrades preserve the burst and affect only shots that remain unfired")

	var level_setup: Dictionary = _homing_fixture(catalog, 7318, &"homing_core", 2)
	var level_simulation: CombatSimulation = level_setup["simulation"]
	var level_runtime: RunWeapon = level_setup["runtime"]
	level_simulation.spawn_fixture_enemy(GameTypes.EnemyType.BOSS, Vector2(4.0, 0.0), -1)
	level_simulation.weapon_system.advance_and_fire(
		Vector2.ZERO,
		level_simulation.enemy_system.enemy_store,
		level_simulation.enemy_system.uniform_grid,
		1,
	)
	level_runtime.level = 4
	level_runtime.ready_on_resume = true
	var restart_ticks := PackedInt32Array([1])
	for current_tick: int in range(2, 15):
		var attacks: Array[Dictionary] = level_simulation.weapon_system.advance_and_fire(
			Vector2.ZERO,
			level_simulation.enemy_system.enemy_store,
			level_simulation.enemy_system.uniform_grid,
			current_tick,
		)
		if not attacks.is_empty():
			restart_ticks.append(current_tick)
	assertions.expect_equal(PackedInt32Array([1, 2, 8, 14]), restart_ticks, "own level-up discards the old remainder and immediately starts the new three-shot burst")

	var evolution_setup: Dictionary = _homing_fixture(catalog, 7319, &"homing_core", 8)
	var evolution_simulation: CombatSimulation = evolution_setup["simulation"]
	var evolution_runtime: RunWeapon = evolution_setup["runtime"]
	evolution_simulation.spawn_fixture_enemy(GameTypes.EnemyType.BOSS, Vector2(4.0, 0.0), -1)
	evolution_simulation.weapon_system.advance_and_fire(
		Vector2.ZERO,
		evolution_simulation.enemy_system.enemy_store,
		evolution_simulation.enemy_system.uniform_grid,
		1,
	)
	evolution_runtime.weapon_id = &"infinite_homing"
	evolution_runtime.level = 1
	evolution_runtime.evolved = true
	evolution_runtime.ready_on_resume = true
	var evolved_attacks: Array[Dictionary] = evolution_simulation.weapon_system.advance_and_fire(
		Vector2.ZERO,
		evolution_simulation.enemy_system.enemy_store,
		evolution_simulation.enemy_system.uniform_grid,
		2,
	)
	assertions.expect_equal(1, evolved_attacks.size(), "evolution discards the old remainder and attacks immediately")
	assertions.expect_equal(0, evolution_simulation.weapon_system.deterministic_state_values()[1].size(), "evolution removes the base burst from deterministic state")
	assertions.expect_equal(ProjectileState.MovementKind.HOMING, _projectile_born_at(evolution_simulation, 2).movement_kind, "infinite homing retains in-flight tracking after evolution")


func test_arc_projectile_explodes_once_on_first_impact(assertions: Variant, _context: Dictionary) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	if catalog == null:
		return
	var state: RunState = RunStateFactory.create(7305, catalog)
	state.weapons.clear()
	var definition: WeaponDefinition = catalog.weapon(&"arc_crystal")
	state.weapons.append(RunWeapon.create(
		definition.weapon_id,
		catalog.lineage_for_weapon(definition.weapon_id),
		false,
		state.rng_streams.create_weapon_rng(catalog.lineage_for_weapon(definition.weapon_id), 0),
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
	var records: Array[Dictionary] = []
	for current_tick: int in range(2, 40):
		if simulation.projectile_pool.active_count() == 0:
			break
		simulation.weapon_system.move_snapshot_projectiles(
			entries,
			simulation.enemy_system.enemy_store,
			Vector2.ZERO,
			current_tick,
			false,
		)
		records.append_array(simulation.weapon_system.resolve_ally_projectile(
			entries[0],
			simulation.enemy_system.enemy_store,
			simulation.enemy_system.uniform_grid,
			Vector2.ZERO,
			current_tick,
		))
	assertions.expect_equal(1, _hit_count_for(records, first_enemy.entity_id), "first impact enemy receives one explosion hit")
	assertions.expect_equal(1, _hit_count_for(records, second_enemy.entity_id), "nearby enemy receives the same explosion once")
	assertions.expect_equal(0, simulation.projectile_pool.active_count(), "arc projectile is released after its single explosion")
	var repeated_records: Array[Dictionary] = simulation.weapon_system.resolve_ally_projectile(
		entries[0],
		simulation.enemy_system.enemy_store,
		simulation.enemy_system.uniform_grid,
		Vector2.ZERO,
		2,
	)
	assertions.expect_equal(0, repeated_records.size(), "released arc projectile cannot deal a double hit")


func test_arc_node_damage_uses_single_resolved_impact(assertions: Variant, _context: Dictionary) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	if catalog == null:
		return
	var node_position: Vector2 = Vector2(9.75, 9.75)

	var collision_simulation: CombatSimulation = _node_projectile_simulation(
		catalog,
		7351,
	)
	var collision_node: ArenaNodeState = collision_simulation.arena_object_system.nodes[0]
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
		BalanceTestFixtures.catalog().manifest().arena.node_max_hp,
		collision_node.hp,
		"arc flight through a later node deals no segment damage before enemy impact",
	)
	assertions.expect_true(blocker.hp < blocker.max_hp, "the earlier enemy receives the resolved arc explosion")
	assertions.expect_equal(0, collision_simulation.projectile_pool.active_count(), "enemy impact consumes the arc projectile")

	var impact_simulation: CombatSimulation = _node_projectile_simulation(
		catalog,
		7354,
	)
	var impact_node: ArenaNodeState = impact_simulation.arena_object_system.nodes[0]
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
	var landing_node: ArenaNodeState = landing_simulation.arena_object_system.nodes[0]
	_acquire_node_probe(
		landing_simulation,
		ProjectileState.MovementKind.ARC,
		Vector2(0.0, node_position.y),
		Vector2(780.0, 0.0),
		node_position.x,
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
	var straight_node: ArenaNodeState = straight_simulation.arena_object_system.nodes[0]
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


func test_mass_projectile_requires_an_in_range_target(assertions: Variant, _context: Dictionary) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	if catalog == null:
		return
	var state: RunState = RunStateFactory.create(7306, catalog)
	state.weapons.clear()
	var definition: WeaponDefinition = catalog.weapon(&"mass_projectile")
	var runtime := RunWeapon.create(
		definition.weapon_id,
		catalog.lineage_for_weapon(definition.weapon_id),
		false,
		state.rng_streams.create_weapon_rng(catalog.lineage_for_weapon(definition.weapon_id), 0),
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
		Vector2(5.0, 0.0),
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


func test_directional_projectile_preserves_last_nonzero_move_direction(assertions: Variant, _context: Dictionary) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	if catalog == null:
		return
	var state: RunState = RunStateFactory.create(7308, catalog)
	state.weapons.clear()
	var definition: WeaponDefinition = catalog.weapon(&"directional_needle")
	state.weapons.append(RunWeapon.create(
		definition.weapon_id,
		catalog.lineage_for_weapon(definition.weapon_id),
		false,
		state.rng_streams.create_weapon_rng(catalog.lineage_for_weapon(definition.weapon_id), 0),
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


func test_returning_ring_uses_explicit_outbound_range_and_hits_on_return(assertions: Variant, _context: Dictionary) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	if catalog == null:
		return
	var state: RunState = RunStateFactory.create(7307, catalog)
	state.weapons.clear()
	var definition: WeaponDefinition = catalog.weapon(&"returning_ring")
	var runtime := RunWeapon.create(
		definition.weapon_id,
		catalog.lineage_for_weapon(definition.weapon_id),
		false,
		state.rng_streams.create_weapon_rng(catalog.lineage_for_weapon(definition.weapon_id), 0),
	)
	state.weapons.append(runtime)
	var outward_reach: float = definition.range_at(1)
	assertions.expect_float(5.5, outward_reach, "level one returning ring uses the explicit outbound range")
	var simulation := CombatSimulation.new()
	simulation.initialize(state, catalog)
	var target: EnemyEntity = simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.BULWARK,
		Vector2(outward_reach, 0.0),
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
	var initial_projectile: ProjectileState = simulation.projectile_pool.resolve_snapshot_entry(
		simulation.projectile_pool.snapshot_active()[0]
	)
	assertions.expect_float(
		outward_reach,
		initial_projectile.outbound_distance_remaining,
		"returning projectile stores its exact outbound turn range",
	)
	assertions.expect_float(
		outward_reach * 2.0,
		initial_projectile.remaining_distance,
		"returning projectile total path is bounded to out-and-back range",
	)
	for current_tick: int in range(2, definition.duration_ticks_at(1) + 4):
		if current_tick > ceili(outward_reach / definition.projectile_speed_at(1) * 60.0):
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
				moving_player_position,
				current_tick,
			)
			var target_hit_count: int = _hit_count_for(records, target.entity_id)
			if returning:
				return_hit_count += target_hit_count
			else:
				outward_hit_count += target_hit_count
	assertions.expect_equal(1, outward_hit_count, "returning ring hits the target once on the outward phase")
	assertions.expect_equal(1, return_hit_count, "moving the player during return does not repeatedly clear the returning hit set")


func test_infinite_homing_configured_cadence_stays_within_pool(assertions: Variant, _context: Dictionary) -> void:
	for cooldown_ticks: int in [1, 7]:
		_assert_infinite_homing_cadence(assertions, cooldown_ticks)


func test_orbital_active_window_uses_duration_and_has_real_gaps(assertions: Variant, _context: Dictionary) -> void:
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
	assertions.expect_true(evolved_simulation.weapon_system.orbital_is_active(&"orbital_array", BalanceTestFixtures.catalog().boss_start_tick * 2), "eternal orbit has no gameplay or visual gap through an unlimited boss fight")
	assertions.expect_equal(8, evolved_simulation.weapon_system.orbital_transforms(Vector2.ZERO, BalanceTestFixtures.catalog().boss_start_tick * 2).size(), "eternal orbit continuously renders every evolved orb")
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


func _assert_infinite_homing_cadence(assertions: Variant, cooldown_ticks: int) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	if catalog == null:
		return
	# Stress one-tick fire and verify a longer interval using detached inputs.
	var definition: WeaponDefinition = catalog.weapon(&"infinite_homing")
	definition.cooldown_ticks_by_level = PackedInt32Array([cooldown_ticks])
	assertions.expect_true(catalog.validate_manifest(catalog.manifest()), "homing cadence fixture validates: %s" % catalog.error_text)
	if not catalog.is_valid:
		return
	var state: RunState = RunStateFactory.create(7303, catalog)
	state.weapons.clear()
	state.weapons.append(RunWeapon.create(
		definition.weapon_id,
		catalog.lineage_for_weapon(definition.weapon_id),
		true,
		state.rng_streams.create_weapon_rng(catalog.lineage_for_weapon(definition.weapon_id), 0),
	))
	var simulation := CombatSimulation.new()
	simulation.initialize(state, catalog)
	var target: EnemyEntity = simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.BOSS,
		Vector2(7.5, 0.0),
		-1,
	)
	target.max_hp = 1_000_000.0
	target.hp = target.max_hp
	var generated_count: int = 0
	for current_tick: int in range(1, 601):
		if current_tick == 2:
			target.position = Vector2(0.0, 7.5)
		var entries: Array[Vector2i] = simulation.projectile_pool.snapshot_active()
		simulation.weapon_system.move_snapshot_projectiles(
			entries,
			simulation.enemy_system.enemy_store,
			Vector2.ZERO,
			current_tick,
			false,
		)
		if current_tick == 2 and not entries.is_empty():
			var tracking_projectile: ProjectileState = (
				simulation.projectile_pool.resolve_snapshot_entry(entries[0])
			)
			assertions.expect_equal(
				ProjectileState.MovementKind.HOMING,
				tracking_projectile.movement_kind,
				"infinite homing retains its in-flight tracking movement",
			)
			assertions.expect_equal(
				Vector2.DOWN,
				tracking_projectile.velocity.normalized(),
				"infinite homing still bends toward a moved living target",
			)
		for entry: Vector2i in entries:
			simulation.weapon_system.resolve_ally_projectile(
				entry,
				simulation.enemy_system.enemy_store,
				simulation.enemy_system.uniform_grid,
				Vector2.ZERO,
				current_tick,
			)
		var attacks: Array[Dictionary] = simulation.weapon_system.advance_and_fire(
			Vector2.ZERO,
			simulation.enemy_system.enemy_store,
			simulation.enemy_system.uniform_grid,
			current_tick,
		)
		var expected_count: int = 1 if (current_tick - 1) % cooldown_ticks == 0 else 0
		assertions.expect_equal(expected_count, attacks.size(), "homing cooldown %d emits at the configured tick %d" % [cooldown_ticks, current_tick])
		generated_count += attacks.size()
	var expected_total: int = 1 + floori(599.0 / float(cooldown_ticks))
	assertions.expect_equal(expected_total, generated_count, "homing emits throughout the configured cadence")
	assertions.expect_equal(0, simulation.projectile_pool.overflow_count, "configured homing cadence does not overflow the projectile pool")
	assertions.expect_true(simulation.projectile_pool.active_count() < ProjectilePool.CAPACITY, "expired homing projectiles recycle active slots")


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
		catalog.lineage_for_weapon(definition.weapon_id),
		definition.is_evolved,
		state.rng_streams.create_weapon_rng(catalog.lineage_for_weapon(definition.weapon_id), 0),
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


func _homing_fixture(
	catalog: DefinitionCatalog,
	fixture_seed: int,
	weapon_id: StringName,
	level: int,
) -> Dictionary:
	var state: RunState = RunStateFactory.create(fixture_seed, catalog)
	state.weapons.clear()
	var definition: WeaponDefinition = catalog.weapon(weapon_id)
	var runtime := RunWeapon.create(
		definition.weapon_id,
		catalog.lineage_for_weapon(definition.weapon_id),
		definition.is_evolved,
		state.rng_streams.create_weapon_rng(catalog.lineage_for_weapon(definition.weapon_id), 0),
	)
	runtime.level = level
	state.weapons.append(runtime)
	var simulation := CombatSimulation.new()
	simulation.initialize(state, catalog)
	return {
		"simulation": simulation,
		"runtime": runtime,
		"state": state,
	}


func _projectile_born_at(
	simulation: CombatSimulation,
	born_tick: int,
) -> ProjectileState:
	for entry: Vector2i in simulation.projectile_pool.snapshot_active():
		var projectile: ProjectileState = (
			simulation.projectile_pool.resolve_snapshot_entry(entry)
		)
		if projectile != null and projectile.born_tick == born_tick:
			return projectile
	return null


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
	for node: ArenaNodeState in simulation.arena_object_system.nodes:
		node.deactivate()
	simulation.arena_object_system.nodes[0].activate(0, Vector2(9.75, 9.75), catalog.manifest().arena.node_max_hp)
	simulation.player_position = Vector2(6.0, 9.75)
	simulation.view.reset(simulation.player_position)
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
	assertions.expect_true(catalog.validate_manifest(BalanceTestFixtures.manifest()), "survival content catalog validates")
	return catalog if catalog.is_valid else null
