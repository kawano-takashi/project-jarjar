extends RefCounted


const LootServiceScript := preload("res://src/loot/loot_service.gd")
const ChestVisualPoolScript := preload("res://src/loot/chest_visual_pool.gd")

var _catalog: DefinitionCatalog = null


func test_names() -> PackedStringArray:
	return PackedStringArray([
		"gate04_reward_acquisition_guarantee_and_rng_contract",
		"gate04_chest_visual_pool_and_failure_contract",
		"gate04_reward_payload_presentation_and_determinism_contract",
	])


func run_test(test_name: String, assertions: Variant, _context: Dictionary) -> void:
	match test_name:
		"gate04_reward_acquisition_guarantee_and_rng_contract":
			_test_reward_acquisition_guarantee_and_rng(assertions)
		"gate04_chest_visual_pool_and_failure_contract":
			_test_chest_visual_pool_and_failure(assertions)
		"gate04_reward_payload_presentation_and_determinism_contract":
			_test_reward_payload_presentation_and_determinism(assertions)
		_:
			assertions.expect_true(false, "registered Gate 4 loot-domain test")


func _test_reward_acquisition_guarantee_and_rng(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _loaded_catalog(assertions)
	if catalog == null:
		return
	var wave: WaveDefinition = catalog.wave(1)
	var hit_seed: int = _find_seed_for_first_chest_decision(wave.normal_chest_rate, true)
	var miss_seed: int = _find_seed_for_first_chest_decision(wave.normal_chest_rate, false)
	assertions.expect_true(hit_seed >= 0, "normal-drop hit fixture seed exists")
	assertions.expect_true(miss_seed >= 0, "normal-drop miss fixture seed exists")
	if hit_seed < 0 or miss_seed < 0:
		return

	var miss_state: RunState = _new_state(miss_seed, 1, catalog)
	var miss_service: LootService = LootServiceScript.new()
	miss_service.initialize(miss_state, catalog)
	var expected_miss_rng := RandomNumberGenerator.new()
	expected_miss_rng.seed = miss_state.rng_streams.loot_seed
	var expected_miss_roll: float = expected_miss_rng.randf()
	assertions.expect_true(expected_miss_roll >= wave.normal_chest_rate, "miss fixture is outside chest rate")
	assertions.expect_equal(null, miss_service.try_normal_drop(Vector2.ZERO, 10), "normal miss creates no reward")
	assertions.expect_equal(expected_miss_rng.state, miss_state.rng_streams.loot_rng.state, "normal death consumes exactly one rate randf on miss")
	assertions.expect_equal(0, miss_state.wave_chests, "normal miss adds no chest")
	assertions.expect_equal(1, miss_state.drop_serial, "normal miss reserves no serial")

	var normal_state: RunState = _new_state(hit_seed, 1, catalog)
	var normal_service: LootService = LootServiceScript.new()
	normal_service.initialize(normal_state, catalog)
	var normal_reward: RewardRoll = normal_service.try_normal_drop(Vector2(3.0, -2.0), 42)
	assertions.expect_true(normal_reward != null, "normal hit creates reward")
	if normal_reward == null:
		return

	var expected_state: RunState = _new_state(hit_seed, 1, catalog)
	var decision_value: float = expected_state.rng_streams.loot_rng.randf()
	assertions.expect_true(decision_value < wave.normal_chest_rate, "hit fixture is inside chest rate")
	var expected_service: LootService = LootServiceScript.new()
	expected_service.initialize(expected_state, catalog)
	var expected_rewards: Array[RewardRoll] = expected_service.acquire_fixed_chests(
		1,
		Vector2(3.0, -2.0),
		42,
	)
	assertions.expect_equal(1, expected_rewards.size(), "fixed comparison creates one reward")
	if expected_rewards.is_empty():
		return
	assertions.expect_equal(
		_reward_snapshot(expected_rewards[0], true),
		_reward_snapshot(normal_reward, true),
		"normal hit equals one rate randf followed by fixed natural acquisition",
	)
	assertions.expect_equal(expected_state.rng_streams.loot_rng.state, normal_state.rng_streams.loot_rng.state, "normal hit has exactly one extra rate randf")
	assertions.expect_true(normal_reward.is_guaranteed_main_weapon, "first natural chest is replaced by guarantee")
	assertions.expect_equal(GameTypes.RewardKind.EQUIPMENT, normal_reward.kind, "guarantee kind fixed equipment")
	assertions.expect_equal(GameTypes.EquipmentSlot.MAIN_WEAPON, normal_reward.equipment.slot, "guarantee slot fixed main weapon")
	assertions.expect_equal(&"", normal_reward.equipment.unique_id, "guarantee never unique")
	assertions.expect_equal(1, normal_state.wave_chests, "guarantee replacement does not add a chest")
	assertions.expect_equal(1, normal_state.total_chests, "guarantee replacement increments total once")
	assertions.expect_equal(2, normal_state.drop_serial, "guarantee reserves exactly one serial")
	_assert_equipment_reward_contract(assertions, normal_reward, hit_seed, 1)

	var fixed_state: RunState = _new_state(hit_seed, 1, catalog)
	var fixed_service: LootService = LootServiceScript.new()
	fixed_service.initialize(fixed_state, catalog)
	var fixed_rewards: Array[RewardRoll] = fixed_service.acquire_fixed_chests(1, Vector2.ZERO, 42)
	assertions.expect_equal(1, fixed_rewards.size(), "special fixed acquisition creates requested count")
	assertions.expect_not_equal(normal_state.rng_streams.loot_rng.state, fixed_state.rng_streams.loot_rng.state, "special fixed acquisition has no leading rate randf")
	assertions.expect_true(fixed_rewards[0].is_guaranteed_main_weapon, "first special fixed chest is guarantee replacement")

	var fallback_state: RunState = _new_state(20260827, 1, catalog)
	var fallback_service: LootService = LootServiceScript.new()
	fallback_service.initialize(fallback_state, catalog)
	var fallback: RewardRoll = fallback_service.ensure_guarantee_fallback(Vector2(5.0, 4.0), 99)
	assertions.expect_true(fallback != null, "zero-natural success creates fallback guarantee")
	if fallback != null:
		assertions.expect_true(fallback.is_guaranteed_main_weapon, "fallback is guaranteed main weapon")
		assertions.expect_equal(99, fallback.acquired_tick, "fallback is acquired at quota tick")
	assertions.expect_equal(1, fallback_state.unopened_rewards.size(), "fallback queue contains exactly one reward")
	assertions.expect_equal(1, fallback_state.wave_chests, "fallback creates exactly one chest")
	assertions.expect_equal(null, fallback_service.ensure_guarantee_fallback(Vector2.ZERO, 100), "fallback cannot duplicate guarantee")
	assertions.expect_equal(1, fallback_state.wave_chests, "duplicate fallback attempt changes no count")

	var natural_then_fallback_state: RunState = _new_state(20260828, 1, catalog)
	var natural_then_fallback_service: LootService = LootServiceScript.new()
	natural_then_fallback_service.initialize(natural_then_fallback_state, catalog)
	natural_then_fallback_service.acquire_fixed_chests(1, Vector2.ZERO, 1)
	assertions.expect_equal(null, natural_then_fallback_service.ensure_guarantee_fallback(Vector2.ZERO, 2), "existing natural guarantee suppresses fallback")
	assertions.expect_equal(1, natural_then_fallback_state.wave_chests, "natural guarantee plus fallback attempt remains one chest")


func _test_chest_visual_pool_and_failure(assertions: Variant) -> void:
	var pool: ChestVisualPool = ChestVisualPoolScript.new()
	var first_visual: ChestVisual = pool.acquire("reward-000", Vector2.ZERO, 0)
	for index: int in range(1, ChestVisualPoolScript.CAPACITY):
		pool.acquire("reward-%03d" % index, Vector2(float(index), 0.0), index)
	assertions.expect_equal(128, pool.active_count(), "visual pool fills all 128 slots")
	assertions.expect_equal(0, pool.forced_absorb_count, "full pool has no premature absorption")
	var reused_visual: ChestVisual = pool.acquire("reward-128", Vector2(128.0, 0.0), 128)
	assertions.expect_equal(first_visual, reused_visual, "overflow reuses the oldest active visual")
	assertions.expect_equal("reward-128", first_visual.reward_id, "oldest visual now represents newest acquired reward")
	assertions.expect_equal(128, pool.active_count(), "overflow keeps visual capacity fixed")
	assertions.expect_equal(1, pool.forced_absorb_count, "overflow immediately absorbs exactly one oldest visual")
	assertions.expect_equal(Basis.IDENTITY, reused_visual.current_transform().basis, "all chest visuals use the same unscaled shape transform")

	var catalog: DefinitionCatalog = _loaded_catalog(assertions)
	if catalog == null:
		return
	var reward_pool: ChestVisualPool = ChestVisualPoolScript.new()
	var overflow_state: RunState = _new_state(128, 1, catalog)
	var overflow_service: LootService = LootServiceScript.new()
	overflow_service.initialize(overflow_state, catalog, reward_pool)
	var overflow_rewards: Array[RewardRoll] = overflow_service.acquire_fixed_chests(
		ChestVisualPoolScript.CAPACITY + 1,
		Vector2.ZERO,
		1,
	)
	assertions.expect_equal(129, overflow_rewards.size(), "overflow acquisition returns every logical RewardRoll")
	assertions.expect_equal(129, overflow_state.unopened_rewards.size(), "overflow loses no queued reward")
	assertions.expect_equal(129, overflow_state.total_chests, "overflow loses no logical chest count")
	assertions.expect_equal(128, reward_pool.active_count(), "overflow retains only bounded visual displays")
	assertions.expect_equal(1, reward_pool.forced_absorb_count, "production acquisition immediately absorbs oldest display")

	var timing_pool: ChestVisualPool = ChestVisualPoolScript.new()
	var timing_visual: ChestVisual = timing_pool.acquire("timed", Vector2(2.0, 3.0), 10)
	timing_pool.advance(0.249)
	assertions.expect_true(timing_visual.active, "chest remains visible before 0.25 seconds")
	assertions.expect_true(timing_visual.current_transform().origin.y > ChestVisual.BASE_HEIGHT, "chest physically bounces before absorption")
	timing_pool.advance(0.001)
	assertions.expect_false(timing_visual.active, "chest auto-absorbs at 0.25 seconds")
	assertions.expect_equal(1, timing_pool.completed_absorb_count, "timed absorption counted once")

	var reduced_pool: ChestVisualPool = ChestVisualPoolScript.new()
	reduced_pool.reduce_motion = true
	reduced_pool.reduce_flashes = true
	var reduced_visual: ChestVisual = reduced_pool.acquire("reduced", Vector2.ZERO, 0)
	reduced_pool.advance(0.10)
	assertions.expect_float(
		ChestVisual.BASE_HEIGHT,
		reduced_visual.current_transform().origin.y,
		"Reduce Motion substitutes a static chest position",
	)
	assertions.expect_true(reduced_visual.reduce_flashes, "Reduce Flashes reaches the chest presentation")

	var success_pool: ChestVisualPool = ChestVisualPoolScript.new()
	for index: int in range(3):
		success_pool.acquire("success-%d" % index, Vector2.ZERO, index)
	success_pool.absorb_all()
	assertions.expect_equal(0, success_pool.active_count(), "success immediately absorbs all displayed acquired chests")
	assertions.expect_equal(3, success_pool.completed_absorb_count, "success absorption accounts for every display")
	success_pool.clear()
	assertions.expect_equal(0, success_pool.active_count(), "failure clear removes all displays")
	assertions.expect_equal(0, success_pool.completed_absorb_count, "failure clear resets presentation counters")

	var state: RunState = _new_state(311, 1, catalog)
	var wave_one_service: LootService = LootServiceScript.new()
	wave_one_service.initialize(state, catalog)
	var past_rewards: Array[RewardRoll] = wave_one_service.acquire_fixed_chests(1, Vector2.ZERO, 1)
	assertions.expect_equal(1, past_rewards.size(), "past wave reward fixture exists")
	if past_rewards.is_empty():
		return
	var past_reward: RewardRoll = past_rewards[0]
	past_reward.revealed = true
	var past_item: ItemInstance = past_reward.equipment
	state.inventory[0] = past_item
	state.wave_number = 2
	state.wave_main_weapon_type = GameTypes.MainWeaponType.UNCLASSIFIED
	state.wave_chests = 0
	var wave_two_service: LootService = LootServiceScript.new()
	wave_two_service.initialize(state, catalog)
	wave_two_service.acquire_fixed_chests(2, Vector2.ZERO, 2)
	assertions.expect_equal(3, state.unopened_rewards.size(), "failure fixture contains past and current rewards")
	assertions.expect_equal(2, wave_two_service.discard_current_wave_rewards(), "failure discards current wave chest count")
	assertions.expect_equal(1, state.unopened_rewards.size(), "failure retains past-wave reward record")
	assertions.expect_equal(past_reward.reward_id, state.unopened_rewards[0].reward_id, "failure retained the past-wave reward")
	assertions.expect_equal(past_item.item_id, (state.inventory[0] as ItemInstance).item_id, "failure preserves past-wave inventory")
	assertions.expect_equal(0, state.wave_chests, "failure clears only current wave chest counter")
	assertions.expect_equal(1, state.total_chests, "failure removes current-wave chests from total")


func _test_reward_payload_presentation_and_determinism(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _loaded_catalog(assertions)
	if catalog == null:
		return
	var presentation_state: RunState = _new_state(20260827, 8, catalog)
	var presentation_service: LootService = LootServiceScript.new()
	presentation_service.initialize(presentation_state, catalog)
	var presentation_rewards: Array[RewardRoll] = presentation_service.acquire_fixed_chests(
		1000,
		Vector2.ZERO,
		10,
	)
	var rarity_seen := PackedByteArray([0, 0, 0, 0])
	var skill_seen: bool = false
	var invalid_skill_payloads: int = 0
	var invalid_equipment_payloads: int = 0
	for reward: RewardRoll in presentation_rewards:
		if reward.kind == GameTypes.RewardKind.SKILL:
			skill_seen = true
			if (
				reward.equipment != null
				or reward.skill_id.is_empty()
				or reward.rarity_for_presentation != -1
				or reward.revealed
			):
				invalid_skill_payloads += 1
			continue
		if not _equipment_reward_contract_is_valid(reward, presentation_state.run_seed, 8):
			invalid_equipment_payloads += 1
		rarity_seen[reward.rarity_for_presentation] = 1
	assertions.expect_true(skill_seen, "production reward sample includes skill presentation")
	assertions.expect_equal(0, invalid_skill_payloads, "all skill rewards use only skill_id and presentation sentinel -1")
	assertions.expect_equal(0, invalid_equipment_payloads, "all equipment rewards fix complete valid payloads at acquisition")
	assertions.expect_equal(PackedByteArray([1, 1, 1, 1]), rarity_seen, "equipment presentation covers Common through Legendary as 0..3")

	var first: Dictionary = _generate_fixed_event_sequence(87123, catalog)
	var second: Dictionary = _generate_fixed_event_sequence(87123, catalog)
	assertions.expect_true(
		_reward_list_snapshot(first["rewards"], true)
		== _reward_list_snapshot(second["rewards"], true),
		"same run seed and combat event sequence reproduces every RewardRoll field",
	)
	assertions.expect_equal(first["rng_states"], second["rng_states"], "same event sequence reproduces all mutable RNG states")

	var modes: PackedStringArray = PackedStringArray(["normal", "fast", "all"])
	for mode_index: int in range(modes.size()):
		var generated: Dictionary = _generate_fixed_event_sequence(87123, catalog)
		var rewards: Array[RewardRoll] = generated["rewards"]
		var payload_before: Array[Dictionary] = _reward_list_snapshot(rewards, false)
		var rng_before: Dictionary = _rng_state_snapshot(generated["state"])
		_apply_presentation_choices(
			rewards,
			modes[mode_index],
			mode_index == 1,
			mode_index == 2,
		)
		assertions.expect_true(payload_before == _reward_list_snapshot(rewards, false), "%s reveal changes no reward payload field" % modes[mode_index])
		assertions.expect_equal(rng_before, _rng_state_snapshot(generated["state"]), "%s reveal and Reduce settings consume no RNG" % modes[mode_index])
		var revealed_count: int = 0
		for reward: RewardRoll in rewards:
			if reward.revealed:
				revealed_count += 1
		assertions.expect_equal(rewards.size(), revealed_count, "%s reveal marks every reward visible" % modes[mode_index])


func _loaded_catalog(assertions: Variant) -> DefinitionCatalog:
	if _catalog == null:
		_catalog = DefinitionCatalog.new()
		var valid: bool = _catalog.load_and_validate()
		assertions.expect_true(valid, "Gate 4 DefinitionCatalog valid: %s" % _catalog.error_text)
	return _catalog if _catalog.is_valid else null


func _new_state(run_seed: int, wave_number: int, catalog: DefinitionCatalog) -> RunState:
	var state: RunState = RunStateFactory.create(run_seed, catalog.wave(1))
	state.wave_number = wave_number
	state.wave_main_weapon_type = GameTypes.MainWeaponType.UNCLASSIFIED
	state.time_remaining = catalog.wave(wave_number).duration_seconds
	return state


func _find_seed_for_first_chest_decision(rate: float, should_drop: bool) -> int:
	for run_seed: int in range(10000):
		var streams: RunRngStreams = RunRngStreams.create(run_seed)
		var drops: bool = streams.loot_rng.randf() < rate
		if drops == should_drop:
			return run_seed
	return -1


func _assert_equipment_reward_contract(
	assertions: Variant,
	reward: RewardRoll,
	run_seed: int,
	wave_number: int,
) -> void:
	assertions.expect_true(reward.equipment != null, "equipment reward has ItemInstance")
	if reward.equipment == null:
		return
	var item: ItemInstance = reward.equipment
	assertions.expect_equal(GameTypes.RewardKind.EQUIPMENT, reward.kind, "equipment reward kind")
	assertions.expect_equal(&"", reward.skill_id, "equipment reward skill id empty")
	assertions.expect_equal(item.rarity, reward.rarity_for_presentation, "equipment presentation rarity equals item rarity")
	assertions.expect_true(reward.rarity_for_presentation >= 0 and reward.rarity_for_presentation <= 3, "equipment presentation rarity is 0..3")
	assertions.expect_equal(wave_number, reward.wave_number, "reward wave fixed at acquisition")
	assertions.expect_true(reward.reward_id.begins_with("r-%016x-%02d-" % [run_seed, wave_number]), "reward id has deterministic run/wave prefix")
	assertions.expect_true(item.item_id.begins_with("i-%016x-%02d-" % [run_seed, wave_number]), "item id has deterministic run/wave prefix")
	assertions.expect_equal(reward.reward_id.trim_prefix("r-"), item.item_id.trim_prefix("i-"), "reward and item share one reserved serial")
	assertions.expect_equal(ItemFactory.derive_item_seed(run_seed, item.item_id), item.item_seed, "item_seed derives from complete item_id")
	assertions.expect_true(not item.display_name.is_empty(), "equipment display name fixed at acquisition")
	if item.slot == GameTypes.EquipmentSlot.MAIN_WEAPON:
		assertions.expect_true(
			item.main_weapon_type >= GameTypes.MainWeaponType.BOW
			and item.main_weapon_type <= GameTypes.MainWeaponType.SWORD,
			"main weapon reward has classified weapon type",
		)
	else:
		assertions.expect_equal(
			GameTypes.MainWeaponType.UNCLASSIFIED,
			item.main_weapon_type,
			"non-main weapon type is UNCLASSIFIED",
		)
	assertions.expect_false(reward.revealed, "new reward starts unrevealed")


func _generate_fixed_event_sequence(run_seed: int, catalog: DefinitionCatalog) -> Dictionary:
	var state: RunState = _new_state(run_seed, 1, catalog)
	for wave_number: int in range(1, 4):
		state.wave_number = wave_number
		state.wave_main_weapon_type = GameTypes.MainWeaponType.UNCLASSIFIED
		state.wave_chests = 0
		var service: LootService = LootServiceScript.new()
		service.initialize(state, catalog)
		for death_index: int in range(24):
			service.try_normal_drop(
				Vector2(float(death_index % 5), float(death_index % 3)),
				wave_number * 100 + death_index,
			)
		if wave_number == 2:
			service.acquire_fixed_chests(2, Vector2.ZERO, wave_number * 100 + 90)
		service.ensure_guarantee_fallback(Vector2.ZERO, wave_number * 100 + 99)
	var rewards: Array[RewardRoll] = state.unopened_rewards.duplicate()
	return {
		"state": state,
		"rewards": rewards,
		"rng_states": _rng_state_snapshot(state),
	}


func _equipment_reward_contract_is_valid(
	reward: RewardRoll,
	run_seed: int,
	wave_number: int,
) -> bool:
	if reward == null or reward.equipment == null:
		return false
	var item: ItemInstance = reward.equipment
	if (
		reward.kind != GameTypes.RewardKind.EQUIPMENT
		or not reward.skill_id.is_empty()
		or reward.rarity_for_presentation != item.rarity
		or reward.rarity_for_presentation < 0
		or reward.rarity_for_presentation > 3
		or reward.wave_number != wave_number
		or not reward.reward_id.begins_with("r-%016x-%02d-" % [run_seed, wave_number])
		or not item.item_id.begins_with("i-%016x-%02d-" % [run_seed, wave_number])
		or reward.reward_id.trim_prefix("r-") != item.item_id.trim_prefix("i-")
		or ItemFactory.derive_item_seed(run_seed, item.item_id) != item.item_seed
		or item.display_name.is_empty()
		or reward.revealed
	):
		return false
	if item.slot == GameTypes.EquipmentSlot.MAIN_WEAPON:
		return (
			item.main_weapon_type >= GameTypes.MainWeaponType.BOW
			and item.main_weapon_type <= GameTypes.MainWeaponType.SWORD
		)
	return item.main_weapon_type == GameTypes.MainWeaponType.UNCLASSIFIED


func _apply_presentation_choices(
	rewards: Array[RewardRoll],
	_mode: String,
	_reduce_motion: bool,
	_reduce_flashes: bool,
) -> void:
	for reward: RewardRoll in rewards:
		reward.revealed = true


func _rng_state_snapshot(state: RunState) -> Dictionary:
	return {
		"combat": state.rng_streams.combat_rng.state,
		"loot": state.rng_streams.loot_rng.state,
		"fusion": state.rng_streams.fusion_rng.state,
		"drop_serial": state.drop_serial,
	}


func _reward_list_snapshot(rewards_value: Variant, include_revealed: bool) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var rewards: Array[RewardRoll] = rewards_value
	for reward: RewardRoll in rewards:
		result.append(_reward_snapshot(reward, include_revealed))
	return result


func _reward_snapshot(reward: RewardRoll, include_revealed: bool) -> Dictionary:
	var equipment_snapshot: Variant = null
	if reward.equipment != null:
		var affix_snapshots: Array[Dictionary] = []
		for affix: AffixRoll in reward.equipment.affixes:
			affix_snapshots.append({
				"affix_id": String(affix.affix_id),
				"value": affix.value,
			})
		equipment_snapshot = {
			"item_id": reward.equipment.item_id,
			"item_seed": reward.equipment.item_seed,
			"slot": reward.equipment.slot,
			"main_weapon_type": reward.equipment.main_weapon_type,
			"rarity": reward.equipment.rarity,
			"affixes": affix_snapshots,
			"unique_id": String(reward.equipment.unique_id),
			"display_name": reward.equipment.display_name,
			"locked": reward.equipment.locked,
		}
	var result: Dictionary = {
		"reward_id": reward.reward_id,
		"wave_number": reward.wave_number,
		"acquired_tick": reward.acquired_tick,
		"is_guaranteed_main_weapon": reward.is_guaranteed_main_weapon,
		"kind": reward.kind,
		"equipment": equipment_snapshot,
		"skill_id": String(reward.skill_id),
		"rarity_for_presentation": reward.rarity_for_presentation,
	}
	if include_revealed:
		result["revealed"] = reward.revealed
	return result
