extends RefCounted


const DELTA: float = 1.0 / 60.0
const PROJECTILE_START: Vector2 = Vector2.ZERO
const PROJECTILE_VELOCITY: Vector2 = Vector2(120.0, 0.0)
const PROJECTILE_TARGET: Vector2 = Vector2(14.0, 0.0)
const LOW_ID_POSITION: Vector2 = Vector2(1.8, 0.0)
const HIGH_ID_POSITION: Vector2 = Vector2(0.8, 0.0)


func test_names() -> PackedStringArray:
	return PackedStringArray([
		"combat_loot_entity_order_and_normal_rate",
		"combat_loot_fixed_special_counts",
		"combat_loot_quota_fallback",
		"combat_loot_success_failure_cleanup",
	])


func run_test(test_name: String, assertions: Variant, _context: Dictionary) -> void:
	match test_name:
		"combat_loot_entity_order_and_normal_rate":
			_test_entity_order_and_normal_rate(assertions)
		"combat_loot_fixed_special_counts":
			_test_fixed_special_counts(assertions)
		"combat_loot_quota_fallback":
			_test_quota_fallback(assertions)
		"combat_loot_success_failure_cleanup":
			_test_success_failure_cleanup(assertions)
		_:
			assertions.expect_true(false, "registered loot combat-loot scenario")


func _test_entity_order_and_normal_rate(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _loaded_catalog(assertions)
	if catalog == null:
		return
	var run_seed: int = _find_seed_for_two_normal_drops(catalog)
	assertions.expect_true(run_seed >= 0, "two-drop combat fixture seed exists")
	if run_seed < 0:
		return

	var expected_state: RunState = RunStateFactory.create(run_seed, catalog.wave(1))
	var expected_service := LootService.new()
	expected_service.initialize(expected_state, catalog)
	var expected_low: RewardRoll = expected_service.try_normal_drop(LOW_ID_POSITION, 1)
	var expected_high: RewardRoll = expected_service.try_normal_drop(HIGH_ID_POSITION, 1)
	assertions.expect_true(expected_low != null and expected_high != null, "fixture gives both normal deaths a chest")

	var simulation: CombatSimulation = _new_simulation(run_seed, catalog, true)
	var low_id_summoned: EnemyEntity = simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.TRACKER,
		LOW_ID_POSITION,
		-1,
		false,
		true,
	)
	var high_id_regular: EnemyEntity = simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.TRACKER,
		HIGH_ID_POSITION,
	)
	assertions.expect_true(low_id_summoned != null and high_id_regular != null, "reverse-death normal fixtures spawn")
	if low_id_summoned == null or high_id_regular == null:
		return
	assertions.expect_true(low_id_summoned.entity_id < high_id_regular.entity_id, "summoned normal owns lower entity id")
	assertions.expect_true(low_id_summoned.summoned_by_boss, "lower-id fixture is boss-summoned normal")
	assertions.expect_false(high_id_regular.summoned_by_boss, "higher-id fixture is regular normal")
	low_id_summoned.hp = 1.0
	high_id_regular.hp = 1.0
	assertions.expect_true(_add_killing_projectile(simulation), "first reverse-death projectile acquired")
	assertions.expect_true(_add_killing_projectile(simulation), "second reverse-death projectile acquired")
	simulation.step(Vector2.ZERO, DELTA)

	assertions.expect_false(simulation.enemy_system.enemy_store.has_entity(low_id_summoned.entity_id), "summoned normal dies in combat path")
	assertions.expect_false(simulation.enemy_system.enemy_store.has_entity(high_id_regular.entity_id), "regular normal dies in combat path")
	assertions.expect_equal(2, simulation.state.wave_kills, "both deaths count in one tick")
	assertions.expect_equal(2, simulation.state.wave_chests, "each normal death performs one successful rate decision")
	assertions.expect_equal(2, simulation.state.unopened_rewards.size(), "two successful natural boxes append two rewards")
	assertions.expect_equal(expected_state.rng_streams.loot_rng.state, simulation.state.rng_streams.loot_rng.state, "combat path consumes the same two normal-rate/content sequences")
	assertions.expect_equal(_reward_ids(expected_state.unopened_rewards), _reward_ids(simulation.state.unopened_rewards), "combat reward IDs follow entity-id loot order")
	assertions.expect_true(simulation.state.unopened_rewards[0].is_guaranteed_main_weapon, "first successful natural box becomes guarantee")
	assertions.expect_false(simulation.state.unopened_rewards[1].is_guaranteed_main_weapon, "second successful natural box remains normal")
	assertions.expect_true(simulation.state.unopened_rewards[0].reward_id < simulation.state.unopened_rewards[1].reward_id, "same-tick rewards retain ascending reserved IDs")
	assertions.expect_equal(2, simulation.chest_visual_pool.active_count(), "both logical rewards have world displays")
	assertions.expect_equal(LOW_ID_POSITION, simulation.chest_visual_pool.slots[0].origin, "guarantee display belongs to minimum entity id despite later death")
	assertions.expect_equal(HIGH_ID_POSITION, simulation.chest_visual_pool.slots[1].origin, "second display belongs to higher entity id")


func _test_fixed_special_counts(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _loaded_catalog(assertions)
	if catalog == null:
		return
	var run_seed: int = 81421
	var expected_state: RunState = RunStateFactory.create(run_seed, catalog.wave(1))
	var expected_service := LootService.new()
	expected_service.initialize(expected_state, catalog)
	expected_service.acquire_elite_chests(LOW_ID_POSITION, 1)
	expected_service.acquire_boss_chests(HIGH_ID_POSITION, 1)

	var simulation: CombatSimulation = _new_simulation(run_seed, catalog, true)
	var low_id_elite: EnemyEntity = simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.ELITE,
		LOW_ID_POSITION,
	)
	var high_id_boss: EnemyEntity = simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.BOSS,
		HIGH_ID_POSITION,
	)
	assertions.expect_true(low_id_elite != null and high_id_boss != null, "special fixed-drop fixtures spawn")
	if low_id_elite == null or high_id_boss == null:
		return
	low_id_elite.hp = 1.0
	high_id_boss.hp = 1.0
	assertions.expect_true(_add_killing_projectile(simulation), "first special-kill projectile acquired")
	assertions.expect_true(_add_killing_projectile(simulation), "second special-kill projectile acquired")
	simulation.step(Vector2.ZERO, DELTA)

	assertions.expect_equal(1, simulation.state.elite_kills, "elite death resolves through combat path")
	assertions.expect_equal(1, simulation.state.boss_kills, "boss death resolves through combat path")
	assertions.expect_equal(11, simulation.state.wave_chests, "elite three plus boss eight keeps exact fixed box total")
	assertions.expect_equal(11, simulation.state.total_chests, "fixed boxes increment total without extra guarantee box")
	assertions.expect_equal(11, simulation.state.unopened_rewards.size(), "fixed boxes append exactly eleven RewardRolls")
	assertions.expect_equal(1, _guarantee_count(simulation.state.unopened_rewards), "first fixed box is replaced by exactly one guarantee")
	assertions.expect_equal(1, _unique_count(simulation.state.unopened_rewards), "boss contributes exactly one UNIQUE")
	assertions.expect_equal(GameTypes.Rarity.UNIQUE, simulation.state.unopened_rewards[10].equipment.rarity, "boss UNIQUE is last after seven non-UNIQUE rewards")
	assertions.expect_equal(0, simulation.state.unopened_rewards[10].equipment.affixes.size(), "boss UNIQUE has no affixes")
	assertions.expect_equal(12, simulation.state.drop_serial, "eleven boxes reserve eleven serials after initial wood stick")
	assertions.expect_equal(expected_state.rng_streams.loot_rng.state, simulation.state.rng_streams.loot_rng.state, "elite and boss fixed boxes consume no rate-decision RNG")
	assertions.expect_equal(_reward_ids(expected_state.unopened_rewards), _reward_ids(simulation.state.unopened_rewards), "special combat rewards match fixed acquisition sequence")
	assertions.expect_equal(11, simulation.chest_visual_pool.active_count(), "all fixed boxes receive displays without count loss")
	for index: int in range(3):
		assertions.expect_equal(LOW_ID_POSITION, simulation.chest_visual_pool.slots[index].origin, "elite fixed display %d uses elite position" % index)
	for index: int in range(3, 11):
		assertions.expect_equal(HIGH_ID_POSITION, simulation.chest_visual_pool.slots[index].origin, "boss fixed display %d uses boss position" % index)


func _test_quota_fallback(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _loaded_catalog(assertions)
	if catalog == null:
		return
	var miss_seed: int = _find_seed_for_first_normal_miss(catalog.wave(1).normal_chest_rate)
	assertions.expect_true(miss_seed >= 0, "fallback combat fixture miss seed exists")
	if miss_seed < 0:
		return
	var fallback_position := Vector2(4.0, -3.0)
	var fallback_simulation: CombatSimulation = _new_simulation(miss_seed, catalog, true)
	fallback_simulation.player_position = fallback_position
	fallback_simulation.state.wave_kills = catalog.wave(1).kill_quota - 1
	var quota_enemy: EnemyEntity = fallback_simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.TRACKER,
		HIGH_ID_POSITION,
	)
	assertions.expect_true(quota_enemy != null, "quota fallback enemy spawns")
	if quota_enemy == null:
		return
	quota_enemy.hp = 1.0
	assertions.expect_true(_add_killing_projectile(fallback_simulation), "quota fallback projectile acquired")
	fallback_simulation.step(Vector2.ZERO, DELTA)

	assertions.expect_true(fallback_simulation.state.wave_cleared, "quota latches after the natural miss")
	assertions.expect_equal(GameTypes.RunPhase.COMBAT, fallback_simulation.state.phase, "frozen countdown leaves latched fixture in combat")
	assertions.expect_equal(1, fallback_simulation.state.wave_chests, "zero-natural quota path adds one fallback box")
	assertions.expect_equal(1, fallback_simulation.state.unopened_rewards.size(), "fallback appends exactly one RewardRoll")
	assertions.expect_true(fallback_simulation.state.unopened_rewards[0].is_guaranteed_main_weapon, "fallback RewardRoll is guaranteed main weapon")
	assertions.expect_equal(fallback_simulation.state.physics_tick, fallback_simulation.state.unopened_rewards[0].acquired_tick, "fallback is logically acquired on quota tick")
	assertions.expect_equal(1, fallback_simulation.chest_visual_pool.active_count(), "fallback creates one immediate world display")
	assertions.expect_equal(fallback_position, fallback_simulation.chest_visual_pool.slots[0].origin, "fallback display uses player position")

	var existing_simulation: CombatSimulation = _new_simulation(20260827, catalog, true)
	existing_simulation.loot_service.acquire_elite_chests(Vector2(-2.0, 1.0), 0)
	existing_simulation.state.wave_kills = catalog.wave(1).kill_quota
	existing_simulation.step(Vector2.ZERO, DELTA)
	assertions.expect_true(existing_simulation.state.wave_cleared, "existing-guarantee quota fixture latches")
	assertions.expect_equal(3, existing_simulation.state.wave_chests, "quota latch does not duplicate an existing guarantee")
	assertions.expect_equal(3, existing_simulation.state.unopened_rewards.size(), "existing elite rewards remain unchanged")
	assertions.expect_equal(1, _guarantee_count(existing_simulation.state.unopened_rewards), "existing guarantee remains unique")


func _test_success_failure_cleanup(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _loaded_catalog(assertions)
	if catalog == null:
		return
	var success_simulation: CombatSimulation = _new_simulation(91173, catalog, false)
	success_simulation.loot_service.acquire_elite_chests(Vector2(2.0, 2.0), 5)
	success_simulation.state.wave_kills = catalog.wave(1).kill_quota
	success_simulation.state.wave_cleared = true
	success_simulation.state.time_remaining = DELTA
	assertions.expect_equal(3, success_simulation.chest_visual_pool.active_count(), "success fixture begins with three displayed acquired chests")
	success_simulation.step(Vector2.ZERO, DELTA)
	assertions.expect_equal(GameTypes.RunPhase.REWARD_REVEAL, success_simulation.state.phase, "successful timeout enters reward reveal")
	assertions.expect_equal(0, success_simulation.chest_visual_pool.active_count(), "success immediately absorbs every remaining display")
	assertions.expect_equal(3, success_simulation.state.unopened_rewards.size(), "success retains the acquired RewardRolls")
	assertions.expect_equal(3, success_simulation.state.wave_chests, "success retains wave chest count")

	var failure_simulation: CombatSimulation = _new_simulation(44119, catalog, false)
	var past_item := ItemInstance.new()
	past_item.item_id = "past-inventory-item"
	past_item.slot = GameTypes.EquipmentSlot.HEAD
	past_item.main_weapon_type = GameTypes.MainWeaponType.UNCLASSIFIED
	past_item.rarity = GameTypes.Rarity.COMMON
	past_item.display_name = "過去装備"
	var past_reward := RewardRoll.new()
	past_reward.reward_id = "past-wave-reward"
	past_reward.wave_number = 0
	past_reward.kind = GameTypes.RewardKind.EQUIPMENT
	past_reward.equipment = past_item
	past_reward.rarity_for_presentation = GameTypes.Rarity.COMMON
	past_reward.revealed = true
	failure_simulation.state.inventory[0] = past_item
	failure_simulation.state.unopened_rewards.append(past_reward)
	failure_simulation.state.total_chests = 1
	var current_rewards: Array[RewardRoll] = failure_simulation.loot_service.acquire_elite_chests(
		Vector2(-2.0, -2.0),
		8,
	)
	assertions.expect_equal(3, current_rewards.size(), "failure fixture current-wave rewards exist")
	failure_simulation.state.time_remaining = DELTA
	failure_simulation.step(Vector2.ZERO, DELTA)

	assertions.expect_equal(GameTypes.RunPhase.FAILED, failure_simulation.state.phase, "pre-quota timeout enters FAILED")
	assertions.expect_equal(0, failure_simulation.chest_visual_pool.active_count(), "FAILED clears current world displays")
	assertions.expect_equal(0, failure_simulation.state.wave_chests, "FAILED clears current-wave chest count")
	assertions.expect_equal(1, failure_simulation.state.total_chests, "FAILED removes only current-wave chests from total")
	assertions.expect_equal(1, failure_simulation.state.unopened_rewards.size(), "FAILED discards only current-wave RewardRolls")
	assertions.expect_equal(past_reward.reward_id, failure_simulation.state.unopened_rewards[0].reward_id, "FAILED retains past-wave reward record")
	assertions.expect_equal(past_item.item_id, (failure_simulation.state.inventory[0] as ItemInstance).item_id, "FAILED preserves past-wave inventory")


func _loaded_catalog(assertions: Variant) -> DefinitionCatalog:
	var catalog := DefinitionCatalog.new()
	assertions.expect_true(catalog.load_and_validate(), "loot combat-loot catalog valid")
	return catalog if catalog.is_valid else null


func _new_simulation(
	run_seed: int,
	catalog: DefinitionCatalog,
	freeze_countdown: bool,
) -> CombatSimulation:
	var state: RunState = RunStateFactory.create(run_seed, catalog.wave(1))
	var simulation := CombatSimulation.new()
	simulation.initialize(state, catalog)
	simulation.freeze_enemy_ai = true
	simulation.freeze_enemy_timers = true
	simulation.freeze_normal_spawn = true
	simulation.freeze_countdown = freeze_countdown
	simulation.weapon_system.attack_elapsed = 0.0
	return simulation


func _add_killing_projectile(simulation: CombatSimulation) -> bool:
	return simulation.projectile_pool.acquire(
		ProjectileState.FACTION_ALLY,
		&"bow",
		-1,
		PROJECTILE_START,
		PROJECTILE_VELOCITY,
		0.20,
		10.0,
		14.0,
		1.0,
		PROJECTILE_TARGET,
		1,
		simulation.state.physics_tick,
	) != null


func _find_seed_for_two_normal_drops(catalog: DefinitionCatalog) -> int:
	for run_seed: int in range(10000):
		var state: RunState = RunStateFactory.create(run_seed, catalog.wave(1))
		var service := LootService.new()
		service.initialize(state, catalog)
		var first: RewardRoll = service.try_normal_drop(LOW_ID_POSITION, 1)
		var second: RewardRoll = service.try_normal_drop(HIGH_ID_POSITION, 1)
		if first != null and second != null:
			return run_seed
	return -1


func _find_seed_for_first_normal_miss(rate: float) -> int:
	for run_seed: int in range(10000):
		var streams: RunRngStreams = RunRngStreams.create(run_seed)
		if streams.loot_rng.randf() >= rate:
			return run_seed
	return -1


func _guarantee_count(rewards: Array[RewardRoll]) -> int:
	var count: int = 0
	for reward: RewardRoll in rewards:
		if reward.is_guaranteed_main_weapon:
			count += 1
	return count


func _unique_count(rewards: Array[RewardRoll]) -> int:
	var count: int = 0
	for reward: RewardRoll in rewards:
		if reward.equipment != null and reward.equipment.rarity == GameTypes.Rarity.UNIQUE:
			count += 1
	return count


func _reward_ids(rewards: Array[RewardRoll]) -> PackedStringArray:
	var result := PackedStringArray()
	for reward: RewardRoll in rewards:
		result.append(reward.reward_id)
	return result
