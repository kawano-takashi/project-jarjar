extends Node


const LaunchArgumentsScript = preload("res://src/app/launch_arguments.gd")
const DefinitionCatalogScript = preload("res://src/core/definition_catalog.gd")
const RunStateFactoryScript = preload("res://src/core/run_state_factory.gd")
const SeedServiceScript = preload("res://src/core/seed_service.gd")
const TutorialControllerScript = preload("res://src/tutorial/tutorial_controller.gd")
const TutorialOverlayScript = preload("res://src/tutorial/tutorial_overlay.gd")
const AudioVoicePoolScript = preload("res://src/audio/audio_voice_pool.gd")
const SurvivalFeedbackScript = preload("res://src/audio/survival_feedback.gd")

const TITLE_SCENE: PackedScene = preload("res://scenes/ui/title_screen.tscn")
const ARENA_SCENE: PackedScene = preload("res://scenes/gameplay/arena_combat.tscn")
const SURVIVAL_OVERLAY_SCENE: PackedScene = preload("res://scenes/ui/survival_overlay.tscn")
const RESULT_SCENE_PATH: String = "res://scenes/ui/result_screen.tscn"
const FAILED_SCENE_PATH: String = "res://scenes/ui/failed_screen.tscn"
const FIXED_TICK_SECONDS: float = 1.0 / 60.0
const BOSS_DEFEAT_HOLD_TICKS: int = 48
const PLAYER_DEFEAT_HOLD_TICKS: int = 27

var _launch_valid: bool = false
var _launch: Dictionary = {}
var _definition_catalog: DefinitionCatalog = null
var _active_screen: Node = null
var _arena: ArenaPresenter = null
var _survival_overlay: SurvivalOverlay = null
var _smoke_frames_remaining: int = 0
var _logical_phase: GameTypes.RunPhase = GameTypes.RunPhase.BOOT
var _manual_paused: bool = false
var _automatic_modal_chain_active: bool = false
var _tutorial_controller: TutorialController = TutorialControllerScript.new()
var _tutorial_overlay: TutorialOverlay = null
var _audio_pool: AudioVoicePool = null
var _feedback: SurvivalFeedback = null
var _terminal_hold_phase: GameTypes.RunPhase = GameTypes.RunPhase.BOOT
var _terminal_hold_ticks_remaining: int = 0
var _terminal_transition_queued: bool = false
var _terminal_focus_position: Vector2 = Vector2.ZERO
var _terminal_event_audio_received: bool = false

var run_state: RunState = null
var combat_simulation: CombatSimulation = null


func _enter_tree() -> void:
	var arguments := _get_launch_arguments()
	_launch = (
		LaunchArgumentsScript.parse_debug(arguments)
		if OS.is_debug_build()
		else LaunchArgumentsScript.parse_release(arguments)
	)
	if not bool(_launch.get("valid", false)):
		_reject_arguments(str(_launch.get("rejected_name", "missing")))
		return

	var settings_store: Variant = _settings_store()
	if settings_store == null:
		print("SETTINGS_INITIALIZATION_FAILED code=%d" % ERR_DOES_NOT_EXIST)
		_quit_deferred(1)
		return

	var initialize_error: Error = _initialize_settings_for_launch(settings_store)
	if initialize_error != OK:
		print("SETTINGS_INITIALIZATION_FAILED code=%d" % initialize_error)
		_quit_deferred(1)
		return

	_definition_catalog = DefinitionCatalogScript.new()
	if not _definition_catalog.load_and_validate():
		print(
			"DEFINITION_CATALOG_INVALID count=%d"
			% _definition_catalog.validation_errors.size()
		)
		for error: String in _definition_catalog.validation_errors:
			printerr(error)
		_quit_deferred(2)
		return
	_launch_valid = true


func _get_launch_arguments() -> PackedStringArray:
	return OS.get_cmdline_user_args()


func _initialize_settings_for_launch(settings_store: Variant) -> Error:
	var mode: StringName = _launch.get("mode", LaunchArgumentsScript.MODE_NORMAL)
	var initialize_error: Error = (
		settings_store.initialize_ephemeral()
		if mode in [
			LaunchArgumentsScript.MODE_SMOKE_QUIT,
			LaunchArgumentsScript.MODE_QA_SCENARIO,
			LaunchArgumentsScript.MODE_PERFORMANCE,
		]
		else settings_store.initialize_for_game(str(_launch.get("settings_path", "")))
	)
	if initialize_error == OK and mode in [
		LaunchArgumentsScript.MODE_QA_SCENARIO,
		LaunchArgumentsScript.MODE_PERFORMANCE,
	]:
		settings_store.tutorial_completed = true
	return initialize_error


func _ready() -> void:
	if not _launch_valid:
		return
	_initialize_presentation()

	match _launch.get("mode", LaunchArgumentsScript.MODE_NORMAL):
		LaunchArgumentsScript.MODE_QA_SCENARIO:
			_start_qa_mode(str(_launch.get("qa_scenario", "")))
		LaunchArgumentsScript.MODE_PERFORMANCE:
			_start_performance_mode()
		_:
			_show_title()


func _initialize_presentation() -> void:
	_tutorial_controller.completed.connect(_on_tutorial_completed)
	_tutorial_overlay = TutorialOverlayScript.new()
	add_child(_tutorial_overlay)
	_audio_pool = AudioVoicePoolScript.new()
	add_child(_audio_pool)
	_feedback = SurvivalFeedbackScript.new()
	_feedback.initialize(_audio_pool, _settings_store())


func _process(delta: float) -> void:
	if (
		run_state != null
		and run_state.phase == GameTypes.RunPhase.COMBAT
		and not _manual_paused
	):
		_tutorial_controller.advance(maxf(0.0, delta))
	_refresh_tutorial_overlay()


func _physics_process(_delta: float) -> void:
	_advance_smoke_quit()
	_advance_terminal_hold_tick()
	if run_state == null or combat_simulation == null:
		return
	var dimensions := Vector2i(get_viewport().get_visible_rect().size)
	if combat_simulation.view.viewport_size != dimensions:
		combat_simulation.set_viewport_size(dimensions)
		_present_snapshot(combat_simulation.build_snapshot(), 0.0)
	_resolve_terminal_state()
	if run_state.phase != GameTypes.RunPhase.COMBAT or _manual_paused:
		_sync_run_phase()
		return

	var screen_input := Input.get_vector(
		&"move_left",
		&"move_right",
		&"move_up",
		&"move_down",
	)
	var move_input: Vector2 = screen_input
	if _arena != null and _arena.has_method(&"camera_relative_move_input"):
		var camera_input: Variant = _arena.call(&"camera_relative_move_input", screen_input)
		if camera_input is Vector2:
			move_input = camera_input
	var snapshot: CombatSnapshot = combat_simulation.step(move_input)
	var actual_movement: Vector2 = combat_simulation.last_player_displacement
	_tutorial_controller.advance_movement(actual_movement, FIXED_TICK_SECONDS)
	_present_snapshot(snapshot, FIXED_TICK_SECONDS)
	_consume_snapshot_events(snapshot)
	_resolve_terminal_state()
	_sync_run_phase()


func _unhandled_input(event: InputEvent) -> void:
	if (
		run_state == null
		or run_state.phase != GameTypes.RunPhase.COMBAT
		or _survival_overlay == null
		or _survival_overlay.automatic_modal_visible()
		or not event.is_action_pressed(&"ui_cancel")
		or event.is_echo()
	):
		return
	if _manual_paused:
		_on_pause_resume_requested()
	elif _survival_overlay.open_pause():
		_manual_paused = true
		if _arena != null:
			_arena.set_simulation_paused(true)
	get_viewport().set_input_as_handled()


func current_run_phase() -> GameTypes.RunPhase:
	return run_state.phase if run_state != null else _logical_phase


func is_manual_paused() -> bool:
	return _manual_paused


func automatic_modal_chain_active() -> bool:
	return _automatic_modal_chain_active


func terminal_presentation_active() -> bool:
	return _terminal_hold_ticks_remaining > 0 or _terminal_transition_queued


static func terminal_hold_ticks_for_phase(phase: GameTypes.RunPhase) -> int:
	if phase == GameTypes.RunPhase.RESULT:
		return BOSS_DEFEAT_HOLD_TICKS
	if phase == GameTypes.RunPhase.FAILED:
		return PLAYER_DEFEAT_HOLD_TICKS
	return 0


static func terminal_hold_ticks_after_physics_tick(remaining_ticks: int) -> int:
	return maxi(0, remaining_ticks - 1)


func start_new_run_with_seed(run_seed: int) -> bool:
	if _definition_catalog == null:
		_definition_catalog = DefinitionCatalogScript.new()
		if not _definition_catalog.load_and_validate():
			return false
	run_state = RunStateFactoryScript.create(run_seed, _definition_catalog)
	if run_state == null or run_state.weapons.is_empty():
		return false
	var settings_store: Variant = _settings_store()
	_tutorial_controller.begin_run(
		bool(settings_store.tutorial_completed) if settings_store != null else false,
		_definition_catalog,
	)
	combat_simulation = CombatSimulation.new()
	combat_simulation.set_viewport_size(Vector2i(get_viewport().get_visible_rect().size))
	combat_simulation.initialize(run_state, _definition_catalog)
	if _audio_pool != null:
		_audio_pool.reset_admission_metrics()
	if _feedback != null:
		_feedback.reset_run_metrics()
	_reset_terminal_hold()
	_manual_paused = false
	_automatic_modal_chain_active = false
	return _show_combat_arena()


func _start_new_run() -> void:
	start_new_run_with_seed(SeedServiceScript.generate_run_seed())


func _show_title() -> void:
	_clear_survival_overlay()
	_clear_active_screen()
	run_state = null
	combat_simulation = null
	_reset_terminal_hold()
	_manual_paused = false
	_automatic_modal_chain_active = false
	_logical_phase = GameTypes.RunPhase.TITLE
	var title_screen := TITLE_SCENE.instantiate() as Control
	_active_screen = title_screen
	title_screen.connect("start_requested", _start_new_run)
	title_screen.connect("exit_requested", _exit_game)
	add_child(title_screen)
	_refresh_tutorial_overlay()
	_raise_persistent_overlays()
	if _launch.get("mode", LaunchArgumentsScript.MODE_NORMAL) == LaunchArgumentsScript.MODE_SMOKE_QUIT:
		_smoke_frames_remaining = int(_launch.get("smoke_frames", 0))


func _show_combat_arena() -> bool:
	if run_state == null or combat_simulation == null:
		return false
	_clear_survival_overlay()
	_clear_active_screen()
	var arena_node: Node = ARENA_SCENE.instantiate()
	if not arena_node is ArenaPresenter:
		arena_node.free()
		push_error("Arena scene root must be ArenaPresenter")
		return false
	_arena = arena_node as ArenaPresenter
	_active_screen = _arena
	add_child(_arena)
	_arena.initialize(combat_simulation)
	var launch_mode: StringName = _launch.get("mode", LaunchArgumentsScript.MODE_NORMAL)
	_arena.set_debug_overlay_visible(launch_mode in [
		LaunchArgumentsScript.MODE_QA_SCENARIO,
		LaunchArgumentsScript.MODE_PERFORMANCE,
	])

	var overlay_node: Node = SURVIVAL_OVERLAY_SCENE.instantiate()
	if not overlay_node is SurvivalOverlay:
		overlay_node.free()
		push_error("Survival overlay scene root must be SurvivalOverlay")
		return false
	_survival_overlay = overlay_node as SurvivalOverlay
	_survival_overlay.initialize(_definition_catalog)
	_survival_overlay.level_choice_requested.connect(_on_level_choice_requested)
	_survival_overlay.chest_continue_requested.connect(_on_chest_continue_requested)
	_survival_overlay.pause_resume_requested.connect(_on_pause_resume_requested)
	_survival_overlay.title_requested.connect(_show_title)
	_survival_overlay.settings_changed.connect(_on_settings_changed)
	add_child(_survival_overlay)
	_logical_phase = run_state.phase
	_present_snapshot(combat_simulation.build_snapshot(), 0.0)
	_sync_run_phase()
	_raise_persistent_overlays()
	return true


func _sync_run_phase() -> void:
	if run_state == null:
		return
	_logical_phase = run_state.phase
	match run_state.phase:
		GameTypes.RunPhase.LEVEL_UP:
			_present_level_offer()
		GameTypes.RunPhase.CHEST_REWARD:
			_present_chest_outcome()
		GameTypes.RunPhase.RESULT:
			if not _active_screen is ResultScreen:
				_sync_terminal_presentation(GameTypes.RunPhase.RESULT)
		GameTypes.RunPhase.FAILED:
			if not _active_screen is FailedScreen:
				_sync_terminal_presentation(GameTypes.RunPhase.FAILED)
		GameTypes.RunPhase.COMBAT:
			if _survival_overlay != null and _survival_overlay.automatic_modal_visible():
				_survival_overlay.hide_automatic_modal()
			_automatic_modal_chain_active = false


func _present_level_offer() -> void:
	if _survival_overlay == null or run_state.active_level_offer == null:
		return
	var serial: int = run_state.active_level_offer.serial
	if (
		_survival_overlay.automatic_modal_visible()
		and _survival_overlay.active_offer_serial() == serial
	):
		return
	_survival_overlay.show_level_offer(run_state.active_level_offer)
	_feedback.play(&"level_up")
	_tutorial_controller.notify_context(&"level_up")
	_automatic_modal_chain_active = true


func _present_chest_outcome() -> void:
	if _survival_overlay == null or run_state.active_chest_outcome == null:
		return
	var serial: int = run_state.active_chest_outcome.serial
	if (
		_survival_overlay.automatic_modal_visible()
		and _survival_overlay.active_chest_serial() == serial
	):
		return
	_survival_overlay.show_chest_outcome(run_state.active_chest_outcome)
	_feedback.play(&"chest_open")
	if run_state.active_chest_outcome.kind == GameTypes.ChestOutcomeKind.EVOLUTION:
		_feedback.play(&"evolution")
		_tutorial_controller.notify_context(&"evolution")
	_automatic_modal_chain_active = true


func _on_level_choice_requested(choice_index: int) -> void:
	if (
		run_state == null
		or run_state.phase != GameTypes.RunPhase.LEVEL_UP
		or run_state.active_level_offer == null
	):
		return
	if not combat_simulation.apply_upgrade_choice(choice_index):
		push_error("Level-up choice failed")
		_survival_overlay.hide_automatic_modal()
		_present_level_offer()
		return
	_survival_overlay.hide_automatic_modal()
	_sync_run_phase()


func _on_chest_continue_requested() -> void:
	if (
		run_state == null
		or run_state.phase != GameTypes.RunPhase.CHEST_REWARD
		or run_state.active_chest_outcome == null
	):
		return
	if not combat_simulation.skip_chest_animation():
		push_error("Chest outcome failed")
		_survival_overlay.hide_automatic_modal()
		_present_chest_outcome()
		return
	_survival_overlay.hide_automatic_modal()
	_sync_run_phase()


func _on_pause_resume_requested() -> void:
	if not _manual_paused:
		return
	_manual_paused = false
	if _arena != null:
		_arena.set_simulation_paused(false)
	if _survival_overlay != null and _survival_overlay.pause_visible():
		_survival_overlay.close_pause()


func _on_settings_changed(_values: Dictionary) -> void:
	if _arena != null:
		_arena.refresh_accessibility()


func _resolve_terminal_state() -> void:
	if run_state == null or run_state.phase != GameTypes.RunPhase.COMBAT:
		return
	if run_state.boss_defeated:
		RunStateMachine.resolve_terminal(run_state, false, true)
	elif run_state.current_hp <= 0.0:
		RunStateMachine.resolve_terminal(run_state, true, false)


func _present_snapshot(snapshot: CombatSnapshot, delta: float) -> void:
	if _arena != null and snapshot != null:
		_arena.present_snapshot(snapshot, delta)
	if _survival_overlay != null and snapshot != null:
		_survival_overlay.update_build_from_values(snapshot.hud_values)
	if snapshot != null:
		_terminal_focus_position = snapshot.player_position
		if snapshot.important_marker_active:
			_terminal_focus_position = snapshot.important_marker_position


func _consume_snapshot_events(snapshot: CombatSnapshot) -> void:
	if snapshot == null:
		return
	var played_event_ids: Dictionary[StringName, bool] = {}
	for event: CombatPresentationEvent in snapshot.presentation_events:
		if event == null:
			continue
		var typed_event_id: StringName = event.resolved_event_id()
		if _arena != null:
			_arena.present_event(event)
		if _feedback != null:
			_feedback.play_presentation_event(event)
		if not typed_event_id.is_empty():
			played_event_ids[typed_event_id] = true
			_tutorial_controller.notify_context(typed_event_id)
		if event.kind == CombatPresentationEvent.Kind.BOSS_DEFEATED:
			_terminal_focus_position = event.position
			_terminal_event_audio_received = true
		elif event.kind == CombatPresentationEvent.Kind.PLAYER_DEFEATED:
			_terminal_focus_position = event.position
			_terminal_event_audio_received = true
	var events_value: Variant = snapshot.hud_values.get("events", [])
	if not events_value is Array:
		return
	for raw_event: Variant in events_value as Array:
		var event_id := StringName(str(raw_event))
		if event_id != &"chest_pickup" and not played_event_ids.has(event_id):
			_feedback.play(event_id)
		_tutorial_controller.notify_context(event_id)


func _sync_terminal_presentation(phase: GameTypes.RunPhase) -> void:
	if _terminal_transition_queued:
		return
	if _terminal_hold_phase == phase:
		if _terminal_hold_ticks_remaining <= 0:
			_queue_terminal_summary(phase)
		return
	_terminal_hold_phase = phase
	_terminal_hold_ticks_remaining = terminal_hold_ticks_for_phase(phase)
	_manual_paused = false
	if _survival_overlay != null and _survival_overlay.pause_visible():
		_survival_overlay.close_pause()
	if _arena != null:
		var prefer_important: bool = phase == GameTypes.RunPhase.RESULT
		var focus_position: Vector2 = _terminal_focus_position
		if focus_position == Vector2.ZERO:
			focus_position = _arena.terminal_focus_position(prefer_important)
		_terminal_focus_position = focus_position
		_arena.begin_terminal_presentation(phase, focus_position)
	else:
		_terminal_hold_ticks_remaining = 0
	if not _terminal_event_audio_received and _feedback != null:
		_feedback.play(
			&"boss_defeated" if phase == GameTypes.RunPhase.RESULT else &"player_defeated",
			AudioVoicePool.Priority.TERMINAL,
			&"terminal",
			1.0,
			true,
		)


func _advance_terminal_hold_tick() -> void:
	if _terminal_hold_ticks_remaining <= 0:
		return
	_terminal_hold_ticks_remaining = terminal_hold_ticks_after_physics_tick(
		_terminal_hold_ticks_remaining
	)
	if _terminal_hold_ticks_remaining <= 0:
		_queue_terminal_summary(_terminal_hold_phase)


func _queue_terminal_summary(phase: GameTypes.RunPhase) -> void:
	if _terminal_transition_queued:
		return
	_terminal_transition_queued = true
	if phase == GameTypes.RunPhase.RESULT:
		_show_result.call_deferred()
	elif phase == GameTypes.RunPhase.FAILED:
		_show_failed.call_deferred()


func _reset_terminal_hold() -> void:
	_terminal_hold_phase = GameTypes.RunPhase.BOOT
	_terminal_hold_ticks_remaining = 0
	_terminal_transition_queued = false
	_terminal_focus_position = Vector2.ZERO
	_terminal_event_audio_received = false


func _show_result() -> bool:
	return _show_run_summary(RESULT_SCENE_PATH, GameTypes.RunPhase.RESULT)


func _show_failed() -> bool:
	return _show_run_summary(FAILED_SCENE_PATH, GameTypes.RunPhase.FAILED)


func _show_run_summary(scene_path: String, phase: GameTypes.RunPhase) -> bool:
	if run_state == null or run_state.phase != phase:
		return false
	var screen: Control = _instantiate_control_scene(scene_path)
	if screen == null:
		return false
	_clear_survival_overlay()
	_clear_active_screen()
	_active_screen = screen
	screen.connect("retry_same_seed_requested", _retry_same_seed)
	screen.connect("retry_new_seed_requested", _retry_new_seed)
	screen.connect("title_requested", _show_title)
	screen.connect("exit_requested", _exit_game)
	screen.call("initialize", run_state, _definition_catalog)
	add_child(screen)
	_reset_terminal_hold()
	_logical_phase = phase
	_manual_paused = false
	_refresh_tutorial_overlay()
	_raise_persistent_overlays()
	return true


func _refresh_tutorial_overlay() -> void:
	if _tutorial_overlay == null or not is_instance_valid(_tutorial_overlay):
		return
	if run_state == null or run_state.phase != GameTypes.RunPhase.COMBAT:
		_tutorial_overlay.hide_message()
		return
	var message: String = _tutorial_controller.current_message()
	if message.is_empty():
		_tutorial_overlay.hide_message()
	else:
		_tutorial_overlay.show_message(message)


func _on_tutorial_completed() -> void:
	var settings_store: Variant = _settings_store()
	if settings_store == null:
		return
	settings_store.tutorial_completed = true
	if str(settings_store.active_settings_path).is_empty():
		return
	var save_error: Error = settings_store.save_settings()
	if save_error != OK:
		push_error("Tutorial setting save failed: %d" % save_error)


func _raise_persistent_overlays() -> void:
	if (
		_tutorial_overlay != null
		and is_instance_valid(_tutorial_overlay)
		and _tutorial_overlay.get_parent() == self
	):
		move_child(_tutorial_overlay, get_child_count() - 1)
	if (
		_survival_overlay != null
		and is_instance_valid(_survival_overlay)
		and _survival_overlay.get_parent() == self
	):
		move_child(_survival_overlay, get_child_count() - 1)


func _start_performance_mode() -> void:
	if not start_new_run_with_seed(int(_launch.get("run_seed", 0))):
		print("PERFORMANCE_FAILED reasons=start_run_failed")
		get_tree().quit(1)
		return
	var runner_script: Variant = load("res://src/debug/performance_runner.gd")
	if runner_script == null:
		print("PERFORMANCE_FAILED reasons=runner_missing")
		get_tree().quit(1)
		return
	var runner: Node = runner_script.new()
	runner.connect("completed", _on_performance_completed)
	add_child(runner)
	var initialize_error: Error = runner.call(
		"initialize",
		combat_simulation,
	)
	if initialize_error != OK:
		print("PERFORMANCE_FAILED reasons=%s" % str(runner.get("last_error_message")))
		get_tree().quit(1)


func _on_performance_completed(exit_code: int, _summary: Dictionary) -> void:
	get_tree().quit(exit_code)


func _start_qa_mode(scenario_id: String) -> void:
	var factory_script: Variant = load("res://src/debug/qa_scenario_factory.gd")
	if factory_script == null:
		print("QA_SCENARIO_FAILED reason=factory")
		get_tree().quit(1)
		return
	var result: Dictionary = factory_script.build(scenario_id, _definition_catalog)
	if not bool(result.get("valid", false)):
		print("QA_SCENARIO_REJECTED name=--qa-scenario")
		get_tree().quit(2)
		return
	run_state = result.get("state") as RunState
	combat_simulation = result.get("simulation") as CombatSimulation
	if run_state == null:
		print("QA_SCENARIO_FAILED reason=state")
		get_tree().quit(1)
		return
	_tutorial_controller.begin_run(true, _definition_catalog)
	match run_state.phase:
		GameTypes.RunPhase.RESULT:
			_show_result()
		GameTypes.RunPhase.FAILED:
			_show_failed()
		_:
			if combat_simulation == null or not _show_combat_arena():
				print("QA_SCENARIO_FAILED reason=combat")
				get_tree().quit(1)


func _retry_same_seed() -> void:
	if run_state != null:
		start_new_run_with_seed(run_state.run_seed)


func _retry_new_seed() -> void:
	start_new_run_with_seed(SeedServiceScript.generate_run_seed())


func _instantiate_control_scene(scene_path: String) -> Control:
	var resource: Resource = load(scene_path)
	if not resource is PackedScene:
		push_error("Missing UI scene: %s" % scene_path)
		return null
	var node: Node = (resource as PackedScene).instantiate()
	if not node is Control:
		node.free()
		push_error("UI scene root must be Control: %s" % scene_path)
		return null
	return node as Control


func _clear_survival_overlay() -> void:
	if _survival_overlay == null:
		return
	var previous_overlay: SurvivalOverlay = _survival_overlay
	_survival_overlay = null
	if previous_overlay.get_parent() == self:
		remove_child(previous_overlay)
	previous_overlay.queue_free()


func _clear_active_screen() -> void:
	if _active_screen == null:
		return
	var previous_screen: Node = _active_screen
	_active_screen = null
	if previous_screen == _arena:
		_arena = null
	if previous_screen.get_parent() == self:
		remove_child(previous_screen)
	previous_screen.queue_free()


func _advance_smoke_quit() -> void:
	if _smoke_frames_remaining <= 0:
		return
	_smoke_frames_remaining -= 1
	if _smoke_frames_remaining == 0:
		get_tree().quit(0)


func _settings_store() -> Variant:
	return get_node_or_null("/root/SettingsStore") if is_inside_tree() else null


func _reject_arguments(argument_name: String) -> void:
	if OS.is_debug_build():
		print("DEBUG_ARGUMENT_REJECTED name=%s child_nodes=0 run_state=0" % argument_name)
	else:
		print("RELEASE_ARGUMENT_REJECTED name=%s" % argument_name)
	_quit_deferred(2)


func _quit_deferred(exit_code: int) -> void:
	get_tree().call_deferred("quit", exit_code)


func _exit_game() -> void:
	get_tree().quit(0)
