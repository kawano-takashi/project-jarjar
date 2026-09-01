extends RefCounted


const BotScript = preload("res://tests/balance/difficulty_calibration_bot.gd")
const AcceptanceScript = preload("res://tests/balance/difficulty_acceptance.gd")


func test_names() -> PackedStringArray:
	return PackedStringArray([
		"difficulty_bot_uses_visible_deterministic_rules",
		"difficulty_acceptance_enforces_two_sided_bounds",
	])


func run_test(test_name: String, assertions: Variant, _context: Dictionary) -> void:
	match test_name:
		"difficulty_bot_uses_visible_deterministic_rules":
			_test_bot_rules(assertions)
		"difficulty_acceptance_enforces_two_sided_bounds":
			_test_acceptance_bounds(assertions)
		_:
			assertions.expect_true(false, "registered difficulty bot test")


func _test_bot_rules(assertions: Variant) -> void:
	var catalog := DefinitionCatalog.new()
	assertions.expect_true(catalog.load_and_validate(), "difficulty bot catalog validates")
	if not catalog.is_valid:
		return
	var state: RunState = RunStateFactory.create(17, catalog)
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
	var rng_before: Dictionary = state.rng_streams.state_digest()
	var cautious: RefCounted = BotScript.new()
	var normal: RefCounted = BotScript.new()
	var evolution: RefCounted = BotScript.new()
	assertions.expect_true(cautious.initialize(0, 17), "cautious policy initializes")
	assertions.expect_true(normal.initialize(1, 17), "normal policy initializes")
	assertions.expect_true(evolution.initialize(2, 17), "evolution policy initializes")
	assertions.expect_equal(2, cautious.choose_upgrade(offer, state, catalog), "cautious policy prefers recovery")
	assertions.expect_equal(0, normal.choose_upgrade(offer, state, catalog), "normal policy first completes a visible evolution pair")
	assertions.expect_equal(0, evolution.choose_upgrade(offer, state, catalog), "evolution policy first acquires the pair")
	state.passives.append(RunPassive.create(&"cycle_crystal"))
	offer.options[0].current_level = 1
	assertions.expect_equal(1, normal.choose_upgrade(offer, state, catalog), "normal policy raises the paired base weapon after acquiring its passive")
	assertions.expect_equal(1, evolution.choose_upgrade(offer, state, catalog), "evolution policy then raises homing core")

	var simulation := CombatSimulation.new()
	simulation.initialize(state, catalog)
	simulation.xp_pickup_pool.acquire(
		Vector2(4.0, 0.0),
		1,
		-1,
		simulation.player_position,
	)
	var collection_bot: RefCounted = BotScript.new()
	assertions.expect_true(collection_bot.initialize(1, 17), "collection bot initializes")
	var collection_move: Vector2 = collection_bot.movement_input(simulation)
	assertions.expect_true(collection_move.x > 0.0, "normal policy moves toward visible XP")
	simulation.player_position = Vector2(8.0, 0.0)
	state.combat_tick = 14
	assertions.expect_equal(
		collection_move,
		collection_bot.movement_input(simulation),
		"movement heading is held before the exact fifteen-tick decision boundary",
	)
	state.combat_tick = 15
	assertions.expect_true(
		collection_bot.movement_input(simulation).x < 0.0,
		"movement objective is reconsidered on the fifteenth tick",
	)
	simulation.player_position = Vector2.ZERO
	state.combat_tick = 0
	var threat: EnemyEntity = simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.SWARMER,
		Vector2(1.0, 0.0),
		-1,
	)
	assertions.expect_true(threat != null, "movement fixture spawns a visible threat")
	var avoidance_bot: RefCounted = BotScript.new()
	assertions.expect_true(avoidance_bot.initialize(0, 17), "avoidance bot initializes")
	var avoidance_move: Vector2 = avoidance_bot.movement_input(simulation)
	assertions.expect_true(avoidance_move.x < 0.0, "cautious policy moves away from a close threat")

	var crowd_state: RunState = RunStateFactory.create(17, catalog)
	var crowd_simulation := CombatSimulation.new()
	crowd_simulation.initialize(crowd_state, catalog)
	crowd_simulation.xp_pickup_pool.acquire(
		Vector2(4.0, 0.0),
		1,
		-1,
		crowd_simulation.player_position,
	)
	var crowd_positions: Array[Vector2] = [
		Vector2(1.95, 0.0),
		Vector2(-2.0, 0.0),
		Vector2(0.0, 2.0),
		Vector2(0.0, -2.0),
	]
	for position: Vector2 in crowd_positions:
		assertions.expect_true(
			crowd_simulation.spawn_fixture_enemy(
				GameTypes.EnemyType.SWARMER,
				position,
				-1,
			) != null,
			"crowd fixture spawns a current visible threat",
		)
	var crowd_bot: RefCounted = BotScript.new()
	assertions.expect_true(crowd_bot.initialize(1, 17), "crowd avoidance bot initializes")
	var crowd_move: Vector2 = crowd_bot.movement_input(crowd_simulation)
	var crowd_avoidance: Dictionary = crowd_bot.debug_state()["avoidance"]
	assertions.expect_true(
		bool(crowd_avoidance["used_low_confidence_escape"]),
		"opposing current threats select a deterministic low-confidence escape",
	)
	assertions.expect_true(
		float(crowd_avoidance["pressure"]) > float(crowd_avoidance["resultant"]),
		"opposing current threats retain pressure instead of cancelling it",
	)
	assertions.expect_float(
		1.0,
		crowd_move.length(),
		"low-confidence crowd evaluation still emits a full deterministic heading",
	)

	var wall_state: RunState = RunStateFactory.create(17, catalog)
	var wall_simulation := CombatSimulation.new()
	wall_simulation.initialize(wall_state, catalog)
	wall_simulation.player_position = Vector2(CombatSimulation.ARENA_MIN.x + 0.25, 0.0)
	for index: int in range(8):
		var wall_threat_position := Vector2(
			wall_simulation.player_position.x + 1.0,
			-1.4 + float(index) * 0.4,
		)
		assertions.expect_true(
			wall_simulation.spawn_fixture_enemy(
				GameTypes.EnemyType.SWARMER,
				wall_threat_position,
				-1,
			) != null,
			"wall fixture spawns a current visible threat",
		)
	var wall_bot: RefCounted = BotScript.new()
	assertions.expect_true(wall_bot.initialize(0, 17), "wall avoidance bot initializes")
	assertions.expect_true(
		wall_bot.movement_input(wall_simulation).x > 0.0,
		"inward wall constraint cannot be overpowered by crowd pressure",
	)

	var memory_state: RunState = RunStateFactory.create(17, catalog)
	var memory_simulation := CombatSimulation.new()
	memory_simulation.initialize(memory_state, catalog)
	memory_simulation.arena_object_system.spawn_chest(Vector2(10.0, 0.0), 0)
	var memory_bot: RefCounted = BotScript.new()
	assertions.expect_true(memory_bot.initialize(1, 17), "chest memory bot initializes")
	assertions.expect_true(memory_bot.movement_input(memory_simulation).x > 0.0, "visible chest becomes the objective")
	memory_simulation.player_position = Vector2(-10.0, 0.0)
	memory_state.combat_tick = 15
	assertions.expect_true(memory_bot.movement_input(memory_simulation).x > 0.0, "seen chest remains known outside awareness")
	assertions.expect_equal(1, memory_bot.debug_state()["seen_chest_count"], "only a seen chest enters memory")

	var tie_state: RunState = RunStateFactory.create(17, catalog)
	var tie_simulation := CombatSimulation.new()
	tie_simulation.initialize(tie_state, catalog)
	tie_simulation.xp_pickup_pool.acquire(Vector2(4.0, 1.0), 1, -1, Vector2.ZERO)
	tie_simulation.xp_pickup_pool.acquire(Vector2(4.0, -1.0), 1, -1, Vector2.ZERO)
	var odd_tie_bot: RefCounted = BotScript.new()
	var even_tie_bot: RefCounted = BotScript.new()
	assertions.expect_true(odd_tie_bot.initialize(1, 17), "odd-seed tie bot initializes")
	assertions.expect_true(even_tie_bot.initialize(1, 18), "even-seed tie bot initializes")
	assertions.expect_true(odd_tie_bot.movement_input(tie_simulation).y > 0.0, "odd seed resolves an ID tie downward")
	assertions.expect_true(even_tie_bot.movement_input(tie_simulation).y < 0.0, "even seed resolves an ID tie upward")

	var cap_state: RunState = RunStateFactory.create(17, catalog)
	var cap_simulation := CombatSimulation.new()
	cap_simulation.initialize(cap_state, catalog)
	for index: int in range(10):
		var position: Vector2 = Vector2.from_angle(TAU * float(index) / 10.0) * 1.5
		var elite: EnemyEntity = cap_simulation.spawn_fixture_enemy(
			GameTypes.EnemyType.ELITE,
			position,
			-1,
		)
		if elite != null:
			elite.telegraph_active = true
			elite.telegraph_position = position
		cap_simulation.projectile_pool.acquire(
			ProjectileState.FACTION_ENEMY,
			&"difficulty_fixture",
			-1,
			position,
			Vector2.ZERO,
			0.1,
			1.0,
			10.0,
			10.0,
			position,
			0,
			-1,
		)
	var cap_bot: RefCounted = BotScript.new()
	assertions.expect_true(cap_bot.initialize(0, 17), "threat-cap bot initializes")
	cap_bot.movement_input(cap_simulation)
	var threat_counts: Dictionary = cap_bot.debug_state()["threat_counts"]
	assertions.expect_equal(8, threat_counts["enemy"], "enemy awareness keeps at most eight current threats")
	assertions.expect_equal(8, threat_counts["projectile"], "projectile awareness keeps at most eight current threats")
	assertions.expect_equal(8, threat_counts["telegraph"], "telegraph awareness keeps at most eight current threats")
	assertions.expect_equal(rng_before, state.rng_streams.state_digest(), "bot observation and choices consume no gameplay RNG")


func _test_acceptance_bounds(assertions: Variant) -> void:
	var passing: Array[Dictionary] = _passing_results()
	var accepted: Dictionary = AcceptanceScript.evaluate(passing)
	assertions.expect_true(bool(accepted["passed"]), "official twelve-run boundary fixture passes")
	assertions.expect_equal(2, accepted["normal_evolved_by_five"], "exactly two normal runs evolve by five minutes")
	assertions.expect_equal(4, accepted["normal_evolved_by_seven"], "all normal runs evolve by seven minutes")
	assertions.expect_float(306.0, float(accepted["normal_mean_evolution_seconds"]), "normal first evolution mean is 306 seconds")

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
		"a normal evolution mean below 288 seconds fails",
	)
	var high_mean: Array[Dictionary] = []
	high_mean.assign(passing.duplicate(true))
	var high_ticks: Array[int] = [17_900, 18_000, 21_600, 21_600]
	for index: int in range(4):
		high_mean[index + 4]["first_evolution_tick"] = high_ticks[index]
	assertions.expect_false(
		bool(AcceptanceScript.evaluate(high_mean)["passed"]),
		"a normal evolution mean above 324 seconds fails",
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
			first_evolution_tick = 17_280 if index < 6 else 19_440
		elif index >= 8:
			policy_name = "evolution"
		results.append({
			"policy": policy_name,
			"death_before_two_minutes": false,
			"boss_reached": index < 10,
			"boss_cleared": index < 6,
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
		})
	return results
