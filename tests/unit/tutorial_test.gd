extends RefCounted


const SETTINGS_OVERLAY_SCENE: PackedScene = preload("res://scenes/ui/settings_overlay.tscn")


func test_names() -> PackedStringArray:
	return PackedStringArray([
		"tutorial_contextual_sequence",
		"completed_tutorial_skips_contextual_hints",
		"tutorial_completion_persists_and_settings_can_replay",
	])


func run_test(test_name: String, assertions: Variant, context: Dictionary) -> void:
	match test_name:
		"tutorial_contextual_sequence":
			_test_contextual_sequence(assertions)
		"completed_tutorial_skips_contextual_hints":
			_test_completed_tutorial(assertions)
		"tutorial_completion_persists_and_settings_can_replay":
			await _test_saved_completion(assertions, context)
		_:
			assertions.expect_true(false, "registered survival tutorial test")


func _test_contextual_sequence(assertions: Variant) -> void:
	var tutorial := TutorialController.new()
	var completions: Array[bool] = []
	tutorial.completed.connect(func() -> void:
		completions.append(true)
	)
	tutorial.begin_run(false, BalanceTestFixtures.catalog())
	assertions.expect_true(tutorial.enabled, "incomplete tutorial enables contextual hints")
	assertions.expect_equal(TutorialController.MOVE_MESSAGE, tutorial.current_message(), "movement and automatic attack appear first")
	for _tick: int in range(59):
		tutorial.advance_movement(Vector2.RIGHT, 1.0 / 60.0)
	assertions.expect_false(tutorial.move_completed, "59 movement ticks do not complete onboarding")
	assertions.expect_true(tutorial.advance_movement(Vector2.RIGHT, 1.0 / 60.0), "60th movement tick completes onboarding")
	assertions.expect_false(tutorial.advance_movement(Vector2.RIGHT, 1.0), "completed movement cannot emit twice")
	assertions.expect_equal([true], completions, "tutorial completion emits exactly once")

	for context_id: StringName in [
		&"xp_pickup",
		&"level_up",
		&"chest_pickup",
		&"evolution",
		&"stop_pickup",
		&"boss_spawn",
	]:
		assertions.expect_true(tutorial.notify_context(context_id), "%s displays on first encounter" % context_id)
		assertions.expect_false(tutorial.current_message().is_empty(), "%s has contextual text" % context_id)
		if context_id == &"evolution":
			assertions.expect_equal(
				"武器が最大Lv、触媒がLv1以上なら宝箱から進化。触媒は最大Lv不要・進化後も消費されません",
				tutorial.current_message(),
				"evolution tutorial explains the complete catalyst contract",
			)
		assertions.expect_false(tutorial.notify_context(context_id), "%s never repeats in the same run" % context_id)
		tutorial.advance(TutorialController.CONTEXT_MESSAGE_SECONDS)
		assertions.expect_equal("", tutorial.current_message(), "%s expires without input" % context_id)


func _test_completed_tutorial(assertions: Variant) -> void:
	var tutorial := TutorialController.new()
	tutorial.begin_run(true, BalanceTestFixtures.catalog())
	assertions.expect_false(tutorial.enabled, "completed tutorial suppresses first-run hints")
	assertions.expect_true(tutorial.move_completed, "completed tutorial never gates movement")
	assertions.expect_equal("", tutorial.current_message(), "completed tutorial has no initial message")
	assertions.expect_false(tutorial.notify_context(&"level_up"), "completed tutorial suppresses context")


func _test_saved_completion(assertions: Variant, context: Dictionary) -> void:
	var store: Variant = context["settings_store"]
	var tree: SceneTree = context["tree"] as SceneTree
	assertions.expect_false(store.tutorial_completed, "clean settings begin with an incomplete tutorial")
	store.master_volume = 0.37
	store.tutorial_completed = true
	assertions.expect_equal(OK, store.save_settings(), "completed tutorial saves to the isolated settings file")
	store.tutorial_completed = false
	assertions.expect_equal(OK, store.reload_settings(), "saved settings reload")
	assertions.expect_true(store.tutorial_completed, "completion survives a settings reload")
	var tutorial := TutorialController.new()
	tutorial.begin_run(store.tutorial_completed, BalanceTestFixtures.catalog())
	assertions.expect_false(tutorial.enabled, "saved completion suppresses the next run's hints")

	var overlay := SETTINGS_OVERLAY_SCENE.instantiate() as SettingsOverlay
	tree.root.add_child(overlay)
	await tree.process_frame
	overlay.open_overlay()
	var replay_button := overlay.focus_control("settings_tutorial_again") as Button
	replay_button.pressed.emit()
	assertions.expect_false(store.tutorial_completed, "the replay button clears completion")
	overlay.close_overlay()
	store.tutorial_completed = true
	assertions.expect_equal(OK, store.reload_settings(), "closing settings persists the replay request")
	assertions.expect_false(store.tutorial_completed, "replay request survives reload")
	assertions.expect_float(0.37, store.master_volume, "replaying the tutorial preserves other settings")
	tutorial.begin_run(store.tutorial_completed, BalanceTestFixtures.catalog())
	assertions.expect_true(tutorial.enabled, "replay request enables movement and contextual hints")
	overlay.queue_free()
	await tree.process_frame

	var config := ConfigFile.new()
	config.set_value("settings", "master_volume", 0.37)
	assertions.expect_equal(OK, config.save(str(store.active_settings_path)), "settings without tutorial state save")
	assertions.expect_equal(OK, store.reload_settings(), "settings without tutorial state load")
	assertions.expect_false(store.tutorial_completed, "missing completion defaults to incomplete")
	config.set_value("settings", "tutorial_completed", 4)
	assertions.expect_equal(OK, config.save(str(store.active_settings_path)), "malformed completion fixture saves")
	assertions.expect_equal(OK, store.reload_settings(), "malformed completion does not prevent loading settings")
	assertions.expect_false(store.tutorial_completed, "non-boolean completion defaults to incomplete")
	assertions.expect_float(0.37, store.master_volume, "defaulting tutorial completion preserves unrelated settings")
