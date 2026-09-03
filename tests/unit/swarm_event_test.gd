extends RefCounted


func test_names() -> PackedStringArray:
	return PackedStringArray([
		"revision_thirteen_swarm_definition_and_drift_rejection",
		"normal_swarmer_outpaces_the_player",
		"swarm_scheduler_is_isolated_repeatable_and_atomic",
		"swarm_formation_crosses_player_relative_frame_and_uses_two_visuals",
		"swarm_contact_kill_and_invulnerability_are_separate",
		"swarm_push_is_capped_clamped_and_paused",
		"boss_transition_absorbs_swarm_without_rewards",
	])


func run_test(test_name: String, assertions: Variant, _context: Dictionary) -> void:
	match test_name:
		"revision_thirteen_swarm_definition_and_drift_rejection":
			_test_definition_and_drift(assertions)
		"normal_swarmer_outpaces_the_player":
			_test_normal_swarmer_speed(assertions)
		"swarm_scheduler_is_isolated_repeatable_and_atomic":
			_test_scheduler_and_atomic_spawn(assertions)
		"swarm_formation_crosses_player_relative_frame_and_uses_two_visuals":
			_test_formation_motion_and_visuals(assertions)
		"swarm_contact_kill_and_invulnerability_are_separate":
			_test_contact_and_death_accounting(assertions)
		"swarm_push_is_capped_clamped_and_paused":
			_test_push_and_pause(assertions)
		"boss_transition_absorbs_swarm_without_rewards":
			_test_boss_transition_absorption(assertions)
		_:
			assertions.expect_true(false, "registered revision thirteen swarm test")


func _test_definition_and_drift(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	if catalog == null:
		return
	var manifest: SurvivalContentManifest = catalog.manifest()
	var event_definition: SwarmEventDefinition = manifest.swarm_event
	var unit: EnemyDefinition = event_definition.unit_definition
	assertions.expect_equal(13, manifest.balance.balance_revision, "swarm ships as balance revision thirteen")
	assertions.expect_equal(6, GameTypes.EnemyType.size(), "swarm adds no seventh EnemyType")
	assertions.expect_equal(6, catalog.enemies.size(), "event unit stays outside the normal enemy catalog")
	assertions.expect_float(5.184, catalog.enemy(&"swarmer").move_speed, "normal swarmer is faster than the player")
	assertions.expect_float(9.0, catalog.enemy(&"swarmer").base_hp, "normal swarmer HP is unchanged")
	assertions.expect_float(4.0, catalog.enemy(&"swarmer").contact_damage, "normal swarmer damage is unchanged")
	assertions.expect_equal(1, catalog.enemy(&"swarmer").xp_value, "normal swarmer XP is unchanged")
	assertions.expect_equal(&"bat_swarm", event_definition.event_id, "event identity is fixed")
	assertions.expect_float(1.0, unit.base_hp, "event member base HP")
	assertions.expect_float(1.0, unit.contact_damage, "event member contact damage")
	assertions.expect_equal(1, unit.xp_value, "event member raw XP")
	assertions.expect_float(0.26, unit.body_radius, "event member radius")
	assertions.expect_float(2.59, unit.move_speed, "event member crossing speed")
	assertions.expect_equal(50, event_definition.member_count, "event creates fifty members")
	assertions.expect_equal(10, event_definition.lateral_count, "formation has ten lateral columns")
	assertions.expect_equal(5, event_definition.depth_count, "formation has five depth rows")
	assertions.expect_float(10.0, CombatEnvelope.SPAWN_INNER_HALF_EXTENT, "shared spawn frame begins ten metres away")
	assertions.expect_float(12.0, CombatEnvelope.SPAWN_OUTER_HALF_EXTENT, "shared spawn frame ends twelve metres away")
	assertions.expect_float(2.0 / 3.0, event_definition.lateral_pitch, "formation lateral pitch")
	assertions.expect_float(0.7, event_definition.depth_pitch, "formation depth pitch")
	var expected_ticks := PackedInt32Array([
		7500, 7800, 8100,
		11100, 11400,
		14700, 15000,
		21900, 22200,
		25500, 25800, 26100, 26400, 26700, 27000,
		29700, 30600, 31500,
		33300, 34200, 35100,
	])
	var expected_chances := PackedFloat32Array([
		1.0, 1.0, 1.0,
		0.1, 0.1,
		0.1, 0.1,
		0.1, 0.1,
		0.8, 0.8, 0.8, 0.8, 0.8, 0.8,
		0.8, 0.8, 0.8,
		0.7, 0.7, 0.7,
	])
	var state: RunState = RunStateFactory.create(8001, catalog)
	var system := EnemySystem.new()
	system.initialize(state, catalog)
	assertions.expect_equal(expected_ticks, system._swarm_attempt_ticks, "all twenty-one attempt ticks are exact")
	assertions.expect_equal(expected_chances, system._swarm_attempt_chances, "all attempt probabilities are exact")

	var speed_drift: SurvivalContentManifest = manifest.duplicate(true) as SurvivalContentManifest
	var speed_event: SwarmEventDefinition = event_definition.duplicate(true) as SwarmEventDefinition
	var speed_unit: EnemyDefinition = unit.duplicate(true) as EnemyDefinition
	speed_unit.move_speed = 2.58
	speed_event.unit_definition = speed_unit
	speed_drift.swarm_event = speed_event
	assertions.expect_false(
		DefinitionCatalog.new().validate_manifest(speed_drift),
		"validator rejects event member drift",
	)
	var schedule_drift: SurvivalContentManifest = manifest.duplicate(true) as SurvivalContentManifest
	var schedule_event: SwarmEventDefinition = event_definition.duplicate(true) as SwarmEventDefinition
	var schedules: Array[SwarmEventScheduleDefinition] = []
	for schedule: SwarmEventScheduleDefinition in event_definition.schedules:
		schedules.append(schedule.duplicate(true) as SwarmEventScheduleDefinition)
	schedules[6].spawn_chance = 0.69
	schedule_event.schedules = schedules
	schedule_drift.swarm_event = schedule_event
	assertions.expect_false(
		DefinitionCatalog.new().validate_manifest(schedule_drift),
		"validator rejects schedule probability drift",
	)


func _test_normal_swarmer_speed(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	if catalog == null:
		return
	var state: RunState = RunStateFactory.create(8002, catalog)
	var system := EnemySystem.new()
	system.initialize(state, catalog)
	var swarmer: EnemyEntity = system.enemy_store.try_spawn(
		state,
		GameTypes.EnemyType.SWARMER,
		catalog.enemy(&"swarmer"),
		Vector2(-5.0, 0.0),
		1.0,
		1.0,
		0,
	)
	var ids: Array[int] = [swarmer.entity_id]
	var moving_player := Vector2(5.0, 0.0)
	var initial_gap: float = moving_player.distance_to(swarmer.position)
	for tick: int in range(1, 61):
		moving_player += Vector2.RIGHT * CombatSimulation.PLAYER_SPEED / 60.0
		state.combat_tick = tick
		system.advance_snapshot(ids, moving_player, tick)
	assertions.expect_true(
		swarmer.position.distance_to(moving_player) < initial_gap,
		"normal swarmer closes distance on a player moving directly away",
	)
	assertions.expect_float(5.184, swarmer.position.x + 5.0, "normal swarmer travels 5.184 metres in one second")
	assertions.expect_float(4.05, moving_player.x - 5.0, "player travels 4.05 metres in one second")
	assertions.expect_equal(EnemyEntity.MovementKind.SEEK_PLAYER, swarmer.movement_kind, "normal swarmer keeps direct pursuit")


func _test_scheduler_and_atomic_spawn(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	if catalog == null:
		return
	var event_definition: SwarmEventDefinition = catalog.manifest().swarm_event
	var first_state: RunState = RunStateFactory.create(8003, catalog)
	var second_state: RunState = RunStateFactory.create(8003, catalog)
	var first_system := EnemySystem.new()
	var second_system := EnemySystem.new()
	first_system.initialize(first_state, catalog)
	second_system.initialize(second_state, catalog)
	first_state.combat_tick = 7500
	second_state.combat_tick = 7500
	first_state.stop_until_tick = 7600
	second_state.stop_until_tick = 7600
	first_state.spawn_credit = 7.25
	var normal_rng_before: int = first_state.rng_streams.spawn_rng.state
	var swarm_rng_before: int = first_state.rng_streams.swarm_event_rng.state
	var first_group: Array[EnemyEntity] = first_system.resolve_swarm_event_spawns(
		Vector2(2.0, -1.0),
		7500,
	)
	var second_group: Array[EnemyEntity] = second_system.resolve_swarm_event_spawns(
		Vector2(2.0, -1.0),
		7500,
	)
	assertions.expect_equal(50, first_group.size(), "first certain attempt spawns atomically during STOP")
	assertions.expect_equal(50, second_group.size(), "same seed repeats the successful attempt")
	assertions.expect_equal(first_group[0].position, second_group[0].position, "same seed repeats direction and formation")
	assertions.expect_equal(first_group[0].fixed_direction, second_group[0].fixed_direction, "same seed repeats fixed direction")
	assertions.expect_equal(normal_rng_before, first_state.rng_streams.spawn_rng.state, "swarm attempt consumes no normal spawn RNG")
	assertions.expect_not_equal(swarm_rng_before, first_state.rng_streams.swarm_event_rng.state, "swarm attempt advances only its dedicated RNG")
	var first_direction: Vector2 = first_group[0].fixed_direction
	var first_spawn_distance: float = -(
		first_group[0].position - Vector2(2.0, -1.0)
	).dot(first_direction)
	assertions.expect_true(
		first_spawn_distance >= CombatEnvelope.SPAWN_INNER_HALF_EXTENT
		and first_spawn_distance <= CombatEnvelope.SPAWN_OUTER_HALF_EXTENT,
		"successful attempt samples the shared ten-to-twelve-metre spawn frame",
	)
	var front_row_center := Vector2.ZERO
	for front_index: int in range(event_definition.lateral_count):
		front_row_center += first_group[front_index].position
	front_row_center /= float(event_definition.lateral_count)
	var lateral_direction := Vector2(-first_direction.y, first_direction.x)
	var front_stagger: float = -0.25 * event_definition.lateral_pitch
	var reconstructed_anchor: Vector2 = front_row_center - lateral_direction * front_stagger
	assertions.expect_true(
		reconstructed_anchor.is_equal_approx(
			Vector2(2.0, -1.0) - first_direction * first_spawn_distance
		),
		"formation anchor has zero lateral offset on the selected player axis",
	)
	assertions.expect_float(
		2.0 * first_spawn_distance
		+ float(event_definition.depth_count - 1) * event_definition.depth_pitch,
		first_group[0].remaining_travel_distance,
		"attempt derives crossing distance from its sampled frame and formation depth",
	)
	var sampling_rng := RandomNumberGenerator.new()
	sampling_rng.seed = 8003
	var side_counts := PackedInt32Array([0, 0, 0, 0])
	var sample_count: int = 4096
	var all_distances_in_frame: bool = true
	for _sample_index: int in range(sample_count):
		var outward_direction: Vector2 = first_system._sample_spawn_outward_direction(
			sampling_rng
		)
		var side_index: int = EnemySystem.SPAWN_OUTWARD_DIRECTIONS.find(outward_direction)
		side_counts[side_index] += 1
		var sampled_distance: float = first_system._sample_spawn_distance(sampling_rng)
		all_distances_in_frame = all_distances_in_frame and (
			sampled_distance >= CombatEnvelope.SPAWN_INNER_HALF_EXTENT
			and sampled_distance <= CombatEnvelope.SPAWN_OUTER_HALF_EXTENT
		)
	assertions.expect_true(
		all_distances_in_frame,
		"swarm distance sampler remains inside the shared frame",
	)
	for count: int in side_counts:
		assertions.expect_true(
			count >= floori(float(sample_count) * 0.20)
			and count <= ceili(float(sample_count) * 0.30),
			"dedicated attempt sampler selects each screen side at twenty-five percent",
		)
	assertions.expect_float(7.25, first_state.spawn_credit, "swarm attempt consumes no spawn credit")
	assertions.expect_equal(0, first_system._normal_enemy_count(), "event members do not count toward the normal target")
	assertions.expect_equal(0, first_system.resolve_swarm_event_spawns(Vector2.ZERO, 7500).size(), "one attempt cannot execute twice")
	assertions.expect_equal(1, first_state.swarm_event_attempt_count, "duplicate call does not duplicate attempt telemetry")
	first_state.spawn_credit = 16.0
	var normal_spawns: Array[EnemyEntity] = first_system.resolve_normal_spawns(Vector2.ZERO, 7500)
	assertions.expect_equal(16, normal_spawns.size(), "normal spawn management also continues during STOP")
	assertions.expect_equal(66, first_system.enemy_store.active_count(), "normal wave and fifty-member event coexist")
	assertions.expect_float(0.0, first_state.spawn_credit, "only normal spawns consume credit")
	assertions.expect_true(176 + 50 + RunState.ELITE_COUNT < EnemyStore.CAPACITY, "approved peak normal target, one swarm, and all elites fit the pool")

	var changed_state: RunState = RunStateFactory.create(8004, catalog)
	var baseline_state: RunState = RunStateFactory.create(8004, catalog)
	var changed_system := EnemySystem.new()
	var baseline_system := EnemySystem.new()
	changed_system.initialize(changed_state, catalog)
	baseline_system.initialize(baseline_state, catalog)
	changed_system._swarm_attempt_chances[0] = 0.0
	changed_state.combat_tick = 7500
	baseline_state.combat_tick = 7500
	changed_system.resolve_swarm_event_spawns(Vector2.ZERO, 7500)
	baseline_system.resolve_swarm_event_spawns(Vector2.ZERO, 7500)
	baseline_system.enemy_store.clear()
	changed_state.combat_tick = 7800
	baseline_state.combat_tick = 7800
	var changed_second: Array[EnemyEntity] = changed_system.resolve_swarm_event_spawns(Vector2.ZERO, 7800)
	var baseline_second: Array[EnemyEntity] = baseline_system.resolve_swarm_event_spawns(Vector2.ZERO, 7800)
	assertions.expect_equal(50, changed_second.size(), "second trial succeeds independently of the first result")
	assertions.expect_equal(50, baseline_second.size(), "baseline second trial succeeds")
	assertions.expect_equal(changed_second[0].fixed_direction, baseline_second[0].fixed_direction, "per-attempt seed isolates later direction")
	assertions.expect_equal(changed_second[0].position, baseline_second[0].position, "per-attempt seed isolates later formation")

	var overflow_state: RunState = RunStateFactory.create(8005, catalog)
	var overflow_system := EnemySystem.new()
	overflow_system.initialize(overflow_state, catalog)
	var pursuer: EnemyDefinition = catalog.enemy(&"pursuer")
	for fill_index: int in range(EnemyStore.CAPACITY - 49):
		overflow_system.enemy_store.try_spawn(
			overflow_state,
			GameTypes.EnemyType.PURSUER,
			pursuer,
			Vector2(float(fill_index % 10), 0.0),
			1.0,
			1.0,
			0,
		)
	overflow_state.combat_tick = 7500
	var count_before: int = overflow_system.enemy_store.active_count()
	assertions.expect_equal(0, overflow_system.resolve_swarm_event_spawns(Vector2.ZERO, 7500).size(), "fewer than fifty free slots rejects the whole group")
	assertions.expect_equal(count_before, overflow_system.enemy_store.active_count(), "atomic rejection creates no partial group")
	assertions.expect_equal(1, overflow_state.swarm_event_spawn_failure_count, "atomic rejection records one group failure")
	assertions.expect_equal(0, overflow_state.swarm_event_group_count, "failed roll success does not count as generated group")
	assertions.expect_equal(0, overflow_system.enemy_store.overflow_count, "preflight avoids per-member pool overflow")
	assertions.expect_equal(0, overflow_system.enemy_store.orphan_count(), "atomic rejection leaves no pool orphan")


func _test_formation_motion_and_visuals(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	if catalog == null:
		return
	var event_definition: SwarmEventDefinition = catalog.manifest().swarm_event
	var state: RunState = RunStateFactory.create(8006, catalog)
	var simulation := CombatSimulation.new()
	simulation.initialize(state, catalog)
	state.combat_tick = 7500
	var captured_player := Vector2(14.0, 14.0)
	simulation.player_position = captured_player
	var direction: Vector2 = EnemySystem.SCREEN_RIGHT_WORLD
	var group: Array[EnemyEntity] = simulation.enemy_system._spawn_swarm_group(
		captured_player,
		direction,
		7500,
		11.0,
	)
	assertions.expect_equal(50, group.size(), "direct fixture creates one complete formation")
	var red_count: int = 0
	var minimum_depth: float = INF
	var maximum_depth: float = -INF
	var minimum_lateral: float = INF
	var maximum_lateral: float = -INF
	var has_outside_member: bool = false
	var lateral_direction := Vector2(-direction.y, direction.x)
	for enemy: EnemyEntity in group:
		red_count += 1 if enemy.swarm_red_variant else 0
		var relative: Vector2 = enemy.position - captured_player
		var depth: float = -relative.dot(direction)
		var lateral: float = relative.dot(lateral_direction)
		minimum_depth = minf(minimum_depth, depth)
		maximum_depth = maxf(maximum_depth, depth)
		minimum_lateral = minf(minimum_lateral, lateral)
		maximum_lateral = maxf(maximum_lateral, lateral)
		has_outside_member = has_outside_member or (
			absf(enemy.position.x) > CombatEnvelope.enemy_center_limit(enemy.body_radius())
			or absf(enemy.position.y) > CombatEnvelope.enemy_center_limit(enemy.body_radius())
		)
		assertions.expect_equal(1, enemy.swarm_group_id, "all members share one group id")
		assertions.expect_equal(EnemyEntity.MovementKind.FIXED_DIRECTION, enemy.movement_kind, "every member uses fixed movement")
	assertions.expect_equal(25, red_count, "checker pattern contains twenty-five red members")
	assertions.expect_float(11.0, minimum_depth, "leading row starts on the sampled spawn frame")
	assertions.expect_float(13.8, maximum_depth, "rear row may extend 2.8 metres beyond the frame")
	assertions.expect_float(6.3333333, maximum_lateral - minimum_lateral, "staggered band spans about 6.33 metres")
	assertions.expect_true(has_outside_member, "event formation is not clamped to the arena")
	var snapshot: CombatSnapshot = simulation.build_snapshot()
	var orange_visuals: int = 0
	var red_visuals: int = 0
	for visual_kind: int in snapshot.enemy_visual_kinds:
		if visual_kind == CombatSnapshot.EnemyVisualKind.SWARMER:
			orange_visuals += 1
		elif visual_kind == CombatSnapshot.EnemyVisualKind.SWARMER_EVENT_RED:
			red_visuals += 1
	assertions.expect_equal(25, orange_visuals, "checker pattern contains twenty-five orange visuals")
	assertions.expect_equal(25, red_visuals, "checker pattern contains twenty-five red visuals")
	simulation._record_visible_enemy_sample(7500)
	assertions.expect_equal(0, state.normal_active_total_by_segment[2], "swarm is excluded from segment normal-active metrics")

	var arena_scene: PackedScene = load("res://scenes/gameplay/arena_combat.tscn") as PackedScene
	var arena: Node = arena_scene.instantiate()
	var orange_instances: MultiMeshInstance3D = arena.get_node("EnemySwarmerInstances") as MultiMeshInstance3D
	var red_instances: MultiMeshInstance3D = arena.get_node("EnemySwarmerEventRedInstances") as MultiMeshInstance3D
	assertions.expect_true(orange_instances.multimesh.mesh == red_instances.multimesh.mesh, "orange and red variants share the same small mesh")
	assertions.expect_true(red_instances.material_override != null, "red variant only overrides the material")
	arena.free()

	var first_id: int = group[0].entity_id
	var second_id: int = group[1].entity_id
	var first_position: Vector2 = group[0].position
	var relative_before: Vector2 = group[1].position - group[0].position
	simulation.player_position = Vector2(-14.0, 14.0)
	state.combat_tick = 7501
	simulation.enemy_system.advance_snapshot(
		simulation.enemy_system.snapshot_ids(),
		simulation.player_position,
		7501,
	)
	var first_after: EnemyEntity = simulation.enemy_system.enemy_store.get_by_id(first_id)
	var second_after: EnemyEntity = simulation.enemy_system.enemy_store.get_by_id(second_id)
	var event_step: float = event_definition.unit_definition.move_speed / float(RunState.TICKS_PER_SECOND)
	assertions.expect_float(event_step, first_after.position.distance_to(first_position), "swarm advances by its configured per-tick distance")
	assertions.expect_true(first_after.fixed_direction.dot(direction) > 0.99999, "moving player does not retarget the swarm")
	assertions.expect_true((second_after.position - first_after.position).is_equal_approx(relative_before), "formation offsets remain fixed")
	var travel_distance: float = 2.0 * 11.0 + 4.0 * 0.7
	assertions.expect_float(travel_distance - event_step, first_after.remaining_travel_distance, "travel derives from spawn depth and formation depth")
	var travel_ticks: int = ceili(travel_distance / event_step)
	assertions.expect_equal(575, travel_ticks, "revision thirteen preserves the 575-tick full crossing")
	for movement_index: int in range(1, travel_ticks):
		var movement_tick: int = 7501 + movement_index
		state.combat_tick = movement_tick
		simulation.enemy_system.advance_snapshot(
			simulation.enemy_system.snapshot_ids(),
			simulation.player_position,
			movement_tick,
		)
	assertions.expect_equal(0, simulation.enemy_system.enemy_store.active_count(), "all members exit together after crossing the player-relative frame")
	assertions.expect_equal(50, state.swarm_event_exit_count, "every survivor is counted as a no-reward exit")
	assertions.expect_equal(0, state.total_kills, "crossing exit grants no kill")
	assertions.expect_equal(0, state.kill_chain_count, "crossing exit grants no chain")
	assertions.expect_equal(0, simulation.xp_pickup_pool.active_count(), "crossing exit creates no XP")
	assertions.expect_equal(0, simulation.arena_object_system.pickups.size(), "crossing exit creates no drop")


func _test_contact_and_death_accounting(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	if catalog == null:
		return
	var state: RunState = RunStateFactory.create(8007, catalog)
	var simulation := CombatSimulation.new()
	simulation.initialize(state, catalog)
	state.combat_tick = 7500
	simulation.player_position = Vector2.ZERO
	var group: Array[EnemyEntity] = simulation.enemy_system._spawn_swarm_group(
		Vector2.ZERO,
		Vector2.RIGHT,
		7500,
		11.0,
	)
	for enemy: EnemyEntity in group:
		enemy.position = Vector2.ZERO
	assertions.expect_float(0.22, group[0].damage_multiplier, "event damage uses only the current segment multiplier")
	assertions.expect_float(0.22, group[0].definition.contact_damage * group[0].damage_multiplier, "normal global damage scale is not applied")
	assertions.expect_true(group[0].is_targetable(7500), "event member has no materialization delay")
	var ids: Array[int] = simulation.enemy_system.snapshot_ids()
	var records: Array[Dictionary] = simulation.enemy_system.resolve_contact_damage_candidates(
		ids,
		Vector2.ZERO,
		7500,
	)
	assertions.expect_equal(50, records.size(), "all overlapping members report contact independently")
	simulation._apply_player_damage_candidates(records)
	assertions.expect_float(99.78, state.current_hp, "thirty-tick invulnerability admits only one simultaneous hit")
	simulation._apply_player_damage_candidates(records)
	assertions.expect_float(99.78, state.current_hp, "same-tick records cannot stack damage")
	state.combat_tick = 7530
	simulation._apply_raw_player_damage(0.22)
	assertions.expect_float(99.78, state.current_hp, "invulnerability protects thirty following ticks")
	state.combat_tick = 7531
	simulation._apply_raw_player_damage(0.22)
	assertions.expect_float(99.56, state.current_hp, "contact becomes eligible after the thirty-tick window")

	var killed: EnemyEntity = group[0]
	killed.hp = 0.0
	simulation._record_enemy_death(killed, &"homing_core", 0.0)
	simulation._process_pending_deaths(7531)
	assertions.expect_equal(1, state.total_kills, "event kill contributes to total kills")
	assertions.expect_equal(1, state.weapon_kill_count, "event kill contributes to weapon kills")
	assertions.expect_equal(1, state.kill_chain_count, "event kill contributes to chain")
	assertions.expect_equal(1, state.swarm_event_kill_count, "event kill is separately measured")
	assertions.expect_equal(1, state.swarm_event_xp, "event raw XP is separately measured")
	assertions.expect_equal(0, state.normal_kills, "event kill is excluded from normal kills")
	assertions.expect_equal(0, state.normal_kills_by_type[GameTypes.EnemyType.SWARMER], "event kill is excluded from swarmer role metrics")
	assertions.expect_equal(0, state.normal_kills_by_segment[2], "event kill is excluded from segment kill metrics")
	assertions.expect_equal(0, state.normal_xp_by_segment[2], "event XP is excluded from normal segment XP")
	assertions.expect_equal(1, simulation.xp_pickup_pool.active_count(), "event kill creates one XP crystal")
	var pickup_index: int = simulation.xp_pickup_pool.active_indices_snapshot()[0]
	assertions.expect_equal(1, simulation.xp_pickup_pool.slots[pickup_index].value, "event crystal carries one raw XP before global scaling")
	state.combat_tick = 7532
	var collected_xp: int = simulation.xp_pickup_pool.advance_and_collect(
		Vector2.ZERO,
		CombatSimulation.FIXED_DELTA_SECONDS,
		state.combat_tick,
	)
	ProgressionService.add_xp(state, collected_xp, catalog)
	assertions.expect_equal(1, collected_xp, "event crystal uses the standard XP collection path")
	assertions.expect_equal(0, state.xp, "one raw event XP is scaled by the global ninety-percent yield")
	assertions.expect_equal(90, state.xp_yield_remainder, "event XP preserves the standard fractional yield remainder")
	assertions.expect_equal(0, simulation.arena_object_system.pickups.size(), "event kill creates no chest or power-up drop")


func _test_push_and_pause(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	if catalog == null:
		return
	var state: RunState = RunStateFactory.create(8008, catalog)
	var system := EnemySystem.new()
	system.initialize(state, catalog)
	var event_step: float = (
		catalog.manifest().swarm_event.unit_definition.move_speed
		/ float(RunState.TICKS_PER_SECOND)
	)
	var event_a: EnemyEntity = _spawn_swarm_member(system, state, catalog, Vector2.ZERO, Vector2.RIGHT, 1)
	var event_b: EnemyEntity = _spawn_swarm_member(system, state, catalog, Vector2.ZERO, Vector2.RIGHT, 1)
	var event_c: EnemyEntity = _spawn_swarm_member(system, state, catalog, Vector2.ZERO, Vector2.RIGHT, 2)
	var targets: Array[EnemyEntity] = []
	for enemy_type: GameTypes.EnemyType in [
		GameTypes.EnemyType.PURSUER,
		GameTypes.EnemyType.ELITE,
		GameTypes.EnemyType.BOSS,
	]:
		var target: EnemyEntity = system.enemy_store.try_spawn(
			state,
			enemy_type,
			catalog.enemy_for_type(enemy_type),
			Vector2(0.3, 0.0),
			1.0,
			1.0,
			0,
		)
		targets.append(target)
	var target_start := Vector2(0.3, 0.0)
	state.combat_tick = 1
	var swarm_sweeps: Array[Dictionary] = [
		system._move_enemy(event_a, target_start, 1.0),
		system._move_enemy(event_b, target_start, 1.0),
		system._move_enemy(event_c, target_start, 1.0),
	]
	system._apply_swarm_pushes(system.snapshot_ids(), swarm_sweeps)
	for target: EnemyEntity in targets:
		assertions.expect_float(
			event_step,
			target.position.distance_to(target_start),
			"normal, elite, and boss pushes share the speed-derived per-target cap",
		)
	assertions.expect_float(event_step, event_a.position.x, "first event member advances normally")
	assertions.expect_float(event_step, event_b.position.x, "overlapping same-group member advances normally")
	assertions.expect_float(event_step, event_c.position.x, "overlapping second-group member advances normally")
	var pushed_damage: Array[Dictionary] = system.resolve_contact_damage_candidates(
		system.snapshot_ids(),
		targets[0].position,
		1,
	)
	assertions.expect_true(pushed_damage.size() >= 3, "pushed enemies can resolve contact in the same tick")

	var boundary_state: RunState = RunStateFactory.create(8009, catalog)
	var boundary_system := EnemySystem.new()
	boundary_system.initialize(boundary_state, catalog)
	var target_definition: EnemyDefinition = catalog.enemy(&"pursuer")
	var center_limit: float = CombatEnvelope.enemy_center_limit(target_definition.body_radius)
	var boundary_target: EnemyEntity = boundary_system.enemy_store.try_spawn(
		boundary_state,
		GameTypes.EnemyType.PURSUER,
		target_definition,
		Vector2(center_limit - event_step * 0.5, 0.0),
		1.0,
		1.0,
		0,
	)
	var boundary_event: EnemyEntity = _spawn_swarm_member(
		boundary_system,
		boundary_state,
		catalog,
		boundary_target.position - Vector2.RIGHT * 0.2,
		Vector2.RIGHT,
		1,
	)
	boundary_state.combat_tick = 1
	var boundary_sweeps: Array[Dictionary] = [
		boundary_system._move_enemy(boundary_event, boundary_target.position, 1.0),
	]
	boundary_system._apply_swarm_pushes(
		boundary_system.snapshot_ids(),
		boundary_sweeps,
	)
	assertions.expect_float(center_limit, boundary_target.position.x, "pushed enemy remains inside its arena radius")

	var stop_state: RunState = RunStateFactory.create(8010, catalog)
	var stop_system := EnemySystem.new()
	stop_system.initialize(stop_state, catalog)
	var stopped: EnemyEntity = _spawn_swarm_member(
		stop_system,
		stop_state,
		catalog,
		Vector2.ZERO,
		Vector2.RIGHT,
		1,
	)
	stop_state.stop_until_tick = 10
	stop_state.combat_tick = 1
	stop_system.advance_snapshot(stop_system.snapshot_ids(), Vector2.ZERO, 1)
	assertions.expect_equal(Vector2.ZERO, stopped.position, "STOP freezes event movement")
	assertions.expect_float(10.0, stopped.remaining_travel_distance, "STOP freezes remaining travel")

	var modal_state: RunState = RunStateFactory.create(8011, catalog)
	var modal_simulation := CombatSimulation.new()
	modal_simulation.initialize(modal_state, catalog)
	var modal_group: Array[EnemyEntity] = modal_simulation.enemy_system._spawn_swarm_group(
		Vector2.ZERO,
		Vector2.RIGHT,
		0,
		11.0,
	)
	var modal_position: Vector2 = modal_group[0].position
	modal_state.phase = GameTypes.RunPhase.LEVEL_UP
	assertions.expect_false(modal_simulation.advance_tick(Vector2.RIGHT), "modal phase blocks the combat tick")
	assertions.expect_equal(modal_position, modal_group[0].position, "modal pause freezes event movement")


func _test_boss_transition_absorption(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	if catalog == null:
		return
	var state: RunState = RunStateFactory.create(8012, catalog)
	var simulation := CombatSimulation.new()
	simulation.initialize(state, catalog)
	state.combat_tick = catalog.manifest().boss_start_tick - 1
	simulation.enemy_system._elite_spawned.fill(1)
	var group: Array[EnemyEntity] = simulation.enemy_system._spawn_swarm_group(
		Vector2.ZERO,
		Vector2.RIGHT,
		state.combat_tick,
		11.0,
	)
	assertions.expect_equal(50, group.size(), "transition fixture starts with one full swarm")
	var total_kills_before: int = state.total_kills
	var chain_before: int = state.kill_chain_count
	assertions.expect_true(simulation.advance_tick(Vector2.ZERO), "ten-minute transition tick resolves")
	assertions.expect_equal(0, _active_swarm_count(simulation.enemy_system), "transition removes every remaining event member")
	assertions.expect_equal(50, state.swarm_event_absorbed_count, "transition separately counts absorbed event members")
	assertions.expect_equal(0, state.absorbed_normal_count, "event absorption does not inflate normal absorption")
	assertions.expect_equal(total_kills_before, state.total_kills, "event absorption grants no kill")
	assertions.expect_equal(chain_before, state.kill_chain_count, "event absorption grants no chain")
	assertions.expect_equal(0, state.swarm_event_xp, "event absorption grants no XP")
	assertions.expect_equal(0, simulation.xp_pickup_pool.active_count(), "event absorption creates no XP pickup")


func _spawn_swarm_member(
	system: EnemySystem,
	state: RunState,
	catalog: DefinitionCatalog,
	position: Vector2,
	direction: Vector2,
	group_id: int,
) -> EnemyEntity:
	var unit: EnemyDefinition = catalog.manifest().swarm_event.unit_definition
	var enemy: EnemyEntity = system.enemy_store.try_spawn(
		state,
		GameTypes.EnemyType.SWARMER,
		unit,
		position,
		1.0,
		1.0,
		0,
	)
	enemy.configure_swarm_event(group_id, direction, 10.0, false)
	return enemy


func _active_swarm_count(system: EnemySystem) -> int:
	var count: int = 0
	for enemy: EnemyEntity in system.enemy_store.entities:
		if enemy.is_swarm_event:
			count += 1
	return count


func _catalog(assertions: Variant) -> DefinitionCatalog:
	var catalog := DefinitionCatalog.new()
	assertions.expect_true(catalog.load_and_validate(), "revision thirteen catalog validates: %s" % catalog.error_text)
	return catalog if catalog.is_valid else null
