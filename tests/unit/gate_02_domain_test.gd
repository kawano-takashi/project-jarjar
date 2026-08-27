extends RefCounted


const CatalogScript := preload("res://src/core/definition_catalog.gd")
const FusionServiceScript := preload("res://src/inventory/fusion_service.gd")
const ItemFactoryScript := preload("res://src/loot/item_factory.gd")
const NameGeneratorScript := preload("res://src/loot/name_generator.gd")
const RunStateFactoryScript := preload("res://src/core/run_state_factory.gd")
const RunStateMachineScript := preload("res://src/core/run_state_machine.gd")
const ScoreServiceScript := preload("res://src/core/score_service.gd")
const SeedServiceScript := preload("res://src/core/seed_service.gd")
const StatCalculatorScript := preload("res://src/combat/stat_calculator.gd")
const TimerMathScript := preload("res://src/core/timer_math.gd")
const WeightedSelectorScript := preload("res://src/core/weighted_selector.gd")

var _catalog: CatalogScript = null


func test_names() -> PackedStringArray:
	return PackedStringArray([
		"game_types_test",
		"seed_service_test",
		"rng_isolation_test",
		"item_factory_test",
		"name_generator_test",
		"weighted_selector_boundary_test",
		"affix_pool_test",
		"affinity_weight_test",
		"fusion_service_test",
		"phase_test",
		"score_test",
		"stat_calculator_test",
		"timer_math_test",
	])


func run_test(test_name: String, assertions: Variant, _context: Dictionary) -> void:
	match test_name:
		"game_types_test":
			_game_types_test(assertions)
		"seed_service_test":
			_seed_service_test(assertions)
		"rng_isolation_test":
			_rng_isolation_test(assertions)
		"item_factory_test":
			_item_factory_test(assertions)
		"name_generator_test":
			_name_generator_test(assertions)
		"weighted_selector_boundary_test":
			_weighted_selector_boundary_test(assertions)
		"affix_pool_test":
			_affix_pool_test(assertions)
		"affinity_weight_test":
			_affinity_weight_test(assertions)
		"fusion_service_test":
			_fusion_service_test(assertions)
		"phase_test":
			_phase_test(assertions)
		"score_test":
			_score_test(assertions)
		"stat_calculator_test":
			_stat_calculator_test(assertions)
		"timer_math_test":
			_timer_math_test(assertions)
		_:
			assertions.expect_true(false, "registered Gate 2 test name")


func _game_types_test(assertions: Variant) -> void:
	assertions.expect_equal([0, 1, 2, 3, 4, 5], GameTypes.EquipmentSlot.values(), "EquipmentSlot values")
	assertions.expect_equal([0, 1, 2, 3], GameTypes.MainWeaponType.values(), "MainWeaponType values")
	assertions.expect_equal([0, 1, 2, 3], GameTypes.Rarity.values(), "Rarity values")
	assertions.expect_equal([0, 1, 2, 3], GameTypes.TriggerType.values(), "TriggerType values")
	assertions.expect_equal([0, 1, 2, 3, 4, 5, 6], GameTypes.RunPhase.values(), "RunPhase values")
	assertions.expect_equal([0, 1, 2, 3, 4, 5], GameTypes.EnemyType.values(), "EnemyType values")
	assertions.expect_equal([0, 1], GameTypes.RewardKind.values(), "RewardKind values")
	var equipment_slot_keys: Array[StringName] = [&"main_weapon", &"sub_weapon", &"head", &"body", &"hands", &"feet"]
	for equipment_slot_value: int in GameTypes.EquipmentSlot.values():
		assertions.expect_equal(
			equipment_slot_keys[equipment_slot_value],
			GameTypes.equipment_slot_to_key(equipment_slot_value as GameTypes.EquipmentSlot),
			"EquipmentSlot string %d" % equipment_slot_value
		)
	var main_weapon_type_keys: Array[StringName] = [&"unclassified", &"bow", &"staff", &"sword"]
	for main_weapon_type_value: int in GameTypes.MainWeaponType.values():
		assertions.expect_equal(
			main_weapon_type_keys[main_weapon_type_value],
			GameTypes.main_weapon_type_to_key(main_weapon_type_value as GameTypes.MainWeaponType),
			"MainWeaponType string %d" % main_weapon_type_value
		)
	var rarity_keys: Array[StringName] = [&"common", &"rare", &"epic", &"legendary"]
	for rarity_value: int in GameTypes.Rarity.values():
		assertions.expect_equal(
			rarity_keys[rarity_value],
			GameTypes.rarity_to_key(rarity_value as GameTypes.Rarity),
			"Rarity string %d" % rarity_value
		)
	var trigger_type_keys: Array[StringName] = [&"time", &"primary_attack_count", &"kill_count", &"hit_count"]
	for trigger_type_value: int in GameTypes.TriggerType.values():
		assertions.expect_equal(
			trigger_type_keys[trigger_type_value],
			GameTypes.trigger_type_to_key(trigger_type_value as GameTypes.TriggerType),
			"TriggerType string %d" % trigger_type_value
		)
	var run_phase_keys: Array[StringName] = [&"boot", &"title", &"combat", &"reward_reveal", &"inventory", &"result", &"failed"]
	for run_phase_value: int in GameTypes.RunPhase.values():
		assertions.expect_equal(
			run_phase_keys[run_phase_value],
			GameTypes.run_phase_to_key(run_phase_value as GameTypes.RunPhase),
			"RunPhase string %d" % run_phase_value
		)
	var enemy_type_keys: Array[StringName] = [&"tracker", &"fast", &"armored", &"ranged", &"elite", &"boss"]
	for enemy_type_value: int in GameTypes.EnemyType.values():
		assertions.expect_equal(
			enemy_type_keys[enemy_type_value],
			GameTypes.enemy_type_to_key(enemy_type_value as GameTypes.EnemyType),
			"EnemyType string %d" % enemy_type_value
		)
	var reward_kind_keys: Array[StringName] = [&"equipment", &"skill"]
	for reward_kind_value: int in GameTypes.RewardKind.values():
		assertions.expect_equal(
			reward_kind_keys[reward_kind_value],
			GameTypes.reward_kind_to_key(reward_kind_value as GameTypes.RewardKind),
			"RewardKind string %d" % reward_kind_value
		)

	var catalog: CatalogScript = _loaded_catalog(assertions)
	if catalog == null:
		return
	assertions.expect_equal(4, catalog.weapons.size(), "weapon definition count")
	assertions.expect_equal(6, catalog.enemies.size(), "enemy definition count")
	assertions.expect_equal(8, catalog.waves.size(), "wave definition count")
	assertions.expect_equal(4, catalog.rarities.size(), "rarity definition count")
	assertions.expect_equal(9, catalog.affixes.size(), "affix definition count")
	assertions.expect_equal(4, catalog.skills.size(), "skill definition count")
	assertions.expect_equal(6, catalog.uniques.size(), "unique definition count")
	assertions.expect_equal(0, catalog.balance_manifest().balance_revision, "balance revision")
	assertions.expect_equal(
		[&"bloodied_dagger", &"broken_clock", &"coward_boots", &"echo_gauntlet", &"hollow_crown", &"immortal_breastplate"],
		catalog.unique_ids(),
		"unique IDs ordinal",
	)
	_verify_wave_resources(assertions, catalog)
	assertions.expect_true(AffixRoll.new() is RefCounted, "AffixRoll RefCounted")
	assertions.expect_true(ItemInstance.new() is RefCounted, "ItemInstance RefCounted")
	assertions.expect_true(SkillState.new() is RefCounted, "SkillState RefCounted")
	assertions.expect_true(PendingSkillActivation.new() is RefCounted, "PendingSkillActivation RefCounted")
	assertions.expect_true(ScheduledProcReplay.new() is RefCounted, "ScheduledProcReplay RefCounted")
	assertions.expect_true(DamageSample.new() is RefCounted, "DamageSample RefCounted")
	assertions.expect_true(RewardRoll.new() is RefCounted, "RewardRoll RefCounted")
	assertions.expect_true(RunState.new() is RefCounted, "RunState RefCounted")
	assertions.expect_true(CombatEvent.new() is RefCounted, "CombatEvent RefCounted")
	assertions.expect_true(CombatSnapshot.new() is RefCounted, "CombatSnapshot RefCounted")


func _seed_service_test(assertions: Variant) -> void:
	assertions.expect_equal(
		SeedServiceScript.derive(20260827, &"combat"),
		SeedServiceScript.derive(20260827, &"combat"),
		"same derive",
	)
	var first: RunRngStreams = RunRngStreams.create(20260827)
	var second: RunRngStreams = RunRngStreams.create(20260827)
	assertions.expect_true(first.combat_rng != first.loot_rng, "combat and loot instances differ")
	assertions.expect_true(first.combat_rng != first.fusion_rng, "combat and fusion instances differ")
	assertions.expect_true(first.loot_rng != first.fusion_rng, "loot and fusion instances differ")
	var combat_values: Array[int] = _take_rng_values(first.combat_rng, 8)
	var loot_values: Array[int] = _take_rng_values(first.loot_rng, 8)
	var fusion_values: Array[int] = _take_rng_values(first.fusion_rng, 8)
	assertions.expect_equal(combat_values, _take_rng_values(second.combat_rng, 8), "combat sequence same")
	assertions.expect_equal(loot_values, _take_rng_values(second.loot_rng, 8), "loot sequence same")
	assertions.expect_equal(fusion_values, _take_rng_values(second.fusion_rng, 8), "fusion sequence same")
	assertions.expect_not_equal(combat_values, loot_values, "combat and loot sequences differ")
	assertions.expect_not_equal(combat_values, fusion_values, "combat and fusion sequences differ")
	assertions.expect_not_equal(loot_values, fusion_values, "loot and fusion sequences differ")
	assertions.expect_not_equal(first.combat_seed, first.loot_seed, "combat and loot seeds differ")
	assertions.expect_not_equal(first.combat_seed, first.fusion_seed, "combat and fusion seeds differ")
	assertions.expect_not_equal(first.loot_seed, first.fusion_seed, "loot and fusion seeds differ")


func _rng_isolation_test(assertions: Variant) -> void:
	var baseline: RunRngStreams = RunRngStreams.create(99173)
	var perturbed: RunRngStreams = RunRngStreams.create(99173)
	var item_seed: int = SeedServiceScript.derive(99173, &"item:test")
	var name_affixes: Array[AffixRoll] = [_affix(&"damage_pct", 8.0)]
	var baseline_name: String = NameGeneratorScript.generate(
		item_seed,
		GameTypes.EquipmentSlot.MAIN_WEAPON,
		GameTypes.MainWeaponType.BOW,
		name_affixes
	)
	var baseline_name_rng_values: Array[int] = NameGeneratorScript.first_rng_values(item_seed)
	for _index: int in range(10000):
		perturbed.combat_rng.randi()
	assertions.expect_equal(_take_rng_values(baseline.loot_rng, 16), _take_rng_values(perturbed.loot_rng, 16), "combat does not perturb loot")
	assertions.expect_equal(_take_rng_values(baseline.fusion_rng, 16), _take_rng_values(perturbed.fusion_rng, 16), "combat does not perturb fusion")
	assertions.expect_equal(
		baseline_name,
		NameGeneratorScript.generate(
			item_seed,
			GameTypes.EquipmentSlot.MAIN_WEAPON,
			GameTypes.MainWeaponType.BOW,
			name_affixes
		),
		"combat consumption does not perturb generated name"
	)
	assertions.expect_equal(
		baseline_name_rng_values,
		NameGeneratorScript.first_rng_values(item_seed),
		"combat consumption does not perturb name RNG",
	)


func _item_factory_test(assertions: Variant) -> void:
	var catalog: CatalogScript = _loaded_catalog(assertions)
	if catalog == null:
		return
	var run_seed: int = 20260827
	var wood: ItemInstance = ItemFactoryScript.create_initial_wood_stick(run_seed)
	assertions.expect_equal("i-00000000013527db-00-0000", wood.item_id, "wood item ID")
	assertions.expect_equal(SeedServiceScript.derive(run_seed, StringName("item:" + wood.item_id)), wood.item_seed, "wood item seed")
	assertions.expect_equal(GameTypes.Rarity.COMMON, wood.rarity, "wood rarity")
	assertions.expect_equal(0, wood.affixes.size(), "wood affix exception")
	assertions.expect_equal("木の棒", wood.display_name, "wood fixed name")
	var state: RunState = RunStateFactoryScript.create(run_seed, catalog.wave(1))
	assertions.expect_equal(1, state.drop_serial, "wood reserves serial zero")
	assertions.expect_equal(wood.item_id, (state.equipped[GameTypes.EquipmentSlot.MAIN_WEAPON] as ItemInstance).item_id, "wood initially equipped")
	assertions.expect_equal("i-00000000013527db-02-0042", ItemFactoryScript.make_item_id(run_seed, 2, 42), "item ID format")
	assertions.expect_equal("r-00000000013527db-02-0042", ItemFactoryScript.make_reward_id(run_seed, 2, 42), "reward ID format")
	for slot_value: int in GameTypes.EquipmentSlot.values():
		var slot: GameTypes.EquipmentSlot = slot_value as GameTypes.EquipmentSlot
		var slot_rng := RandomNumberGenerator.new()
		slot_rng.seed = 3000 + slot_value
		var slot_item: ItemInstance = ItemFactoryScript.create_item(
			run_seed,
			ItemFactoryScript.make_item_id(run_seed, 1, 100 + slot_value),
			slot,
			GameTypes.MainWeaponType.BOW,
			GameTypes.Rarity.COMMON,
			&"",
			GameTypes.MainWeaponType.STAFF,
			slot_rng,
			catalog
		)
		assertions.expect_equal(slot, slot_item.slot, "generated slot %d" % slot_value)
		var expected_weapon_type: GameTypes.MainWeaponType = (
			GameTypes.MainWeaponType.BOW
			if slot == GameTypes.EquipmentSlot.MAIN_WEAPON
			else GameTypes.MainWeaponType.UNCLASSIFIED
		)
		assertions.expect_equal(expected_weapon_type, slot_item.main_weapon_type, "slot weapon type %d" % slot_value)
	var weapon_types: Array[GameTypes.MainWeaponType] = [
		GameTypes.MainWeaponType.BOW,
		GameTypes.MainWeaponType.STAFF,
		GameTypes.MainWeaponType.SWORD,
	]
	for weapon_index: int in range(weapon_types.size()):
		var weapon_type: GameTypes.MainWeaponType = weapon_types[weapon_index]
		var weapon_rng := RandomNumberGenerator.new()
		weapon_rng.seed = 3500 + weapon_index
		var weapon_item: ItemInstance = ItemFactoryScript.create_item(
			run_seed,
			ItemFactoryScript.make_item_id(run_seed, 1, 120 + weapon_index),
			GameTypes.EquipmentSlot.MAIN_WEAPON,
			weapon_type,
			GameTypes.Rarity.COMMON,
			&"",
			GameTypes.MainWeaponType.BOW,
			weapon_rng,
			catalog
		)
		assertions.expect_equal(GameTypes.EquipmentSlot.MAIN_WEAPON, weapon_item.slot, "main weapon slot %d" % weapon_index)
		assertions.expect_equal(weapon_type, weapon_item.main_weapon_type, "main weapon type %d" % weapon_index)

	for rarity_value: int in GameTypes.Rarity.values():
		var rarity: GameTypes.Rarity = rarity_value as GameTypes.Rarity
		var rng := RandomNumberGenerator.new()
		rng.seed = 4000 + rarity_value
		var normal: ItemInstance = ItemFactoryScript.create_item(
			run_seed,
			ItemFactoryScript.make_item_id(run_seed, 1, 10 + rarity_value),
			GameTypes.EquipmentSlot.HANDS,
			GameTypes.MainWeaponType.SWORD,
			rarity,
			&"",
			GameTypes.MainWeaponType.BOW,
			rng,
			catalog
		)
		assertions.expect_equal(GameTypes.MainWeaponType.UNCLASSIFIED, normal.main_weapon_type, "non-main weapon type %d" % rarity_value)
		assertions.expect_equal(catalog.rarity(rarity).affix_count, normal.affixes.size(), "normal affix count %d" % rarity_value)
		assertions.expect_equal(normal.affixes.size(), _affix_id_set(normal).size(), "normal affixes unique %d" % rarity_value)
		var unique_rng := RandomNumberGenerator.new()
		unique_rng.seed = 5000 + rarity_value
		var unique: ItemInstance = ItemFactoryScript.create_item(
			run_seed,
			ItemFactoryScript.make_item_id(run_seed, 1, 20 + rarity_value),
			GameTypes.EquipmentSlot.SUB_WEAPON,
			GameTypes.MainWeaponType.UNCLASSIFIED,
			rarity,
			&"bloodied_dagger",
			GameTypes.MainWeaponType.STAFF,
			unique_rng,
			catalog
		)
		var expected_unique_count: int = floori(float(catalog.rarity(rarity).affix_count) / 2.0)
		assertions.expect_equal(expected_unique_count, unique.affixes.size(), "unique affix count %d" % rarity_value)
		assertions.expect_equal("血塗れの短剣", unique.display_name, "unique fixed name %d" % rarity_value)


func _name_generator_test(assertions: Variant) -> void:
	var one_affix: Array[AffixRoll] = [_affix(&"damage_pct", 8.0)]
	var first_name: String = NameGeneratorScript.generate(
		777,
		GameTypes.EquipmentSlot.MAIN_WEAPON,
		GameTypes.MainWeaponType.BOW,
		one_affix
	)
	assertions.expect_equal(first_name, NameGeneratorScript.generate(777, GameTypes.EquipmentSlot.MAIN_WEAPON, GameTypes.MainWeaponType.BOW, one_affix), "same item seed same name")
	var materials_found: Dictionary[String, bool] = {}
	var suffixes_found: Dictionary[String, bool] = {}
	var names_found: Dictionary[String, bool] = {}
	var materials: PackedStringArray = NameGeneratorScript.MATERIAL_WORDS
	var single_suffixes: PackedStringArray = NameGeneratorScript.SINGLE_AFFIX_SUFFIXES
	for item_seed: int in range(1000):
		var generated: String = NameGeneratorScript.generate(item_seed, GameTypes.EquipmentSlot.MAIN_WEAPON, GameTypes.MainWeaponType.BOW, one_affix)
		names_found[generated] = true
		for material: String in materials:
			if material in generated:
				materials_found[material] = true
		for suffix: String in single_suffixes:
			if "『%s』" % suffix in generated:
				suffixes_found[suffix] = true
	assertions.expect_equal(8, materials_found.size(), "all material words reached")
	assertions.expect_equal(4, suffixes_found.size(), "all one-affix suffixes reached")
	assertions.expect_true(names_found.size() >= 28 and names_found.size() <= 32, "one-affix distinct names 28..32")
	var secondary_ids: Array[StringName] = [
		&"damage_pct", &"attack_speed_pct", &"cooldown_reduction_pct", &"area_pct", &"pierce",
		&"max_hp", &"damage_reduction_pct", &"move_speed_pct", &"skill_power_pct",
	]
	for secondary_id: StringName in secondary_ids:
		var primary_id: StringName = &"attack_speed_pct" if secondary_id == &"damage_pct" else &"damage_pct"
		var affixes: Array[AffixRoll] = [_affix(primary_id, 1.0), _affix(secondary_id, 1.0)]
		var generated: String = NameGeneratorScript.generate(12345, GameTypes.EquipmentSlot.HEAD, GameTypes.MainWeaponType.UNCLASSIFIED, affixes)
		assertions.expect_true(generated.ends_with("『%s』" % NameGeneratorScript.secondary_suffix(secondary_id)), "secondary suffix %s" % secondary_id)


func _weighted_selector_boundary_test(assertions: Variant) -> void:
	var candidates: Array[StringName] = [&"common", &"rare", &"epic", &"legendary"]
	var weights := PackedFloat64Array([88.0, 11.0, 1.0, 0.0])
	assertions.expect_true(WeightedSelectorScript.validate_weights(candidates, weights), "valid weights")
	assertions.expect_equal(&"common", WeightedSelectorScript.select_with_value(candidates, weights, 0.0), "randf zero first positive")
	assertions.expect_equal(&"epic", WeightedSelectorScript.select_with_value(candidates, weights, 1.0), "randf one last positive")
	var invalid_rng := RandomNumberGenerator.new()
	invalid_rng.seed = 8080
	var before_state: int = invalid_rng.state
	assertions.expect_equal(&"", WeightedSelectorScript.select(invalid_rng, [], PackedFloat64Array()), "empty rejected")
	assertions.expect_equal(before_state, invalid_rng.state, "invalid selection consumes no RNG")
	assertions.expect_false(WeightedSelectorScript.validate_weights(candidates, PackedFloat64Array([1.0])), "length mismatch rejected")
	assertions.expect_false(WeightedSelectorScript.validate_weights([&"a"], PackedFloat64Array([-1.0])), "negative rejected")
	assertions.expect_false(WeightedSelectorScript.validate_weights([&"a"], PackedFloat64Array([0.0])), "zero total rejected")
	var legendary_count: int = 0
	for index: int in range(10000):
		var value: float = 1.0 if index % 2 == 0 else float(index % 100) / 100.0
		if WeightedSelectorScript.select_with_value(candidates, weights, value) == &"legendary":
			legendary_count += 1
	assertions.expect_equal(0, legendary_count, "zero-weight endpoint never selected")


func _affix_pool_test(assertions: Variant) -> void:
	var specific_count: int = 0
	for seed_value: int in range(10000):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		if ItemFactoryScript.choose_slot_specific_pool(rng):
			specific_count += 1
	var specific_pct: float = float(specific_count) / 100.0
	var common_pct: float = 100.0 - specific_pct
	assertions.expect_true(specific_pct >= 74.0 and specific_pct <= 76.0, "slot pool 75 percent")
	assertions.expect_true(common_pct >= 24.0 and common_pct <= 26.0, "common pool 25 percent")


func _affinity_weight_test(assertions: Variant) -> void:
	var catalog: CatalogScript = _loaded_catalog(assertions)
	if catalog == null:
		return
	var candidates: Array[StringName] = [&"attack_speed_pct", &"damage_pct"]
	var affinity_count: int = 0
	var normal_count: int = 0
	for seed_value: int in range(10000):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var selected: StringName = ItemFactoryScript.select_affix_id(candidates, GameTypes.MainWeaponType.BOW, rng, catalog)
		if selected == &"attack_speed_pct":
			affinity_count += 1
		elif selected == &"damage_pct":
			normal_count += 1
	var observed_ratio: float = float(affinity_count) / float(normal_count)
	assertions.expect_true(observed_ratio >= 1.8 and observed_ratio <= 2.2, "affinity selector ratio 1.8..2.2")


func _fusion_service_test(assertions: Variant) -> void:
	var catalog: CatalogScript = _loaded_catalog(assertions)
	if catalog == null:
		return
	assertions.expect_equal(
		[&"body", &"feet", &"hands", &"head", &"main_weapon", &"sub_weapon"],
		FusionServiceScript.SLOT_IDS,
		"fusion slot IDs ordinal"
	)
	var equipped_ids: Array[String] = []
	var common: Array[ItemInstance] = [
		_manual_item("c0", GameTypes.Rarity.COMMON),
		_manual_item("c1", GameTypes.Rarity.COMMON),
		_manual_item("c2", GameTypes.Rarity.COMMON),
	]
	var rng := RandomNumberGenerator.new()
	rng.seed = 6001
	var success: Dictionary = FusionServiceScript.fuse(common, 0, 0, equipped_ids, false, 77, 2, 5, GameTypes.MainWeaponType.BOW, rng, catalog)
	assertions.expect_true(bool(success["success"]), "three-to-one succeeds")
	assertions.expect_equal(GameTypes.Rarity.RARE, success["output_rarity"], "fusion rarity increases")
	assertions.expect_equal(6, success["next_drop_serial"], "fusion serial increments once")
	var wild_rng := RandomNumberGenerator.new()
	wild_rng.seed = 6002
	var wild_success: Dictionary = FusionServiceScript.fuse([common[0], common[1]], 1, 1, equipped_ids, false, 77, 2, 6, GameTypes.MainWeaponType.STAFF, wild_rng, catalog)
	assertions.expect_true(bool(wild_success["success"]), "two plus wild succeeds")
	assertions.expect_equal(1, wild_success["wild_consumed"], "one wild consumed")
	assertions.expect_equal(&"wild_limit", FusionServiceScript.validate_materials([common[0]], 2, 2, equipped_ids)["error"], "two wild rejected")
	assertions.expect_equal(&"wild_unavailable", FusionServiceScript.validate_materials([common[0], common[1]], 1, 0, equipped_ids)["error"], "unowned wild rejected")
	assertions.expect_equal(&"rarity_mismatch", FusionServiceScript.validate_materials([common[0], common[1], _manual_item("r0", GameTypes.Rarity.RARE)], 0, 0, equipped_ids)["error"], "rarity mismatch rejected")
	var locked: ItemInstance = _manual_item("locked", GameTypes.Rarity.COMMON)
	locked.locked = true
	assertions.expect_equal(&"locked", FusionServiceScript.validate_materials([common[0], common[1], locked], 0, 0, equipped_ids)["error"], "locked rejected")
	assertions.expect_equal(&"equipped", FusionServiceScript.validate_materials(common, 0, 0, ["c1"])["error"], "equipped rejected")
	var legendary: Array[ItemInstance] = [
		_manual_item("l0", GameTypes.Rarity.LEGENDARY),
		_manual_item("l1", GameTypes.Rarity.LEGENDARY),
		_manual_item("l2", GameTypes.Rarity.LEGENDARY),
	]
	assertions.expect_equal(&"legendary", FusionServiceScript.validate_materials(legendary, 0, 0, equipped_ids)["error"], "Legendary rejected")
	var unique_item: ItemInstance = _manual_item("u0", GameTypes.Rarity.COMMON, &"bloodied_dagger")
	unique_item.display_name = "血塗れの短剣"
	var unique_materials: Array[ItemInstance] = [unique_item, common[1], common[2]]
	var warning_rng := RandomNumberGenerator.new()
	warning_rng.seed = 7001
	var warning_state: int = warning_rng.state
	var warning: Dictionary = FusionServiceScript.fuse(unique_materials, 0, 0, equipped_ids, false, 77, 2, 7, GameTypes.MainWeaponType.SWORD, warning_rng, catalog)
	assertions.expect_false(bool(warning["success"]), "unique waits for confirmation")
	assertions.expect_true(bool(warning["needs_unique_confirmation"]), "unique warning required")
	assertions.expect_equal(warning_state, warning_rng.state, "unique warning consumes no RNG")
	assertions.expect_equal(7, warning["next_drop_serial"], "unique warning preserves serial")
	var confirmed: Dictionary = FusionServiceScript.fuse(unique_materials, 0, 0, equipped_ids, true, 77, 2, 7, GameTypes.MainWeaponType.SWORD, warning_rng, catalog)
	assertions.expect_true(bool(confirmed["success"]), "confirmed unique fusion succeeds")


func _phase_test(assertions: Variant) -> void:
	var allowed: Array[Vector2i] = [
		Vector2i(GameTypes.RunPhase.BOOT, GameTypes.RunPhase.TITLE),
		Vector2i(GameTypes.RunPhase.TITLE, GameTypes.RunPhase.COMBAT),
		Vector2i(GameTypes.RunPhase.COMBAT, GameTypes.RunPhase.REWARD_REVEAL),
		Vector2i(GameTypes.RunPhase.COMBAT, GameTypes.RunPhase.FAILED),
		Vector2i(GameTypes.RunPhase.REWARD_REVEAL, GameTypes.RunPhase.INVENTORY),
		Vector2i(GameTypes.RunPhase.INVENTORY, GameTypes.RunPhase.COMBAT),
		Vector2i(GameTypes.RunPhase.INVENTORY, GameTypes.RunPhase.RESULT),
		Vector2i(GameTypes.RunPhase.FAILED, GameTypes.RunPhase.COMBAT),
		Vector2i(GameTypes.RunPhase.FAILED, GameTypes.RunPhase.TITLE),
		Vector2i(GameTypes.RunPhase.RESULT, GameTypes.RunPhase.COMBAT),
		Vector2i(GameTypes.RunPhase.RESULT, GameTypes.RunPhase.TITLE),
	]
	for from_value: int in GameTypes.RunPhase.values():
		for to_value: int in GameTypes.RunPhase.values():
			var pair := Vector2i(from_value, to_value)
			assertions.expect_equal(
				pair in allowed,
				RunStateMachineScript.can_transition(
					from_value as GameTypes.RunPhase,
					to_value as GameTypes.RunPhase
				),
				"transition matrix %d-%d" % [from_value, to_value]
			)
	for pair: Vector2i in allowed:
		var state := RunState.new()
		state.phase = pair.x as GameTypes.RunPhase
		if pair.x == GameTypes.RunPhase.COMBAT:
			state.wave_cleared = pair.y == GameTypes.RunPhase.REWARD_REVEAL
		if pair.x == GameTypes.RunPhase.INVENTORY:
			state.wave_number = 8 if pair.y == GameTypes.RunPhase.RESULT else 7
			state.equipped[GameTypes.EquipmentSlot.MAIN_WEAPON] = _manual_item("phase-main", GameTypes.Rarity.COMMON)
		assertions.expect_true(
			RunStateMachineScript.transition(state, pair.y as GameTypes.RunPhase),
			"actual transition %s" % pair
		)
		assertions.expect_equal(pair.y, state.phase, "actual phase %s" % pair)
	var gated_inventory := RunState.new()
	gated_inventory.phase = GameTypes.RunPhase.INVENTORY
	gated_inventory.wave_number = 7
	assertions.expect_false(RunStateMachineScript.can_transition_state(gated_inventory, GameTypes.RunPhase.COMBAT), "main weapon required")
	gated_inventory.equipped[GameTypes.EquipmentSlot.MAIN_WEAPON] = _manual_item("phase-main", GameTypes.Rarity.COMMON)
	gated_inventory.overflow.append(_manual_item("phase-overflow", GameTypes.Rarity.COMMON))
	assertions.expect_false(RunStateMachineScript.can_transition_state(gated_inventory, GameTypes.RunPhase.COMBAT), "overflow must be empty")
	gated_inventory.overflow.clear()
	assertions.expect_true(RunStateMachineScript.can_transition_state(gated_inventory, GameTypes.RunPhase.COMBAT), "valid W1-W7 inventory exit")
	assertions.expect_false(RunStateMachineScript.can_transition_state(gated_inventory, GameTypes.RunPhase.RESULT), "W1-W7 cannot result")
	gated_inventory.wave_number = 8
	assertions.expect_true(RunStateMachineScript.can_transition_state(gated_inventory, GameTypes.RunPhase.RESULT), "valid W8 inventory exit")
	assertions.expect_false(RunStateMachineScript.can_transition_state(gated_inventory, GameTypes.RunPhase.COMBAT), "W8 cannot continue combat")
	var catalog: CatalogScript = _loaded_catalog(assertions)
	if catalog == null:
		return
	var quota_death: RunState = _combat_state(1, 40, false, 30.0)
	RunStateMachineScript.resolve_combat_tick(quota_death, catalog.wave(1), true, 1.0 / 60.0)
	assertions.expect_true(quota_death.wave_cleared, "quota latched before death")
	assertions.expect_equal(GameTypes.RunPhase.REWARD_REVEAL, quota_death.phase, "quota/death same tick succeeds")
	var quota_timeout: RunState = _combat_state(1, 40, false, 1.0 / 60.0)
	RunStateMachineScript.resolve_combat_tick(quota_timeout, catalog.wave(1), false, 1.0 / 60.0)
	assertions.expect_equal(GameTypes.RunPhase.REWARD_REVEAL, quota_timeout.phase, "quota/timeout same tick succeeds")
	var pre_quota: RunState = _combat_state(1, 39, false, 1.0 / 60.0)
	RunStateMachineScript.resolve_combat_tick(pre_quota, catalog.wave(1), false, 1.0 / 60.0)
	assertions.expect_equal(GameTypes.RunPhase.FAILED, pre_quota.phase, "pre-quota timeout fails")
	_verify_w8_case(assertions, catalog, 300, false, false)
	_verify_w8_case(assertions, catalog, 299, true, false)
	_verify_w8_case(assertions, catalog, 300, true, true)


func _score_test(assertions: Variant) -> void:
	var catalog: CatalogScript = _loaded_catalog(assertions)
	if catalog == null:
		return
	var held: Array[ItemInstance] = [
		_manual_item("score-common", GameTypes.Rarity.COMMON),
		_manual_item("score-rare", GameTypes.Rarity.RARE, &"bloodied_dagger"),
		_manual_item("score-epic", GameTypes.Rarity.EPIC),
		_manual_item("score-legendary", GameTypes.Rarity.LEGENDARY),
	]
	var starfall := SkillState.new()
	starfall.skill_id = &"starfall"
	starfall.level = 3
	var blades := SkillState.new()
	blades.skill_id = &"thousand_blades"
	blades.level = 2
	var skills: Dictionary[StringName, SkillState] = {
		&"starfall": starfall,
		&"thousand_blades": blades,
	}
	var breakdown: Dictionary = ScoreServiceScript.calculate(100, 1, 1, 20, 8, true, held, skills, 2, catalog.score_definition())
	assertions.expect_equal(9000, breakdown[&"combat_score"], "fixed combat score")
	assertions.expect_equal(3055, breakdown[&"final_build_score"], "fixed build score")
	assertions.expect_equal(12055, breakdown[&"total"], "fixed total 12,055")


func _stat_calculator_test(assertions: Variant) -> void:
	var body: ItemInstance = _manual_item("body", GameTypes.Rarity.COMMON, &"immortal_breastplate")
	body.slot = GameTypes.EquipmentSlot.BODY
	var head: ItemInstance = _manual_item("head", GameTypes.Rarity.LEGENDARY)
	head.slot = GameTypes.EquipmentSlot.HEAD
	head.affixes = [_affix(&"damage_reduction_pct", 25.0)]
	var hands: ItemInstance = _manual_item("hands", GameTypes.Rarity.LEGENDARY)
	hands.slot = GameTypes.EquipmentSlot.HANDS
	hands.affixes = [_affix(&"damage_reduction_pct", 25.0)]
	var equipped: Dictionary = {
		GameTypes.EquipmentSlot.BODY: body,
		GameTypes.EquipmentSlot.HEAD: head,
		GameTypes.EquipmentSlot.HANDS: hands,
	}
	var reduction: float = StatCalculatorScript.effective_damage_reduction_pct(equipped)
	assertions.expect_float(100.0, reduction, "immortal reaches 100 percent")
	assertions.expect_float(0.0, StatCalculatorScript.apply_incoming_damage(999.0, reduction), "100 percent reduction zero damage")
	var extreme_stats: Dictionary = {
		&"attack_speed_pct": 100000.0,
		&"cooldown_reduction_pct": 100.0,
	}
	assertions.expect_float(0.05, StatCalculatorScript.effective_attack_interval(0.75, GameTypes.MainWeaponType.BOW, extreme_stats), "attack lower bound")
	assertions.expect_float(0.25, StatCalculatorScript.effective_time_skill_interval(6.0, extreme_stats, [&"broken_clock"]), "skill lower bound")
	var ordered_stats: Dictionary = {&"damage_pct": 40.0, &"skill_power_pct": 50.0}
	assertions.expect_float(0.35, StatCalculatorScript.damage_multiplier(ordered_stats, [&"immortal_breastplate", &"bloodied_dagger"]), "unique multipliers after affix sum")
	assertions.expect_float(0.2625, StatCalculatorScript.damage_multiplier(ordered_stats, [&"immortal_breastplate", &"bloodied_dagger", &"broken_clock"], true), "skill multiplier order")


func _timer_math_test(assertions: Variant) -> void:
	var intervals := PackedFloat64Array([0.05, 0.25, 0.75, 0.80, 0.90, 1.20, 1.50, 1.80, 3.0, 4.0, 6.0, 60.0])
	var ticks := PackedInt32Array([3, 15, 45, 48, 54, 72, 90, 108, 180, 240, 360, 3600])
	for interval_index: int in range(intervals.size()):
		var elapsed: float = 0.0
		var early: bool = false
		for _tick: int in range(ticks[interval_index] - 1):
			elapsed = TimerMathScript.advance_clamped(elapsed, intervals[interval_index], 1.0 / 60.0)
			if TimerMathScript.is_ready(elapsed, intervals[interval_index]):
				early = true
		assertions.expect_false(early, "timer not early %.2f" % intervals[interval_index])
		elapsed = TimerMathScript.advance_clamped(elapsed, intervals[interval_index], 1.0 / 60.0)
		assertions.expect_true(TimerMathScript.is_ready(elapsed, intervals[interval_index]), "timer ready at tick %.2f" % intervals[interval_index])
		assertions.expect_float(intervals[interval_index], elapsed, "timer clamped exact %.2f" % intervals[interval_index])
	var remaining: float = 60.0
	for _tick: int in range(3600):
		remaining = TimerMathScript.countdown(remaining, 1.0 / 60.0)
	assertions.expect_float(0.0, remaining, "60-second countdown exact zero")
	var normal_accumulator: float = 0.0
	var normal_events: int = 0
	var fast_accumulator: float = 0.0
	var fast_events: int = 0
	for _tick: int in range(21):
		var normal: Dictionary = TimerMathScript.consume_repeating(normal_accumulator, 0.35, 1.0 / 60.0)
		normal_accumulator = float(normal["accumulator"])
		normal_events += int(normal["events"])
		var fast: Dictionary = TimerMathScript.consume_repeating(fast_accumulator, 0.0875, 1.0 / 60.0)
		fast_accumulator = float(fast["accumulator"])
		fast_events += int(fast["events"])
	assertions.expect_equal(1, normal_events, "normal repeating 21 ticks")
	assertions.expect_float(0.0, normal_accumulator, "normal repeating no remainder")
	assertions.expect_equal(4, fast_events, "fast repeating 21 ticks")
	assertions.expect_float(0.0, fast_accumulator, "fast repeating no remainder")
	var capped: Dictionary = TimerMathScript.consume_repeating(0.0, 0.0875, 2.0)
	assertions.expect_equal(16, capped["events"], "repeating max 16")
	assertions.expect_float(0.6, float(capped["accumulator"]), "repeating preserves excess")


func _loaded_catalog(assertions: Variant) -> CatalogScript:
	if _catalog == null:
		_catalog = CatalogScript.new()
		var valid: bool = _catalog.load_and_validate()
		assertions.expect_true(valid, "DefinitionCatalog valid: %s" % _catalog.error_text)
	return _catalog if _catalog.is_valid else null


func _verify_wave_resources(assertions: Variant, catalog: CatalogScript) -> void:
	var quotas := PackedInt32Array([40, 60, 85, 115, 150, 190, 240, 300])
	var hp := PackedFloat64Array([1.0, 1.15, 1.35, 1.60, 1.90, 2.25, 2.65, 3.10])
	var damage := PackedFloat64Array([1.0, 1.10, 1.20, 1.35, 1.50, 1.70, 1.90, 2.20])
	var spawn_start := PackedFloat64Array([1.4, 2.0, 2.7, 3.6, 4.5, 5.6, 7.0, 9.0])
	var spawn_end := PackedFloat64Array([2.0, 2.8, 3.8, 5.0, 6.0, 7.4, 9.2, 12.0])
	var chest := PackedFloat64Array([0.30, 0.22, 0.16, 0.10, 0.09, 0.075, 0.06, 0.03])
	for wave_number: int in range(1, 9):
		var wave: WaveDefinition = catalog.wave(wave_number)
		assertions.expect_true(wave != null, "wave %d exists" % wave_number)
		if wave == null:
			continue
		var index: int = wave_number - 1
		assertions.expect_float(60.0, wave.duration_seconds, "wave %d duration" % wave_number)
		assertions.expect_equal(quotas[index], wave.kill_quota, "wave %d quota" % wave_number)
		assertions.expect_float(hp[index], wave.hp_multiplier, "wave %d HP" % wave_number)
		assertions.expect_float(damage[index], wave.damage_multiplier, "wave %d damage" % wave_number)
		assertions.expect_float(spawn_start[index], wave.spawn_rate_start, "wave %d spawn start" % wave_number)
		assertions.expect_float(spawn_end[index], wave.spawn_rate_end, "wave %d spawn end" % wave_number)
		assertions.expect_float(chest[index], wave.normal_chest_rate, "wave %d chest" % wave_number)
		assertions.expect_float(30.0 if wave_number == 4 else -1.0, wave.elite_spawn_elapsed, "wave %d elite elapsed" % wave_number)
		assertions.expect_equal(wave_number == 8, wave.boss_at_start, "wave %d boss flag" % wave_number)
		var enemy_weight_total: float = 0.0
		for weight_value: Variant in wave.enemy_weights.values():
			enemy_weight_total += float(weight_value)
		assertions.expect_float(1.0, enemy_weight_total, "wave %d enemy weight total" % wave_number)
		var rarity_weight_total: float = 0.0
		for weight_value: Variant in wave.rarity_weights.values():
			rarity_weight_total += float(weight_value)
		assertions.expect_float(1.0, rarity_weight_total, "wave %d rarity weight total" % wave_number)


func _verify_w8_case(
	assertions: Variant,
	catalog: CatalogScript,
	wave_kills: int,
	boss_defeated: bool,
	expected_success: bool
) -> void:
	var state: RunState = _combat_state(8, wave_kills, boss_defeated, 1.0 / 60.0)
	RunStateMachineScript.resolve_combat_tick(state, catalog.wave(8), false, 1.0 / 60.0)
	assertions.expect_equal(expected_success, state.wave_cleared, "W8 cleared kills=%d boss=%s" % [wave_kills, boss_defeated])
	assertions.expect_equal(GameTypes.RunPhase.REWARD_REVEAL if expected_success else GameTypes.RunPhase.FAILED, state.phase, "W8 phase kills=%d boss=%s" % [wave_kills, boss_defeated])


func _combat_state(wave_number: int, kills: int, boss_defeated: bool, remaining: float) -> RunState:
	var state := RunState.new()
	state.phase = GameTypes.RunPhase.COMBAT
	state.wave_number = wave_number
	state.wave_kills = kills
	state.boss_defeated = boss_defeated
	state.time_remaining = remaining
	return state


func _take_rng_values(rng: RandomNumberGenerator, count: int) -> Array[int]:
	var values: Array[int] = []
	for _index: int in range(count):
		values.append(rng.randi())
	return values


func _affix(affix_id: StringName, value: float) -> AffixRoll:
	var roll := AffixRoll.new()
	roll.affix_id = affix_id
	roll.value = value
	return roll


func _affix_id_set(item: ItemInstance) -> Dictionary[StringName, bool]:
	var result: Dictionary[StringName, bool] = {}
	for affix: AffixRoll in item.affixes:
		result[affix.affix_id] = true
	return result


func _manual_item(
	item_id: String,
	rarity: GameTypes.Rarity,
	unique_id: StringName = &""
) -> ItemInstance:
	var item := ItemInstance.new()
	item.item_id = item_id
	item.rarity = rarity
	item.slot = GameTypes.EquipmentSlot.HANDS
	item.main_weapon_type = GameTypes.MainWeaponType.UNCLASSIFIED
	item.unique_id = unique_id
	item.display_name = item_id
	return item
