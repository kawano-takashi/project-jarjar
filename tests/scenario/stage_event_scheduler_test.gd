extends RefCounted


func test_stage_events_reserve_encounters_before_swarms_and_retry_once(a: Variant, _context: Dictionary) -> void:
	for blocked: bool in [false, true]:
		var content: SurvivalContentManifest = _content()
		content.combat.enemy_pool_capacity = 4
		content.encounters.member_count = 2
		var swarm := content.stage_events.events[0] as SwarmEventScheduleDefinition
		swarm.interval_ticks = 1
		swarm.attempt_count = 2
		content.stage_events.events[1].start_tick = 2
		var sim: CombatSimulation = _simulation(content, a)
		var system: EnemySystem = sim.enemy_system
		var blockers: Array[int] = []
		if blocked:
			for index: int in range(4):
				blockers.append(sim.spawn_fixture_enemy(GameTypes.EnemyType.ELITE, Vector2(100 + index, 0)).entity_id)
		system.resolve_stage_events(Vector2.ZERO, 1)
		a.expect_true(system.stage_events.swarm_warning != null, "first attempt announces a swarm")
		var spawned: Array[EnemyEntity] = system.resolve_stage_events(Vector2.ZERO, 2)
		a.expect_equal(0 if blocked else 1, spawned.size(), "encounter has first claim on capacity at the warning deadline")
		a.expect_equal(-1 if blocked else 2, sim.state.elite_spawn_ticks[0], "failed encounter stays pending without a false spawn record")
		a.expect_equal(1, sim.state.swarm_event_spawn_failure_count, "insufficient space rejects the entire warned swarm")
		a.expect_equal(1, sim.state.swarm_event_skipped_busy_count, "same-tick repeat is consumed after the warning")
		if blocked:
			for index: int in range(3):
				system.enemy_store.remove(blockers[index])
		spawned = system.resolve_stage_events(Vector2.ZERO, 3)
		a.expect_equal(1 if blocked else 0, spawned.size(), "only a pending encounter retries after capacity becomes available")
		a.expect_equal(3 if blocked else 2, sim.state.elite_spawn_ticks[0], "actual spawn time follows successful allocation")
		var elite: EnemyEntity = null
		for enemy: EnemyEntity in system.enemy_store.entities:
			if enemy.elite_serial == 0:
				elite = enemy
		a.expect_true(elite != null, "the successful encounter keeps its scheduled source")
		if elite != null:
			elite.hp = 0.0
			sim._record_enemy_death(elite)
			sim._process_pending_deaths(3)
			a.expect_equal(GameTypes.ChestKind.EVOLUTION_CAPABLE, sim.arena_object_system.pickups[0].chest_kind, "retry preserves the source chest kind")
		a.expect_true(system.resolve_stage_events(Vector2.ZERO, 3).is_empty(), "repeated resolution cannot duplicate consumed events")
		a.expect_equal(2, sim.state.swarm_event_attempt_count, "failed or busy swarms never enter the encounter retry queue")
		a.expect_equal(0, sim.state.swarm_event_generated_count, "no partial formation or deferred swarm was created")


func test_stopped_swarm_survives_encounter_start_and_scheduler_resets(a: Variant, _context: Dictionary) -> void:
	var sim: CombatSimulation = _simulation(_content(), a)
	sim.state.stop_until_tick = 60
	sim.advance_tick(Vector2.ZERO)
	sim.advance_tick(Vector2.ZERO)
	var members: Array[int] = []
	for enemy: EnemyEntity in sim.enemy_system.enemy_store.entities:
		if enemy.is_swarm_event:
			members.append(enemy.entity_id)
	a.expect_equal(2, members.size(), "the earlier swarm materializes during STOP")
	if members.is_empty():
		return
	var first_position: Vector2 = sim.enemy_system.enemy_store.get_by_id(members[0]).position
	sim.advance_tick(Vector2.ZERO)
	a.expect_equal(3, sim.state.elite_spawn_ticks[0], "STOP does not postpone the encounter")
	for entity_id: int in members:
		a.expect_true(sim.enemy_system.enemy_store.has_entity(entity_id), "encounter preserves every stopped swarm member")
	a.expect_equal(first_position, sim.enemy_system.enemy_store.get_by_id(members[0]).position, "swarm travel remains frozen")
	sim.state.current_hp = 0.0
	sim.advance_tick(Vector2.ZERO)
	a.expect_true(sim.enemy_system.resolve_stage_events(Vector2.ZERO, 20).is_empty(), "defeat retires all pending event work")
	sim.initialize(RunStateFactory.create(4021, sim.catalog), sim.catalog)
	sim.advance_tick(Vector2.ZERO)
	a.expect_true(sim.enemy_system.stage_events.swarm_warning != null, "a new run begins its own first warning")
	a.expect_equal(1, sim.state.swarm_event_attempt_count, "restart clears event consumption and accounting")


func test_boss_transition_discards_pending_encounters(a: Variant, _context: Dictionary) -> void:
	var content: SurvivalContentManifest = _content()
	content.combat.enemy_pool_capacity = 4
	content.encounters.member_count = 2
	content.stage_events.events = [content.stage_events.events[1]]
	var sim: CombatSimulation = _simulation(content, a)
	for index: int in range(4):
		sim.spawn_fixture_enemy(GameTypes.EnemyType.ELITE, Vector2(100 + index, 0))
	sim.enemy_system.resolve_stage_events(Vector2.ZERO, 3)
	a.expect_equal(-1, sim.state.elite_spawn_ticks[0], "full pool leaves the encounter pending")
	sim.state.combat_tick = 19
	sim.advance_tick(Vector2.ZERO)
	a.expect_equal(20, sim.state.boss_spawn_tick, "boss transition absorbs blockers and creates the boss on time")
	a.expect_equal(-1, sim.state.elite_spawn_ticks[0], "the old pending encounter cannot use newly freed boss capacity")
	a.expect_equal(1, sim.enemy_system.enemy_store.active_count(), "only the final boss remains after the boundary")
	a.expect_true(sim.enemy_system.resolve_stage_events(Vector2.ZERO, 21).is_empty(), "discarded encounters never resume in the boss phase")


func _content() -> SurvivalContentManifest:
	var content: SurvivalContentManifest = BalanceTestFixtures.manifest()
	content.segments.resize(1)
	content.segments[0].duration_ticks = 20
	content.segments[0].target_active = 0
	content.swarm_event.telegraph_ticks = 1
	content.swarm_event.lateral_count = 2
	content.swarm_event.depth_count = 1
	var swarm := SwarmEventScheduleDefinition.new()
	swarm.event_id = &"swarm"
	swarm.start_tick = 1
	swarm.interval_ticks = 1
	swarm.attempt_count = 1
	swarm.spawn_chance = 1.0
	swarm.hp_multiplier = 1.0
	swarm.damage_multiplier = 1.0
	var elite := EliteSpawnDefinition.new()
	elite.event_id = &"encounter"
	elite.start_tick = 3
	elite.chest_kind = GameTypes.ChestKind.EVOLUTION_CAPABLE
	content.stage_events.events = [swarm, elite]
	return content


func _simulation(content: SurvivalContentManifest, a: Variant) -> CombatSimulation:
	var catalog := DefinitionCatalog.new()
	a.expect_true(catalog.validate_manifest(content), catalog.error_text)
	var sim := CombatSimulation.new()
	sim.initialize(RunStateFactory.create(4020, catalog), catalog)
	sim.state.weapons.clear()
	return sim
