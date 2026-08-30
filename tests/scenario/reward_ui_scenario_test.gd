extends RefCounted


const DELTA: float = 1.0 / 60.0
const REWARD_SCENE: PackedScene = preload("res://scenes/ui/reward_reveal_screen.tscn")

var _catalog: DefinitionCatalog = null


func test_names() -> PackedStringArray:
	return PackedStringArray([
		"reward_controls_fixed_fixture_and_focus_contract",
		"controller_hold_button_settings_and_y_contract",
		"mouse_capture_and_button_priority_contract",
		"reveal_timing_prealert_accessibility_and_rng_contract",
	])


func run_test(test_name: String, assertions: Variant, context: Dictionary) -> void:
	match test_name:
		"reward_controls_fixed_fixture_and_focus_contract":
			await _test_fixed_fixture_and_focus(assertions, context)
		"controller_hold_button_settings_and_y_contract":
			await _test_controller_contract(assertions, context)
		"mouse_capture_and_button_priority_contract":
			await _test_mouse_contract(assertions, context)
		"reveal_timing_prealert_accessibility_and_rng_contract":
			await _test_reveal_modes_and_accessibility(assertions, context)
		_:
			assertions.expect_true(false, "registered loot reward UI scenario test")


func _test_fixed_fixture_and_focus(assertions: Variant, context: Dictionary) -> void:
	var fixture: Dictionary = await _spawn_reward_screen(assertions, context)
	if fixture.is_empty():
		return
	var state: RunState = fixture["state"]
	var screen: RewardRevealScreen = fixture["screen"]
	assertions.expect_equal(GameTypes.RunPhase.REWARD_REVEAL, state.phase, "reward_controls begins at REWARD_REVEAL")
	assertions.expect_equal(3, state.wave_number, "reward_controls begins at W3")
	assertions.expect_equal(5, state.unopened_rewards.size(), "reward_controls has four normal rarities and one fixed Unique")
	var expected: Array[Dictionary] = [
		{
			"reward_id": "qa-reward-common-bow",
			"item_id": "qa-item-common-bow",
			"tick": 0,
			"rarity": GameTypes.Rarity.COMMON,
			"slot": GameTypes.EquipmentSlot.MAIN_WEAPON,
			"weapon_type": GameTypes.MainWeaponType.BOW,
			"affixes": [{"id": "max_hp", "value": 10.0}],
		},
		{
			"reward_id": "qa-reward-rare-body",
			"item_id": "qa-item-rare-body",
			"tick": 1,
			"rarity": GameTypes.Rarity.RARE,
			"slot": GameTypes.EquipmentSlot.BODY,
			"weapon_type": GameTypes.MainWeaponType.UNCLASSIFIED,
			"affixes": [
				{"id": "max_hp", "value": 18.0},
				{"id": "damage_reduction_pct", "value": 9.0},
			],
		},
		{
			"reward_id": "qa-reward-epic-hands",
			"item_id": "qa-item-epic-hands",
			"tick": 2,
			"rarity": GameTypes.Rarity.EPIC,
			"slot": GameTypes.EquipmentSlot.HANDS,
			"weapon_type": GameTypes.MainWeaponType.UNCLASSIFIED,
			"affixes": [
				{"id": "damage_pct", "value": 24.0},
				{"id": "attack_speed_pct", "value": 24.0},
				{"id": "area_pct", "value": 30.0},
			],
		},
		{
			"reward_id": "qa-reward-legendary-feet",
			"item_id": "qa-item-legendary-feet",
			"tick": 3,
			"rarity": GameTypes.Rarity.LEGENDARY,
			"slot": GameTypes.EquipmentSlot.FEET,
			"weapon_type": GameTypes.MainWeaponType.UNCLASSIFIED,
			"affixes": [
				{"id": "move_speed_pct", "value": 25.0},
				{"id": "max_hp", "value": 50.0},
				{"id": "damage_reduction_pct", "value": 25.0},
				{"id": "skill_power_pct", "value": 50.0},
			],
		},
		{
			"reward_id": "qa-reward-unique-clock",
			"item_id": "qa-item-unique-clock",
			"tick": 4,
			"rarity": GameTypes.Rarity.UNIQUE,
			"slot": GameTypes.EquipmentSlot.SUB_WEAPON,
			"weapon_type": GameTypes.MainWeaponType.UNCLASSIFIED,
			"affixes": [],
			"unique_id": &"broken_clock",
			"display_name": "壊れた時計",
			"source": GameTypes.RewardSource.BOSS,
		},
	]
	for index: int in expected.size():
		var reward: RewardRoll = state.unopened_rewards[index]
		var expected_reward: Dictionary = expected[index]
		assertions.expect_equal(expected_reward["reward_id"], reward.reward_id, "QA reward %d id" % index)
		assertions.expect_equal(3, reward.wave_number, "QA reward %d wave" % index)
		assertions.expect_equal(expected_reward["tick"], reward.acquired_tick, "QA reward %d tick" % index)
		assertions.expect_false(reward.is_guaranteed_main_weapon, "QA reward %d is not guaranteed" % index)
		assertions.expect_equal(GameTypes.RewardKind.EQUIPMENT, reward.kind, "QA reward %d equipment kind" % index)
		assertions.expect_equal(
			int(expected_reward.get("source", GameTypes.RewardSource.NORMAL)),
			reward.source,
			"QA reward %d source" % index,
		)
		assertions.expect_equal(&"", reward.skill_id, "QA reward %d skill id empty" % index)
		assertions.expect_equal(expected_reward["rarity"], reward.rarity_for_presentation, "QA reward %d presentation rarity" % index)
		assertions.expect_false(reward.revealed, "QA reward %d starts unrevealed" % index)
		var item: ItemInstance = reward.equipment
		assertions.expect_true(item != null, "QA reward %d item exists" % index)
		if item == null:
			continue
		assertions.expect_equal(expected_reward["item_id"], item.item_id, "QA item %d id" % index)
		assertions.expect_equal(expected_reward["slot"], item.slot, "QA item %d slot" % index)
		assertions.expect_equal(expected_reward["weapon_type"], item.main_weapon_type, "QA item %d weapon type" % index)
		assertions.expect_equal(expected_reward["rarity"], item.rarity, "QA item %d rarity" % index)
		assertions.expect_equal(
			StringName(expected_reward.get("unique_id", &"")),
			item.unique_id,
			"QA item %d Unique identity" % index,
		)
		assertions.expect_false(item.locked, "QA item %d unlocked" % index)
		assertions.expect_true(not item.display_name.is_empty(), "QA item %d name is fixed" % index)
		if expected_reward.has("display_name"):
			assertions.expect_equal(expected_reward["display_name"], item.display_name, "QA Unique name comes from its definition")
		assertions.expect_equal(expected_reward["affixes"], _affix_snapshot(item.affixes), "QA item %d affixes" % index)
	var rarity_labels: PackedStringArray = PackedStringArray()
	var outline_tokens: PackedStringArray = PackedStringArray()
	for reward: RewardRoll in state.unopened_rewards:
		rarity_labels.append(RewardRevealController.rarity_label(reward))
		outline_tokens.append(RewardRevealController.outline_token(reward))
	assertions.expect_equal(
		PackedStringArray(["COMMON", "RARE", "EPIC", "LEGENDARY", "UNIQUE"]),
		rarity_labels,
		"equipment presentation indices 0..4 map to five rarity labels",
	)
	assertions.expect_equal(5, _unique_string_count(outline_tokens), "five rarities use five readable outline shapes")
	assertions.expect_equal("★", outline_tokens[4], "Unique uses its dedicated star outline token")
	var skill_reward := RewardRoll.new()
	skill_reward.kind = GameTypes.RewardKind.SKILL
	skill_reward.skill_id = &"starfall"
	skill_reward.rarity_for_presentation = -1
	assertions.expect_equal("スキル", RewardRevealController.rarity_label(skill_reward), "skill -1 displays as スキル")
	assertions.expect_not_equal("COMMON", RewardRevealController.rarity_label(skill_reward), "skill is never presented as Common")

	assertions.expect_equal(
		PackedStringArray(["reward_speed_proxy", "reward_open_all", "reward_settings"]),
		screen.focus_order(),
		"reward focus order is fixed",
	)
	assertions.expect_equal("reward_speed_proxy", screen.debug_state()["focus_id"], "reward proxy receives deferred initial focus")
	var proxy: Control = screen.get_node("%RewardSpeedProxy") as Control
	var current_card: Control = screen.get_node("%CurrentCard") as Control
	var speed_label: Control = screen.get_node("%SpeedLabel") as Control
	var open_all: Control = screen.get_node("%RewardOpenAll") as Control
	var settings: Control = screen.get_node("%RewardSettings") as Control
	assertions.expect_false(proxy is Button, "reward_speed_proxy is not a Button")
	assertions.expect_true(_rect_encloses(proxy.get_global_rect(), current_card.get_global_rect()), "proxy rectangle covers current card")
	assertions.expect_true(_rect_encloses(proxy.get_global_rect(), speed_label.get_global_rect()), "proxy rectangle covers 4x label")
	assertions.expect_false(proxy.get_global_rect().intersects(open_all.get_global_rect()), "proxy does not overlap open-all button")
	assertions.expect_false(proxy.get_global_rect().intersects(settings.get_global_rect()), "proxy does not overlap settings button")
	_assert_horizontal_neighbors(assertions, proxy, open_all, settings)
	_cleanup_fixture(fixture, context)


func _test_controller_contract(assertions: Variant, context: Dictionary) -> void:
	var fixture: Dictionary = await _spawn_reward_screen(assertions, context)
	if fixture.is_empty():
		return
	var screen: RewardRevealScreen = fixture["screen"]
	assertions.expect_equal(0, screen.debug_state()["pointer_event_count"], "controller scenario begins with zero pointer events")

	screen.test_accept_press("reward_speed_proxy")
	screen.test_tick(0.249)
	assertions.expect_false(screen.debug_state()["fast_open"], "proxy A hold is not fast before 0.25 seconds")
	screen.test_accept_release()
	assertions.expect_false(screen.debug_state()["settings_open"], "short proxy A does not open settings")
	assertions.expect_equal(0, screen.debug_state()["reward_settings_click_count"], "short proxy A activates no button")

	screen.test_accept_press("reward_speed_proxy")
	screen.test_tick(0.249)
	assertions.expect_false(screen.debug_state()["fast_open"], "second proxy hold remains normal below threshold")
	screen.test_tick(0.001)
	assertions.expect_true(screen.debug_state()["fast_open"], "proxy A enables 4x exactly at 0.25 seconds")
	screen.test_accept_release()
	assertions.expect_false(screen.debug_state()["fast_open"], "proxy A release restores normal speed")

	screen.test_accept_press("reward_settings")
	screen.test_tick(0.10)
	screen.test_accept_release()
	assertions.expect_true(screen.debug_state()["settings_open"], "short settings A opens overlay")
	assertions.expect_true(screen.debug_state()["paused"], "settings overlay pauses reward timer")
	assertions.expect_equal(1, screen.debug_state()["reward_settings_click_count"], "short settings A activates exactly once")
	var overlay: SettingsOverlay = screen.get_node("%SettingsOverlay") as SettingsOverlay
	await (context["tree"] as SceneTree).process_frame
	assertions.expect_equal(overlay.initial_focus_control(), screen.get_viewport().gui_get_focus_owner(), "settings overlay starts at settings_master")
	assertions.expect_equal(
		PackedStringArray([
			"settings_master", "settings_music", "settings_sfx",
			"settings_reduce_motion", "settings_reduce_flashes",
			"settings_vibration", "settings_tutorial_again", "settings_close",
		]),
		overlay.focus_order(),
		"settings overlay fixed eight-element focus order",
	)
	overlay.close_overlay()
	await (context["tree"] as SceneTree).process_frame
	assertions.expect_false(screen.debug_state()["settings_open"], "settings overlay closes")
	assertions.expect_false(screen.debug_state()["paused"], "closing settings resumes timer at same position")
	assertions.expect_equal("reward_settings", screen.debug_state()["focus_id"], "settings close restores exact prior focus")

	screen.test_accept_press("reward_settings")
	screen.test_tick(0.25)
	assertions.expect_false(screen.debug_state()["fast_open"], "settings A hold never enables 4x")
	screen.test_accept_release()
	assertions.expect_false(screen.debug_state()["settings_open"], "settings A hold does not open overlay")
	assertions.expect_equal(1, screen.debug_state()["reward_settings_click_count"], "settings A hold consumes without activation")
	assertions.expect_equal(0, screen.debug_state()["pointer_event_count"], "controller scenario emits zero pointer events")
	_cleanup_fixture(fixture, context)

	for focus_id: String in ["reward_speed_proxy", "reward_open_all", "reward_settings"]:
		var y_fixture: Dictionary = await _spawn_reward_screen(assertions, context)
		if y_fixture.is_empty():
			return
		var y_screen: RewardRevealScreen = y_fixture["screen"]
		_focus_control(y_screen, focus_id).grab_focus()
		y_screen.test_press_reward_open_all_action()
		assertions.expect_true(y_screen.debug_state()["aggregate_prealert"], "Y from %s starts aggregate true prealert" % focus_id)
		assertions.expect_float(1.0, float(y_screen.debug_state()["prealert_duration"]), "Y aggregate uses Unique one-second prealert")
		y_screen.test_tick(1.0)
		assertions.expect_true(y_screen.reveal_controller().is_complete(), "Y from %s opens every reward" % focus_id)
		assertions.expect_equal(0, y_screen.debug_state()["pointer_event_count"], "Y from %s uses no pointer event" % focus_id)
		_cleanup_fixture(y_fixture, context)


func _test_mouse_contract(assertions: Variant, context: Dictionary) -> void:
	var fixture: Dictionary = await _spawn_reward_screen(assertions, context)
	if fixture.is_empty():
		return
	var screen: RewardRevealScreen = fixture["screen"]
	screen.test_mouse_proxy_press()
	screen.test_tick(0.249)
	assertions.expect_false(screen.debug_state()["fast_open"], "mouse proxy hold below threshold remains normal")
	screen.test_mouse_proxy_release()
	assertions.expect_false(screen.debug_state()["fast_open"], "short proxy release outside clears capture")
	assertions.expect_equal(0, screen.debug_state()["reward_open_all_click_count"], "short proxy mouse generates no open-all click")
	assertions.expect_equal(0, screen.debug_state()["reward_settings_click_count"], "short proxy mouse generates no settings click")

	screen.test_mouse_proxy_press()
	screen.test_tick(0.25)
	assertions.expect_true(screen.debug_state()["fast_open"], "mouse proxy enables 4x at threshold")
	assertions.expect_true(screen.debug_state()["mouse_proxy_captured"], "mouse proxy retains pointer capture")
	screen.test_mouse_proxy_release()
	assertions.expect_false(screen.debug_state()["fast_open"], "proxy release outside restores normal speed")
	assertions.expect_false(screen.debug_state()["mouse_proxy_captured"], "proxy release outside clears capture")

	screen.test_mouse_button_press("reward_open_all")
	screen.test_tick(0.40)
	assertions.expect_false(screen.debug_state()["fast_open"], "mouse hold starting on open-all never enables 4x")
	screen.test_mouse_button_release("outside")
	assertions.expect_equal(1, screen.debug_state()["reward_open_all_click_count"], "open-all mouse origin clicks once regardless hold")

	var settings_fixture: Dictionary = await _spawn_reward_screen(assertions, context)
	if settings_fixture.is_empty():
		_cleanup_fixture(fixture, context)
		return
	var settings_screen: RewardRevealScreen = settings_fixture["screen"]
	settings_screen.test_mouse_button_press("reward_settings")
	settings_screen.test_tick(0.40)
	assertions.expect_false(settings_screen.debug_state()["fast_open"], "mouse hold starting on settings never enables 4x")
	settings_screen.test_mouse_button_release("outside")
	assertions.expect_equal(1, settings_screen.debug_state()["reward_settings_click_count"], "settings mouse origin clicks once regardless hold")
	assertions.expect_true(settings_screen.debug_state()["settings_open"], "settings mouse click opens overlay")
	_cleanup_fixture(settings_fixture, context)
	_cleanup_fixture(fixture, context)


func _test_reveal_modes_and_accessibility(assertions: Variant, context: Dictionary) -> void:
	var baseline_fixture: Dictionary = QaScenarioFactory.build("reward_controls", _loaded_catalog(assertions))
	assertions.expect_true(baseline_fixture.get("valid", false), "reward mode baseline fixture valid")
	if not baseline_fixture.get("valid", false):
		return
	var baseline_payload: Array[Dictionary] = _reward_payload_snapshot(
		(baseline_fixture["state"] as RunState).unopened_rewards
	)

	for mode: String in ["normal", "fast", "all"]:
		var fixture: Dictionary = await _spawn_reward_screen(assertions, context)
		if fixture.is_empty():
			return
		var state: RunState = fixture["state"]
		var screen: RewardRevealScreen = fixture["screen"]
		var rng_before: Dictionary = _rng_snapshot(state)
		if mode == "fast":
			screen.test_accept_press("reward_speed_proxy")
			screen.test_tick(0.25)
		elif mode == "all":
			screen.test_press_reward_open_all_action()
		var guard_ticks: int = 0
		while not screen.reveal_controller().is_complete() and guard_ticks < 600:
			screen.test_tick(DELTA)
			guard_ticks += 1
		if mode == "fast":
			screen.test_accept_release()
		assertions.expect_true(screen.reveal_controller().is_complete(), "%s mode reveals all five rewards" % mode)
		assertions.expect_equal(
			GameTypes.Rarity.UNIQUE,
			screen.reveal_controller().last_revealed_reward().rarity_for_presentation,
			"%s mode reveals Unique last" % mode,
		)
		assertions.expect_equal(baseline_payload, _reward_payload_snapshot(state.unopened_rewards), "%s mode preserves every RewardRoll payload field" % mode)
		assertions.expect_equal(rng_before, _rng_snapshot(state), "%s mode preserves all RNG states and serial" % mode)
		_cleanup_fixture(fixture, context)

	var timing_fixture: Dictionary = await _spawn_reward_screen(assertions, context)
	if timing_fixture.is_empty():
		return
	var timing_screen: RewardRevealScreen = timing_fixture["screen"]
	timing_screen.test_tick(0.35)
	assertions.expect_equal(1, timing_screen.reveal_controller().revealed_rewards().size(), "first Common reveals at 0.35 seconds without prealert")
	assertions.expect_false(timing_screen.debug_state()["prealert_active"], "Common emits no false prealert")
	timing_screen.test_tick(0.35)
	assertions.expect_equal(2, timing_screen.reveal_controller().revealed_rewards().size(), "Rare reveals at next 0.35 seconds")
	assertions.expect_false(timing_screen.debug_state()["prealert_active"], "Rare emits no false prealert")
	timing_screen.test_tick(0.35)
	assertions.expect_true(timing_screen.debug_state()["prealert_active"], "Epic enters true prealert before reveal")
	assertions.expect_equal(2, timing_screen.reveal_controller().revealed_rewards().size(), "Epic remains hidden during prealert")
	assertions.expect_equal("qa-reward-epic-hands", timing_screen.debug_state()["prealert_reward_ids"][0], "Epic prealert identifies the actual next high reward")
	timing_screen.test_tick(0.749)
	assertions.expect_equal(2, timing_screen.reveal_controller().revealed_rewards().size(), "Epic remains hidden before 0.75 seconds")
	timing_screen.test_tick(0.001)
	assertions.expect_equal(3, timing_screen.reveal_controller().revealed_rewards().size(), "Epic reveals exactly after 0.75-second prealert")
	_cleanup_fixture(timing_fixture, context)

	var unique_qa: Dictionary = QaScenarioFactory.build("reward_controls", _loaded_catalog(assertions))
	var unique_state: RunState = unique_qa["state"] as RunState
	var unique_reward: RewardRoll = unique_state.unopened_rewards[4]
	var unique_rewards: Array[RewardRoll] = [unique_reward]
	unique_state.unopened_rewards = unique_rewards
	var unique_controller := RewardRevealController.new()
	unique_controller.initialize(unique_state)
	unique_controller.configure_accessibility(false, false, true)
	unique_controller.tick(0.35)
	var unique_prealert: Dictionary = unique_controller.presentation_state()
	assertions.expect_true(unique_controller.is_prealert_active(), "normal opening starts a dedicated Unique prealert")
	assertions.expect_equal(GameTypes.Rarity.UNIQUE, unique_prealert["prealert_rarity"], "Unique prealert exposes its rarity")
	assertions.expect_float(1.0, float(unique_prealert["prealert_duration"]), "Unique prealert lasts exactly one second")
	assertions.expect_equal(PackedStringArray(["qa-reward-unique-clock"]), unique_controller.prealert_reward_ids(), "Unique prealert targets the actual final reward")
	assertions.expect_float(0.70, float(unique_prealert["last_vibration_weak"]), "Unique vibration weak magnitude")
	assertions.expect_float(1.0, float(unique_prealert["last_vibration_strong"]), "Unique vibration strong magnitude")
	assertions.expect_float(0.65, float(unique_prealert["last_vibration_duration"]), "Unique vibration duration")
	unique_controller.tick(0.999)
	assertions.expect_equal(0, unique_controller.revealed_rewards().size(), "Unique stays hidden before its one-second prealert ends")
	unique_controller.tick(0.001)
	assertions.expect_equal(1, unique_controller.revealed_rewards().size(), "Unique reveals exactly at one second")

	var no_high_qa: Dictionary = QaScenarioFactory.build("reward_controls", _loaded_catalog(assertions))
	var no_high_state: RunState = no_high_qa["state"] as RunState
	var no_high_rewards: Array[RewardRoll] = [
		no_high_state.unopened_rewards[0],
		no_high_state.unopened_rewards[1],
	]
	no_high_state.unopened_rewards = no_high_rewards
	var no_high_controller := RewardRevealController.new()
	no_high_controller.initialize(no_high_state)
	no_high_controller.request_open_all()
	assertions.expect_false(no_high_controller.is_prealert_active(), "all-open with only Common/Rare has no false prealert")
	assertions.expect_true(no_high_controller.is_complete(), "all-open with no high rarity reveals immediately")

	var unique_ui_fixture: Dictionary = await _spawn_reward_screen(assertions, context)
	if unique_ui_fixture.is_empty():
		return
	var unique_screen: RewardRevealScreen = unique_ui_fixture["screen"]
	var audio_events: Array[StringName] = []
	unique_screen.audio_event_requested.connect(
		func(event_id: StringName) -> void:
			audio_events.append(event_id)
	)
	unique_screen.test_press_reward_open_all_action()
	var unique_ui_state: Dictionary = unique_screen.debug_state()
	assertions.expect_equal(GameTypes.Rarity.UNIQUE, unique_ui_state["prealert_rarity"], "open-all promotes Unique to the aggregate prealert")
	assertions.expect_float(1.0, float(unique_ui_state["prealert_duration"]), "open-all keeps the full Unique prealert duration")
	assertions.expect_float(0.70, float(unique_ui_state["last_vibration_weak"]), "open-all Unique weak vibration")
	assertions.expect_float(1.0, float(unique_ui_state["last_vibration_strong"]), "open-all Unique strong vibration")
	assertions.expect_float(0.65, float(unique_ui_state["last_vibration_duration"]), "open-all Unique vibration duration")
	assertions.expect_equal(PackedStringArray([&"unique_prealert"]), PackedStringArray(audio_events), "open-all emits the dedicated Unique sweep")
	assertions.expect_equal("★ UNIQUE 予告", (unique_screen.get_node("%PrealertBanner") as Label).text, "Unique uses its dedicated prealert banner")
	assertions.expect_equal("★ UNIQUE", (unique_screen.get_node("%CurrentRarity") as Label).text, "Unique prealert uses the exact presentation label")
	var prealert_style := (unique_screen.get_node("%CurrentCard") as PanelContainer).get_theme_stylebox("panel") as StyleBoxFlat
	assertions.expect_equal(Color(0.95, 0.16, 0.22, 1.0), prealert_style.border_color, "Unique reveal card uses the deep-crimson border")
	assertions.expect_equal(PackedInt32Array([2, 28, 2, 28]), PackedInt32Array([
		prealert_style.corner_radius_top_left,
		prealert_style.corner_radius_top_right,
		prealert_style.corner_radius_bottom_right,
		prealert_style.corner_radius_bottom_left,
	]), "Unique reveal card uses its dedicated outline shape")
	unique_screen.test_tick(1.0)
	assertions.expect_true(unique_screen.reveal_controller().is_complete(), "open-all reveals every card after the Unique prealert")
	assertions.expect_equal(GameTypes.Rarity.UNIQUE, unique_screen.reveal_controller().last_revealed_reward().rarity_for_presentation, "open-all reveals Unique last")
	assertions.expect_equal("★ UNIQUE", (unique_screen.get_node("%CurrentRarity") as Label).text, "revealed Unique keeps the exact star label")
	assertions.expect_equal("壊れた時計", (unique_screen.get_node("%CurrentName") as Label).text, "Unique card shows its catalog name")
	var clock_definition: UniqueDefinition = _loaded_catalog(assertions).unique(&"broken_clock")
	assertions.expect_equal(
		"部位 sub_weapon\n固有効果: %s" % clock_definition.effect_description,
		(unique_screen.get_node("%CurrentDetails") as Label).text,
		"Unique card shows the complete catalog effect text",
	)
	var missing_item := ItemInstance.new()
	missing_item.rarity = GameTypes.Rarity.UNIQUE
	missing_item.slot = GameTypes.EquipmentSlot.SUB_WEAPON
	missing_item.unique_id = &"missing_definition"
	var missing_reward := RewardRoll.new()
	missing_reward.equipment = missing_item
	missing_reward.rarity_for_presentation = GameTypes.Rarity.UNIQUE
	assertions.expect_equal(
		"部位 sub_weapon\n固有効果: 不明な固有効果",
		String(unique_screen.call("_reward_details", missing_reward)),
		"missing Unique definition alone uses the fallback effect text",
	)
	_cleanup_fixture(unique_ui_fixture, context)

	var reduce_fixture: Dictionary = await _spawn_reward_screen(assertions, context)
	if reduce_fixture.is_empty():
		return
	var reduce_screen: RewardRevealScreen = reduce_fixture["screen"]
	var reduce_controller: RewardRevealController = reduce_screen.reveal_controller()
	reduce_controller.configure_accessibility(true, true, false)
	reduce_screen.test_press_reward_open_all_action()
	reduce_screen.test_tick(0.26)
	var reduce_state: Dictionary = reduce_screen.debug_state()
	assertions.expect_true(reduce_state["aggregate_prealert"], "all-open high rewards use one aggregate prealert")
	assertions.expect_equal(3, (reduce_state["prealert_reward_ids"] as PackedStringArray).size(), "aggregate prealert targets Epic, Legendary, and Unique cards")
	assertions.expect_float(1.0, float(reduce_state["prealert_duration"]), "accessibility settings preserve Unique prealert timing")
	assertions.expect_float(0.0, float(reduce_state["shake_offset"]), "Reduce Motion removes positional shake")
	assertions.expect_true(float(reduce_state["scale_multiplier"]) > 1.0 and float(reduce_state["scale_multiplier"]) <= 1.02, "Reduce Motion substitutes at most 2 percent scale pulse")
	assertions.expect_equal(0, reduce_state["stage_light_step"], "Reduce Flashes removes stepped light")
	assertions.expect_true(int(reduce_state["outline_thickness"]) > 3, "Reduce Flashes substitutes outline thickness")
	assertions.expect_equal(
		"動き軽減 ON・点滅軽減 ON",
		reduce_state["accessibility_status"],
		"accessibility alternatives remain visibly identified",
	)
	assertions.expect_equal(0, reduce_state["vibration_request_count"], "vibration disabled suppresses controller vibration")
	reduce_screen.test_tick(0.739)
	assertions.expect_false(reduce_controller.is_complete(), "accessibility settings keep Unique hidden before one second")
	reduce_screen.test_tick(0.001)
	assertions.expect_true(reduce_controller.is_complete(), "aggregate prealert reveals all cards at one second")
	_cleanup_fixture(reduce_fixture, context)


func _spawn_reward_screen(assertions: Variant, context: Dictionary) -> Dictionary:
	var catalog: DefinitionCatalog = _loaded_catalog(assertions)
	if catalog == null:
		return {}
	var qa: Dictionary = QaScenarioFactory.build("reward_controls", catalog)
	assertions.expect_true(qa.get("valid", false), "reward_controls QA state builds without RNG movement")
	if not qa.get("valid", false):
		return {}
	var screen := REWARD_SCENE.instantiate() as RewardRevealScreen
	assertions.expect_true(screen != null, "reward reveal scene instantiates")
	if screen == null:
		return {}
	screen.set_automatic_progression(false)
	screen.initialize(qa["state"] as RunState, catalog)
	var tree: SceneTree = context["tree"] as SceneTree
	tree.root.add_child(screen)
	await tree.process_frame
	await tree.process_frame
	return {
		"state": qa["state"],
		"simulation": qa["simulation"],
		"screen": screen,
	}


func _cleanup_fixture(fixture: Dictionary, context: Dictionary) -> void:
	var screen: RewardRevealScreen = fixture.get("screen") as RewardRevealScreen
	if screen == null:
		return
	var tree: SceneTree = context["tree"] as SceneTree
	if screen.get_parent() == tree.root:
		tree.root.remove_child(screen)
	screen.free()


func _loaded_catalog(assertions: Variant) -> DefinitionCatalog:
	if _catalog == null:
		_catalog = DefinitionCatalog.new()
		var valid: bool = _catalog.load_and_validate()
		assertions.expect_true(valid, "loot reward UI catalog valid: %s" % _catalog.error_text)
	return _catalog if _catalog.is_valid else null


func _affix_snapshot(affixes: Array[AffixRoll]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for affix: AffixRoll in affixes:
		result.append({"id": String(affix.affix_id), "value": affix.value})
	return result


func _reward_payload_snapshot(rewards: Array[RewardRoll]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for reward: RewardRoll in rewards:
		var equipment: Variant = null
		if reward.equipment != null:
			equipment = {
				"item_id": reward.equipment.item_id,
				"item_seed": reward.equipment.item_seed,
				"slot": reward.equipment.slot,
				"main_weapon_type": reward.equipment.main_weapon_type,
				"rarity": reward.equipment.rarity,
				"affixes": _affix_snapshot(reward.equipment.affixes),
				"unique_id": String(reward.equipment.unique_id),
				"display_name": reward.equipment.display_name,
				"locked": reward.equipment.locked,
			}
		result.append({
			"reward_id": reward.reward_id,
			"wave_number": reward.wave_number,
			"acquired_tick": reward.acquired_tick,
			"guaranteed": reward.is_guaranteed_main_weapon,
			"kind": reward.kind,
			"source": reward.source,
			"equipment": equipment,
			"skill_id": String(reward.skill_id),
			"rarity_for_presentation": reward.rarity_for_presentation,
		})
	return result


func _rng_snapshot(state: RunState) -> Dictionary:
	return {
		"combat": state.rng_streams.combat_rng.state,
		"loot": state.rng_streams.loot_rng.state,
		"fusion": state.rng_streams.fusion_rng.state,
		"drop_serial": state.drop_serial,
	}


func _rect_encloses(outer: Rect2, inner: Rect2) -> bool:
	return (
		inner.position.x >= outer.position.x
		and inner.position.y >= outer.position.y
		and inner.end.x <= outer.end.x
		and inner.end.y <= outer.end.y
	)


func _focus_control(screen: RewardRevealScreen, focus_id: String) -> Control:
	match focus_id:
		"reward_open_all":
			return screen.get_node("%RewardOpenAll") as Control
		"reward_settings":
			return screen.get_node("%RewardSettings") as Control
	return screen.get_node("%RewardSpeedProxy") as Control


func _unique_string_count(values: PackedStringArray) -> int:
	var unique: Dictionary[String, bool] = {}
	for value: String in values:
		unique[value] = true
	return unique.size()


func _assert_horizontal_neighbors(
	assertions: Variant,
	proxy: Control,
	open_all: Control,
	settings: Control,
) -> void:
	assertions.expect_equal(proxy.get_path_to(settings), proxy.focus_neighbor_left, "proxy left wraps to settings")
	assertions.expect_equal(proxy.get_path_to(open_all), proxy.focus_neighbor_right, "proxy right reaches open-all")
	assertions.expect_equal(open_all.get_path_to(proxy), open_all.focus_neighbor_left, "open-all left reaches proxy")
	assertions.expect_equal(open_all.get_path_to(settings), open_all.focus_neighbor_right, "open-all right reaches settings")
	assertions.expect_equal(settings.get_path_to(open_all), settings.focus_neighbor_left, "settings left reaches open-all")
	assertions.expect_equal(settings.get_path_to(proxy), settings.focus_neighbor_right, "settings right wraps to proxy")
	for control: Control in [proxy, open_all, settings]:
		assertions.expect_equal(control.get_path_to(control), control.focus_neighbor_top, "%s up stays self" % control.get_meta("focus_id"))
		assertions.expect_equal(control.get_path_to(control), control.focus_neighbor_bottom, "%s down stays self" % control.get_meta("focus_id"))
