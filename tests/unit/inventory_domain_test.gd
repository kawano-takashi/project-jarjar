extends RefCounted


func test_names() -> PackedStringArray:
	return PackedStringArray([
		"three_weapon_three_charm_moves_and_minimum_weapon",
		"fusion_three_any_category_and_protection",
		"auto_material_selection_uses_visible_storage_order",
	])


func run_test(test_name: String, assertions: Variant, _context: Dictionary) -> void:
	match test_name:
		"three_weapon_three_charm_moves_and_minimum_weapon":
			_test_moves(assertions)
		"fusion_three_any_category_and_protection":
			_test_fusion(assertions)
		"auto_material_selection_uses_visible_storage_order":
			_test_auto_selection(assertions)
		_:
			assertions.expect_true(false, "registered inventory domain test")


func _test_moves(assertions: Variant) -> void:
	var setup: Dictionary = _setup(assertions)
	var catalog: DefinitionCatalog = setup["catalog"]
	var state: RunState = setup["state"]
	if not catalog.is_valid:
		return
	var bow_a: ItemInstance = QaItemBuilder.weapon(catalog, "bow-a", GameTypes.WeaponType.BOW)
	var bow_b: ItemInstance = QaItemBuilder.weapon(catalog, "bow-b", GameTypes.WeaponType.BOW)
	state.inventory[0] = bow_a
	state.inventory[1] = bow_b
	var first_move: Dictionary = InventoryService.apply_move(state, &"inventory", 0, &"equipped", GameTypes.EquipmentSlot.WEAPON_2)
	var second_move: Dictionary = InventoryService.apply_move(state, &"inventory", 1, &"equipped", GameTypes.EquipmentSlot.WEAPON_3)
	assertions.expect_true(first_move["success"], "weapon equips into weapon slot 2")
	assertions.expect_true(second_move["success"], "duplicate weapon type equips into weapon slot 3")
	assertions.expect_equal(3, InventoryService.equipped_weapon_count(state), "all three weapon slots active")
	var incompatible: Dictionary = InventoryService.validate_move(state, &"equipped", GameTypes.EquipmentSlot.WEAPON_2, &"equipped", GameTypes.EquipmentSlot.CHARM_1)
	assertions.expect_false(incompatible["success"], "weapon cannot enter charm slot")
	assertions.expect_true(InventoryService.unequip(state, GameTypes.EquipmentSlot.WEAPON_1)["success"], "wood stick may move after another weapon exists")
	assertions.expect_equal(2, InventoryService.equipped_weapon_count(state), "wood stick moved to storage")
	assertions.expect_true(InventoryService.unequip(state, GameTypes.EquipmentSlot.WEAPON_2)["success"], "second weapon may unequip")
	var last_weapon: Dictionary = InventoryService.unequip(state, GameTypes.EquipmentSlot.WEAPON_3)
	assertions.expect_false(last_weapon["success"], "last equipped weapon is protected")


func _test_fusion(assertions: Variant) -> void:
	var setup: Dictionary = _setup(assertions)
	var catalog: DefinitionCatalog = setup["catalog"]
	var state: RunState = setup["state"]
	if not catalog.is_valid:
		return
	var bow: ItemInstance = QaItemBuilder.weapon(catalog, "fusion-bow", GameTypes.WeaponType.BOW)
	state.equipped[GameTypes.EquipmentSlot.WEAPON_2] = bow
	assertions.expect_true(InventoryService.unequip(state, GameTypes.EquipmentSlot.WEAPON_1)["success"], "wood stick becomes a storage item")
	var ids: Array[StringName] = catalog.affix_ids()
	var charm_a: ItemInstance = QaItemBuilder.charm(catalog, "fusion-charm-a", GameTypes.Rarity.COMMON, [ids[0]])
	var charm_b: ItemInstance = QaItemBuilder.charm(catalog, "fusion-charm-b", GameTypes.Rarity.COMMON, [ids[1]])
	state.inventory[1] = charm_a
	state.inventory[2] = charm_b
	var wood: ItemInstance = state.inventory[0]
	var mixed: Array[ItemInstance] = [wood, charm_a, charm_b]
	assertions.expect_true(FusionService.validate_materials(mixed, InventoryService.equipped_item_ids(state))["valid"], "weapon and charms may be mixed as same-rarity materials")
	var preview: Dictionary = FusionCommitService.preview(state, PackedStringArray([wood.item_id, charm_a.item_id, charm_b.item_id]))
	assertions.expect_true(preview["success"], "wood stick is valid fusion material once unequipped")
	var commit: Dictionary = FusionCommitService.commit(state, preview["material_ids"], catalog)
	assertions.expect_true(commit["success"], "mixed fusion commits")
	var output: ItemInstance = commit.get("output") as ItemInstance
	assertions.expect_equal(GameTypes.Rarity.RARE, output.rarity, "fusion promotes exactly one rarity")
	assertions.expect_true(output.category in GameTypes.ItemCategory.values(), "fusion rerolls output category")

	var locked: ItemInstance = QaItemBuilder.weapon(catalog, "locked", GameTypes.WeaponType.SWORD)
	locked.locked = true
	assertions.expect_equal(&"locked", FusionService.validate_materials([locked, charm_a, charm_b], [])["error"], "locked item rejected")
	var legendary: Array[ItemInstance] = []
	for index: int in range(3):
		legendary.append(QaItemBuilder.weapon(catalog, "legendary-%d" % index, GameTypes.WeaponType.BOW, GameTypes.Rarity.LEGENDARY))
	assertions.expect_equal(&"legendary", FusionService.validate_materials(legendary, [])["error"], "legendary fusion rejected")
	assertions.expect_equal(&"equipped", FusionService.validate_materials([bow, locked, charm_a], [bow.item_id])["error"], "equipped protection is enforced before mutation")


func _test_auto_selection(assertions: Variant) -> void:
	var setup: Dictionary = _setup(assertions)
	var catalog: DefinitionCatalog = setup["catalog"]
	var state: RunState = setup["state"]
	if not catalog.is_valid:
		return
	var ids: Array[StringName] = catalog.affix_ids()
	state.inventory[7] = QaItemBuilder.charm(catalog, "visible-7", GameTypes.Rarity.COMMON, [ids[0]])
	state.inventory[2] = QaItemBuilder.weapon(catalog, "visible-2", GameTypes.WeaponType.BOW)
	state.inventory[5] = QaItemBuilder.charm(catalog, "visible-5", GameTypes.Rarity.COMMON, [ids[1]])
	state.overflow.append(QaItemBuilder.weapon(catalog, "visible-overflow", GameTypes.WeaponType.STAFF))
	assertions.expect_equal(
		PackedStringArray(["visible-2", "visible-5", "visible-7"]),
		InventoryService.auto_select(state, GameTypes.Rarity.COMMON, 3),
		"auto selection follows inventory index before overflow",
	)
	var controller := InventoryController.new()
	controller.initialize(state, catalog)
	assertions.expect_true(controller.has_fusion_material_set(), "fusion opens when any eligible rarity has three items")
	controller.open_fusion()
	assertions.expect_equal(
		PackedStringArray(["visible-2", "visible-5", "visible-7"]),
		controller.auto_fill_fusion(),
		"controller presents the same visible storage order",
	)
	assertions.expect_true(controller.replace_fusion_material(0, "visible-overflow"), "candidate replaces a material before confirmation")
	assertions.expect_equal(
		PackedStringArray(["visible-overflow", "visible-5", "visible-7"]),
		controller.fusion_material_ids,
		"replacement preserves the other two material positions",
	)
	assertions.expect_true(controller.replace_fusion_material(0, "visible-7"), "selected material can be moved by swapping")
	assertions.expect_equal(
		PackedStringArray(["visible-7", "visible-5", "visible-overflow"]),
		controller.fusion_material_ids,
		"dragging an already-selected material swaps positions",
	)
	state.inventory[2].locked = true
	assertions.expect_equal(
		PackedStringArray(["visible-5", "visible-7", "visible-overflow"]),
		InventoryService.auto_select(state, GameTypes.Rarity.COMMON, 3),
		"locked item is skipped without hidden affinity scoring",
	)

	var rare_state: RunState = RunStateFactory.create(20260827, catalog.wave(1))
	for index: int in range(3):
		rare_state.inventory[index] = QaItemBuilder.weapon(
			catalog,
			"rare-only-%d" % index,
			GameTypes.WeaponType.BOW,
			GameTypes.Rarity.RARE,
		)
	var rare_controller := InventoryController.new()
	rare_controller.initialize(rare_state, catalog)
	assertions.expect_true(rare_controller.has_fusion_material_set(), "Rare-only materials still enable fusion")


func _setup(assertions: Variant) -> Dictionary:
	var catalog := DefinitionCatalog.new()
	assertions.expect_true(catalog.load_and_validate(), "inventory catalog valid: %s" % catalog.error_text)
	return {"catalog": catalog, "state": RunStateFactory.create(20260827, catalog.wave(1))}
