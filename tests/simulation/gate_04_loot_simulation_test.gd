extends RefCounted


const LootServiceScript := preload("res://src/loot/loot_service.gd")
const UniqueSelectorScript := preload("res://src/loot/unique_selector.gd")
const FusionServiceScript := preload("res://src/inventory/fusion_service.gd")

const SIMULATION_SEED: int = 20260827
const DRAW_COUNT: int = 100000
const RUN_COUNT: int = 100

var _catalog: DefinitionCatalog = null


func test_names() -> PackedStringArray:
	return PackedStringArray([
		"gate04_reward_kind_rarity_and_guarantee_distribution",
		"gate04_normal_fusion_and_unique_selector_distribution",
		"gate04_chest_counts_and_fusion_progression",
	])


func run_test(test_name: String, assertions: Variant, _context: Dictionary) -> void:
	match test_name:
		"gate04_reward_kind_rarity_and_guarantee_distribution":
			_test_reward_kind_rarity_and_guarantee_distribution(assertions)
		"gate04_normal_fusion_and_unique_selector_distribution":
			_test_normal_fusion_and_unique_selector_distribution(assertions)
		"gate04_chest_counts_and_fusion_progression":
			_test_chest_counts_and_fusion_progression(assertions)
		_:
			assertions.expect_true(false, "registered Gate 4 loot simulation test")


func _test_reward_kind_rarity_and_guarantee_distribution(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _loaded_catalog(assertions)
	if catalog == null:
		return
	var kind_rng := _seeded_rng()
	var equipment_count: int = 0
	var skill_count: int = 0
	for _draw: int in range(DRAW_COUNT):
		if LootServiceScript.select_reward_kind(kind_rng) == GameTypes.RewardKind.EQUIPMENT:
			equipment_count += 1
		else:
			skill_count += 1
	_assert_percent(assertions, 90.0, _percent(equipment_count, DRAW_COUNT), 0.6, "normal reward equipment 90 percent")
	_assert_percent(assertions, 10.0, _percent(skill_count, DRAW_COUNT), 0.6, "normal reward skill 10 percent")

	var representative_waves := PackedInt32Array([1, 3, 5, 7])
	for wave_number: int in representative_waves:
		var wave: WaveDefinition = catalog.wave(wave_number)
		var rarity_rng := _seeded_rng()
		var rarity_counts := PackedInt32Array([0, 0, 0, 0])
		for _draw: int in range(DRAW_COUNT):
			var rarity: GameTypes.Rarity = LootServiceScript.select_rarity(wave, rarity_rng)
			rarity_counts[rarity] += 1
		for rarity_value: int in GameTypes.Rarity.values():
			var expected_percent: float = 100.0 * float(wave.rarity_weights[rarity_value])
			_assert_percent(
				assertions,
				expected_percent,
				_percent(rarity_counts[rarity_value], DRAW_COUNT),
				0.5,
				"W%d rarity %s" % [wave_number, GameTypes.rarity_to_key(rarity_value as GameTypes.Rarity)],
			)

	var guarantee_cases: Array[Dictionary] = [
		{
			"label": "W1 UNCLASSIFIED",
			"wave": 1,
			"snapshot": GameTypes.MainWeaponType.UNCLASSIFIED,
			"expected": PackedFloat64Array([100.0 / 3.0, 100.0 / 3.0, 100.0 / 3.0]),
		},
		{
			"label": "W2 BOW",
			"wave": 2,
			"snapshot": GameTypes.MainWeaponType.BOW,
			"expected": PackedFloat64Array([50.0, 25.0, 25.0]),
		},
		{
			"label": "W2 STAFF",
			"wave": 2,
			"snapshot": GameTypes.MainWeaponType.STAFF,
			"expected": PackedFloat64Array([25.0, 50.0, 25.0]),
		},
		{
			"label": "W2 SWORD",
			"wave": 2,
			"snapshot": GameTypes.MainWeaponType.SWORD,
			"expected": PackedFloat64Array([25.0, 25.0, 50.0]),
		},
		{
			"label": "W2 UNCLASSIFIED",
			"wave": 2,
			"snapshot": GameTypes.MainWeaponType.UNCLASSIFIED,
			"expected": PackedFloat64Array([100.0 / 3.0, 100.0 / 3.0, 100.0 / 3.0]),
		},
	]
	for guarantee_case: Dictionary in guarantee_cases:
		var guarantee_rng := _seeded_rng()
		var type_counts := PackedInt32Array([0, 0, 0])
		var invalid_count: int = 0
		for _draw: int in range(DRAW_COUNT):
			var weapon_type: GameTypes.MainWeaponType = LootServiceScript.select_guaranteed_main_weapon_type(
				int(guarantee_case["wave"]),
				guarantee_case["snapshot"] as GameTypes.MainWeaponType,
				guarantee_rng,
			)
			if weapon_type < GameTypes.MainWeaponType.BOW or weapon_type > GameTypes.MainWeaponType.SWORD:
				invalid_count += 1
			else:
				type_counts[weapon_type - GameTypes.MainWeaponType.BOW] += 1
		assertions.expect_equal(0, invalid_count, "%s guarantee emits only classified weapon types" % guarantee_case["label"])
		var expected: PackedFloat64Array = guarantee_case["expected"]
		for type_index: int in range(3):
			_assert_percent(
				assertions,
				expected[type_index],
				_percent(type_counts[type_index], DRAW_COUNT),
				0.8,
				"%s guarantee %s" % [
					guarantee_case["label"],
					GameTypes.main_weapon_type_to_key((type_index + GameTypes.MainWeaponType.BOW) as GameTypes.MainWeaponType),
				],
			)


func _test_normal_fusion_and_unique_selector_distribution(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _loaded_catalog(assertions)
	if catalog == null:
		return
	var normal_rng := _seeded_rng()
	var normal_unique_count: int = 0
	var normal_non_unique_count: int = 0
	var normal_slot_counts := PackedInt32Array([0, 0, 0, 0, 0, 0])
	for _draw: int in range(DRAW_COUNT):
		var shape: Dictionary = LootServiceScript.select_normal_equipment_shape(normal_rng, catalog)
		var unique_id: StringName = shape["unique_id"] as StringName
		if not unique_id.is_empty():
			normal_unique_count += 1
		else:
			normal_non_unique_count += 1
			var slot: GameTypes.EquipmentSlot = shape["slot"] as GameTypes.EquipmentSlot
			normal_slot_counts[slot] += 1
	_assert_percent(assertions, 4.0, _percent(normal_unique_count, DRAW_COUNT), 0.3, "normal loot equipment unique 4 percent")
	_assert_six_slot_distribution(assertions, normal_slot_counts, normal_non_unique_count, "normal unique-miss slot")

	var unique_rng := _seeded_rng()
	var unique_counts: Dictionary[StringName, int] = {}
	for unique_id: StringName in UniqueSelectorScript.UNIQUE_IDS:
		unique_counts[unique_id] = 0
	var invalid_unique_count: int = 0
	for _draw: int in range(DRAW_COUNT):
		var selected_unique: StringName = UniqueSelectorScript.select_won(unique_rng)
		if unique_counts.has(selected_unique):
			unique_counts[selected_unique] += 1
		else:
			invalid_unique_count += 1
	assertions.expect_equal(0, invalid_unique_count, "independent UniqueSelector emits only fixed six IDs")
	for unique_id: StringName in UniqueSelectorScript.UNIQUE_IDS:
		_assert_percent(
			assertions,
			100.0 / 6.0,
			_percent(unique_counts[unique_id], DRAW_COUNT),
			0.6,
			"independent UniqueSelector %s" % unique_id,
		)

	var materials: Array[ItemInstance] = [
		_manual_material("fusion-material-0"),
		_manual_material("fusion-material-1"),
		_manual_material("fusion-material-2"),
	]
	var fusion_rng := _seeded_rng()
	var fusion_unique_count: int = 0
	var fusion_non_unique_count: int = 0
	var fusion_slot_counts := PackedInt32Array([0, 0, 0, 0, 0, 0])
	var fusion_failure_count: int = 0
	for draw_index: int in range(DRAW_COUNT):
		var result: Dictionary = FusionServiceScript.fuse(
			materials,
			0,
			0,
			[],
			false,
			SIMULATION_SEED,
			1,
			draw_index + 1,
			GameTypes.MainWeaponType.UNCLASSIFIED,
			fusion_rng,
			catalog,
		)
		if not bool(result["success"]):
			fusion_failure_count += 1
			continue
		var output: ItemInstance = result["output"] as ItemInstance
		if not output.unique_id.is_empty():
			fusion_unique_count += 1
		else:
			fusion_non_unique_count += 1
			fusion_slot_counts[output.slot] += 1
	assertions.expect_equal(0, fusion_failure_count, "100k production FusionService rolls all succeed")
	_assert_percent(assertions, 4.0, _percent(fusion_unique_count, DRAW_COUNT), 0.3, "fusion output unique 4 percent")
	_assert_six_slot_distribution(assertions, fusion_slot_counts, fusion_non_unique_count, "fusion unique-miss slot")


func _test_chest_counts_and_fusion_progression(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _loaded_catalog(assertions)
	if catalog == null:
		return
	var chest_totals := PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0])
	var guarantee_count_failures: int = 0
	var replacement_count_failures: int = 0
	var fusion_reached_epic: int = 0
	var fusion_reached_legendary: int = 0
	var direct_epic_total: int = 0
	var direct_legendary_total: int = 0
	var fusion_epic_total: int = 0
	var fusion_legendary_total: int = 0
	for run_seed: int in range(RUN_COUNT):
		var result: Dictionary = _simulate_reward_rows_and_fusion(run_seed, catalog)
		var wave_chests: PackedInt32Array = result["wave_chests"]
		for wave_index: int in range(8):
			chest_totals[wave_index] += wave_chests[wave_index]
		guarantee_count_failures += int(result["guarantee_count_failures"])
		replacement_count_failures += int(result["replacement_count_failures"])
		if bool(result["fusion_reached_epic"]):
			fusion_reached_epic += 1
		if bool(result["fusion_reached_legendary"]):
			fusion_reached_legendary += 1
		direct_epic_total += int(result["direct_epic"])
		direct_legendary_total += int(result["direct_legendary"])
		fusion_epic_total += int(result["fusion_epic"])
		fusion_legendary_total += int(result["fusion_legendary"])

	for wave_index: int in range(8):
		var mean: float = float(chest_totals[wave_index]) / float(RUN_COUNT)
		print("GATE04_CHEST_MEAN wave=%d mean=%.4f total=%d seeds=%d" % [wave_index + 1, mean, chest_totals[wave_index], RUN_COUNT])
		assertions.expect_true(
			mean >= 15.0 and mean <= 25.0,
			"W%d chest mean 15..25 actual=%.4f" % [wave_index + 1, mean],
		)
	print(
		"GATE04_FUSION_PROGRESSION epic_reached=%d legendary_reached=%d direct_epic=%d fusion_epic=%d direct_legendary=%d fusion_legendary=%d seeds=%d"
		% [
			fusion_reached_epic,
			fusion_reached_legendary,
			direct_epic_total,
			fusion_epic_total,
			direct_legendary_total,
			fusion_legendary_total,
			RUN_COUNT,
		]
	)
	assertions.expect_equal(0, guarantee_count_failures, "every seed and wave has exactly one guaranteed main weapon")
	assertions.expect_equal(0, replacement_count_failures, "first natural guarantee replacement never increases natural chest count")
	assertions.expect_true(fusion_reached_epic >= 95, "fusion-derived Epic reaches at least 95 seeds actual=%d" % fusion_reached_epic)
	assertions.expect_true(fusion_reached_legendary >= 90, "fusion-derived Legendary reaches at least 90 seeds actual=%d" % fusion_reached_legendary)
	assertions.expect_true(fusion_epic_total > direct_epic_total, "fusion Epic total exceeds direct drops fusion=%d direct=%d" % [fusion_epic_total, direct_epic_total])
	assertions.expect_true(fusion_legendary_total > direct_legendary_total, "fusion Legendary total exceeds direct drops fusion=%d direct=%d" % [fusion_legendary_total, direct_legendary_total])


func _simulate_reward_rows_and_fusion(run_seed: int, catalog: DefinitionCatalog) -> Dictionary:
	var state: RunState = RunStateFactory.create(run_seed, catalog.wave(1))
	var wood_stick: ItemInstance = state.equipped[GameTypes.EquipmentSlot.MAIN_WEAPON]
	var equipped_ids: Array[String] = [wood_stick.item_id]
	var materials: Array[ItemInstance] = []
	var wave_chests := PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0])
	var guarantee_count_failures: int = 0
	var replacement_count_failures: int = 0
	var direct_epic: int = 0
	var direct_legendary: int = 0
	var fusion_epic: int = 0
	var fusion_legendary: int = 0
	var event_tick: int = 0
	for wave_number: int in range(1, 9):
		var wave: WaveDefinition = catalog.wave(wave_number)
		state.wave_number = wave_number
		state.wave_main_weapon_type = GameTypes.MainWeaponType.UNCLASSIFIED
		state.wave_chests = 0
		var service: LootService = LootServiceScript.new()
		service.initialize(state, catalog)
		var natural_chests: int = 0
		var normal_kills: int = ceili(float(wave.kill_quota) * 1.5)
		for _kill_index: int in range(normal_kills):
			event_tick += 1
			if service.try_normal_drop(Vector2.ZERO, event_tick) != null:
				natural_chests += 1
		var fixed_count: int = 3 if wave_number == 4 else (8 if wave_number == 8 else 0)
		if fixed_count > 0:
			event_tick += 1
			var fixed_rewards: Array[RewardRoll] = service.acquire_fixed_chests(
				fixed_count,
				Vector2.ZERO,
				event_tick,
			)
			natural_chests += fixed_rewards.size()
		var fallback: RewardRoll = service.ensure_guarantee_fallback(Vector2.ZERO, event_tick)
		var expected_wave_chests: int = natural_chests if natural_chests > 0 else 1
		if state.wave_chests != expected_wave_chests:
			replacement_count_failures += 1
		if natural_chests > 0 and fallback != null:
			replacement_count_failures += 1
		wave_chests[wave_number - 1] = state.wave_chests
		var guaranteed_count: int = 0
		for reward: RewardRoll in state.unopened_rewards:
			if reward.wave_number != wave_number:
				continue
			if reward.is_guaranteed_main_weapon:
				guaranteed_count += 1
			if reward.kind != GameTypes.RewardKind.EQUIPMENT or reward.equipment == null:
				continue
			if reward.equipment.rarity == GameTypes.Rarity.EPIC:
				direct_epic += 1
			elif reward.equipment.rarity == GameTypes.Rarity.LEGENDARY:
				direct_legendary += 1
			if reward.equipment.unique_id.is_empty():
				materials.append(reward.equipment)
		if guaranteed_count != 1:
			guarantee_count_failures += 1
		state.unopened_rewards.clear()

		for rarity: GameTypes.Rarity in [
			GameTypes.Rarity.COMMON,
			GameTypes.Rarity.RARE,
			GameTypes.Rarity.EPIC,
		]:
			while true:
				var candidates: Array[ItemInstance] = _sorted_materials(materials, rarity)
				if candidates.size() < 3:
					break
				var selected: Array[ItemInstance] = [candidates[0], candidates[1], candidates[2]]
				var fusion_result: Dictionary = FusionServiceScript.fuse(
					selected,
					0,
					0,
					equipped_ids,
					false,
					run_seed,
					wave_number,
					state.drop_serial,
					GameTypes.MainWeaponType.UNCLASSIFIED,
					state.rng_streams.fusion_rng,
					catalog,
				)
				if not bool(fusion_result["success"]):
					break
				for consumed: ItemInstance in selected:
					materials.erase(consumed)
				state.drop_serial = int(fusion_result["next_drop_serial"])
				var output: ItemInstance = fusion_result["output"] as ItemInstance
				if output.rarity == GameTypes.Rarity.EPIC:
					fusion_epic += 1
				elif output.rarity == GameTypes.Rarity.LEGENDARY:
					fusion_legendary += 1
				if output.unique_id.is_empty():
					materials.append(output)

	return {
		"wave_chests": wave_chests,
		"guarantee_count_failures": guarantee_count_failures,
		"replacement_count_failures": replacement_count_failures,
		"fusion_reached_epic": fusion_epic > 0,
		"fusion_reached_legendary": fusion_legendary > 0,
		"direct_epic": direct_epic,
		"direct_legendary": direct_legendary,
		"fusion_epic": fusion_epic,
		"fusion_legendary": fusion_legendary,
	}


func _loaded_catalog(assertions: Variant) -> DefinitionCatalog:
	if _catalog == null:
		_catalog = DefinitionCatalog.new()
		var valid: bool = _catalog.load_and_validate()
		assertions.expect_true(valid, "Gate 4 simulation DefinitionCatalog valid: %s" % _catalog.error_text)
	return _catalog if _catalog.is_valid else null


func _seeded_rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = SIMULATION_SEED
	return rng


func _percent(count: int, denominator: int) -> float:
	return 100.0 * float(count) / float(denominator) if denominator > 0 else 0.0


func _assert_percent(
	assertions: Variant,
	expected: float,
	actual: float,
	tolerance: float,
	label: String,
) -> void:
	assertions.expect_true(
		absf(actual - expected) <= tolerance,
		"%s expected=%.4f%% tolerance=%.4fpp actual=%.4f%%" % [label, expected, tolerance, actual],
	)


func _assert_six_slot_distribution(
	assertions: Variant,
	counts: PackedInt32Array,
	denominator: int,
	label: String,
) -> void:
	assertions.expect_true(denominator > 0, "%s has non-empty conditional sample" % label)
	if denominator <= 0:
		return
	for slot_value: int in GameTypes.EquipmentSlot.values():
		_assert_percent(
			assertions,
			100.0 / 6.0,
			_percent(counts[slot_value], denominator),
			0.6,
			"%s %s" % [label, GameTypes.equipment_slot_to_key(slot_value as GameTypes.EquipmentSlot)],
		)


func _manual_material(item_id: String) -> ItemInstance:
	var item := ItemInstance.new()
	item.item_id = item_id
	item.rarity = GameTypes.Rarity.COMMON
	item.slot = GameTypes.EquipmentSlot.HANDS
	item.main_weapon_type = GameTypes.MainWeaponType.UNCLASSIFIED
	item.unique_id = &""
	item.locked = false
	return item


func _sorted_materials(
	materials: Array[ItemInstance],
	rarity: GameTypes.Rarity,
) -> Array[ItemInstance]:
	var result: Array[ItemInstance] = []
	for item: ItemInstance in materials:
		if item.rarity == rarity and item.unique_id.is_empty():
			result.append(item)
	result.sort_custom(_item_id_less)
	return result


func _item_id_less(left: ItemInstance, right: ItemInstance) -> bool:
	return left.item_id < right.item_id
