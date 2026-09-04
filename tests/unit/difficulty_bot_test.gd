extends RefCounted


const BotScript = preload("res://tests/balance/difficulty_calibration_bot.gd")
const AcceptanceScript = preload("res://tests/balance/difficulty_acceptance.gd")


func test_names() -> PackedStringArray:
	return PackedStringArray([
		"difficulty_bot_prediction_contract_and_view",
		"difficulty_bot_avoids_each_tick_and_respects_walls",
		"difficulty_bot_predicts_special_threats",
		"difficulty_bot_caps_detail_and_separates_history",
		"difficulty_bot_preserves_policies_and_determinism",
		"difficulty_bot_unavoidable_fallback_order",
		"difficulty_acceptance_enforces_two_sided_bounds",
	])


func run_test(test_name: String, assertions: Variant, _context: Dictionary) -> void:
	match test_name:
		"difficulty_bot_prediction_contract_and_view":
			_test_prediction_contract_and_view(assertions)
		"difficulty_bot_avoids_each_tick_and_respects_walls":
			_test_avoidance_and_walls(assertions)
		"difficulty_bot_predicts_special_threats":
			_test_special_threats(assertions)
		"difficulty_bot_caps_detail_and_separates_history":
			_test_detail_and_history(assertions)
		"difficulty_bot_preserves_policies_and_determinism":
			_test_policies_and_determinism(assertions)
		"difficulty_bot_unavoidable_fallback_order":
			_test_fallback_order(assertions)
		"difficulty_acceptance_enforces_two_sided_bounds":
			_test_acceptance_bounds(assertions)
		_:
			assertions.expect_true(false, "registered difficulty bot test")


func _test_prediction_contract_and_view(assertions: Variant) -> void:
	var setup: Dictionary = _bot_fixture(16)
	assertions.expect_true(bool(setup.get("valid", false)), "prediction fixture catalog validates")
	if not bool(setup.get("valid", false)):
		return
	var simulation: CombatSimulation = setup["simulation"]
	var bot: RefCounted = BotScript.new()
	assertions.expect_true(bot.initialize(1, 16), "prediction bot initializes")
	var initial_debug: Dictionary = bot.debug_state()
	assertions.expect_equal(120, initial_debug["prediction_horizon_ticks"], "prediction horizon is exactly two seconds")
	assertions.expect_equal(32, initial_debug["heading_direction_count"], "candidate ring has thirty-two directions")
	assertions.expect_float(0.20, float(initial_debug["safety_margin"]), "combined radii include the common safety margin")
	assertions.expect_float(16.0, float(initial_debug["view_half_width"]), "screen-ground rectangle keeps the projected half width")
	assertions.expect_float(
		10.9869713097598,
		float(initial_debug["view_half_depth"]),
		"screen-ground rectangle keeps the projected half depth",
	)
	var screen_right: Vector2 = EnemySystem.SCREEN_RIGHT_WORLD
	assertions.expect_true(
		bool(bot.call(
			&"_circle_intersects_view",
			Vector2.ZERO,
			screen_right * 16.19,
			0.20,
		)),
		"a radius intersecting the screen rectangle is visible",
	)
	assertions.expect_false(
		bool(bot.call(
			&"_circle_intersects_view",
			Vector2.ZERO,
			screen_right * 16.21,
			0.20,
		)),
		"a circle fully outside the screen rectangle is hidden",
	)
	var pickup_kinds: Array[ArenaPickup.Kind] = [
		ArenaPickup.Kind.CHEST,
		ArenaPickup.Kind.HEAL,
		ArenaPickup.Kind.VACUUM,
		ArenaPickup.Kind.STOP,
	]
	for kind: ArenaPickup.Kind in pickup_kinds:
		simulation.arena_object_system.pickups.append(ArenaPickup.new(
			100 + int(kind),
			kind,
			screen_right * 4.0,
			int(kind),
		))
	simulation.xp_pickup_pool.acquire(screen_right * 5.0, 1, -1, Vector2.ZERO)
	for kind: ArenaPickup.Kind in pickup_kinds:
		var target: Dictionary = bot.call(
			&"_nearest_arena_pickup",
			simulation,
			Vector2.ZERO,
			int(kind),
		)
		assertions.expect_true(bool(target.get("found", false)), "each arena pickup kind uses the shared view")
	var xp_target: Dictionary = bot.call(&"_nearest_xp", simulation, Vector2.ZERO)
	assertions.expect_true(bool(xp_target.get("found", false)), "XP uses the shared view")

	var movement_setup: Dictionary = _bot_fixture(16)
	var movement_simulation: CombatSimulation = movement_setup["simulation"]
	var movement_state: RunState = movement_setup["state"]
	var pickup: XpPickupState = movement_simulation.xp_pickup_pool.acquire(
		Vector2(4.0, 0.0),
		1,
		-1,
		Vector2.ZERO,
	)
	var movement_bot: RefCounted = BotScript.new()
	assertions.expect_true(movement_bot.initialize(1, 16), "every-tick movement bot initializes")
	var first_move: Vector2 = movement_bot.movement_input(movement_simulation)
	assertions.expect_true(first_move.x > 0.9, "visible XP is selected as the objective")
	pickup.position = Vector2(-4.0, 0.0)
	movement_state.combat_tick = 1
	var second_move: Vector2 = movement_bot.movement_input(movement_simulation)
	assertions.expect_true(second_move.x < -0.9, "objective changes are reconsidered on the next combat tick")
	assertions.expect_not_equal(first_move, second_move, "the removed fifteen-tick hold cannot mask a changed observation")
	var same_tick_move: Vector2 = movement_bot.movement_input(movement_simulation)
	assertions.expect_equal(second_move, same_tick_move, "duplicate reads inside one combat tick are stable")
	movement_state.combat_tick = 2
	var equivalent_move: Vector2 = movement_bot.movement_input(movement_simulation)
	assertions.expect_equal(second_move, equivalent_move, "equivalent safety and objective state retains the previous input")
	var avoidance: Dictionary = movement_bot.debug_state()["avoidance"]
	assertions.expect_true(int(avoidance["candidate_count"]) >= 33, "the ring and stop candidate are always present")
	assertions.expect_equal(0, int(avoidance["selected_contact_tick_count"]), "an empty scene chooses a collision-free path")
	assertions.expect_equal(-1, int(avoidance["selected_first_collision_tick"]), "collision-free paths keep the no-contact sentinel")

	var memory_setup: Dictionary = _bot_fixture(17)
	var memory_simulation: CombatSimulation = memory_setup["simulation"]
	var memory_state: RunState = memory_setup["state"]
	var chest: ArenaPickup = memory_simulation.arena_object_system.spawn_chest(Vector2(8.0, 0.0), 0)
	var memory_bot: RefCounted = BotScript.new()
	assertions.expect_true(memory_bot.initialize(1, 17), "chest-memory bot initializes")
	memory_bot.movement_input(memory_simulation)
	assertions.expect_equal(1, memory_bot.debug_state()["seen_chest_count"], "only observed static chests enter memory")
	memory_simulation.player_position = Vector2(-10.0, 0.0)
	memory_state.combat_tick = 1
	memory_bot.movement_input(memory_simulation)
	assertions.expect_equal(1, memory_bot.debug_state()["seen_chest_count"], "an offscreen static chest remains remembered")
	chest.active = false
	memory_simulation.arena_object_system.pickups.erase(chest)
	memory_state.combat_tick = 2
	memory_bot.movement_input(memory_simulation)
	assertions.expect_equal(1, memory_bot.debug_state()["seen_chest_count"], "offscreen disappearance is not observed")
	memory_simulation.player_position = Vector2.ZERO
	memory_state.combat_tick = 3
	memory_bot.movement_input(memory_simulation)
	assertions.expect_equal(0, memory_bot.debug_state()["seen_chest_count"], "a remembered chest is forgotten only when its empty location is visible")


func _test_avoidance_and_walls(assertions: Variant) -> void:
	var setup: Dictionary = _bot_fixture(17)
	assertions.expect_true(bool(setup.get("valid", false)), "avoidance fixture catalog validates")
	if not bool(setup.get("valid", false)):
		return
	var simulation: CombatSimulation = setup["simulation"]
	var state: RunState = setup["state"]
	state.weapons.clear()
	var incoming: ProjectileState = simulation.projectile_pool.acquire(
		ProjectileState.FACTION_ENEMY,
		&"predictive_fixture",
		900,
		Vector2(-5.0, 0.0),
		Vector2(7.5, 0.0),
		0.26,
		8.0,
		20.0,
		3.0,
		Vector2(15.0, 0.0),
		0,
		-1,
		&"predictive_fixture",
		ProjectileState.MovementKind.STRAIGHT,
		-1,
		180,
		0,
		0.0,
		0.5,
	)
	assertions.expect_true(incoming != null, "incoming projectile fixture spawns")
	var bot: RefCounted = BotScript.new()
	assertions.expect_true(bot.initialize(1, 17), "projectile avoidance bot initializes")
	var first_move: Vector2 = bot.movement_input(simulation)
	var first_debug: Dictionary = bot.debug_state()["avoidance"]
	assertions.expect_true(int(first_debug["safe_candidate_count"]) > 0, "incoming projectile leaves at least one predicted safe path")
	assertions.expect_equal(-1, int(first_debug["selected_first_collision_tick"]), "the selected projectile path is safe for the full horizon")
	assertions.expect_true(absf(first_move.y) > 0.25, "a crossing projectile causes lateral avoidance")
	var damage_ticks: int = 0
	var total_damage: float = 0.0
	for _tick: int in range(120):
		var hp_before: float = state.current_hp
		var movement: Vector2 = bot.movement_input(simulation)
		if not simulation.advance_tick(movement):
			break
		var damage: float = maxf(0.0, hp_before - state.current_hp)
		if damage > 0.0:
			damage_ticks += 1
			total_damage += damage
	assertions.expect_equal(0, damage_ticks, "per-tick replanning avoids the crossing projectile in the real tick order")
	assertions.expect_float(0.0, total_damage, "projectile avoidance takes no damage in the fixed scenario")

	var radius: float = CombatEnvelope.PLAYER_BODY_RADIUS + 0.26 + 0.20
	var just_inside: Vector2 = bot.call(
		&"_circle_contact_interval",
		Vector2(radius - 0.001, 0.0),
		Vector2.ZERO,
		radius,
		2.0,
	)
	var just_outside: Vector2 = bot.call(
		&"_circle_contact_interval",
		Vector2(radius + 0.001, 0.0),
		Vector2.ZERO,
		radius,
		2.0,
	)
	assertions.expect_true(just_inside.x >= 0.0, "the safety margin boundary is treated as contact")
	assertions.expect_true(just_outside.x < 0.0, "a stationary circle outside the safety margin is clear")

	var wall_setup: Dictionary = _bot_fixture(17)
	var wall_simulation: CombatSimulation = wall_setup["simulation"]
	wall_simulation.player_position = Vector2(CombatSimulation.ARENA_MIN.x + 0.10, 0.0)
	wall_simulation.xp_pickup_pool.acquire(
		Vector2(CombatSimulation.ARENA_MIN.x, 0.0),
		1,
		-1,
		wall_simulation.player_position,
	)
	var wall_bot: RefCounted = BotScript.new()
	assertions.expect_true(wall_bot.initialize(1, 17), "wall bot initializes")
	assertions.expect_true(wall_bot.movement_input(wall_simulation).x > 0.0, "wall scoring keeps the selected input inward")
	var wall_segments: Array = wall_bot.call(
		&"_player_motion_segments",
		wall_simulation.player_position,
		Vector2.LEFT,
	)
	var final_segment: Dictionary = wall_segments[wall_segments.size() - 1]
	var predicted_end: Vector2 = wall_bot.call(&"_segment_position_at", final_segment, 2.0)
	assertions.expect_float(CombatSimulation.ARENA_MIN.x, predicted_end.x, "prediction applies the same arena clamp as gameplay")


func _test_special_threats(assertions: Variant) -> void:
	var setup: Dictionary = _bot_fixture(17)
	assertions.expect_true(bool(setup.get("valid", false)), "special-threat fixture catalog validates")
	if not bool(setup.get("valid", false)):
		return
	var simulation: CombatSimulation = setup["simulation"]
	var state: RunState = setup["state"]
	var materializing: EnemyEntity = simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.ELITE,
		Vector2(3.0, 0.0),
		state.combat_tick,
		false,
		false,
	)
	assertions.expect_true(materializing != null, "materializing enemy fixture spawns")
	var boss: EnemyEntity = simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.BOSS,
		Vector2(5.0, 2.0),
	)
	assertions.expect_true(boss != null, "boss warning fixture spawns")
	if boss != null:
		boss.boss_charge_active = true
		boss.boss_charge_elapsed_ticks = 20.0
		boss.boss_charge_spoke_count = 16
		boss.boss_charge_half_step = true
	var telegraph: EnemyEntity = simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.ELITE,
		Vector2(-4.0, -2.0),
	)
	assertions.expect_true(telegraph != null, "area telegraph fixture spawns")
	if telegraph != null:
		telegraph.telegraph_active = true
		telegraph.telegraph_position = Vector2(-2.0, -2.0)
	var swarm_positions: Array[Vector2] = [
		Vector2(-6.0, -1.0),
		Vector2(-6.0, 0.0),
		Vector2(-6.0, 1.0),
	]
	for position: Vector2 in swarm_positions:
		var swarm: EnemyEntity = simulation.spawn_fixture_enemy(
			GameTypes.EnemyType.SWARMER,
			position,
		)
		assertions.expect_true(swarm != null, "fixed swarm member fixture spawns")
		if swarm != null:
			swarm.configure_swarm_event(77, Vector2.RIGHT, 20.0, false)
	var bot: RefCounted = BotScript.new()
	assertions.expect_true(bot.initialize(0, 17), "special-threat bot initializes")
	bot.movement_input(simulation)
	var debug: Dictionary = bot.debug_state()
	var counts: Dictionary = debug["threat_counts"]
	var avoidance: Dictionary = debug["avoidance"]
	assertions.expect_equal(1, counts["materializing"], "materializing enemies are observed before activation")
	assertions.expect_equal(1, counts["telegraph"], "visible area telegraphs share threat observation")
	assertions.expect_equal(1, counts["boss_warning"], "visible boss charge is observed")
	assertions.expect_equal(3, counts["swarm_member"], "all visible fixed-direction swarm members contribute density")
	assertions.expect_equal(16, avoidance["boss_spoke_count"], "all phase-three warning spokes bypass the detail cap")
	assertions.expect_equal(1, avoidance["swarm_envelope_count"], "a fixed swarm group contributes one swept envelope")
	assertions.expect_true(
		int(avoidance["detailed_threat_count"]) >= 19,
		"mandatory swarm and boss predictions remain in detailed evaluation",
	)
	if boss != null:
		for spoke_count: int in [8, 12, 16]:
			boss.boss_charge_spoke_count = spoke_count
			var spokes: Array = bot.call(
				&"_boss_warning_spokes",
				simulation,
				boss,
				Vector2.ZERO,
			)
			assertions.expect_equal(
				spoke_count,
				spokes.size(),
				"each visible boss phase predicts every announced projectile spoke",
			)
		boss.boss_charge_spoke_count = 16
	var initial_collection: Dictionary = bot.call(
		&"_collect_visible_threats",
		simulation,
		simulation.player_position,
	)
	var materializing_threat: Dictionary = {}
	for visible_value: Variant in initial_collection.get("visible", []):
		var visible_threat: Dictionary = visible_value
		if visible_threat.get("kind", &"") == &"materializing":
			materializing_threat = visible_threat
			break
	assertions.expect_false(materializing_threat.is_empty(), "the visible entry warning becomes a predicted threat")
	if not materializing_threat.is_empty():
		assertions.expect_equal(
			materializing.activation_tick - state.combat_tick,
			int(materializing_threat["first_active_tick"]),
			"entry prediction begins on the enemy activation tick",
		)
		assertions.expect_true(
			bool(materializing_threat["seek_player"]),
			"an entry warning transitions into pursuit rather than straight motion",
		)
		var entry_segments: Array = bot.call(
			&"_threat_motion_segments",
			materializing_threat,
			state,
		)
		assertions.expect_false(
			bool(entry_segments[0]["damaging"]),
			"an enemy cannot damage while its entry warning is active",
		)
		assertions.expect_true(
			bool(entry_segments[entry_segments.size() - 1]["damaging"]),
			"the same enemy becomes damaging after entry completes",
		)

	state.stop_until_tick = state.combat_tick + 121
	state.combat_tick += 1
	bot.movement_input(simulation)
	var stopped_debug: Dictionary = bot.debug_state()["avoidance"]
	assertions.expect_true(
		int(stopped_debug["safe_candidate_count"]) >= 0,
		"STOP state is accepted by the predictor without consuming future state",
	)
	assertions.expect_equal(16, stopped_debug["boss_spoke_count"], "boss warning spokes remain predicted at half speed during STOP")
	var stopped_collection: Dictionary = bot.call(
		&"_collect_visible_threats",
		simulation,
		simulation.player_position,
	)
	var stopped_normal_segments: Array = []
	var stopped_boss_segments: Array = []
	for visible_value: Variant in stopped_collection.get("visible", []):
		var visible_threat: Dictionary = visible_value
		if visible_threat.get("kind", &"") not in [&"enemy", &"swarm_member"]:
			continue
		var segments: Array = bot.call(
			&"_threat_motion_segments",
			visible_threat,
			state,
		)
		if is_equal_approx(float(visible_threat.get("stop_scale", 0.0)), 0.5):
			stopped_boss_segments = segments
		elif visible_threat.get("kind", &"") == &"swarm_member":
			stopped_normal_segments = segments
	assertions.expect_false(stopped_normal_segments.is_empty(), "a fixed swarm path remains represented during STOP")
	if not stopped_normal_segments.is_empty():
		assertions.expect_equal(
			Vector2.ZERO,
			stopped_normal_segments[0]["velocity"],
			"STOP freezes fixed-direction swarm movement",
		)
		assertions.expect_false(
			bool(stopped_normal_segments[0]["damaging"]),
			"a frozen swarm does not create a contact prediction",
		)
	assertions.expect_false(stopped_boss_segments.is_empty(), "the boss path remains represented during STOP")
	if not stopped_boss_segments.is_empty() and boss != null:
		assertions.expect_float(
			boss.definition.move_speed * 0.5,
			(stopped_boss_segments[0]["velocity"] as Vector2).length(),
			"STOP predicts the boss at half movement speed",
		)

	var all_types_setup: Dictionary = _bot_fixture(29)
	var all_types_simulation: CombatSimulation = all_types_setup["simulation"]
	for enemy_type: GameTypes.EnemyType in [
		GameTypes.EnemyType.PURSUER,
		GameTypes.EnemyType.SWARMER,
		GameTypes.EnemyType.BULWARK,
		GameTypes.EnemyType.SHOOTER,
		GameTypes.EnemyType.ELITE,
		GameTypes.EnemyType.BOSS,
	]:
		var angle: float = TAU * float(int(enemy_type)) / 6.0
		assertions.expect_true(
			all_types_simulation.spawn_fixture_enemy(
				enemy_type,
				Vector2.from_angle(angle) * 5.0,
			) != null,
			"each enemy type fixture spawns",
		)
	var all_types_bot: RefCounted = BotScript.new()
	all_types_bot.initialize(1, 29)
	all_types_bot.movement_input(all_types_simulation)
	assertions.expect_equal(6, all_types_bot.debug_state()["threat_counts"]["enemy"], "all six enemy types enter the common prediction path")
	var all_types_collection: Dictionary = all_types_bot.call(
		&"_collect_visible_threats",
		all_types_simulation,
		all_types_simulation.player_position,
	)
	var seeking_enemy_count: int = 0
	for visible_value: Variant in all_types_collection.get("visible", []):
		var visible_threat: Dictionary = visible_value
		if visible_threat.get("kind", &"") != &"enemy":
			continue
		if bool(visible_threat.get("seek_player", false)):
			seeking_enemy_count += 1
	assertions.expect_equal(
		6,
		seeking_enemy_count,
		"every ordinary enemy, including a non-group Swarmer, is predicted as pursuing",
	)
	var fixed_swarm_collection: Dictionary = bot.call(
		&"_collect_visible_threats",
		simulation,
		simulation.player_position,
	)
	var fixed_swarm_seek_count: int = 0
	for visible_value: Variant in fixed_swarm_collection.get("visible", []):
		var visible_threat: Dictionary = visible_value
		if (
			visible_threat.get("kind", &"") == &"swarm_member"
			and bool(visible_threat.get("seek_player", false))
		):
			fixed_swarm_seek_count += 1
	assertions.expect_equal(
		0,
		fixed_swarm_seek_count,
		"only explicitly configured fixed-direction swarm members bypass pursuit prediction",
	)


func _test_detail_and_history(assertions: Variant) -> void:
	var setup: Dictionary = _bot_fixture(17)
	assertions.expect_true(bool(setup.get("valid", false)), "detail fixture catalog validates")
	if not bool(setup.get("valid", false)):
		return
	var simulation: CombatSimulation = setup["simulation"]
	var state: RunState = setup["state"]
	for index: int in range(40):
		var position: Vector2 = Vector2.from_angle(TAU * float(index) / 40.0) * 7.0
		assertions.expect_true(
			simulation.spawn_fixture_enemy(
				GameTypes.EnemyType.PURSUER,
				position,
			) != null,
			"detail-cap enemy fixture spawns",
		)
	var bot: RefCounted = BotScript.new()
	assertions.expect_true(bot.initialize(1, 17), "detail-cap bot initializes")
	bot.movement_input(simulation)
	var debug: Dictionary = bot.debug_state()
	var avoidance: Dictionary = debug["avoidance"]
	assertions.expect_equal(40, debug["observation_count"], "all visible threats feed lightweight observation")
	assertions.expect_equal(32, avoidance["regular_detailed_threat_count"], "sector representatives and earliest TTC fill exactly the detail cap")
	assertions.expect_equal(32, avoidance["detailed_threat_count"], "ordinary detailed evaluation remains capped")
	var digest_values: Array = bot.deterministic_state_values()
	var observation_entries: Array = digest_values[8]
	assertions.expect_equal(40, observation_entries.size(), "behavior-affecting history is included in deterministic state")
	for entity_id: int in simulation.enemy_system.enemy_store.snapshot_ids_sorted():
		var enemy: EnemyEntity = simulation.enemy_system.enemy_store.get_by_id(entity_id)
		enemy.position = EnemySystem.SCREEN_RIGHT_WORLD * 18.0
	state.combat_tick = 1
	bot.movement_input(simulation)
	assertions.expect_equal(0, bot.debug_state()["observation_count"], "dynamic history is discarded immediately after leaving the view")

	var generation_setup: Dictionary = _bot_fixture(17)
	var generation_simulation: CombatSimulation = generation_setup["simulation"]
	var generation_state: RunState = generation_setup["state"]
	var first_enemy: EnemyEntity = generation_simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.PURSUER,
		Vector2(3.0, 0.0),
	)
	var generation_bot: RefCounted = BotScript.new()
	generation_bot.initialize(1, 17)
	generation_bot.movement_input(generation_simulation)
	var first_history: Array = generation_bot.deterministic_state_values()[8]
	assertions.expect_equal(1, first_history.size(), "first pool generation enters history")
	var first_key: String = str(first_history[0][0])
	assertions.expect_true(
		generation_simulation.enemy_system.enemy_store.remove(first_enemy.entity_id),
		"first pool generation is removed",
	)
	var second_enemy: EnemyEntity = generation_simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.PURSUER,
		Vector2(3.0, 0.0),
	)
	assertions.expect_true(second_enemy != null, "reused pool slot spawns a new generation")
	generation_state.combat_tick = 1
	generation_bot.movement_input(generation_simulation)
	var second_history: Array = generation_bot.deterministic_state_values()[8]
	assertions.expect_equal(1, second_history.size(), "reused slots do not retain a stale history row")
	assertions.expect_not_equal(first_key, str(second_history[0][0]), "history keys separate pool generations")

	var odd_bot: RefCounted = BotScript.new()
	var even_bot: RefCounted = BotScript.new()
	odd_bot.initialize(1, 17)
	even_bot.initialize(1, 18)
	assertions.expect_true(bool(odd_bot.call(&"_stable_id_wins", 1, 2)), "odd seed prefers the lower stable ID")
	assertions.expect_true(bool(even_bot.call(&"_stable_id_wins", 2, 1)), "even seed prefers the higher stable ID")


func _test_policies_and_determinism(assertions: Variant) -> void:
	var setup: Dictionary = _bot_fixture(17)
	assertions.expect_true(bool(setup.get("valid", false)), "policy fixture catalog validates")
	if not bool(setup.get("valid", false)):
		return
	var catalog: DefinitionCatalog = setup["catalog"]
	var state: RunState = setup["state"]
	state.weapons.clear()
	state.weapons.append(RunWeapon.create(
		&"homing_core",
		&"homing_core",
		false,
		state.rng_streams.create_weapon_rng(&"homing_core", 0),
	))
	var offer := LevelOffer.new()
	offer.options = [
		_option(GameTypes.UpgradeKind.PASSIVE, &"cycle_crystal", 0, 5),
		_option(GameTypes.UpgradeKind.WEAPON, &"homing_core", 1, 8),
		_option(GameTypes.UpgradeKind.PASSIVE, &"repair_core", 0, 5),
	]
	var cautious: RefCounted = BotScript.new()
	var normal: RefCounted = BotScript.new()
	var evolution: RefCounted = BotScript.new()
	cautious.initialize(0, 17)
	normal.initialize(1, 17)
	evolution.initialize(2, 17)
	assertions.expect_equal(2, cautious.choose_upgrade(offer, state, catalog), "cautious upgrade priority remains recovery first")
	assertions.expect_equal(0, normal.choose_upgrade(offer, state, catalog), "normal upgrade focus still completes a visible pair")
	assertions.expect_equal(0, evolution.choose_upgrade(offer, state, catalog), "evolution policy still acquires its catalyst first")
	state.passives.append(RunPassive.create(&"cycle_crystal"))
	offer.options[0].current_level = 1
	assertions.expect_equal(1, normal.choose_upgrade(offer, state, catalog), "normal policy raises its paired weapon after the catalyst")
	assertions.expect_equal(1, evolution.choose_upgrade(offer, state, catalog), "evolution policy raises homing core after the catalyst")

	var objective_setup: Dictionary = _bot_fixture(17)
	var objective_simulation: CombatSimulation = objective_setup["simulation"]
	var objective_state: RunState = objective_setup["state"]
	objective_state.current_hp = objective_state.max_hp * 0.50
	objective_simulation.arena_object_system.spawn_chest(Vector2(4.0, 0.0), 0)
	objective_simulation.arena_object_system.pickups.append(ArenaPickup.new(
		700,
		ArenaPickup.Kind.HEAL,
		Vector2(-4.0, 0.0),
		0,
	))
	var objective_cautious: RefCounted = BotScript.new()
	var objective_normal: RefCounted = BotScript.new()
	var objective_evolution: RefCounted = BotScript.new()
	objective_cautious.initialize(0, 17)
	objective_normal.initialize(1, 17)
	objective_evolution.initialize(2, 17)
	assertions.expect_true(objective_cautious.movement_input(objective_simulation).x < -0.9, "cautious objective priority still chooses low-HP healing")
	assertions.expect_true(objective_normal.movement_input(objective_simulation).x > 0.9, "normal objective priority still chooses a chest")
	assertions.expect_true(objective_evolution.movement_input(objective_simulation).x > 0.9, "evolution objective priority still chooses a chest")

	var safety_setup: Dictionary = _bot_fixture(29)
	var safety_simulation: CombatSimulation = safety_setup["simulation"]
	var safety_state: RunState = safety_setup["state"]
	safety_simulation.projectile_pool.acquire(
		ProjectileState.FACTION_ENEMY,
		&"policy_safety",
		-1,
		Vector2(-4.0, 0.0),
		Vector2(7.5, 0.0),
		0.26,
		5.0,
		20.0,
		3.0,
		Vector2(16.0, 0.0),
		0,
		-1,
		&"policy_safety",
		ProjectileState.MovementKind.STRAIGHT,
		-1,
		180,
		0,
		0.0,
		0.5,
	)
	var rng_before: Dictionary = safety_state.rng_streams.state_digest()
	for policy_value: int in range(3):
		var policy_bot: RefCounted = BotScript.new()
		policy_bot.initialize(policy_value, 29)
		policy_bot.movement_input(safety_simulation)
		var policy_debug: Dictionary = policy_bot.debug_state()["avoidance"]
		assertions.expect_true(int(policy_debug["safe_candidate_count"]) > 0, "every policy evaluates the common safe set")
		assertions.expect_equal(-1, policy_debug["selected_first_collision_tick"], "every policy applies safety before its objective score")
	assertions.expect_equal(rng_before, safety_state.rng_streams.state_digest(), "observation and planning consume no gameplay RNG")

	var left_setup: Dictionary = _bot_fixture(43)
	var right_setup: Dictionary = _bot_fixture(43)
	var left_simulation: CombatSimulation = left_setup["simulation"]
	var right_simulation: CombatSimulation = right_setup["simulation"]
	var left_state: RunState = left_setup["state"]
	var right_state: RunState = right_setup["state"]
	var left_projectile: ProjectileState = _add_determinism_projectile(left_simulation)
	var right_projectile: ProjectileState = _add_determinism_projectile(right_simulation)
	var left_bot: RefCounted = BotScript.new()
	var right_bot: RefCounted = BotScript.new()
	left_bot.initialize(1, 43)
	right_bot.initialize(1, 43)
	var left_inputs: Array[Vector2] = []
	var right_inputs: Array[Vector2] = []
	for tick: int in range(5):
		left_state.combat_tick = tick
		right_state.combat_tick = tick
		if tick > 0:
			left_projectile.position += left_projectile.velocity / 60.0
			right_projectile.position += right_projectile.velocity / 60.0
		left_inputs.append(left_bot.movement_input(left_simulation))
		right_inputs.append(right_bot.movement_input(right_simulation))
		assertions.expect_equal(left_bot.debug_state(), right_bot.debug_state(), "same-seed diagnostic state is deterministic each tick")
	assertions.expect_equal(left_inputs, right_inputs, "same-seed input sequence is deterministic")
	assertions.expect_equal(left_bot.deterministic_state_values(), right_bot.deterministic_state_values(), "same-seed observation history digest is deterministic")


func _test_fallback_order(assertions: Variant) -> void:
	var bot: RefCounted = BotScript.new()
	bot.initialize(1, 17)
	var baseline: Dictionary = _fallback_metrics(20, 12, 8.0, 1.0, 5)
	assertions.expect_true(
		bool(bot.call(&"_candidate_is_better", _fallback_metrics(21, 99, 99.0, -5.0, 6), baseline, true)),
		"fallback first maximizes time to first contact",
	)
	assertions.expect_true(
		bool(bot.call(&"_candidate_is_better", _fallback_metrics(20, 11, 99.0, -5.0, 6), baseline, true)),
		"fallback next minimizes predicted contact ticks",
	)
	assertions.expect_true(
		bool(bot.call(&"_candidate_is_better", _fallback_metrics(20, 12, 7.0, -5.0, 6), baseline, true)),
		"fallback next minimizes peak damage",
	)
	assertions.expect_true(
		bool(bot.call(&"_candidate_is_better", _fallback_metrics(20, 12, 8.0, 1.1, 6), baseline, true)),
		"fallback finally maximizes end clearance",
	)
	var stable_winner: Dictionary = _fallback_metrics(20, 12, 8.0, 1.0, 4)
	assertions.expect_true(
		bool(bot.call(&"_candidate_is_better", stable_winner, baseline, true)),
		"a complete tie uses stable candidate order",
	)
	var safe: Dictionary = _fallback_metrics(121, 0, 0.0, 2.0, 9)
	safe["safe"] = true
	assertions.expect_true(
		bool(bot.call(&"_candidate_is_better", safe, baseline, false)),
		"a safe path always beats an unsafe path for every policy",
	)
	var setup: Dictionary = _bot_fixture(17)
	var simulation: CombatSimulation = setup["simulation"]
	var overlap_positions: Array[Vector2] = [
		Vector2(0.4, 0.0),
		Vector2(-0.4, 0.0),
		Vector2(0.0, 0.4),
		Vector2(0.0, -0.4),
	]
	for position: Vector2 in overlap_positions:
		simulation.spawn_fixture_enemy(GameTypes.EnemyType.ELITE, position)
	var trapped_bot: RefCounted = BotScript.new()
	trapped_bot.initialize(1, 17)
	trapped_bot.movement_input(simulation)
	var trapped_debug: Dictionary = trapped_bot.debug_state()["avoidance"]
	assertions.expect_equal(0, trapped_debug["safe_candidate_count"], "an immediate enclosure has no safe candidate")
	assertions.expect_true(bool(trapped_debug["used_unavoidable_fallback"]), "an immediate enclosure records unavoidable fallback use")
	assertions.expect_true(int(trapped_debug["selected_contact_tick_count"]) > 0, "fallback diagnostics retain predicted contact ticks")


func _bot_fixture(run_seed: int) -> Dictionary:
	var catalog := DefinitionCatalog.new()
	if not catalog.load_and_validate():
		return {"valid": false}
	var state: RunState = RunStateFactory.create(run_seed, catalog)
	var simulation := CombatSimulation.new()
	simulation.initialize(state, catalog)
	return {
		"valid": true,
		"catalog": catalog,
		"state": state,
		"simulation": simulation,
	}


func _add_determinism_projectile(simulation: CombatSimulation) -> ProjectileState:
	return simulation.projectile_pool.acquire(
		ProjectileState.FACTION_ENEMY,
		&"determinism",
		-1,
		Vector2(-5.0, 1.0),
		Vector2(7.5, 0.0),
		0.26,
		5.0,
		20.0,
		3.0,
		Vector2(15.0, 1.0),
		0,
		-1,
		&"determinism",
		ProjectileState.MovementKind.STRAIGHT,
		-1,
		180,
		0,
		0.0,
		0.5,
	)


func _fallback_metrics(
	first_collision_tick: int,
	contact_tick_count: int,
	peak_damage: float,
	end_clearance: float,
	stable_rank: int,
) -> Dictionary:
	return {
		"safe": false,
		"first_collision_tick": first_collision_tick,
		"contact_tick_count": contact_tick_count,
		"peak_damage": peak_damage,
		"end_clearance": end_clearance,
		"utility": 0.0,
		"stable_rank": stable_rank,
	}


func _test_acceptance_bounds(assertions: Variant) -> void:
	var passing: Array[Dictionary] = _passing_results()
	var accepted: Dictionary = AcceptanceScript.evaluate(passing)
	assertions.expect_true(bool(accepted["passed"]), "official twelve-run boundary fixture passes")
	assertions.expect_equal(2, accepted["normal_evolved_by_five"], "exactly two normal runs evolve by five minutes")
	assertions.expect_equal(4, accepted["normal_evolved_by_seven"], "all normal runs evolve by seven minutes")
	assertions.expect_float(330.0, float(accepted["normal_mean_evolution_seconds"]), "normal first evolution mean is 330 seconds")
	var passing_segments: Array[Dictionary] = _passing_segment_results()
	var accepted_with_segments: Dictionary = AcceptanceScript.evaluate(
		passing,
		passing_segments,
	)
	assertions.expect_true(
		bool(accepted_with_segments["passed"]),
		"wave, elite, and boss duration boundaries pass together",
	)
	var flat_rest_segments: Array[Dictionary] = []
	flat_rest_segments.assign(passing_segments.duplicate(true))
	for row: Dictionary in flat_rest_segments:
		if int(row["segment_index"]) in [2, 4, 6, 8]:
			row["mean_engaged_normal"] = 80.0
	assertions.expect_false(
		bool(AcceptanceScript.evaluate(passing, flat_rest_segments)["passed"]),
		"a rest interval with only twenty-percent pressure relief fails",
	)
	var wide_passing: Array[Dictionary] = _passing_wide_results()
	var wide_accepted: Dictionary = AcceptanceScript.evaluate(
		wide_passing,
		_passing_segment_results(24),
		true,
	)
	assertions.expect_true(bool(wide_accepted["passed"]), "wide twenty-four-run fixture passes")
	assertions.expect_equal(20, wide_accepted["boss_reached"], "wide fixture uses its own reach range")
	assertions.expect_equal(12, wide_accepted["boss_cleared"], "wide fixture uses its own clear range")

	var too_easy: Array[Dictionary] = []
	too_easy.assign(passing.duplicate(true))
	for row: Dictionary in too_easy:
		row["boss_reached"] = true
	var too_easy_result: Dictionary = AcceptanceScript.evaluate(too_easy)
	assertions.expect_false(bool(too_easy_result["passed"]), "twelve boss reaches fails the upper bound")
	var too_few_reaches: Array[Dictionary] = []
	too_few_reaches.assign(passing.duplicate(true))
	for index: int in range(too_few_reaches.size()):
		too_few_reaches[index]["boss_reached"] = index < 8
	assertions.expect_false(
		bool(AcceptanceScript.evaluate(too_few_reaches)["passed"]),
		"eight boss reaches fails the lower bound",
	)

	var too_hard: Array[Dictionary] = []
	too_hard.assign(passing.duplicate(true))
	for index: int in range(too_hard.size()):
		too_hard[index]["boss_cleared"] = index < 4
	var too_hard_result: Dictionary = AcceptanceScript.evaluate(too_hard)
	assertions.expect_false(bool(too_hard_result["passed"]), "four boss clears fails the lower bound")
	var too_many_clears: Array[Dictionary] = []
	too_many_clears.assign(passing.duplicate(true))
	for index: int in range(too_many_clears.size()):
		too_many_clears[index]["boss_cleared"] = index < 9
	assertions.expect_false(
		bool(AcceptanceScript.evaluate(too_many_clears)["passed"]),
		"nine boss clears fails the upper bound",
	)

	var early_death: Array[Dictionary] = []
	early_death.assign(passing.duplicate(true))
	early_death[0]["death_before_two_minutes"] = true
	assertions.expect_false(
		bool(AcceptanceScript.evaluate(early_death)["passed"]),
		"one death before two minutes fails",
	)

	var too_many_early_evolutions: Array[Dictionary] = []
	too_many_early_evolutions.assign(passing.duplicate(true))
	too_many_early_evolutions[6]["first_evolution_tick"] = 18_000
	var early_evolution_result: Dictionary = AcceptanceScript.evaluate(too_many_early_evolutions)
	assertions.expect_false(bool(early_evolution_result["passed"]), "three normal evolutions by five minutes fails the exact count")

	var forbidden_three_minute_evolution: Array[Dictionary] = []
	forbidden_three_minute_evolution.assign(passing.duplicate(true))
	forbidden_three_minute_evolution[0]["first_evolution_tick"] = 10_800
	var forbidden_result: Dictionary = AcceptanceScript.evaluate(forbidden_three_minute_evolution)
	assertions.expect_false(bool(forbidden_result["passed"]), "any evolution by three minutes fails")

	var late_normal: Array[Dictionary] = []
	late_normal.assign(passing.duplicate(true))
	late_normal[7]["first_evolution_tick"] = 25_201
	assertions.expect_false(
		bool(AcceptanceScript.evaluate(late_normal)["passed"]),
		"a normal evolution after seven minutes fails",
	)
	var low_mean: Array[Dictionary] = []
	low_mean.assign(passing.duplicate(true))
	var low_ticks: Array[int] = [14_400, 15_000, 19_800, 19_800]
	for index: int in range(4):
		low_mean[index + 4]["first_evolution_tick"] = low_ticks[index]
	assertions.expect_false(
		bool(AcceptanceScript.evaluate(low_mean)["passed"]),
		"a normal evolution mean below 315 seconds fails",
	)
	var high_mean: Array[Dictionary] = []
	high_mean.assign(passing.duplicate(true))
	var high_ticks: Array[int] = [18_000, 18_600, 23_400, 24_000]
	for index: int in range(4):
		high_mean[index + 4]["first_evolution_tick"] = high_ticks[index]
	assertions.expect_false(
		bool(AcceptanceScript.evaluate(high_mean)["passed"]),
		"a normal evolution mean above 345 seconds fails",
	)

	var overflowed: Array[Dictionary] = []
	overflowed.assign(passing.duplicate(true))
	overflowed[0]["pool_overflow_count"] = 1
	var overflow_result: Dictionary = AcceptanceScript.evaluate(overflowed)
	assertions.expect_false(bool(overflow_result["passed"]), "any pool overflow fails the literal all-pool gate")
	var orphaned: Array[Dictionary] = []
	orphaned.assign(passing.duplicate(true))
	orphaned[0]["pool_orphan_count"] = 1
	assertions.expect_false(
		bool(AcceptanceScript.evaluate(orphaned)["passed"]),
		"any pool orphan fails the literal all-pool gate",
	)
	var important_vfx_dropped: Array[Dictionary] = []
	important_vfx_dropped.assign(passing.duplicate(true))
	important_vfx_dropped[0]["important_vfx_dropped"] = 1
	assertions.expect_false(
		bool(AcceptanceScript.evaluate(important_vfx_dropped)["passed"]),
		"dropping any elite, boss, or terminal VFX fails the hard gate",
	)
	var short_results: Array[Dictionary] = []
	short_results.assign(passing.slice(0, 11))
	assertions.expect_false(
		bool(AcceptanceScript.evaluate(short_results)["passed"]),
		"eleven rows fail the exact run-count contract",
	)
	var wrong_policy_count: Array[Dictionary] = []
	wrong_policy_count.assign(passing.duplicate(true))
	wrong_policy_count[4]["policy"] = "cautious"
	assertions.expect_false(
		bool(AcceptanceScript.evaluate(wrong_policy_count)["passed"]),
		"three normal rows fail the exact policy-count contract",
	)
	var no_evolutions: Array[Dictionary] = []
	no_evolutions.assign(passing.duplicate(true))
	for index: int in range(4, 8):
		no_evolutions[index]["first_evolution_tick"] = -1
	assertions.expect_float(
		-1.0,
		float(AcceptanceScript.evaluate(no_evolutions)["normal_mean_evolution_minutes"]),
		"missing normal evolutions retain the minus-one minute sentinel",
	)


func _option(
	kind: GameTypes.UpgradeKind,
	content_id: StringName,
	current_level: int,
	max_level: int,
) -> UpgradeOption:
	var option := UpgradeOption.new()
	option.kind = kind
	option.content_id = content_id
	option.current_level = current_level
	option.next_level = current_level + 1
	option.max_level = max_level
	return option


func _passing_results() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for index: int in range(12):
		var policy_name: String = "cautious"
		var first_evolution_tick: int = 21_600
		if index >= 4 and index < 8:
			policy_name = "normal"
			var normal_ticks: Array[int] = [17_400, 18_000, 21_600, 22_200]
			first_evolution_tick = normal_ticks[index - 4]
		elif index >= 8:
			policy_name = "evolution"
		results.append({
			"policy": policy_name,
			"death_before_two_minutes": false,
			"boss_reached": index < 10,
			"boss_cleared": index < 6,
			"boss_fight_seconds": 90.0,
			"first_evolution_tick": first_evolution_tick,
			"weapon_hits": 100,
			"weapon_kills": 20,
			"visible_weapon_hits": 100,
			"visible_weapon_kills": 20,
			"offscreen_weapon_hits": 0,
			"offscreen_weapon_kills": 0,
			"max_hit_center_distance": 9.5,
			"max_kill_center_distance": 9.5,
			"max_effect_outer_distance": 8.9,
			"peak_visible_enemies": 120,
			"mean_visible_enemies": 72.0,
			"peak_engaged_enemies": 96,
			"mean_engaged_enemies": 52.0,
			"peak_materializing_enemies": 16,
			"mean_materializing_enemies": 4.0,
			"absorbed_normal_count": 0,
			"absorbed_enemy_projectile_count": 0,
			"feedback_emitted": 100,
			"feedback_suppressed": 0,
			"vfx_admitted": 100,
			"vfx_suppressed": 0,
			"important_vfx_dropped": 0,
			"audio_admitted": 80,
			"audio_suppressed": 20,
			"pool_overflow_count": 0,
			"pool_orphan_count": 0,
			"elite_1_spawn_tick": 7_200,
			"elite_1_kill_seconds": 45.0,
			"elite_2_spawn_tick": 14_400,
			"elite_2_kill_seconds": 45.0,
			"elite_3_spawn_tick": 21_600,
			"elite_3_kill_seconds": 45.0,
			"elite_4_spawn_tick": 28_800,
			"elite_4_kill_seconds": 45.0,
		})
	return results


func _passing_wide_results() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for row: Dictionary in _passing_results():
		results.append(row)
		var duplicate: Dictionary = row.duplicate(true)
		duplicate["seed"] = int(row.get("seed", 0)) + 100
		results.append(duplicate)
	return results


func _passing_segment_results(run_count: int = 12) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var runs_per_policy: int = floori(float(run_count) / 3.0)
	for run_index: int in range(run_count):
		for segment_index: int in range(10):
			var is_peak: bool = segment_index in [1, 3, 5, 7]
			var is_rest: bool = segment_index in [2, 4, 6, 8]
			results.append({
				"policy": ["cautious", "normal", "evolution"][
					floori(float(run_index) / float(runs_per_policy))
				],
				"seed": run_index % 4,
				"segment_index": segment_index,
				"completed": true,
				"mean_engaged_normal": 100.0 if is_peak else (70.0 if is_rest else 50.0),
				"normal_kills": 120 if is_peak else (100 if is_rest else 50),
				"normal_xp": 120 if is_peak else (100 if is_rest else 50),
			})
	return results
