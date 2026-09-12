extends RefCounted


const SURVIVAL_OVERLAY_SCENE: PackedScene = preload("res://scenes/ui/survival_overlay.tscn")
const COMBAT_HUD_SCENE: PackedScene = preload("res://scenes/ui/combat_hud.tscn")
const RESULT_SCENE: PackedScene = preload("res://scenes/ui/result_screen.tscn")


func test_survival_modals_are_three_choice_and_immediately_skippable(assertions: Variant, context: Dictionary) -> void:
	var tree: SceneTree = context["tree"]
	var overlay: SurvivalOverlay = SURVIVAL_OVERLAY_SCENE.instantiate() as SurvivalOverlay
	tree.root.add_child(overlay)
	await tree.process_frame
	var selected := PackedInt32Array()
	var chest_continues := PackedInt32Array()
	var title_requests := PackedInt32Array()
	overlay.level_choice_requested.connect(func(index: int) -> void:
		selected.append(index)
	)
	overlay.chest_continue_requested.connect(func() -> void:
		chest_continues.append(1)
	)
	overlay.title_requested.connect(func() -> void:
		title_requests.append(1)
	)
	overlay.show_level_offer({
		"serial": 71,
		"options": [
			_option(
				GameTypes.UpgradeKind.WEAPON,
				"共鳴波",
				1,
				2,
				"進化: 共鳴波 Lv8 ＋ 触媒：生命格子 Lv1以上 → 生命共鳴",
				100.0,
				"波数 2 → 3",
			),
			_option(
				GameTypes.UpgradeKind.PASSIVE,
				"周期結晶",
				0,
				1,
				"進化: 追尾核 Lv8 ＋ 触媒：周期結晶 Lv1以上 → 無限追尾",
				90.0,
			),
			_option(-1, "分類なし", 4, 5, "進化: 不明", 80.0, "効果 4 → 5"),
		],
	})
	await tree.process_frame
	var level_state: Dictionary = overlay.debug_state()
	assertions.expect_true(level_state["level_visible"], "level-up modal is visible")
	assertions.expect_equal(3, level_state["option_texts"].size(), "exactly three choices are visible")
	var choice_zero := overlay.get_node("Root/LevelUpModal/Center/Panel/Content/ChoiceScroll/Choices/LevelChoice0") as Button
	assertions.expect_equal("共鳴波", choice_zero.accessibility_name, "accessibility name remains the display name")
	assertions.expect_true(
		choice_zero.get_combined_minimum_size().y <= choice_zero.size.y,
		"the longer catalyst hint fits inside a configured level-choice card",
	)
	var level_panel := overlay.get_node("Root/LevelUpModal/Center/Panel") as Control
	assertions.expect_true(
		level_panel.size.x <= 1920.0 and level_panel.size.y <= 1080.0,
		"the catalyst cards remain inside the 1920x1080 design viewport",
	)
	var choice_two := overlay.get_node("Root/LevelUpModal/Center/Panel/Content/ChoiceScroll/Choices/LevelChoice2") as Button
	choice_two.pressed.emit()
	assertions.expect_equal(PackedInt32Array([2]), selected, "choice buttons emit their indexed selection")

	overlay.show_chest_outcome({
		"serial": 91,
		"display_name": "生命共鳴",
		"source_weapon_id": &"resonance_wave",
		"previous_level": 8,
		"new_level": 1,
	})
	var chest_state: Dictionary = overlay.debug_state()
	assertions.expect_true(chest_state["chest_visible"], "chest result modal is visible")
	var chest_action := overlay.get_node("Root/ChestModal/Center/Panel/Scroll/Content/ChestContinue") as Control
	_exercise_chest_input(assertions, overlay, chest_action, _key_event(KEY_ENTER), chest_continues, 1)
	_exercise_chest_input(assertions, overlay, chest_action, _key_event(KEY_KP_ENTER), chest_continues, 2)
	_exercise_chest_input(assertions, overlay, chest_action, _joy_event(JOY_BUTTON_A), chest_continues, 3)
	_exercise_chest_input(assertions, overlay, chest_action, _mouse_event(MOUSE_BUTTON_LEFT), chest_continues, 4)
	_exercise_chest_input(assertions, overlay, chest_action, _key_event(KEY_SPACE), chest_continues, 4)
	_exercise_chest_input(assertions, overlay, chest_action, _key_event(KEY_ESCAPE), chest_continues, 4)
	_exercise_chest_input(assertions, overlay, chest_action, _joy_event(JOY_BUTTON_B), chest_continues, 4)
	assertions.expect_equal(4, chest_continues.size(), "only Enter, keypad Enter, A, and left click skip")
	overlay.hide_automatic_modal()
	assertions.expect_true(overlay.open_pause(), "manual pause opens outside automatic modals")
	var title_button := overlay.get_node("Root/PauseModal/Center/Panel/Scroll/Content/PauseTitle") as Button
	title_button.pressed.emit()
	assertions.expect_true(overlay.debug_state()["confirmation_visible"], "title return requires confirmation")
	assertions.expect_equal(0, title_requests.size(), "opening confirmation does not leave the run")
	var confirmation := overlay.get_node("Root/TitleConfirmation") as JarjarConfirmationDialog
	var confirm_button := confirmation.focus_control("dialog_confirm") as Button
	confirm_button.pressed.emit()
	assertions.expect_equal(1, title_requests.size(), "confirmed title return emits exactly once")
	overlay.queue_free()
	await tree.process_frame


func test_pause_shows_all_evolution_pairs_from_run_start(assertions: Variant, context: Dictionary) -> void:
	var tree: SceneTree = context["tree"]
	var catalog := BalanceTestFixtures.catalog()
	var overlay := SURVIVAL_OVERLAY_SCENE.instantiate() as SurvivalOverlay
	overlay.initialize(catalog)
	tree.root.add_child(overlay)
	await tree.process_frame
	assertions.expect_true(overlay.open_pause(), "evolution guide is reachable from pause")
	var guide := str(overlay.debug_state()["evolution_guide"])
	for base_id: StringName in catalog.basic_weapon_ids():
		var evolution := catalog.evolution_for_weapon(base_id)
		for name: String in [catalog.weapon(base_id).display_name, catalog.passive(evolution.passive_id).display_name, catalog.weapon(evolution.evolved_weapon_id).display_name]:
			assertions.expect_true(guide.contains(name), "evolution guide includes %s" % name)
	overlay.queue_free()
	await tree.process_frame


func test_level_up_real_inputs_do_not_leak_between_consecutive_modals(assertions: Variant, context: Dictionary) -> void:
	var tree: SceneTree = context["tree"]
	var overlay: SurvivalOverlay = SURVIVAL_OVERLAY_SCENE.instantiate() as SurvivalOverlay
	tree.root.add_child(overlay)
	await tree.process_frame
	var selections := PackedInt32Array()
	var queued_offers: Array[Dictionary] = [
		_level_offer(102, "SECOND"),
		_level_offer(103, "THIRD"),
	]
	overlay.level_choice_requested.connect(func(index: int) -> void:
		selections.append(index)
		if not queued_offers.is_empty():
			overlay.show_level_offer(queued_offers.pop_front())
	)
	overlay.show_level_offer(_level_offer(101, "FIRST"))
	await tree.process_frame
	var choice_zero := overlay.get_node("Root/LevelUpModal/Center/Panel/Content/ChoiceScroll/Choices/LevelChoice0") as Button
	var choice_one := overlay.get_node("Root/LevelUpModal/Center/Panel/Content/ChoiceScroll/Choices/LevelChoice1") as Button
	var choice_two := overlay.get_node("Root/LevelUpModal/Center/Panel/Content/ChoiceScroll/Choices/LevelChoice2") as Button
	assertions.expect_equal(choice_zero, tree.root.gui_get_focus_owner(), "first modal focuses the first choice")

	_push_key(tree.root, KEY_RIGHT)
	assertions.expect_equal(choice_one, tree.root.gui_get_focus_owner(), "keyboard navigation moves real focus")
	_push_key(tree.root, KEY_ENTER)
	await tree.process_frame
	assertions.expect_equal(PackedInt32Array([1]), selections, "Enter chooses exactly once across a modal transition")
	assertions.expect_equal(102, overlay.active_offer_serial(), "next queued modal remains active after Enter release")
	assertions.expect_equal(choice_zero, tree.root.gui_get_focus_owner(), "consecutive modal restores first-choice focus")

	(overlay.get_node("%ChoiceScroll") as ScrollContainer).ensure_control_visible(choice_two)
	await tree.process_frame
	_push_mouse_click(tree.root, choice_two.get_global_rect().get_center())
	await tree.process_frame
	assertions.expect_equal(PackedInt32Array([1, 2]), selections, "mouse click chooses exactly once across a modal transition")
	assertions.expect_equal(103, overlay.active_offer_serial(), "third queued modal remains active after mouse release")
	assertions.expect_equal(choice_zero, tree.root.gui_get_focus_owner(), "mouse-driven transition restores first-choice focus")

	_push_joy_button(tree.root, JOY_BUTTON_DPAD_RIGHT)
	_push_joy_button(tree.root, JOY_BUTTON_DPAD_RIGHT)
	assertions.expect_equal(choice_two, tree.root.gui_get_focus_owner(), "gamepad navigation reaches the third choice")
	_push_joy_button(tree.root, JOY_BUTTON_A)
	await tree.process_frame
	assertions.expect_equal(PackedInt32Array([1, 2, 2]), selections, "gamepad A chooses once without leaking")
	overlay.hide_automatic_modal()
	assertions.expect_equal(null, tree.root.gui_get_focus_owner(), "leaving the final automatic modal releases hidden focus")
	overlay.queue_free()
	await tree.process_frame


func test_combat_hud_shows_max_build_slots_and_boss_health(assertions: Variant, context: Dictionary) -> void:
	var tree: SceneTree = context["tree"]
	var hud: CombatHud = COMBAT_HUD_SCENE.instantiate() as CombatHud
	tree.root.add_child(hud)
	await tree.process_frame
	hud.update_from_values({
		"weapon_slot_count": 5,
		"passive_slot_count": 5,
		"time_seconds": 900.0,
		"level": 42,
		"total_kills": 1234,
		"current_hp": 88.0,
		"max_hp": 120.0,
		"xp": 0,
		"xp_for_next_level": 1,
		"build_maxed": true,
		"weapons": [
			{"display_name": "生命共鳴", "level": 1, "evolved": true},
			{"display_name": "無限追尾", "level": 1, "evolved": true},
		],
		"passives": [
			{"display_name": "生命格子", "level": 5},
		],
		"boss_active": true,
		"boss_hp": 850.0,
		"boss_max_hp": 1000.0,
		"active_xp": 17,
	})
	var state: Dictionary = hud.debug_state()
	assertions.expect_equal(5, state["weapons"].size(), "HUD always exposes five weapon slots")
	assertions.expect_equal(5, state["passives"].size(), "HUD always exposes five passive slots")
	assertions.expect_true(state["boss_visible"], "final boss health panel is visible")
	assertions.expect_true(str(state["boss_hp"]).contains("850"), "final boss health has exact current value")
	hud.queue_free()
	await tree.process_frame


func test_summary_uses_catalog_names_and_final_lineage_name(assertions: Variant, context: Dictionary) -> void:
	var tree: SceneTree = context["tree"]
	var catalog := DefinitionCatalog.new()
	assertions.expect_true(catalog.validate_manifest(BalanceTestFixtures.manifest()), "summary catalog valid")
	var state: RunState = RunStateFactory.create(20260827, catalog)
	state.phase = GameTypes.RunPhase.RESULT
	state.combat_tick = catalog.boss_start_tick
	state.boss_defeated = true
	state.weapons[0].weapon_id = &"infinite_homing"
	state.weapons[0].evolved = true
	state.weapons[0].level = 1
	state.passives.append(RunPassive.create(&"cycle_crystal"))
	state.weapon_damage_by_lineage[&"homing_core"] = 1234.0
	var summary: ResultScreen = RESULT_SCENE.instantiate() as ResultScreen
	summary.initialize(state, catalog)
	tree.root.add_child(summary)
	await tree.process_frame
	var rendered: Dictionary = summary.debug_state()
	assertions.expect_true(str(rendered["build_text"]).contains(catalog.weapon(&"infinite_homing").display_name), "build uses evolved weapon display name")
	assertions.expect_true(str(rendered["build_text"]).contains(catalog.passive(&"cycle_crystal").display_name), "build uses passive display name")
	assertions.expect_true(str(rendered["damage_text"]).contains(catalog.weapon(&"infinite_homing").display_name), "lineage damage uses final weapon display name")
	assertions.expect_true(str(rendered["damage_text"]).contains("1234"), "lineage damage remains aggregated")
	summary.queue_free()
	await tree.process_frame


func _option(
	kind: int,
	display_name: String,
	current_level: int,
	next_level: int,
	pairing_hint: String,
	weight: float,
	upgrade_detail: String = "",
) -> Dictionary:
	return {
		"kind": kind,
		"display_name": display_name,
		"description": "説明",
		"upgrade_detail": upgrade_detail,
		"pairing_hint": pairing_hint,
		"current_level": current_level,
		"next_level": next_level,
		"weight": weight,
	}


func _level_offer(serial: int, prefix: String) -> Dictionary:
	return {
		"serial": serial,
		"options": [
			_option(GameTypes.UpgradeKind.WEAPON, "%s 0" % prefix, 1, 2, "進化: P0", 100.0),
			_option(GameTypes.UpgradeKind.PASSIVE, "%s 1" % prefix, 1, 2, "進化: P1", 90.0),
			_option(GameTypes.UpgradeKind.WEAPON, "%s 2" % prefix, 1, 2, "進化: P2", 80.0),
		],
	}


func _exercise_chest_input(
	assertions: Variant,
	overlay: SurvivalOverlay,
	action: Control,
	event: InputEvent,
	continues: PackedInt32Array,
	expected_count: int,
) -> void:
	overlay.show_chest_outcome({
		"serial": 100 + expected_count,
		"display_name": "共鳴波",
		"previous_level": 1,
		"new_level": 2,
		"upgrade_detail": "波数 2 → 3",
	})
	action.call("test_handle_input", event)
	assertions.expect_equal(
		expected_count,
		continues.size(),
		"strict chest activation for %s" % event.as_text(),
	)


func _key_event(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	return event


func _joy_event(button_index: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button_index
	event.pressed = true
	return event


func _mouse_event(button_index: MouseButton) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button_index
	event.pressed = true
	return event


func _push_key(viewport: Viewport, keycode: Key) -> void:
	var pressed := InputEventKey.new()
	pressed.keycode = keycode
	pressed.physical_keycode = keycode
	pressed.pressed = true
	viewport.push_input(pressed, true)
	var released := pressed.duplicate() as InputEventKey
	released.pressed = false
	viewport.push_input(released, true)


func _push_joy_button(viewport: Viewport, button_index: JoyButton) -> void:
	var pressed := InputEventJoypadButton.new()
	pressed.button_index = button_index
	pressed.pressed = true
	viewport.push_input(pressed, true)
	var released := pressed.duplicate() as InputEventJoypadButton
	released.pressed = false
	viewport.push_input(released, true)


func _push_mouse_click(viewport: Viewport, position: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	viewport.push_input(motion, true)
	var pressed := InputEventMouseButton.new()
	pressed.button_index = MOUSE_BUTTON_LEFT
	pressed.position = position
	pressed.global_position = position
	pressed.pressed = true
	viewport.push_input(pressed, true)
	var released := pressed.duplicate() as InputEventMouseButton
	released.pressed = false
	viewport.push_input(released, true)
