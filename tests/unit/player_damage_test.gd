extends RefCounted


func test_names() -> PackedStringArray:
	return PackedStringArray([
		"catalog_accepts_contact_tuning_without_per_enemy_cadence",
		"seeking_enemy_stops_at_contact_and_damages_every_tick",
		"player_pushes_enemy_at_full_speed_and_recontact_damages_immediately",
		"all_active_enemy_kinds_offer_contact_while_entry_and_stop_gate_actions",
		"exact_overlap_is_deterministic_and_wall_clamp_allows_temporary_overlap",
		"fixed_direction_swarm_crosses_the_player_without_soft_separation",
		"contact_and_projectiles_apply_only_the_strongest_candidate_every_tick",
		"level_up_resume_protection_consumes_projectiles_without_damage",
		"player_hit_feedback_is_emitted_each_damage_tick_with_audio_cap",
		"equal_damage_candidate_ties_use_stable_source_entity_pool_order",
	])


func run_test(test_name: String, assertions: Variant, _context: Dictionary) -> void:
	match test_name:
		"catalog_accepts_contact_tuning_without_per_enemy_cadence":
			_test_contact_catalog_contract(assertions)
		"seeking_enemy_stops_at_contact_and_damages_every_tick":
			_test_continuous_contact(assertions)
		"player_pushes_enemy_at_full_speed_and_recontact_damages_immediately":
			_test_player_push_and_recontact(assertions)
		"all_active_enemy_kinds_offer_contact_while_entry_and_stop_gate_actions":
			_test_enemy_kinds_entry_and_stop(assertions)
		"exact_overlap_is_deterministic_and_wall_clamp_allows_temporary_overlap":
			_test_exact_overlap_and_wall(assertions)
		"fixed_direction_swarm_crosses_the_player_without_soft_separation":
			_test_swarm_passthrough(assertions)
		"contact_and_projectiles_apply_only_the_strongest_candidate_every_tick":
			_test_maximum_damage_and_projectile_consumption(assertions)
		"level_up_resume_protection_consumes_projectiles_without_damage":
			_test_level_up_protection_and_projectile_consumption(assertions)
		"player_hit_feedback_is_emitted_each_damage_tick_with_audio_cap":
			_test_player_hit_feedback_and_audio_cap(assertions)
		"equal_damage_candidate_ties_use_stable_source_entity_pool_order":
			_test_stable_tie_break(assertions)
		_:
			assertions.expect_true(false, "registered contact-damage test")


func _test_contact_catalog_contract(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	if catalog == null:
		return
	var definition: EnemyDefinition = catalog.enemy(&"pursuer")
	var property_names: Array[StringName] = []
	for property: Dictionary in definition.get_property_list():
		property_names.append(StringName(property.get("name", &"")))
	assertions.expect_false(
		property_names.has(&"contact_interval_ticks"),
		"enemy definitions no longer expose a per-enemy contact cadence",
	)
	var canonical: SurvivalContentManifest = catalog.manifest()
	var manifest_property_names: Array[StringName] = []
	for property: Dictionary in canonical.get_property_list():
		manifest_property_names.append(StringName(property.get("name", &"")))
	assertions.expect_false(
		manifest_property_names.has(&"damage_invulnerability_ticks"),
		"the global post-hit invulnerability setting is removed",
	)
	assertions.expect_false(
		manifest_property_names.has(&"modal_resume_invulnerability_ticks"),
		"the generic modal protection setting is removed",
	)
	var enemy_index: int = _enemy_index(canonical, &"pursuer")
	var radius_drift: EnemyDefinition = definition.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as EnemyDefinition
	radius_drift.body_radius += 0.01
	assertions.expect_true(
		DefinitionCatalog.new().validate_manifest(
			_manifest_with_enemy(canonical, enemy_index, radius_drift)
		),
		"catalog accepts a valid contact-radius change",
	)
	var damage_drift: EnemyDefinition = definition.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as EnemyDefinition
	damage_drift.contact_damage += 1.0
	assertions.expect_true(
		DefinitionCatalog.new().validate_manifest(
			_manifest_with_enemy(canonical, enemy_index, damage_drift)
		),
		"catalog accepts a valid contact-damage change",
	)


func _test_continuous_contact(assertions: Variant) -> void:
	var simulation: CombatSimulation = _simulation(assertions, 14_001)
	if simulation == null:
		return
	var definition: EnemyDefinition = simulation.catalog.enemy(&"pursuer")
	var contact_radius: float = BalanceTestFixtures.catalog().envelope.player_body_radius + definition.body_radius
	var enemy: EnemyEntity = simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.PURSUER,
		Vector2(contact_radius + definition.move_speed / 120.0, 0.0),
	)
	var ids: Array[int] = [enemy.entity_id]
	var expected_damage: float = definition.contact_damage
	var candidate_ticks: int = 0
	for tick: int in range(1, 6):
		simulation.state.combat_tick = tick
		simulation.enemy_system.advance_snapshot(ids, simulation.player_position, tick)
		var candidates: Array[Dictionary] = (
			simulation.enemy_system.resolve_contact_damage_candidates(
				ids,
				simulation.player_position,
				tick,
			)
		)
		candidate_ticks += candidates.size()
		simulation._apply_player_damage_candidates(candidates)
		assertions.expect_float(
			contact_radius,
			enemy.position.distance_to(simulation.player_position),
			"pursuer remains at the combined contact radius",
		)
		assertions.expect_float(
			100.0 - expected_damage * float(tick),
			simulation.state.current_hp,
			"contact applies damage on every combat tick",
		)
	assertions.expect_equal(5, candidate_ticks, "overlap produces one contact candidate every tick")
	assertions.expect_float(
		100.0 - expected_damage * 5.0,
		simulation.state.current_hp,
		"five contact ticks apply five full damage instances",
	)


func _test_player_push_and_recontact(assertions: Variant) -> void:
	var simulation: CombatSimulation = _simulation(assertions, 14_002)
	if simulation == null:
		return
	var definition: EnemyDefinition = simulation.catalog.enemy(&"pursuer")
	var contact_radius: float = BalanceTestFixtures.catalog().envelope.player_body_radius + definition.body_radius
	var enemy: EnemyEntity = simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.PURSUER,
		Vector2(contact_radius, 0.0),
	)
	var ids: Array[int] = [enemy.entity_id]
	simulation.state.combat_tick = 1
	simulation._move_player(Vector2.RIGHT)
	simulation.enemy_system.advance_snapshot(ids, simulation.player_position, 1)
	assertions.expect_float(
		BalanceTestFixtures.catalog().manifest().player.move_speed / float(RunState.TICKS_PER_SECOND),
		simulation.player_position.x,
		"contact never reduces the player's configured movement step",
	)
	assertions.expect_float(
		contact_radius,
		enemy.position.distance_to(simulation.player_position),
		"player penetration pushes the enemy only to the combined radius",
	)
	var first_candidates: Array[Dictionary] = (
		simulation.enemy_system.resolve_contact_damage_candidates(
			ids,
			simulation.player_position,
			1,
		)
	)
	simulation._apply_player_damage_candidates(first_candidates)
	var hp_after_first_hit: float = simulation.state.current_hp

	simulation.state.combat_tick = 10
	simulation.player_position = Vector2(-5.0, 0.0)
	simulation.enemy_system.advance_snapshot(ids, simulation.player_position, 10)
	assertions.expect_equal(
		0,
		simulation.enemy_system.resolve_contact_damage_candidates(
			ids,
			simulation.player_position,
			10,
		).size(),
		"leaving contact removes the damage candidate",
	)

	simulation.state.combat_tick = 20
	simulation.player_position = enemy.position - Vector2.RIGHT * contact_radius
	var recontact_candidates: Array[Dictionary] = (
		simulation.enemy_system.resolve_contact_damage_candidates(
			ids,
			simulation.player_position,
			20,
		)
	)
	simulation._apply_player_damage_candidates(recontact_candidates)
	assertions.expect_float(
		hp_after_first_hit - definition.contact_damage,
		simulation.state.current_hp,
		"recontact damages immediately without residual post-hit protection",
	)
	simulation.state.combat_tick = 21
	var next_tick_candidates: Array[Dictionary] = (
		simulation.enemy_system.resolve_contact_damage_candidates(
			ids,
			simulation.player_position,
			21,
		)
	)
	simulation._apply_player_damage_candidates(next_tick_candidates)
	assertions.expect_float(
		hp_after_first_hit - definition.contact_damage * 2.0,
		simulation.state.current_hp,
		"continued recontact damages again on the next combat tick",
	)


func _test_enemy_kinds_entry_and_stop(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	if catalog == null:
		return
	var state: RunState = RunStateFactory.create(14_003, catalog)
	state.combat_tick = 100
	var system := EnemySystem.new()
	system.initialize(state, catalog)
	var boss_id: int = -1
	for enemy_type: GameTypes.EnemyType in [
		GameTypes.EnemyType.PURSUER,
		GameTypes.EnemyType.SWARMER,
		GameTypes.EnemyType.BULWARK,
		GameTypes.EnemyType.SHOOTER,
		GameTypes.EnemyType.ELITE,
		GameTypes.EnemyType.BOSS,
	]:
		var definition: EnemyDefinition = catalog.enemy_for_type(enemy_type)
		var enemy: EnemyEntity = system.enemy_store.try_spawn(
			state,
			enemy_type,
			definition,
			Vector2.ZERO,
			1.0,
			1.0,
			99,
		)
		if enemy_type == GameTypes.EnemyType.BOSS:
			boss_id = enemy.entity_id
	var swarm: EnemyEntity = system.enemy_store.try_spawn(
		state,
		GameTypes.EnemyType.SWARMER,
		catalog.manifest().swarm_event.unit_definition,
		Vector2.ZERO,
		1.0,
		1.0,
		99,
	)
	swarm.configure_swarm_event(1, Vector2.RIGHT, 10.0, false)
	system.enemy_store.try_spawn(
		state,
		GameTypes.EnemyType.PURSUER,
		catalog.enemy(&"pursuer"),
		Vector2.ZERO,
		1.0,
		1.0,
		100,
		BalanceTestFixtures.catalog().envelope.normal_entry_ticks,
	)
	var ids: Array[int] = system.snapshot_ids()
	var active_candidates: Array[Dictionary] = system.resolve_contact_damage_candidates(
		ids,
		Vector2.ZERO,
		100,
	)
	assertions.expect_equal(
		7,
		active_candidates.size(),
		"all six active enemy types and the fixed swarm member offer contact",
	)
	state.stop_until_tick = 200
	var stopped_candidates: Array[Dictionary] = system.resolve_contact_damage_candidates(
		ids,
		Vector2.ZERO,
		100,
	)
	assertions.expect_equal(1, stopped_candidates.size(), "STOP gates normal and swarm contact actions")
	assertions.expect_equal(
		boss_id,
		int(stopped_candidates[0].get("source_entity_id", -1)),
		"the half-speed boss remains action-capable during STOP",
	)


func _test_exact_overlap_and_wall(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	if catalog == null:
		return
	var first_state: RunState = RunStateFactory.create(14_004, catalog)
	var first_system := EnemySystem.new()
	first_system.initialize(first_state, catalog)
	var definition: EnemyDefinition = catalog.enemy(&"pursuer")
	var first: EnemyEntity = first_system.enemy_store.try_spawn(
		first_state,
		GameTypes.EnemyType.PURSUER,
		definition,
		Vector2.ZERO,
		1.0,
		1.0,
		0,
	)
	first_state.combat_tick = 1
	first_system.advance_snapshot([first.entity_id], Vector2.ZERO, 1)
	var contact_radius: float = BalanceTestFixtures.catalog().envelope.player_body_radius + definition.body_radius
	var expected_position: Vector2 = (
		first_system._deterministic_contact_direction(first.entity_id) * contact_radius
	)
	assertions.expect_true(
		first.position.is_equal_approx(expected_position),
		"an exact center overlap separates along the entity-ID-derived direction",
	)

	var replay_state: RunState = RunStateFactory.create(14_004, catalog)
	var replay_system := EnemySystem.new()
	replay_system.initialize(replay_state, catalog)
	var replay: EnemyEntity = replay_system.enemy_store.try_spawn(
		replay_state,
		GameTypes.EnemyType.PURSUER,
		definition,
		Vector2.ZERO,
		1.0,
		1.0,
		0,
	)
	replay_state.combat_tick = 1
	replay_system.advance_snapshot([replay.entity_id], Vector2.ZERO, 1)
	assertions.expect_equal(first.position, replay.position, "exact-overlap separation replays deterministically")

	var wall_state: RunState = RunStateFactory.create(14_005, catalog)
	var wall_system := EnemySystem.new()
	wall_system.initialize(wall_state, catalog)
	var wall_player := Vector2(BalanceTestFixtures.catalog().envelope.player_center_max.x, 0.0)
	var wall_enemy: EnemyEntity = wall_system.enemy_store.try_spawn(
		wall_state,
		GameTypes.EnemyType.PURSUER,
		definition,
		wall_player + Vector2(0.01, 0.0),
		1.0,
		1.0,
		0,
	)
	wall_state.combat_tick = 1
	wall_system.advance_snapshot([wall_enemy.entity_id], wall_player, 1)
	assertions.expect_float(
		BalanceTestFixtures.catalog().envelope.enemy_center_limit(definition.body_radius).x,
		wall_enemy.position.x,
		"wall-constrained separation holds the enemy at its arena boundary",
	)
	assertions.expect_true(
		wall_enemy.position.distance_to(wall_player) < contact_radius,
		"the arena edge permits temporary overlap when full separation is impossible",
	)
	assertions.expect_equal(
		1,
		wall_system.resolve_contact_damage_candidates(
			[wall_enemy.entity_id],
			wall_player,
			1,
		).size(),
		"wall-constrained overlap remains a contact candidate",
	)


func _test_swarm_passthrough(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	if catalog == null:
		return
	var state: RunState = RunStateFactory.create(14_006, catalog)
	var system := EnemySystem.new()
	system.initialize(state, catalog)
	var unit: EnemyDefinition = catalog.manifest().swarm_event.unit_definition
	var enemy: EnemyEntity = system.enemy_store.try_spawn(
		state,
		GameTypes.EnemyType.SWARMER,
		unit,
		Vector2(-0.02, 0.0),
		1.0,
		1.0,
		0,
	)
	enemy.configure_swarm_event(1, Vector2.RIGHT, 10.0, false)
	state.combat_tick = 1
	system.advance_snapshot([enemy.entity_id], Vector2.ZERO, 1)
	assertions.expect_true(enemy.position.x > 0.0, "fixed-direction swarm crosses through the player center")
	assertions.expect_float(
		unit.move_speed / float(RunState.TICKS_PER_SECOND) - 0.02,
		enemy.position.x,
		"swarm crossing keeps its configured travel step",
	)
	assertions.expect_true(
		enemy.position.distance_to(Vector2.ZERO)
		< BalanceTestFixtures.catalog().envelope.player_body_radius + unit.body_radius,
		"swarm is not pushed out to the soft-contact radius",
	)
	assertions.expect_equal(
		1,
		system.resolve_contact_damage_candidates([enemy.entity_id], Vector2.ZERO, 1).size(),
		"a passing swarm member still offers contact on its overlap tick",
	)


func _test_maximum_damage_and_projectile_consumption(assertions: Variant) -> void:
	var simulation: CombatSimulation = _simulation(assertions, 14_007)
	if simulation == null:
		return
	simulation.state.combat_tick = 100
	simulation.state.max_hp = 300.0
	simulation.state.current_hp = 300.0
	simulation.state.weapons.clear()
	simulation.spawn_fixture_enemy(GameTypes.EnemyType.PURSUER, Vector2.ZERO)
	simulation.spawn_fixture_enemy(GameTypes.EnemyType.ELITE, Vector2.ZERO)
	_spawn_hostile_projectile(simulation, 12.0, &"weaker_projectile")
	_spawn_hostile_projectile(simulation, 30.0, &"stronger_projectile")
	assertions.expect_true(simulation.advance_tick(Vector2.ZERO), "combined collision tick advances")
	assertions.expect_float(270.0, simulation.state.current_hp, "only the largest post-multiplier damage is applied")
	assertions.expect_equal(0, simulation.projectile_pool.active_count(), "selected and unselected collided projectiles are consumed")

	_spawn_hostile_projectile(simulation, 99.0, &"next_tick_projectile")
	assertions.expect_true(simulation.advance_tick(Vector2.ZERO), "next collision tick advances")
	assertions.expect_float(171.0, simulation.state.current_hp, "the strongest next-tick projectile applies without post-hit protection")
	assertions.expect_equal(0, simulation.projectile_pool.active_count(), "the next-tick projectile is consumed")
	assertions.expect_true(simulation.advance_tick(Vector2.ZERO), "continued contact tick advances")
	assertions.expect_float(153.0, simulation.state.current_hp, "contact resumes as the next tick's maximum candidate")


func _test_level_up_protection_and_projectile_consumption(assertions: Variant) -> void:
	var simulation: CombatSimulation = _simulation(assertions, 14_008)
	if simulation == null:
		return
	simulation.state.combat_tick = 100
	simulation.state.max_hp = 200.0
	simulation.state.current_hp = 200.0
	simulation.state.weapons.clear()
	simulation.spawn_fixture_enemy(GameTypes.EnemyType.ELITE, Vector2.ZERO)
	simulation.grant_level_up_resume_invulnerability_ticks(45)
	_spawn_hostile_projectile(simulation, 99.0, &"protected_projectile")
	assertions.expect_true(simulation.advance_tick(Vector2.ZERO), "protected collision tick advances")
	assertions.expect_float(200.0, simulation.state.current_hp, "level-up resume protection blocks every damage candidate")
	assertions.expect_equal(0, simulation.projectile_pool.active_count(), "a projectile collided during protection is consumed")
	assertions.expect_false(simulation._player_hit_this_tick, "protected collision emits no player-hit event")

	simulation.state.combat_tick = 144
	_spawn_hostile_projectile(simulation, 99.0, &"last_protected_projectile")
	assertions.expect_true(simulation.advance_tick(Vector2.ZERO), "forty-fifth protected update advances")
	assertions.expect_float(200.0, simulation.state.current_hp, "the forty-fifth resumed update remains protected")
	assertions.expect_equal(0, simulation.projectile_pool.active_count(), "the last protected projectile is consumed")

	_spawn_hostile_projectile(simulation, 40.0, &"first_eligible_projectile")
	assertions.expect_true(simulation.advance_tick(Vector2.ZERO), "forty-sixth resumed update advances")
	assertions.expect_float(160.0, simulation.state.current_hp, "damage resumes on the forty-sixth update")
	assertions.expect_equal(0, simulation.projectile_pool.active_count(), "the first eligible projectile is consumed")
	assertions.expect_true(simulation._player_hit_this_tick, "eligible collision emits a player-hit event")


func _test_player_hit_feedback_and_audio_cap(assertions: Variant) -> void:
	var simulation: CombatSimulation = _simulation(assertions, 14_009)
	if simulation == null:
		return
	simulation.state.max_hp = 200.0
	simulation.state.current_hp = 200.0
	var player_hit_events: int = 0
	for tick: int in range(1, RunState.TICKS_PER_SECOND + 1):
		simulation.state.combat_tick = tick
		simulation._step_events.clear()
		simulation._presentation_events.clear()
		simulation._player_hit_this_tick = false
		simulation._apply_raw_player_damage(1.0)
		simulation._flush_transient_feedback()
		for event: CombatPresentationEvent in simulation._presentation_events:
			if event.kind == CombatPresentationEvent.Kind.PLAYER_HIT:
				player_hit_events += 1
		simulation._record_audio_cue_metrics()
	assertions.expect_float(140.0, simulation.state.current_hp, "sixty combat ticks apply sixty damage instances")
	assertions.expect_equal(60, player_hit_events, "every damaging tick emits one player-hit presentation event")
	assertions.expect_equal(8, simulation._audio_cue_admission.admitted_count, "existing noncritical audio cap admits eight cues per second")
	assertions.expect_equal(52, simulation._audio_cue_admission.suppressed_count, "remaining per-tick hit cues are audio-suppressed")


func _test_stable_tie_break(assertions: Variant) -> void:
	var simulation: CombatSimulation = _simulation(assertions, 14_010)
	if simulation == null:
		return
	var source_winner: Dictionary = simulation._select_player_damage_candidate([
		_damage_candidate(10.0, &"zeta", 1, 1),
		_damage_candidate(10.0, &"alpha", 9, 9),
	])
	assertions.expect_equal(&"alpha", source_winner.get("source_effect_id", &""), "equal damage first uses stable source order")
	var entity_winner: Dictionary = simulation._select_player_damage_candidate([
		_damage_candidate(10.0, &"same", 7, 1),
		_damage_candidate(10.0, &"same", 3, 9),
	])
	assertions.expect_equal(3, int(entity_winner.get("source_entity_id", -1)), "equal source next uses stable entity order")
	var pool_winner: Dictionary = simulation._select_player_damage_candidate([
		_damage_candidate(10.0, &"same", 3, 8),
		_damage_candidate(10.0, &"same", 3, 2),
	])
	assertions.expect_equal(2, int(pool_winner.get("source_pool_index", -1)), "equal source and entity use stable pool order")
	var generation_winner: Dictionary = simulation._select_player_damage_candidate([
		_damage_candidate(10.0, &"same", 3, 2, 8),
		_damage_candidate(10.0, &"same", 3, 2, 4),
	])
	assertions.expect_equal(4, int(generation_winner.get("source_generation", -1)), "fully tied candidates use stable generation order")


func _spawn_hostile_projectile(
	simulation: CombatSimulation,
	damage: float,
	source_effect_id: StringName,
) -> ProjectileState:
	return simulation.projectile_pool.acquire(
		ProjectileState.FACTION_ENEMY,
		&"player_damage_probe",
		-1,
		simulation.player_position,
		Vector2.ZERO,
		0.2,
		damage,
		1.0,
		1.0,
		simulation.player_position,
		0,
		simulation.state.combat_tick - 1,
		source_effect_id,
	)


func _damage_candidate(
	damage: float,
	source_effect_id: StringName,
	source_entity_id: int,
	source_pool_index: int,
	source_generation: int = 1,
) -> Dictionary:
	return {
		"raw_damage": damage,
		"source_effect_id": source_effect_id,
		"source_entity_id": source_entity_id,
		"source_pool_index": source_pool_index,
		"source_generation": source_generation,
	}


func _manifest_with_enemy(
	manifest: SurvivalContentManifest,
	enemy_index: int,
	enemy: EnemyDefinition,
) -> SurvivalContentManifest:
	var copy: SurvivalContentManifest = manifest.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as SurvivalContentManifest
	var enemies: Array[EnemyDefinition] = []
	enemies.assign(manifest.enemies)
	enemies[enemy_index] = enemy
	copy.enemies = enemies
	return copy


func _enemy_index(manifest: SurvivalContentManifest, enemy_id: StringName) -> int:
	for index: int in range(manifest.enemies.size()):
		if manifest.enemies[index].enemy_id == enemy_id:
			return index
	return -1


func _simulation(assertions: Variant, run_seed: int) -> CombatSimulation:
	var catalog: DefinitionCatalog = _catalog(assertions)
	if catalog == null:
		return null
	var state: RunState = RunStateFactory.create(run_seed, catalog)
	var simulation := CombatSimulation.new()
	simulation.initialize(state, catalog)
	return simulation


func _catalog(assertions: Variant) -> DefinitionCatalog:
	var catalog := DefinitionCatalog.new()
	assertions.expect_true(
		catalog.validate_manifest(BalanceTestFixtures.manifest()),
		"contact content validates: %s" % catalog.error_text,
	)
	return catalog if catalog.is_valid else null
