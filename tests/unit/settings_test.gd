extends RefCounted


const SETTINGS_OVERLAY_SCENE: PackedScene = preload("res://scenes/ui/settings_overlay.tscn")


func test_settings_save_reload_and_tutorial_replay(assertions: Variant, context: Dictionary) -> void:
	var store: Variant = context["settings_store"]
	var tree: SceneTree = context["tree"] as SceneTree
	assertions.expect_false(store.tutorial_completed, "clean settings begin with an incomplete tutorial")
	store.master_volume = 0.37
	store.tutorial_completed = true
	assertions.expect_equal(OK, store.save_settings(), "settings save to the isolated file")
	store.master_volume = 0.75
	store.tutorial_completed = false
	assertions.expect_equal(OK, store.reload_settings(), "saved settings reload")
	assertions.expect_float(0.37, store.master_volume, "saved volume replaces the in-memory value")
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
