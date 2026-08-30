extends RefCounted


const InventoryItemVisualsScript := preload("res://src/ui/inventory_item_visuals.gd")
const InventoryCardButtonScript := preload("res://src/ui/inventory_card_button.gd")
const UiPolishScript := preload("res://src/ui/ui_polish.gd")


func test_names() -> PackedStringArray:
	return PackedStringArray([
		"inventory_nine_icon_mapping_contract",
		"inventory_rarity_color_and_shape_contract",
		"inventory_icon_identity_ignores_item_identity_contract",
		"inventory_badge_canvas_order_contract",
	])


func run_test(test_name: String, assertions: Variant, _context: Dictionary) -> void:
	match test_name:
		"inventory_nine_icon_mapping_contract":
			_test_nine_icon_mapping(assertions)
		"inventory_rarity_color_and_shape_contract":
			_test_rarity_color_and_shape(assertions)
		"inventory_icon_identity_ignores_item_identity_contract":
			_test_icon_identity_ignores_item_identity(assertions)
		"inventory_badge_canvas_order_contract":
			_test_badge_canvas_order(assertions)
		_:
			assertions.expect_true(false, "registered inventory visual unit test")


func _test_nine_icon_mapping(assertions: Variant) -> void:
	var cases: Array[Dictionary] = [
		{
			"slot": GameTypes.EquipmentSlot.MAIN_WEAPON,
			"weapon": GameTypes.MainWeaponType.UNCLASSIFIED,
			"path": "res://assets/ui/inventory_icons/weapon_stick.png",
			"label": "empty or unclassified main weapon uses wood stick",
		},
		{
			"slot": GameTypes.EquipmentSlot.MAIN_WEAPON,
			"weapon": GameTypes.MainWeaponType.BOW,
			"path": "res://assets/ui/inventory_icons/weapon_bow.png",
			"label": "bow",
		},
		{
			"slot": GameTypes.EquipmentSlot.MAIN_WEAPON,
			"weapon": GameTypes.MainWeaponType.STAFF,
			"path": "res://assets/ui/inventory_icons/weapon_staff.png",
			"label": "staff",
		},
		{
			"slot": GameTypes.EquipmentSlot.MAIN_WEAPON,
			"weapon": GameTypes.MainWeaponType.SWORD,
			"path": "res://assets/ui/inventory_icons/weapon_sword.png",
			"label": "sword",
		},
		{
			"slot": GameTypes.EquipmentSlot.SUB_WEAPON,
			"weapon": GameTypes.MainWeaponType.UNCLASSIFIED,
			"path": "res://assets/ui/inventory_icons/slot_sub_weapon.png",
			"label": "catalyst",
		},
		{
			"slot": GameTypes.EquipmentSlot.HEAD,
			"weapon": GameTypes.MainWeaponType.UNCLASSIFIED,
			"path": "res://assets/ui/inventory_icons/slot_head.png",
			"label": "helm",
		},
		{
			"slot": GameTypes.EquipmentSlot.BODY,
			"weapon": GameTypes.MainWeaponType.UNCLASSIFIED,
			"path": "res://assets/ui/inventory_icons/slot_body.png",
			"label": "cuirass",
		},
		{
			"slot": GameTypes.EquipmentSlot.HANDS,
			"weapon": GameTypes.MainWeaponType.UNCLASSIFIED,
			"path": "res://assets/ui/inventory_icons/slot_hands.png",
			"label": "hand armor",
		},
		{
			"slot": GameTypes.EquipmentSlot.FEET,
			"weapon": GameTypes.MainWeaponType.UNCLASSIFIED,
			"path": "res://assets/ui/inventory_icons/slot_feet.png",
			"label": "boots",
		},
	]
	for test_case: Dictionary in cases:
		var texture: Texture2D = InventoryItemVisualsScript.icon_for_slot(
			int(test_case["slot"]),
			int(test_case["weapon"]),
		)
		assertions.expect_true(texture != null, "%s icon loads" % test_case["label"])
		if texture == null:
			continue
		assertions.expect_equal(test_case["path"], texture.resource_path, "%s icon path" % test_case["label"])
		assertions.expect_equal(32, texture.get_width(), "%s icon width" % test_case["label"])
		assertions.expect_equal(32, texture.get_height(), "%s icon height" % test_case["label"])


func _test_rarity_color_and_shape(assertions: Variant) -> void:
	var cases: Array[Dictionary] = [
		{
			"rarity": GameTypes.Rarity.COMMON,
			"color": Color(0.72, 0.76, 0.78, 1.0),
			"radii": PackedInt32Array([1, 1, 1, 1]),
		},
		{
			"rarity": GameTypes.Rarity.RARE,
			"color": Color(0.25, 0.67, 1.0, 1.0),
			"radii": PackedInt32Array([9, 9, 9, 9]),
		},
		{
			"rarity": GameTypes.Rarity.EPIC,
			"color": Color(0.78, 0.35, 1.0, 1.0),
			"radii": PackedInt32Array([20, 2, 20, 2]),
		},
		{
			"rarity": GameTypes.Rarity.LEGENDARY,
			"color": Color(1.0, 0.68, 0.18, 1.0),
			"radii": PackedInt32Array([28, 28, 28, 28]),
		},
		{
			"rarity": GameTypes.Rarity.UNIQUE,
			"color": Color(0.95, 0.16, 0.22, 1.0),
			"radii": PackedInt32Array([2, 28, 2, 28]),
		},
	]
	for test_case: Dictionary in cases:
		var rarity: int = int(test_case["rarity"])
		assertions.expect_equal(test_case["color"], UiPolishScript.rarity_color(rarity), "rarity color %d" % rarity)
		assertions.expect_equal(test_case["radii"], UiPolishScript.rarity_corner_radii(rarity), "rarity shape %d" % rarity)
		var style := StyleBoxFlat.new()
		UiPolishScript.apply_rarity_corner_shape(style, rarity)
		assertions.expect_equal(
			test_case["radii"],
			PackedInt32Array([
				style.corner_radius_top_left,
				style.corner_radius_top_right,
				style.corner_radius_bottom_right,
				style.corner_radius_bottom_left,
			]),
			"applied rarity shape %d" % rarity,
		)


func _test_icon_identity_ignores_item_identity(assertions: Variant) -> void:
	var first := ItemInstance.new()
	first.item_id = "visual-a"
	first.display_name = "普通の兜"
	first.slot = GameTypes.EquipmentSlot.HEAD
	first.rarity = GameTypes.Rarity.COMMON
	var second := ItemInstance.new()
	second.item_id = "visual-b"
	second.display_name = "伝説の固有名"
	second.slot = GameTypes.EquipmentSlot.HEAD
	second.rarity = GameTypes.Rarity.UNIQUE
	second.unique_id = &"hollow_crown"
	second.locked = true
	assertions.expect_equal(
		InventoryItemVisualsScript.icon_for_item(first),
		InventoryItemVisualsScript.icon_for_item(second),
		"same equipment type shares one icon across name rarity unique and lock state",
	)
	second.slot = GameTypes.EquipmentSlot.MAIN_WEAPON
	second.main_weapon_type = GameTypes.MainWeaponType.BOW
	first.slot = GameTypes.EquipmentSlot.MAIN_WEAPON
	first.main_weapon_type = GameTypes.MainWeaponType.BOW
	assertions.expect_equal(
		InventoryItemVisualsScript.icon_for_item(first),
		InventoryItemVisualsScript.icon_for_item(second),
		"same main weapon type shares one icon across item identity",
	)


func _test_badge_canvas_order(assertions: Variant) -> void:
	var card := InventoryCardButtonScript.new() as InventoryCardButton
	card.configure_item_visual(
		InventoryItemVisualsScript.icon_for_slot(
			GameTypes.EquipmentSlot.MAIN_WEAPON,
			GameTypes.MainWeaponType.SWORD,
		),
		GameTypes.Rarity.RARE,
		true,
		true,
		"✓",
		false,
		"描画順テスト",
		"状態印はカード上、モーダルの背面",
	)
	var expected_badges: Dictionary[String, String] = {
		"UniqueBadge": "★",
		"LockBadge": "🔒",
		"StateBadge": "✓",
	}
	for badge_name: String in expected_badges:
		var badge := card.get_node(NodePath(badge_name)) as Label
		assertions.expect_true(badge != null, "%s exists" % badge_name)
		if badge == null:
			continue
		assertions.expect_equal(expected_badges[badge_name], badge.text, "%s keeps its text" % badge_name)
		assertions.expect_equal(0, badge.z_index, "%s stays in the card canvas order" % badge_name)
		assertions.expect_true(badge.z_as_relative, "%s remains relative to the card" % badge_name)
	var drag_preview := card._build_drag_preview() as InventoryCardButton
	assertions.expect_true(drag_preview != null, "item drag preview remains an icon card")
	if drag_preview != null:
		for badge_name: String in expected_badges:
			var preview_badge := drag_preview.get_node(NodePath(badge_name)) as Label
			assertions.expect_equal(0, preview_badge.z_index, "drag preview %s stays in local canvas order" % badge_name)
		drag_preview.free()
	card.free()
