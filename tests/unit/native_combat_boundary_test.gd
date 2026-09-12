extends RefCounted


func test_native_death_batch_preserves_rewards_over_xp_and_effect_capacity(a: Variant, _context: Dictionary) -> void:
	var content: SurvivalContentManifest = BalanceTestFixtures.manifest()
	content.progression.xp_pool_capacity = 4
	var catalog := DefinitionCatalog.new()
	a.expect_true(catalog.validate_manifest(content), catalog.error_text)
	var simulation := CombatSimulation.new()
	simulation.initialize(RunStateFactory.create(4201, catalog), catalog)
	simulation.state.combat_tick = 1
	var requests: Array[Dictionary] = []
	var expected_xp: int = 0
	for index: int in 96:
		var enemy: EnemyEntity = simulation.spawn_fixture_enemy(GameTypes.EnemyType.PURSUER, Vector2(1.0, index * 0.001))
		expected_xp += enemy.definition.xp_value
		requests.append({"entity_id": enemy.entity_id, "damage": enemy.hp, "source_effect_id": &"batch_fixture"})
	simulation.world.set_context(CombatNative.context(catalog, simulation.state, Vector2.ZERO, 1))
	simulation.world.apply_hits(requests)
	simulation._consume_native_damage()
	simulation._process_pending_deaths(1)
	a.expect_equal(96, simulation.state.total_kills, "every death contributes to the kill total")
	a.expect_equal(expected_xp, simulation.xp_pickup_pool.total_value(), "a full XP pool preserves every reward from the batch")
	a.expect_equal(4, simulation.xp_pickup_pool.active_count(), "overflow merges within capacity")
	a.expect_true(simulation.vfx_pool.admitted_count < 96, "presentation limits do not limit rewards")
	a.expect_equal(0, simulation.xp_pickup_pool.advance_and_collect(Vector2.ZERO, 1000.0, 1), "new rewards are not collected in their birth tick")
	a.expect_equal(expected_xp, simulation.xp_pickup_pool.advance_and_collect(Vector2.ZERO, 1000.0, 2), "the full merged value can be collected on a later tick")
	simulation._process_pending_deaths(2)
	a.expect_equal(96, simulation.state.total_kills, "draining deaths twice cannot duplicate rewards")
	a.expect_equal(0, simulation.enemy_system.enemy_store.orphan_count() + simulation.xp_pickup_pool.orphan_count(), "bulk removal leaves every slot accounted for")


func test_native_events_survive_multiple_ticks_and_readonly_snapshots(a: Variant, _context: Dictionary) -> void:
	var catalog: DefinitionCatalog = BalanceTestFixtures.catalog()
	var simulation := CombatSimulation.new()
	simulation.initialize(RunStateFactory.create(4202, catalog), catalog)
	for phase: int in [2, 3]:
		simulation._queue_presentation_event(simulation._make_presentation_event(
			CombatPresentationEvent.Kind.BOSS_PHASE_CHANGED, &"boss_phase", Vector2(phase, 0.0),
			CombatPresentationEvent.Priority.IMPORTANT, phase))
		simulation.advance_tick(Vector2.ZERO)
	a.expect_true(simulation.build_snapshot().presentation_events.is_empty(), "drawing reads do not drain events")
	simulation.build_snapshot()
	var phases: Array[int] = []
	for event: CombatPresentationEvent in simulation.take_events().presentation_events:
		if event.kind == CombatPresentationEvent.Kind.BOSS_PHASE_CHANGED:
			phases.append(event.count)
	a.expect_equal([2, 3], phases, "important changes retain their order across simulation ticks")
	a.expect_true(simulation.take_events().presentation_events.is_empty(), "each event can be drained only once")
