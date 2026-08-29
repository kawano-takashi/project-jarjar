extends RefCounted


const TITLE_SCENE: PackedScene = preload("res://scenes/ui/title_screen.tscn")
const REWARD_SCENE: PackedScene = preload("res://scenes/ui/reward_reveal_screen.tscn")
const INVENTORY_SCENE: PackedScene = preload("res://scenes/ui/inventory_screen.tscn")
const RESULT_SCENE: PackedScene = preload("res://scenes/ui/result_screen.tscn")
const FAILED_SCENE: PackedScene = preload("res://scenes/ui/failed_screen.tscn")
const TEST_JOYPAD_DEVICE: int = 63
const SETTINGS_FOCUS_ORDER: Array[String] = [
	"settings_master",
	"settings_music",
	"settings_sfx",
	"settings_reduce_motion",
	"settings_reduce_flashes",
	"settings_vibration",
	"settings_tutorial_again",
	"settings_close",
]

var _catalog: DefinitionCatalog = null


func test_names() -> PackedStringArray:
	return PackedStringArray([
		"controller_only_primary_routes_and_zero_pointer_contract",
		"left_stick_focus_moves_once_per_tilt",
	])


func run_test(test_name: String, assertions: Variant, context: Dictionary) -> void:
	match test_name:
		"controller_only_primary_routes_and_zero_pointer_contract":
			await _test_controller_only_primary_routes(assertions, context)
		"left_stick_focus_moves_once_per_tilt":
			await _test_left_stick_focus_moves_once_per_tilt(assertions, context)
		_:
			assertions.expect_true(false, "registered release readiness controller-only scenario test")


func _test_controller_only_primary_routes(assertions: Variant, context: Dictionary) -> void:
	var catalog: DefinitionCatalog = _loaded_catalog(assertions)
	if catalog == null:
		return
	var pointer_event_count: Array[int] = [0]
	await _exercise_title_and_all_settings(assertions, context, pointer_event_count)
	await _exercise_reward(assertions, context, catalog, pointer_event_count)
	await _exercise_inventory(assertions, context, catalog, pointer_event_count)
	await _exercise_summary(
		assertions,
		context,
		catalog,
		RESULT_SCENE,
		"result",
		GameTypes.RunPhase.RESULT,
		pointer_event_count,
	)
	await _exercise_summary(
		assertions,
		context,
		catalog,
		FAILED_SCENE,
		"failed",
		GameTypes.RunPhase.FAILED,
		pointer_event_count,
	)
	assertions.expect_equal(
		0,
		pointer_event_count[0],
		"release readiness controller-only scenario pointer event count=0",
	)


func _test_left_stick_focus_moves_once_per_tilt(
	assertions: Variant,
	context: Dictionary,
) -> void:
	var tree: SceneTree = context["tree"] as SceneTree
	await _neutralize_left_stick(tree)

	var title := TITLE_SCENE.instantiate() as Control
	assertions.expect_true(title != null, "TITLE scene instantiates for left-stick regression")
	if title == null:
		return
	tree.root.add_child(title)
	await tree.process_frame
	await tree.process_frame
	var title_start := title.get_node("%TitleStart") as Button
	var title_settings := title.get_node("%TitleSettings") as Button
	var title_exit := title.get_node("%TitleExit") as Button
	assertions.expect_equal(
		title_start,
		title.get_viewport().gui_get_focus_owner(),
		"TITLE left-stick regression starts on start",
	)
	await _send_joy_motion(tree, JOY_AXIS_LEFT_Y, 0.49)
	assertions.expect_equal(
		title_start,
		title.get_viewport().gui_get_focus_owner(),
		"TITLE left stick below deadzone does not move focus",
	)
	await _send_joy_motion(tree, JOY_AXIS_LEFT_Y, 0.75)
	assertions.expect_equal(
		title_settings,
		title.get_viewport().gui_get_focus_owner(),
		"TITLE first downward tilt moves exactly one focus target",
	)
	await _send_joy_motion(tree, JOY_AXIS_LEFT_Y, 0.82)
	await _send_joy_motion(tree, JOY_AXIS_LEFT_Y, 0.93)
	assertions.expect_equal(
		title_settings,
		title.get_viewport().gui_get_focus_owner(),
		"TITLE held downward tilt does not repeat focus movement",
	)
	await _send_joy_motion(tree, JOY_AXIS_LEFT_Y, 0.0)
	await _send_joy_motion(tree, JOY_AXIS_LEFT_Y, 0.75)
	assertions.expect_equal(
		title_exit,
		title.get_viewport().gui_get_focus_owner(),
		"TITLE neutral rearms the next downward tilt",
	)
	await _neutralize_left_stick(tree)
	await _remove_screen(title, tree)

	var catalog: DefinitionCatalog = _loaded_catalog(assertions)
	if catalog == null:
		return
	var qa: Dictionary = QaScenarioFactory.build("inventory_controller", catalog)
	assertions.expect_true(qa.get("valid", false), "INVENTORY left-stick fixture is valid")
	if not qa.get("valid", false):
		return
	var screen := INVENTORY_SCENE.instantiate() as InventoryScreen
	assertions.expect_true(screen != null, "INVENTORY scene instantiates for left-stick regression")
	if screen == null:
		return
	screen.initialize(qa["state"] as RunState, catalog)
	tree.root.add_child(screen)
	await tree.process_frame
	await tree.process_frame
	assertions.expect_true(screen.test_focus("grid_0"), "INVENTORY focuses grid_0 for left-stick test")
	await _send_joy_motion(tree, JOY_AXIS_LEFT_X, 0.75)
	assertions.expect_equal(
		"grid_1",
		screen.debug_state()["focus_id"],
		"INVENTORY first right tilt moves exactly one grid cell",
	)
	await _send_joy_motion(tree, JOY_AXIS_LEFT_X, 0.82)
	await _send_joy_motion(tree, JOY_AXIS_LEFT_X, 0.93)
	assertions.expect_equal(
		"grid_1",
		screen.debug_state()["focus_id"],
		"INVENTORY held right tilt does not repeat focus movement",
	)
	await _send_joy_motion(tree, JOY_AXIS_LEFT_X, 0.0)
	await _send_joy_motion(tree, JOY_AXIS_LEFT_X, 0.75)
	assertions.expect_equal(
		"grid_2",
		screen.debug_state()["focus_id"],
		"INVENTORY neutral rearms the next right tilt",
	)
	await _send_joy_motion(tree, JOY_AXIS_LEFT_X, 0.0)
	await _send_joy_button(tree, JOY_BUTTON_DPAD_RIGHT, true)
	assertions.expect_equal(
		"grid_3",
		screen.debug_state()["focus_id"],
		"INVENTORY D-pad navigation remains digital and immediate",
	)
	await _send_joy_button(tree, JOY_BUTTON_DPAD_RIGHT, false)
	var shifted_right := _key_event(KEY_RIGHT, true, true)
	assertions.expect_equal(
		FocusController.DIRECTION_RIGHT,
		FocusController.direction_for_event(shifted_right),
		"modified arrow keys retain the previous non-exact action match",
	)
	Input.parse_input_event(shifted_right)
	await tree.process_frame
	assertions.expect_equal(
		"grid_4",
		screen.debug_state()["focus_id"],
		"INVENTORY Shift+Right remains a valid keyboard focus move",
	)
	Input.parse_input_event(_key_event(KEY_RIGHT, false, true))
	await tree.process_frame

	assertions.expect_true(screen.test_focus("action_2"), "INVENTORY focuses normal fusion action")
	screen.test_accept()
	await tree.process_frame
	await tree.process_frame
	assertions.expect_true(screen.test_focus("FR"), "fusion focuses the rarity selector")
	var rarity_values: Array[GameTypes.Rarity] = [
		GameTypes.Rarity.COMMON,
		GameTypes.Rarity.RARE,
		GameTypes.Rarity.EPIC,
	]
	var initial_rarity: GameTypes.Rarity = screen.debug_state()["fusion_rarity"]
	var expected_rarity: GameTypes.Rarity = rarity_values[
		(rarity_values.find(initial_rarity) + 1) % rarity_values.size()
	]
	await _send_joy_motion(tree, JOY_AXIS_LEFT_X, 0.75)
	assertions.expect_equal(
		expected_rarity,
		screen.debug_state()["fusion_rarity"],
		"fusion first right tilt changes rarity exactly once",
	)
	await _send_joy_motion(tree, JOY_AXIS_LEFT_X, 0.82)
	await _send_joy_motion(tree, JOY_AXIS_LEFT_X, 0.93)
	assertions.expect_equal(
		expected_rarity,
		screen.debug_state()["fusion_rarity"],
		"fusion held right tilt does not cycle rarity",
	)
	await _neutralize_left_stick(tree)
	await _remove_screen(screen, tree)


func _exercise_title_and_all_settings(
	assertions: Variant,
	context: Dictionary,
	pointer_event_count: Array[int],
) -> void:
	var tree: SceneTree = context["tree"] as SceneTree
	var settings_store: Variant = context["settings_store"]
	settings_store.tutorial_seen = true
	var title := TITLE_SCENE.instantiate() as Control
	assertions.expect_true(title != null, "TITLE scene instantiates for controller-only acceptance")
	if title == null:
		return
	tree.root.add_child(title)
	await tree.process_frame
	await tree.process_frame
	_instrument_pointer_events(title, pointer_event_count)

	var title_start := title.get_node("%TitleStart") as Button
	var title_settings := title.get_node("%TitleSettings") as Button
	assertions.expect_equal(
		PackedStringArray(["title_start", "title_settings", "title_exit"]),
		title.call("focus_order"),
		"TITLE exposes the 3.12 controller focus order",
	)
	assertions.expect_equal(
		title_start,
		title.get_viewport().gui_get_focus_owner(),
		"TITLE starts focused on start",
	)
	var next_from_start: Control = title_start.get_node_or_null(title_start.focus_neighbor_bottom) as Control
	assertions.expect_equal(title_settings, next_from_start, "TITLE down reaches settings")
	if next_from_start != null:
		next_from_start.grab_focus()
	title_settings.emit_signal("pressed")
	await tree.process_frame

	var overlay := title.get_node("%SettingsOverlay") as SettingsOverlay
	assertions.expect_true(overlay.visible, "TITLE A on settings opens the overlay")
	assertions.expect_equal(
		PackedStringArray(SETTINGS_FOCUS_ORDER),
		overlay.focus_order(),
		"settings exposes all eight 3.12 focus elements",
	)
	assertions.expect_equal(
		overlay.initial_focus_control(),
		title.get_viewport().gui_get_focus_owner(),
		"settings starts focused on master volume",
	)
	_assert_settings_background_isolated(
		assertions,
		title_settings,
		overlay,
		"TITLE settings",
	)

	var visited := PackedStringArray()
	var control: Control = title.get_viewport().gui_get_focus_owner()
	for index: int in range(SETTINGS_FOCUS_ORDER.size()):
		var focus_id: String = SETTINGS_FOCUS_ORDER[index]
		assertions.expect_true(control != null, "settings controller reaches %s" % focus_id)
		if control == null:
			break
		assertions.expect_equal(
			focus_id,
			str(control.get_meta("focus_id", "")),
			"settings down traversal reaches %s in order" % focus_id,
		)
		visited.append(focus_id)
		match focus_id:
			"settings_master", "settings_music", "settings_sfx":
				var slider := control as HSlider
				slider.value -= slider.step
			"settings_reduce_motion", "settings_reduce_flashes", "settings_vibration":
				var toggle := control as CheckButton
				toggle.button_pressed = not toggle.button_pressed
			"settings_tutorial_again":
				(control as Button).emit_signal("pressed")
			"settings_close":
				pass
		if index + 1 < SETTINGS_FOCUS_ORDER.size():
			var next_control: Control = control.get_node_or_null(control.focus_neighbor_bottom) as Control
			assertions.expect_true(next_control != null, "%s has a controller-down target" % focus_id)
			control = next_control
			if control != null:
				control.grab_focus()
	assertions.expect_equal(
		PackedStringArray(SETTINGS_FOCUS_ORDER),
		visited,
		"controller visits all eight settings elements",
	)
	assertions.expect_float(0.99, float(settings_store.master_volume), "controller changes master volume")
	assertions.expect_float(0.79, float(settings_store.music_volume), "controller changes music volume")
	assertions.expect_float(0.89, float(settings_store.sfx_volume), "controller changes SFX volume")
	assertions.expect_true(bool(settings_store.reduce_motion), "controller changes Reduce Motion")
	assertions.expect_true(bool(settings_store.reduce_flashes), "controller changes Reduce Flashes")
	assertions.expect_false(bool(settings_store.controller_vibration), "controller changes vibration")
	assertions.expect_false(bool(settings_store.tutorial_seen), "controller requests tutorial again")

	_send_cancel_to_settings(overlay)
	await tree.process_frame
	assertions.expect_false(overlay.visible, "settings B closes the overlay")
	assertions.expect_equal(
		title_settings,
		title.get_viewport().gui_get_focus_owner(),
		"settings B restores exact TITLE origin focus",
	)

	var start_hits: Array[int] = [0]
	title.connect(&"start_requested", func() -> void: start_hits[0] += 1)
	var previous_from_settings: Control = (
		title_settings.get_node_or_null(title_settings.focus_neighbor_top) as Control
	)
	assertions.expect_equal(title_start, previous_from_settings, "TITLE up returns to start")
	if previous_from_settings != null:
		previous_from_settings.grab_focus()
	title_start.emit_signal("pressed")
	assertions.expect_equal(1, start_hits[0], "TITLE start emits exactly one controller command")
	assertions.expect_equal(0, pointer_event_count[0], "TITLE/settings pointer event count=0")
	await _remove_screen(title, tree)


func _exercise_reward(
	assertions: Variant,
	context: Dictionary,
	catalog: DefinitionCatalog,
	pointer_event_count: Array[int],
) -> void:
	var qa: Dictionary = QaScenarioFactory.build("reward_controls", catalog)
	assertions.expect_true(qa.get("valid", false), "REWARD_REVEAL controller fixture is valid")
	if not qa.get("valid", false):
		return
	var screen := REWARD_SCENE.instantiate() as RewardRevealScreen
	assertions.expect_true(screen != null, "REWARD_REVEAL scene instantiates")
	if screen == null:
		return
	screen.set_automatic_progression(false)
	screen.initialize(qa["state"] as RunState)
	var tree: SceneTree = context["tree"] as SceneTree
	tree.root.add_child(screen)
	await tree.process_frame
	await tree.process_frame
	_instrument_pointer_events(screen, pointer_event_count)
	assertions.expect_equal(
		GameTypes.RunPhase.REWARD_REVEAL,
		(qa["state"] as RunState).phase,
		"REWARD_REVEAL route starts in the expected phase",
	)

	screen.test_accept_press("reward_speed_proxy")
	screen.test_tick(RewardRevealScreen.HOLD_THRESHOLD_SECONDS)
	assertions.expect_true(screen.debug_state()["fast_open"], "reward A hold reaches 4x mode")
	screen.test_accept_release()
	screen.test_accept_press("reward_settings")
	screen.test_tick(0.10)
	screen.test_accept_release()
	assertions.expect_true(screen.debug_state()["settings_open"], "reward controller opens settings")
	var overlay := screen.get_node("%SettingsOverlay") as SettingsOverlay
	_assert_settings_background_isolated(
		assertions,
		screen.get_node("%RewardSettings") as Control,
		overlay,
		"REWARD settings",
	)
	_send_cancel_to_settings(overlay)
	await tree.process_frame
	assertions.expect_false(screen.debug_state()["settings_open"], "reward settings B closes overlay")
	assertions.expect_equal(
		"reward_settings",
		screen.debug_state()["focus_id"],
		"reward settings B restores exact origin focus",
	)
	screen.test_press_reward_open_all_action()
	screen.test_tick(0.75)
	assertions.expect_true(screen.reveal_controller().is_complete(), "reward Y opens all fixed rewards")
	assertions.expect_equal(
		0,
		screen.debug_state()["pointer_event_count"],
		"REWARD_REVEAL controller-only pointer event count=0",
	)
	assertions.expect_equal(0, pointer_event_count[0], "REWARD_REVEAL observed pointer event count=0")
	await _remove_screen(screen, tree)


func _exercise_inventory(
	assertions: Variant,
	context: Dictionary,
	catalog: DefinitionCatalog,
	pointer_event_count: Array[int],
) -> void:
	var qa: Dictionary = QaScenarioFactory.build("inventory_controller", catalog)
	assertions.expect_true(qa.get("valid", false), "INVENTORY controller fixture is valid")
	if not qa.get("valid", false):
		return
	var state: RunState = qa["state"] as RunState
	var screen := INVENTORY_SCENE.instantiate() as InventoryScreen
	assertions.expect_true(screen != null, "INVENTORY scene instantiates")
	if screen == null:
		return
	screen.initialize(state, catalog)
	screen.item_move_requested.connect(_apply_item_move.bind(state, screen))
	screen.skill_move_requested.connect(_apply_skill_move.bind(state, screen))
	var tree: SceneTree = context["tree"] as SceneTree
	tree.root.add_child(screen)
	await tree.process_frame
	await tree.process_frame
	_instrument_pointer_events(screen, pointer_event_count)
	assertions.expect_equal(GameTypes.RunPhase.INVENTORY, state.phase, "INVENTORY route starts in phase")

	var grid_0_before: ItemInstance = state.inventory[0]
	var grid_6_before: ItemInstance = state.inventory[6]
	screen.test_focus("grid_0")
	screen.test_accept()
	screen.test_focus("grid_6")
	screen.test_accept()
	assertions.expect_equal(grid_0_before, state.inventory[6], "inventory controller moves item G0 to G6")
	assertions.expect_equal(grid_6_before, state.inventory[0], "inventory controller preserves displaced item")

	var soul_chain := state.skill_library.get(&"soul_chain") as SkillState
	assertions.expect_equal(-1, soul_chain.equipped_slot, "inventory skill fixture starts unequipped")
	screen.test_focus("skill_4")
	screen.test_accept()
	screen.test_focus("skill_0")
	screen.test_accept()
	assertions.expect_equal(0, soul_chain.equipped_slot, "inventory controller equips skill into K0")
	assertions.expect_true(
		(screen.debug_state()["held_skill_source"] as Dictionary).is_empty(),
		"inventory skill controller command completes",
	)
	screen.test_focus("grid_1")
	screen.test_accept()
	var tutorial_overlay := TutorialOverlay.new()
	var tutorial_cancel_observed: Array[int] = [0]
	tutorial_overlay.cancel_input_observed.connect(
		func() -> void: tutorial_cancel_observed[0] += 1
	)
	tree.root.add_child(tutorial_overlay)
	await tree.process_frame
	var cancel_event := InputEventAction.new()
	cancel_event.action = &"ui_cancel"
	cancel_event.pressed = true
	tree.root.push_input(cancel_event)
	await tree.process_frame
	assertions.expect_equal(
		0,
		tutorial_cancel_observed[0],
		"handled INVENTORY B does not reach the tutorial overlay",
	)
	assertions.expect_true(
		(screen.debug_state()["held_item_source"] as Dictionary).is_empty(),
		"first B cancels only the active INVENTORY item lift",
	)
	screen.test_focus("action_2")
	screen.test_accept()
	await tree.process_frame
	assertions.expect_true(screen.debug_state()["fusion_open"], "fusion modal opens above the remaining tutorial")
	var modal_cancel_event := InputEventAction.new()
	modal_cancel_event.action = &"ui_cancel"
	modal_cancel_event.pressed = true
	tree.root.push_input(modal_cancel_event)
	await tree.process_frame
	assertions.expect_false(screen.debug_state()["fusion_open"], "next B closes only the top fusion modal")
	assertions.expect_equal(
		0,
		tutorial_cancel_observed[0],
		"fusion-consumed B does not also dismiss the tutorial",
	)
	var second_cancel_event := InputEventAction.new()
	second_cancel_event.action = &"ui_cancel"
	second_cancel_event.pressed = true
	tree.root.push_input(second_cancel_event)
	await tree.process_frame
	assertions.expect_equal(
		1,
		tutorial_cancel_observed[0],
		"following unhandled B reaches the remaining tutorial overlay",
	)
	tree.root.remove_child(tutorial_overlay)
	tutorial_overlay.free()
	assertions.expect_equal(
		0,
		screen.debug_state()["pointer_event_count"],
		"INVENTORY item/skill controller-only pointer event count=0",
	)
	assertions.expect_equal(0, pointer_event_count[0], "INVENTORY observed pointer event count=0")
	await _remove_screen(screen, tree)


func _exercise_summary(
	assertions: Variant,
	context: Dictionary,
	catalog: DefinitionCatalog,
	scene: PackedScene,
	prefix: String,
	phase: GameTypes.RunPhase,
	pointer_event_count: Array[int],
) -> void:
	var qa: Dictionary = QaScenarioFactory.build("result_controller", catalog)
	assertions.expect_true(qa.get("valid", false), "%s controller fixture is valid" % prefix)
	if not qa.get("valid", false):
		return
	var state: RunState = qa["state"] as RunState
	state.phase = phase
	if phase == GameTypes.RunPhase.FAILED:
		state.wave_number = 6
		state.cleared_waves = 5
	var screen := scene.instantiate() as RunSummaryScreen
	assertions.expect_true(screen != null, "%s scene instantiates" % prefix.to_upper())
	if screen == null:
		return
	screen.initialize(state, catalog)
	var tree: SceneTree = context["tree"] as SceneTree
	tree.root.add_child(screen)
	await tree.process_frame
	await tree.process_frame
	_instrument_pointer_events(screen, pointer_event_count)

	var expected_order := PackedStringArray([
		"%s_retry_same_seed" % prefix,
		"%s_retry_new_seed" % prefix,
		"%s_title" % prefix,
		"%s_exit" % prefix,
		"%s_settings" % prefix,
	])
	assertions.expect_equal(expected_order, screen.focus_order(), "%s exposes all five routes" % prefix)
	var hits: Dictionary[String, int] = {"same": 0, "new": 0, "title": 0, "exit": 0}
	screen.retry_same_seed_requested.connect(func() -> void: hits["same"] += 1)
	screen.retry_new_seed_requested.connect(func() -> void: hits["new"] += 1)
	screen.title_requested.connect(func() -> void: hits["title"] += 1)
	screen.exit_requested.connect(func() -> void: hits["exit"] += 1)
	for index: int in range(4):
		screen.test_focus(expected_order[index])
		screen.test_accept()
	assertions.expect_equal(
		{"same": 1, "new": 1, "title": 1, "exit": 1},
		hits,
		"%s controller activates each primary command exactly once" % prefix,
	)
	screen.test_focus(expected_order[4])
	screen.test_accept()
	await tree.process_frame
	assertions.expect_true(screen.debug_state()["settings_open"], "%s controller opens settings" % prefix)
	var settings_overlay := screen.get_node("%SettingsOverlay") as SettingsOverlay
	_assert_settings_background_isolated(
		assertions,
		screen.focus_control(expected_order[4]),
		settings_overlay,
		"%s settings" % prefix,
	)
	_send_cancel_to_settings(settings_overlay)
	await tree.process_frame
	assertions.expect_false(screen.debug_state()["settings_open"], "%s settings B closes overlay" % prefix)
	assertions.expect_equal(
		expected_order[4],
		screen.debug_state()["focus_id"],
		"%s settings B restores exact origin focus" % prefix,
	)
	assertions.expect_equal(
		0,
		pointer_event_count[0],
		"%s controller-only observed pointer event count=0" % prefix,
	)
	await _remove_screen(screen, tree)


func _apply_item_move(
	source: Dictionary,
	target: Dictionary,
	state: RunState,
	screen: InventoryScreen,
) -> void:
	screen.apply_command_result(
		&"item_move",
		InventoryService.apply_move(
			state,
			StringName(source.get("kind", &"")),
			int(source.get("index", -1)),
			StringName(target.get("kind", &"")),
			int(target.get("index", -1)),
		),
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


func _send_cancel_to_settings(overlay: SettingsOverlay) -> void:
	var cancel := InputEventAction.new()
	cancel.action = &"ui_cancel"
	cancel.pressed = true
	overlay.call("_input", cancel)


func _assert_settings_background_isolated(
	assertions: Variant,
	background_control: Control,
	overlay: SettingsOverlay,
	label: String,
) -> void:
	assertions.expect_equal(
		Control.FOCUS_NONE,
		background_control.get_focus_mode_with_override(),
		"%s disables background focus recursively" % label,
	)
	assertions.expect_equal(
		Control.MOUSE_FILTER_IGNORE,
		background_control.get_mouse_filter_with_override(),
		"%s disables background mouse recursively" % label,
	)
	assertions.expect_false(
		overlay.mouse_force_pass_scroll_events,
		"%s blocker does not pass wheel events" % label,
	)
	background_control.grab_focus()
	assertions.expect_false(
		background_control == overlay.get_viewport().gui_get_focus_owner(),
		"%s rejects direct background grab_focus" % label,
	)
	FocusController.grab_focus_safe(overlay.initial_focus_control())


func _instrument_pointer_events(root: Control, counter: Array[int]) -> void:
	for control: Control in _descendant_controls(root):
		control.gui_input.connect(_on_observed_gui_input.bind(counter))


func _on_observed_gui_input(event: InputEvent, counter: Array[int]) -> void:
	if event is InputEventMouse:
		counter[0] += 1


func _descendant_controls(root: Control) -> Array[Control]:
	var result: Array[Control] = [root]
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var current: Node = pending.pop_back()
		for child: Node in current.get_children():
			pending.append(child)
			if child is Control:
				result.append(child as Control)
	return result


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


func _key_event(keycode: Key, pressed: bool, shift_pressed: bool = false) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.pressed = pressed
	event.shift_pressed = shift_pressed
	return event


func _neutralize_left_stick(tree: SceneTree) -> void:
	await _send_joy_motion(tree, JOY_AXIS_LEFT_X, 0.0)
	await _send_joy_motion(tree, JOY_AXIS_LEFT_Y, 0.0)


func _remove_screen(screen: Control, tree: SceneTree) -> void:
	if screen.get_parent() == tree.root:
		tree.root.remove_child(screen)
	screen.free()
	await tree.process_frame


func _loaded_catalog(assertions: Variant) -> DefinitionCatalog:
	if _catalog == null:
		_catalog = DefinitionCatalog.new()
		var valid: bool = _catalog.load_and_validate()
		assertions.expect_true(valid, "release readiness controller-only catalog valid: %s" % _catalog.error_text)
	return _catalog if _catalog.is_valid else null
