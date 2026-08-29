extends RefCounted


const INVENTORY_SCENE: PackedScene = preload("res://scenes/ui/inventory_screen.tscn")
const RESULT_SCENE: PackedScene = preload("res://scenes/ui/result_screen.tscn")
const FAILED_SCENE: PackedScene = preload("res://scenes/ui/failed_screen.tscn")
const DIRECTIONS: Array[StringName] = [
	FocusController.DIRECTION_TOP,
	FocusController.DIRECTION_BOTTOM,
	FocusController.DIRECTION_LEFT,
	FocusController.DIRECTION_RIGHT,
]

var _catalog: DefinitionCatalog = null


func test_names() -> PackedStringArray:
	return PackedStringArray([
		"inventory_focus_modal_overflow_contract",
		"inventory_icon_card_presentation_contract",
		"inventory_rarity_sort_button_contract",
		"inventory_japanese_effect_presentation_contract",
		"inventory_unique_effect_presentation_contract",
		"inventory_controller_mouse_bulk_fusion_and_discard_contract",
		"fusion_dialog_exact_controller_contract",
		"inventory_exact_skill_sequence_and_crown_contract",
		"result_failed_summary_focus_and_routes_contract",
	])


func run_test(test_name: String, assertions: Variant, context: Dictionary) -> void:
	match test_name:
		"inventory_focus_modal_overflow_contract":
			await _test_focus_modal_overflow(assertions, context)
		"inventory_icon_card_presentation_contract":
			await _test_icon_card_presentation(assertions, context)
		"inventory_rarity_sort_button_contract":
			await _test_rarity_sort_button(assertions, context)
		"inventory_japanese_effect_presentation_contract":
			await _test_japanese_effect_presentation(assertions, context)
		"inventory_unique_effect_presentation_contract":
			await _test_unique_effect_presentation(assertions, context)
		"inventory_controller_mouse_bulk_fusion_and_discard_contract":
			await _test_controller_mouse_bulk_fusion_and_discard(assertions, context)
		"fusion_dialog_exact_controller_contract":
			await _test_fusion_dialog_exact_controller(assertions, context)
		"inventory_exact_skill_sequence_and_crown_contract":
			await _test_skill_sequence_and_crown(assertions, context)
		"result_failed_summary_focus_and_routes_contract":
			await _test_result_failed_routes(assertions, context)
		_:
			assertions.expect_true(false, "registered inventory inventory UI scenario test")


func _test_focus_modal_overflow(
	assertions: Variant,
	context: Dictionary,
) -> void:
	var fixture: Dictionary = await _spawn_inventory(assertions, context)
	if fixture.is_empty():
		return
	var screen: InventoryScreen = fixture["screen"]
	assertions.expect_equal("equip_0", screen.debug_state()["focus_id"], "INVENTORY deferred initial focus is MAIN_WEAPON")
	_assert_neighbor_spec(assertions, screen, "equip_0", "skill_0", "grid_0", "equip_5", "equip_1", "E0")
	_assert_neighbor_spec(assertions, screen, "grid_0", "equip_0", "grid_6", "grid_5", "grid_1", "G0,0")
	_assert_neighbor_spec(assertions, screen, "grid_35", "grid_29", "overflow_3", "grid_34", "grid_30", "G5,5")
	_assert_neighbor_spec(assertions, screen, "overflow_0", "grid_30", "action_0", "overflow_3", "overflow_1", "O0")
	_assert_neighbor_spec(assertions, screen, "action_sort", "overflow_1", "skill_1", "action_0", "action_1", "sort action")
	_assert_neighbor_spec(assertions, screen, "action_5", "overflow_3", "skill_5", "action_4", "action_0", "A5")
	_assert_neighbor_spec(assertions, screen, "skill_0", "action_0", "equip_0", "skill_5", "skill_1", "K0")
	_assert_focus_graph(assertions, screen, "normal inventory")
	assertions.expect_true((screen.focus_control("action_4") as Button).disabled, "overflow disables next-wave action")
	screen.test_focus("action_3")
	screen.test_direction(FocusController.DIRECTION_RIGHT)
	assertions.expect_equal("action_5", screen.debug_state()["focus_id"], "disabled next-wave action is skipped")

	screen.test_focus("action_5")
	var background_action_5: Control = screen.focus_control("action_5")
	screen.test_accept()
	await (context["tree"] as SceneTree).process_frame
	assertions.expect_true(screen.debug_state()["settings_open"], "inventory settings opens from A")
	var settings: SettingsOverlay = screen.get_node("%SettingsOverlay") as SettingsOverlay
	assertions.expect_equal(Control.FOCUS_NONE, background_action_5.get_focus_mode_with_override(), "inventory settings disables background focus")
	assertions.expect_equal(Control.MOUSE_FILTER_IGNORE, background_action_5.get_mouse_filter_with_override(), "inventory settings disables background mouse")
	assertions.expect_false(settings.mouse_force_pass_scroll_events, "inventory settings blocks background wheel events")
	background_action_5.grab_focus()
	assertions.expect_false(
		background_action_5 == screen.get_viewport().gui_get_focus_owner(),
		"inventory settings rejects direct background grab_focus",
	)
	FocusController.grab_focus_safe(settings.initial_focus_control())
	settings.close_overlay()
	await (context["tree"] as SceneTree).process_frame
	assertions.expect_equal("action_5", screen.debug_state()["focus_id"], "settings closes to exact origin")

	screen.test_focus("grid_0")
	var background_grid_0: Control = screen.focus_control("grid_0")
	screen.test_open_bulk()
	await (context["tree"] as SceneTree).process_frame
	var bulk: BulkSelectDialog = screen.get_node("%BulkSelectDialog") as BulkSelectDialog
	assertions.expect_equal(
		PackedStringArray(["bulk_common", "bulk_rare", "bulk_epic", "bulk_legendary", "bulk_cancel"]),
		bulk.focus_order(),
		"BulkSelectDialog exact focus order",
	)
	assertions.expect_equal("bulk_common", bulk.debug_state()["focus_id"], "BulkSelectDialog starts at last item rarity")
	assertions.expect_equal(Control.FOCUS_NONE, background_grid_0.get_focus_mode_with_override(), "bulk dialog disables background focus")
	assertions.expect_equal(Control.MOUSE_FILTER_IGNORE, background_grid_0.get_mouse_filter_with_override(), "bulk dialog disables background mouse")
	assertions.expect_false(bulk.mouse_force_pass_scroll_events, "bulk blocker does not pass wheel events")
	_assert_control_neighbor_paths(assertions, bulk.focus_controls(), "bulk")
	bulk.get_node("%BulkCancel").emit_signal("pressed")
	await (context["tree"] as SceneTree).process_frame
	assertions.expect_equal("grid_0", screen.debug_state()["focus_id"], "bulk cancel restores exact opening focus")

	screen.test_focus("action_2")
	screen.test_accept()
	await (context["tree"] as SceneTree).process_frame
	assertions.expect_true(screen.debug_state()["fusion_open"], "A2 opens FusionDialog")
	assertions.expect_equal("FR", screen.debug_state()["focus_id"], "FusionDialog starts at FR")
	var fusion_dialog: FusionDialog = screen.get_node("%FusionDialog") as FusionDialog
	var candidate_count: int = int(fusion_dialog.debug_state()["candidate_count"])
	assertions.expect_true(candidate_count > 4, "FusionDialog owns a non-empty candidate grid")
	_assert_neighbor_spec(assertions, screen, "FR", "FA3", "F0", "FR", "FR", "FR")
	_assert_neighbor_spec(assertions, screen, "F0", "FR", "FC0", "F2", "F1", "Fusion material 0")
	_assert_neighbor_spec(assertions, screen, "FC0", "F0", "FC8", "FC7", "FC1", "Fusion candidate 0")
	_assert_neighbor_spec(
		assertions,
		screen,
		"FA3",
		"FC%d" % (candidate_count - 1),
		"FR",
		"FA2",
		"FA0",
		"FA3",
	)
	assertions.expect_false("grid_0" in screen.focus_ids(), "fusion public focus set excludes background grid")
	assertions.expect_false("overflow_0" in screen.focus_ids(), "fusion public focus set excludes background overflow")
	assertions.expect_true("F0" in screen.focus_ids(), "empty material slot remains accessible and focusable")
	assertions.expect_false(fusion_dialog.mouse_force_pass_scroll_events, "fusion blocker does not pass wheel events")
	assertions.expect_false((fusion_dialog.get_node("%FusionCandidateScroll") as ScrollContainer).mouse_force_pass_scroll_events, "candidate scroll does not pass wheel events to the background")
	var outside_click := InputEventMouseButton.new()
	outside_click.button_index = MOUSE_BUTTON_LEFT
	outside_click.pressed = true
	fusion_dialog.emit_signal("gui_input", outside_click)
	assertions.expect_true(fusion_dialog.visible, "outside blocker click does not close FusionDialog")
	assertions.expect_equal(Control.FOCUS_NONE, background_grid_0.get_focus_mode_with_override(), "fusion recursively disables background focus")
	assertions.expect_equal(Control.MOUSE_FILTER_IGNORE, background_grid_0.get_mouse_filter_with_override(), "fusion recursively disables background mouse input")
	background_grid_0.grab_focus()
	assertions.expect_equal("FR", screen.debug_state()["focus_id"], "direct background grab_focus cannot steal modal focus")
	assertions.expect_true(fusion_dialog.test_tab(true), "Tab advances inside FusionDialog")
	assertions.expect_equal("F0", screen.debug_state()["focus_id"], "Tab visits the first empty material slot")
	assertions.expect_true(fusion_dialog.test_tab(false), "Shift+Tab reverses inside FusionDialog")
	assertions.expect_equal("FR", screen.debug_state()["focus_id"], "Shift+Tab wraps back to rarity")
	_assert_focus_graph(assertions, screen, "fusion modal")
	screen.test_cancel()
	assertions.expect_equal("action_2", screen.debug_state()["focus_id"], "FusionDialog B restores A2")
	_cleanup_fixture(fixture, context)

	var no_overflow_state: RunState = _overflow_state(assertions, 0)
	no_overflow_state.wild_material_count = 0
	no_overflow_state.skill_library.erase(&"soul_chain")
	var no_overflow_fixture: Dictionary = await _spawn_inventory(assertions, context, no_overflow_state)
	if no_overflow_fixture.is_empty():
		return
	var no_overflow_screen: InventoryScreen = no_overflow_fixture["screen"]
	assertions.expect_equal(0, no_overflow_screen.debug_state()["overflow_count"], "zero-overflow state hides O row")
	assertions.expect_true(no_overflow_screen.focus_control("overflow_0") == null, "zero-overflow graph registers no O node")
	assertions.expect_true((no_overflow_screen.focus_control("action_3") as Button).disabled, "wild zero disables A3")
	assertions.expect_false((no_overflow_screen.focus_control("action_4") as Button).disabled, "overflow zero with main weapon enables A4")
	assertions.expect_false((no_overflow_screen.focus_control("skill_4") as Control).visible, "unowned K4 is hidden")
	no_overflow_screen.test_focus("action_2")
	no_overflow_screen.test_direction(FocusController.DIRECTION_RIGHT)
	assertions.expect_equal("action_4", no_overflow_screen.debug_state()["focus_id"], "wild-zero traversal skips disabled A3")
	no_overflow_screen.test_focus("skill_3")
	no_overflow_screen.test_direction(FocusController.DIRECTION_RIGHT)
	assertions.expect_equal("skill_5", no_overflow_screen.debug_state()["focus_id"], "skill row traversal skips hidden unowned K4")
	_assert_focus_graph(assertions, no_overflow_screen, "zero overflow and wild")
	_cleanup_fixture(no_overflow_fixture, context)

	var missing_weapon_state: RunState = _overflow_state(assertions, 0)
	missing_weapon_state.wild_material_count = 0
	missing_weapon_state.equipped[GameTypes.EquipmentSlot.MAIN_WEAPON] = null
	var missing_weapon_fixture: Dictionary = await _spawn_inventory(assertions, context, missing_weapon_state)
	if missing_weapon_fixture.is_empty():
		return
	var missing_weapon_screen: InventoryScreen = missing_weapon_fixture["screen"]
	assertions.expect_true((missing_weapon_screen.focus_control("action_4") as Button).disabled, "injected null MAIN_WEAPON disables transition gate")
	missing_weapon_screen.test_focus("action_2")
	missing_weapon_screen.test_direction(FocusController.DIRECTION_RIGHT)
	assertions.expect_equal("action_5", missing_weapon_screen.debug_state()["focus_id"], "wild and transition disabled states are both skipped")
	_cleanup_fixture(missing_weapon_fixture, context)

	var empty_candidate_state: RunState = _overflow_state(assertions, 0)
	for item: ItemInstance in empty_candidate_state.inventory:
		if item != null:
			item.locked = true
	var empty_candidate_fixture: Dictionary = await _spawn_inventory(
		assertions,
		context,
		empty_candidate_state,
	)
	if not empty_candidate_fixture.is_empty():
		var empty_candidate_screen: InventoryScreen = empty_candidate_fixture["screen"]
		empty_candidate_screen.test_focus("action_2")
		empty_candidate_screen.test_accept()
		await (context["tree"] as SceneTree).process_frame
		var empty_dialog: FusionDialog = empty_candidate_screen.get_node("%FusionDialog") as FusionDialog
		assertions.expect_equal(0, empty_dialog.debug_state()["candidate_count"], "empty candidate state renders an explicit empty list")
		assertions.expect_equal(
			PackedStringArray(["FR", "F0", "F1", "F2", "FA0", "FA1", "FA2", "FA3"]),
			empty_dialog.focus_order(),
			"empty material slots remain in the exact Tab order",
		)
		_assert_neighbor_spec(assertions, empty_candidate_screen, "FR", "FA3", "F0", "FR", "FR", "empty FusionDialog FR")
		empty_candidate_screen.test_cancel()
		_cleanup_fixture(empty_candidate_fixture, context)

	var overflow_fixture: Dictionary = await _spawn_inventory(assertions, context, _overflow_state(assertions, 40))
	if overflow_fixture.is_empty():
		return
	var overflow_screen: InventoryScreen = overflow_fixture["screen"]
	assertions.expect_equal(40, overflow_screen.debug_state()["overflow_count"], "overflow UI has no 40-item cap")
	overflow_screen.test_focus("overflow_0")
	for expected_index: int in range(40):
		assertions.expect_equal(
			"overflow_%d" % expected_index,
			overflow_screen.debug_state()["focus_id"],
			"overflow right traversal reaches O%d" % expected_index,
		)
		await (context["tree"] as SceneTree).process_frame
		_assert_horizontally_visible(assertions, overflow_screen, expected_index)
		overflow_screen.test_direction(FocusController.DIRECTION_RIGHT)
	assertions.expect_equal("overflow_0", overflow_screen.debug_state()["focus_id"], "O39 right wraps to O0")
	overflow_screen.test_direction(FocusController.DIRECTION_LEFT)
	await (context["tree"] as SceneTree).process_frame
	assertions.expect_equal("overflow_39", overflow_screen.debug_state()["focus_id"], "O0 left wraps to O39")
	_assert_horizontally_visible(assertions, overflow_screen, 39)
	overflow_screen.test_focus("action_2")
	overflow_screen.test_accept()
	await (context["tree"] as SceneTree).process_frame
	var long_fusion: FusionDialog = overflow_screen.get_node("%FusionDialog") as FusionDialog
	var long_ids: PackedStringArray = long_fusion.debug_state()["candidate_item_ids"] as PackedStringArray
	assertions.expect_equal(8, long_fusion.debug_state()["candidate_columns"], "long fusion list remains eight columns")
	assertions.expect_equal(40, long_ids.slice(long_ids.size() - 40).size(), "all 40 temporary-receipt candidates remain available")
	assertions.expect_equal("qa-overflow-long-00", long_ids[long_ids.size() - 40], "temporary candidates follow normal inventory candidates")
	assertions.expect_equal("qa-overflow-long-39", long_ids[-1], "temporary candidate order is stable through O39")
	_assert_neighbor_spec(assertions, overflow_screen, "F0", "FR", "FC0", "F2", "F1", "long fusion material 0")
	_assert_neighbor_spec(assertions, overflow_screen, "F1", "FR", "FC3", "F0", "F2", "long fusion material 1")
	_assert_neighbor_spec(assertions, overflow_screen, "F2", "FR", "FC6", "F1", "F0", "long fusion material 2")
	_assert_neighbor_spec(assertions, overflow_screen, "FC2", "F1", "FC10", "FC1", "FC3", "long fusion first-row column 2")
	_assert_neighbor_spec(assertions, overflow_screen, "FC5", "F2", "FC13", "FC4", "FC6", "long fusion first-row column 5")
	_assert_neighbor_spec(assertions, overflow_screen, "FC50", "FC42", "FA1", "FC49", "FC51", "long fusion bottom column 2")
	_assert_neighbor_spec(assertions, overflow_screen, "FC55", "FC47", "FA3", "FC54", "FC48", "long fusion bottom column 7")
	assertions.expect_true(overflow_screen.test_fusion_candidate_focus("qa-overflow-long-39"), "last temporary candidate can receive focus")
	await (context["tree"] as SceneTree).process_frame
	_assert_fusion_candidate_vertically_visible(assertions, long_fusion, "qa-overflow-long-39")
	assertions.expect_true(int(long_fusion.debug_state()["candidate_scroll"]) > 0, "candidate focus scrolls only the candidate list")
	overflow_screen.test_cancel()
	_cleanup_fixture(overflow_fixture, context)


func _test_icon_card_presentation(assertions: Variant, context: Dictionary) -> void:
	var fixture: Dictionary = await _spawn_inventory(assertions, context)
	if fixture.is_empty():
		return
	var screen: InventoryScreen = fixture["screen"]
	var state: RunState = fixture["state"]
	assertions.expect_equal(null, screen.get_node_or_null("%ComparePanel"), "fixed inventory detail panel is removed")
	assertions.expect_equal(null, screen.get_node_or_null("%ComparisonText"), "fixed inventory comparison label is removed")
	assertions.expect_equal(null, screen.get_node_or_null("%PlacementWarning"), "fixed inventory warning label is removed")
	assertions.expect_equal(null, screen.get_node_or_null("%InventoryControlsLegend"), "fixed inventory controls legend is removed")
	var initial_tooltip: Dictionary = _inventory_tooltip_state(screen)
	assertions.expect_false(initial_tooltip["visible"], "shared tooltip is hidden before the first real input")
	assertions.expect_equal(&"none", initial_tooltip["input_mode"], "shared tooltip starts without an input mode")
	assertions.expect_equal(
		AccessibilityServer.LIVE_POLITE,
		initial_tooltip["warning_accessibility_live"],
		"shared placement warning uses a polite accessibility live region",
	)
	var equipped_bow: Dictionary = screen.item_card_presentation("equip_0")
	assertions.expect_equal(Vector2(96.0, 96.0), equipped_bow["minimum_size"], "equipped card is 96px square")
	assertions.expect_equal("res://assets/ui/inventory_icons/weapon_bow.png", equipped_bow["icon_path"], "equipped bow uses the bow icon")
	assertions.expect_equal(Color(0.72, 0.76, 0.78, 1.0), equipped_bow["icon_color"], "equipped Common icon uses the shared gray")
	assertions.expect_equal("", equipped_bow["text"], "equipped icon card contains no visible text")
	assertions.expect_equal(64, equipped_bow["icon_max_width"], "equipped icon is capped at 64px")
	assertions.expect_equal(CanvasItem.TEXTURE_FILTER_NEAREST, equipped_bow["texture_filter"], "equipped icon uses Nearest filtering")
	assertions.expect_true("主武器／弓" in str(equipped_bow["tooltip"]), "equipped tooltip contains the item type")
	assertions.expect_true("装備中 E0" in str(equipped_bow["accessibility_name"]), "equipped accessibility name contains its location")
	assertions.expect_true(equipped_bow["managed_tooltip"], "registered card suppresses the native tooltip")
	var equipped_bow_control := screen.focus_control("equip_0") as InventoryCardButton
	assertions.expect_equal("", equipped_bow_control.get_tooltip(Vector2.ZERO), "managed card does not duplicate the native tooltip")

	var grid_bow: Dictionary = screen.item_card_presentation("grid_0")
	var grid_staff: Dictionary = screen.item_card_presentation("grid_6")
	var grid_sword: Dictionary = screen.item_card_presentation("grid_12")
	assertions.expect_equal(Vector2(76.0, 76.0), grid_bow["minimum_size"], "normal inventory card is 76px square")
	assertions.expect_equal("res://assets/ui/inventory_icons/weapon_bow.png", grid_bow["icon_path"], "normal bow uses the bow icon")
	assertions.expect_equal("res://assets/ui/inventory_icons/weapon_staff.png", grid_staff["icon_path"], "normal staff uses the staff icon")
	assertions.expect_equal("res://assets/ui/inventory_icons/weapon_sword.png", grid_sword["icon_path"], "normal sword uses the sword icon")
	assertions.expect_equal(PackedInt32Array([1, 1, 1, 1]), grid_bow["corner_radii"], "Common card uses the shared square shape")

	var unique_card_control := screen.focus_control("grid_33") as InventoryCardButton
	assertions.expect_true(unique_card_control != null, "unique inventory card is available for modal ordering")
	var background_unique_badge := (
		unique_card_control.get_node("UniqueBadge") as Label
		if unique_card_control != null
		else null
	)
	var unique_card: Dictionary = screen.item_card_presentation("grid_33")
	assertions.expect_equal("res://assets/ui/inventory_icons/slot_sub_weapon.png", unique_card["icon_path"], "unique catalyst reuses the catalyst icon")
	assertions.expect_equal(Color(0.25, 0.67, 1.0, 1.0), unique_card["icon_color"], "Rare icon uses the shared blue")
	assertions.expect_equal(PackedInt32Array([9, 9, 9, 9]), unique_card["corner_radii"], "Rare card uses the shared rounded-square shape")
	assertions.expect_true(unique_card["unique_badge"], "unique item shows a top-left star")
	assertions.expect_true("名前:" in str(unique_card["tooltip"]), "unique tooltip includes its name")
	assertions.expect_true("A／Enter" in str(unique_card["accessibility_description"]), "unique accessibility description includes current operations")
	for guidance_label: String in ["配置可否:", "操作:"]:
		assertions.expect_true(
			guidance_label in str(unique_card["tooltip"]),
			"item tooltip retains %s" % guidance_label,
		)
		assertions.expect_true(
			guidance_label in str(unique_card["accessibility_description"]),
			"item accessibility description retains %s" % guidance_label,
		)
	var unique_drag: Dictionary = unique_card["drag_preview"] as Dictionary
	assertions.expect_equal(unique_card["icon_path"], unique_drag["icon_path"], "drag preview keeps the same icon")
	assertions.expect_equal(unique_card["icon_color"], unique_drag["icon_color"], "drag preview keeps the same rarity color")
	assertions.expect_equal(unique_card["unique_badge"], unique_drag["unique_badge"], "drag preview keeps the unique badge")

	var locked_card: Dictionary = screen.item_card_presentation("grid_34")
	assertions.expect_true(locked_card["lock_badge"], "locked item shows a top-right lock")
	var legendary_card: Dictionary = screen.item_card_presentation("grid_35")
	assertions.expect_equal(Color(1.0, 0.68, 0.18, 1.0), legendary_card["icon_color"], "Legendary icon uses the shared orange")
	assertions.expect_equal(PackedInt32Array([28, 28, 28, 28]), legendary_card["corner_radii"], "Legendary card uses the shared round shape")
	var overflow_card: Dictionary = screen.item_card_presentation("overflow_0")
	assertions.expect_equal(Vector2(96.0, 96.0), overflow_card["minimum_size"], "temporary-receipt card is 96px square")
	assertions.expect_equal("res://assets/ui/inventory_icons/weapon_staff.png", overflow_card["icon_path"], "temporary staff uses the staff icon")
	assertions.expect_true("一時受取 O0" in str(overflow_card["tooltip"]), "temporary tooltip contains its exact location")

	screen.test_focus("grid_33")
	var details_text: String = _inventory_tooltip_details(screen)
	for expected_text: String in ["種類:", "レアリティ:", "名前:", "効果:", "装備比較:", "保管位置:", "状態:", "配置可否:", "操作:"]:
		assertions.expect_true(expected_text in details_text, "shared inventory tooltip contains %s" % expected_text)

	screen.test_focus("action_2")
	screen.test_accept()
	await (context["tree"] as SceneTree).process_frame
	var fusion_dialog := screen.get_node("%FusionDialog") as FusionDialog
	assertions.expect_true(fusion_dialog.visible, "fusion dialog is visible for modal ordering")
	if background_unique_badge != null:
		assertions.expect_equal(0, background_unique_badge.z_index, "background unique star uses the card canvas order")
		assertions.expect_true(background_unique_badge.z_as_relative, "background unique star remains relative to its card")
		assertions.expect_true(background_unique_badge.is_visible_in_tree(), "background unique star is dimmed instead of explicitly hidden")
		assertions.expect_true(
			fusion_dialog.is_greater_than(background_unique_badge),
			"fusion dialog renders after the background unique star",
		)
	var fusion_debug: Dictionary = fusion_dialog.debug_state()
	assertions.expect_equal(8, fusion_debug["candidate_columns"], "fusion candidate grid uses eight columns")
	var unique_candidate_index: int = (fusion_debug["candidate_item_ids"] as PackedStringArray).find("qa-inventory-33")
	var candidate_presentations: Array = fusion_debug["candidate_presentations"] as Array
	assertions.expect_true(unique_candidate_index >= 0, "unique item remains a fusion candidate")
	if unique_candidate_index >= 0:
		var candidate: Dictionary = candidate_presentations[unique_candidate_index] as Dictionary
		assertions.expect_equal(Vector2(96.0, 96.0), candidate["minimum_size"], "fusion candidate is 96px square")
		assertions.expect_equal(unique_card["icon_path"], candidate["icon_path"], "fusion candidate reuses the inventory icon")
		assertions.expect_true(candidate["unique_badge"], "fusion candidate keeps the unique star")
	screen.test_fusion_candidate_focus("qa-inventory-18")
	var fusion_candidate_details: String = _fusion_tooltip_details(fusion_dialog)
	for guidance_label: String in ["配置可否:", "操作:"]:
		assertions.expect_true(
			guidance_label in fusion_candidate_details,
			"fusion candidate details retain %s" % guidance_label,
		)
	screen.test_accept()
	fusion_debug = fusion_dialog.debug_state()
	var material_presentations: Array = fusion_debug["material_presentations"] as Array
	var first_material: Dictionary = material_presentations[0] as Dictionary
	assertions.expect_equal(Vector2(96.0, 96.0), first_material["minimum_size"], "fusion material is 96px square")
	assertions.expect_equal("1", first_material["state_badge"], "fusion material shows its selected material number")
	assertions.expect_true("合成材料枠1" in str(first_material["accessibility_name"]), "fusion material accessibility identifies its slot")
	screen.test_cancel()

	screen.test_focus("grid_34")
	screen.test_lock()
	assertions.expect_false(screen.item_card_presentation("grid_34")["lock_badge"], "lock removal immediately redraws the card")
	screen.test_lock()
	assertions.expect_true(screen.item_card_presentation("grid_34")["lock_badge"], "lock restoration immediately redraws the card")
	screen.test_focus("grid_0")
	screen.test_open_bulk()
	screen.test_select_bulk(GameTypes.Rarity.COMMON)
	assertions.expect_equal("✓", screen.item_card_presentation("grid_0")["state_badge"], "bulk selection immediately draws the check badge")
	screen.test_focus("action_sort")
	screen.test_accept()
	var sorted_first: Dictionary = screen.item_card_presentation("grid_0")
	assertions.expect_equal("res://assets/ui/inventory_icons/slot_feet.png", sorted_first["icon_path"], "sort redraws the new first item icon")
	assertions.expect_equal(Color(1.0, 0.68, 0.18, 1.0), sorted_first["icon_color"], "sort redraws the new first item rarity color")

	state.equipped[GameTypes.EquipmentSlot.MAIN_WEAPON] = null
	state.inventory[5] = null
	screen.refresh_from_state(true)
	var empty_main: Dictionary = screen.item_card_presentation("equip_0")
	assertions.expect_equal("res://assets/ui/inventory_icons/weapon_stick.png", empty_main["icon_path"], "empty main weapon shows the wood-stick icon")
	assertions.expect_true(empty_main["muted"], "empty main weapon icon is muted")
	assertions.expect_true("空き" in str(empty_main["accessibility_name"]), "empty equipped slot has a complete accessibility name")
	for guidance_label: String in ["配置可否:", "操作:"]:
		assertions.expect_true(
			guidance_label in str(empty_main["accessibility_description"]),
			"empty slot accessibility description retains %s" % guidance_label,
		)
	var empty_grid: Dictionary = screen.item_card_presentation("grid_5")
	assertions.expect_equal("", empty_grid["icon_path"], "empty normal slot stays iconless")
	assertions.expect_true(empty_grid["muted"], "empty normal slot uses the empty presentation")
	screen.test_focus("equip_0")
	var empty_slot_details: String = _inventory_tooltip_details(screen)
	assertions.expect_true("主武器／木の棒" in empty_slot_details, "empty main weapon tooltip identifies the placeholder type")
	assertions.expect_true("配置可否:" in empty_slot_details, "empty slot tooltip retains placement availability")
	assertions.expect_true("操作:" in empty_slot_details, "empty slot tooltip retains current operations")
	_cleanup_fixture(fixture, context)


func _test_rarity_sort_button(
	assertions: Variant,
	context: Dictionary,
) -> void:
	var controller_fixture: Dictionary = await _spawn_inventory(assertions, context)
	var mouse_fixture: Dictionary = await _spawn_inventory(assertions, context)
	if controller_fixture.is_empty() or mouse_fixture.is_empty():
		_cleanup_fixture(controller_fixture, context)
		_cleanup_fixture(mouse_fixture, context)
		return
	var controller_screen: InventoryScreen = controller_fixture["screen"]
	var mouse_screen: InventoryScreen = mouse_fixture["screen"]
	var controller_state: RunState = controller_fixture["state"]
	var mouse_state: RunState = mouse_fixture["state"]
	var sort_button: Button = controller_screen.focus_control("action_sort") as Button
	assertions.expect_true(sort_button != null, "rarity sort button is registered")
	if sort_button == null:
		_cleanup_fixture(controller_fixture, context)
		_cleanup_fixture(mouse_fixture, context)
		return
	assertions.expect_equal(
		InventoryScreen.SORT_ACTION_LABEL,
		sort_button.text,
		"rarity sort button exposes the exact operation label",
	)
	assertions.expect_false(sort_button.disabled, "rarity sort button is always enabled")
	var focus_ids: PackedStringArray = controller_screen.focus_ids()
	assertions.expect_equal(
		focus_ids.find("action_0") + 1,
		focus_ids.find("action_sort"),
		"rarity sort follows bulk selection in Tab order",
	)
	assertions.expect_equal(
		focus_ids.find("action_sort") + 1,
		focus_ids.find("action_1"),
		"discard follows rarity sort in Tab order",
	)

	for screen: InventoryScreen in [controller_screen, mouse_screen]:
		screen.test_focus("grid_0")
		screen.test_open_bulk()
		screen.test_select_bulk(GameTypes.Rarity.COMMON)
	var controller_marks_before: PackedStringArray = controller_screen.debug_state()["marked_item_ids"]
	var mouse_marks_before: PackedStringArray = mouse_screen.debug_state()["marked_item_ids"]
	var controller_last_item_before: String = str(controller_screen.debug_state()["last_item_focus_id"])
	var mouse_last_item_before: String = str(mouse_screen.debug_state()["last_item_focus_id"])
	var controller_overflow_before: PackedStringArray = _item_ids(controller_state.overflow)
	var mouse_overflow_before: PackedStringArray = _item_ids(mouse_state.overflow)

	controller_screen.test_focus("grid_0")
	controller_screen.test_accept()
	assertions.expect_false(
		(controller_screen.debug_state()["held_item_source"] as Dictionary).is_empty(),
		"controller fixture starts with a lifted item",
	)
	controller_screen.test_focus("action_sort")
	controller_screen.test_accept()

	mouse_screen.test_focus("skill_2")
	mouse_screen.test_accept()
	assertions.expect_false(
		(mouse_screen.debug_state()["held_skill_source"] as Dictionary).is_empty(),
		"mouse fixture starts with a lifted skill",
	)
	mouse_screen.test_focus("action_sort")
	var mouse_sort_button: Button = mouse_screen.focus_control("action_sort") as Button
	mouse_sort_button.emit_signal("pressed")

	var expected_ids := PackedStringArray(["qa-inventory-35"])
	for index: int in range(27, 33):
		expected_ids.append("qa-inventory-%02d" % index)
	for index: int in range(18, 27):
		expected_ids.append("qa-inventory-%02d" % index)
	expected_ids.append("qa-inventory-33")
	for index: int in range(18):
		expected_ids.append("qa-inventory-%02d" % index)
	expected_ids.append("qa-inventory-34")
	assertions.expect_equal(expected_ids, _inventory_ids(controller_state), "controller sort uses exact rarity order")
	assertions.expect_equal(expected_ids, _inventory_ids(mouse_state), "mouse sort matches controller order")
	assertions.expect_equal(controller_overflow_before, _item_ids(controller_state.overflow), "controller sort preserves overflow")
	assertions.expect_equal(mouse_overflow_before, _item_ids(mouse_state.overflow), "mouse sort preserves overflow")
	assertions.expect_true(controller_state.inventory[35].locked, "controller sort preserves the locked Common item")
	assertions.expect_equal(&"bloodied_dagger", controller_state.inventory[16].unique_id, "controller sort preserves the Rare unique item")

	for result_case: Dictionary in [
		{
			"label": "controller",
			"screen": controller_screen,
			"marks": controller_marks_before,
			"last_item": controller_last_item_before,
		},
		{
			"label": "mouse",
			"screen": mouse_screen,
			"marks": mouse_marks_before,
			"last_item": mouse_last_item_before,
		},
	]:
		var label: String = str(result_case["label"])
		var screen: InventoryScreen = result_case["screen"] as InventoryScreen
		var debug: Dictionary = screen.debug_state()
		assertions.expect_equal("action_sort", debug["focus_id"], "%s sort preserves button focus" % label)
		assertions.expect_equal(
			InventoryService.SORT_COMPLETE_MESSAGE,
			debug["status"],
			"%s sort displays the exact completion message" % label,
		)
		assertions.expect_equal(result_case["marks"], debug["marked_item_ids"], "%s sort preserves marks" % label)
		assertions.expect_equal(result_case["last_item"], debug["last_item_focus_id"], "%s sort preserves last item" % label)
		assertions.expect_true((debug["held_item_source"] as Dictionary).is_empty(), "%s sort clears item lift" % label)
		assertions.expect_true((debug["held_skill_source"] as Dictionary).is_empty(), "%s sort clears skill lift" % label)
		assertions.expect_false(bool(debug["confirmation_open"]), "%s sort opens no confirmation" % label)
		assertions.expect_equal(0, debug["modal_stack_size"], "%s sort leaves no active modal" % label)
		assertions.expect_equal(&"", debug["pending_command_kind"], "%s sort completes synchronously" % label)

	var sorted_before: PackedStringArray = _inventory_ids(controller_state)
	controller_screen.test_accept()
	assertions.expect_equal(sorted_before, _inventory_ids(controller_state), "repeated UI sort is idempotent")
	assertions.expect_equal(
		InventoryService.SORT_COMPLETE_MESSAGE,
		controller_screen.debug_state()["status"],
		"repeated UI sort keeps the same completion message",
	)
	assertions.expect_equal("action_sort", controller_screen.debug_state()["focus_id"], "repeated UI sort keeps focus")
	_cleanup_fixture(controller_fixture, context)
	_cleanup_fixture(mouse_fixture, context)


func _test_japanese_effect_presentation(
	assertions: Variant,
	context: Dictionary,
) -> void:
	var catalog: DefinitionCatalog = _loaded_catalog(assertions)
	if catalog == null:
		return
	var qa: Dictionary = QaScenarioFactory.build("inventory_controller", catalog)
	assertions.expect_true(qa.get("valid", false), "Japanese effect presentation fixture valid")
	if not qa.get("valid", false):
		return
	var state: RunState = qa["state"] as RunState
	var item: ItemInstance = state.inventory[0]
	var unknown_item: ItemInstance = state.inventory[1]
	var equipped: ItemInstance = state.equipped.get(
		GameTypes.EquipmentSlot.MAIN_WEAPON
	) as ItemInstance
	assertions.expect_true(
		item != null and unknown_item != null and equipped != null,
		"Japanese effect presentation items exist",
	)
	if item == null or unknown_item == null or equipped == null:
		return

	var effect_cases: Array[Dictionary] = [
		{"id": &"damage_pct", "value": 14.5, "text": "与ダメージ +14.5%"},
		{"id": &"attack_speed_pct", "value": 8.0, "text": "攻撃速度 +8%"},
		{"id": &"cooldown_reduction_pct", "value": 10.0, "text": "クールダウン短縮 +10%"},
		{"id": &"area_pct", "value": 30.0, "text": "効果範囲 +30%"},
		{"id": &"pierce", "value": 2.0, "text": "貫通数 +2"},
		{"id": &"max_hp", "value": 18.0, "text": "最大HP +18"},
		{"id": &"damage_reduction_pct", "value": 9.0, "text": "被ダメージ軽減 +9%"},
		{"id": &"move_speed_pct", "value": 10.0, "text": "移動速度 +10%"},
		{"id": &"skill_power_pct", "value": 18.0, "text": "スキルダメージ +18%"},
	]
	item.display_name = "日本語効果テスト"
	item.affixes.clear()
	for effect_case: Dictionary in effect_cases:
		item.affixes.append(_effect_affix(
			effect_case["id"] as StringName,
			float(effect_case["value"]),
		))
	var equipped_affixes: Array[AffixRoll] = [
		_effect_affix(&"damage_pct", 20.0),
		_effect_affix(&"attack_speed_pct", 8.0),
		_effect_affix(&"max_hp", 10.0),
	]
	equipped.affixes = equipped_affixes
	unknown_item.display_name = "未知効果テスト"
	var unknown_affixes: Array[AffixRoll] = [_effect_affix(&"future_effect", 2.0)]
	unknown_item.affixes = unknown_affixes

	var fixture: Dictionary = await _spawn_inventory(assertions, context, state)
	if fixture.is_empty():
		return
	var screen: InventoryScreen = fixture["screen"]
	var item_card: InventoryCardButton = screen.focus_control("grid_0") as InventoryCardButton
	assertions.expect_true(item_card != null, "Japanese effect item card exists")
	var tooltip: String = item_card.tooltip_text if item_card != null else ""
	for effect_case: Dictionary in effect_cases:
		assertions.expect_true(
			str(effect_case["text"]) in tooltip,
			"tooltip presents %s" % effect_case["id"],
		)
		assertions.expect_false(
			str(effect_case["id"]) in tooltip,
			"tooltip hides internal ID %s" % effect_case["id"],
		)

	screen.test_focus("grid_0")
	var comparison: String = _inventory_tooltip_details(screen)
	assertions.expect_true("▼ 与ダメージ -5.5%" in comparison, "comparison presents a negative percentage delta")
	assertions.expect_true("◆ 攻撃速度 0%" in comparison, "comparison presents a zero percentage delta")
	assertions.expect_true("▲ 最大HP +8" in comparison, "comparison presents a positive absolute delta")
	for effect_case: Dictionary in effect_cases:
		assertions.expect_false(
			str(effect_case["id"]) in comparison,
			"comparison hides internal ID %s" % effect_case["id"],
		)

	var unknown_card: InventoryCardButton = screen.focus_control("grid_1") as InventoryCardButton
	var unknown_tooltip: String = unknown_card.tooltip_text if unknown_card != null else ""
	assertions.expect_true("不明な効果 +2" in unknown_tooltip, "unknown effect uses the Japanese fallback")
	assertions.expect_false("future_effect" in unknown_tooltip, "unknown effect hides its internal ID")
	screen.test_focus("grid_1")
	var unknown_comparison: String = _inventory_tooltip_details(screen)
	assertions.expect_true("不明な効果 +2" in unknown_comparison, "comparison uses the unknown-effect fallback")
	assertions.expect_false("future_effect" in unknown_comparison, "comparison hides an unknown internal ID")

	screen.test_focus("grid_0")
	screen.test_focus("action_2")
	screen.test_accept()
	assertions.expect_true(
		screen.test_fusion_candidate_focus(item.item_id),
		"Japanese effect fusion candidate receives focus",
	)
	var fusion_dialog: FusionDialog = screen.get_node("%FusionDialog") as FusionDialog
	var candidate_details: String = _fusion_tooltip_details(fusion_dialog)
	for effect_case: Dictionary in effect_cases:
		assertions.expect_true(
			str(effect_case["text"]) in candidate_details,
			"fusion details present %s" % effect_case["id"],
		)
		assertions.expect_false(
			str(effect_case["id"]) in candidate_details,
			"fusion details hide internal ID %s" % effect_case["id"],
		)
	screen.test_cancel()
	_cleanup_fixture(fixture, context)


func _test_unique_effect_presentation(
	assertions: Variant,
	context: Dictionary,
) -> void:
	var catalog: DefinitionCatalog = _loaded_catalog(assertions)
	if catalog == null:
		return
	var qa: Dictionary = QaScenarioFactory.build("inventory_controller", catalog)
	assertions.expect_true(qa.get("valid", false), "unique effect presentation fixture valid")
	if not qa.get("valid", false):
		return
	var state: RunState = qa["state"] as RunState
	var unique_ids: Array[StringName] = catalog.unique_ids()
	var unique_items: Array[ItemInstance] = []
	for index: int in range(unique_ids.size()):
		var unique_id: StringName = unique_ids[index]
		var definition: UniqueDefinition = catalog.unique(unique_id)
		assertions.expect_true(definition != null, "unique UI definition %s exists" % unique_id)
		if definition == null:
			continue
		var item := ItemInstance.new()
		item.item_id = "qa-unique-effect-%s" % unique_id
		item.item_seed = index
		item.slot = definition.equipment_slot
		item.rarity = GameTypes.Rarity.COMMON
		item.unique_id = unique_id
		item.display_name = definition.display_name
		state.inventory[index] = item
		unique_items.append(item)

	var unknown_index: int = unique_ids.size()
	var unknown_item := ItemInstance.new()
	unknown_item.item_id = "qa-unknown-unique-effect"
	unknown_item.item_seed = unknown_index
	unknown_item.slot = GameTypes.EquipmentSlot.SUB_WEAPON
	unknown_item.rarity = GameTypes.Rarity.COMMON
	unknown_item.unique_id = &"future_unique"
	unknown_item.display_name = "未知のユニーク装備"
	state.inventory[unknown_index] = unknown_item

	var normal_index: int = unknown_index + 1
	var normal_item := ItemInstance.new()
	normal_item.item_id = "qa-normal-effect-control"
	normal_item.item_seed = normal_index
	normal_item.slot = GameTypes.EquipmentSlot.SUB_WEAPON
	normal_item.rarity = GameTypes.Rarity.COMMON
	normal_item.display_name = "通常装備"
	state.inventory[normal_index] = normal_item

	var fixture: Dictionary = await _spawn_inventory(assertions, context, state)
	if fixture.is_empty():
		return
	var screen: InventoryScreen = fixture["screen"]
	for index: int in range(unique_items.size()):
		var item: ItemInstance = unique_items[index]
		var definition: UniqueDefinition = catalog.unique(item.unique_id)
		var effect_block: String = "固有効果:\n★ %s" % definition.effect_description
		var focus_id: String = "grid_%d" % index
		var card: Dictionary = screen.item_card_presentation(focus_id)
		var tooltip: String = str(card.get("tooltip", ""))
		var accessibility_name: String = str(card.get("accessibility_name", ""))
		var accessibility_description: String = str(card.get("accessibility_description", ""))
		assertions.expect_true(effect_block in tooltip, "%s tooltip presents its unique effect" % item.unique_id)
		assertions.expect_true(
			definition.effect_description in accessibility_name,
			"%s accessibility name presents its unique effect" % item.unique_id,
		)
		assertions.expect_true(
			effect_block in accessibility_description,
			"%s accessibility description presents its unique effect" % item.unique_id,
		)
		assertions.expect_false(
			String(item.unique_id) in tooltip,
			"%s tooltip hides its internal unique ID" % item.unique_id,
		)
		assertions.expect_true(screen.test_focus(focus_id), "%s receives inventory focus" % item.unique_id)
		var comparison: String = _inventory_tooltip_details(screen)
		assertions.expect_true(
			effect_block in comparison,
			"%s right details present its unique effect" % item.unique_id,
		)

	var unknown_focus_id: String = "grid_%d" % unknown_index
	var unknown_card: Dictionary = screen.item_card_presentation(unknown_focus_id)
	var unknown_tooltip: String = str(unknown_card.get("tooltip", ""))
	assertions.expect_true(
		"固有効果:\n★ 不明な固有効果" in unknown_tooltip,
		"unknown unique tooltip uses the Japanese fallback",
	)
	assertions.expect_false(
		"future_unique" in unknown_tooltip,
		"unknown unique tooltip hides its internal ID",
	)
	assertions.expect_true(screen.test_focus(unknown_focus_id), "unknown unique receives inventory focus")
	var unknown_comparison: String = _inventory_tooltip_details(screen)
	assertions.expect_true(
		"固有効果:\n★ 不明な固有効果" in unknown_comparison,
		"unknown unique right details use the Japanese fallback",
	)
	assertions.expect_false(
		"future_unique" in unknown_comparison,
		"unknown unique right details hide its internal ID",
	)

	var normal_card: Dictionary = screen.item_card_presentation("grid_%d" % normal_index)
	assertions.expect_false(
		"固有効果:" in str(normal_card.get("tooltip", "")),
		"normal equipment omits the unique-effect block",
	)

	assertions.expect_true(screen.test_focus("grid_0"), "first unique restores focus before fusion")
	assertions.expect_true(screen.test_focus("action_2"), "fusion action receives focus for unique effects")
	screen.test_accept()
	var fusion_dialog: FusionDialog = screen.get_node("%FusionDialog") as FusionDialog
	for item: ItemInstance in unique_items:
		var definition: UniqueDefinition = catalog.unique(item.unique_id)
		var fusion_effect_block: String = "固有効果:\n★ %s" % definition.effect_description
		assertions.expect_true(
			screen.test_fusion_candidate_focus(item.item_id),
			"%s fusion candidate receives focus" % item.unique_id,
		)
		var candidate_details: String = _fusion_tooltip_details(fusion_dialog)
		assertions.expect_true(
			fusion_effect_block in candidate_details,
			"%s fusion details present its unique effect" % item.unique_id,
		)
	assertions.expect_true(
		screen.test_fusion_candidate_focus(unknown_item.item_id),
		"unknown unique fusion candidate receives focus",
	)
	var unknown_candidate_details: String = _fusion_tooltip_details(fusion_dialog)
	assertions.expect_true(
		"固有効果:\n★ 不明な固有効果" in unknown_candidate_details,
		"unknown unique fusion details use the Japanese fallback",
	)
	assertions.expect_false(
		"future_unique" in unknown_candidate_details,
		"unknown unique fusion details hide its internal ID",
	)

	var first_unique: ItemInstance = unique_items[0]
	var first_definition: UniqueDefinition = catalog.unique(first_unique.unique_id)
	assertions.expect_true(
		screen.test_fusion_candidate_focus(first_unique.item_id),
		"first unique fusion candidate receives focus for material details",
	)
	screen.test_accept()
	assertions.expect_true(screen.test_focus("F0"), "first fusion material receives focus")
	var material_details: String = _fusion_tooltip_details(fusion_dialog)
	var material_effect_block: String = "固有効果:\n★ %s" % first_definition.effect_description
	assertions.expect_true(
		material_effect_block in material_details,
		"fusion material details present the unique effect",
	)
	screen.test_cancel()
	_cleanup_fixture(fixture, context)


func _test_controller_mouse_bulk_fusion_and_discard(
	assertions: Variant,
	context: Dictionary,
) -> void:
	var controller_fixture: Dictionary = await _spawn_inventory(assertions, context)
	var mouse_fixture: Dictionary = await _spawn_inventory(assertions, context)
	if controller_fixture.is_empty() or mouse_fixture.is_empty():
		_cleanup_fixture(controller_fixture, context)
		_cleanup_fixture(mouse_fixture, context)
		return
	var controller_screen: InventoryScreen = controller_fixture["screen"]
	var mouse_screen: InventoryScreen = mouse_fixture["screen"]
	var controller_state: RunState = controller_fixture["state"]
	var mouse_state: RunState = mouse_fixture["state"]
	controller_screen.test_focus("grid_0")
	assertions.expect_true("比較:" in _inventory_tooltip_details(controller_screen), "controller focus updates the shared tooltip")
	controller_screen.test_accept()
	assertions.expect_equal(
		"",
		_inventory_tooltip_warning(controller_screen),
		"controller lift shows no warning for its valid source slot",
	)
	controller_screen.test_focus("grid_6")
	assertions.expect_equal(
		"",
		_inventory_tooltip_warning(controller_screen),
		"controller lift shows no warning for a valid storage target",
	)
	controller_screen.test_accept()
	var initial_mouse_source: Dictionary = {
		"drag_type": &"item",
		"kind": &"inventory",
		"index": 0,
		"item_id": "qa-inventory-00",
	}
	var initial_mouse_target: Dictionary = {"kind": &"inventory", "index": 6}
	mouse_screen.test_mouse_drag_preview(initial_mouse_source, initial_mouse_target)
	assertions.expect_equal(
		"",
		_inventory_tooltip_warning(mouse_screen),
		"mouse drag shows no warning for a valid storage target",
	)
	mouse_screen.test_mouse_drop(
		initial_mouse_source,
		initial_mouse_target,
	)
	mouse_screen.test_mouse_drag_end()
	assertions.expect_equal(
		"",
		_inventory_tooltip_warning(mouse_screen),
		"mouse drag end clears placement warning state",
	)
	assertions.expect_equal(_inventory_ids(controller_state), _inventory_ids(mouse_state), "mouse drag and controller lift produce identical inventory")
	assertions.expect_equal(
		"res://assets/ui/inventory_icons/weapon_staff.png",
		controller_screen.item_card_presentation("grid_0")["icon_path"],
		"controller move redraws the staff icon at its new position",
	)
	assertions.expect_equal(
		controller_screen.item_card_presentation("grid_0")["icon_path"],
		mouse_screen.item_card_presentation("grid_0")["icon_path"],
		"mouse move redraws the same icon as controller movement",
	)
	assertions.expect_equal(0, controller_screen.debug_state()["pointer_event_count"], "controller item move emits zero pointer events")
	assertions.expect_true(int(mouse_screen.debug_state()["pointer_event_count"]) > 0, "mouse item move records pointer activity")

	var controller_main_before: ItemInstance = controller_state.equipped[GameTypes.EquipmentSlot.MAIN_WEAPON]
	var mouse_main_before: ItemInstance = mouse_state.equipped[GameTypes.EquipmentSlot.MAIN_WEAPON]
	var controller_exchange_before: ItemInstance = controller_state.inventory[6]
	var mouse_exchange_before: ItemInstance = mouse_state.inventory[6]
	controller_screen.test_focus("equip_0")
	controller_screen.test_accept()
	controller_screen.test_focus("grid_6")
	controller_screen.test_accept()
	mouse_screen.test_mouse_drop(
		{"drag_type": &"item", "kind": &"equipped", "index": 0, "item_id": mouse_main_before.item_id},
		{"kind": &"inventory", "index": 6},
	)
	assertions.expect_equal(controller_exchange_before.item_id, controller_state.equipped[GameTypes.EquipmentSlot.MAIN_WEAPON].item_id, "controller equipment exchange installs matching main weapon")
	assertions.expect_equal(controller_main_before.item_id, controller_state.inventory[6].item_id, "controller equipment exchange returns old main weapon")
	assertions.expect_equal(mouse_exchange_before.item_id, mouse_state.equipped[GameTypes.EquipmentSlot.MAIN_WEAPON].item_id, "mouse equipment exchange installs matching main weapon")
	assertions.expect_equal(mouse_main_before.item_id, mouse_state.inventory[6].item_id, "mouse equipment exchange returns old main weapon")
	assertions.expect_equal(_inventory_ids(controller_state), _inventory_ids(mouse_state), "mouse and controller equipment exchange results match")

	var controller_sub_before: ItemInstance = controller_state.equipped[GameTypes.EquipmentSlot.SUB_WEAPON]
	var mouse_sub_before: ItemInstance = mouse_state.equipped[GameTypes.EquipmentSlot.SUB_WEAPON]
	controller_state.inventory[5] = null
	mouse_state.inventory[5] = null
	controller_screen.refresh_from_state(true)
	mouse_screen.refresh_from_state(true)
	controller_screen.test_focus("equip_1")
	controller_screen.test_accept()
	controller_screen.test_focus("grid_5")
	controller_screen.test_accept()
	mouse_screen.test_mouse_drop(
		{"drag_type": &"item", "kind": &"equipped", "index": 1, "item_id": mouse_sub_before.item_id},
		{"kind": &"inventory", "index": 5},
	)
	assertions.expect_equal(null, controller_state.equipped[GameTypes.EquipmentSlot.SUB_WEAPON], "controller returns equipped item to empty inventory slot")
	assertions.expect_equal(controller_sub_before.item_id, controller_state.inventory[5].item_id, "controller unequip preserves exact item")
	assertions.expect_equal(null, mouse_state.equipped[GameTypes.EquipmentSlot.SUB_WEAPON], "mouse returns equipped item to empty inventory slot")
	assertions.expect_equal(mouse_sub_before.item_id, mouse_state.inventory[5].item_id, "mouse unequip preserves exact item")
	assertions.expect_equal(_inventory_ids(controller_state), _inventory_ids(mouse_state), "mouse and controller unequip results match")
	assertions.expect_true(controller_screen.item_card_presentation("equip_1")["muted"], "controller unequip redraws an empty muted equipment slot")
	assertions.expect_equal(
		"res://assets/ui/inventory_icons/slot_sub_weapon.png",
		controller_screen.item_card_presentation("grid_5")["icon_path"],
		"controller unequip redraws the catalyst icon in normal storage",
	)

	var before_cancel: PackedStringArray = _inventory_ids(controller_state)
	controller_screen.test_focus("grid_1")
	controller_screen.test_accept()
	assertions.expect_false((controller_screen.debug_state()["held_item_source"] as Dictionary).is_empty(), "A lifts focused item")
	controller_screen.test_cancel()
	assertions.expect_equal(before_cancel, _inventory_ids(controller_state), "B cancel restores item without state mutation")
	assertions.expect_true((controller_screen.debug_state()["held_item_source"] as Dictionary).is_empty(), "B clears held item")
	controller_screen.test_focus("grid_1")
	controller_screen.test_lock()
	assertions.expect_true(controller_state.inventory[1].locked, "X locks focused item")
	controller_screen.test_lock()
	assertions.expect_false(controller_state.inventory[1].locked, "X toggles lock back off")
	_cleanup_fixture(mouse_fixture, context)
	_cleanup_fixture(controller_fixture, context)

	var full_controller_fixture: Dictionary = await _spawn_inventory(
		assertions,
		context,
		_overflow_state(assertions, 0),
	)
	var full_mouse_fixture: Dictionary = await _spawn_inventory(
		assertions,
		context,
		_overflow_state(assertions, 0),
	)
	if full_controller_fixture.is_empty() or full_mouse_fixture.is_empty():
		_cleanup_fixture(full_controller_fixture, context)
		_cleanup_fixture(full_mouse_fixture, context)
		return
	var full_controller_screen: InventoryScreen = full_controller_fixture["screen"]
	var full_mouse_screen: InventoryScreen = full_mouse_fixture["screen"]
	var full_controller_state: RunState = full_controller_fixture["state"]
	var full_mouse_state: RunState = full_mouse_fixture["state"]
	var full_controller_sub: ItemInstance = full_controller_state.equipped[GameTypes.EquipmentSlot.SUB_WEAPON]
	var full_mouse_sub: ItemInstance = full_mouse_state.equipped[GameTypes.EquipmentSlot.SUB_WEAPON]
	assertions.expect_equal(-1, InventoryService.first_empty_index(full_controller_state), "full unequip fixture has no inventory gap")
	full_controller_screen.test_focus("equip_1")
	full_controller_screen.test_accept()
	full_controller_screen.test_accept()
	full_mouse_screen.test_mouse_drop(
		{"drag_type": &"item", "kind": &"equipped", "index": 1, "item_id": full_mouse_sub.item_id},
		{"kind": &"equipped", "index": 1},
	)
	assertions.expect_equal(null, full_controller_state.equipped[GameTypes.EquipmentSlot.SUB_WEAPON], "same E controller placement performs standalone unequip")
	assertions.expect_equal(null, full_mouse_state.equipped[GameTypes.EquipmentSlot.SUB_WEAPON], "same E mouse drop performs standalone unequip")
	assertions.expect_equal(1, full_controller_state.overflow.size(), "full inventory controller unequip appends to overflow")
	assertions.expect_equal(1, full_mouse_state.overflow.size(), "full inventory mouse unequip appends to overflow")
	assertions.expect_equal(full_controller_sub.item_id, full_controller_state.overflow[0].item_id, "controller overflow keeps exact unequipped item")
	assertions.expect_equal(full_mouse_sub.item_id, full_mouse_state.overflow[0].item_id, "mouse overflow keeps exact unequipped item")
	assertions.expect_equal(_inventory_ids(full_controller_state), _inventory_ids(full_mouse_state), "full inventory standalone unequip keeps controller and mouse inventory equal")
	var full_controller_main_id: String = full_controller_state.equipped[GameTypes.EquipmentSlot.MAIN_WEAPON].item_id
	full_controller_screen.test_focus("equip_0")
	full_controller_screen.test_accept()
	var main_warning: String = (
		InventoryScreen.PLACEMENT_WARNING_PREFIX
		+ InventoryService.MAIN_WEAPON_REQUIRED_MESSAGE
	)
	assertions.expect_equal(
		main_warning,
		_inventory_tooltip_warning(full_controller_screen),
		"controller main-weapon lift warns before same-slot removal",
	)
	full_controller_screen.test_accept()
	assertions.expect_equal(full_controller_main_id, full_controller_state.equipped[GameTypes.EquipmentSlot.MAIN_WEAPON].item_id, "same E main weapon standalone unequip is rejected")
	assertions.expect_equal(InventoryService.MAIN_WEAPON_REQUIRED_MESSAGE, full_controller_screen.debug_state()["status"], "main weapon standalone rejection displays fixed message")
	assertions.expect_false((full_controller_screen.debug_state()["held_item_source"] as Dictionary).is_empty(), "failed main weapon standalone move remains held until B")
	assertions.expect_equal(
		main_warning,
		_inventory_tooltip_warning(full_controller_screen),
		"failed controller move keeps its advisory warning",
	)
	full_controller_screen.test_focus("action_2")
	full_controller_screen.test_accept()
	assertions.expect_true(
		full_controller_screen.debug_state()["fusion_open"],
		"controller can open a modal while an item remains held",
	)
	assertions.expect_equal(
		"",
		_inventory_tooltip_warning(full_controller_screen),
		"opening a modal clears placement warning",
	)
	full_controller_screen.test_cancel()
	full_controller_screen.test_cancel()
	assertions.expect_true((full_controller_screen.debug_state()["held_item_source"] as Dictionary).is_empty(), "B cancels rejected main weapon lift")
	assertions.expect_equal(
		"",
		_inventory_tooltip_warning(full_controller_screen),
		"controller cancel clears placement warning",
	)
	var full_mouse_main: ItemInstance = full_mouse_state.equipped[GameTypes.EquipmentSlot.MAIN_WEAPON]
	var mouse_main_source: Dictionary = {
		"drag_type": &"item",
		"kind": &"equipped",
		"index": GameTypes.EquipmentSlot.MAIN_WEAPON,
		"item_id": full_mouse_main.item_id,
	}
	var mouse_main_target: Dictionary = {
		"kind": &"equipped",
		"index": GameTypes.EquipmentSlot.MAIN_WEAPON,
	}
	full_mouse_screen.test_mouse_drag_preview(mouse_main_source, mouse_main_target)
	assertions.expect_equal(
		main_warning,
		_inventory_tooltip_warning(full_mouse_screen),
		"mouse main-weapon drag shows the same advisory warning",
	)
	full_mouse_screen.test_mouse_drag_end()
	assertions.expect_equal(
		"",
		_inventory_tooltip_warning(full_mouse_screen),
		"mouse drag end clears an active invalid warning",
	)
	full_mouse_screen.test_mouse_drag_preview(mouse_main_source, mouse_main_target)
	full_mouse_screen.test_mouse_drop(mouse_main_source, mouse_main_target)
	assertions.expect_equal(
		InventoryService.MAIN_WEAPON_REQUIRED_MESSAGE,
		full_mouse_screen.debug_state()["status"],
		"mouse invalid drop still reaches the existing command error",
	)
	assertions.expect_equal(
		full_mouse_main.item_id,
		full_mouse_state.equipped[GameTypes.EquipmentSlot.MAIN_WEAPON].item_id,
		"mouse advisory does not mutate or block the main weapon",
	)
	assertions.expect_equal(0, full_controller_screen.debug_state()["pointer_event_count"], "full inventory controller unequip remains pointer-free")
	assertions.expect_true(int(full_mouse_screen.debug_state()["pointer_event_count"]) > 0, "full inventory mouse unequip records pointer activity")
	_cleanup_fixture(full_mouse_fixture, context)
	_cleanup_fixture(full_controller_fixture, context)

	var controller_fusion_fixture: Dictionary = await _spawn_inventory(assertions, context)
	var mouse_fusion_fixture: Dictionary = await _spawn_inventory(assertions, context)
	if controller_fusion_fixture.is_empty() or mouse_fusion_fixture.is_empty():
		_cleanup_fixture(controller_fusion_fixture, context)
		_cleanup_fixture(mouse_fusion_fixture, context)
		return
	var controller_fusion_screen: InventoryScreen = controller_fusion_fixture["screen"]
	var mouse_fusion_screen: InventoryScreen = mouse_fusion_fixture["screen"]
	controller_fusion_screen.test_focus("action_2")
	controller_fusion_screen.test_accept()
	mouse_fusion_screen.test_focus("action_2")
	mouse_fusion_screen.test_accept()
	controller_fusion_screen.test_fusion_candidate_focus("qa-inventory-00")
	controller_fusion_screen.test_accept()
	var mouse_fusion_dialog: FusionDialog = mouse_fusion_screen.get_node("%FusionDialog") as FusionDialog
	mouse_fusion_dialog.pointer_event.emit()
	mouse_fusion_dialog.material_item_dropped.emit(
		{"drag_type": &"item", "kind": &"inventory", "index": 0, "item_id": "qa-inventory-00"},
		0,
	)
	assertions.expect_equal(
		controller_fusion_screen.debug_state()["fusion_material_ids"],
		mouse_fusion_screen.debug_state()["fusion_material_ids"],
		"mouse G-to-F drag and controller G accept select identical fusion material",
	)
	controller_fusion_screen.test_focus("F0")
	controller_fusion_screen.test_accept()
	mouse_fusion_dialog.pointer_event.emit()
	mouse_fusion_dialog.material_drag_removed.emit(0)
	assertions.expect_equal(
		controller_fusion_screen.debug_state()["fusion_material_ids"],
		mouse_fusion_screen.debug_state()["fusion_material_ids"],
		"mouse F removal drag and controller F accept remove identical material",
	)
	assertions.expect_equal(0, controller_fusion_screen.debug_state()["pointer_event_count"], "controller fusion material editing remains pointer-free")
	assertions.expect_true(int(mouse_fusion_screen.debug_state()["pointer_event_count"]) > 0, "mouse fusion material editing records pointer activity")
	_cleanup_fixture(mouse_fusion_fixture, context)
	_cleanup_fixture(controller_fusion_fixture, context)

	var bulk_fixture: Dictionary = await _spawn_inventory(assertions, context)
	if bulk_fixture.is_empty():
		return
	var bulk_screen: InventoryScreen = bulk_fixture["screen"]
	var bulk_state: RunState = bulk_fixture["state"]
	bulk_screen.test_focus("grid_0")
	bulk_screen.test_open_bulk()
	bulk_screen.test_select_bulk(GameTypes.Rarity.COMMON)
	assertions.expect_equal(
		PackedStringArray(["qa-inventory-00", "qa-inventory-01", "qa-inventory-02"]),
		bulk_screen.debug_state()["marked_item_ids"],
		"Common bulk selection returns exact build-value and item-id order",
	)
	bulk_screen.test_focus("action_1")
	bulk_screen.test_accept()
	assertions.expect_equal(1, bulk_state.overflow.size(), "first bulk discard refills three stable overflow entries")
	bulk_screen.test_focus("action_0")
	bulk_screen.test_accept()
	bulk_screen.test_select_bulk(GameTypes.Rarity.COMMON)
	bulk_screen.test_focus("action_1")
	bulk_screen.test_accept()
	assertions.expect_equal(0, bulk_state.overflow.size(), "controller-only bulk flow resolves overflow")
	assertions.expect_false((bulk_screen.focus_control("action_4") as Button).disabled, "next-wave action enables after overflow resolves")
	var continue_hits: Array[int] = [0]
	bulk_screen.continue_requested.connect(func() -> void: continue_hits[0] += 1)
	bulk_screen.test_focus("action_4")
	bulk_screen.test_accept()
	assertions.expect_equal(1, continue_hits[0], "controller reaches next-wave command")
	assertions.expect_equal(0, bulk_screen.debug_state()["pointer_event_count"], "bulk controller scenario remains pointer-free")
	_cleanup_fixture(bulk_fixture, context)

	var unique_fixture: Dictionary = await _spawn_inventory(assertions, context)
	if unique_fixture.is_empty():
		return
	var unique_screen: InventoryScreen = unique_fixture["screen"]
	var unique_state: RunState = unique_fixture["state"]
	var rng_before: Dictionary = _rng_snapshot(unique_state)
	unique_screen.test_focus("grid_33")
	unique_screen.test_focus("action_1")
	var discard_origin: Control = unique_screen.focus_control("action_1")
	unique_screen.test_accept()
	await (context["tree"] as SceneTree).process_frame
	assertions.expect_true(unique_screen.debug_state()["confirmation_open"], "unique discard opens standard confirmation")
	assertions.expect_equal("dialog_cancel", (unique_screen.get_node("%ConfirmationDialog") as JarjarConfirmationDialog).debug_state()["focus_id"], "confirmation starts on cancel")
	assertions.expect_equal(Control.FOCUS_NONE, discard_origin.get_focus_mode_with_override(), "confirmation disables inventory background focus")
	assertions.expect_equal(Control.MOUSE_FILTER_IGNORE, discard_origin.get_mouse_filter_with_override(), "confirmation disables inventory background mouse")
	unique_screen.test_confirm_dialog(false)
	assertions.expect_equal("action_1", unique_screen.debug_state()["focus_id"], "unique discard cancel restores A1")
	assertions.expect_equal(rng_before, _rng_snapshot(unique_state), "unique discard cancel preserves RNG and serial")
	assertions.expect_false(InventoryService.find_item(unique_state, "qa-inventory-33").is_empty(), "unique survives confirmation cancel")
	unique_screen.test_accept()
	unique_screen.test_confirm_dialog(true)
	assertions.expect_true(InventoryService.find_item(unique_state, "qa-inventory-33").is_empty(), "unique confirm discards exact target")
	assertions.expect_equal("action_1", unique_screen.debug_state()["focus_id"], "unique discard confirm restores A1")
	assertions.expect_equal(rng_before, _rng_snapshot(unique_state), "discard confirmation consumes no RNG")
	_cleanup_fixture(unique_fixture, context)

	var fusion_fixture: Dictionary = await _spawn_inventory(assertions, context)
	if fusion_fixture.is_empty():
		return
	var fusion_screen: InventoryScreen = fusion_fixture["screen"]
	var fusion_state: RunState = fusion_fixture["state"]
	var fusion_requests: Array[Dictionary] = []
	var fusion_background_grid_0: Control = fusion_screen.focus_control("grid_0")
	fusion_screen.fusion_requested.connect(func(ids: PackedStringArray, use_wild: bool, confirmed: bool) -> void:
		fusion_requests.append({"ids": ids.duplicate(), "wild": use_wild, "confirmed": confirmed})
	)
	fusion_screen.test_focus("action_2")
	fusion_screen.test_accept()
	var fusion_dialog: FusionDialog = fusion_screen.get_node("%FusionDialog") as FusionDialog
	var fusion_rarity_before: GameTypes.Rarity = fusion_screen.debug_state()["fusion_rarity"]
	fusion_screen.test_focus("FA0")
	fusion_screen.test_accept()
	var first_material_ids := PackedStringArray([
		"qa-inventory-00",
		"qa-inventory-01",
		"qa-inventory-02",
	])
	assertions.expect_equal(
		first_material_ids,
		fusion_screen.debug_state()["fusion_material_ids"],
		"fusion auto-fill uses exact fixed Common IDs",
	)
	fusion_screen.test_focus("FA2")
	fusion_screen.apply_command_result(
		&"fusion",
		{"success": false, "error": &"invalid", "message": "合成できません"},
	)
	assertions.expect_true(fusion_screen.debug_state()["fusion_open"], "fusion failure keeps the modal open")
	assertions.expect_equal(first_material_ids, fusion_screen.debug_state()["fusion_material_ids"], "fusion failure preserves exact material IDs")
	assertions.expect_equal("合成できません", fusion_screen.debug_state()["fusion_status"], "fusion failure is visible inside the modal")
	assertions.expect_equal("FA2", fusion_screen.debug_state()["focus_id"], "fusion failure restores the confirm focus")
	fusion_screen.test_accept()
	assertions.expect_equal(1, fusion_requests.size(), "fusion confirm emits one command")
	if not fusion_requests.is_empty():
		assertions.expect_equal(first_material_ids, fusion_requests[0]["ids"], "fusion command preserves exact material order")
	assertions.expect_equal(1, fusion_state.fusion_count, "fusion command commits once")
	var first_success: Dictionary = fusion_screen.debug_state()
	assertions.expect_true(first_success["fusion_open"], "fusion success keeps FusionDialog open")
	assertions.expect_equal(1, first_success["modal_stack_size"], "fusion success keeps one active modal")
	assertions.expect_equal(&"FusionDialog", first_success["active_modal"], "fusion success keeps FusionDialog topmost")
	assertions.expect_equal(fusion_rarity_before, first_success["fusion_rarity"], "fusion success preserves the selected rarity")
	assertions.expect_equal(PackedStringArray(), first_success["fusion_material_ids"], "fusion success clears consumed material slots")
	assertions.expect_false(first_success["fusion_use_wild"], "fusion success clears the wild reservation")
	assertions.expect_false(first_success["fusion_valid"], "fusion success disables confirm until new materials are chosen")
	assertions.expect_equal("FA0", first_success["focus_id"], "fusion success focuses auto-fill")
	assertions.expect_equal(InventoryScreen.FUSION_SUCCESS_FALLBACK_TEXT, first_success["fusion_status"], "fusion success message is visible inside FusionDialog")
	assertions.expect_equal("FusionStatus", first_success["fusion_feedback_target"], "fusion success animates the modal status")
	assertions.expect_equal(Control.FOCUS_NONE, fusion_background_grid_0.get_focus_mode_with_override(), "fusion success never re-enables background focus")
	assertions.expect_equal(Control.MOUSE_FILTER_IGNORE, fusion_background_grid_0.get_mouse_filter_with_override(), "fusion success never re-enables background mouse input")
	var refreshed_candidate_ids: PackedStringArray = fusion_dialog.debug_state()["candidate_item_ids"]
	for consumed_id: String in first_material_ids:
		assertions.expect_false(consumed_id in refreshed_candidate_ids, "fusion refresh removes consumed candidate %s" % consumed_id)
	assertions.expect_true(fusion_screen.test_fusion_candidate_focus("qa-inventory-03"), "fusion success refresh keeps the next Common candidate")
	assertions.expect_equal(InventoryScreen.FUSION_SUCCESS_FALLBACK_TEXT, fusion_screen.debug_state()["fusion_status"], "focus movement does not clear the success message")
	fusion_screen.test_focus("FA0")
	fusion_screen.test_accept()
	var second_material_ids: PackedStringArray = fusion_screen.debug_state()["fusion_material_ids"]
	assertions.expect_equal(3, second_material_ids.size(), "auto-fill prepares a second fusion without closing the modal")
	for consumed_id: String in first_material_ids:
		assertions.expect_false(consumed_id in second_material_ids, "second auto-fill never reuses consumed material %s" % consumed_id)
	assertions.expect_equal("", fusion_screen.debug_state()["fusion_status"], "next fusion operation clears the success message")
	assertions.expect_false(fusion_screen.debug_state()["fusion_feedback_presented"], "next fusion operation clears the success feedback")
	fusion_screen.test_focus("FA2")
	fusion_screen.test_accept()
	assertions.expect_equal(2, fusion_requests.size(), "second fusion emits exactly one additional command")
	assertions.expect_equal(2, fusion_state.fusion_count, "second fusion commits without stale selection state")
	assertions.expect_true(fusion_screen.debug_state()["fusion_open"], "second fusion also keeps the modal open")
	assertions.expect_equal("FA0", fusion_screen.debug_state()["focus_id"], "second fusion returns to auto-fill")
	assertions.expect_equal(0, fusion_screen.debug_state()["pointer_event_count"], "fusion controller flow emits zero pointer events")
	fusion_screen.test_cancel()
	assertions.expect_false(fusion_screen.debug_state()["fusion_open"], "manual close ends the continued fusion session")
	assertions.expect_equal("action_2", fusion_screen.debug_state()["focus_id"], "successful fusion session closes to A2")
	assertions.expect_equal("", fusion_screen.debug_state()["status"], "closing the successful session does not carry its message to the background")
	_cleanup_fixture(fusion_fixture, context)

	var exhausted_state: RunState = _overflow_state(assertions, 0)
	if exhausted_state != null:
		exhausted_state.wild_material_count = 0
		for index: int in range(exhausted_state.inventory.size()):
			var item: ItemInstance = exhausted_state.inventory[index]
			if item != null:
				item.locked = index > 2
		var exhausted_fixture: Dictionary = await _spawn_inventory(
			assertions,
			context,
			exhausted_state,
		)
		if not exhausted_fixture.is_empty():
			var exhausted_screen: InventoryScreen = exhausted_fixture["screen"]
			exhausted_screen.test_focus("action_2")
			exhausted_screen.test_accept()
			exhausted_screen.test_focus("FA0")
			exhausted_screen.test_accept()
			exhausted_screen.test_focus("FA2")
			exhausted_screen.test_accept()
			var exhausted_dialog: FusionDialog = exhausted_screen.get_node("%FusionDialog") as FusionDialog
			assertions.expect_equal(0, exhausted_dialog.debug_state()["candidate_count"], "fusion success supports an empty refreshed candidate list")
			assertions.expect_equal("FA0", exhausted_screen.debug_state()["focus_id"], "empty refreshed candidates still focus auto-fill")
			assertions.expect_false(exhausted_dialog.debug_state()["wild_enabled"], "empty exhausted fixture disables wild")
			assertions.expect_false(exhausted_dialog.debug_state()["confirm_enabled"], "empty exhausted fixture disables confirm")
			assertions.expect_true(exhausted_dialog.test_tab(true), "Tab remains usable after the final candidate is consumed")
			assertions.expect_equal("FA3", exhausted_screen.debug_state()["focus_id"], "Tab skips disabled wild and confirm buttons")
			exhausted_screen.test_cancel()
			assertions.expect_equal("action_2", exhausted_screen.debug_state()["focus_id"], "exhausted successful session closes to A2")
			_cleanup_fixture(exhausted_fixture, context)

	var wild_fixture: Dictionary = await _spawn_inventory(assertions, context)
	if wild_fixture.is_empty():
		return
	var wild_screen: InventoryScreen = wild_fixture["screen"]
	wild_screen.test_focus("action_3")
	wild_screen.test_accept()
	wild_screen.test_focus("FA0")
	wild_screen.test_accept()
	assertions.expect_true(wild_screen.debug_state()["fusion_use_wild"], "wild shortcut reserves exactly one wild material")
	assertions.expect_equal(PackedStringArray(["qa-inventory-00", "qa-inventory-01"]), wild_screen.debug_state()["fusion_material_ids"], "wild fusion auto-fill uses exact two item IDs")
	wild_screen.test_cancel()
	assertions.expect_equal("action_3", wild_screen.debug_state()["focus_id"], "wild fusion B returns to its exact A3 origin")
	assertions.expect_equal(1, (wild_fixture["state"] as RunState).wild_material_count, "wild cancel leaves RunState unchanged")
	_cleanup_fixture(wild_fixture, context)


func _test_fusion_dialog_exact_controller(
	assertions: Variant,
	context: Dictionary,
) -> void:
	var rare_fixture: Dictionary = await _spawn_inventory(assertions, context)
	if rare_fixture.is_empty():
		return
	var rare_screen: InventoryScreen = rare_fixture["screen"]
	var rare_state: RunState = rare_fixture["state"]
	var rare_before: Dictionary = _run_state_signature(rare_state)
	var rare_rng_before: Dictionary = _rng_snapshot(rare_state)
	rare_screen.test_focus("grid_33")
	rare_screen.test_focus("action_2")
	rare_screen.test_accept()
	assertions.expect_equal(GameTypes.Rarity.RARE, rare_screen.debug_state()["fusion_rarity"], "last focus qa-inventory-33 opens FR=Rare")
	var rare_dialog: FusionDialog = rare_screen.get_node("%FusionDialog") as FusionDialog
	var unique_candidate_id: String = rare_dialog.focus_id_for_candidate("qa-inventory-33")
	assertions.expect_false(unique_candidate_id.is_empty(), "unlocked unique remains manually selectable")
	rare_screen.test_fusion_candidate_focus("qa-inventory-33")
	assertions.expect_true("通常枠 G5,3" in _fusion_tooltip_details(rare_dialog), "candidate tooltip shows exact storage location")
	assertions.expect_true("固有効果が失われます" in _fusion_tooltip_details(rare_dialog), "unique candidate tooltip shows loss warning")
	var unique_candidate: BaseButton = rare_dialog.focus_control(unique_candidate_id) as BaseButton
	var unique_candidate_position: Vector2 = unique_candidate.position
	for index: int in [18, 19, 33]:
		rare_screen.test_fusion_candidate_focus("qa-inventory-%02d" % index)
		rare_screen.test_accept()
	assertions.expect_equal(
		PackedStringArray(["qa-inventory-18", "qa-inventory-19", "qa-inventory-33"]),
		rare_screen.debug_state()["fusion_material_ids"],
		"controller assigns exact Rare IDs to F0, F1, F2",
	)
	assertions.expect_equal(unique_candidate, rare_dialog.focus_control(unique_candidate_id), "selected candidate keeps the same control and list position")
	assertions.expect_equal(unique_candidate_position, unique_candidate.position, "selected candidate stays at its original grid position")
	assertions.expect_true(unique_candidate.button_pressed, "selected candidate has persistent highlighted state")
	var unique_presentation: Dictionary = (unique_candidate as InventoryCardButton).presentation_snapshot()
	assertions.expect_equal("", unique_presentation["text"], "selected candidate keeps card text empty")
	assertions.expect_equal("3", unique_presentation["state_badge"], "selected candidate shows material number badge")
	assertions.expect_true(unique_presentation["unique_badge"], "selected unique candidate shows the star badge")
	var candidate_unique_badge := unique_candidate.get_node("UniqueBadge") as Label
	var unique_material := rare_dialog.focus_control("F2") as InventoryCardButton
	assertions.expect_true(unique_material != null, "third material card contains the selected unique item")
	var material_unique_badge := unique_material.get_node("UniqueBadge") as Label
	var material_number_badge := unique_material.get_node("StateBadge") as Label
	assertions.expect_equal(rare_before, _run_state_signature(rare_state), "selecting F materials does not remove or mutate source slots before commit")
	assertions.expect_true((rare_screen.get_node("%FusionDialog") as FusionDialog).debug_state()["confirm_enabled"], "FA2 enables for exact three Rare materials")
	rare_screen.test_focus("FA2")
	rare_screen.test_accept()
	await (context["tree"] as SceneTree).process_frame
	assertions.expect_true(rare_screen.debug_state()["confirmation_open"], "Rare fusion containing unique opens named confirmation")
	var confirmation_dialog := rare_screen.get_node("%ConfirmationDialog") as JarjarConfirmationDialog
	for lower_badge: Label in [candidate_unique_badge, material_unique_badge, material_number_badge]:
		assertions.expect_equal(0, lower_badge.z_index, "%s uses local canvas order below confirmation" % lower_badge.name)
		assertions.expect_true(
			confirmation_dialog.is_greater_than(lower_badge),
			"confirmation dialog renders after %s" % lower_badge.name,
		)
	var rare_confirm: Control = rare_dialog.focus_control("FA2")
	assertions.expect_equal(Control.FOCUS_NONE, rare_confirm.get_focus_mode_with_override(), "nested confirmation disables lower FusionDialog focus")
	rare_confirm.grab_focus()
	assertions.expect_equal("dialog_cancel", rare_screen.debug_state()["focus_id"], "lower modal cannot steal nested confirmation focus")
	var fusion_selection_before_cancel: Dictionary = _fusion_selection_signature(rare_screen)
	rare_screen.test_confirm_dialog(false)
	assertions.expect_equal("FA2", rare_screen.debug_state()["focus_id"], "confirmation cancel restores fusion confirm")
	assertions.expect_equal(fusion_selection_before_cancel, _fusion_selection_signature(rare_screen), "unique warning cancel preserves F selection and rarity")
	assertions.expect_equal(rare_before, _run_state_signature(rare_state), "unique warning cancel preserves complete RunState")
	assertions.expect_equal(rare_rng_before, _rng_snapshot(rare_state), "unique warning cancel preserves every RNG stream")
	rare_screen.test_accept()
	rare_screen.test_confirm_dialog(true)
	for item_id: String in ["qa-inventory-18", "qa-inventory-19", "qa-inventory-33"]:
		assertions.expect_true(InventoryService.find_item(rare_state, item_id).is_empty(), "confirmed Rare fusion consumes exact source %s" % item_id)
	var rare_output: ItemInstance = rare_state.inventory[18]
	assertions.expect_true(rare_output != null, "confirmed Rare fusion writes one output into lowest source slot")
	if rare_output != null:
		assertions.expect_equal(GameTypes.Rarity.EPIC, rare_output.rarity, "confirmed Rare fusion creates exact Epic output")
	assertions.expect_equal(1, rare_state.fusion_count, "confirmed Rare fusion increments count once")
	assertions.expect_true(rare_screen.debug_state()["fusion_open"], "confirmed unique fusion keeps FusionDialog open")
	assertions.expect_equal(GameTypes.Rarity.RARE, rare_screen.debug_state()["fusion_rarity"], "confirmed unique fusion preserves Rare selection")
	assertions.expect_equal(PackedStringArray(), rare_screen.debug_state()["fusion_material_ids"], "confirmed unique fusion clears materials")
	var cleared_materials: Array = (rare_dialog.debug_state()["material_presentations"] as Array)
	for cleared_material_value: Variant in cleared_materials:
		var cleared_material: Dictionary = cleared_material_value as Dictionary
		assertions.expect_equal("", cleared_material["icon_path"], "fusion success clears each material icon")
		assertions.expect_true(cleared_material["muted"], "fusion success redraws each material slot as empty")
	assertions.expect_equal("FA0", rare_screen.debug_state()["focus_id"], "confirmed unique fusion focuses auto-fill")
	for consumed_id: String in ["qa-inventory-18", "qa-inventory-19", "qa-inventory-33"]:
		assertions.expect_false(rare_screen.test_fusion_candidate_focus(consumed_id), "confirmed unique fusion removes candidate %s" % consumed_id)
	assertions.expect_equal(0, rare_screen.debug_state()["pointer_event_count"], "exact Rare fusion controller flow emits no pointer events")
	rare_screen.test_cancel()
	assertions.expect_equal("action_2", rare_screen.debug_state()["focus_id"], "confirmed unique fusion session closes to A2")
	_cleanup_fixture(rare_fixture, context)

	var wild_fixture: Dictionary = await _spawn_inventory(assertions, context)
	if wild_fixture.is_empty():
		return
	var wild_screen: InventoryScreen = wild_fixture["screen"]
	var wild_state: RunState = wild_fixture["state"]
	wild_screen.test_focus("grid_3")
	wild_screen.test_focus("action_3")
	wild_screen.test_accept()
	assertions.expect_equal(GameTypes.Rarity.COMMON, wild_screen.debug_state()["fusion_rarity"], "last focus qa-inventory-03 opens FR=Common")
	assertions.expect_true(wild_screen.debug_state()["fusion_use_wild"], "A3 reserves exactly one wild material")
	for index: int in [3, 4]:
		wild_screen.test_fusion_candidate_focus("qa-inventory-%02d" % index)
		wild_screen.test_accept()
	assertions.expect_equal(PackedStringArray(["qa-inventory-03", "qa-inventory-04"]), wild_screen.debug_state()["fusion_material_ids"], "wild controller flow assigns exact Common IDs")
	wild_screen.test_focus("FA2")
	wild_screen.test_accept()
	for item_id: String in ["qa-inventory-03", "qa-inventory-04"]:
		assertions.expect_true(InventoryService.find_item(wild_state, item_id).is_empty(), "wild fusion consumes exact source %s" % item_id)
	var wild_output: ItemInstance = wild_state.inventory[3]
	assertions.expect_true(wild_output != null, "wild fusion writes one output into lowest source slot")
	if wild_output != null:
		assertions.expect_equal(GameTypes.Rarity.RARE, wild_output.rarity, "two Common plus wild creates exact Rare output")
	assertions.expect_equal(0, wild_state.wild_material_count, "wild fusion consumes exactly one wild material")
	assertions.expect_equal(1, wild_state.fusion_count, "wild fusion increments count once")
	assertions.expect_true(wild_screen.debug_state()["fusion_open"], "wild fusion success keeps FusionDialog open")
	assertions.expect_false(wild_screen.debug_state()["fusion_use_wild"], "wild fusion success clears the next reservation")
	assertions.expect_equal(PackedStringArray(), wild_screen.debug_state()["fusion_material_ids"], "wild fusion success clears materials")
	assertions.expect_equal("FA0", wild_screen.debug_state()["focus_id"], "wild fusion success focuses auto-fill")
	assertions.expect_false((wild_screen.get_node("%FusionDialog") as FusionDialog).debug_state()["wild_enabled"], "consumed final wild disables its button")
	assertions.expect_equal(0, wild_screen.debug_state()["pointer_event_count"], "exact wild fusion controller flow emits no pointer events")
	wild_screen.test_cancel()
	assertions.expect_equal("action_2", wild_screen.debug_state()["focus_id"], "successful A3 fusion session ultimately closes to A2")
	_cleanup_fixture(wild_fixture, context)

	var rejection_fixture: Dictionary = await _spawn_inventory(assertions, context)
	if rejection_fixture.is_empty():
		return
	var rejection_screen: InventoryScreen = rejection_fixture["screen"]
	var rejection_state: RunState = rejection_fixture["state"]
	var rejection_before: Dictionary = _run_state_signature(rejection_state)
	var rejection_rng_before: Dictionary = _rng_snapshot(rejection_state)
	rejection_screen.test_focus("grid_3")
	rejection_screen.test_focus("action_2")
	rejection_screen.test_accept()
	for rejected_index: int in [34, 35, 18]:
		assertions.expect_false(
			rejection_screen.test_fusion_candidate_focus("qa-inventory-%02d" % rejected_index),
			"locked/Legendary/mismatched item %d is absent from candidates" % rejected_index,
		)
		assertions.expect_equal(PackedStringArray(), rejection_screen.debug_state()["fusion_material_ids"], "locked/Legendary/mismatched material %d is rejected" % rejected_index)
	rejection_screen.test_fusion_candidate_focus("qa-inventory-03")
	rejection_screen.test_accept()
	assertions.expect_equal(PackedStringArray(["qa-inventory-03"]), rejection_screen.debug_state()["fusion_material_ids"], "valid Common enters F0")
	rejection_screen.test_focus("F0")
	rejection_screen.test_accept()
	assertions.expect_equal(PackedStringArray(), rejection_screen.debug_state()["fusion_material_ids"], "A on F removes selected material")
	for index: int in [3, 4]:
		rejection_screen.test_fusion_candidate_focus("qa-inventory-%02d" % index)
		rejection_screen.test_accept()
	rejection_screen.test_focus("FA1")
	rejection_screen.test_accept()
	assertions.expect_true(rejection_screen.debug_state()["fusion_use_wild"], "button reset fixture reserves wild material")
	var rarity_dialog := rejection_screen.get_node("%FusionDialog") as FusionDialog
	var rarity_button := rarity_dialog.get_node("%FusionRarity") as Button
	rarity_button.emit_signal("pressed")
	assertions.expect_equal(GameTypes.Rarity.RARE, rejection_screen.debug_state()["fusion_rarity"], "rarity button advances Common to Rare")
	assertions.expect_equal(PackedStringArray(), rejection_screen.debug_state()["fusion_material_ids"], "rarity button clears all F material slots")
	assertions.expect_false(rejection_screen.debug_state()["fusion_use_wild"], "rarity button clears wild reservation")
	var rare_button_state: Dictionary = rarity_dialog.debug_state()
	var rare_candidate_ids: PackedStringArray = rare_button_state["candidate_item_ids"] as PackedStringArray
	assertions.expect_true("qa-inventory-18" in rare_candidate_ids, "rarity button refreshes Rare candidates")
	assertions.expect_false("qa-inventory-03" in rare_candidate_ids, "rarity button removes Common candidates from the view")
	assertions.expect_true("出力: EPIC" in str(rare_button_state["preview"]), "rarity button refreshes the output preview")
	rarity_button.emit_signal("pressed")
	assertions.expect_equal(GameTypes.Rarity.EPIC, rejection_screen.debug_state()["fusion_rarity"], "rarity button advances Rare to Epic")
	rarity_button.emit_signal("pressed")
	assertions.expect_equal(GameTypes.Rarity.COMMON, rejection_screen.debug_state()["fusion_rarity"], "rarity button wraps Epic to Common")
	assertions.expect_equal(
		"レアリティ　◀ COMMON ▶\n←→／方向パッド左右",
		rarity_dialog.debug_state()["rarity_text"],
		"rarity button keeps the existing operation copy",
	)
	for index: int in [3, 4]:
		rejection_screen.test_fusion_candidate_focus("qa-inventory-%02d" % index)
		rejection_screen.test_accept()
	_replay_fusion_rarity_input(rejection_screen, "ui_right")
	assertions.expect_equal(GameTypes.Rarity.RARE, rejection_screen.debug_state()["fusion_rarity"], "controller FR right changes Common to Rare")
	assertions.expect_equal(PackedStringArray(), rejection_screen.debug_state()["fusion_material_ids"], "FR change clears all F material slots")
	assertions.expect_false(rejection_screen.debug_state()["fusion_use_wild"], "FR change clears wild reservation")
	_replay_fusion_rarity_input(rejection_screen, "ui_left")
	assertions.expect_equal(GameTypes.Rarity.COMMON, rejection_screen.debug_state()["fusion_rarity"], "controller FR left changes Rare to Common")
	rejection_screen.test_cancel()
	assertions.expect_equal(rejection_before, _run_state_signature(rejection_state), "FusionDialog B cancel preserves complete RunState")
	assertions.expect_equal(rejection_rng_before, _rng_snapshot(rejection_state), "FusionDialog invalid/edit/cancel flow preserves every RNG stream")
	_cleanup_fixture(rejection_fixture, context)

	var controller_fixture: Dictionary = await _spawn_inventory(assertions, context)
	var mouse_fixture: Dictionary = await _spawn_inventory(assertions, context)
	if controller_fixture.is_empty() or mouse_fixture.is_empty():
		_cleanup_fixture(controller_fixture, context)
		_cleanup_fixture(mouse_fixture, context)
		return
	var controller_screen: InventoryScreen = controller_fixture["screen"]
	var mouse_screen: InventoryScreen = mouse_fixture["screen"]
	for screen: InventoryScreen in [controller_screen, mouse_screen]:
		screen.test_focus("grid_33")
		screen.test_focus("action_2")
		screen.test_accept()
	for index: int in [18, 19, 33]:
		controller_screen.test_fusion_candidate_focus("qa-inventory-%02d" % index)
		controller_screen.test_accept()
	var mouse_dialog: FusionDialog = mouse_screen.get_node("%FusionDialog") as FusionDialog
	var rare_ids := PackedStringArray(["qa-inventory-18", "qa-inventory-19", "qa-inventory-33"])
	for index: int in range(rare_ids.size()):
		mouse_dialog.pointer_event.emit()
		mouse_dialog.material_item_dropped.emit(
			{"drag_type": &"item", "kind": &"inventory", "index": [18, 19, 33][index], "item_id": rare_ids[index]},
			index,
		)
	assertions.expect_equal(controller_screen.debug_state()["fusion_material_ids"], mouse_screen.debug_state()["fusion_material_ids"], "mouse drag and controller place all three exact F materials identically")
	assertions.expect_equal(0, controller_screen.debug_state()["pointer_event_count"], "three-material controller placement emits zero pointer events")
	assertions.expect_true(int(mouse_screen.debug_state()["pointer_event_count"]) > 0, "three-material mouse placement records pointer events")
	_cleanup_fixture(mouse_fixture, context)
	_cleanup_fixture(controller_fixture, context)


func _test_skill_sequence_and_crown(assertions: Variant, context: Dictionary) -> void:
	var fixture: Dictionary = await _spawn_inventory(assertions, context)
	if fixture.is_empty():
		return
	var state: RunState = fixture["state"]
	var screen: InventoryScreen = fixture["screen"]
	_assert_skill_slots(assertions, state, PackedInt32Array([0, 1, -1, -1]), "initial")
	_move_skill_with_controller(screen, "skill_4", "skill_0")
	_assert_skill_slots(assertions, state, PackedInt32Array([-1, 1, 0, -1]), "K4 to K0")
	_move_skill_with_controller(screen, "skill_3", "skill_0")
	_assert_skill_slots(assertions, state, PackedInt32Array([-1, 0, 1, -1]), "K3 to K0")
	_move_skill_with_controller(screen, "skill_2", "skill_1")
	_assert_skill_slots(assertions, state, PackedInt32Array([1, 0, -1, -1]), "K2 to K1")
	screen.test_focus("skill_5")
	screen.test_accept()
	screen.test_cancel()
	_assert_skill_slots(assertions, state, PackedInt32Array([1, 0, -1, -1]), "K5 B cancel")
	assertions.expect_equal(0, screen.debug_state()["pointer_event_count"], "exact skill sequence is pointer-free")

	var head: ItemInstance = state.equipped.get(GameTypes.EquipmentSlot.HEAD) as ItemInstance
	head.unique_id = &"hollow_crown"
	SkillEquipService.apply_crown_seal(state)
	screen.refresh_from_state(true)
	assertions.expect_true((screen.focus_control("skill_1") as Button).disabled, "hollow crown disables K1")
	screen.test_focus("skill_0")
	screen.test_direction(FocusController.DIRECTION_RIGHT)
	assertions.expect_equal("skill_2", screen.debug_state()["focus_id"], "four-direction move skips sealed K1")
	head.unique_id = &""
	screen.refresh_from_state(true)
	screen.test_focus("skill_0")
	screen.test_direction(FocusController.DIRECTION_RIGHT)
	assertions.expect_equal("skill_1", screen.debug_state()["focus_id"], "K1 becomes reachable after crown removal")

	SkillEquipService.apply_move(state, &"catalog", &"starfall", &"slot", 1)
	screen.refresh_from_state(true)
	screen.test_focus("skill_1")
	screen.test_accept()
	assertions.expect_false((screen.debug_state()["held_skill_source"] as Dictionary).is_empty(), "K1 can be lifted before crown seal")
	head.unique_id = &"hollow_crown"
	SkillEquipService.apply_crown_seal(state)
	screen.refresh_from_state(true)
	assertions.expect_true((screen.debug_state()["held_skill_source"] as Dictionary).is_empty(), "mid-lift crown seal cancels K1 operation")
	assertions.expect_true((screen.focus_control("skill_1") as Button).disabled, "mid-lift crown keeps K1 skipped")
	_cleanup_fixture(fixture, context)


func _test_result_failed_routes(assertions: Variant, context: Dictionary) -> void:
	var catalog: DefinitionCatalog = _loaded_catalog(assertions)
	if catalog == null:
		return
	var qa: Dictionary = QaScenarioFactory.build("result_controller", catalog)
	assertions.expect_true(qa.get("valid", false), "result_controller fixture valid")
	if not qa.get("valid", false):
		return
	var result_state: RunState = qa["state"] as RunState
	var result: RunSummaryScreen = await _spawn_summary(RESULT_SCENE, result_state, catalog, context)
	assertions.expect_true(result != null, "RESULT scene instantiates")
	if result != null:
		await _assert_summary_contract(assertions, result, "result", 12055, context)
		_cleanup_screen(result, context)

	var failed_state: RunState = qa["state"] as RunState
	failed_state.phase = GameTypes.RunPhase.FAILED
	failed_state.wave_number = 6
	failed_state.cleared_waves = 5
	failed_state.score_breakdown[&"combat_score"] = 7000
	failed_state.score_breakdown[&"final_build_score"] = 3055
	failed_state.score_breakdown[&"total"] = 10055
	var failed: RunSummaryScreen = await _spawn_summary(FAILED_SCENE, failed_state, catalog, context)
	assertions.expect_true(failed != null, "FAILED scene instantiates")
	if failed != null:
		await _assert_summary_contract(assertions, failed, "failed", 10055, context)
		assertions.expect_true("失敗ウェーブ  6" in str(failed.debug_state()["run_text"]), "FAILED displays failed wave")
		_cleanup_screen(failed, context)


func _assert_summary_contract(
	assertions: Variant,
	screen: RunSummaryScreen,
	prefix: String,
	expected_total: int,
	context: Dictionary,
) -> void:
	var expected_order := PackedStringArray([
		"%s_retry_same_seed" % prefix,
		"%s_retry_new_seed" % prefix,
		"%s_title" % prefix,
		"%s_exit" % prefix,
		"%s_settings" % prefix,
	])
	assertions.expect_equal(expected_order, screen.focus_order(), "%s exact five-element focus order" % prefix)
	assertions.expect_equal(expected_order[0], screen.debug_state()["focus_id"], "%s deferred initial focus" % prefix)
	for focus_id: String in expected_order:
		var specification: Dictionary = screen.neighbor_specification(focus_id)
		assertions.expect_equal(focus_id, specification[FocusController.DIRECTION_LEFT], "%s left self" % focus_id)
		assertions.expect_equal(focus_id, specification[FocusController.DIRECTION_RIGHT], "%s right self" % focus_id)
	var last_index: int = expected_order.size() - 1
	for index: int in range(expected_order.size()):
		var specification: Dictionary = screen.neighbor_specification(expected_order[index])
		assertions.expect_equal(expected_order[posmod(index - 1, expected_order.size())], specification[FocusController.DIRECTION_TOP], "%s top cycles" % expected_order[index])
		assertions.expect_equal(expected_order[(index + 1) % expected_order.size()], specification[FocusController.DIRECTION_BOTTOM], "%s bottom cycles" % expected_order[index])
	assertions.expect_equal(expected_order[last_index], screen.neighbor_specification(expected_order[0])[FocusController.DIRECTION_TOP], "%s first top reaches last" % prefix)
	assertions.expect_equal(expected_total, screen.debug_state()["total"], "%s displays expected total" % prefix)
	assertions.expect_equal(
		int(screen.debug_state()["combat_score"]) + int(screen.debug_state()["final_build_score"]),
		int(screen.debug_state()["total"]),
		"%s displayed subtotal sum equals total" % prefix,
	)
	var hits: Dictionary[String, int] = {"same": 0, "new": 0, "title": 0, "exit": 0}
	screen.retry_same_seed_requested.connect(func() -> void: hits["same"] += 1)
	screen.retry_new_seed_requested.connect(func() -> void: hits["new"] += 1)
	screen.title_requested.connect(func() -> void: hits["title"] += 1)
	screen.exit_requested.connect(func() -> void: hits["exit"] += 1)
	for index: int in range(4):
		screen.test_focus(expected_order[index])
		screen.test_accept()
	assertions.expect_equal({"same": 1, "new": 1, "title": 1, "exit": 1}, hits, "%s exposes all four command routes" % prefix)
	screen.test_focus(expected_order[4])
	screen.test_accept()
	await (context["tree"] as SceneTree).process_frame
	assertions.expect_true(screen.debug_state()["settings_open"], "%s settings route opens overlay" % prefix)
	(screen.get_node("%SettingsOverlay") as SettingsOverlay).close_overlay()
	await (context["tree"] as SceneTree).process_frame
	assertions.expect_equal(expected_order[4], screen.debug_state()["focus_id"], "%s settings closes to origin" % prefix)


func _spawn_inventory(
	assertions: Variant,
	context: Dictionary,
	state_override: RunState = null,
) -> Dictionary:
	var catalog: DefinitionCatalog = _loaded_catalog(assertions)
	if catalog == null:
		return {}
	var state: RunState = state_override
	if state == null:
		var qa: Dictionary = QaScenarioFactory.build("inventory_controller", catalog)
		assertions.expect_true(qa.get("valid", false), "inventory_controller fixture valid")
		if not qa.get("valid", false):
			return {}
		state = qa["state"] as RunState
	var screen := INVENTORY_SCENE.instantiate() as InventoryScreen
	assertions.expect_true(screen != null, "InventoryScreen scene instantiates")
	if screen == null:
		return {}
	screen.initialize(state, catalog)
	_connect_commands(screen, state, catalog)
	var tree: SceneTree = context["tree"] as SceneTree
	tree.root.add_child(screen)
	await tree.process_frame
	await tree.process_frame
	return {"screen": screen, "state": state, "catalog": catalog}


func _spawn_summary(
	scene: PackedScene,
	state: RunState,
	catalog: DefinitionCatalog,
	context: Dictionary,
) -> RunSummaryScreen:
	var screen := scene.instantiate() as RunSummaryScreen
	if screen == null:
		return null
	screen.initialize(state, catalog)
	var tree: SceneTree = context["tree"] as SceneTree
	tree.root.add_child(screen)
	await tree.process_frame
	await tree.process_frame
	return screen


func _connect_commands(screen: InventoryScreen, state: RunState, catalog: DefinitionCatalog) -> void:
	screen.item_move_requested.connect(_apply_item_move.bind(state, screen))
	screen.item_lock_requested.connect(_apply_item_lock.bind(state, screen))
	screen.sort_requested.connect(_apply_inventory_sort.bind(state, screen))
	screen.discard_requested.connect(_apply_discard.bind(state, screen))
	screen.fusion_requested.connect(_apply_fusion.bind(state, catalog, screen))
	screen.skill_move_requested.connect(_apply_skill_move.bind(state, screen))


func _apply_item_move(
	source: Dictionary,
	target: Dictionary,
	state: RunState,
	screen: InventoryScreen,
) -> void:
	var result: Dictionary = InventoryService.apply_move(
		state,
		StringName(source.get("kind", &"")),
		int(source.get("index", -1)),
		StringName(target.get("kind", &"")),
		int(target.get("index", -1)),
	)
	screen.apply_command_result(&"item_move", result)


func _apply_item_lock(item_id: String, state: RunState, screen: InventoryScreen) -> void:
	screen.apply_command_result(&"item_lock", InventoryService.toggle_lock(state, item_id))


func _apply_inventory_sort(state: RunState, screen: InventoryScreen) -> void:
	screen.apply_command_result(&"sort", InventoryService.sort_inventory_by_rarity(state))


func _apply_discard(
	item_ids: PackedStringArray,
	unique_confirmed: bool,
	state: RunState,
	screen: InventoryScreen,
) -> void:
	screen.apply_command_result(&"discard", InventoryService.discard(state, item_ids, unique_confirmed))


func _apply_fusion(
	material_ids: PackedStringArray,
	use_wild: bool,
	unique_confirmed: bool,
	state: RunState,
	catalog: DefinitionCatalog,
	screen: InventoryScreen,
) -> void:
	screen.apply_command_result(
		&"fusion",
		FusionCommitService.commit(state, material_ids, use_wild, unique_confirmed, catalog),
	)


func _apply_skill_move(
	source_kind: StringName,
	source_id: Variant,
	target_kind: StringName,
	target_id: Variant,
	state: RunState,
	screen: InventoryScreen,
) -> void:
	screen.apply_command_result(
		&"skill_move",
		SkillEquipService.apply_move(state, source_kind, source_id, target_kind, target_id),
	)


func _assert_focus_graph(assertions: Variant, screen: InventoryScreen, label: String) -> void:
	var focus_ids: PackedStringArray = screen.focus_ids()
	for focus_id: String in focus_ids:
		var control: Control = screen.focus_control(focus_id)
		if control == null or not control.visible or (control is BaseButton and (control as BaseButton).disabled):
			continue
		var specification: Dictionary = screen.neighbor_specification(focus_id)
		for direction: StringName in DIRECTIONS:
			assertions.expect_true(specification.has(direction), "%s %s has %s neighbor" % [label, focus_id, direction])
			screen.test_focus(focus_id)
			screen.test_direction(direction)
			var target_id: String = str(screen.debug_state()["focus_id"])
			var target: Control = screen.focus_control(target_id)
			assertions.expect_true(target != null and target.visible, "%s %s %s stays in visible graph" % [label, focus_id, direction])
			if target is BaseButton:
				assertions.expect_false((target as BaseButton).disabled, "%s %s %s skips disabled" % [label, focus_id, direction])


func _assert_neighbor_spec(
	assertions: Variant,
	screen: InventoryScreen,
	focus_id: String,
	top: String,
	bottom: String,
	left: String,
	right: String,
	label: String,
) -> void:
	assertions.expect_equal(
		{
			FocusController.DIRECTION_TOP: top,
			FocusController.DIRECTION_BOTTOM: bottom,
			FocusController.DIRECTION_LEFT: left,
			FocusController.DIRECTION_RIGHT: right,
		},
		screen.neighbor_specification(focus_id),
		"%s exact four-direction neighbor table" % label,
	)


func _assert_control_neighbor_paths(assertions: Variant, controls: Dictionary, label: String) -> void:
	for focus_id_value: Variant in controls:
		var focus_id: String = str(focus_id_value)
		var control: Control = controls[focus_id_value] as Control
		for property_name: String in [
			"focus_neighbor_top",
			"focus_neighbor_bottom",
			"focus_neighbor_left",
			"focus_neighbor_right",
			"focus_previous",
			"focus_next",
		]:
			assertions.expect_false((control.get(property_name) as NodePath).is_empty(), "%s %s has %s" % [label, focus_id, property_name])


func _assert_horizontally_visible(assertions: Variant, screen: InventoryScreen, index: int) -> void:
	var scroll: ScrollContainer = screen.get_node("%OverflowScroll") as ScrollContainer
	var card: Control = screen.focus_control("overflow_%d" % index)
	var viewport_rect: Rect2 = scroll.get_global_rect()
	var card_rect: Rect2 = card.get_global_rect()
	assertions.expect_true(
		card_rect.position.x >= viewport_rect.position.x - 0.5
		and card_rect.end.x <= viewport_rect.end.x + 0.5,
		"focused O%d is fully inside horizontal viewport (viewport=%s card=%s scroll=%d)" % [
			index,
			viewport_rect,
			card_rect,
			scroll.scroll_horizontal,
		],
	)


func _assert_fusion_candidate_vertically_visible(
	assertions: Variant,
	dialog: FusionDialog,
	item_id: String,
) -> void:
	var scroll: ScrollContainer = dialog.get_node("%FusionCandidateScroll") as ScrollContainer
	var focus_id: String = dialog.focus_id_for_candidate(item_id)
	var card: Control = dialog.focus_control(focus_id)
	var viewport_rect: Rect2 = scroll.get_global_rect()
	var card_rect: Rect2 = card.get_global_rect()
	assertions.expect_true(
		card_rect.position.y >= viewport_rect.position.y - 0.5
		and card_rect.end.y <= viewport_rect.end.y + 0.5,
		"focused %s is fully inside candidate viewport (viewport=%s card=%s scroll=%d)" % [
			item_id,
			viewport_rect,
			card_rect,
			scroll.scroll_vertical,
		],
	)


func _move_skill_with_controller(screen: InventoryScreen, source_id: String, target_id: String) -> void:
	screen.test_focus(source_id)
	screen.test_accept()
	screen.test_focus(target_id)
	screen.test_accept()


func _assert_skill_slots(
	assertions: Variant,
	state: RunState,
	expected: PackedInt32Array,
	label: String,
) -> void:
	var ids: Array[StringName] = [&"starfall", &"thousand_blades", &"soul_chain", &"bell_of_retribution"]
	var occupied: Dictionary[int, int] = {}
	for index: int in range(ids.size()):
		var skill: SkillState = state.skill_library.get(ids[index]) as SkillState
		assertions.expect_equal(expected[index], skill.equipped_slot, "%s exact %s slot" % [label, ids[index]])
		if skill.equipped_slot >= 0:
			occupied[skill.equipped_slot] = int(occupied.get(skill.equipped_slot, 0)) + 1
	for slot_index: int in range(2):
		assertions.expect_true(int(occupied.get(slot_index, 0)) <= 1, "%s slot %d has at most one skill" % [label, slot_index])


func _effect_affix(affix_id: StringName, value: float) -> AffixRoll:
	var affix := AffixRoll.new()
	affix.affix_id = affix_id
	affix.value = value
	return affix


func _overflow_state(assertions: Variant, count: int) -> RunState:
	var catalog: DefinitionCatalog = _loaded_catalog(assertions)
	if catalog == null:
		return null
	var qa: Dictionary = QaScenarioFactory.build("inventory_controller", catalog)
	if not qa.get("valid", false):
		return null
	var state: RunState = qa["state"] as RunState
	state.overflow.clear()
	for index: int in range(count):
		var item := ItemInstance.new()
		item.item_id = "qa-overflow-long-%02d" % index
		item.item_seed = index
		item.slot = (index % GameTypes.EquipmentSlot.size()) as GameTypes.EquipmentSlot
		item.main_weapon_type = (
			GameTypes.MainWeaponType.BOW
			if item.slot == GameTypes.EquipmentSlot.MAIN_WEAPON
			else GameTypes.MainWeaponType.UNCLASSIFIED
		)
		item.rarity = GameTypes.Rarity.COMMON
		item.display_name = "一時受取テスト%02d" % index
		state.overflow.append(item)
	return state


func _inventory_ids(state: RunState) -> PackedStringArray:
	return _item_ids(state.inventory)


func _item_ids(items: Array[ItemInstance]) -> PackedStringArray:
	var result := PackedStringArray()
	for item: ItemInstance in items:
		result.append(item.item_id if item != null else "")
	return result


func _rng_snapshot(state: RunState) -> Dictionary:
	return {
		"combat": state.rng_streams.combat_rng.state,
		"loot": state.rng_streams.loot_rng.state,
		"fusion": state.rng_streams.fusion_rng.state,
		"drop_serial": state.drop_serial,
	}


func _fusion_selection_signature(screen: InventoryScreen) -> Dictionary:
	var debug: Dictionary = screen.debug_state()
	return {
		"open": debug["fusion_open"],
		"rarity": debug["fusion_rarity"],
		"material_ids": (debug["fusion_material_ids"] as PackedStringArray).duplicate(),
		"use_wild": debug["fusion_use_wild"],
		"valid": debug["fusion_valid"],
	}


func _inventory_tooltip_state(screen: InventoryScreen) -> Dictionary:
	return screen.debug_state()["tooltip"] as Dictionary


func _inventory_tooltip_details(screen: InventoryScreen) -> String:
	return str(_inventory_tooltip_state(screen)["details"])


func _inventory_tooltip_warning(screen: InventoryScreen) -> String:
	return str(_inventory_tooltip_state(screen)["warning"])


func _fusion_tooltip_state(dialog: FusionDialog) -> Dictionary:
	return dialog.debug_state()["tooltip"] as Dictionary


func _fusion_tooltip_details(dialog: FusionDialog) -> String:
	return str(_fusion_tooltip_state(dialog)["details"])


func _replay_fusion_rarity_input(screen: InventoryScreen, action: StringName) -> void:
	screen.test_focus("FR")
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	event.strength = 1.0
	(screen.get_node("%FusionDialog") as FusionDialog)._input(event)


func _run_state_signature(state: RunState) -> Dictionary:
	var equipped_signatures: Array[Dictionary] = []
	for slot: int in range(GameTypes.EquipmentSlot.size()):
		equipped_signatures.append(_item_signature(state.equipped.get(slot) as ItemInstance))
	var inventory_signatures: Array[Dictionary] = []
	for item: ItemInstance in state.inventory:
		inventory_signatures.append(_item_signature(item))
	var overflow_signatures: Array[Dictionary] = []
	for item: ItemInstance in state.overflow:
		overflow_signatures.append(_item_signature(item))
	var skill_signatures: Array[Dictionary] = []
	var skill_ids: Array = state.skill_library.keys()
	skill_ids.sort()
	for skill_id_value: Variant in skill_ids:
		var skill: SkillState = state.skill_library[skill_id_value] as SkillState
		var pending_signatures: Array[Dictionary] = []
		for pending: PendingSkillActivation in skill.pending_queue:
			pending_signatures.append({
				"activation_serial": pending.activation_serial,
				"origin_event_serial": pending.origin_event_serial,
				"inherited_effect_chain": pending.inherited_effect_chain.duplicate(),
			})
		skill_signatures.append({
			"skill_id": skill.skill_id,
			"level": skill.level,
			"equipped_slot": skill.equipped_slot,
			"trigger_progress": skill.trigger_progress,
			"pending": pending_signatures,
		})
	var reward_signatures: Array[Dictionary] = []
	for reward: RewardRoll in state.unopened_rewards:
		reward_signatures.append({
			"reward_id": reward.reward_id,
			"wave_number": reward.wave_number,
			"acquired_tick": reward.acquired_tick,
			"guaranteed": reward.is_guaranteed_main_weapon,
			"kind": reward.kind,
			"equipment": _item_signature(reward.equipment),
			"skill_id": reward.skill_id,
			"rarity": reward.rarity_for_presentation,
			"revealed": reward.revealed,
		})
	var replay_signatures: Array[Dictionary] = []
	for replay: ScheduledProcReplay in state.scheduled_proc_replays:
		replay_signatures.append({
			"due_physics_tick": replay.due_physics_tick,
			"schedule_serial": replay.schedule_serial,
			"source_effect_id": replay.source_effect_id,
			"proc_effect_id": replay.proc_effect_id,
			"inherited_effect_chain": replay.inherited_effect_chain.duplicate(),
			"damage_snapshot": replay.damage_snapshot,
			"direction": replay.direction,
			"aim_distance": replay.aim_distance,
			"target_entity_id": replay.target_entity_id,
		})
	var damage_signatures: Array[Dictionary] = []
	for sample: DamageSample in state.recent_damage_samples:
		damage_signatures.append({
			"physics_tick": sample.physics_tick,
			"event_serial": sample.event_serial,
			"applied_damage": sample.applied_damage,
		})
	return {
		"run_seed": state.run_seed,
		"rng": _rng_snapshot(state),
		"phase": state.phase,
		"wave_number": state.wave_number,
		"wave_main_weapon_type": state.wave_main_weapon_type,
		"physics_tick": state.physics_tick,
		"time_remaining": state.time_remaining,
		"wave_cleared": state.wave_cleared,
		"boss_defeated": state.boss_defeated,
		"current_hp": state.current_hp,
		"max_hp": state.max_hp,
		"equipped": equipped_signatures,
		"inventory": inventory_signatures,
		"overflow": overflow_signatures,
		"skills": skill_signatures,
		"rewards": reward_signatures,
		"replays": replay_signatures,
		"wild_material_count": state.wild_material_count,
		"drop_serial": state.drop_serial,
		"next_entity_id": state.next_entity_id,
		"next_activation_serial": state.next_activation_serial,
		"next_event_serial": state.next_event_serial,
		"spawn_credit": state.spawn_credit,
		"coward_stationary_elapsed": state.coward_stationary_elapsed,
		"echo_progress_item_id": state.echo_progress_item_id,
		"echo_primary_attack_progress": state.echo_primary_attack_progress,
		"non_boss_spawned": state.non_boss_spawned,
		"wave_kills": state.wave_kills,
		"total_kills": state.total_kills,
		"normal_kills": state.normal_kills,
		"post_quota_kills": state.post_quota_kills,
		"elite_kills": state.elite_kills,
		"boss_kills": state.boss_kills,
		"cleared_waves": state.cleared_waves,
		"wave_chests": state.wave_chests,
		"total_chests": state.total_chests,
		"fusion_count": state.fusion_count,
		"peak_dps": state.peak_dps,
		"recent_damage_samples": damage_signatures,
		"score_breakdown": state.score_breakdown.duplicate(true),
	}


func _item_signature(item: ItemInstance) -> Dictionary:
	if item == null:
		return {}
	var affix_signatures: Array[Dictionary] = []
	for affix: AffixRoll in item.affixes:
		affix_signatures.append({"affix_id": affix.affix_id, "value": affix.value})
	return {
		"item_id": item.item_id,
		"item_seed": item.item_seed,
		"slot": item.slot,
		"main_weapon_type": item.main_weapon_type,
		"rarity": item.rarity,
		"affixes": affix_signatures,
		"unique_id": item.unique_id,
		"display_name": item.display_name,
		"locked": item.locked,
	}


func _loaded_catalog(assertions: Variant) -> DefinitionCatalog:
	if _catalog == null:
		_catalog = DefinitionCatalog.new()
		var valid: bool = _catalog.load_and_validate()
		assertions.expect_true(valid, "inventory inventory UI catalog valid: %s" % _catalog.error_text)
	return _catalog if _catalog.is_valid else null


func _cleanup_fixture(fixture: Dictionary, context: Dictionary) -> void:
	_cleanup_screen(fixture.get("screen") as Node, context)


func _cleanup_screen(screen: Node, context: Dictionary) -> void:
	if screen == null:
		return
	var tree: SceneTree = context["tree"] as SceneTree
	if screen.get_parent() == tree.root:
		tree.root.remove_child(screen)
	screen.free()
