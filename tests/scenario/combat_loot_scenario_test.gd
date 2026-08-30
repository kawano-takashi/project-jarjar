extends RefCounted


func test_names() -> PackedStringArray:
	return PackedStringArray([
		"fixed_seed_reward_sequence_reproduces",
		"w8_boss_rewards_wait_until_combat_ends",
		"w8_legendary_can_be_equipped_for_final_score",
	])


func run_test(test_name: String, assertions: Variant, _context: Dictionary) -> void:
	match test_name:
		"fixed_seed_reward_sequence_reproduces":
			_test_reproduction(assertions)
		"w8_boss_rewards_wait_until_combat_ends":
			_test_boss_reward_timing(assertions)
		"w8_legendary_can_be_equipped_for_final_score":
			_test_final_legendary(assertions)
		_:
			assertions.expect_true(false, "registered combat loot scenario test")


func _test_reproduction(assertions: Variant) -> void:
	var first: Array[Dictionary] = _elite_sequence(assertions, 1, 551122)
	var second: Array[Dictionary] = _elite_sequence(assertions, 1, 551122)
	assertions.expect_equal(first, second, "fixed seed reproduces category type rarity and effects")
	assertions.expect_equal(GameTypes.ItemCategory.WEAPON, first[0]["category"], "sequence starts with W1 guaranteed weapon")
	assertions.expect_true(first[0]["guaranteed"], "only first sequence entry is guaranteed")
	assertions.expect_false(first[1]["guaranteed"], "later W1 sequence preserves randomness")


func _test_boss_reward_timing(assertions: Variant) -> void:
	var catalog := DefinitionCatalog.new()
	assertions.expect_true(catalog.load_and_validate(), "W8 timing catalog valid")
	if not catalog.is_valid:
		return
	var state: RunState = RunStateFactory.create(8081, catalog.wave(8))
	state.wave_number = 8
	state.wave_kills = 299
	state.non_boss_spawned = 299
	var simulation := CombatSimulation.new()
	simulation.initialize(state, catalog)
	simulation.freeze_enemy_ai = true
	simulation.freeze_enemy_timers = true
	simulation.freeze_normal_spawn = true
	simulation.freeze_countdown = true
	var boss: EnemyEntity = simulation.enemy_system.enemy_store.get_by_id(0)
	assertions.expect_true(boss != null, "W8 timing fixture starts with boss")
	if boss == null:
		return
	boss.position = Vector2(1.0, 0.0)
	simulation.weapon_damage_override = boss.hp
	var weapon_slot := GameTypes.EquipmentSlot.WEAPON_1
	simulation.weapon_system.attack_elapsed_by_slot[int(weapon_slot)] = (
		simulation.weapon_system.attack_interval_by_slot[int(weapon_slot)]
	)
	simulation.step(Vector2.ZERO, 1.0 / 60.0)
	assertions.expect_equal(GameTypes.RunPhase.COMBAT, state.phase, "boss defeat can precede combat end")
	assertions.expect_true(state.wave_cleared, "boss defeat at 300 kills latches W8 clear")
	assertions.expect_equal(0, state.unopened_rewards.size(), "boss batch is not usable during remaining combat")

	simulation.freeze_countdown = false
	state.time_remaining = 1.0 / 60.0
	simulation.step(Vector2.ZERO, 1.0 / 60.0)
	assertions.expect_equal(GameTypes.RunPhase.REWARD_REVEAL, state.phase, "combat ends before boss batch is granted")
	assertions.expect_equal(8, state.unopened_rewards.size(), "combat end grants exactly seven normal and one legendary")
	assertions.expect_equal(GameTypes.Rarity.LEGENDARY, state.unopened_rewards[7].item.rarity, "deferred batch keeps legendary last")
	assertions.expect_equal(state.physics_tick, state.unopened_rewards[7].acquired_tick, "legendary acquisition occurs on transition tick")


func _test_final_legendary(assertions: Variant) -> void:
	var catalog := DefinitionCatalog.new()
	assertions.expect_true(catalog.load_and_validate(), "W8 score catalog valid")
	if not catalog.is_valid:
		return
	var state: RunState = RunStateFactory.create(8080, catalog.wave(8))
	state.wave_number = 8
	var service := LootService.new()
	service.initialize(state, catalog)
	var rewards: Array[RewardRoll] = service.acquire_boss_chests(Vector2.ZERO, 99)
	for reward: RewardRoll in rewards:
		reward.revealed = true
	assertions.expect_true(RewardApplicationService.apply_revealed(state)["success"], "W8 rewards enter final inventory")
	var legendary: ItemInstance = rewards[7].item
	var target_slot: GameTypes.EquipmentSlot = (
		GameTypes.EquipmentSlot.WEAPON_2
		if legendary.category == GameTypes.ItemCategory.WEAPON
		else GameTypes.EquipmentSlot.CHARM_1
	)
	var location: Dictionary = InventoryService.find_item(state, legendary.item_id)
	assertions.expect_true(InventoryService.apply_move(state, StringName(location["kind"]), int(location["index"]), &"equipped", target_slot)["success"], "final legendary equips before scoring")
	var score: Dictionary = ScoreService.calculate(0, 0, 0, 0, 8, true, InventoryService.equipped_items(state), catalog.score_definition())
	assertions.expect_true(int(score[&"equipment"]) >= 1260 + 30, "final score includes equipped legendary and starter")


func _elite_sequence(assertions: Variant, wave_number: int, run_seed: int) -> Array[Dictionary]:
	var catalog := DefinitionCatalog.new()
	assertions.expect_true(catalog.load_and_validate(), "sequence catalog valid")
	var state: RunState = RunStateFactory.create(run_seed, catalog.wave(wave_number))
	state.wave_number = wave_number
	var service := LootService.new()
	service.initialize(state, catalog)
	var result: Array[Dictionary] = []
	for reward: RewardRoll in service.acquire_elite_chests(Vector2.ZERO, 50):
		var affixes := PackedStringArray()
		for affix: AffixRoll in reward.item.affixes:
			affixes.append("%s:%.0f" % [affix.affix_id, affix.value])
		result.append({
			"category": reward.item.category,
			"weapon_type": reward.item.weapon_type,
			"rarity": reward.item.rarity,
			"affixes": affixes,
			"guaranteed": reward.is_guaranteed_weapon,
		})
	return result
