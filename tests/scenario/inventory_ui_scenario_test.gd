extends RefCounted


const INVENTORY_SCENE: PackedScene = preload("res://scenes/ui/inventory_screen.tscn")
const HUD_SCENE: PackedScene = preload("res://scenes/ui/combat_hud.tscn")
const TEST_JOYPAD_DEVICE: int = 63
const DIRECTIONS: Array[StringName] = [
	FocusController.DIRECTION_TOP,
	FocusController.DIRECTION_BOTTOM,
	FocusController.DIRECTION_LEFT,
	FocusController.DIRECTION_RIGHT,
]


func test_names() -> PackedStringArray:
	return PackedStringArray([
		"six_slots_storage_focus_and_accessibility",
		"controller_vertical_spatial_navigation",
		"target_specific_comparison_and_mouse_drag_presentation",
		"fusion_dialog_has_three_materials_and_no_wild_path",
		"fusion_controller_spatial_navigation",
		"combat_hud_shows_three_weapon_icons_and_rarities",
	])


func run_test(test_name: String, assertions: Variant, context: Dictionary) -> void:
	match test_name:
		"six_slots_storage_focus_and_accessibility":
			await _test_slots(assertions, context)
		"controller_vertical_spatial_navigation":
			await _test_controller_navigation(assertions, context)
		"target_specific_comparison_and_mouse_drag_presentation":
			await _test_comparison(assertions, context)
		"fusion_dialog_has_three_materials_and_no_wild_path":
			await _test_fusion(assertions, context)
		"fusion_controller_spatial_navigation":
			await _test_fusion_navigation(assertions, context)
		"combat_hud_shows_three_weapon_icons_and_rarities":
			await _test_hud(assertions, context)
		_:
			assertions.expect_true(false, "registered equipment UI scenario test")


func _test_slots(assertions: Variant, context: Dictionary) -> void:
	var fixture: Dictionary = _fixture(assertions)
	if not fixture.get("valid", false):
		return
	var screen: InventoryScreen = INVENTORY_SCENE.instantiate() as InventoryScreen
	screen.initialize(fixture["state"], fixture["catalog"])
	var viewport: SubViewport = await _attach(screen, context["tree"])
	var debug: Dictionary = screen.debug_state()
	assertions.expect_equal(6, int(debug["equipment_slot_count"]), "UI exposes three weapon and three charm slots")
	assertions.expect_equal(36, int(debug["inventory_slot_count"]), "UI keeps 36 storage slots")
	assertions.expect_equal(1, int(debug["overflow_count"]), "temporary receiving row remains available")
	for slot_index: int in range(6):
		assertions.expect_true("equip_%d" % slot_index in screen.focus_ids(), "gamepad focus includes equip slot %d" % slot_index)
	assertions.expect_true(screen.test_focus("equip_0"), "gamepad can focus first weapon")
	assertions.expect_true(screen.test_direction(FocusController.DIRECTION_RIGHT), "gamepad directional navigation moves focus")
	var card: InventoryCardButton = screen.focus_control("grid_3") as InventoryCardButton
	assertions.expect_true(card != null, "mouse-capable storage card exists")
	if card != null:
		assertions.expect_true(card.accessibility_name.contains("弓"), "item has readable Japanese accessibility name")
		assertions.expect_true(card.accessibility_description.contains("A／Enter"), "item exposes keyboard/gamepad action reading")
		assertions.expect_false(card.accessibility_description.contains("保管位置"), "accessibility text omits storage position heading")
		assertions.expect_false(card.accessibility_description.contains("装備中 E"), "accessibility text omits legacy E location marker")
		assertions.expect_false(card.accessibility_description.contains("通常枠 G"), "accessibility text omits legacy G location marker")
		assertions.expect_false(card.accessibility_description.contains("一時受取 O"), "accessibility text omits legacy O location marker")
	assertions.expect_equal(null, screen.get_node_or_null("Margin/Content/SkillPanel"), "skill panel is absent")
	await _detach(screen, viewport, context["tree"])


func _test_controller_navigation(assertions: Variant, context: Dictionary) -> void:
	var fixture: Dictionary = _fixture(assertions)
	if not fixture.get("valid", false):
		return
	var state: RunState = fixture["state"] as RunState
	var catalog: DefinitionCatalog = fixture["catalog"] as DefinitionCatalog
	for index: int in range(7):
		var overflow_item: ItemInstance = QaItemBuilder.weapon(
			catalog,
			"navigation-overflow-%d" % index,
			GameTypes.WeaponType.BOW,
			GameTypes.Rarity.COMMON,
		)
		assertions.expect_true(overflow_item != null, "overflow navigation fixture item %d exists" % index)
		if overflow_item != null:
			state.overflow.append(overflow_item)
	var tree: SceneTree = context["tree"] as SceneTree
	await _neutralize_left_stick(tree)
	var screen: InventoryScreen = INVENTORY_SCENE.instantiate() as InventoryScreen
	screen.initialize(state, catalog)
	await _attach_to_root(screen, tree)

	_assert_neighbor_spec(assertions, screen, "equip_0", "action_0", "grid_0", "equip_5", "equip_1")
	_assert_neighbor_spec(assertions, screen, "grid_7", "grid_1", "grid_13", "grid_6", "grid_8")
	_assert_neighbor_spec(assertions, screen, "grid_5", "equip_5", "grid_11", "grid_4", "grid_0")
	_assert_neighbor_spec(assertions, screen, "grid_35", "grid_29", "overflow_5", "grid_34", "grid_30")
	_assert_neighbor_spec(assertions, screen, "overflow_7", "grid_35", "action_5", "overflow_6", "overflow_0")
	_assert_neighbor_spec(assertions, screen, "action_0", "overflow_0", "equip_0", "action_5", "action_1")
	_assert_focus_graph(assertions, screen, "inventory with eight overflow items")

	assertions.expect_true(screen.test_focus("grid_7"), "D-pad test focuses grid_7")
	await _send_joy_button(tree, JOY_BUTTON_DPAD_DOWN, true)
	assertions.expect_equal("grid_13", _current_focus_id(screen), "D-pad down moves one storage row")
	await _send_joy_button(tree, JOY_BUTTON_DPAD_DOWN, false)
	await _send_joy_button(tree, JOY_BUTTON_DPAD_UP, true)
	assertions.expect_equal("grid_7", _current_focus_id(screen), "D-pad up returns one storage row")
	await _send_joy_button(tree, JOY_BUTTON_DPAD_UP, false)

	await _neutralize_left_stick(tree)
	assertions.expect_true(screen.test_focus("grid_7"), "left-stick test focuses grid_7")
	await _send_joy_motion(tree, JOY_AXIS_LEFT_Y, 0.75)
	assertions.expect_equal("grid_13", _current_focus_id(screen), "left stick down moves one storage row")
	await _send_joy_motion(tree, JOY_AXIS_LEFT_Y, 0.82)
	await _send_joy_motion(tree, JOY_AXIS_LEFT_Y, 0.93)
	assertions.expect_equal("grid_13", _current_focus_id(screen), "held left stick does not repeat before neutral")
	await _send_joy_motion(tree, JOY_AXIS_LEFT_Y, 0.0)
	await _send_joy_motion(tree, JOY_AXIS_LEFT_Y, -0.75)
	assertions.expect_equal("grid_7", _current_focus_id(screen), "neutral rearms left-stick up")
	await _send_joy_motion(tree, JOY_AXIS_LEFT_Y, 0.0)

	assertions.expect_true(screen.test_focus("grid_7"), "keyboard test focuses grid_7")
	await _send_key(tree, KEY_DOWN, true)
	assertions.expect_equal("grid_13", _current_focus_id(screen), "keyboard down shares spatial navigation")
	await _send_key(tree, KEY_DOWN, false)
	await _send_key(tree, KEY_UP, true)
	assertions.expect_equal("grid_7", _current_focus_id(screen), "keyboard up shares spatial navigation")
	await _send_key(tree, KEY_UP, false)
	await _detach_from_root(screen, tree)

	var no_overflow_fixture: Dictionary = _fixture(assertions)
	if not no_overflow_fixture.get("valid", false):
		return
	var no_overflow_state: RunState = no_overflow_fixture["state"] as RunState
	no_overflow_state.overflow.clear()
	var no_overflow_screen: InventoryScreen = INVENTORY_SCENE.instantiate() as InventoryScreen
	no_overflow_screen.initialize(
		no_overflow_state,
		no_overflow_fixture["catalog"] as DefinitionCatalog,
	)
	await _attach_to_root(no_overflow_screen, tree)
	_assert_neighbor_spec(assertions, no_overflow_screen, "grid_30", "grid_24", "action_0", "grid_35", "grid_31")
	_assert_neighbor_spec(assertions, no_overflow_screen, "action_0", "grid_30", "equip_0", "action_5", "action_1")
	assertions.expect_equal(null, no_overflow_screen.focus_control("overflow_0"), "empty overflow registers no focus target")
	_assert_focus_graph(assertions, no_overflow_screen, "inventory without overflow")
	await _detach_from_root(no_overflow_screen, tree)


func _test_comparison(assertions: Variant, context: Dictionary) -> void:
	var fixture: Dictionary = _fixture(assertions)
	if not fixture.get("valid", false):
		return
	(fixture["state"] as RunState).equipped[GameTypes.EquipmentSlot.WEAPON_2] = QaItemBuilder.weapon(
		fixture["catalog"],
		"comparison-equipped-bow",
		GameTypes.WeaponType.BOW,
	)
	var screen: InventoryScreen = INVENTORY_SCENE.instantiate() as InventoryScreen
	screen.initialize(fixture["state"], fixture["catalog"])
	var viewport: SubViewport = await _attach(screen, context["tree"])
	screen.test_focus("grid_3")
	await (context["tree"] as SceneTree).process_frame
	var own_tooltip: Dictionary = screen.debug_state()["tooltip"] as Dictionary
	assertions.expect_true(str(own_tooltip["details"]).contains("基礎ダメージ"), "ordinary tooltip shows item performance")
	assertions.expect_true(str(own_tooltip["details"]).contains("基準間隔"), "weapon tooltip labels the displayed value as nominal interval")
	assertions.expect_false(str(own_tooltip["details"]).contains("移動後"), "ordinary tooltip does not guess a destination comparison")
	var item_card: InventoryCardButton = screen.focus_control("grid_3") as InventoryCardButton
	var drag_preview: Dictionary = item_card.drag_preview_snapshot() if item_card != null else {}
	assertions.expect_true(item_card != null, "drag source card remains available")
	assertions.expect_true(bool(drag_preview.get("visual_mode", false)), "mouse drag preview preserves item icon presentation")
	screen.test_accept()
	screen.test_focus("equip_1")
	await (context["tree"] as SceneTree).process_frame
	var comparison: Dictionary = screen.debug_state()["tooltip"] as Dictionary
	assertions.expect_true(str(comparison["details"]).contains("移動後"), "comparison appears only at a concrete destination")
	assertions.expect_true(str(comparison["details"]).contains("基礎ダメージ"), "weapon replacement comparison shows before and after")
	var emitted: Array[Dictionary] = []
	screen.item_move_requested.connect(func(source: Dictionary, target: Dictionary) -> void: emitted.append({"source": source, "target": target}))
	screen.test_accept()
	assertions.expect_equal(1, emitted.size(), "gamepad accept emits the same move command used by drag/drop")
	screen.apply_command_result(&"item_move", {"success": true, "message": ""})
	screen.test_focus("equip_0")
	screen.test_accept()
	screen.test_focus("grid_3")
	await (context["tree"] as SceneTree).process_frame
	var reverse_comparison: Dictionary = screen.debug_state()["tooltip"] as Dictionary
	assertions.expect_true(str(reverse_comparison["details"]).contains("基礎ダメージ 10 → 18"), "equipped-to-storage swap compares the item entering the source slot")
	screen.apply_command_result(&"item_move", {"success": true, "message": ""})
	screen.test_focus("equip_0")
	screen.test_accept()
	screen.test_focus("grid_0")
	await (context["tree"] as SceneTree).process_frame
	var incompatible: Dictionary = screen.debug_state()["tooltip"] as Dictionary
	assertions.expect_true(not str(incompatible["warning"]).is_empty(), "concrete incompatible storage swap shows its warning before confirmation")
	screen.apply_command_result(&"item_move", {"success": true, "message": ""})
	screen.test_focus("equip_0")
	screen.test_accept()
	screen.test_focus("grid_6")
	await (context["tree"] as SceneTree).process_frame
	var removal: Dictionary = screen.debug_state()["tooltip"] as Dictionary
	assertions.expect_true(str(removal["details"]).contains("基礎ダメージ 10 → 0"), "moving to an empty destination compares equipment removal")
	await _detach(screen, viewport, context["tree"])


func _test_fusion(assertions: Variant, context: Dictionary) -> void:
	var fixture: Dictionary = _fixture(assertions)
	if not fixture.get("valid", false):
		return
	var screen: InventoryScreen = INVENTORY_SCENE.instantiate() as InventoryScreen
	screen.initialize(fixture["state"], fixture["catalog"])
	var viewport: SubViewport = await _attach(screen, context["tree"])
	screen.test_focus("action_2")
	screen.test_accept()
	await (context["tree"] as SceneTree).process_frame
	var fusion: FusionDialog = screen.get_node("FusionDialog") as FusionDialog
	assertions.expect_true(fusion.visible, "fusion modal opens with keyboard/gamepad action")
	assertions.expect_equal(null, fusion.get_node_or_null("Center/Panel/Margin/Content/Actions/FusionWildToggle"), "wild action is absent")
	assertions.expect_true(fusion.test_focus("FA0"), "fusion auto-fill is focusable")
	fusion.test_accept()
	var fusion_debug: Dictionary = fusion.debug_state()
	assertions.expect_true(bool(fusion_debug["confirm_enabled"]), "three visible-order materials enable confirmation")
	assertions.expect_equal(3, (screen.focus_control("F0").get_parent() as HBoxContainer).get_child_count(), "fusion exposes exactly three material slots")
	assertions.expect_true("FA1" in fusion.focus_ids(), "fusion confirm participates in focus graph")
	assertions.expect_false("FA3" in fusion.focus_ids(), "removed wild path leaves no legacy fourth action")
	await _detach(screen, viewport, context["tree"])


func _test_fusion_navigation(assertions: Variant, context: Dictionary) -> void:
	var fixture: Dictionary = _fixture(assertions)
	if not fixture.get("valid", false):
		return
	var state: RunState = fixture["state"] as RunState
	var catalog: DefinitionCatalog = fixture["catalog"] as DefinitionCatalog
	for inventory_index: int in range(6, 18):
		var candidate: ItemInstance = QaItemBuilder.weapon(
			catalog,
			"navigation-candidate-%d" % inventory_index,
			GameTypes.WeaponType.BOW,
			GameTypes.Rarity.COMMON,
		)
		assertions.expect_true(candidate != null, "fusion navigation candidate %d exists" % inventory_index)
		state.inventory[inventory_index] = candidate
	var tree: SceneTree = context["tree"] as SceneTree
	await _neutralize_left_stick(tree)
	var screen: InventoryScreen = INVENTORY_SCENE.instantiate() as InventoryScreen
	screen.initialize(state, catalog)
	await _attach_to_root(screen, tree)
	assertions.expect_true(screen.test_focus("action_2"), "fusion navigation focuses fusion action")
	screen.test_accept()
	await tree.process_frame
	await tree.process_frame
	var fusion: FusionDialog = screen.get_node("FusionDialog") as FusionDialog
	assertions.expect_true(fusion.visible, "fusion navigation opens modal")
	assertions.expect_equal(16, int(fusion.debug_state()["candidate_count"]), "fusion navigation fixture spans two complete rows")
	_assert_neighbor_spec(assertions, screen, "FR", "FA2", "F0", "FR", "FR")
	_assert_neighbor_spec(assertions, screen, "F0", "FR", "FC0", "F2", "F1")
	_assert_neighbor_spec(assertions, screen, "F1", "FR", "FC3", "F0", "F2")
	_assert_neighbor_spec(assertions, screen, "F2", "FR", "FC6", "F1", "F0")
	_assert_neighbor_spec(assertions, screen, "FC0", "F0", "FC8", "FC7", "FC1")
	_assert_neighbor_spec(assertions, screen, "FC7", "F2", "FC15", "FC6", "FC0")
	_assert_neighbor_spec(assertions, screen, "FC8", "FC0", "FA0", "FC15", "FC9")
	_assert_neighbor_spec(assertions, screen, "FC11", "FC3", "FA1", "FC10", "FC12")
	_assert_neighbor_spec(assertions, screen, "FC15", "FC7", "FA2", "FC14", "FC8")
	_assert_neighbor_spec(assertions, screen, "FA0", "FC9", "FR", "FA2", "FA1")
	_assert_neighbor_spec(assertions, screen, "FA1", "FC12", "FR", "FA0", "FA2")
	_assert_neighbor_spec(assertions, screen, "FA2", "FC14", "FR", "FA1", "FA0")
	_assert_focus_graph(assertions, screen, "fusion with two candidate rows")

	assertions.expect_true(screen.test_focus("FC0"), "fusion D-pad test focuses first candidate")
	await _send_joy_button(tree, JOY_BUTTON_DPAD_DOWN, true)
	assertions.expect_equal("FC8", _current_focus_id(screen), "fusion D-pad down keeps candidate column")
	await _send_joy_button(tree, JOY_BUTTON_DPAD_DOWN, false)
	await _send_joy_button(tree, JOY_BUTTON_DPAD_UP, true)
	assertions.expect_equal("FC0", _current_focus_id(screen), "fusion D-pad up returns candidate column")
	await _send_joy_button(tree, JOY_BUTTON_DPAD_UP, false)

	await _neutralize_left_stick(tree)
	assertions.expect_true(screen.test_focus("FC0"), "fusion left-stick test focuses first candidate")
	await _send_joy_motion(tree, JOY_AXIS_LEFT_Y, 0.75)
	assertions.expect_equal("FC8", _current_focus_id(screen), "fusion left stick down keeps candidate column")
	await _send_joy_motion(tree, JOY_AXIS_LEFT_Y, 0.90)
	assertions.expect_equal("FC8", _current_focus_id(screen), "fusion held stick remains one input per tilt")
	await _send_joy_motion(tree, JOY_AXIS_LEFT_Y, 0.0)
	await _send_joy_motion(tree, JOY_AXIS_LEFT_Y, -0.75)
	assertions.expect_equal("FC0", _current_focus_id(screen), "fusion neutral rearms upward tilt")
	await _send_joy_motion(tree, JOY_AXIS_LEFT_Y, 0.0)

	assertions.expect_true(screen.test_focus("FR"), "rarity selector receives focus")
	var rarity_before: String = str(fusion.debug_state()["rarity_text"])
	await _send_joy_button(tree, JOY_BUTTON_DPAD_RIGHT, true)
	await _send_joy_button(tree, JOY_BUTTON_DPAD_RIGHT, false)
	assertions.expect_equal("FR", _current_focus_id(screen), "rarity left/right does not move focus")
	assertions.expect_not_equal(rarity_before, str(fusion.debug_state()["rarity_text"]), "rarity right still changes selected rarity")

	fusion.update_view("COMMON", [], false, "材料を選択してください", "", [])
	_assert_neighbor_spec(assertions, screen, "F1", "FR", "FA1", "F0", "F2")
	_assert_neighbor_spec(assertions, screen, "FA1", "F1", "FR", "FA0", "FA2")
	assertions.expect_true(screen.test_focus("F1"), "empty candidate graph focuses middle material")
	assertions.expect_true(screen.test_direction(FocusController.DIRECTION_BOTTOM), "empty candidate graph resolves disabled confirm")
	assertions.expect_equal("FR", _current_focus_id(screen), "disabled confirm is skipped without trapping focus")
	_assert_focus_graph(assertions, screen, "fusion without candidates")
	await _neutralize_left_stick(tree)
	await _detach_from_root(screen, tree)


func _test_hud(assertions: Variant, context: Dictionary) -> void:
	var hud: CombatHud = HUD_SCENE.instantiate() as CombatHud
	var viewport: SubViewport = await _attach(hud, context["tree"])
	var snapshot := CombatSnapshot.new()
	snapshot.hud_values = {
		"wave_number": 2,
		"time_remaining": 30.0,
		"wave_kills": 5,
		"kill_quota": 40,
		"current_hp": 100.0,
		"max_hp": 100.0,
		"wave_chests": 1,
		"weapon_slots": [
			{"weapon_type": GameTypes.WeaponType.BOW, "rarity": GameTypes.Rarity.RARE},
			{"weapon_type": GameTypes.WeaponType.STAFF, "rarity": GameTypes.Rarity.EPIC},
			{"weapon_type": GameTypes.WeaponType.SWORD, "rarity": GameTypes.Rarity.LEGENDARY},
		],
	}
	hud.update_from_snapshot(snapshot)
	assertions.expect_equal("RARE", (hud.get_node("WeaponPanel/Content/WeaponSlot0/WeaponSlot0Value") as Label).text, "HUD weapon 1 shows rarity only")
	assertions.expect_equal("EPIC", (hud.get_node("WeaponPanel/Content/WeaponSlot1/WeaponSlot1Value") as Label).text, "HUD weapon 2 shows rarity only")
	assertions.expect_equal("LEGENDARY", (hud.get_node("WeaponPanel/Content/WeaponSlot2/WeaponSlot2Value") as Label).text, "HUD weapon 3 shows rarity only")
	for index: int in range(3):
		assertions.expect_true((hud.get_node("WeaponPanel/Content/WeaponSlot%d/WeaponSlot%dIcon" % [index, index]) as TextureRect).texture != null, "HUD weapon icon %d exists" % index)
	assertions.expect_equal(null, hud.get_node_or_null("SkillPanel"), "combat HUD has no skill display")
	await _detach(hud, viewport, context["tree"])


func _fixture(assertions: Variant) -> Dictionary:
	var catalog := DefinitionCatalog.new()
	assertions.expect_true(catalog.load_and_validate(), "UI catalog valid")
	if not catalog.is_valid:
		return {"valid": false}
	var fixture: Dictionary = QaScenarioFactory.build("inventory_controller", catalog)
	fixture["catalog"] = catalog
	assertions.expect_true(fixture.get("valid", false), "inventory UI fixture valid")
	return fixture


func _attach(screen: Control, tree: SceneTree) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	tree.root.add_child(viewport)
	viewport.add_child(screen)
	await tree.process_frame
	await tree.process_frame
	return viewport


func _detach(screen: Control, viewport: SubViewport, tree: SceneTree) -> void:
	viewport.remove_child(screen)
	screen.free()
	tree.root.remove_child(viewport)
	viewport.free()
	await tree.process_frame


func _attach_to_root(screen: Control, tree: SceneTree) -> void:
	tree.root.add_child(screen)
	await tree.process_frame
	await tree.process_frame


func _detach_from_root(screen: Control, tree: SceneTree) -> void:
	if screen.get_parent() == tree.root:
		tree.root.remove_child(screen)
	screen.free()
	await tree.process_frame


func _send_joy_motion(tree: SceneTree, axis: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = TEST_JOYPAD_DEVICE
	event.axis = axis
	event.axis_value = value
	Input.parse_input_event(event)
	await tree.process_frame


func _send_joy_button(tree: SceneTree, button: JoyButton, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.device = TEST_JOYPAD_DEVICE
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)
	await tree.process_frame


func _send_key(tree: SceneTree, keycode: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.pressed = pressed
	Input.parse_input_event(event)
	await tree.process_frame


func _neutralize_left_stick(tree: SceneTree) -> void:
	await _send_joy_motion(tree, JOY_AXIS_LEFT_X, 0.0)
	await _send_joy_motion(tree, JOY_AXIS_LEFT_Y, 0.0)


func _current_focus_id(screen: Control) -> String:
	var focused: Control = screen.get_viewport().gui_get_focus_owner()
	return str(focused.get_meta("focus_id", "")) if focused != null else ""


func _assert_neighbor_spec(
	assertions: Variant,
	screen: InventoryScreen,
	focus_id: String,
	top: String,
	bottom: String,
	left: String,
	right: String,
) -> void:
	assertions.expect_equal(
		{
			FocusController.DIRECTION_TOP: top,
			FocusController.DIRECTION_BOTTOM: bottom,
			FocusController.DIRECTION_LEFT: left,
			FocusController.DIRECTION_RIGHT: right,
		},
		screen.neighbor_specification(focus_id),
		"%s has the exact spatial focus neighbors" % focus_id,
	)


func _assert_focus_graph(assertions: Variant, screen: InventoryScreen, label: String) -> void:
	for focus_id: String in screen.focus_ids():
		var control: Control = screen.focus_control(focus_id)
		if (
			control == null
			or not control.is_visible_in_tree()
			or (control is BaseButton and (control as BaseButton).disabled)
		):
			continue
		for direction: StringName in DIRECTIONS:
			assertions.expect_true(screen.test_focus(focus_id), "%s focuses %s" % [label, focus_id])
			assertions.expect_true(screen.test_direction(direction), "%s moves from %s toward %s" % [label, focus_id, direction])
			var target_id: String = _current_focus_id(screen)
			var target: Control = screen.focus_control(target_id)
			assertions.expect_true(target != null and target.is_visible_in_tree(), "%s %s reaches a visible target" % [label, focus_id])
			if target is BaseButton:
				assertions.expect_false((target as BaseButton).disabled, "%s %s skips disabled targets" % [label, focus_id])
