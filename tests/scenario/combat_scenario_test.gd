extends RefCounted


func test_continuous_clock_and_time_only_spawn_targets(assertions: Variant, _context: Dictionary) -> void:
	var setup: Dictionary = _simulation(assertions, 8101)
	var simulation: CombatSimulation = setup.get("simulation") as CombatSimulation
	if simulation == null:
		return
	for _tick: int in range(60):
		simulation.step(Vector2.ZERO)
	assertions.expect_equal(60, simulation.state.combat_tick, "one second advances exactly sixty combat ticks")
	assertions.expect_float(1.0, simulation.state.elapsed_seconds(), "HUD clock derives from integer combat ticks")
	var first_segment: EnemySegmentDefinition = simulation.catalog.segment_for_tick(simulation.state.combat_tick)
	assertions.expect_equal(16, first_segment.target_active, "first minute uses the active-enemy target")
	assertions.expect_true(simulation.enemy_system.enemy_store.active_count() <= 16, "spawn fill never overshoots the segment target")


func test_scheduled_elites_and_final_boss_are_guaranteed(assertions: Variant, _context: Dictionary) -> void:
	var setup: Dictionary = _simulation(assertions, 8102)
	var simulation: CombatSimulation = setup.get("simulation") as CombatSimulation
	if simulation == null:
		return
	var schedule: PackedInt32Array = simulation.catalog.elite_spawn_ticks
	for elite_index: int in range(schedule.size()):
		simulation.state.combat_tick = schedule[elite_index]
		var spawned: Array[EnemyEntity] = simulation.enemy_system.resolve_scheduled_spawns(
			Vector2.ZERO,
			schedule[elite_index],
		)
		assertions.expect_equal(1, spawned.size(), "scheduled elite %d spawns exactly once" % elite_index)
		assertions.expect_equal(GameTypes.EnemyType.ELITE, spawned[0].enemy_type, "scheduled spawn is an elite")
		assertions.expect_equal(elite_index, spawned[0].elite_serial, "elite carries its chest serial")
		assertions.expect_equal(0, simulation.enemy_system.resolve_scheduled_spawns(Vector2.ZERO, schedule[elite_index]).size(), "same scheduled elite cannot duplicate")
	simulation.state.combat_tick = BalanceTestFixtures.catalog().boss_start_tick
	var boss_spawns: Array[EnemyEntity] = simulation.enemy_system.resolve_scheduled_spawns(
		Vector2.ZERO,
		BalanceTestFixtures.catalog().boss_start_tick,
	)
	assertions.expect_equal(1, boss_spawns.size(), "the boss boundary creates one final boss")
	assertions.expect_equal(GameTypes.EnemyType.BOSS, boss_spawns[0].enemy_type, "the boss boundary scheduled entity is the boss")
	assertions.expect_true(simulation.state.boss_spawned, "boss-spawn state latches after successful allocation")
	assertions.expect_equal(0, simulation.enemy_system.resolve_normal_spawns(Vector2.ZERO, BalanceTestFixtures.catalog().boss_start_tick).size(), "normal spawning stops at the boss boundary")


func test_stop_freezes_normal_and_halves_boss_projectiles(assertions: Variant, _context: Dictionary) -> void:
	var setup: Dictionary = _simulation(assertions, 8103)
	var simulation: CombatSimulation = setup.get("simulation") as CombatSimulation
	if simulation == null:
		return
	var normal: EnemyEntity = simulation.spawn_fixture_enemy(GameTypes.EnemyType.PURSUER, Vector2(5.0, 0.0), 0)
	var boss: EnemyEntity = simulation.spawn_fixture_enemy(GameTypes.EnemyType.BOSS, Vector2(5.0, 5.0), 0)
	simulation.state.combat_tick = 1
	simulation.state.stop_until_tick = 301
	var normal_before: Vector2 = normal.position
	var boss_before: Vector2 = boss.position
	simulation.enemy_system.advance_snapshot(
		simulation.enemy_system.snapshot_ids(),
		Vector2.ZERO,
		1,
	)
	assertions.expect_equal(normal_before, normal.position, "stop pickup fully freezes a normal enemy")
	var boss_full_step: float = boss.definition.move_speed / float(RunState.TICKS_PER_SECOND)
	assertions.expect_float(boss_full_step * 0.5, boss.position.distance_to(boss_before), "stop pickup moves boss at fifty percent")
	var boss_projectile: ProjectileState = simulation.projectile_pool.acquire(
		ProjectileState.FACTION_ENEMY, &"boss", boss.entity_id, Vector2.ZERO,
		Vector2.RIGHT * 60.0, 0.1, 1.0, 10.0, 1.0, Vector2.RIGHT * 10.0,
		0, 0, &"boss_projectile", ProjectileState.MovementKind.STRAIGHT,
		-1, 60, 0, 0.0, 0.5,
	)
	var projectile_handles: Array[Vector2i] = simulation.projectile_pool.snapshot_active()
	simulation.weapon_system.move_snapshot_projectiles(
		projectile_handles,
		simulation.enemy_system.enemy_store,
		Vector2.ZERO,
		1,
		true,
	)
	assertions.expect_float(0.5, boss_projectile.position.x, "stop moves an existing boss projectile at fifty percent")
	var slowed_boss_hit: Dictionary = simulation.weapon_system.resolve_enemy_projectile(
		Vector2i(boss_projectile.pool_index, boss_projectile.generation),
		Vector2.ZERO,
		1,
	)
	assertions.expect_true(not slowed_boss_hit.is_empty(), "a boss projectile still resolves collision at half speed")


func test_boss_three_phases_and_activation_relative_enrage(assertions: Variant, _context: Dictionary) -> void:
	var setup: Dictionary = _simulation(assertions, 8104)
	var simulation: CombatSimulation = setup.get("simulation") as CombatSimulation
	if simulation == null:
		return
	var boss: EnemyEntity = simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.BOSS,
		Vector2(8.0, 8.0),
		BalanceTestFixtures.catalog().boss_start_tick - BalanceTestFixtures.catalog().envelope.boss_entry_ticks,
		true,
		false,
	)
	simulation.state.boss_spawned = true
	assertions.expect_float(
		boss.definition.base_hp * simulation.catalog.manifest().combat.boss_hp_multiplier,
		boss.max_hp,
		"boss HP uses its dedicated manifest multiplier outside segment scaling",
	)
	assertions.expect_float(
		simulation.catalog.manifest().combat.boss_damage_multiplier,
		boss.damage_multiplier,
		"boss damage uses its dedicated manifest multiplier outside segment scaling",
	)
	simulation.state.combat_tick = BalanceTestFixtures.catalog().boss_start_tick
	boss.hp = boss.max_hp
	simulation.enemy_system.advance_snapshot([boss.entity_id], Vector2.ZERO, BalanceTestFixtures.catalog().boss_start_tick + 1)
	assertions.expect_equal(1, simulation.state.boss_phase, "boss starts in phase one")
	boss.hp = boss.max_hp * 0.66
	simulation.enemy_system.advance_snapshot([boss.entity_id], Vector2.ZERO, BalanceTestFixtures.catalog().boss_start_tick + 2)
	assertions.expect_equal(2, simulation.state.boss_phase, "boss enters phase two at 66 percent HP")
	boss.hp = boss.max_hp * 0.33
	simulation.enemy_system.advance_snapshot([boss.entity_id], Vector2.ZERO, BalanceTestFixtures.catalog().boss_start_tick + 3)
	assertions.expect_equal(3, simulation.state.boss_phase, "boss enters phase three at 33 percent HP")
	boss.boss_action_age_ticks = float(
		simulation.catalog.manifest().combat.boss_enrage_interval_ticks - 1
	)
	simulation.enemy_system.advance_snapshot(
		[boss.entity_id],
		Vector2.ZERO,
		BalanceTestFixtures.catalog().boss_start_tick + 4,
	)
	assertions.expect_equal(1, simulation.state.boss_enrage_stacks, "boss gains one pressure stack after thirty seconds")
	simulation.state.boss_enrage_stacks = 2
	assertions.expect_float(73.0, simulation.enemy_system._boss_action_interval(100, 1), "two enrage stacks and the action rate produce a 73-tick interval")


func test_scheduled_boss_uses_dedicated_manifest_multipliers(assertions: Variant, _context: Dictionary) -> void:
	var canonical := DefinitionCatalog.new()
	assertions.expect_true(canonical.validate_manifest(BalanceTestFixtures.manifest()), "canonical boss fixture content validates")
	if not canonical.is_valid:
		return
	var manifest: SurvivalContentManifest = canonical.manifest().duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as SurvivalContentManifest
	manifest.combat.boss_hp_multiplier = 2.0
	manifest.combat.boss_damage_multiplier = 0.2
	manifest.combat.boss_action_rate_multiplier = (
		0.8
	)
	var custom_catalog := DefinitionCatalog.new()
	assertions.expect_true(
		custom_catalog.validate_manifest(manifest),
		"authorized non-neutral boss multiplier fixture validates",
	)
	if not custom_catalog.is_valid:
		return
	var segment_ten: EnemySegmentDefinition = custom_catalog.segment(9)
	assertions.expect_true(
		not is_equal_approx(manifest.combat.boss_hp_multiplier, segment_ten.hp_multiplier),
		"fixture keeps boss HP separate from segment ten",
	)
	assertions.expect_true(
		not is_equal_approx(manifest.combat.boss_damage_multiplier, segment_ten.damage_multiplier),
		"fixture keeps boss damage separate from segment ten",
	)
	var state: RunState = RunStateFactory.create(8_104_801, custom_catalog)
	var simulation := CombatSimulation.new()
	simulation.initialize(state, custom_catalog)
	state.combat_tick = custom_catalog.boss_start_tick
	var spawned: Array[EnemyEntity] = simulation.enemy_system.resolve_scheduled_spawns(
		Vector2.ZERO,
		custom_catalog.boss_start_tick,
	)
	var boss: EnemyEntity = null
	for enemy: EnemyEntity in spawned:
		if enemy.enemy_type == GameTypes.EnemyType.BOSS:
			boss = enemy
			break
	assertions.expect_true(boss != null, "production scheduler creates the multiplier probe boss")
	if boss == null:
		return
	assertions.expect_float(
		boss.definition.base_hp * manifest.combat.boss_hp_multiplier,
		boss.max_hp,
		"scheduled boss HP uses the dedicated multiplier",
	)
	assertions.expect_float(
		manifest.combat.boss_damage_multiplier,
		boss.damage_multiplier,
		"scheduled boss damage uses the dedicated multiplier",
	)
	assertions.expect_float(
		125.0,
		simulation.enemy_system._boss_action_interval(100, 1),
		"non-neutral boss action rate changes radial-volley cadence",
	)


func test_same_tick_boss_victory_beats_player_death(assertions: Variant, _context: Dictionary) -> void:
	var setup: Dictionary = _simulation(assertions, 8107)
	var simulation: CombatSimulation = setup.get("simulation") as CombatSimulation
	if simulation == null:
		return
	var boss: EnemyEntity = simulation.spawn_fixture_enemy(GameTypes.EnemyType.BOSS, Vector2(2.0, 0.0), -1)
	boss.hp = 1.0
	simulation.state.boss_spawned = true
	simulation.state.boss_hp = boss.hp
	simulation.state.boss_max_hp = boss.max_hp
	simulation.state.current_hp = 1.0
	simulation.projectile_pool.acquire(
		ProjectileState.FACTION_ALLY, &"resonance_wave", -1, boss.position,
		Vector2.ZERO, 3.0, 10.0, 1.0, 1.0, boss.position, 0,
		simulation.state.combat_tick - 1, &"resonance_wave",
	)
	simulation.projectile_pool.acquire(
		ProjectileState.FACTION_ENEMY, &"boss", boss.entity_id, simulation.player_position,
		Vector2.ZERO, 1.0, 99.0, 1.0, 1.0, simulation.player_position, 0,
		simulation.state.combat_tick - 1, &"boss_projectile",
	)
	simulation.step(Vector2.ZERO)
	assertions.expect_equal(0.0, simulation.state.current_hp, "same tick can contain lethal player damage")
	assertions.expect_true(simulation.state.boss_defeated, "same tick also records final boss defeat")
	assertions.expect_equal(GameTypes.RunPhase.RESULT, simulation.state.phase, "boss victory has priority over same-tick player death")


func test_lethal_enemy_still_resolves_ready_attack_before_death(assertions: Variant, _context: Dictionary) -> void:
	var setup: Dictionary = _simulation(assertions, 8109)
	var simulation: CombatSimulation = setup.get("simulation") as CombatSimulation
	if simulation == null:
		return
	var enemy: EnemyEntity = simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.PURSUER,
		simulation.player_position,
		-1,
	)
	enemy.hp = 1.0
	var hp_before: float = simulation.state.current_hp
	var expected_damage: float = enemy.definition.contact_damage * enemy.damage_multiplier
	simulation.projectile_pool.acquire(
		ProjectileState.FACTION_ALLY,
		&"order_probe",
		-1,
		enemy.position,
		Vector2.ZERO,
		1.0,
		2.0,
		1.0,
		1.0,
		enemy.position,
		0,
		-1,
		&"resonance_wave",
	)
	simulation.step(Vector2.ZERO)
	assertions.expect_float(hp_before - expected_damage, simulation.state.current_hp, "a ready contact attack resolves after the enemy takes lethal allied damage")
	assertions.expect_true(not simulation.enemy_system.enemy_store.has_entity(enemy.entity_id), "the lethally hit enemy is removed in the death stage")
	assertions.expect_equal(1, simulation.state.total_kills, "multiple same-tick lethal records count one death")


func test_evolved_damage_combines_into_base_lineage(assertions: Variant, _context: Dictionary) -> void:
	var setup: Dictionary = _simulation(assertions, 8108)
	var simulation: CombatSimulation = setup.get("simulation") as CombatSimulation
	if simulation == null:
		return
	var enemy: EnemyEntity = simulation.spawn_fixture_enemy(GameTypes.EnemyType.BULWARK, Vector2(2.0, 0.0), -1)
	enemy.hp = 1000.0
	enemy.max_hp = 1000.0
	var base_event: CombatEvent = simulation.event_router.create_primary(
		simulation.state, &"weapon_hit", -1, &"homing_core", 10.0,
	)
	simulation._apply_enemy_hit_records([{"entity_id": enemy.entity_id, "event": base_event}])
	var runtime: RunWeapon = simulation.state.weapon_for_lineage(&"homing_core")
	runtime.weapon_id = &"infinite_homing"
	runtime.evolved = true
	var evolved_event: CombatEvent = simulation.event_router.create_primary(
		simulation.state, &"weapon_hit", -1, &"homing_core", 25.0,
	)
	simulation._apply_enemy_hit_records([{"entity_id": enemy.entity_id, "event": evolved_event}])
	assertions.expect_equal(1, simulation.state.weapon_damage_by_lineage.size(), "base and evolved damage share one lineage entry")
	assertions.expect_float(35.0, simulation.state.weapon_damage_by_lineage[&"homing_core"], "lineage damage sums before and after evolution")


func test_level_up_resume_invulnerability_is_limited(assertions: Variant, _context: Dictionary) -> void:
	var setup: Dictionary = _simulation(assertions, 8105)
	var simulation: CombatSimulation = setup.get("simulation") as CombatSimulation
	if simulation == null:
		return
	simulation.state.combat_tick = 100
	simulation.grant_level_up_resume_invulnerability_ticks(45)
	assertions.expect_equal(146, simulation.state.level_up_invulnerable_until_tick, "exclusive deadline covers exactly 45 resumed updates")
	assertions.expect_true(simulation.state.is_level_up_resume_invulnerable(), "level-up resume protection is active before its deadline")
	simulation.state.combat_tick = 145
	assertions.expect_true(simulation.state.is_level_up_resume_invulnerable(), "the forty-fifth resumed update remains protected")
	simulation.state.combat_tick = 146
	assertions.expect_true(not simulation.state.is_level_up_resume_invulnerable(), "the forty-sixth resumed update can take damage")


func test_player_damage_has_no_post_hit_invulnerability(assertions: Variant, _context: Dictionary) -> void:
	var setup: Dictionary = _simulation(assertions, 8107)
	var simulation: CombatSimulation = setup.get("simulation") as CombatSimulation
	if simulation == null:
		return
	simulation.state.combat_tick = 100
	simulation._apply_raw_player_damage(10.0)
	assertions.expect_float(90.0, simulation.state.current_hp, "first damage tick applies")
	simulation.state.combat_tick = 101
	simulation._apply_raw_player_damage(50.0)
	assertions.expect_float(40.0, simulation.state.current_hp, "the next combat tick applies damage without a cooldown")


func test_advance_tick_matches_step_gameplay_state(assertions: Variant, _context: Dictionary) -> void:
	var setup_step: Dictionary = _simulation(assertions, 8108)
	var setup_advance: Dictionary = _simulation(assertions, 8108)
	var step_simulation: CombatSimulation = setup_step.get("simulation") as CombatSimulation
	var advance_simulation: CombatSimulation = setup_advance.get("simulation") as CombatSimulation
	if step_simulation == null or advance_simulation == null:
		return
	var every_tick_advanced: bool = true
	for tick_index: int in range(180):
		var move_input: Vector2 = _replay_input(tick_index)
		step_simulation.step(move_input)
		every_tick_advanced = (
			advance_simulation.advance_tick(move_input) and every_tick_advanced
		)
		if not _resolve_replay_modals(step_simulation) or not _resolve_replay_modals(advance_simulation):
			assertions.expect_true(false, "both paths resolve identical modal state")
			return
	assertions.expect_true(every_tick_advanced, "headless ticks advance production logic")
	assertions.expect_equal(_gameplay_digest(step_simulation), _gameplay_digest(advance_simulation), "step and snapshot-free advance share gameplay state")
	assertions.expect_equal(
		_gameplay_digest(step_simulation),
		_gameplay_digest_after_snapshot(advance_simulation),
		"building a snapshot after advance_tick is gameplay-pure",
	)


func test_fixed_seed_replay_ignores_reduce_motion(assertions: Variant, _context: Dictionary) -> void:
	var setup_a: Dictionary = _simulation(assertions, 8110)
	var setup_b: Dictionary = _simulation(assertions, 8110)
	var simulation_a: CombatSimulation = setup_a.get("simulation") as CombatSimulation
	var simulation_b: CombatSimulation = setup_b.get("simulation") as CombatSimulation
	if simulation_a == null or simulation_b == null:
		return
	var initial_streams: Dictionary = simulation_a.state.rng_streams.state_digest()
	var probe_a: Dictionary = _prepare_replay(simulation_a, false)
	var probe_b: Dictionary = _prepare_replay(simulation_b, true)
	if probe_a.is_empty() or probe_b.is_empty():
		assertions.expect_true(false, "deterministic replay fixture initializes")
		return
	for tick_index: int in range(360):
		var move_input: Vector2 = _replay_input(tick_index)
		simulation_a.step(move_input)
		simulation_b.step(move_input)
		if not _resolve_replay_modals(simulation_a) or not _resolve_replay_modals(simulation_b):
			assertions.expect_true(false, "replay resolves identical modal selections")
			return
	assertions.expect_equal(_gameplay_digest(simulation_a), _gameplay_digest(simulation_b), "same seed, input, and choices reproduce complete gameplay despite reduce-motion")
	assertions.expect_true(not simulation_a.vfx_pool.reduce_motion, "first replay uses full motion presentation")
	assertions.expect_true(simulation_b.vfx_pool.reduce_motion, "second replay uses reduced motion presentation")
	assertions.expect_true(initial_streams != simulation_a.state.rng_streams.state_digest(), "replay advances gameplay RNG streams")
	var mass_a: RunWeapon = simulation_a.state.weapon_for_lineage(&"mass_projectile")
	var boss_a: EnemyEntity = simulation_a.enemy_system.enemy_store.get_by_id(int(probe_a["boss_id"]))
	assertions.expect_true(mass_a != null and mass_a.rng.state != int(probe_a["mass_rng_state"]), "weapon-individual RNG participates in the replay")
	assertions.expect_true(boss_a != null and boss_a.rng.state == int(probe_a["boss_rng_state"]), "boss radial volleys do not consume private RNG state")
	assertions.expect_true(simulation_a.projectile_pool.active_count() > 0, "digest contains active projectiles")
	assertions.expect_true(simulation_a.xp_pickup_pool.active_count() > 0, "digest contains active XP pickups")


func _prepare_replay(simulation: CombatSimulation, reduce_motion: bool) -> Dictionary:
	simulation.configure_accessibility(reduce_motion, false)
	simulation.state.level_up_invulnerable_until_tick = 10_000
	var mass_definition: WeaponDefinition = simulation.catalog.weapon(&"mass_projectile")
	var slot_index: int = simulation.state.weapons.size()
	var mass_weapon: RunWeapon = RunWeapon.create(
		mass_definition.weapon_id,
		simulation.catalog.lineage_for_weapon(mass_definition.weapon_id),
		false,
		simulation.state.rng_streams.create_weapon_rng(
			simulation.catalog.lineage_for_weapon(mass_definition.weapon_id),
			slot_index,
		),
	)
	simulation.state.weapons.append(mass_weapon)
	for target_position: Vector2 in [Vector2(3, 0), Vector2(-3, 0)]:
		var target: EnemyEntity = simulation.spawn_fixture_enemy(GameTypes.EnemyType.BULWARK, target_position, -1)
		target.hp = 1_000_000.0
		target.max_hp = target.hp
	ProgressionService.add_xp(
		simulation.state,
		ProgressionService.xp_required_for_level(simulation.state.level, BalanceTestFixtures.catalog().manifest().progression),
		simulation.catalog,
	)
	simulation.state.pending_chest_sources.append(0)
	simulation.arena_object_system.damage_nodes_circle(
		simulation.arena_object_system.nodes[0].position,
		1.0,
		BalanceTestFixtures.catalog().manifest().arena.node_max_hp,
		simulation.state.combat_tick,
	)
	simulation.xp_pickup_pool.acquire(
		Vector2(-18.0, -18.0),
		7,
		simulation.state.combat_tick,
		simulation.player_position,
	)
	var boss: EnemyEntity = simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.BOSS,
		Vector2(10.0, 10.0),
		-1,
	)
	if boss == null:
		return {}
	boss.max_hp = 1_000_000.0
	boss.hp = boss.max_hp
	boss.special_elapsed_ticks = float(boss.definition.special_interval_ticks)
	simulation.state.boss_spawned = true
	simulation.state.boss_hp = boss.hp
	simulation.state.boss_max_hp = boss.max_hp
	simulation.projectile_pool.acquire(
		ProjectileState.FACTION_ENEMY,
		&"replay_probe",
		boss.entity_id,
		Vector2(18.0, 18.0),
		Vector2.ZERO,
		0.01,
		1.0,
		9999.0,
		9999.0,
		Vector2(18.0, 18.0),
		0,
		-1,
		&"replay_probe",
		ProjectileState.MovementKind.STRAIGHT,
		-1,
		600_000,
		0,
		0.0,
		0.5,
	)
	return {
		"boss_id": boss.entity_id,
		"boss_rng_state": boss.rng.state,
		"mass_rng_state": mass_weapon.rng.state,
	}


func _resolve_replay_modals(simulation: CombatSimulation) -> bool:
	while simulation.state.phase != GameTypes.RunPhase.COMBAT:
		match simulation.state.phase:
			GameTypes.RunPhase.LEVEL_UP:
				if not simulation.apply_upgrade_choice(0):
					return false
			GameTypes.RunPhase.CHEST_REWARD:
				if not simulation.complete_chest_reward():
					return false
			_:
				return false
	return true


func _replay_input(tick_index: int) -> Vector2:
	var cycle_tick: int = tick_index % 240
	if cycle_tick < 60:
		return Vector2.RIGHT
	if cycle_tick < 120:
		return Vector2.DOWN
	if cycle_tick < 180:
		return Vector2.LEFT
	return Vector2.UP


func _gameplay_digest(simulation: CombatSimulation) -> String:
	var state: RunState = simulation.state
	return str([
		state.phase, state.combat_tick, simulation.player_position,
		state.current_hp, state.level, state.xp, state.total_kills,
		state.pending_level_ups, state.pending_chest_count(),
		state.weapon_damage_by_lineage, state.rng_streams.state_digest(),
	])


func _gameplay_digest_after_snapshot(simulation: CombatSimulation) -> String:
	simulation.build_snapshot()
	return _gameplay_digest(simulation)


func _simulation(assertions: Variant, run_seed: int) -> Dictionary:
	var catalog := DefinitionCatalog.new()
	assertions.expect_true(catalog.validate_manifest(BalanceTestFixtures.manifest()), "survival scenario content validates")
	if not catalog.is_valid:
		return {}
	var state: RunState = RunStateFactory.create(run_seed, catalog)
	var simulation := CombatSimulation.new()
	simulation.initialize(state, catalog)
	return {"simulation": simulation, "catalog": catalog, "state": state}
