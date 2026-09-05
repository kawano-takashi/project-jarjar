extends RefCounted


const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")


class AppUnderTest extends "res://src/app/game_app.gd":


	# Reuse the runner's isolated settings through the existing initialization hook.
	func _initialize_settings_for_launch(settings_store: Variant) -> Error:
		return OK if settings_store.runner_safe_mode else ERR_UNAUTHORIZED


func test_game_starts_pauses_upgrades_finishes_and_restarts(a: Variant, context: Dictionary) -> void:
	var tree: SceneTree = context["tree"]
	var scene := MAIN_SCENE.instantiate()
	a.expect_equal(preload("res://src/app/game_app.gd"), scene.get_script(), "main scene starts the game app")
	scene.set_script(AppUnderTest)
	var app := scene as AppUnderTest
	tree.root.add_child(app)
	app.set_physics_process(false)
	await tree.process_frame
	var content := BalanceTestFixtures.manifest()
	content.progression.xp_yield_percent = 100
	var catalog := DefinitionCatalog.new()
	a.expect_true(catalog.validate_manifest(content), "game flow uses detached XP input")
	app._definition_catalog = catalog
	await _exercise_run_buttons(app, a, tree)
	app._audio_pool.stop_all()
	# The audio server releases stopped playback on its own mix cycle.
	await tree.create_timer(0.1).timeout
	app.queue_free()
	await tree.process_frame


func _exercise_run_buttons(app: AppUnderTest, a: Variant, tree: SceneTree) -> void:
	for terminal_phase: GameTypes.RunPhase in [GameTypes.RunPhase.FAILED, GameTypes.RunPhase.RESULT]:
		a.expect_equal(GameTypes.RunPhase.TITLE, app.current_run_phase(), "title is ready for a new run")
		(app._active_screen.get_node("%TitleStart") as Button).pressed.emit()
		await tree.process_frame
		a.expect_equal(GameTypes.RunPhase.COMBAT, app.current_run_phase(), "start button enters combat")
		a.expect_float(app.run_state.max_hp, app.run_state.current_hp, "new run starts with full health")
		a.expect_equal(0, app.run_state.combat_tick, "new run resets the clock")

		var pause := InputEventAction.new()
		pause.action = &"ui_cancel"
		pause.pressed = true
		app._unhandled_input(pause)
		a.expect_true(app.is_manual_paused(), "cancel input opens pause")
		app._physics_process(1.0 / 60.0)
		a.expect_equal(0, app.run_state.combat_tick, "pause freezes combat time")
		(app._survival_overlay.get_node("%PauseResume") as Button).pressed.emit()
		a.expect_false(app.is_manual_paused(), "resume button resumes combat")

		var catalog: DefinitionCatalog = app.combat_simulation.catalog
		ProgressionService.add_xp(app.run_state, ProgressionService.xp_required_for_level(1, catalog.manifest().progression), catalog)
		app._physics_process(1.0 / 60.0)
		await tree.process_frame
		a.expect_equal(GameTypes.RunPhase.LEVEL_UP, app.current_run_phase(), "earned XP opens a level choice")
		(app._survival_overlay.get_node("%LevelChoice0") as Button).pressed.emit()
		a.expect_equal(GameTypes.RunPhase.COMBAT, app.current_run_phase(), "choice button applies the upgrade and resumes")
		a.expect_equal(0, app.run_state.pending_level_ups, "chosen upgrade is consumed")

		app.run_state.pending_chest_sources.append(0)
		app._physics_process(1.0 / 60.0)
		await tree.process_frame
		a.expect_equal(GameTypes.RunPhase.CHEST_REWARD, app.current_run_phase(), "collected chest opens its reward")
		app._survival_overlay.get_node("%ChestContinue").emit_signal("activated")
		a.expect_equal(GameTypes.RunPhase.COMBAT, app.current_run_phase(), "chest control applies its reward and resumes")
		a.expect_equal(1, app.run_state.opened_chests, "chest reward is applied once")

		app.run_state.boss_defeated = terminal_phase == GameTypes.RunPhase.RESULT
		app.run_state.current_hp = 0.0 if terminal_phase == GameTypes.RunPhase.FAILED else app.run_state.max_hp
		app._physics_process(1.0 / 60.0)
		for _tick in range(AppUnderTest.terminal_hold_ticks_for_phase(terminal_phase) + 1):
			app._physics_process(1.0 / 60.0)
		await tree.process_frame
		await tree.process_frame
		a.expect_equal(terminal_phase, app.current_run_phase(), "victory or defeat reaches its terminal state")
		if terminal_phase == GameTypes.RunPhase.RESULT:
			a.expect_true(app._active_screen is ResultScreen, "victory displays its result screen")
		else:
			a.expect_true(app._active_screen is FailedScreen, "defeat displays its failed screen")
		(app._active_screen.get_node("%SummaryTitleButton") as Button).pressed.emit()
		await tree.process_frame
		a.expect_equal(null, app.run_state, "return to title releases the completed run")
