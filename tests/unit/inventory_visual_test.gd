extends RefCounted


func test_names() -> PackedStringArray:
	return PackedStringArray([
		"weapon_and_charm_icons_and_labels",
	])


func run_test(test_name: String, assertions: Variant, _context: Dictionary) -> void:
	if test_name != "weapon_and_charm_icons_and_labels":
		assertions.expect_true(false, "registered inventory visual test")
		return
	for weapon_type: GameTypes.WeaponType in [
		GameTypes.WeaponType.WOOD_STICK,
		GameTypes.WeaponType.BOW,
		GameTypes.WeaponType.STAFF,
		GameTypes.WeaponType.SWORD,
	]:
		assertions.expect_true(InventoryItemVisuals.icon_for_weapon_type(weapon_type) != null, "weapon icon exists %d" % weapon_type)
	for slot_value: int in GameTypes.EquipmentSlot.values():
		var label: String = InventoryItemVisuals.slot_label(slot_value)
		assertions.expect_true(label.begins_with("武器") or label.begins_with("お守り"), "slot has unified label %d" % slot_value)
		assertions.expect_true(InventoryItemVisuals.icon_for_slot(slot_value) != null, "empty slot icon exists %d" % slot_value)
	var charm := ItemInstance.new()
	charm.category = GameTypes.ItemCategory.CHARM
	charm.weapon_type = GameTypes.WeaponType.NONE
	assertions.expect_equal("お守り", InventoryItemVisuals.item_type_label(charm), "charm type label has no armor term")
