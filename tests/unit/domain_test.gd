extends RefCounted


func test_names() -> PackedStringArray:
	return PackedStringArray([
		"catalog_weapon_charm_contract",
		"item_invariants_and_fixed_charm_effects",
		"charm_addition_and_safety_caps",
		"score_uses_equipped_six_only",
	])


func run_test(test_name: String, assertions: Variant, _context: Dictionary) -> void:
	match test_name:
		"catalog_weapon_charm_contract":
			_test_catalog(assertions)
		"item_invariants_and_fixed_charm_effects":
			_test_items(assertions)
		"charm_addition_and_safety_caps":
			_test_stats(assertions)
		"score_uses_equipped_six_only":
			_test_score(assertions)
		_:
			assertions.expect_true(false, "registered domain test")


func _test_catalog(assertions: Variant) -> void:
	var catalog := _catalog(assertions)
	if not catalog.is_valid:
		return
	assertions.expect_equal(4, GameTypes.Rarity.size(), "four rarities only")
	assertions.expect_equal(2, GameTypes.ItemCategory.size(), "weapon and charm categories only")
	assertions.expect_equal(6, GameTypes.EquipmentSlot.size(), "six equal equipment slots")
	var expected_damage: Dictionary = {
		GameTypes.WeaponType.WOOD_STICK: PackedFloat32Array([10, 10, 10, 10]),
		GameTypes.WeaponType.BOW: PackedFloat32Array([12, 18, 27, 41]),
		GameTypes.WeaponType.STAFF: PackedFloat32Array([18, 27, 41, 61]),
		GameTypes.WeaponType.SWORD: PackedFloat32Array([14, 21, 32, 48]),
	}
	var expected_specs: Dictionary = {
		GameTypes.WeaponType.WOOD_STICK: {"interval": 0.8, "range": 1.8, "aoe": 0.0, "arc": 0.0},
		GameTypes.WeaponType.BOW: {"interval": 0.75, "range": 14.0, "aoe": 0.0, "arc": 0.0},
		GameTypes.WeaponType.STAFF: {"interval": 1.5, "range": 13.0, "aoe": 2.25, "arc": 0.0},
		GameTypes.WeaponType.SWORD: {"interval": 0.9, "range": 2.4, "aoe": 0.0, "arc": 120.0},
	}
	for weapon_type: GameTypes.WeaponType in expected_damage:
		var definition: WeaponDefinition = catalog.weapon_for_type(weapon_type)
		assertions.expect_true(definition != null, "weapon definition %s exists" % weapon_type)
		if definition != null:
			assertions.expect_equal(expected_damage[weapon_type], definition.damage_by_rarity, "weapon tier values %s" % weapon_type)
			var spec: Dictionary = expected_specs[weapon_type]
			assertions.expect_float(float(spec["interval"]), definition.base_interval, "fixed interval %s" % weapon_type)
			assertions.expect_float(float(spec["range"]), definition.range_m, "fixed range %s" % weapon_type)
			assertions.expect_float(float(spec["aoe"]), definition.aoe_radius, "fixed area %s" % weapon_type)
			assertions.expect_float(float(spec["arc"]), definition.arc_degrees, "fixed fan %s" % weapon_type)
	assertions.expect_false(catalog.weapon_for_type(GameTypes.WeaponType.WOOD_STICK).lootable, "wood stick is starter-only")
	assertions.expect_equal(7, catalog.affix_ids().size(), "exactly seven charm effects")
	var expected_affixes: Dictionary = {
		&"damage_pct": PackedFloat32Array([8, 14, 24, 40]),
		&"attack_speed_pct": PackedFloat32Array([8, 14, 24, 40]),
		&"area_pct": PackedFloat32Array([10, 18, 30, 48]),
		&"pierce": PackedFloat32Array([1, 1, 2, 3]),
		&"max_hp": PackedFloat32Array([10, 18, 30, 50]),
		&"damage_reduction_pct": PackedFloat32Array([5, 9, 15, 25]),
		&"move_speed_pct": PackedFloat32Array([6, 10, 16, 25]),
	}
	for affix_id: StringName in expected_affixes:
		assertions.expect_equal(expected_affixes[affix_id], catalog.affix(affix_id).values_by_rarity, "fixed charm values %s" % affix_id)
	assertions.expect_equal(3, catalog.balance_manifest().balance_revision, "balance revision invalidates prior QA")


func _test_items(assertions: Variant) -> void:
	var catalog := _catalog(assertions)
	if not catalog.is_valid:
		return
	var weapon: ItemInstance = ItemFactory.create_weapon(
		123,
		"weapon-test",
		GameTypes.WeaponType.BOW,
		GameTypes.Rarity.EPIC,
		catalog,
	)
	assertions.expect_equal(GameTypes.ItemCategory.WEAPON, weapon.category, "weapon category invariant")
	assertions.expect_equal(0, weapon.affixes.size(), "weapon has no random effects")
	assertions.expect_equal(GameTypes.WeaponType.BOW, weapon.weapon_type, "weapon type is explicit")
	for rarity_value: int in GameTypes.Rarity.values():
		var rarity := rarity_value as GameTypes.Rarity
		var rng := RandomNumberGenerator.new()
		rng.seed = 9000 + rarity_value
		var charm: ItemInstance = ItemFactory.create_charm(123, "charm-%d" % rarity_value, rarity, rng, catalog)
		assertions.expect_equal(GameTypes.ItemCategory.CHARM, charm.category, "charm category %d" % rarity_value)
		assertions.expect_equal(GameTypes.WeaponType.NONE, charm.weapon_type, "charm has no weapon type %d" % rarity_value)
		assertions.expect_equal(rarity_value + 1, charm.affixes.size(), "rarity controls distinct effect count %d" % rarity_value)
		var seen: Dictionary[StringName, bool] = {}
		for affix: AffixRoll in charm.affixes:
			assertions.expect_false(seen.has(affix.affix_id), "no duplicate charm effect %d" % rarity_value)
			seen[affix.affix_id] = true
			assertions.expect_float(catalog.affix(affix.affix_id).values_by_rarity[rarity_value], affix.value, "fixed charm value %s" % affix.affix_id)


func _test_stats(assertions: Variant) -> void:
	var equipped: Dictionary = {}
	for slot_value: int in GameTypes.EquipmentSlot.values():
		equipped[slot_value] = null
	for index: int in range(3):
		var charm := ItemInstance.new()
		charm.item_id = "manual-charm-%d" % index
		charm.category = GameTypes.ItemCategory.CHARM
		charm.weapon_type = GameTypes.WeaponType.NONE
		var damage := AffixRoll.new()
		damage.affix_id = &"damage_pct"
		damage.value = 40.0
		var reduction := AffixRoll.new()
		reduction.affix_id = &"damage_reduction_pct"
		reduction.value = 50.0
		var attack_speed := AffixRoll.new()
		attack_speed.affix_id = &"attack_speed_pct"
		attack_speed.value = 40.0
		var area := AffixRoll.new()
		area.affix_id = &"area_pct"
		area.value = 48.0
		var pierce := AffixRoll.new()
		pierce.affix_id = &"pierce"
		pierce.value = 3.0
		var max_hp := AffixRoll.new()
		max_hp.affix_id = &"max_hp"
		max_hp.value = 50.0
		var move_speed := AffixRoll.new()
		move_speed.affix_id = &"move_speed_pct"
		move_speed.value = 25.0
		charm.affixes = [damage, reduction, attack_speed, area, pierce, max_hp, move_speed]
		equipped[GameTypes.charm_slots()[index]] = charm
	var totals: Dictionary = StatCalculator.aggregate_affixes(equipped)
	assertions.expect_float(120.0, float(totals[&"damage_pct"]), "three charms add globally")
	assertions.expect_float(2.2, StatCalculator.damage_multiplier(totals), "damage bonus adds across charms")
	assertions.expect_float(0.8 / 2.2, StatCalculator.effective_attack_interval(0.8, totals), "attack speed adds across charms")
	assertions.expect_float(2.44, StatCalculator.effective_area_multiplier(totals), "area adds across charms")
	assertions.expect_equal(9, StatCalculator.effective_pierce(totals), "pierce adds across charms")
	assertions.expect_float(250.0, StatCalculator.effective_max_hp(totals), "maximum HP adds across charms")
	assertions.expect_float(8.75, StatCalculator.effective_move_speed(totals), "movement speed adds across charms")
	assertions.expect_float(100.0, StatCalculator.effective_damage_reduction_pct(equipped), "damage reduction clamps to 100 percent")
	assertions.expect_float(0.0, StatCalculator.apply_incoming_damage(50.0, 150.0), "incoming damage uses safety cap")
	assertions.expect_float(0.05, StatCalculator.effective_attack_interval(0.8, {&"attack_speed_pct": 100000.0}), "attack interval keeps 0.05 second floor")


func _test_score(assertions: Variant) -> void:
	var catalog := _catalog(assertions)
	if not catalog.is_valid:
		return
	var equipped: Array[ItemInstance] = []
	for rarity_value: int in [0, 1, 2, 3, 3, 0]:
		var item := ItemInstance.new()
		item.rarity = rarity_value as GameTypes.Rarity
		equipped.append(item)
	var score: Dictionary = ScoreService.calculate(1, 1, 1, 1, 1, true, equipped, catalog.score_definition())
	var expected_equipment: int = 30 + 105 + 360 + 1260 + 1260 + 30
	assertions.expect_equal(expected_equipment, int(score[&"equipment"]), "only supplied equipped six score")
	assertions.expect_equal(expected_equipment, int(score[&"final_build_score"]), "final build has no legacy score rows")
	assertions.expect_equal(int(score[&"combat_score"]) + expected_equipment, int(score[&"total"]), "combat coefficients remain additive")


func _catalog(assertions: Variant) -> DefinitionCatalog:
	var catalog := DefinitionCatalog.new()
	assertions.expect_true(catalog.load_and_validate(), "catalog valid: %s" % catalog.error_text)
	return catalog
