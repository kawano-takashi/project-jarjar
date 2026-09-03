extends RefCounted


func test_names() -> PackedStringArray:
	return PackedStringArray([
		"continuous_clock_and_time_only_spawn_targets",
		"four_elites_and_final_boss_are_guaranteed",
		"stop_freezes_normal_and_halves_boss_projectiles",
		"boss_three_phases_and_activation_relative_enrage",
		"scheduled_boss_uses_dedicated_manifest_multipliers",
		"same_tick_boss_victory_beats_player_death",
		"lethal_enemy_still_resolves_ready_attack_before_death",
		"evolved_damage_combines_into_base_lineage",
		"modal_resume_invulnerability_is_limited",
		"normal_damage_invulnerability_is_thirty_ticks",
		"advance_tick_matches_step_gameplay_state",
		"fixed_seed_replay_ignores_reduce_motion",
		"focused_build_progression_matches_revision9_enemy_pacing",
		"performance_fixture_has_all_survival_loads",
	])


func run_test(test_name: String, assertions: Variant, _context: Dictionary) -> void:
	match test_name:
		"continuous_clock_and_time_only_spawn_targets":
			_test_continuous_clock(assertions)
		"four_elites_and_final_boss_are_guaranteed":
			_test_scheduled_elites_and_boss(assertions)
		"stop_freezes_normal_and_halves_boss_projectiles":
			_test_stop_scaling(assertions)
		"boss_three_phases_and_activation_relative_enrage":
			_test_boss_phases(assertions)
		"scheduled_boss_uses_dedicated_manifest_multipliers":
			_test_scheduled_boss_multiplier_separation(assertions)
		"same_tick_boss_victory_beats_player_death":
			_test_same_tick_victory_priority(assertions)
		"lethal_enemy_still_resolves_ready_attack_before_death":
			_test_enemy_attack_before_death(assertions)
		"evolved_damage_combines_into_base_lineage":
			_test_lineage_damage(assertions)
		"modal_resume_invulnerability_is_limited":
			_test_modal_invulnerability(assertions)
		"normal_damage_invulnerability_is_thirty_ticks":
			_test_damage_invulnerability(assertions)
		"advance_tick_matches_step_gameplay_state":
			_test_advance_tick_equivalence(assertions)
		"fixed_seed_replay_ignores_reduce_motion":
			_test_deterministic_replay(assertions)
		"focused_build_progression_matches_revision9_enemy_pacing":
			_test_focused_build_pacing(assertions)
		"performance_fixture_has_all_survival_loads":
			_test_performance_fixture(assertions)
		_:
			assertions.expect_true(false, "registered survival combat scenario test")


func _test_continuous_clock(assertions: Variant) -> void:
	var setup: Dictionary = _simulation(assertions, 8101)
	var simulation: CombatSimulation = setup.get("simulation") as CombatSimulation
	if simulation == null:
		return
	for _tick: int in range(60):
		simulation.step(Vector2.ZERO)
	assertions.expect_equal(60, simulation.state.combat_tick, "one second advances exactly sixty combat ticks")
	assertions.expect_float(1.0, simulation.state.elapsed_seconds(), "HUD clock derives from integer combat ticks")
	var first_segment: EnemySegmentDefinition = simulation.catalog.segment_for_tick(simulation.state.combat_tick)
	assertions.expect_equal(16, first_segment.target_active, "first minute uses the Revision 5 active-enemy target")
	assertions.expect_true(simulation.enemy_system.enemy_store.active_count() <= 16, "spawn fill never overshoots the segment target")


func _test_scheduled_elites_and_boss(assertions: Variant) -> void:
	var setup: Dictionary = _simulation(assertions, 8102)
	var simulation: CombatSimulation = setup.get("simulation") as CombatSimulation
	if simulation == null:
		return
	var schedule: PackedInt32Array = simulation.catalog.manifest().elite_spawn_ticks
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
	simulation.state.combat_tick = RunState.BOSS_START_TICK
	var boss_spawns: Array[EnemyEntity] = simulation.enemy_system.resolve_scheduled_spawns(
		Vector2.ZERO,
		RunState.BOSS_START_TICK,
	)
	assertions.expect_equal(1, boss_spawns.size(), "10:00 creates one final boss")
	assertions.expect_equal(GameTypes.EnemyType.BOSS, boss_spawns[0].enemy_type, "10:00 scheduled entity is the boss")
	assertions.expect_true(simulation.state.boss_spawned, "boss-spawn state latches after successful allocation")
	assertions.expect_equal(0, simulation.enemy_system.resolve_normal_spawns(Vector2.ZERO, RunState.BOSS_START_TICK).size(), "normal spawning stops at 10:00")


func _test_stop_scaling(assertions: Variant) -> void:
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


func _test_boss_phases(assertions: Variant) -> void:
	var setup: Dictionary = _simulation(assertions, 8104)
	var simulation: CombatSimulation = setup.get("simulation") as CombatSimulation
	if simulation == null:
		return
	var boss: EnemyEntity = simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.BOSS,
		Vector2(8.0, 8.0),
		RunState.BOSS_START_TICK - CombatEnvelope.BOSS_ENTRY_TICKS,
		true,
		false,
	)
	simulation.state.boss_spawned = true
	assertions.expect_float(
		boss.definition.base_hp * simulation.catalog.manifest().boss_hp_multiplier,
		boss.max_hp,
		"boss HP uses its dedicated manifest multiplier outside segment scaling",
	)
	assertions.expect_float(
		simulation.catalog.manifest().boss_damage_multiplier,
		boss.damage_multiplier,
		"boss damage uses its dedicated manifest multiplier outside segment scaling",
	)
	simulation.state.combat_tick = RunState.BOSS_START_TICK
	boss.hp = boss.max_hp
	simulation.enemy_system.advance_snapshot([boss.entity_id], Vector2.ZERO, RunState.BOSS_START_TICK + 1)
	assertions.expect_equal(1, simulation.state.boss_phase, "boss starts in phase one")
	boss.hp = boss.max_hp * 0.66
	simulation.enemy_system.advance_snapshot([boss.entity_id], Vector2.ZERO, RunState.BOSS_START_TICK + 2)
	assertions.expect_equal(2, simulation.state.boss_phase, "boss enters phase two at 66 percent HP")
	boss.hp = boss.max_hp * 0.33
	simulation.enemy_system.advance_snapshot([boss.entity_id], Vector2.ZERO, RunState.BOSS_START_TICK + 3)
	assertions.expect_equal(3, simulation.state.boss_phase, "boss enters phase three at 33 percent HP")
	boss.boss_action_age_ticks = float(
		simulation.catalog.manifest().boss_enrage_interval_ticks - 1
	)
	simulation.enemy_system.advance_snapshot(
		[boss.entity_id],
		Vector2.ZERO,
		RunState.BOSS_START_TICK + 4,
	)
	assertions.expect_equal(1, simulation.state.boss_enrage_stacks, "boss gains one pressure stack after thirty seconds")
	simulation.state.boss_enrage_stacks = 2
	assertions.expect_float(73.0, simulation.enemy_system._boss_action_interval(100, 1), "two enrage stacks and the revision nine action rate produce a 73-tick interval")


func _test_scheduled_boss_multiplier_separation(assertions: Variant) -> void:
	var canonical := DefinitionCatalog.new()
	assertions.expect_true(canonical.load_and_validate(), "canonical boss fixture content validates")
	if not canonical.is_valid:
		return
	var manifest: SurvivalContentManifest = canonical.manifest().duplicate(true) as SurvivalContentManifest
	manifest.boss_hp_multiplier = SurvivalContentManifest.DEFAULT_BOSS_HP_MULTIPLIER * 0.80
	manifest.boss_damage_multiplier = SurvivalContentManifest.DEFAULT_BOSS_DAMAGE_MULTIPLIER * 0.80
	manifest.boss_action_rate_multiplier = (
		SurvivalContentManifest.DEFAULT_BOSS_ACTION_RATE_MULTIPLIER * 0.80
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
		not is_equal_approx(manifest.boss_hp_multiplier, segment_ten.hp_multiplier),
		"fixture keeps boss HP separate from segment ten",
	)
	assertions.expect_true(
		not is_equal_approx(manifest.boss_damage_multiplier, segment_ten.damage_multiplier),
		"fixture keeps boss damage separate from segment ten",
	)
	var state: RunState = RunStateFactory.create(8_104_801, custom_catalog)
	var simulation := CombatSimulation.new()
	simulation.initialize(state, custom_catalog)
	state.combat_tick = manifest.boss_start_tick
	var spawned: Array[EnemyEntity] = simulation.enemy_system.resolve_scheduled_spawns(
		Vector2.ZERO,
		manifest.boss_start_tick,
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
		boss.definition.base_hp * manifest.boss_hp_multiplier,
		boss.max_hp,
		"scheduled boss HP uses the dedicated multiplier",
	)
	assertions.expect_float(
		manifest.boss_damage_multiplier,
		boss.damage_multiplier,
		"scheduled boss damage uses the dedicated multiplier",
	)
	assertions.expect_float(
		125.0,
		simulation.enemy_system._boss_action_interval(100, 1),
		"non-neutral boss action rate changes radial-volley cadence",
	)


func _test_same_tick_victory_priority(assertions: Variant) -> void:
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


func _test_enemy_attack_before_death(assertions: Variant) -> void:
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
	enemy.contact_elapsed_ticks = float(enemy.definition.contact_interval_ticks)
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


func _test_lineage_damage(assertions: Variant) -> void:
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


func _test_modal_invulnerability(assertions: Variant) -> void:
	var setup: Dictionary = _simulation(assertions, 8105)
	var simulation: CombatSimulation = setup.get("simulation") as CombatSimulation
	if simulation == null:
		return
	simulation.state.combat_tick = 100
	simulation.grant_resume_invulnerability_ticks(45)
	assertions.expect_equal(146, simulation.state.modal_invulnerable_until_tick, "exclusive deadline covers exactly 45 resumed updates")
	assertions.expect_true(simulation.state.is_invulnerable(), "resume protection is active before its deadline")
	simulation.state.combat_tick = 145
	assertions.expect_true(simulation.state.is_invulnerable(), "the forty-fifth resumed update remains protected")
	simulation.state.combat_tick = 146
	assertions.expect_true(not simulation.state.is_invulnerable(), "the forty-sixth resumed update can take damage")


func _test_damage_invulnerability(assertions: Variant) -> void:
	var setup: Dictionary = _simulation(assertions, 8107)
	var simulation: CombatSimulation = setup.get("simulation") as CombatSimulation
	if simulation == null:
		return
	simulation.state.combat_tick = 100
	simulation._apply_raw_player_damage(10.0)
	assertions.expect_float(90.0, simulation.state.current_hp, "first same-tick hit applies")
	assertions.expect_equal(131, simulation.state.damage_invulnerable_until_tick, "exclusive deadline covers thirty following ticks")
	simulation._apply_raw_player_damage(50.0)
	assertions.expect_float(90.0, simulation.state.current_hp, "second same-tick hit is ignored")
	assertions.expect_equal(131, simulation.state.damage_invulnerable_until_tick, "ignored damage never extends protection")
	simulation.state.combat_tick = 130
	simulation._apply_raw_player_damage(50.0)
	assertions.expect_float(90.0, simulation.state.current_hp, "thirtieth following tick remains protected")
	simulation.state.combat_tick = 131
	simulation._apply_raw_player_damage(10.0)
	assertions.expect_float(80.0, simulation.state.current_hp, "damage resumes when the exclusive deadline is reached")


func _test_advance_tick_equivalence(assertions: Variant) -> void:
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


func _test_deterministic_replay(assertions: Variant) -> void:
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


func _test_focused_build_pacing(assertions: Variant) -> void:
	var setup: Dictionary = _simulation(assertions, 43)
	var simulation: CombatSimulation = setup.get("simulation") as CombatSimulation
	if simulation == null:
		return
	var evolution_bot := DifficultyCalibrationBot.new()
	assertions.expect_true(
		evolution_bot.initialize(DifficultyCalibrationBot.Policy.EVOLUTION, 43),
		"focused pacing uses the approved evolution policy",
	)
	var gate_probe: RunState = RunStateFactory.create(1616, simulation.catalog)
	gate_probe.weapon_for_lineage(&"homing_core").level = 8
	ProgressionService.apply_direct_upgrade(
		gate_probe,
		simulation.catalog,
		GameTypes.UpgradeKind.PASSIVE,
		&"cycle_crystal",
	)
	gate_probe.pending_chest_sources.append(0)
	var ungated_outcome: ChestOutcome = ChestRewardService.create_outcome(
		gate_probe,
		simulation.catalog,
	)
	assertions.expect_equal(GameTypes.ChestOutcomeKind.EVOLUTION, ungated_outcome.kind, "evolution eligibility itself has no clock gate at tick zero")
	simulation.state.modal_invulnerable_until_tick = 100_000
	var check_ticks := PackedInt32Array([7200, 14_400, 21_600])
	var expected_kinds: Array[GameTypes.ChestOutcomeKind] = [
		GameTypes.ChestOutcomeKind.UPGRADE,
		GameTypes.ChestOutcomeKind.EVOLUTION,
		GameTypes.ChestOutcomeKind.UPGRADE,
	]
	var check_index: int = 0
	while simulation.state.combat_tick < check_ticks[check_ticks.size() - 1]:
		if simulation.state.phase == GameTypes.RunPhase.COMBAT:
			simulation.step(_pacing_move(simulation))
			_remove_pacing_elites(simulation)
		else:
			assertions.expect_true(
				_resolve_pacing_modal(simulation, evolution_bot),
				"focused weighted choice applies",
			)
		if (
			check_index < check_ticks.size()
			and simulation.state.combat_tick == check_ticks[check_index]
		):
			while simulation.state.phase != GameTypes.RunPhase.COMBAT:
				if not _resolve_pacing_modal(simulation, evolution_bot):
					assertions.expect_true(false, "all queued focused choices resolve before chest")
					return
			var homing: RunWeapon = simulation.state.weapon_for_lineage(&"homing_core")
			var cycle_crystal: RunPassive = simulation.state.passive(&"cycle_crystal")
			if check_index == 0:
				assertions.expect_equal(0, simulation.state.evolution_count, "two-minute chest has no prior evolution")
			elif check_index == 1:
				assertions.expect_equal(8, homing.level, "focused homing reaches maximum by four minutes with Revision 5 XP tuning")
				assertions.expect_true(cycle_crystal != null, "focused build owns the paired passive by four minutes")
			else:
				assertions.expect_true(homing.evolved, "focused lineage remains evolved at six minutes")
				assertions.expect_equal(1, simulation.state.evolution_count, "focused pacing creates one evolution before the six-minute chest")
			var cycle_level_before: int = 0 if cycle_crystal == null else cycle_crystal.level
			simulation.state.pending_chest_sources.append(check_index)
			var outcome: ChestOutcome = ChestRewardService.create_outcome(
				simulation.state,
				simulation.catalog,
			)
			assertions.expect_equal(expected_kinds[check_index], outcome.kind, "scheduled chest %d has the intended evolution eligibility" % check_index)
			var result: Dictionary = ChestRewardService.apply_outcome(
				simulation.state,
				simulation.catalog,
				outcome.serial,
			)
			assertions.expect_true(bool(result.get(&"success", false)), "scheduled chest applies exactly one outcome")
			if check_index == 1:
				assertions.expect_equal(
					cycle_level_before,
					simulation.state.passive(&"cycle_crystal").level,
					"four-minute evolution does not consume or rank its paired passive",
				)
			check_index += 1
	var evolved: RunWeapon = simulation.state.weapon_for_lineage(&"homing_core")
	assertions.expect_equal(3, simulation.state.opened_chests, "all three scheduled chest outcomes are consumed")
	assertions.expect_equal(1, simulation.state.evolution_count, "revision nine fixture retains its first focused evolution through six minutes")
	assertions.expect_true(evolved.evolved and evolved.weapon_id == &"infinite_homing", "focused lineage remains evolved after six minutes")


func _test_performance_fixture(assertions: Variant) -> void:
	var setup: Dictionary = _simulation(assertions, 8106)
	var simulation: CombatSimulation = setup.get("simulation") as CombatSimulation
	if simulation == null:
		return
	assertions.expect_true(simulation.prepare_performance_fixture(500, 1200, 800, 1024), "survival performance fixture fills every requested load")
	var metrics: Dictionary = simulation.performance_fixture_metrics()
	assertions.expect_equal(500, metrics["active_enemy"], "performance fixture has 500 enemies")
	assertions.expect_equal(1200, metrics["active_projectile"], "performance fixture has 1200 projectiles")
	assertions.expect_equal(800, metrics["active_vfx"], "performance fixture has 800 VFX")
	assertions.expect_equal(1024, metrics["active_xp"], "performance fixture has 1024 XP crystals")
	assertions.expect_equal(5, metrics["active_weapon"], "performance fixture has five weapons")
	assertions.expect_equal(0, metrics["projectile_pool_overflow"], "performance projectile pool does not overflow")
	assertions.expect_equal(0, metrics["vfx_pool_overflow"], "performance VFX pool does not overflow")
	assertions.expect_equal(0, metrics["xp_pool_overflow_merges"], "performance XP pool stays below overflow")
	var contract: Dictionary = simulation.performance_profile_contract()
	assertions.expect_equal(&"full_hd_500_2000", contract["profile_name"], "existing performance profile name is unchanged")
	assertions.expect_equal(500, contract["enemy_count"], "profile contract fixes 500 enemies")
	assertions.expect_equal(1200, contract["projectile_count"], "profile contract fixes 1200 projectiles")
	assertions.expect_equal(800, contract["vfx_count"], "profile contract fixes 800 VFX")
	assertions.expect_equal(1024, contract["xp_count"], "profile contract includes the XP stress load")
	assertions.expect_equal(5, contract["weapon_count"], "profile contract fixes five weapons")
	assertions.expect_true(bool(contract["active_updates"]), "profile contract requires active simulation updates")
	assertions.expect_true(bool(contract["exact_count_lock"]), "profile contract keeps exact render counts")
	var initial_tick: int = simulation.state.combat_tick
	for tick_index: int in range(120):
		var movement_cycle: Array[Vector2] = [
			Vector2.RIGHT,
			Vector2.DOWN,
			Vector2.LEFT,
			Vector2.UP,
		]
		simulation.step(movement_cycle[tick_index % movement_cycle.size()])
	metrics = simulation.performance_fixture_metrics()
	assertions.expect_equal(initial_tick + 120, simulation.state.combat_tick, "active profile advances all 120 combat ticks")
	assertions.expect_true(simulation.freeze_all_updates, "legacy fixture flag remains compatible while active workload runs")
	assertions.expect_true(bool(metrics["active_workload"]), "performance fixture reports active combat workload")
	assertions.expect_true(bool(metrics["exact_counts"]), "active workload restores exact counts every tick")
	assertions.expect_equal(500, metrics["active_enemy"], "active workload retains exactly 500 enemies")
	assertions.expect_equal(1200, metrics["active_projectile"], "active workload retains exactly 1200 projectiles")
	assertions.expect_equal(800, metrics["active_vfx"], "active workload retains exactly 800 VFX")
	assertions.expect_equal(1024, metrics["active_xp"], "active workload retains exactly 1024 XP crystals")
	assertions.expect_equal(5, metrics["active_weapon"], "active workload retains exactly five weapons")
	assertions.expect_equal(120, metrics["workload_ticks"], "every fixture tick executes active workload")
	assertions.expect_equal(120, metrics["grid_updates"], "enemy grid rebuilds on every active workload tick")
	assertions.expect_true(float(metrics["enemy_motion_distance"]) > 0.0, "fixture enemies really move")
	assertions.expect_true(float(metrics["projectile_motion_distance"]) > 0.0, "fixture projectiles really move")
	assertions.expect_true(int(metrics["projectile_collision_resolutions"]) >= 1200 * 120, "fixture resolves the full projectile collision workload")
	assertions.expect_true(int(metrics["weapon_attacks"]) > 0, "five equipped weapons really fire")
	assertions.expect_true(int(metrics["enemy_recycles"]) >= 4, "fixture periodically removes and respawns enemies")
	assertions.expect_true(int(metrics["enemy_pool_reuse"]) > 0, "enemy pool slots are reused")
	assertions.expect_true(int(metrics["projectile_pool_reuse"]) > 0, "projectile pool slots are reused")
	assertions.expect_true(int(metrics["vfx_pool_reuse"]) > 0, "VFX pool slots are reused")
	assertions.expect_true(int(metrics["xp_pool_reuse"]) > 0, "XP pool slots are reused")
	assertions.expect_equal(0, metrics["pool_orphan_count"], "all active/free pool indices remain owned")
	assertions.expect_equal(0, metrics["enemy_pool_overflow"], "active workload enemy pool does not overflow")
	assertions.expect_equal(0, metrics["projectile_pool_overflow"], "active workload projectile pool does not overflow")
	assertions.expect_equal(0, metrics["vfx_pool_overflow"], "active workload VFX pool does not overflow")
	assertions.expect_equal(0, metrics["xp_pool_overflow_merges"], "active workload XP pool does not overflow")
	var tracked_id: int = simulation.enemy_system.enemy_store.snapshot_ids_sorted()[0]
	var tracked_enemy: EnemyEntity = simulation.enemy_system.enemy_store.get_by_id(tracked_id)
	assertions.expect_true(
		simulation.enemy_system.uniform_grid.query_circle_candidates(
			tracked_enemy.position,
			0.1,
			0.0,
		).has(tracked_id),
		"active workload grid owns the current tracked enemy position",
	)


func _prepare_replay(simulation: CombatSimulation, reduce_motion: bool) -> Dictionary:
	simulation.configure_accessibility(reduce_motion, false)
	simulation.state.modal_invulnerable_until_tick = 10_000
	var mass_definition: WeaponDefinition = simulation.catalog.weapon(&"mass_projectile")
	var slot_index: int = simulation.state.weapons.size()
	var mass_weapon: RunWeapon = RunWeapon.create(
		mass_definition.weapon_id,
		mass_definition.lineage_id,
		false,
		simulation.state.rng_streams.create_weapon_rng(
			mass_definition.lineage_id,
			slot_index,
		),
	)
	simulation.state.weapons.append(mass_weapon)
	ProgressionService.add_xp(
		simulation.state,
		ProgressionService.xp_required_for_level(simulation.state.level),
		simulation.catalog,
	)
	simulation.state.pending_chest_sources.append(0)
	simulation.arena_object_system.damage_nodes_circle(
		ArenaObjectSystem.NODE_SITE_POSITIONS[0],
		1.0,
		ArenaObjectSystem.NODE_MAX_HP,
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


func _resolve_pacing_modal(
	simulation: CombatSimulation,
	evolution_bot: DifficultyCalibrationBot,
) -> bool:
	if simulation.state.phase != GameTypes.RunPhase.LEVEL_UP:
		return false
	var offer: LevelOffer = simulation.state.active_level_offer
	if offer == null:
		return false
	var choice_index: int = evolution_bot.choose_upgrade(
		offer,
		simulation.state,
		simulation.catalog,
	)
	return choice_index >= 0 and simulation.apply_upgrade_choice(choice_index)


func _pacing_move(simulation: CombatSimulation) -> Vector2:
	var nearest_position: Vector2 = simulation.player_position
	var nearest_distance_squared: float = INF
	for pool_index: int in simulation.xp_pickup_pool.active_indices_snapshot():
		var pickup: XpPickupState = simulation.xp_pickup_pool.slots[pool_index]
		var distance_squared: float = pickup.position.distance_squared_to(
			simulation.player_position
		)
		if distance_squared < nearest_distance_squared:
			nearest_distance_squared = distance_squared
			nearest_position = pickup.position
	if nearest_distance_squared == INF:
		for entity_id: int in simulation.enemy_system.enemy_store.snapshot_ids_sorted():
			var enemy: EnemyEntity = simulation.enemy_system.enemy_store.get_by_id(entity_id)
			var distance_squared: float = enemy.position.distance_squared_to(
				simulation.player_position
			)
			if distance_squared < nearest_distance_squared:
				nearest_distance_squared = distance_squared
				nearest_position = enemy.position
	var offset: Vector2 = nearest_position - simulation.player_position
	return offset.normalized() if offset.length_squared() > 0.000001 else Vector2.ZERO


func _remove_pacing_elites(simulation: CombatSimulation) -> void:
	# Elite scheduling/drop behavior has its own contract test. Removing the fixture
	# elite fixes reward evaluation to the exact 2/4/6-minute ticks so variable
	# kill and pickup travel time cannot add an unintended extra chest.
	for entity_id: int in simulation.enemy_system.enemy_store.snapshot_ids_sorted():
		var enemy: EnemyEntity = simulation.enemy_system.enemy_store.get_by_id(entity_id)
		if enemy != null and enemy.enemy_type == GameTypes.EnemyType.ELITE:
			simulation.enemy_system.enemy_store.remove(entity_id)


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
	var streams: RunRngStreams = state.rng_streams
	var values: Array = [
		state.run_seed,
		int(state.phase),
		state.combat_tick,
		simulation.player_position,
		state.current_hp,
		state.max_hp,
		state.base_max_hp,
		state.level,
		state.xp,
		state.xp_yield_remainder,
		state.pending_level_ups,
		state.upgrade_selections_applied,
		state.build_maxed,
		state.next_offer_serial,
		state.next_chest_serial,
		state.pending_chest_sources,
		state.opened_chests,
		state.evolution_count,
		state.boss_spawned,
		state.boss_transition_started,
		state.boss_defeated,
		state.boss_phase,
		state.boss_enrage_stacks,
		state.boss_hp,
		state.boss_max_hp,
		state.stop_until_tick,
		state.damage_invulnerable_until_tick,
		state.modal_invulnerable_until_tick,
		state.next_entity_id,
		state.next_event_serial,
		state.next_swarm_group_id,
		state.spawn_credit,
		state.total_kills,
		state.normal_kills,
		state.elite_kills,
		state.boss_kills,
		state.absorbed_normal_count,
		state.normal_far_despawn_count,
		state.absorbed_enemy_projectile_count,
		state.swarm_event_attempt_count,
		state.swarm_event_roll_success_count,
		state.swarm_event_spawn_failure_count,
		state.swarm_event_group_count,
		state.swarm_event_generated_count,
		state.swarm_event_kill_count,
		state.swarm_event_exit_count,
		state.swarm_event_absorbed_count,
		state.swarm_event_xp,
		state.kill_chain_count,
		state.kill_chain_last_tick,
		state.kill_chain_accent_milestone,
		state.weapon_hit_count,
		state.weapon_kill_count,
		state.visible_weapon_hit_count,
		state.visible_weapon_kill_count,
		state.offscreen_weapon_hit_count,
		state.offscreen_weapon_kill_count,
		state.max_weapon_hit_center_distance,
		state.max_weapon_kill_center_distance,
		state.max_weapon_effect_outer_distance,
		state.visible_enemy_sample_count,
		state.visible_enemy_count_total,
		state.engaged_enemy_count_total,
		state.materializing_enemy_count_total,
		state.peak_visible_enemy_count,
		state.peak_engaged_enemy_count,
		state.peak_materializing_enemy_count,
		state.feedback_event_emitted_count,
		state.feedback_event_suppressed_count,
		streams.spawn_seed,
		streams.upgrade_seed,
		streams.chest_seed,
		streams.powerup_seed,
		streams.swarm_event_seed,
		streams.spawn_rng.state,
		streams.upgrade_rng.state,
		streams.chest_rng.state,
		streams.powerup_rng.state,
		streams.swarm_event_rng.state,
		_int_bool_entries(state.applied_offer_serials),
		_int_bool_entries(state.applied_chest_serials),
		_offer_entry(state.active_level_offer),
		_chest_entry(state.active_chest_outcome),
		_weapon_entries(state),
		_passive_entries(state),
		_lineage_damage_entries(state),
		_damage_sample_entries(state),
		_enemy_system_entries(simulation),
		_projectile_entries(simulation),
		_xp_entries(simulation),
		_arena_entries(simulation),
		simulation.weapon_system.deterministic_state_values(),
		simulation._vacuum_collecting,
	]
	return var_to_bytes(values).hex_encode().sha256_text()


func _gameplay_digest_after_snapshot(simulation: CombatSimulation) -> String:
	simulation.build_snapshot()
	return _gameplay_digest(simulation)


func _offer_entry(offer: LevelOffer) -> Array:
	if offer == null:
		return []
	var options: Array = []
	for option: UpgradeOption in offer.options:
		options.append([
			int(option.kind),
			String(option.content_id),
			option.current_level,
			option.next_level,
			option.max_level,
			option.weight,
		])
	return [offer.serial, offer.offer_level, offer.applied, options]


func _chest_entry(outcome: ChestOutcome) -> Array:
	if outcome == null:
		return []
	return [
		outcome.serial,
		outcome.source_elite_index,
		int(outcome.kind),
		int(outcome.upgrade_kind),
		String(outcome.content_id),
		outcome.previous_level,
		outcome.new_level,
		String(outcome.source_weapon_id),
		outcome.applied,
	]


func _weapon_entries(state: RunState) -> Array:
	var result: Array = []
	for slot_index: int in range(state.weapons.size()):
		var weapon: RunWeapon = state.weapons[slot_index]
		var rng_seed: int = 0
		var rng_state: int = 0
		if weapon.rng != null:
			rng_seed = weapon.rng.seed
			rng_state = weapon.rng.state
		result.append([
			slot_index,
			String(weapon.weapon_id),
			String(weapon.lineage_id),
			weapon.level,
			weapon.evolved,
			weapon.cooldown_remaining_ticks,
			weapon.ready_on_resume,
			rng_seed,
			rng_state,
		])
	return result


func _passive_entries(state: RunState) -> Array:
	var result: Array = []
	for passive: RunPassive in state.passives:
		result.append([String(passive.passive_id), passive.level])
	return result


func _lineage_damage_entries(state: RunState) -> Array:
	var result: Array = []
	for lineage_key: String in _sorted_string_keys(state.weapon_damage_by_lineage):
		var lineage_id := StringName(lineage_key)
		result.append([lineage_key, float(state.weapon_damage_by_lineage[lineage_id])])
	return result


func _damage_sample_entries(state: RunState) -> Array:
	var result: Array = []
	for sample: DamageSample in state.recent_damage_samples:
		result.append([sample.physics_tick, sample.event_serial, sample.applied_damage])
	return result


func _enemy_system_entries(simulation: CombatSimulation) -> Array:
	var result: Array = []
	for entity_id: int in simulation.enemy_system.enemy_store.snapshot_ids_sorted():
		var enemy: EnemyEntity = simulation.enemy_system.enemy_store.get_by_id(entity_id)
		var rng_seed: int = 0
		var rng_state: int = 0
		if enemy.rng != null:
			rng_seed = enemy.rng.seed
			rng_state = enemy.rng.state
		result.append([
			enemy.pool_index,
			enemy.generation,
			enemy.entity_id,
			int(enemy.enemy_type),
			String(enemy.definition.enemy_id),
			enemy.position,
			enemy.hp,
			enemy.max_hp,
			enemy.damage_multiplier,
			enemy.born_tick,
			enemy.spawn_tick,
			enemy.activation_tick,
			enemy.contact_elapsed_ticks,
			enemy.special_elapsed_ticks,
			enemy.telegraph_elapsed_ticks,
			enemy.telegraph_active,
			enemy.telegraph_position,
			enemy.barrage_alternate,
			enemy.boss_charge_active,
			enemy.boss_charge_elapsed_ticks,
			enemy.boss_charge_interval_ticks,
			enemy.boss_charge_spoke_count,
			enemy.boss_charge_half_step,
			enemy.boss_action_age_ticks,
			enemy.hit_flash_until_tick,
			enemy.alive,
			enemy.elite_serial,
			enemy.boss_phase,
			int(enemy.movement_kind),
			enemy.swarm_group_id,
			enemy.fixed_direction,
			enemy.remaining_travel_distance,
			enemy.swarm_red_variant,
			enemy.is_swarm_event,
			rng_seed,
			rng_state,
		])
	var elite_spawned: Array[int] = []
	for value: int in simulation.enemy_system._elite_spawned:
		elite_spawned.append(value)
	return [
		result,
		elite_spawned,
		simulation.enemy_system._swarm_attempt_consumed,
		simulation.enemy_system.enemy_store.overflow_count,
	]


func _projectile_entries(simulation: CombatSimulation) -> Array:
	var result: Array = []
	for pool_index: int in simulation.projectile_pool.active_indices_snapshot():
		var projectile: ProjectileState = simulation.projectile_pool.slots[pool_index]
		result.append([
			pool_index,
			projectile.generation,
			String(projectile.faction),
			String(projectile.weapon_id),
			projectile.source_entity_id,
			projectile.position,
			projectile.previous_position,
			projectile.velocity,
			projectile.radius,
			projectile.damage,
			projectile.remaining_distance,
			projectile.previous_remaining_distance,
			projectile.remaining_lifetime,
			projectile.target_position,
			projectile.pierce_remaining,
			projectile.born_tick,
			_sorted_int_keys(projectile.hit_entity_ids),
			_sorted_int_keys(projectile.hit_node_sites),
			String(projectile.source_effect_id),
			int(projectile.movement_kind),
			projectile.target_entity_id,
			projectile.speed,
			projectile.elapsed_ticks,
			projectile.total_lifetime_ticks,
			projectile.return_after_ticks,
			projectile.return_phase_started,
			projectile.explosion_radius,
			projectile.stop_time_scale,
			projectile.expired_this_tick,
		])
	return [result, simulation.projectile_pool.overflow_count]


func _xp_entries(simulation: CombatSimulation) -> Array:
	var result: Array = []
	for pool_index: int in simulation.xp_pickup_pool.active_indices_snapshot():
		var pickup: XpPickupState = simulation.xp_pickup_pool.slots[pool_index]
		result.append([
			pool_index,
			pickup.generation,
			pickup.position,
			pickup.value,
			pickup.born_tick,
		])
	return [result, simulation.xp_pickup_pool.overflow_merge_count]


func _arena_entries(simulation: CombatSimulation) -> Array:
	var arena: ArenaObjectSystem = simulation.arena_object_system
	var nodes: Array = []
	for node: ArenaNodeState in arena.nodes:
		nodes.append([node.site_index, node.position, node.hp, node.active])
	var pickups: Array = []
	for pickup: ArenaPickup in arena.pickups:
		pickups.append([
			pickup.pickup_id,
			int(pickup.kind),
			pickup.position,
			pickup.source_serial,
			pickup.active,
			pickup.effect_counts.duplicate(),
		])
	return [
		nodes,
		pickups,
		arena._pending_respawn_ticks.duplicate(),
		arena._next_pickup_id,
		arena.destroyed_node_count,
	]


func _sorted_int_keys(source: Dictionary) -> Array[int]:
	var result: Array[int] = []
	for key_value: Variant in source:
		result.append(int(key_value))
	result.sort()
	return result


func _sorted_string_keys(source: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for key_value: Variant in source:
		result.append(String(key_value))
	result.sort()
	return result


func _int_bool_entries(source: Dictionary) -> Array:
	var result: Array = []
	for key_value: int in _sorted_int_keys(source):
		result.append([key_value, bool(source[key_value])])
	return result


func _simulation(assertions: Variant, run_seed: int) -> Dictionary:
	var catalog := DefinitionCatalog.new()
	assertions.expect_true(catalog.load_and_validate(), "survival scenario content validates")
	if not catalog.is_valid:
		return {}
	var state: RunState = RunStateFactory.create(run_seed, catalog)
	var simulation := CombatSimulation.new()
	simulation.initialize(state, catalog)
	return {"simulation": simulation, "catalog": catalog, "state": state}
