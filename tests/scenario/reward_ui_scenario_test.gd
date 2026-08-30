extends RefCounted


const REWARD_SCENE: PackedScene = preload("res://scenes/ui/reward_reveal_screen.tscn")
const RESULT_SCENE: PackedScene = preload("res://scenes/ui/result_screen.tscn")


class InputLeakProbe:
	extends Node

	var unhandled_action_count: int = 0


	func _unhandled_input(event: InputEvent) -> void:
		if (
			event.is_action_pressed(&"ui_accept")
			or event.is_action_released(&"ui_accept")
			or event.is_action_pressed(&"reward_open_all")
			or event.is_action_released(&"reward_open_all")
		):
			unhandled_action_count += 1


func test_names() -> PackedStringArray:
	return PackedStringArray([
		"reward_reveal_handles_items_and_legendary_prealert",
		"reward_reveal_coalesces_bulk_audio",
		"reward_open_all_inputs_survive_synchronous_screen_removal",
		"summary_lists_only_six_equipped_items_and_current_scores",
	])


func run_test(test_name: String, assertions: Variant, context: Dictionary) -> void:
	match test_name:
		"reward_reveal_handles_items_and_legendary_prealert":
			await _test_reward(assertions, context)
		"reward_reveal_coalesces_bulk_audio":
			await _test_bulk_audio(assertions, context)
		"reward_open_all_inputs_survive_synchronous_screen_removal":
			await _test_open_all_input_lifecycle(assertions, context)
		"summary_lists_only_six_equipped_items_and_current_scores":
			await _test_summary(assertions, context)
		_:
			assertions.expect_true(false, "registered reward UI scenario test")


func _test_reward(assertions: Variant, context: Dictionary) -> void:
	var catalog := DefinitionCatalog.new()
	assertions.expect_true(catalog.load_and_validate(), "reward UI catalog valid")
	if not catalog.is_valid:
		return
	var fixture: Dictionary = QaScenarioFactory.build("reward_controls", catalog)
	assertions.expect_true(fixture.get("valid", false), "reward UI fixture valid")
	if not fixture.get("valid", false):
		return
	var screen: RewardRevealScreen = REWARD_SCENE.instantiate() as RewardRevealScreen
	screen.set_automatic_progression(false)
	screen.initialize(fixture["state"], catalog)
	var viewport: SubViewport = await _attach(screen, context["tree"])
	var audio_events: Array[StringName] = []
	screen.audio_event_requested.connect(func(event_id: StringName) -> void: audio_events.append(event_id))
	screen.test_press_reward_open_all_action()
	assertions.expect_true(screen.reveal_controller().is_prealert_active(), "open-all starts one aggregate high-rarity prealert")
	assertions.expect_float(0.75, float(screen.reveal_controller().presentation_state()["prealert_duration"]), "legendary uses current high-rarity prealert duration")
	screen.test_tick(0.75)
	assertions.expect_true(screen.reveal_controller().is_complete(), "all item rewards reveal after prealert")
	assertions.expect_true(&"legendary_prealert" in audio_events, "legendary audio path remains")
	assertions.expect_false(&"unique_prealert" in audio_events, "removed unique audio path never emits")
	var name_text: String = (screen.get_node("%CurrentName") as Label).text
	var detail_text: String = (screen.get_node("%CurrentDetails") as Label).text
	assertions.expect_false(name_text.contains("スキル"), "reward card never renders a skill reward")
	assertions.expect_false(detail_text.contains("ユニーク"), "reward details have no unique branch")
	assertions.expect_true(detail_text.contains("基礎ダメージ") or detail_text.contains("お守り"), "reward card shows the item's own performance")
	assertions.expect_true(detail_text.contains("基準間隔"), "weapon reward labels the displayed value as nominal interval")
	await _detach(screen, viewport, context["tree"])


func _test_bulk_audio(assertions: Variant, context: Dictionary) -> void:
	var catalog := DefinitionCatalog.new()
	assertions.expect_true(catalog.load_and_validate(), "bulk audio catalog valid")
	if not catalog.is_valid:
		return
	await _run_reward_audio_case(
		assertions,
		context,
		catalog,
		"mixed bulk",
		PackedInt32Array(),
		true,
		PackedStringArray(["legendary_prealert", "rare_open"]),
	)
	await _run_reward_audio_case(
		assertions,
		context,
		catalog,
		"previous rare excluded",
		PackedInt32Array([GameTypes.Rarity.RARE]),
		true,
		PackedStringArray(["legendary_prealert", "normal_open"]),
	)
	await _run_reward_audio_case(
		assertions,
		context,
		catalog,
		"high rarity only",
		PackedInt32Array([GameTypes.Rarity.COMMON, GameTypes.Rarity.RARE]),
		true,
		PackedStringArray(["legendary_prealert"]),
	)
	await _run_reward_audio_case(
		assertions,
		context,
		catalog,
		"automatic progression",
		PackedInt32Array(),
		false,
		PackedStringArray(["normal_open", "rare_open"]),
	)


func _run_reward_audio_case(
	assertions: Variant,
	context: Dictionary,
	catalog: DefinitionCatalog,
	label: String,
	already_revealed_rarities: PackedInt32Array,
	use_open_all: bool,
	expected_audio_events: PackedStringArray,
) -> void:
	var fixture: Dictionary = QaScenarioFactory.build("reward_controls", catalog)
	assertions.expect_true(fixture.get("valid", false), "%s fixture valid" % label)
	if not fixture.get("valid", false):
		return
	var state: RunState = fixture["state"] as RunState
	for reward: RewardRoll in state.unopened_rewards:
		if reward.rarity_for_presentation in already_revealed_rarities:
			reward.revealed = true

	var screen: RewardRevealScreen = REWARD_SCENE.instantiate() as RewardRevealScreen
	screen.set_automatic_progression(false)
	screen.initialize(state, catalog)
	var audio_events: Array[StringName] = []
	screen.audio_event_requested.connect(
		func(event_id: StringName) -> void: audio_events.append(event_id)
	)
	var viewport: SubViewport = await _attach(screen, context["tree"])
	if use_open_all:
		screen.test_press_reward_open_all_action()
		assertions.expect_true(
			screen.reveal_controller().is_prealert_active(),
			"%s starts aggregate prealert" % label,
		)
		screen.test_tick(0.75)
		assertions.expect_true(
			screen.reveal_controller().is_complete(),
			"%s completes bulk reveal" % label,
		)
	else:
		screen.test_tick(0.35)
		screen.test_tick(0.35)
	assertions.expect_equal(
		expected_audio_events,
		PackedStringArray(audio_events),
		"%s emits expected audio sequence" % label,
	)
	await _detach(screen, viewport, context["tree"])


func _test_open_all_input_lifecycle(assertions: Variant, context: Dictionary) -> void:
	var catalog := DefinitionCatalog.new()
	assertions.expect_true(catalog.load_and_validate(), "open-all lifecycle catalog valid")
	if not catalog.is_valid:
		return
	for action: StringName in [&"ui_accept", &"reward_open_all"]:
		var fixture: Dictionary = QaScenarioFactory.build("reward_controls", catalog)
		assertions.expect_true(fixture.get("valid", false), "%s fixture valid" % action)
		if not fixture.get("valid", false):
			continue
		var state: RunState = fixture["state"] as RunState
		for reward: RewardRoll in state.unopened_rewards:
			if RewardRevealController.is_high_rarity(reward):
				reward.revealed = true

		var screen: RewardRevealScreen = REWARD_SCENE.instantiate() as RewardRevealScreen
		screen.set_automatic_progression(false)
		screen.initialize(state, catalog)
		var audio_events: Array[StringName] = []
		screen.audio_event_requested.connect(
			func(event_id: StringName) -> void: audio_events.append(event_id)
		)
		var viewport := SubViewport.new()
		viewport.size = Vector2i(1920, 1080)
		var probe := InputLeakProbe.new()
		context["tree"].root.add_child(viewport)
		viewport.add_child(probe)
		screen.reveal_completed.connect(func() -> void:
			if screen.get_parent() == viewport:
				viewport.remove_child(screen)
		)
		viewport.add_child(screen)
		await context["tree"].process_frame
		await context["tree"].process_frame

		assertions.expect_equal(
			PackedStringArray(["reward_open_all", "reward_settings"]),
			screen.focus_order(),
			"%s focus order omits fast-open proxy" % action,
		)
		assertions.expect_equal(
			screen.initial_focus_control(),
			viewport.gui_get_focus_owner(),
			"%s starts focused on open-all" % action,
		)
		assertions.expect_false(
			screen.reveal_controller().presentation_state().has("fast_open"),
			"%s presentation omits fast-open state" % action,
		)
		assertions.expect_equal(
			null,
			screen.find_child("RewardSpeedProxy", true, false),
			"%s scene omits fast-open proxy" % action,
		)

		_push_action(viewport, action, true)
		if action == &"ui_accept":
			_push_action(viewport, action, false)
		assertions.expect_true(
			screen.reveal_controller().is_complete(),
			"%s completes all remaining rewards" % action,
		)
		assertions.expect_equal(
			null,
			screen.get_parent(),
			"%s may synchronously remove the reward screen" % action,
		)
		assertions.expect_equal(
			0,
			probe.unhandled_action_count,
			"%s does not leak input after synchronous removal" % action,
		)
		assertions.expect_equal(
			PackedStringArray(["rare_open"]),
			PackedStringArray(audio_events),
			"%s emits one representative bulk-open sound" % action,
		)

		screen.free()
		context["tree"].root.remove_child(viewport)
		viewport.free()
		await context["tree"].process_frame


func _test_summary(assertions: Variant, context: Dictionary) -> void:
	var catalog := DefinitionCatalog.new()
	assertions.expect_true(catalog.load_and_validate(), "summary catalog valid")
	if not catalog.is_valid:
		return
	var fixture: Dictionary = QaScenarioFactory.build("result_controller", catalog)
	assertions.expect_true(fixture.get("valid", false), "summary fixture valid")
	if not fixture.get("valid", false):
		return
	var screen: RunSummaryScreen = RESULT_SCENE.instantiate() as RunSummaryScreen
	screen.initialize(fixture["state"], catalog)
	var viewport: SubViewport = await _attach(screen, context["tree"])
	var debug: Dictionary = screen.debug_state()
	var build_text: String = str(debug["build_text"])
	for token: String in ["武器1", "武器2", "武器3", "お守り1", "お守り2", "お守り3"]:
		assertions.expect_true(build_text.contains(token), "summary lists %s" % token)
	for removed: String in ["スキル", "ユニーク", "ワイルド"]:
		assertions.expect_false(build_text.contains(removed), "summary omits %s" % removed)
	var score_text: String = str(debug["score_text"])
	assertions.expect_true(score_text.contains("装備中6枠"), "score names equipped-only source")
	assertions.expect_false(score_text.contains("保持装備"), "score no longer counts held inventory")
	assertions.expect_equal(int(debug["combat_score"]) + int(debug["final_build_score"]), int(debug["total"]), "summary score recomposes")
	await _detach(screen, viewport, context["tree"])


func _push_action(viewport: Viewport, action: StringName, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_ENTER if action == &"ui_accept" else KEY_F
	event.pressed = pressed
	viewport.push_input(event)


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
