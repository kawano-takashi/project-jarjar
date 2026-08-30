extends RefCounted


func test_names() -> PackedStringArray:
	return PackedStringArray([
		"w1_first_reward_only_is_weapon_guaranteed",
		"w2_fallback_has_no_weapon_guarantee",
		"boss_reward_is_seven_plus_final_legendary",
		"revealed_rewards_apply_as_items_only",
	])


func run_test(test_name: String, assertions: Variant, _context: Dictionary) -> void:
	match test_name:
		"w1_first_reward_only_is_weapon_guaranteed":
			_test_w1_guarantee(assertions)
		"w2_fallback_has_no_weapon_guarantee":
			_test_w2_fallback(assertions)
		"boss_reward_is_seven_plus_final_legendary":
			_test_boss(assertions)
		"revealed_rewards_apply_as_items_only":
			_test_application(assertions)
		_:
			assertions.expect_true(false, "registered loot domain test")


func _test_w1_guarantee(assertions: Variant) -> void:
	var setup: Dictionary = _setup_wave(assertions, 1, 111)
	var service: LootService = setup["service"]
	var rewards: Array[RewardRoll] = service.acquire_elite_chests(Vector2.ZERO, 10)
	assertions.expect_equal(3, rewards.size(), "elite reward count remains three")
	assertions.expect_true(rewards[0].is_guaranteed_weapon, "W1 first item is marked guaranteed")
	assertions.expect_equal(GameTypes.ItemCategory.WEAPON, rewards[0].item.category, "W1 first item is a weapon")
	assertions.expect_false(rewards[1].is_guaranteed_weapon, "W1 second item has no guarantee")
	assertions.expect_false(rewards[2].is_guaranteed_weapon, "W1 third item has no guarantee")
	assertions.expect_equal(3, (setup["state"] as RunState).wave_chests, "existing chest count preserved")


func _test_w2_fallback(assertions: Variant) -> void:
	var setup: Dictionary = _setup_wave(assertions, 2, 222)
	var service: LootService = setup["service"]
	var reward: RewardRoll = service.ensure_reward_fallback(Vector2.ZERO, 20)
	assertions.expect_true(reward != null, "zero-chest wave still receives existing fallback")
	assertions.expect_false(reward.is_guaranteed_weapon, "W2 fallback does not guarantee weapon")
	assertions.expect_equal(1, (setup["state"] as RunState).wave_chests, "fallback preserves one minimum reward")
	assertions.expect_equal(null, service.ensure_reward_fallback(Vector2.ZERO, 21), "fallback only occurs once")
	for wave_number: int in range(2, 9):
		var later_setup: Dictionary = _setup_wave(assertions, wave_number, 220 + wave_number)
		var later_rewards: Array[RewardRoll] = (later_setup["service"] as LootService).acquire_elite_chests(Vector2.ZERO, 22)
		for later_reward: RewardRoll in later_rewards:
			assertions.expect_false(later_reward.is_guaranteed_weapon, "W%d has no weapon guarantee" % wave_number)


func _test_boss(assertions: Variant) -> void:
	var setup: Dictionary = _setup_wave(assertions, 8, 333)
	var rewards: Array[RewardRoll] = (setup["service"] as LootService).acquire_boss_chests(Vector2.ZERO, 30)
	assertions.expect_equal(8, rewards.size(), "boss gives seven normal plus one final item")
	assertions.expect_equal(GameTypes.Rarity.LEGENDARY, rewards[7].item.rarity, "last boss reward is legendary")
	assertions.expect_equal(GameTypes.Rarity.LEGENDARY, rewards[7].rarity_for_presentation, "legendary presentation is fixed")
	assertions.expect_true(rewards[7].item.category in GameTypes.ItemCategory.values(), "legendary category is still weapon or charm")
	assertions.expect_equal(8, (setup["state"] as RunState).total_chests, "boss reward total remains eight")


func _test_application(assertions: Variant) -> void:
	var setup: Dictionary = _setup_wave(assertions, 1, 444)
	var state: RunState = setup["state"]
	var rewards: Array[RewardRoll] = (setup["service"] as LootService).acquire_elite_chests(Vector2.ZERO, 40)
	for reward: RewardRoll in rewards:
		reward.revealed = true
	var result: Dictionary = RewardApplicationService.apply_revealed(state)
	assertions.expect_true(result["success"], "all reward types apply through one item path")
	assertions.expect_equal(0, state.unopened_rewards.size(), "applied queue is empty")
	var stored: int = 0
	for item: ItemInstance in state.inventory:
		if item != null:
			stored += 1
	assertions.expect_equal(3, stored, "all three item rewards enter storage")


func _setup_wave(assertions: Variant, wave_number: int, run_seed: int) -> Dictionary:
	var catalog := DefinitionCatalog.new()
	assertions.expect_true(catalog.load_and_validate(), "loot catalog valid: %s" % catalog.error_text)
	var state: RunState = RunStateFactory.create(run_seed, catalog.wave(wave_number))
	state.wave_number = wave_number
	state.time_remaining = catalog.wave(wave_number).duration_seconds
	var service := LootService.new()
	service.initialize(state, catalog)
	return {"catalog": catalog, "state": state, "service": service}
