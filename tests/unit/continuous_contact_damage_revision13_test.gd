extends RefCounted


func test_names() -> PackedStringArray:
	return PackedStringArray([
		"catalog_locks_contact_damage_and_radius_without_per_enemy_cadence",
		"seeking_enemy_stops_at_contact_and_rehits_after_thirty_protected_ticks",
		"player_pushes_enemy_at_full_speed_and_recontact_keeps_shared_invulnerability",
		"all_active_enemy_kinds_offer_contact_while_entry_and_stop_gate_actions",
		"exact_overlap_is_deterministic_and_wall_clamp_allows_temporary_overlap",
		"fixed_direction_swarm_crosses_the_player_without_soft_separation",
		"contact_and_projectiles_apply_only_the_strongest_candidate_and_consume_hits",
		"equal_damage_candidate_ties_use_stable_source_entity_pool_order",
	])


func run_test(test_name: String, assertions: Variant, _context: Dictionary) -> void:
	match test_name:
		"catalog_locks_contact_damage_and_radius_without_per_enemy_cadence":
			_test_contact_catalog_contract(assertions)
		"seeking_enemy_stops_at_contact_and_rehits_after_thirty_protected_ticks":
			_test_continuous_contact(assertions)
		"player_pushes_enemy_at_full_speed_and_recontact_keeps_shared_invulnerability":
			_test_player_push_and_recontact(assertions)
		"all_active_enemy_kinds_offer_contact_while_entry_and_stop_gate_actions":
			_test_enemy_kinds_entry_and_stop(assertions)
		"exact_overlap_is_deterministic_and_wall_clamp_allows_temporary_overlap":
			_test_exact_overlap_and_wall(assertions)
		"fixed_direction_swarm_crosses_the_player_without_soft_separation":
			_test_swarm_passthrough(assertions)
		"contact_and_projectiles_apply_only_the_strongest_candidate_and_consume_hits":
			_test_maximum_damage_and_projectile_consumption(assertions)
		"equal_damage_candidate_ties_use_stable_source_entity_pool_order":
			_test_stable_tie_break(assertions)
		_:
			assertions.expect_true(false, "registered revision thirteen contact-damage test")


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
	assertions.expect_float(0.38, definition.body_radius, "revision thirteen locks pursuer radius")
	assertions.expect_float(8.0, definition.contact_damage, "revision thirteen locks pursuer contact damage")
	var canonical: SurvivalContentManifest = catalog.manifest()
	var enemy_index: int = _enemy_index(canonical, &"pursuer")
	var radius_drift: EnemyDefinition = definition.duplicate(true) as EnemyDefinition
	radius_drift.body_radius += 0.01
	assertions.expect_false(
		DefinitionCatalog.new().validate_manifest(
			_manifest_with_enemy(canonical, enemy_index, radius_drift)
		),
		"catalog rejects contact-radius drift",
	)
	var damage_drift: EnemyDefinition = definition.duplicate(true) as EnemyDefinition
	damage_drift.contact_damage += 1.0
	assertions.expect_false(
		DefinitionCatalog.new().validate_manifest(
			_manifest_with_enemy(canonical, enemy_index, damage_drift)
		),
		"catalog rejects contact-damage drift",
	)


func _test_continuous_contact(assertions: Variant) -> void:
	var simulation: CombatSimulation = _simulation(assertions, 13_001)
	if simulation == null:
		return
	var definition: EnemyDefinition = simulation.catalog.enemy(&"pursuer")
	var contact_radius: float = CombatEnvelope.PLAYER_BODY_RADIUS + definition.body_radius
	var enemy: EnemyEntity = simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.PURSUER,
		Vector2(contact_radius + definition.move_speed / 120.0, 0.0),
	)
	var ids: Array[int] = [enemy.entity_id]
	var expected_damage: float = definition.contact_damage
	var candidate_ticks: int = 0
	for tick: int in range(1, 33):
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
		if tick == 1:
			assertions.expect_float(
				100.0 - expected_damage,
				simulation.state.current_hp,
				"first contact damages immediately",
			)
		elif tick == 31:
			assertions.expect_float(
				100.0 - expected_damage,
				simulation.state.current_hp,
				"the next thirty combat ticks remain protected",
			)
	assertions.expect_equal(32, candidate_ticks, "overlap produces one contact candidate every tick")
	assertions.expect_float(
		100.0 - expected_damage * 2.0,
		simulation.state.current_hp,
		"contact damages again on the first tick after the protection window",
	)


func _test_player_push_and_recontact(assertions: Variant) -> void:
	var simulation: CombatSimulation = _simulation(assertions, 13_002)
	if simulation == null:
		return
	var definition: EnemyDefinition = simulation.catalog.enemy(&"pursuer")
	var contact_radius: float = CombatEnvelope.PLAYER_BODY_RADIUS + definition.body_radius
	var enemy: EnemyEntity = simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.PURSUER,
		Vector2(contact_radius, 0.0),
	)
	var ids: Array[int] = [enemy.entity_id]
	simulation.state.combat_tick = 1
	simulation._move_player(Vector2.RIGHT)
	simulation.enemy_system.advance_snapshot(ids, simulation.player_position, 1)
	assertions.expect_float(
		CombatSimulation.PLAYER_SPEED / float(RunState.TICKS_PER_SECOND),
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
	var protected_candidates: Array[Dictionary] = (
		simulation.enemy_system.resolve_contact_damage_candidates(
			ids,
			simulation.player_position,
			20,
		)
	)
	simulation._apply_player_damage_candidates(protected_candidates)
	assertions.expect_float(
		hp_after_first_hit,
		simulation.state.current_hp,
		"recontact does not reset or bypass the shared remaining invulnerability",
	)
	simulation.state.combat_tick = 32
	var eligible_candidates: Array[Dictionary] = (
		simulation.enemy_system.resolve_contact_damage_candidates(
			ids,
			simulation.player_position,
			32,
		)
	)
	simulation._apply_player_damage_candidates(eligible_candidates)
	assertions.expect_float(
		hp_after_first_hit - definition.contact_damage,
		simulation.state.current_hp,
		"recontact damages as soon as the original invulnerability expires",
	)


func _test_enemy_kinds_entry_and_stop(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	if catalog == null:
		return
	var state: RunState = RunStateFactory.create(13_003, catalog)
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
		CombatEnvelope.NORMAL_ENTRY_TICKS,
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
	var first_state: RunState = RunStateFactory.create(13_004, catalog)
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
	var contact_radius: float = CombatEnvelope.PLAYER_BODY_RADIUS + definition.body_radius
	var expected_position: Vector2 = (
		first_system._deterministic_contact_direction(first.entity_id) * contact_radius
	)
	assertions.expect_true(
		first.position.is_equal_approx(expected_position),
		"an exact center overlap separates along the entity-ID-derived direction",
	)

	var replay_state: RunState = RunStateFactory.create(13_004, catalog)
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

	var wall_state: RunState = RunStateFactory.create(13_005, catalog)
	var wall_system := EnemySystem.new()
	wall_system.initialize(wall_state, catalog)
	var wall_player := Vector2(CombatEnvelope.PLAYER_CENTER_LIMIT, 0.0)
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
		CombatEnvelope.enemy_center_limit(definition.body_radius),
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
	var state: RunState = RunStateFactory.create(13_006, catalog)
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
		< CombatEnvelope.PLAYER_BODY_RADIUS + unit.body_radius,
		"swarm is not pushed out to the soft-contact radius",
	)
	assertions.expect_equal(
		1,
		system.resolve_contact_damage_candidates([enemy.entity_id], Vector2.ZERO, 1).size(),
		"a passing swarm member still offers contact on its overlap tick",
	)


func _test_maximum_damage_and_projectile_consumption(assertions: Variant) -> void:
	var simulation: CombatSimulation = _simulation(assertions, 13_007)
	if simulation == null:
		return
	simulation.state.combat_tick = 100
	simulation.state.weapons.clear()
	simulation.spawn_fixture_enemy(GameTypes.EnemyType.PURSUER, Vector2.ZERO)
	simulation.spawn_fixture_enemy(GameTypes.EnemyType.ELITE, Vector2.ZERO)
	_spawn_hostile_projectile(simulation, 12.0, &"weaker_projectile")
	_spawn_hostile_projectile(simulation, 30.0, &"stronger_projectile")
	assertions.expect_true(simulation.advance_tick(Vector2.ZERO), "combined collision tick advances")
	assertions.expect_float(70.0, simulation.state.current_hp, "only the largest post-multiplier damage is applied")
	assertions.expect_equal(0, simulation.projectile_pool.active_count(), "selected and unselected collided projectiles are consumed")

	_spawn_hostile_projectile(simulation, 99.0, &"invulnerable_projectile")
	assertions.expect_true(simulation.advance_tick(Vector2.ZERO), "invulnerable collision tick advances")
	assertions.expect_float(70.0, simulation.state.current_hp, "the shared invulnerability blocks the next collision tick")
	assertions.expect_equal(0, simulation.projectile_pool.active_count(), "a projectile collided during invulnerability is still consumed")


func _test_stable_tie_break(assertions: Variant) -> void:
	var simulation: CombatSimulation = _simulation(assertions, 13_008)
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


func _spawn_hostile_projectile(
	simulation: CombatSimulation,
	damage: float,
	source_effect_id: StringName,
) -> ProjectileState:
	return simulation.projectile_pool.acquire(
		ProjectileState.FACTION_ENEMY,
		&"revision13_contact_probe",
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
) -> Dictionary:
	return {
		"raw_damage": damage,
		"source_effect_id": source_effect_id,
		"source_entity_id": source_entity_id,
		"source_pool_index": source_pool_index,
		"source_generation": 1,
	}


func _manifest_with_enemy(
	manifest: SurvivalContentManifest,
	enemy_index: int,
	enemy: EnemyDefinition,
) -> SurvivalContentManifest:
	var copy: SurvivalContentManifest = manifest.duplicate(true) as SurvivalContentManifest
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
		catalog.load_and_validate(),
		"revision thirteen contact content validates: %s" % catalog.error_text,
	)
	return catalog if catalog.is_valid else null
