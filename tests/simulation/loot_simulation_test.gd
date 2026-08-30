extends RefCounted


func test_names() -> PackedStringArray:
	return PackedStringArray([
		"normal_category_and_weapon_type_distribution",
		"charm_effect_selection_is_uniform_without_replacement",
		"fusion_rerolls_category_and_weapon_type",
		"fixed_seed_wave_reward_totals",
	])


func run_test(test_name: String, assertions: Variant, _context: Dictionary) -> void:
	match test_name:
		"normal_category_and_weapon_type_distribution":
			_test_loot_distribution(assertions)
		"charm_effect_selection_is_uniform_without_replacement":
			_test_affix_distribution(assertions)
		"fusion_rerolls_category_and_weapon_type":
			_test_fusion_distribution(assertions)
		"fixed_seed_wave_reward_totals":
			_test_fixed_seed_wave_reward_totals(assertions)
		_:
			assertions.expect_true(false, "registered loot simulation test")


func _test_loot_distribution(assertions: Variant) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7654321
	var categories := PackedInt32Array([0, 0])
	var weapon_types := PackedInt32Array([0, 0, 0])
	for _index: int in range(30000):
		var category: GameTypes.ItemCategory = LootService.select_category(rng)
		categories[int(category)] += 1
		var weapon_type: GameTypes.WeaponType = LootService.select_weapon_type(rng)
		weapon_types[int(weapon_type) - int(GameTypes.WeaponType.BOW)] += 1
	_assert_share(assertions, categories[0], 30000, 0.50, 0.015, "weapon category 50 percent")
	_assert_share(assertions, categories[1], 30000, 0.50, 0.015, "charm category 50 percent")
	for index: int in range(3):
		_assert_share(assertions, weapon_types[index], 30000, 1.0 / 3.0, 0.015, "weapon type uniform %d" % index)


func _test_affix_distribution(assertions: Variant) -> void:
	var catalog := DefinitionCatalog.new()
	assertions.expect_true(catalog.load_and_validate(), "affix simulation catalog valid")
	if not catalog.is_valid:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 246810
	var counts: Dictionary[StringName, int] = {}
	for affix_id: StringName in catalog.affix_ids():
		counts[affix_id] = 0
	for index: int in range(14000):
		var charm: ItemInstance = ItemFactory.create_charm(1, "uniform-%d" % index, GameTypes.Rarity.COMMON, rng, catalog)
		counts[charm.affixes[0].affix_id] += 1
	for affix_id: StringName in counts:
		_assert_share(assertions, counts[affix_id], 14000, 1.0 / 7.0, 0.012, "seven effects uniform %s" % affix_id)


func _test_fusion_distribution(assertions: Variant) -> void:
	var catalog := DefinitionCatalog.new()
	assertions.expect_true(catalog.load_and_validate(), "fusion simulation catalog valid")
	if not catalog.is_valid:
		return
	var materials: Array[ItemInstance] = []
	for index: int in range(3):
		materials.append(QaItemBuilder.weapon(catalog, "material-%d" % index, GameTypes.WeaponType.BOW))
	var rng := RandomNumberGenerator.new()
	rng.seed = 112233
	var categories := PackedInt32Array([0, 0])
	var weapon_types := PackedInt32Array([0, 0, 0])
	var weapon_outputs: int = 0
	var all_succeeded: bool = true
	for index: int in range(15000):
		var result: Dictionary = FusionService.fuse(materials, [], 1, 1, index, rng, catalog)
		if not bool(result["success"]):
			all_succeeded = false
			continue
		var output: ItemInstance = result["output"] as ItemInstance
		categories[int(output.category)] += 1
		if output.category == GameTypes.ItemCategory.WEAPON:
			weapon_outputs += 1
			weapon_types[int(output.weapon_type) - int(GameTypes.WeaponType.BOW)] += 1
	assertions.expect_true(all_succeeded, "all fusion distribution samples succeed")
	_assert_share(assertions, categories[0], 15000, 0.50, 0.018, "fusion weapon 50 percent")
	_assert_share(assertions, categories[1], 15000, 0.50, 0.018, "fusion charm 50 percent")
	for index: int in range(3):
		_assert_share(assertions, weapon_types[index], weapon_outputs, 1.0 / 3.0, 0.025, "fusion weapon type uniform %d" % index)


func _test_fixed_seed_wave_reward_totals(assertions: Variant) -> void:
	var catalog := DefinitionCatalog.new()
	assertions.expect_true(catalog.load_and_validate(), "fixed-total catalog valid")
	if not catalog.is_valid:
		return
	var state: RunState = RunStateFactory.create(20260830, catalog.wave(1))
	var totals := PackedInt32Array()
	for wave_number: int in range(1, 9):
		var wave: WaveDefinition = catalog.wave(wave_number)
		state.wave_number = wave_number
		state.wave_chests = 0
		state.unopened_rewards.clear()
		var service := LootService.new()
		service.initialize(state, catalog)
		for event_tick: int in range(1, ceili(float(wave.kill_quota) * 1.5) + 1):
			service.try_normal_drop(Vector2.ZERO, event_tick)
		if wave_number == 4:
			service.acquire_elite_chests(Vector2.ZERO, 10_000 + wave_number)
		elif wave_number == 8:
			service.acquire_boss_chests(Vector2.ZERO, 10_000 + wave_number)
		service.ensure_reward_fallback(Vector2.ZERO, 20_000 + wave_number)
		totals.append(state.wave_chests)
	assertions.expect_equal(
		PackedInt32Array([23, 20, 23, 23, 19, 20, 26, 24]),
		totals,
		"fixed seed preserves the accepted per-wave reward totals",
	)


func _assert_share(
	assertions: Variant,
	count: int,
	total: int,
	expected: float,
	tolerance: float,
	label: String,
) -> void:
	var share: float = float(count) / float(total)
	assertions.expect_true(absf(share - expected) <= tolerance, "%s actual=%.5f" % [label, share])
