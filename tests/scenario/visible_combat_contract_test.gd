extends RefCounted


const REQUIRED_VISIBLE_METRIC_KEYS: Array[String] = [
	"weapon_hits",
	"weapon_kills",
	"visible_weapon_hits",
	"visible_weapon_kills",
	"offscreen_weapon_hits",
	"offscreen_weapon_kills",
	"max_hit_center_distance",
	"max_kill_center_distance",
	"max_effect_outer_distance",
	"peak_visible_enemies",
	"mean_visible_enemies",
	"peak_engaged_enemies",
	"mean_engaged_enemies",
	"peak_materializing_enemies",
	"mean_materializing_enemies",
	"absorbed_normal_count",
	"normal_far_despawns",
	"absorbed_enemy_projectile_count",
	"swarm_event_attempts",
	"swarm_event_roll_successes",
	"swarm_event_spawn_failures",
	"swarm_event_groups",
	"swarm_event_generated",
	"swarm_event_kills",
	"swarm_event_exits",
	"swarm_event_absorbed",
	"swarm_event_xp",
	"feedback_emitted",
	"feedback_suppressed",
	"vfx_admitted",
	"vfx_suppressed",
	"important_vfx_dropped",
	"audio_admitted",
	"audio_suppressed",
]


func test_names() -> PackedStringArray:
	return PackedStringArray([
		"boss_transition_absorbs_normals_and_hostile_projectiles_without_rewards",
		"boss_enrage_counts_action_ticks_under_stop_and_modal",
		"maximum_enrage_preserves_full_thirty_tick_charge",
		"boss_volley_event_preserves_latched_phase_spokes",
		"shooter_type_chases_for_contact_without_normal_projectiles",
		"combat_envelope_enforces_8_9_10_meter_gates",
		"visible_combat_metrics_has_required_schema",
		"presentation_event_admission_is_bounded_and_priority_aware",
		"vfx_admission_reserves_important_capacity_and_hard_caps",
		"audio_admission_metrics_cover_combat_stop_and_modal_cues",
	])


func run_test(test_name: String, assertions: Variant, _context: Dictionary) -> void:
	match test_name:
		"boss_transition_absorbs_normals_and_hostile_projectiles_without_rewards":
			_test_boss_transition_absorption(assertions)
		"boss_enrage_counts_action_ticks_under_stop_and_modal":
			_test_boss_enrage_action_clock(assertions)
		"maximum_enrage_preserves_full_thirty_tick_charge":
			_test_maximum_enrage_charge(assertions)
		"boss_volley_event_preserves_latched_phase_spokes":
			_test_boss_volley_event_latch(assertions)
		"shooter_type_chases_for_contact_without_normal_projectiles":
			_test_shooter_contact_contract(assertions)
		"combat_envelope_enforces_8_9_10_meter_gates":
			_test_combat_envelope_gates(assertions)
		"visible_combat_metrics_has_required_schema":
			_test_visible_metric_schema(assertions)
		"presentation_event_admission_is_bounded_and_priority_aware":
			_test_presentation_event_admission(assertions)
		"vfx_admission_reserves_important_capacity_and_hard_caps":
			_test_vfx_admission(assertions)
		"audio_admission_metrics_cover_combat_stop_and_modal_cues":
			_test_audio_admission_metrics(assertions)
		_:
			assertions.expect_true(false, "registered combat contract test")


func _test_boss_transition_absorption(assertions: Variant) -> void:
	var simulation: CombatSimulation = _simulation(assertions, 8501)
	if simulation == null:
		return
	var boss_start_tick: int = simulation.catalog.boss_start_tick
	simulation.state.combat_tick = boss_start_tick - 1
	# This fixture jumps directly to 10:00, so mark the four earlier scheduled
	# elites handled. The elite below represents an already-active survivor.
	simulation.enemy_system._elite_spawned.fill(1)
	var contact_enemy: EnemyEntity = simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.PURSUER,
		simulation.player_position,
		boss_start_tick - 2,
		false,
		true,
	)
	var shooter: EnemyEntity = simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.SHOOTER,
		Vector2(1.0, 0.0),
		boss_start_tick - 2,
		false,
		true,
	)
	var elite: EnemyEntity = simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.ELITE,
		Vector2(12.0, 12.0),
		boss_start_tick - 2,
		false,
		true,
	)
	assertions.expect_true(contact_enemy != null and shooter != null and elite != null, "boss transition fixtures allocate")
	if contact_enemy == null or shooter == null or elite == null:
		return
	# Pool slots are deliberately reusable, so retain stable IDs before absorption.
	var contact_enemy_id: int = contact_enemy.entity_id
	var shooter_id: int = shooter.entity_id
	var elite_id: int = elite.entity_id
	shooter.special_elapsed_ticks = float(shooter.definition.special_interval_ticks)
	_spawn_hostile_projectile(simulation, contact_enemy_id, &"enemy_projectile")
	_spawn_hostile_projectile(simulation, -1, &"boss_projectile")
	var existing_xp: XpPickupState = simulation.xp_pickup_pool.acquire(
		Vector2(14.0, 14.0),
		17,
		boss_start_tick - 2,
		simulation.player_position,
	)
	var existing_chest: ArenaPickup = simulation.arena_object_system.spawn_chest(
		Vector2(-12.0, 12.0),
		77,
	)
	assertions.expect_true(existing_xp != null and existing_chest != null, "persistent world fixtures allocate")
	if existing_xp == null or existing_chest == null:
		return
	simulation.state.current_hp = 83.0
	simulation.state.xp = 23
	simulation.state.total_kills = 11
	simulation.state.normal_kills = 9
	simulation.state.elite_kills = 2
	simulation.state.kill_chain_count = 7
	simulation.state.kill_chain_last_tick = boss_start_tick - 5
	simulation.state.kill_chain_accent_milestone = 0
	var hp_before: float = simulation.state.current_hp
	var xp_before: int = simulation.state.xp
	var total_kills_before: int = simulation.state.total_kills
	var normal_kills_before: int = simulation.state.normal_kills
	var elite_kills_before: int = simulation.state.elite_kills
	var chain_before: Array[int] = [
		simulation.state.kill_chain_count,
		simulation.state.kill_chain_last_tick,
		simulation.state.kill_chain_accent_milestone,
	]
	var xp_count_before: int = simulation.xp_pickup_pool.active_count()
	var xp_value_before: int = simulation.xp_pickup_pool.total_value()
	var arena_before: Array = _arena_object_digest(simulation.arena_object_system)
	assertions.expect_true(simulation.advance_tick(Vector2.ZERO), "10:00 transition tick advances")
	assertions.expect_equal(boss_start_tick, simulation.state.combat_tick, "transition starts on the exact 10:00 tick")
	assertions.expect_true(simulation.state.boss_transition_started, "boss transition latches once")
	assertions.expect_true(not simulation.enemy_system.enemy_store.has_entity(contact_enemy_id), "contact enemy is removed before its ready attack")
	assertions.expect_true(not simulation.enemy_system.enemy_store.has_entity(shooter_id), "shooter is absorbed before its ready projectile action")
	assertions.expect_true(simulation.enemy_system.enemy_store.has_entity(elite_id), "existing elite remains in combat")
	assertions.expect_equal(0, _hostile_projectile_count(simulation), "all pre-existing hostile projectiles are harmless in the transition tick")
	assertions.expect_float(hp_before, simulation.state.current_hp, "absorbed contact and projectile threats deal no transition-tick damage")
	assertions.expect_equal(xp_before, simulation.state.xp, "absorption grants no direct XP")
	assertions.expect_equal(total_kills_before, simulation.state.total_kills, "absorption grants no kills")
	assertions.expect_equal(normal_kills_before, simulation.state.normal_kills, "absorption does not enter the normal death path")
	assertions.expect_equal(elite_kills_before, simulation.state.elite_kills, "preserved elite is not counted as killed")
	assertions.expect_equal(chain_before, [
		simulation.state.kill_chain_count,
		simulation.state.kill_chain_last_tick,
		simulation.state.kill_chain_accent_milestone,
	], "absorption does not alter cosmetic kill-chain state")
	assertions.expect_equal(xp_count_before, simulation.xp_pickup_pool.active_count(), "existing XP crystal count is preserved")
	assertions.expect_equal(xp_value_before, simulation.xp_pickup_pool.total_value(), "existing XP crystal value is preserved")
	assertions.expect_equal(arena_before, _arena_object_digest(simulation.arena_object_system), "arena nodes and existing drops are preserved")
	assertions.expect_equal(2, simulation.state.absorbed_normal_count, "transition records both absorbed normal enemies")
	assertions.expect_equal(2, simulation.state.absorbed_enemy_projectile_count, "transition records both absorbed hostile projectiles")
	var boss: EnemyEntity = simulation.enemy_system.boss_entity()
	assertions.expect_true(boss != null, "10:00 production scheduler creates the boss")
	if boss == null:
		return
	assertions.expect_equal(Vector2.ZERO, boss.position, "boss entry starts at the exact arena center")
	assertions.expect_equal(boss_start_tick, boss.spawn_tick, "boss records the entry-start tick")
	assertions.expect_equal(boss_start_tick + BalanceTestFixtures.catalog().envelope.boss_entry_ticks, boss.activation_tick, "boss materializes for exactly sixty ticks")
	assertions.expect_true(boss.is_materializing(boss_start_tick + 59), "boss is still materializing on the last entry tick")
	assertions.expect_true(not boss.is_targetable(boss_start_tick + 59), "boss cannot be targeted before entry completes")
	assertions.expect_true(boss.is_targetable(boss_start_tick + 60), "boss becomes targetable on the exact activation boundary")


func _test_boss_enrage_action_clock(assertions: Variant) -> void:
	var simulation: CombatSimulation = _simulation(assertions, 8504)
	if simulation == null:
		return
	var boss: EnemyEntity = simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.BOSS,
		Vector2.ZERO,
		0,
		false,
		true,
	)
	assertions.expect_true(boss != null, "STOP enrage fixture creates an active boss")
	if boss == null:
		return
	simulation.state.boss_spawned = true
	var enrage_interval: int = simulation.catalog.manifest().combat.boss_enrage_interval_ticks
	var stopped_updates_to_boundary: int = enrage_interval * 2
	simulation.state.stop_until_tick = stopped_updates_to_boundary + 10
	for current_tick: int in range(1, stopped_updates_to_boundary):
		simulation.state.combat_tick = current_tick
		simulation.enemy_system.advance_snapshot(
			[boss.entity_id],
			simulation.player_position,
			current_tick,
		)
	assertions.expect_float(
		float(enrage_interval) - 0.5,
		boss.boss_action_age_ticks,
		"STOP advances the boss enrage clock at half action speed",
	)
	assertions.expect_equal(0, simulation.state.boss_enrage_stacks, "1799.5 action ticks do not grant the first enrage stack")
	simulation.state.combat_tick = stopped_updates_to_boundary
	simulation.enemy_system.advance_snapshot(
		[boss.entity_id],
		simulation.player_position,
		stopped_updates_to_boundary,
	)
	assertions.expect_float(float(enrage_interval), boss.boss_action_age_ticks, "the next half-speed update reaches exactly 1800 action ticks")
	assertions.expect_equal(1, simulation.state.boss_enrage_stacks, "the first stack activates on the exact 1800th action tick")
	var action_age_before_modal: float = boss.boss_action_age_ticks
	var special_age_before_modal: float = boss.special_elapsed_ticks
	var combat_tick_before_modal: int = simulation.state.combat_tick
	simulation.state.phase = GameTypes.RunPhase.LEVEL_UP
	for _modal_update: int in range(10):
		assertions.expect_true(not simulation.advance_tick(Vector2.ZERO), "modal state rejects combat advancement")
	assertions.expect_equal(combat_tick_before_modal, simulation.state.combat_tick, "modal state freezes the combat clock")
	assertions.expect_float(action_age_before_modal, boss.boss_action_age_ticks, "modal state freezes the enrage action clock")
	assertions.expect_float(special_age_before_modal, boss.special_elapsed_ticks, "modal state freezes the boss attack timer")
	assertions.expect_equal(1, simulation.state.boss_enrage_stacks, "modal state cannot advance enrage stacks")


func _test_maximum_enrage_charge(assertions: Variant) -> void:
	var simulation: CombatSimulation = _simulation(assertions, 8505)
	if simulation == null:
		return
	var boss: EnemyEntity = simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.BOSS,
		Vector2.ZERO,
		0,
		false,
		true,
	)
	assertions.expect_true(boss != null, "maximum-enrage charge fixture creates an active boss")
	if boss == null:
		return
	var manifest: SurvivalContentManifest = simulation.catalog.manifest()
	simulation.state.boss_spawned = true
	simulation.state.boss_enrage_stacks = manifest.combat.boss_enrage_max_stacks
	boss.boss_action_age_ticks = float(
		manifest.combat.boss_enrage_interval_ticks * manifest.combat.boss_enrage_max_stacks
	)
	boss.hp = boss.max_hp * 0.30
	boss.boss_phase = 3
	simulation.state.boss_phase = 3
	assertions.expect_equal(
		BalanceTestFixtures.catalog().enemy_for_type(GameTypes.EnemyType.BOSS).telegraph_ticks,
		simulation.enemy_system._boss_action_interval_ticks(
			boss.definition.special_interval_ticks,
			3,
		),
		"maximum enrage clamps the phase-three period to thirty action ticks",
	)
	simulation.enemy_system.resolve_ready_enemy_special_actions(
		[boss.entity_id],
		simulation.player_position,
		0,
		simulation.projectile_pool,
	)
	assertions.expect_true(boss.boss_charge_active, "minimum interval starts a charge instead of firing immediately")
	assertions.expect_equal(16, boss.boss_charge_spoke_count, "phase-three maximum-enrage charge previews all sixteen spokes")
	assertions.expect_equal(0, simulation.projectile_pool.active_count(), "charge start emits no hostile projectile")
	for current_tick: int in range(1, BalanceTestFixtures.catalog().enemy_for_type(GameTypes.EnemyType.BOSS).telegraph_ticks):
		simulation.state.combat_tick = current_tick
		simulation.enemy_system.advance_snapshot(
			[boss.entity_id],
			simulation.player_position,
			current_tick,
		)
		simulation.enemy_system.resolve_ready_enemy_special_actions(
			[boss.entity_id],
			simulation.player_position,
			current_tick,
			simulation.projectile_pool,
		)
	assertions.expect_float(29.0, boss.boss_charge_elapsed_ticks, "maximum-enrage warning lasts through twenty-nine complete action ticks")
	assertions.expect_equal(0, simulation.projectile_pool.active_count(), "no volley fires before the thirtieth charge tick")
	simulation.state.combat_tick = BalanceTestFixtures.catalog().enemy_for_type(GameTypes.EnemyType.BOSS).telegraph_ticks
	simulation.enemy_system.advance_snapshot(
		[boss.entity_id],
		simulation.player_position,
		BalanceTestFixtures.catalog().enemy_for_type(GameTypes.EnemyType.BOSS).telegraph_ticks,
	)
	simulation.enemy_system.resolve_ready_enemy_special_actions(
		[boss.entity_id],
		simulation.player_position,
		BalanceTestFixtures.catalog().enemy_for_type(GameTypes.EnemyType.BOSS).telegraph_ticks,
		simulation.projectile_pool,
	)
	assertions.expect_equal(16, simulation.projectile_pool.active_count(), "sixteen-spoke volley fires exactly after the full thirty-tick warning")
	assertions.expect_true(boss.boss_charge_active, "minimum-period next volley begins a new warning instead of skipping it")
	assertions.expect_float(0.0, boss.boss_charge_elapsed_ticks, "next warning restarts at zero after the volley")


func _test_boss_volley_event_latch(assertions: Variant) -> void:
	var simulation: CombatSimulation = _simulation(assertions, 8506)
	if simulation == null:
		return
	var boss: EnemyEntity = simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.BOSS,
		Vector2.ZERO,
		0,
		false,
		true,
	)
	assertions.expect_true(boss != null, "volley event fixture creates an active boss")
	if boss == null:
		return
	simulation.state.boss_spawned = true
	# Model a phase-two twelve-spoke charge that crossed into phase three before
	# firing. The alternate latch changes only when the volley is emitted.
	boss.boss_phase = 3
	boss.barrage_alternate = true
	simulation._record_boss_action_feedback(true, false, 12)
	var snapshot: CombatSnapshot = simulation.build_snapshot()
	var volley_event: CombatPresentationEvent = null
	for event: CombatPresentationEvent in snapshot.presentation_events:
		if event.kind == CombatPresentationEvent.Kind.BOSS_VOLLEY:
			volley_event = event
			break
	assertions.expect_true(volley_event != null, "volley feedback is emitted after the latched charge fires")
	if volley_event != null:
		assertions.expect_equal(12, volley_event.count, "volley feedback preserves the twelve latched spokes across a phase change")


func _test_shooter_contact_contract(assertions: Variant) -> void:
	var simulation: CombatSimulation = _simulation(assertions, 8506)
	if simulation == null:
		return
	var shooter_definition: EnemyDefinition = simulation.catalog.enemy_for_type(
		GameTypes.EnemyType.SHOOTER
	)
	assertions.expect_true(shooter_definition != null, "SHOOTER remains a registered internal enemy type")
	if shooter_definition == null:
		return
	for definition: EnemyDefinition in simulation.catalog.enemies.values():
		if definition.enemy_type == GameTypes.EnemyType.BOSS:
			continue
		assertions.expect_true(
			definition.special_interval_ticks == 0
			and definition.telegraph_ticks == 0
			and is_finite(definition.projectile_damage)
			and definition.projectile_damage == 0.0
			and is_finite(definition.projectile_speed)
			and definition.projectile_speed == 0.0
			and is_finite(definition.projectile_radius)
			and definition.projectile_radius == 0.0
			and definition.projectile_lifetime_ticks == 0
			and definition.volley_count == 0,
			"non-boss definition %s has no ranged behavior" % definition.enemy_id,
		)
	assertions.expect_true(
		EnemySystem.NORMAL_ENEMY_TYPES.has(GameTypes.EnemyType.SHOOTER),
		"SHOOTER remains in the normal-enemy type set",
	)
	assertions.expect_true(
		simulation.catalog.segment(3).weight_for(GameTypes.EnemyType.SHOOTER) > 0.0,
		"SHOOTER remains in the wave table from segment four onward",
	)
	assertions.expect_true(
		shooter_definition.contact_damage > 0.0,
		"SHOOTER is a contact-damage enemy",
	)
	var property_names: PackedStringArray = []
	for property: Dictionary in shooter_definition.get_property_list():
		property_names.append(property.name)
	assertions.expect_false(property_names.has("preferred_distance_min"), "unused ranged minimum was removed")
	assertions.expect_false(property_names.has("preferred_distance_max"), "unused ranged maximum was removed")
	assertions.expect_equal(0, shooter_definition.special_interval_ticks, "SHOOTER has no ranged attack cadence")
	assertions.expect_float(0.0, shooter_definition.projectile_damage, "SHOOTER has no projectile damage")
	assertions.expect_float(0.0, shooter_definition.projectile_speed, "SHOOTER has no projectile speed")
	assertions.expect_float(0.0, shooter_definition.projectile_radius, "SHOOTER has no projectile radius")
	assertions.expect_equal(0, shooter_definition.projectile_lifetime_ticks, "SHOOTER has no projectile lifetime")
	assertions.expect_equal(0, shooter_definition.volley_count, "SHOOTER has no projectile volley")
	var scaled_contact_enemy: EnemyEntity = simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.PURSUER,
		Vector2(8.0, 0.0),
		-1,
		true,
		true,
	)
	assertions.expect_true(scaled_contact_enemy != null, "scaled contact fixture allocates")
	if scaled_contact_enemy != null:
		assertions.expect_float(
			simulation.catalog.segment_for_tick(simulation.state.combat_tick).damage_multiplier
			* simulation.catalog.manifest().combat.normal_enemy_damage_scale,
			scaled_contact_enemy.damage_multiplier,
			"normal contact enemies apply the shared tuning scale after segment damage",
		)
	var shooter: EnemyEntity = simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.SHOOTER,
		Vector2(6.0, 0.0),
		-1,
		false,
		true,
	)
	assertions.expect_true(shooter != null, "active SHOOTER fixture allocates")
	if shooter == null:
		return
	var initial_distance: float = shooter.position.distance_to(simulation.player_position)
	var shooter_ids: Array[int] = [shooter.entity_id]
	for current_tick: int in range(1, 601):
		simulation.state.combat_tick = current_tick
		simulation.enemy_system.advance_snapshot(
			shooter_ids,
			simulation.player_position,
			current_tick,
		)
		simulation.enemy_system.resolve_ready_enemy_special_actions(
			shooter_ids,
			simulation.player_position,
			current_tick,
			simulation.projectile_pool,
		)
	assertions.expect_true(
		shooter.position.distance_to(simulation.player_position) < initial_distance,
		"SHOOTER directly chases the player instead of holding ranged standoff",
	)
	assertions.expect_equal(0, simulation.projectile_pool.active_count(), "production SHOOTER action path creates zero normal-enemy projectiles")
	var elite: EnemyEntity = simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.ELITE,
		Vector2(-6.0, 0.0),
		-1,
		false,
		true,
	)
	assertions.expect_true(elite != null, "active ELITE contact-only fixture allocates")
	if elite != null:
		simulation.enemy_system.resolve_ready_enemy_special_actions(
			[elite.entity_id],
			simulation.player_position,
			simulation.state.combat_tick,
			simulation.projectile_pool,
		)
		assertions.expect_equal(
			0,
			simulation.projectile_pool.active_count(),
			"production ELITE action path creates zero projectiles",
		)
	shooter.position = simulation.player_position
	var contact_records: Array[Dictionary] = (
		simulation.enemy_system.resolve_contact_damage_candidates(
			shooter_ids,
			simulation.player_position,
			simulation.state.combat_tick,
		)
	)
	assertions.expect_equal(1, contact_records.size(), "SHOOTER resolves one ready contact hit at overlap")
	if not contact_records.is_empty():
		assertions.expect_true(float(contact_records[0].get("raw_damage", 0.0)) > 0.0, "SHOOTER contact hit carries positive damage")


func _test_combat_envelope_gates(assertions: Variant) -> void:
	var simulation: CombatSimulation = _simulation(assertions, 8502)
	if simulation == null:
		return
	var acquired_at_eight: EnemyEntity = simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.BULWARK,
		Vector2(BalanceTestFixtures.catalog().envelope.target_center_radius, 0.0),
		-1,
		false,
		true,
	)
	var rejected_after_eight: EnemyEntity = simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.BULWARK,
		Vector2(BalanceTestFixtures.catalog().envelope.target_center_radius + 0.01, 1.0),
		-1,
		false,
		true,
	)
	assertions.expect_true(
		simulation.weapon_system._is_ally_acquirable(
			acquired_at_eight,
			simulation.player_position,
			simulation.state.combat_tick,
		),
		"enemy center at eight meters remains acquirable",
	)
	assertions.expect_true(
		not simulation.weapon_system._is_ally_acquirable(
			rejected_after_eight,
			simulation.player_position,
			simulation.state.combat_tick,
		),
		"enemy center beyond eight meters cannot be newly acquired",
	)
	var damage_at_ten: EnemyEntity = simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.PURSUER,
		Vector2(BalanceTestFixtures.catalog().envelope.damage_center_radius, 0.0),
		-1,
		false,
		true,
	)
	var rejected_after_ten: EnemyEntity = simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.PURSUER,
		Vector2(BalanceTestFixtures.catalog().envelope.damage_center_radius + 0.01, 0.0),
		-1,
		false,
		true,
	)
	var effect_at_nine: EnemyEntity = simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.PURSUER,
		Vector2(5.0, 0.0),
		-1,
		false,
		true,
	)
	var rejected_after_nine: EnemyEntity = simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.PURSUER,
		Vector2(5.0, 1.0),
		-1,
		false,
		true,
	)
	var damage_at_ten_before: float = damage_at_ten.hp
	var rejected_after_ten_before: float = rejected_after_ten.hp
	var effect_at_nine_before: float = effect_at_nine.hp
	var rejected_after_nine_before: float = rejected_after_nine.hp
	simulation._apply_enemy_hit_records([
		_damage_record(simulation, damage_at_ten.entity_id, 3.0, BalanceTestFixtures.catalog().envelope.effect_outer_radius),
		_damage_record(simulation, rejected_after_ten.entity_id, 3.0, BalanceTestFixtures.catalog().envelope.effect_outer_radius),
		_damage_record(simulation, effect_at_nine.entity_id, 3.0, BalanceTestFixtures.catalog().envelope.effect_outer_radius),
		_damage_record(simulation, rejected_after_nine.entity_id, 3.0, BalanceTestFixtures.catalog().envelope.effect_outer_radius + 0.01),
	])
	assertions.expect_float(damage_at_ten_before - 3.0, damage_at_ten.hp, "body-overlap exception allows a center exactly ten meters away")
	assertions.expect_float(rejected_after_ten_before, rejected_after_ten.hp, "final damage resolution rejects centers beyond ten meters")
	assertions.expect_float(effect_at_nine_before - 3.0, effect_at_nine.hp, "effect outer edge exactly at nine meters is accepted")
	assertions.expect_float(rejected_after_nine_before, rejected_after_nine.hp, "effect outer edge beyond nine meters is rejected")
	var metrics: Dictionary = simulation.visible_combat_metrics()
	assertions.expect_equal(2, metrics["weapon_hits"], "only the two in-contract hit records apply")
	assertions.expect_equal(0, metrics["offscreen_weapon_hits"], "accepted envelope hits remain visible")
	assertions.expect_float(BalanceTestFixtures.catalog().envelope.damage_center_radius, float(metrics["max_hit_center_distance"]), "damage-center metric reaches but never exceeds ten meters")
	assertions.expect_float(BalanceTestFixtures.catalog().envelope.effect_outer_radius, float(metrics["max_effect_outer_distance"]), "effect metric reaches but never exceeds nine meters")


func _test_visible_metric_schema(assertions: Variant) -> void:
	var simulation: CombatSimulation = _simulation(assertions, 8503)
	if simulation == null:
		return
	simulation.state.normal_far_despawn_count = 3
	var metrics: Dictionary = simulation.visible_combat_metrics()
	assertions.expect_equal(REQUIRED_VISIBLE_METRIC_KEYS.size(), metrics.size(), "metrics expose every required visibility and VFX value")
	for key: String in REQUIRED_VISIBLE_METRIC_KEYS:
		assertions.expect_true(metrics.has(key), "visible combat metrics include %s" % key)
	assertions.expect_equal(3, metrics["normal_far_despawns"], "normal far despawns propagate to visible metrics")


func _test_presentation_event_admission(assertions: Variant) -> void:
	var event_simulation: CombatSimulation = _simulation(assertions, 8507)
	if event_simulation == null:
		return
	for event_index: int in range(CombatSimulation.MAX_PRESENTATION_EVENTS_PER_TICK):
		event_simulation._queue_presentation_event(
			event_simulation._make_presentation_event(
				CombatPresentationEvent.Kind.IMPORTANT_SPAWN,
				StringName("important_%d" % event_index),
				Vector2(float(event_index), 0.0),
				CombatPresentationEvent.Priority.IMPORTANT,
			)
		)
	assertions.expect_equal(
		CombatSimulation.MAX_PRESENTATION_EVENTS_PER_TICK,
		event_simulation._presentation_events.size(),
		"important presentation events fill but never exceed the hard sixty-four-event cap",
	)
	var suppressed_before_unique: int = (
		event_simulation.state.feedback_event_suppressed_count
	)
	event_simulation._queue_presentation_event(
		event_simulation._make_presentation_event(
			CombatPresentationEvent.Kind.IMPORTANT_SPAWN,
			&"important_64",
			Vector2.ZERO,
			CombatPresentationEvent.Priority.IMPORTANT,
		)
	)
	assertions.expect_equal(
		CombatSimulation.MAX_PRESENTATION_EVENTS_PER_TICK,
		event_simulation._presentation_events.size(),
		"sixty-fifth unique same-priority important event is bounded",
	)
	assertions.expect_equal(
		suppressed_before_unique + 1,
		event_simulation.state.feedback_event_suppressed_count,
		"same-priority cap suppression is recorded",
	)
	event_simulation._queue_presentation_event(
		event_simulation._make_presentation_event(
			CombatPresentationEvent.Kind.IMPORTANT_SPAWN,
			&"important_0",
			Vector2(99.0, 0.0),
			CombatPresentationEvent.Priority.IMPORTANT,
			2,
		)
	)
	assertions.expect_equal(
		CombatSimulation.MAX_PRESENTATION_EVENTS_PER_TICK,
		event_simulation._presentation_events.size(),
		"compatible important feedback coalesces at the cap",
	)
	assertions.expect_equal(
		3,
		event_simulation._presentation_events[0].count,
		"coalesced important feedback preserves its represented count",
	)
	event_simulation._queue_presentation_event(
		event_simulation._make_presentation_event(
			CombatPresentationEvent.Kind.PLAYER_DEFEATED,
			&"player_defeated",
			Vector2.ZERO,
			CombatPresentationEvent.Priority.TERMINAL,
		)
	)
	assertions.expect_equal(
		CombatSimulation.MAX_PRESENTATION_EVENTS_PER_TICK,
		event_simulation._presentation_events.size(),
		"terminal replacement keeps the presentation queue bounded",
	)
	var terminal_present: bool = false
	for event: CombatPresentationEvent in event_simulation._presentation_events:
		if event.kind == CombatPresentationEvent.Kind.PLAYER_DEFEATED:
			terminal_present = true
			break
	assertions.expect_true(terminal_present, "terminal feedback replaces a lower-priority important event")

	var ordered_simulation: CombatSimulation = _simulation(assertions, 8509)
	if ordered_simulation == null:
		return
	for event_index: int in range(CombatSimulation.PRESENTATION_IMPORTANT_RESERVE):
		ordered_simulation._queue_presentation_event(
			ordered_simulation._make_presentation_event(
				CombatPresentationEvent.Kind.IMPORTANT_SPAWN,
				StringName("ordered_important_%d" % event_index),
				Vector2.ZERO,
				CombatPresentationEvent.Priority.IMPORTANT,
			)
		)
	for event_index: int in range(
		CombatSimulation.MAX_PRESENTATION_EVENTS_PER_TICK
		- CombatSimulation.PRESENTATION_IMPORTANT_RESERVE
	):
		ordered_simulation._queue_presentation_event(
			ordered_simulation._make_presentation_event(
				CombatPresentationEvent.Kind.ENEMY_HIT,
				StringName("ordered_normal_%d" % event_index),
				Vector2.ZERO,
				CombatPresentationEvent.Priority.NORMAL,
			)
		)
	assertions.expect_equal(
		CombatSimulation.MAX_PRESENTATION_EVENTS_PER_TICK,
		ordered_simulation._presentation_events.size(),
		"important-first ordering preserves all thirty-two ordinary admission slots",
	)

	var terminal_simulation: CombatSimulation = _simulation(assertions, 8511)
	if terminal_simulation == null:
		return
	for event_index: int in range(CombatSimulation.MAX_PRESENTATION_EVENTS_PER_TICK):
		terminal_simulation._queue_presentation_event(
			terminal_simulation._make_presentation_event(
				CombatPresentationEvent.Kind.PLAYER_DEFEATED,
				StringName("terminal_%d" % event_index),
				Vector2.ZERO,
				CombatPresentationEvent.Priority.TERMINAL,
			)
		)
	terminal_simulation._queue_presentation_event(
		terminal_simulation._make_presentation_event(
			CombatPresentationEvent.Kind.PLAYER_DEFEATED,
			&"terminal_64",
			Vector2.ZERO,
			CombatPresentationEvent.Priority.TERMINAL,
		)
	)
	assertions.expect_equal(
		CombatSimulation.MAX_PRESENTATION_EVENTS_PER_TICK,
		terminal_simulation._presentation_events.size(),
		"sixty-fifth unique same-priority terminal event is bounded",
	)


func _test_vfx_admission(assertions: Variant) -> void:
	var ordered_vfx_pool := VfxPool.new()
	for request_index: int in range(VfxPool.IMPORTANT_RESERVED_SLOTS):
		assertions.expect_true(
			ordered_vfx_pool.request(
				Vector2(float(request_index), 0.0),
				1.0,
				1.0,
				Color.WHITE,
				0,
				VfxPool.PRIORITY_IMPORTANT,
			) != null,
			"important-first VFX request %d is admitted" % request_index,
		)
	for request_index: int in range(
		VfxPool.MAX_PRODUCTION_REQUESTS_PER_TICK - VfxPool.IMPORTANT_RESERVED_SLOTS
	):
		assertions.expect_true(
			ordered_vfx_pool.request(
				Vector2(float(request_index), 1.0),
				1.0,
				1.0,
				Color.WHITE,
				0,
				VfxPool.PRIORITY_ATTACK,
			) != null,
			"important-first ordering preserves ordinary VFX request %d" % request_index,
		)
	assertions.expect_equal(
		VfxPool.MAX_PRODUCTION_REQUESTS_PER_TICK,
		ordered_vfx_pool.active_count(),
		"VFX reserve is independent of request ordering",
	)
	var hard_cap_vfx_pool := VfxPool.new()
	for request_index: int in range(VfxPool.MAX_PRODUCTION_REQUESTS_PER_TICK):
		hard_cap_vfx_pool.request(
			Vector2(float(request_index), 0.0),
			1.0,
			1.0,
			Color.WHITE,
			0,
			VfxPool.PRIORITY_IMPORTANT,
		)
	var over_cap_vfx: VfxState = hard_cap_vfx_pool.request(
		Vector2.ZERO,
		1.0,
		1.0,
		Color.WHITE,
		0,
		VfxPool.PRIORITY_ATTACK,
	)
	assertions.expect_true(
		over_cap_vfx == null,
		"ordinary VFX cannot exceed the hard cap after sixty-four important requests",
	)
	assertions.expect_equal(
		VfxPool.MAX_PRODUCTION_REQUESTS_PER_TICK,
		hard_cap_vfx_pool.active_count(),
		"VFX hard cap is priority independent",
	)
	assertions.expect_equal(
		1,
		hard_cap_vfx_pool.generic_drop_count,
		"ordinary VFX rejected by the hard cap is recorded",
	)
	assertions.expect_equal(
		0,
		hard_cap_vfx_pool.important_drop_count,
		"hard-cap probe does not misclassify an ordinary VFX drop",
	)


func _test_audio_admission_metrics(assertions: Variant) -> void:
	var audio_simulation: CombatSimulation = _simulation(assertions, 8508)
	if audio_simulation == null:
		return
	for cue_index: int in range(AudioCueAdmission.MAX_NONCRITICAL_CUES_PER_WINDOW):
		audio_simulation._queue_presentation_event(
			audio_simulation._make_presentation_event(
				CombatPresentationEvent.Kind.ENEMY_HIT,
				&"enemy_hit",
				Vector2.ZERO,
				CombatPresentationEvent.Priority.NORMAL,
				1,
				GameTypes.EnemyType.PURSUER,
				StringName("lineage_%d" % cue_index),
			)
		)
	for cue_index: int in range(5):
		audio_simulation._queue_presentation_event(
			audio_simulation._make_presentation_event(
				CombatPresentationEvent.Kind.BOSS_PHASE_CHANGED,
				&"boss_phase",
				Vector2.ZERO,
				CombatPresentationEvent.Priority.IMPORTANT,
				1,
				GameTypes.EnemyType.BOSS,
				StringName("critical_%d" % cue_index),
			)
		)
	audio_simulation._record_audio_cue_metrics()
	var metrics: Dictionary = audio_simulation.visible_combat_metrics()
	assertions.expect_equal(12, metrics["audio_admitted"], "rolling audio policy admits at most twelve cues per second")
	assertions.expect_equal(1, metrics["audio_suppressed"], "rolling audio policy records every excess cue suppression")

	var legacy_audio_simulation: CombatSimulation = _simulation(assertions, 8510)
	if legacy_audio_simulation == null:
		return
	legacy_audio_simulation._step_events.append(&"stop_pickup")
	legacy_audio_simulation._record_audio_cue_metrics()
	legacy_audio_simulation._record_audio_cue_id(&"level_up")
	legacy_audio_simulation._record_audio_cue_id(&"chest_open")
	legacy_audio_simulation._record_audio_cue_id(&"evolution")
	var legacy_metrics: Dictionary = legacy_audio_simulation.visible_combat_metrics()
	assertions.expect_equal(
		4,
		legacy_metrics["audio_admitted"],
		"run audio telemetry includes STOP and modal reward cues",
	)


func _damage_record(
	simulation: CombatSimulation,
	entity_id: int,
	damage: float,
	effect_outer_distance: float,
) -> Dictionary:
	return {
		"entity_id": entity_id,
		"event": simulation.event_router.create_primary(
			simulation.state,
			&"weapon_hit",
			-1,
			&"combat_envelope_probe",
			damage,
		),
		"effect_outer_distance": effect_outer_distance,
	}


func _spawn_hostile_projectile(
	simulation: CombatSimulation,
	source_entity_id: int,
	source_effect_id: StringName,
) -> ProjectileState:
	return simulation.projectile_pool.acquire(
		ProjectileState.FACTION_ENEMY,
		&"transition_probe",
		source_entity_id,
		simulation.player_position,
		Vector2.ZERO,
		0.3,
		99.0,
		10.0,
		10.0,
		simulation.player_position,
		0,
		simulation.state.combat_tick - 1,
		source_effect_id,
	)


func _hostile_projectile_count(simulation: CombatSimulation) -> int:
	var count: int = 0
	for pool_index: int in simulation.projectile_pool.active_indices_snapshot():
		var projectile: ProjectileState = simulation.projectile_pool.slots[pool_index]
		if projectile.faction == ProjectileState.FACTION_ENEMY:
			count += 1
	return count


func _arena_object_digest(arena: ArenaObjectSystem) -> Array:
	var node_entries: Array = []
	for node: ArenaNodeState in arena.nodes:
		node_entries.append([node.site_index, node.position, node.hp, node.active])
	var pickup_entries: Array = []
	for pickup: ArenaPickup in arena.pickups:
		pickup_entries.append([
			pickup.pickup_id,
			int(pickup.kind),
			pickup.position,
			pickup.source_serial,
			pickup.active,
		])
	return [node_entries, pickup_entries, arena.destroyed_node_count]


func _simulation(assertions: Variant, run_seed: int) -> CombatSimulation:
	var catalog := DefinitionCatalog.new()
	assertions.expect_true(catalog.validate_manifest(BalanceTestFixtures.manifest()), "combat content validates")
	if not catalog.is_valid:
		return null
	var state: RunState = RunStateFactory.create(run_seed, catalog)
	var simulation := CombatSimulation.new()
	simulation.initialize(state, catalog)
	return simulation
