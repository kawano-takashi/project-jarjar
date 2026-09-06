extends RefCounted

const BotObserver = preload("res://dev/bot/bot_observer.gd")
const BotSession = preload("res://dev/bot/bot_session.gd")
const ARENA_SCENE: PackedScene = preload("res://scenes/gameplay/arena_combat.tscn")


class BotWatchApp extends "res://dev/bot/bot_app.gd":
	var dimensions := Vector2i(1920, 1080)

	func _get_launch_arguments() -> PackedStringArray:
		return PackedStringArray(["--bot=watch", "--run-seed=778", "--bot-view=%dx%d" % [dimensions.x, dimensions.y]])

	func _initialize_settings_for_launch(settings_store: Variant) -> Error:
		return OK if settings_store.runner_safe_mode else ERR_UNAUTHORIZED

	func _report_bot(_message: String) -> void:
		pass


func test_bot_watch_and_fast_paths_share_decisions_and_gameplay(a: Variant, context: Dictionary) -> void:
	var tree: SceneTree = context["tree"]
	var window: Window = tree.root
	var previous: Array = [window.content_scale_size, window.content_scale_mode, window.content_scale_aspect, window.title]
	for speed: int in [1, 4, 16]:
		var app := BotWatchApp.new()
		if speed == 4:
			app.dimensions = Vector2i(1024, 768)
		tree.root.add_child(app)
		app.set_process(false)
		app.set_physics_process(false)
		app._launch["bot_speed"] = speed
		await tree.process_frame
		await tree.process_frame
		var viewport_bounds: Rect2 = app.get_viewport().get_visible_rect().grow(1.0)
		var hud := app._arena.get_node("%CombatHUD") as CombatHud
		for field_name: String in ["TimeValue", "LevelKills", "HpValue", "XpValue", "Weapons", "Passives"]:
			var field := hud.get_node("%%%s" % field_name) as Control
			a.expect_true(viewport_bounds.encloses(field.get_global_rect()), "watch HUD keeps %s on screen at %s" % [field_name, app.dimensions])
		var fast := BotSession.new()
		a.expect_true(fast.initialize(app._definition_catalog, 778, app.dimensions), "comparison run starts with the same initial state")
		for frame_index: int in 30:
			if frame_index in [0, 12]:
				for sim: CombatSimulation in [app.combat_simulation, fast.simulation]:
					sim.state.pending_level_ups = 1
					sim.state.pending_chest_sources.append(0)
					sim._resolve_modal_priority()
			app._process_watched_bot()
			while fast.action_count < app._bot_session.action_count:
				if not fast.advance():
					break
		a.expect_equal(fast.action_digest, app._bot_session.action_digest, "watch speed does not change movement or modal choices")
		a.expect_equal(_gameplay_digest(fast.simulation), _gameplay_digest(app.combat_simulation), "rendering does not change gameplay or random streams")
		a.expect_equal(fast.view.camera_transform, app._bot_session.view.camera_transform, "camera advances exactly once per combat tick")
		app._manual_paused = true
		var actions_before: int = app._bot_session.action_count
		app._process_watched_bot()
		a.expect_equal(actions_before, app._bot_session.action_count, "manual pause stops bot actions")
		app.run_state.phase = GameTypes.RunPhase.FAILED
		a.expect_true(app._show_failed(), "watched defeat displays the normal result controls")
		app._retry_same_seed()
		a.expect_equal(778, app.run_state.run_seed, "watched retry preserves the requested seed")
		a.expect_equal(0, app.run_state.combat_tick, "watched retry starts a fresh ordinary run")
		app.run_state.combat_tick = BotSession.MAX_COMBAT_TICKS
		app._bot_session.advance()
		app._finish_bot_session()
		a.expect_true(app._active_screen is RunSummaryScreen, "watch time limit leaves a result screen")
		a.expect_equal(&"timeout", app._bot_session.result, "the watched result retains its time-limit classification")
		app._show_title()
		a.expect_false(app._is_bot_launch(), "returning to the title restores ordinary play")
		a.expect_equal(previous[2], window.content_scale_aspect, "leaving watch mode restores ordinary window scaling")
		app._manual_paused = true
		app._audio_pool.stop_all()
		await tree.create_timer(0.1).timeout
		app.queue_free()
		await tree.process_frame
	window.content_scale_size = previous[0]
	window.content_scale_mode = previous[1]
	window.content_scale_aspect = previous[2]
	window.title = previous[3]


func _gameplay_digest(simulation: CombatSimulation) -> String:
	var state: RunState = simulation.state
	return str([
		state.phase, state.combat_tick, simulation.player_position,
		state.current_hp, state.level, state.xp, state.total_kills,
		state.pending_level_ups, state.pending_chest_count(),
		state.weapon_damage_by_lineage, state.rng_streams.state_digest(),
	])


func test_observer_projection_matches_following_camera_and_partial_edges(a: Variant, context: Dictionary) -> void:
	var tree: SceneTree = context["tree"]
	var arena := ARENA_SCENE.instantiate() as ArenaPresenter
	var viewport: SubViewport = await _attach(arena, tree)
	var camera := arena.get_node("%ArenaCamera") as Camera3D
	for dimensions: Vector2i in [Vector2i(1920, 1080), Vector2i(1024, 768)]:
		viewport.size = dimensions
		await tree.process_frame
		var hud := arena.get_node("%CombatHUD") as CombatHud
		a.expect_equal(Vector2.ONE, hud.scale, "ordinary play keeps its HUD scale at either viewport size")
		for step_index: int in 30:
			arena._update_camera(Vector2(step_index, -step_index) * 0.06, 1.0 / 60.0)
		for point: Vector3 in [Vector3.ZERO, Vector3(4, 1, -2), Vector3(-3, 4, 5)]:
			var expected: Vector2 = camera.unproject_position(point)
			var actual: Vector2 = arena.view.project_position(point)
			a.expect_true(expected.distance_to(actual) < 0.01, "headless projection follows the actual camera at both aspect ratios")
		var half_width: float = camera.size * 0.5 * float(dimensions.x) / float(dimensions.y)
		var edge: Vector3 = camera.transform * Vector3(half_width + 0.2, 0.0, -20.0)
		var bounds := AABB(Vector3.ONE * -0.3, Vector3.ONE * 0.6)
		a.expect_false(camera.is_position_in_frustum(edge), "the center is outside the screen")
		a.expect_true(BotObserver.Culler.new(arena.view).contains_visual(Transform3D(Basis.IDENTITY, edge), bounds), "a partially visible object remains observable")
		var outside: Vector3 = camera.transform * Vector3(half_width + 1.0, 0.0, -20.0)
		a.expect_false(BotObserver.Culler.new(arena.view).contains_visual(Transform3D(Basis.IDENTITY, outside), bounds), "an entirely offscreen object is excluded")
	await _detach(arena, viewport, tree)


func _attach(arena: ArenaPresenter, tree: SceneTree) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	tree.root.add_child(viewport)
	viewport.add_child(arena)
	await tree.process_frame
	await tree.process_frame
	return viewport


func _detach(arena: ArenaPresenter, viewport: SubViewport, tree: SceneTree) -> void:
	viewport.remove_child(arena)
	arena.free()
	tree.root.remove_child(viewport)
	viewport.free()
	await tree.process_frame
