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
const TARGET_XP_COUNT: int = 1_024
const TARGET_WEAPON_COUNT: int = 5
const WARMUP_USEC: int = 30_000_000
const RUN_DURATION_USEC: int = 120_000_000
const EARLY_MEMORY_FIRST_SECOND: int = 30
const EARLY_MEMORY_LAST_SECOND: int = 59
const LATE_MEMORY_FIRST_SECOND: int = 90
const LATE_MEMORY_LAST_SECOND: int = 119

var exit_code: int = -1
var last_error_message: String = ""

var _initialized: bool = false
var _start_scheduled: bool = false
var _running: bool = false
var _baseline_captured: bool = false
var _simulation: CombatSimulation = null
var _start_ticks_usec: int = 0
var _previous_frame_ticks_usec: int = 0
var _frame_index: int = 0
var _next_early_memory_second: int = EARLY_MEMORY_FIRST_SECOND
var _next_late_memory_second: int = LATE_MEMORY_FIRST_SECOND
var _measurement_frame_times_usec := PackedInt64Array()
var _early_memory_samples := PackedInt64Array()
var _late_memory_samples := PackedInt64Array()
var _failure_reasons := PackedStringArray()
var _host_info: Dictionary = {}
var _count_violation_frames: int = 0
var _static_memory_invalid_frames: int = 0
var _pool_overflow_violation_frames: int = 0
var _orphan_node_violation_frames: int = 0
var _maximum_orphan_node_count: int = 0
var _first_count_violation: String = ""
var _final_workload_metrics: Dictionary = {}


func initialize(simulation: CombatSimulation) -> Error:
	if _initialized:
		return ERR_ALREADY_IN_USE
	if not _simulation_is_usable(simulation):
		last_error_message = "simulation_not_initialized"
		return ERR_INVALID_PARAMETER

	_simulation = simulation
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

	_record_frame_sample(elapsed_usec, frame_time_usec, frame_values)

	if elapsed_usec > RUN_DURATION_USEC:
		_finish_capture()


func _finish_capture() -> void:
	if not _running:
		return
	_running = false
	if RenderingServer.frame_post_draw.is_connected(_on_frame_post_draw):
		RenderingServer.frame_post_draw.disconnect(_on_frame_post_draw)

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
	last_error_message = "" if exit_code == 0 else ";".join(_failure_reasons)
	print(
		"PERFORMANCE_METRICS average_fps=%.6f p95_usec=%d one_percent_low_fps=%.6f worst_usec=%d memory_growth_ratio=%.6f samples=%d"
		% [
			float(metrics["average_fps"]), int(metrics["p95_frame_time_usec"]),
			float(metrics["one_percent_low_fps"]), int(metrics["worst_frame_time_usec"]),
			float(metrics["memory_growth_ratio"]), int(metrics["sample_count"]),
		]
	)
	if OS.is_stdout_verbose():
		print("PERFORMANCE_DETAILS %s" % JSON.stringify(summary))
	print("PERFORMANCE_OK" if exit_code == 0 else "PERFORMANCE_FAILED reasons=%s" % last_error_message)
	completed.emit(exit_code, summary)


func _prepare_or_validate_full_load() -> Dictionary:
	var initial_counts := _active_counts()
	if (
		int(initial_counts["active_enemy"]) == TARGET_ENEMY_COUNT
		and int(initial_counts["active_projectile"]) == TARGET_PROJECTILE_COUNT
		and int(initial_counts["active_vfx"]) == TARGET_VFX_COUNT
		and int(initial_counts["active_xp"]) == TARGET_XP_COUNT
		and int(initial_counts["active_weapon"]) == TARGET_WEAPON_COUNT
	):
		_configure_simulation_freeze()
		return {"valid": true, "reason": ""}
	if (
		int(initial_counts["active_enemy"]) != 0
		or int(initial_counts["active_projectile"]) != 0
		or int(initial_counts["active_vfx"]) != 0
		or int(initial_counts["active_xp"]) != 0
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
			TARGET_XP_COUNT,
		)
	):
		return {"valid": false, "reason": "performance_fixture_prepare_failed"}
	_configure_simulation_freeze()

	var final_counts := _active_counts()
	if (
		int(final_counts["active_enemy"]) != TARGET_ENEMY_COUNT
		or int(final_counts["active_projectile"]) != TARGET_PROJECTILE_COUNT
		or int(final_counts["active_vfx"]) != TARGET_VFX_COUNT
		or int(final_counts["active_xp"]) != TARGET_XP_COUNT
		or int(final_counts["active_weapon"]) != TARGET_WEAPON_COUNT
	):
		return {"valid": false, "reason": "full_load_fixture_count_mismatch"}
	return {"valid": true, "reason": ""}


func _configure_simulation_freeze() -> void:
	_simulation.freeze_all_updates = true
	_simulation.state.current_hp = _simulation.state.max_hp


func _simulation_is_usable(simulation: CombatSimulation) -> bool:
	return (
		simulation != null
		and simulation.state != null
		and simulation.catalog != null
		and simulation.enemy_system != null
		and simulation.enemy_system.enemy_store != null
		and simulation.projectile_pool != null
		and simulation.vfx_pool != null
		and simulation.xp_pickup_pool != null
		and simulation.arena_object_system != null
		and simulation.weapon_system != null
		and simulation.event_router != null
	)


func _active_counts() -> Dictionary:
	return {
		"active_enemy": _simulation.enemy_system.enemy_store.active_count(),
		"active_projectile": _simulation.projectile_pool.active_count(),
		"active_vfx": _simulation.vfx_pool.active_count(),
		"active_xp": _simulation.xp_pickup_pool.active_count(),
		"active_weapon": _simulation.state.weapons.size(),
	}


func _runtime_frame_values() -> Dictionary:
	var counts := _active_counts()
	counts["projectile_pool_used"] = counts["active_projectile"]
	counts["vfx_pool_used"] = counts["active_vfx"]
	counts["xp_pool_used"] = counts["active_xp"]
	counts["static_memory_bytes"] = OS.get_static_memory_usage()
	counts["enemy_pool_overflow"] = _simulation.enemy_system.enemy_store.overflow_count
	counts["projectile_pool_overflow"] = _simulation.projectile_pool.overflow_count
	counts["vfx_pool_overflow"] = _simulation.vfx_pool.overflow_count
	counts["xp_pool_overflow_merges"] = _simulation.xp_pickup_pool.overflow_merge_count
	counts["orphan_node_count"] = int(
		Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	)
	return counts


func _record_frame_sample(elapsed_usec: int, frame_time_usec: int, values: Dictionary) -> void:
	_validate_frame_values(values)
	_collect_memory_samples(elapsed_usec, int(values["static_memory_bytes"]))
	if elapsed_usec > WARMUP_USEC and elapsed_usec <= RUN_DURATION_USEC:
		_measurement_frame_times_usec.append(frame_time_usec)
	_frame_index += 1


func _validate_runtime_state() -> void:
	_validate_frame_values(_runtime_frame_values())


func _validate_frame_values(values: Dictionary) -> void:
	var active_enemy: int = int(values["active_enemy"])
	var active_projectile: int = int(values["active_projectile"])
	var active_vfx: int = int(values["active_vfx"])
	var active_xp: int = int(values["active_xp"])
	var active_weapon: int = int(values["active_weapon"])
	if (
		active_enemy != TARGET_ENEMY_COUNT
		or active_projectile != TARGET_PROJECTILE_COUNT
		or active_vfx != TARGET_VFX_COUNT
		or active_xp != TARGET_XP_COUNT
		or active_weapon != TARGET_WEAPON_COUNT
	):
		_count_violation_frames += 1
		if _first_count_violation.is_empty():
			_first_count_violation = "%d/%d/%d/%d/%d" % [
				active_enemy,
				active_projectile,
				active_vfx,
				active_xp,
				active_weapon,
			]

	if int(values["static_memory_bytes"]) <= 0:
		_static_memory_invalid_frames += 1
	var pool_overflow_total := (
		int(values["enemy_pool_overflow"])
		+ int(values["projectile_pool_overflow"])
		+ int(values["vfx_pool_overflow"])
		+ int(values["xp_pool_overflow_merges"])
	)
	if pool_overflow_total != 0:
		_pool_overflow_violation_frames += 1
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
	if _orphan_node_violation_frames != 0:
		_append_failure_once("orphan_node_nonzero")
	_capture_and_validate_workload_metrics()


func _capture_and_validate_workload_metrics() -> void:
	_final_workload_metrics.clear()
	if (
		not _simulation_is_usable(_simulation)
		or not _simulation.has_method(&"performance_fixture_metrics")
	):
		_append_failure_once("performance_workload_metrics_missing")
		return
	_final_workload_metrics = _simulation.performance_fixture_metrics()
	if str(_final_workload_metrics.get("profile_name", "")) != PROFILE_NAME:
		_append_failure_once("performance_profile_contract_mismatch")
	if not bool(_final_workload_metrics.get("active_workload", false)):
		_append_failure_once("performance_workload_inactive")
	if not bool(_final_workload_metrics.get("exact_counts", false)):
		_append_failure_once("performance_fixture_count_lock_failed")
	var workload_ticks: int = int(_final_workload_metrics.get("workload_ticks", 0))
	if workload_ticks <= 0:
		_append_failure_once("performance_workload_ticks_zero")
	if int(_final_workload_metrics.get("grid_updates", 0)) < workload_ticks:
		_append_failure_once("performance_grid_updates_missing")
	if int(_final_workload_metrics.get("projectile_collision_resolutions", 0)) <= 0:
		_append_failure_once("performance_projectile_collision_workload_missing")
	if int(_final_workload_metrics.get("weapon_attacks", 0)) <= 0:
		_append_failure_once("performance_weapon_attack_workload_missing")
	if int(_final_workload_metrics.get("enemy_pool_reuse", 0)) <= 0:
		_append_failure_once("performance_enemy_pool_reuse_zero")
	if int(_final_workload_metrics.get("projectile_pool_reuse", 0)) <= 0:
		_append_failure_once("performance_projectile_pool_reuse_zero")
	if int(_final_workload_metrics.get("vfx_pool_reuse", 0)) <= 0:
		_append_failure_once("performance_vfx_pool_reuse_zero")
	if int(_final_workload_metrics.get("xp_pool_reuse", 0)) <= 0:
		_append_failure_once("performance_xp_pool_reuse_zero")
	if int(_final_workload_metrics.get("pool_orphan_count", -1)) != 0:
		_append_failure_once("performance_pool_orphan_nonzero")
	var final_overflow_total: int = (
		int(_final_workload_metrics.get("enemy_pool_overflow", -1))
		+ int(_final_workload_metrics.get("projectile_pool_overflow", -1))
		+ int(_final_workload_metrics.get("vfx_pool_overflow", -1))
		+ int(_final_workload_metrics.get("xp_pool_overflow_merges", -1))
	)
	if final_overflow_total != 0:
		_append_failure_once("performance_final_pool_overflow_nonzero")


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
		"frame_count": _frame_index,
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
		"orphan_node_violation_frames": _orphan_node_violation_frames,
		"maximum_orphan_node_count": _maximum_orphan_node_count,
		"active_enemy_final": int(frame_values.get("active_enemy", -1)),
		"active_projectile_final": int(frame_values.get("active_projectile", -1)),
		"active_vfx_final": int(frame_values.get("active_vfx", -1)),
		"active_xp_final": int(frame_values.get("active_xp", -1)),
		"active_weapon_final": int(frame_values.get("active_weapon", -1)),
		"enemy_pool_overflow": int(frame_values.get("enemy_pool_overflow", -1)),
		"projectile_pool_overflow": int(frame_values.get("projectile_pool_overflow", -1)),
		"vfx_pool_overflow": int(frame_values.get("vfx_pool_overflow", -1)),
		"xp_pool_overflow_merges": int(frame_values.get("xp_pool_overflow_merges", -1)),
		"active_workload": bool(_final_workload_metrics.get("active_workload", false)),
		"exact_counts": bool(_final_workload_metrics.get("exact_counts", false)),
		"workload_ticks": int(_final_workload_metrics.get("workload_ticks", 0)),
		"grid_updates": int(_final_workload_metrics.get("grid_updates", 0)),
		"projectile_collision_resolutions": int(_final_workload_metrics.get("projectile_collision_resolutions", 0)),
		"weapon_attacks": int(_final_workload_metrics.get("weapon_attacks", 0)),
		"enemy_pool_reuse": int(_final_workload_metrics.get("enemy_pool_reuse", 0)),
		"projectile_pool_reuse": int(_final_workload_metrics.get("projectile_pool_reuse", 0)),
		"vfx_pool_reuse": int(_final_workload_metrics.get("vfx_pool_reuse", 0)),
		"xp_pool_reuse": int(_final_workload_metrics.get("xp_pool_reuse", 0)),
		"pool_orphan_count": int(_final_workload_metrics.get("pool_orphan_count", -1)),
		"failure_reasons": ";".join(_failure_reasons),
		"host": _host_info.duplicate(true),
	}


func _append_failure_once(reason: String) -> void:
	if not reason.is_empty() and not _failure_reasons.has(reason):
		_failure_reasons.append(reason)
