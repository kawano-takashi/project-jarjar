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
		"inventory_controller_mouse_bulk_fusion_and_discard_contract",
		"fusion_dialog_exact_controller_contract",
		"inventory_exact_skill_sequence_and_crown_contract",
		"result_failed_summary_focus_and_routes_contract",
	])


func run_test(test_name: String, assertions: Variant, context: Dictionary) -> void:
	match test_name:
		"inventory_focus_modal_overflow_contract":
			await _test_focus_modal_overflow(assertions, context)
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
	_assert_neighbor_spec(assertions, screen, "action_5", "overflow_3", "skill_5", "action_4", "action_0", "A5")
	_assert_neighbor_spec(assertions, screen, "skill_0", "action_0", "equip_0", "skill_5", "skill_1", "K0")
	_assert_focus_graph(assertions, screen, "normal inventory")
	assertions.expect_true((screen.focus_control("action_4") as Button).disabled, "overflow disables next-wave action")
	screen.test_focus("action_3")
	screen.test_direction(FocusController.DIRECTION_RIGHT)
	assertions.expect_equal("action_5", screen.debug_state()["focus_id"], "disabled next-wave action is skipped")

	screen.test_focus("action_5")
	screen.test_accept()
	await (context["tree"] as SceneTree).process_frame
	assertions.expect_true(screen.debug_state()["settings_open"], "inventory settings opens from A")
	var settings: SettingsOverlay = screen.get_node("%SettingsOverlay") as SettingsOverlay
	settings.close_overlay()
	await (context["tree"] as SceneTree).process_frame
	assertions.expect_equal("action_5", screen.debug_state()["focus_id"], "settings closes to exact origin")

	screen.test_focus("grid_0")
	screen.test_open_bulk()
	await (context["tree"] as SceneTree).process_frame
	var bulk: BulkSelectDialog = screen.get_node("%BulkSelectDialog") as BulkSelectDialog
	assertions.expect_equal(
		PackedStringArray(["bulk_common", "bulk_rare", "bulk_epic", "bulk_legendary", "bulk_cancel"]),
		bulk.focus_order(),
		"BulkSelectDialog exact focus order",
	)
	assertions.expect_equal("bulk_common", bulk.debug_state()["focus_id"], "BulkSelectDialog starts at last item rarity")
	_assert_control_neighbor_paths(assertions, bulk.focus_controls(), "bulk")
	bulk.get_node("%BulkCancel").emit_signal("pressed")
	await (context["tree"] as SceneTree).process_frame
	assertions.expect_equal("action_0", screen.debug_state()["focus_id"], "bulk cancel restores A0")

	screen.test_focus("action_2")
	screen.test_accept()
	await (context["tree"] as SceneTree).process_frame
	assertions.expect_true(screen.debug_state()["fusion_open"], "A2 opens FusionDialog")
	assertions.expect_equal("FR", screen.debug_state()["focus_id"], "FusionDialog starts at FR")
	_assert_neighbor_spec(assertions, screen, "FR", "FA3", "F0", "FR", "FR", "FR")
	_assert_neighbor_spec(assertions, screen, "F1", "FR", "grid_2", "F0", "F2", "F1")
	_assert_neighbor_spec(assertions, screen, "grid_0", "F0", "grid_6", "grid_5", "grid_1", "Fusion G0,0")
	_assert_neighbor_spec(assertions, screen, "overflow_0", "grid_30", "FA0", "overflow_3", "overflow_1", "Fusion O0")
	_assert_neighbor_spec(assertions, screen, "FA3", "overflow_3", "FR", "FA2", "FA0", "FA3")
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
	_cleanup_fixture(overflow_fixture, context)

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
	assertions.expect_true("比較:" in str(controller_screen.debug_state()["comparison"]), "controller focus updates comparison")
	controller_screen.test_accept()
	controller_screen.test_focus("grid_6")
	controller_screen.test_accept()
	mouse_screen.test_mouse_drop(
		{"drag_type": &"item", "kind": &"inventory", "index": 0, "item_id": "qa-inventory-00"},
		{"kind": &"inventory", "index": 6},
	)
	assertions.expect_equal(_inventory_ids(controller_state), _inventory_ids(mouse_state), "mouse drag and controller lift produce identical inventory")
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
	full_controller_screen.test_accept()
	assertions.expect_equal(full_controller_main_id, full_controller_state.equipped[GameTypes.EquipmentSlot.MAIN_WEAPON].item_id, "same E main weapon standalone unequip is rejected")
	assertions.expect_equal(InventoryService.MAIN_WEAPON_REQUIRED_MESSAGE, full_controller_screen.debug_state()["status"], "main weapon standalone rejection displays fixed message")
	assertions.expect_false((full_controller_screen.debug_state()["held_item_source"] as Dictionary).is_empty(), "failed main weapon standalone move remains held until B")
	full_controller_screen.test_cancel()
	assertions.expect_true((full_controller_screen.debug_state()["held_item_source"] as Dictionary).is_empty(), "B cancels rejected main weapon lift")
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
	controller_fusion_screen.test_focus("grid_0")
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
	unique_screen.test_accept()
	await (context["tree"] as SceneTree).process_frame
	assertions.expect_true(unique_screen.debug_state()["confirmation_open"], "unique discard opens standard confirmation")
	assertions.expect_equal("dialog_cancel", (unique_screen.get_node("%ConfirmationDialog") as JarjarConfirmationDialog).debug_state()["focus_id"], "confirmation starts on cancel")
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
	fusion_screen.fusion_requested.connect(func(ids: PackedStringArray, use_wild: bool, confirmed: bool) -> void:
		fusion_requests.append({"ids": ids.duplicate(), "wild": use_wild, "confirmed": confirmed})
	)
	fusion_screen.test_focus("action_2")
	fusion_screen.test_accept()
	fusion_screen.test_focus("FA0")
	fusion_screen.test_accept()
	assertions.expect_equal(
		PackedStringArray(["qa-inventory-00", "qa-inventory-01", "qa-inventory-02"]),
		fusion_screen.debug_state()["fusion_material_ids"],
		"fusion auto-fill uses exact fixed Common IDs",
	)
	fusion_screen.test_focus("FA2")
	fusion_screen.test_accept()
	assertions.expect_equal(1, fusion_requests.size(), "fusion confirm emits one command")
	if not fusion_requests.is_empty():
		assertions.expect_equal(PackedStringArray(["qa-inventory-00", "qa-inventory-01", "qa-inventory-02"]), fusion_requests[0]["ids"], "fusion command preserves exact material order")
	assertions.expect_equal(1, fusion_state.fusion_count, "fusion command commits once")
	assertions.expect_equal("action_2", fusion_screen.debug_state()["focus_id"], "fusion success closes to A2")
	assertions.expect_equal(0, fusion_screen.debug_state()["pointer_event_count"], "fusion controller flow emits zero pointer events")
	_cleanup_fixture(fusion_fixture, context)

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
	assertions.expect_equal("action_2", wild_screen.debug_state()["focus_id"], "wild fusion B discards reservation and returns A2")
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
	for index: int in [18, 19, 33]:
		rare_screen.test_focus("grid_%d" % index)
		rare_screen.test_accept()
	assertions.expect_equal(
		PackedStringArray(["qa-inventory-18", "qa-inventory-19", "qa-inventory-33"]),
		rare_screen.debug_state()["fusion_material_ids"],
		"controller assigns exact Rare IDs to F0, F1, F2",
	)
	assertions.expect_equal(rare_before, _run_state_signature(rare_state), "selecting F materials does not remove or mutate source slots before commit")
	assertions.expect_true((rare_screen.get_node("%FusionDialog") as FusionDialog).debug_state()["confirm_enabled"], "FA2 enables for exact three Rare materials")
	rare_screen.test_focus("FA2")
	rare_screen.test_accept()
	assertions.expect_true(rare_screen.debug_state()["confirmation_open"], "Rare fusion containing unique opens named confirmation")
	var fusion_selection_before_cancel: Dictionary = _fusion_selection_signature(rare_screen)
	rare_screen.test_confirm_dialog(false)
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
	assertions.expect_equal(0, rare_screen.debug_state()["pointer_event_count"], "exact Rare fusion controller flow emits no pointer events")
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
		wild_screen.test_focus("grid_%d" % index)
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
	assertions.expect_equal(0, wild_screen.debug_state()["pointer_event_count"], "exact wild fusion controller flow emits no pointer events")
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
		rejection_screen.test_focus("grid_%d" % rejected_index)
		rejection_screen.test_accept()
		assertions.expect_equal(PackedStringArray(), rejection_screen.debug_state()["fusion_material_ids"], "locked/Legendary/mismatched material %d is rejected" % rejected_index)
	rejection_screen.test_focus("grid_3")
	rejection_screen.test_accept()
	assertions.expect_equal(PackedStringArray(["qa-inventory-03"]), rejection_screen.debug_state()["fusion_material_ids"], "valid Common enters F0")
	rejection_screen.test_focus("F0")
	rejection_screen.test_accept()
	assertions.expect_equal(PackedStringArray(), rejection_screen.debug_state()["fusion_material_ids"], "A on F removes selected material")
	for index: int in [3, 4]:
		rejection_screen.test_focus("grid_%d" % index)
		rejection_screen.test_accept()
	_replay_fusion_rarity_input(rejection_screen, "ui_right")
	assertions.expect_equal(GameTypes.Rarity.RARE, rejection_screen.debug_state()["fusion_rarity"], "controller FR right changes Common to Rare")
	assertions.expect_equal(PackedStringArray(), rejection_screen.debug_state()["fusion_material_ids"], "FR change clears all F material slots")
	assertions.expect_false(rejection_screen.debug_state()["fusion_use_wild"], "FR change clears wild reservation")
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
		controller_screen.test_focus("grid_%d" % index)
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
		for property_name: String in ["focus_neighbor_top", "focus_neighbor_bottom", "focus_neighbor_left", "focus_neighbor_right"]:
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
	var result := PackedStringArray()
	for item: ItemInstance in state.inventory:
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
