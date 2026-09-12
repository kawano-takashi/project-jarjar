extends "res://src/app/game_app.gd"

const BotSession = preload("res://dev/bot/bot_session.gd")
const BotArguments = preload("res://dev/bot/launch_arguments.gd")
const WatchHudLayout = preload("res://dev/bot/watch_hud_layout.gd")

var _bot_active: bool = true
var _bot_session: BotSession = null
var _bot_completed_runs: int = 0
var _bot_wins: int = 0
var _bot_summary_printed: bool = false
var _bot_next_report_tick: int = 18000
var _bot_errors: BotErrorMonitor = null
var _bot_window_settings: Array = []


class BotErrorMonitor extends Logger:
	var _mutex := Mutex.new()
	var _errors: int = 0

	func _log_error(
		_function: String, _file: String, _line: int, _code: String, _rationale: String,
		_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace],
	) -> void:
		if error_type != Logger.ERROR_TYPE_WARNING:
			_mutex.lock()
			_errors += 1
			_mutex.unlock()

	func count() -> int:
		_mutex.lock()
		var value: int = _errors
		_mutex.unlock()
		return value


class TimeoutScreen extends FailedScreen:
	func _render() -> void:
		super()
		if is_node_ready():
			_heading.text = "RUN TIMEOUT"

	func _boss_result_text(_state: RunState) -> String:
		return "TIME LIMIT (30:00)"


func _enter_tree() -> void:
	if not OS.is_debug_build():
		_report_bot("BOT_ERROR development_build_required")
		_quit_deferred(2)
		return
	_launch = BotArguments.parse(_get_launch_arguments())
	if not bool(_launch.get("valid", false)):
		_reject_arguments(str(_launch.get("rejected_name", "missing")))
		return
	if not _initialize_combat_native():
		return
	_bot_errors = BotErrorMonitor.new()
	OS.add_logger(_bot_errors)

	var settings_store: Variant = _settings_store()
	if settings_store == null:
		print("SETTINGS_INITIALIZATION_FAILED code=%d" % ERR_DOES_NOT_EXIST)
		_quit_deferred(2)
		return

	var initialize_error: Error = _initialize_settings_for_launch(settings_store)
	if initialize_error != OK:
		print("SETTINGS_INITIALIZATION_FAILED code=%d" % initialize_error)
		_quit_deferred(2)
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


func _initialize_settings_for_launch(settings_store: Variant) -> Error:
	var initialize_error: Error = settings_store.initialize_ephemeral()
	if initialize_error == OK:
		settings_store.tutorial_completed = true
	return initialize_error


func _ready() -> void:
	if not _launch_valid:
		return
	if _launch["bot"] == "watch":
		_initialize_presentation()
	_start_bot_session()


func _process(delta: float) -> void:
	if not _bot_active:
		super(delta)
	elif _launch_valid:
		if _bot_errors != null and _bot_errors.count() > 0 and _bot_session == null:
			_report_bot("BOT_ERROR engine_or_script_error")
			set_process(false)
			_quit_deferred(2)
		elif _launch["bot"] == "fast":
			_process_fast_bot()
		elif _launch["bot"] == "watch":
			_render_current_snapshot(delta)


func _physics_process(delta: float) -> void:
	if not _bot_active:
		super(delta)
	elif _launch_valid:
		_advance_terminal_hold_tick()
		if _launch["bot"] == "watch":
			_process_watched_bot()


func _is_bot_launch() -> bool:
	return _bot_active


func _show_title() -> void:
	if _is_bot_launch():
		if not _bot_window_settings.is_empty():
			var window: Window = get_window()
			window.content_scale_size = _bot_window_settings[0]
			window.content_scale_mode = _bot_window_settings[1]
			window.content_scale_aspect = _bot_window_settings[2]
			window.title = _bot_window_settings[3]
			_bot_window_settings.clear()
		if _bot_errors != null:
			OS.remove_logger(_bot_errors)
			_bot_errors = null
		_bot_active = false
		_bot_session = null
	super()


func _on_level_choice_requested(choice_index: int) -> void:
	if not _bot_active:
		super(choice_index)


func _on_chest_continue_requested() -> void:
	if not _bot_active:
		super()


func _retry_same_seed() -> void:
	if _is_bot_launch() and _launch["bot"] == "watch":
		_bot_completed_runs = 0
		_bot_wins = 0
		_start_bot_session()
		return
	super()


func _retry_new_seed() -> void:
	if _is_bot_launch() and _launch["bot"] == "watch":
		_launch["run_seed"] = SeedServiceScript.generate_run_seed()
		_retry_same_seed()
		return
	super()


func _instantiate_control_scene(scene_path: String) -> Control:
	var screen: Control = super(scene_path)
	if screen != null and _bot_session != null and _bot_session.result == &"timeout" and scene_path == FAILED_SCENE_PATH:
		screen.set_script(TimeoutScreen)
	return screen


func _start_bot_session() -> void:
	_bot_session = BotSession.new()
	_bot_summary_printed = false
	_bot_next_report_tick = 18000
	var seed_value: int = int(_launch["run_seed"]) + _bot_completed_runs
	if not _bot_session.initialize(_definition_catalog, seed_value, _launch["bot_view"], _launch["bot_profile"]):
		_report_bot("BOT_ERROR " + _bot_session.error_message)
		set_process(false)
		set_physics_process(false)
		_quit_deferred(2)
		return
	run_state = _bot_session.simulation.state
	combat_simulation = _bot_session.simulation
	if _launch["bot"] == "watch":
		var window: Window = get_window()
		if _bot_window_settings.is_empty():
			_bot_window_settings = [window.content_scale_size, window.content_scale_mode, window.content_scale_aspect, window.title]
		window.content_scale_size = _launch["bot_view"]
		window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
		window.title = "Project JARJAR — BOT ×%d — seed %d" % [int(_launch["bot_speed"]), seed_value]
		_reset_terminal_hold()
		_manual_paused = false
		if not _show_combat_arena():
			_quit_deferred(2)
			return
		var hud := _arena.get_node("%CombatHUD") as CombatHud
		hud.add_child(WatchHudLayout.new())
		_render_dirty = true
		_render_current_snapshot(0.0)
	_report_bot("BOT_START seed=%d mode=%s view=%dx%d" % [seed_value, _launch["bot"], _bot_session.view.viewport_size.x, _bot_session.view.viewport_size.y])


func _process_fast_bot() -> void:
	if _bot_session == null:
		return
	# Yield regularly so close requests and engine errors cannot leave a busy loop.
	var deadline_usec: int = Time.get_ticks_usec() + 16_000
	for _step_index: int in 256:
		if not _bot_session.result.is_empty():
			_finish_bot_session()
			return
		_bot_session.advance()
		combat_simulation.take_events()
		if _bot_errors != null and _bot_errors.count() > 0:
			_bot_session.fail("engine_or_script_error")
			_finish_bot_session()
			return
		if run_state.combat_tick >= _bot_next_report_tick:
			_report_bot("BOT_PROGRESS seed=%d game_seconds=%.1f hp=%.1f level=%d" % [run_state.run_seed, run_state.elapsed_seconds(), run_state.current_hp, run_state.level])
			_bot_next_report_tick += 18000
		if Time.get_ticks_usec() >= deadline_usec:
			return


func _process_watched_bot() -> void:
	if _bot_session == null or _manual_paused:
		return
	if not _bot_session.result.is_empty():
		_finish_bot_session()
		return
	for _step_index: int in int(_launch["bot_speed"]):
		var phase_before: GameTypes.RunPhase = run_state.phase
		_bot_session.advance()
		_render_dirty = true
		_consume_snapshot_events(combat_simulation.take_events())
		if _bot_errors != null and _bot_errors.count() > 0:
			_bot_session.fail("engine_or_script_error")
			_finish_bot_session()
			return
		if run_state.phase != GameTypes.RunPhase.COMBAT or phase_before != GameTypes.RunPhase.COMBAT or not _bot_session.result.is_empty():
			break
	_sync_run_phase()
	if not _bot_session.result.is_empty():
		_finish_bot_session()


func _finish_bot_session() -> void:
	if _bot_summary_printed:
		return
	if _bot_errors != null and _bot_errors.count() > 0 and _bot_session.result != &"error":
		_bot_session.fail("engine_or_script_error")
	_bot_summary_printed = true
	_report_bot("BOT_RUN " + JSON.stringify(_bot_session.summary()))
	if _bot_session.profile != null:
		_bot_session.profile.report()
	_bot_completed_runs += 1
	if _bot_session.result == &"won":
		_bot_wins += 1
	if _bot_session.result == &"error":
		_quit_deferred(2)
		return
	if _launch["bot"] == "watch":
		if _bot_session.result == &"timeout":
			get_window().title = "Project JARJAR — BOT TIMEOUT (30:00)"
			run_state.phase = GameTypes.RunPhase.FAILED
			if not _show_failed():
				_quit_deferred(2)
		return
	if _bot_completed_runs < int(_launch["runs"]):
		_start_bot_session()
		return
	_report_bot("BOT_SUMMARY runs=%d won=%d failed=%d" % [_bot_completed_runs, _bot_wins, _bot_completed_runs - _bot_wins])
	set_process(false)
	_quit_deferred(0 if _bot_wins == _bot_completed_runs else 1)


func _report_bot(message: String) -> void:
	print(message)


func _exit_tree() -> void:
	if _bot_errors != null:
		OS.remove_logger(_bot_errors)
		_bot_errors = null
