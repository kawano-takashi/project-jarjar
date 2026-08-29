class_name PerformanceRunner
extends Node


signal completed(exit_code: int, summary: Dictionary)


const MetricsScript = preload("res://src/debug/performance_metrics.gd")

const PROFILE_NAME: String = "full_hd_500_2000"
const RUN_SEED: int = 5_002_000
const TARGET_WINDOW_SIZE: Vector2i = Vector2i(1920, 1080)
const TARGET_ENEMY_COUNT: int = 500
const TARGET_PROJECTILE_COUNT: int = 1_200
const TARGET_VFX_COUNT: int = 800
const WARMUP_USEC: int = 30_000_000
const RUN_DURATION_USEC: int = 120_000_000
const EARLY_MEMORY_FIRST_SECOND: int = 30
const EARLY_MEMORY_LAST_SECOND: int = 59
const LATE_MEMORY_FIRST_SECOND: int = 90
const LATE_MEMORY_LAST_SECOND: int = 119
const CSV_FILENAME: String = "performance.csv"
const SUMMARY_FILENAME: String = "performance-summary.txt"
const CSV_HEADER: String = (
	"frame_index,elapsed_usec,frame_time_usec,active_enemy,active_projectile,"
	+ "active_vfx,projectile_pool_used,vfx_pool_used,static_memory_bytes"
)

var exit_code: int = -1
var last_error_message: String = ""

var _initialized: bool = false
var _start_scheduled: bool = false
var _running: bool = false
var _baseline_captured: bool = false
var _simulation: CombatSimulation = null
var _output_directory: String = ""
var _csv_file: FileAccess = null
var _start_ticks_usec: int = 0
var _previous_frame_ticks_usec: int = 0
var _frame_index: int = 0
var _next_early_memory_second: int = EARLY_MEMORY_FIRST_SECOND
var _next_late_memory_second: int = LATE_MEMORY_FIRST_SECOND
var _csv_frame_times_usec := PackedInt64Array()
var _csv_static_memory_bytes := PackedInt64Array()
var _csv_count_overrides: Dictionary = {}
var _measurement_frame_times_usec := PackedInt64Array()
var _early_memory_samples := PackedInt64Array()
var _late_memory_samples := PackedInt64Array()
var _failure_reasons := PackedStringArray()
var _host_info: Dictionary = {}
var _count_violation_frames: int = 0
var _static_memory_invalid_frames: int = 0
var _pool_overflow_violation_frames: int = 0
var _effect_chain_overflow_violation_frames: int = 0
var _orphan_node_violation_frames: int = 0
var _maximum_orphan_node_count: int = 0
var _first_count_violation: String = ""


func initialize(simulation: CombatSimulation, output_directory: String) -> Error:
	if _initialized:
		return ERR_ALREADY_IN_USE
	if not _simulation_is_usable(simulation):
		last_error_message = "simulation_not_initialized"
		return ERR_INVALID_PARAMETER

	var normalized_output := output_directory.replace("\\", "/").simplify_path()
	if (
		normalized_output.is_empty()
		or not normalized_output.is_absolute_path()
		or not DirAccess.dir_exists_absolute(normalized_output)
	):
		last_error_message = "output_directory_invalid_or_missing"
		return ERR_INVALID_PARAMETER

	_simulation = simulation
	_output_directory = normalized_output.trim_suffix("/")
	if _simulation.state.run_seed != RUN_SEED:
		last_error_message = "performance_run_seed_not_%d" % RUN_SEED
		_simulation = null
		return ERR_INVALID_DATA
	if _simulation.state.phase != GameTypes.RunPhase.COMBAT:
		last_error_message = "performance_requires_combat_phase"
		_simulation = null
		return ERR_INVALID_DATA
	var fixture_result := _prepare_or_validate_full_load()
	if not bool(fixture_result.get("valid", false)):
		last_error_message = str(fixture_result.get("reason", "full_load_fixture_failed"))
		return ERR_INVALID_DATA

	_initialized = true
	if is_node_ready():
		_schedule_start()
	return OK


func _ready() -> void:
	if _initialized:
		_schedule_start()


func debug_state() -> Dictionary:
	return {
		"initialized": _initialized,
		"running": _running,
		"baseline_captured": _baseline_captured,
		"frame_index": _frame_index,
		"csv_buffer_count": _csv_frame_times_usec.size(),
		"measurement_sample_count": _measurement_frame_times_usec.size(),
		"early_memory_sample_count": _early_memory_samples.size(),
		"late_memory_sample_count": _late_memory_samples.size(),
		"exit_code": exit_code,
		"last_error_message": last_error_message,
	}


func _schedule_start() -> void:
	if _start_scheduled or _running or exit_code >= 0:
		return
	_start_scheduled = true
	_start_capture.call_deferred()


func _start_capture() -> void:
	_start_scheduled = false
	if not _initialized or _running or exit_code >= 0:
		return

	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(TARGET_WINDOW_SIZE)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	var csv_path := _output_directory.path_join(CSV_FILENAME)
	_csv_file = FileAccess.open(csv_path, FileAccess.WRITE)
	if _csv_file == null:
		last_error_message = "performance_csv_open_failed_%d" % FileAccess.get_open_error()
		_finish_without_capture()
		return
	_csv_file.store_string(CSV_HEADER + "\n")
	if _csv_file.get_error() != OK:
		last_error_message = "performance_csv_header_write_failed"
		_csv_file.close()
		_csv_file = null
		_finish_without_capture()
		return
	_running = true
	RenderingServer.frame_post_draw.connect(_on_frame_post_draw)


func _on_frame_post_draw() -> void:
	if not _running:
		return
	var now_usec := Time.get_ticks_usec()
	if not _baseline_captured:
		_baseline_captured = true
		_start_ticks_usec = now_usec
		_previous_frame_ticks_usec = now_usec
		_host_info = _capture_host_info()
		for reason: String in _environment_failures(_host_info):
			_append_failure_once(reason)
		_validate_runtime_state()
		if not _failure_reasons.is_empty():
			_finish_capture()
		return

	var elapsed_usec := now_usec - _start_ticks_usec
	var frame_time_usec := now_usec - _previous_frame_ticks_usec
	_previous_frame_ticks_usec = now_usec
	var frame_values := _runtime_frame_values()
	_record_csv_frame(frame_time_usec, frame_values)
	_validate_frame_values(frame_values)
	_collect_memory_samples(elapsed_usec, int(frame_values["static_memory_bytes"]))
	if elapsed_usec > WARMUP_USEC and elapsed_usec <= RUN_DURATION_USEC:
		_measurement_frame_times_usec.append(frame_time_usec)
	_frame_index += 1

	if elapsed_usec > RUN_DURATION_USEC:
		_finish_capture()


func _finish_capture() -> void:
	if not _running:
		return
	_running = false
	if RenderingServer.frame_post_draw.is_connected(_on_frame_post_draw):
		RenderingServer.frame_post_draw.disconnect(_on_frame_post_draw)
	if _csv_file != null:
		if not _write_buffered_csv_rows():
			_append_failure_once("performance_csv_buffer_or_write_failed")
		_csv_file.flush()
		if _csv_file.get_error() != OK:
			_append_failure_once("performance_csv_write_failed")
		_csv_file.close()
		_csv_file = null

	var metrics: Dictionary = MetricsScript.summarize(
		_measurement_frame_times_usec,
		_early_memory_samples,
		_late_memory_samples,
	)
	for reason: String in MetricsScript.threshold_failures(metrics):
		_append_failure_once(reason)
	_append_runtime_counter_failures()
	var summary := _build_summary(metrics)
	exit_code = 0 if _failure_reasons.is_empty() else 1
	summary["passed"] = exit_code == 0
	summary["exit_code"] = exit_code
	if not _write_summary(summary):
		exit_code = 1
		summary["passed"] = false
		summary["exit_code"] = exit_code
		_append_failure_once("performance_summary_write_failed")
		summary["failure_reasons"] = ";".join(_failure_reasons)
	last_error_message = "" if exit_code == 0 else ";".join(_failure_reasons)
	if exit_code == 0:
		print(
			"PERFORMANCE_OK average_fps=%.6f p95_usec=%d one_percent_low_fps=%.6f worst_usec=%d"
			% [
				float(metrics["average_fps"]),
				int(metrics["p95_frame_time_usec"]),
				float(metrics["one_percent_low_fps"]),
				int(metrics["worst_frame_time_usec"]),
			]
		)
	else:
		print("PERFORMANCE_FAILED reasons=%s" % last_error_message)
	completed.emit(exit_code, summary)


func _finish_without_capture() -> void:
	exit_code = 1
	_append_failure_once(last_error_message)
	var metrics: Dictionary = MetricsScript.summarize(
		PackedInt64Array(),
		PackedInt64Array(),
		PackedInt64Array(),
	)
	var summary := _build_summary(metrics)
	summary["passed"] = false
	summary["exit_code"] = exit_code
	if not _write_summary(summary):
		_append_failure_once("performance_summary_write_failed")
		summary["failure_reasons"] = ";".join(_failure_reasons)
	last_error_message = ";".join(_failure_reasons)
	print("PERFORMANCE_FAILED reasons=%s" % ";".join(_failure_reasons))
	completed.emit(exit_code, summary)


func _prepare_or_validate_full_load() -> Dictionary:
	var initial_counts := _active_counts()
	if (
		int(initial_counts["active_enemy"]) == TARGET_ENEMY_COUNT
		and int(initial_counts["active_projectile"]) == TARGET_PROJECTILE_COUNT
		and int(initial_counts["active_vfx"]) == TARGET_VFX_COUNT
	):
		_configure_simulation_freeze()
		return {"valid": true, "reason": ""}
	if (
		int(initial_counts["active_enemy"]) != 0
		or int(initial_counts["active_projectile"]) != 0
		or int(initial_counts["active_vfx"]) != 0
	):
		return {"valid": false, "reason": "full_load_fixture_requires_empty_or_exact_simulation"}

	if not _simulation.has_method(&"prepare_performance_fixture"):
		return {"valid": false, "reason": "performance_fixture_helper_missing"}
	if not bool(
		_simulation.call(
			&"prepare_performance_fixture",
			TARGET_ENEMY_COUNT,
			TARGET_PROJECTILE_COUNT,
			TARGET_VFX_COUNT,
		)
	):
		return {"valid": false, "reason": "performance_fixture_prepare_failed"}
	_configure_simulation_freeze()

	var final_counts := _active_counts()
	if (
		int(final_counts["active_enemy"]) != TARGET_ENEMY_COUNT
		or int(final_counts["active_projectile"]) != TARGET_PROJECTILE_COUNT
		or int(final_counts["active_vfx"]) != TARGET_VFX_COUNT
	):
		return {"valid": false, "reason": "full_load_fixture_count_mismatch"}
	return {"valid": true, "reason": ""}


func _configure_simulation_freeze() -> void:
	_simulation.freeze_enemy_ai = true
	_simulation.freeze_enemy_timers = true
	_simulation.freeze_normal_spawn = true
	_simulation.freeze_countdown = true
	_simulation.freeze_all_updates = true
	_simulation.allow_contact_timers_only = false
	_simulation.main_weapon_damage_override = 0.0
	_simulation.state.current_hp = _simulation.state.max_hp


func _simulation_is_usable(simulation: CombatSimulation) -> bool:
	return (
		simulation != null
		and simulation.state != null
		and simulation.catalog != null
		and simulation.wave != null
		and simulation.enemy_system != null
		and simulation.enemy_system.enemy_store != null
		and simulation.projectile_pool != null
		and simulation.vfx_pool != null
		and simulation.chest_visual_pool != null
		and simulation.event_router != null
	)


func _active_counts() -> Dictionary:
	return {
		"active_enemy": _simulation.enemy_system.enemy_store.active_count(),
		"active_projectile": _simulation.projectile_pool.active_count(),
		"active_vfx": _simulation.vfx_pool.active_count(),
	}


func _runtime_frame_values() -> Dictionary:
	var counts := _active_counts()
	counts["projectile_pool_used"] = counts["active_projectile"]
	counts["vfx_pool_used"] = counts["active_vfx"]
	counts["static_memory_bytes"] = OS.get_static_memory_usage()
	counts["enemy_pool_overflow"] = _simulation.enemy_system.enemy_store.overflow_count
	counts["projectile_pool_overflow"] = _simulation.projectile_pool.overflow_count
	counts["vfx_pool_overflow"] = _simulation.vfx_pool.overflow_count
	counts["chest_pool_forced_absorb"] = _simulation.chest_visual_pool.forced_absorb_count
	counts["effect_chain_depth_overflow"] = _simulation.event_router.chain_depth_overflow_count
	counts["orphan_node_count"] = int(
		Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	)
	return counts


func _record_csv_frame(frame_time_usec: int, values: Dictionary) -> void:
	_csv_frame_times_usec.append(frame_time_usec)
	_csv_static_memory_bytes.append(int(values["static_memory_bytes"]))
	var active_enemy: int = int(values["active_enemy"])
	var active_projectile: int = int(values["active_projectile"])
	var active_vfx: int = int(values["active_vfx"])
	if (
		active_enemy != TARGET_ENEMY_COUNT
		or active_projectile != TARGET_PROJECTILE_COUNT
		or active_vfx != TARGET_VFX_COUNT
	):
		_csv_count_overrides[_frame_index] = PackedInt64Array([
			active_enemy,
			active_projectile,
			active_vfx,
		])


func _write_buffered_csv_rows() -> bool:
	if (
		_csv_file == null
		or _csv_frame_times_usec.size() != _frame_index
		or _csv_static_memory_bytes.size() != _frame_index
	):
		return false
	var elapsed_usec: int = 0
	for index: int in range(_frame_index):
		var frame_time_usec: int = _csv_frame_times_usec[index]
		elapsed_usec += frame_time_usec
		var active_enemy: int = TARGET_ENEMY_COUNT
		var active_projectile: int = TARGET_PROJECTILE_COUNT
		var active_vfx: int = TARGET_VFX_COUNT
		if _csv_count_overrides.has(index):
			var counts: PackedInt64Array = _csv_count_overrides[index]
			if counts.size() != 3:
				return false
			active_enemy = counts[0]
			active_projectile = counts[1]
			active_vfx = counts[2]
		_csv_file.store_string(
			"%d,%d,%d,%d,%d,%d,%d,%d,%d\n"
			% [
				index,
				elapsed_usec,
				frame_time_usec,
				active_enemy,
				active_projectile,
				active_vfx,
				active_projectile,
				active_vfx,
				_csv_static_memory_bytes[index],
			]
		)
		if _csv_file.get_error() != OK:
			return false
	return true


func _validate_runtime_state() -> void:
	_validate_frame_values(_runtime_frame_values())


func _validate_frame_values(values: Dictionary) -> void:
	var active_enemy: int = int(values["active_enemy"])
	var active_projectile: int = int(values["active_projectile"])
	var active_vfx: int = int(values["active_vfx"])
	if (
		active_enemy != TARGET_ENEMY_COUNT
		or active_projectile != TARGET_PROJECTILE_COUNT
		or active_vfx != TARGET_VFX_COUNT
	):
		_count_violation_frames += 1
		if _first_count_violation.is_empty():
			_first_count_violation = "%d/%d/%d" % [
				active_enemy,
				active_projectile,
				active_vfx,
			]

	if int(values["static_memory_bytes"]) <= 0:
		_static_memory_invalid_frames += 1
	var pool_overflow_total := (
		int(values["enemy_pool_overflow"])
		+ int(values["projectile_pool_overflow"])
		+ int(values["vfx_pool_overflow"])
		+ int(values["chest_pool_forced_absorb"])
	)
	if pool_overflow_total != 0:
		_pool_overflow_violation_frames += 1
	if int(values["effect_chain_depth_overflow"]) != 0:
		_effect_chain_overflow_violation_frames += 1
	var orphan_node_count: int = int(values["orphan_node_count"])
	_maximum_orphan_node_count = maxi(_maximum_orphan_node_count, orphan_node_count)
	if orphan_node_count != 0:
		_orphan_node_violation_frames += 1


func _collect_memory_samples(elapsed_usec: int, static_memory_bytes: int) -> void:
	while (
		_next_early_memory_second <= EARLY_MEMORY_LAST_SECOND
		and elapsed_usec > _next_early_memory_second * 1_000_000
	):
		_early_memory_samples.append(static_memory_bytes)
		_next_early_memory_second += 1
	while (
		_next_late_memory_second <= LATE_MEMORY_LAST_SECOND
		and elapsed_usec > _next_late_memory_second * 1_000_000
	):
		_late_memory_samples.append(static_memory_bytes)
		_next_late_memory_second += 1


func _append_runtime_counter_failures() -> void:
	if _count_violation_frames != 0:
		_append_failure_once("active_count_mismatch")
	if _static_memory_invalid_frames != 0:
		_append_failure_once("static_memory_nonpositive")
	if _pool_overflow_violation_frames != 0:
		_append_failure_once("pool_overflow_nonzero")
	if _effect_chain_overflow_violation_frames != 0:
		_append_failure_once("effect_chain_depth_overflow_nonzero")
	if _orphan_node_violation_frames != 0:
		_append_failure_once("orphan_node_nonzero")


func _capture_host_info() -> Dictionary:
	var memory_info: Dictionary = OS.get_memory_info()
	var version_info: Dictionary = Engine.get_version_info()
	var version_string := str(version_info.get("string", ""))
	var version_hash := str(version_info.get("hash", ""))
	return {
		"windows_version": "%s %s" % [OS.get_name(), OS.get_version()],
		"windows_version_alias": OS.get_version_alias(),
		"cpu_name": OS.get_processor_name(),
		"logical_core_count": OS.get_processor_count(),
		"gpu_name": RenderingServer.get_video_adapter_name(),
		"ram_capacity_bytes": int(memory_info.get("physical", -1)),
		"godot_version": (
			version_string + (" " + version_hash if not version_hash.is_empty() else "")
		),
		"godot_version_hash": version_hash,
		"rendering_method": RenderingServer.get_current_rendering_method(),
		"rendering_driver": RenderingServer.get_current_rendering_driver_name(),
		"window_width": DisplayServer.window_get_size().x,
		"window_height": DisplayServer.window_get_size().y,
		"viewport_width": int(get_viewport().get_visible_rect().size.x),
		"viewport_height": int(get_viewport().get_visible_rect().size.y),
		"vsync_mode": int(DisplayServer.window_get_vsync_mode()),
	}


func _environment_failures(host_info: Dictionary) -> PackedStringArray:
	var failures := PackedStringArray()
	if not OS.is_debug_build():
		failures.append("performance_requires_debug_build")
	if OS.get_name() != "Windows":
		failures.append("performance_requires_windows")
	if str(host_info["rendering_method"]) != "gl_compatibility":
		failures.append("rendering_method_not_compatibility")
	if (
		int(host_info["window_width"]) != TARGET_WINDOW_SIZE.x
		or int(host_info["window_height"]) != TARGET_WINDOW_SIZE.y
	):
		failures.append("window_size_not_1920x1080")
	if (
		int(host_info["viewport_width"]) != TARGET_WINDOW_SIZE.x
		or int(host_info["viewport_height"]) != TARGET_WINDOW_SIZE.y
	):
		failures.append("viewport_size_not_1920x1080")
	if int(host_info["vsync_mode"]) != DisplayServer.VSYNC_DISABLED:
		failures.append("vsync_not_disabled")
	if str(host_info["windows_version"]).strip_edges().is_empty():
		failures.append("windows_version_missing")
	if str(host_info["cpu_name"]).strip_edges().is_empty():
		failures.append("cpu_name_missing")
	if int(host_info["logical_core_count"]) <= 0:
		failures.append("logical_core_count_nonpositive")
	if str(host_info["gpu_name"]).strip_edges().is_empty():
		failures.append("gpu_name_missing")
	if int(host_info["ram_capacity_bytes"]) <= 0:
		failures.append("ram_capacity_nonpositive")
	if str(host_info["godot_version"]).strip_edges().is_empty():
		failures.append("godot_version_missing")
	return failures


func _build_summary(metrics: Dictionary) -> Dictionary:
	var frame_values := _runtime_frame_values() if _simulation_is_usable(_simulation) else {}
	return {
		"profile": PROFILE_NAME,
		"run_seed": RUN_SEED,
		"warmup_usec": WARMUP_USEC,
		"run_duration_usec": RUN_DURATION_USEC,
		"csv_frame_count": _frame_index,
		"measurement_sample_count": int(metrics.get("sample_count", 0)),
		"total_frame_time_usec": int(metrics.get("total_frame_time_usec", 0)),
		"average_fps": float(metrics.get("average_fps", 0.0)),
		"p95_frame_time_usec": int(metrics.get("p95_frame_time_usec", 0)),
		"p99_frame_time_usec": int(metrics.get("p99_frame_time_usec", 0)),
		"one_percent_low_fps": float(metrics.get("one_percent_low_fps", 0.0)),
		"worst_frame_time_usec": int(metrics.get("worst_frame_time_usec", 0)),
		"early_memory_sample_count": int(metrics.get("early_memory_sample_count", 0)),
		"late_memory_sample_count": int(metrics.get("late_memory_sample_count", 0)),
		"early_memory_median_bytes": float(metrics.get("early_memory_median_bytes", 0.0)),
		"late_memory_median_bytes": float(metrics.get("late_memory_median_bytes", 0.0)),
		"memory_growth_ratio": float(metrics.get("memory_growth_ratio", INF)),
		"active_count_violation_frames": _count_violation_frames,
		"first_count_violation": _first_count_violation,
		"static_memory_invalid_frames": _static_memory_invalid_frames,
		"pool_overflow_violation_frames": _pool_overflow_violation_frames,
		"effect_chain_overflow_violation_frames": _effect_chain_overflow_violation_frames,
		"orphan_node_violation_frames": _orphan_node_violation_frames,
		"maximum_orphan_node_count": _maximum_orphan_node_count,
		"active_enemy_final": int(frame_values.get("active_enemy", -1)),
		"active_projectile_final": int(frame_values.get("active_projectile", -1)),
		"active_vfx_final": int(frame_values.get("active_vfx", -1)),
		"enemy_pool_overflow": int(frame_values.get("enemy_pool_overflow", -1)),
		"projectile_pool_overflow": int(frame_values.get("projectile_pool_overflow", -1)),
		"vfx_pool_overflow": int(frame_values.get("vfx_pool_overflow", -1)),
		"chest_pool_forced_absorb": int(frame_values.get("chest_pool_forced_absorb", -1)),
		"effect_chain_depth_overflow": int(frame_values.get("effect_chain_depth_overflow", -1)),
		"failure_reasons": ";".join(_failure_reasons),
		"host": _host_info.duplicate(true),
	}


func _write_summary(summary: Dictionary) -> bool:
	var summary_path := _output_directory.path_join(SUMMARY_FILENAME)
	var file := FileAccess.open(summary_path, FileAccess.WRITE)
	if file == null:
		return false
	var host: Dictionary = summary.get("host", {})
	var lines := PackedStringArray([
		"passed=%s" % str(bool(summary.get("passed", false))).to_lower(),
		"exit_code=%d" % int(summary.get("exit_code", 1)),
		"profile=%s" % str(summary["profile"]),
		"run_seed=%d" % int(summary["run_seed"]),
		"rendering_method=%s" % str(host.get("rendering_method", "")),
		"rendering_driver=%s" % str(host.get("rendering_driver", "")),
		"window_size=%dx%d" % [int(host.get("window_width", 0)), int(host.get("window_height", 0))],
		"viewport_size=%dx%d" % [int(host.get("viewport_width", 0)), int(host.get("viewport_height", 0))],
		"vsync_mode=%d" % int(host.get("vsync_mode", -1)),
		"warmup_usec=%d" % int(summary["warmup_usec"]),
		"run_duration_usec=%d" % int(summary["run_duration_usec"]),
		"csv_frame_count=%d" % int(summary["csv_frame_count"]),
		"measurement_sample_count=%d" % int(summary["measurement_sample_count"]),
		"total_frame_time_usec=%d" % int(summary["total_frame_time_usec"]),
		"average_fps=%.6f" % float(summary["average_fps"]),
		"p95_frame_time_usec=%d" % int(summary["p95_frame_time_usec"]),
		"p95_frame_time_ms=%.6f" % (float(summary["p95_frame_time_usec"]) / 1000.0),
		"p99_frame_time_usec=%d" % int(summary["p99_frame_time_usec"]),
		"p99_frame_time_ms=%.6f" % (float(summary["p99_frame_time_usec"]) / 1000.0),
		"one_percent_low_fps=%.6f" % float(summary["one_percent_low_fps"]),
		"worst_frame_time_usec=%d" % int(summary["worst_frame_time_usec"]),
		"worst_frame_time_ms=%.6f" % (float(summary["worst_frame_time_usec"]) / 1000.0),
		"early_memory_sample_count=%d" % int(summary["early_memory_sample_count"]),
		"late_memory_sample_count=%d" % int(summary["late_memory_sample_count"]),
		"early_memory_median_bytes=%.1f" % float(summary["early_memory_median_bytes"]),
		"late_memory_median_bytes=%.1f" % float(summary["late_memory_median_bytes"]),
		"memory_growth_ratio=%.9f" % float(summary["memory_growth_ratio"]),
		"active_enemy_final=%d" % int(summary["active_enemy_final"]),
		"active_projectile_final=%d" % int(summary["active_projectile_final"]),
		"active_vfx_final=%d" % int(summary["active_vfx_final"]),
		"active_count_violation_frames=%d" % int(summary["active_count_violation_frames"]),
		"first_count_violation=%s" % str(summary["first_count_violation"]),
		"enemy_pool_overflow=%d" % int(summary["enemy_pool_overflow"]),
		"projectile_pool_overflow=%d" % int(summary["projectile_pool_overflow"]),
		"vfx_pool_overflow=%d" % int(summary["vfx_pool_overflow"]),
		"chest_pool_forced_absorb=%d" % int(summary["chest_pool_forced_absorb"]),
		"pool_overflow_violation_frames=%d" % int(summary["pool_overflow_violation_frames"]),
		"effect_chain_depth_overflow=%d" % int(summary["effect_chain_depth_overflow"]),
		"effect_chain_overflow_violation_frames=%d" % int(summary["effect_chain_overflow_violation_frames"]),
		"maximum_orphan_node_count=%d" % int(summary["maximum_orphan_node_count"]),
		"orphan_node_violation_frames=%d" % int(summary["orphan_node_violation_frames"]),
		"static_memory_invalid_frames=%d" % int(summary["static_memory_invalid_frames"]),
		"windows_version=%s" % str(host.get("windows_version", "")),
		"windows_version_alias=%s" % str(host.get("windows_version_alias", "")),
		"cpu_name=%s" % str(host.get("cpu_name", "")),
		"logical_core_count=%d" % int(host.get("logical_core_count", 0)),
		"gpu_name=%s" % str(host.get("gpu_name", "")),
		"ram_capacity_bytes=%d" % int(host.get("ram_capacity_bytes", -1)),
		"godot_version=%s" % str(host.get("godot_version", "")),
		"godot_version_hash=%s" % str(host.get("godot_version_hash", "")),
		"failure_reasons=%s" % str(summary.get("failure_reasons", "")),
	])
	file.store_string("\n".join(lines) + "\n")
	file.flush()
	var write_succeeded := file.get_error() == OK
	file.close()
	return write_succeeded


func _append_failure_once(reason: String) -> void:
	if not reason.is_empty() and not _failure_reasons.has(reason):
		_failure_reasons.append(reason)
