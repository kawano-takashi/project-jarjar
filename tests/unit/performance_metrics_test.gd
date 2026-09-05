extends RefCounted


const MetricsScript = preload("res://src/debug/performance_metrics.gd")
const RunnerScript = preload("res://src/debug/performance_runner.gd")


func test_names() -> PackedStringArray:
	return PackedStringArray([
		"performance_nearest_rank_and_memory_median",
		"performance_summary_thresholds",
		"performance_csv_buffer_contract",
		"performance_fixture_contract",
	])


func run_test(test_name: String, assertions: Variant, context: Dictionary) -> void:
	match test_name:
		"performance_nearest_rank_and_memory_median":
			_test_nearest_rank_and_memory_median(assertions)
		"performance_summary_thresholds":
			_test_summary_thresholds(assertions)
		"performance_csv_buffer_contract":
			_test_csv_buffer_contract(assertions)
		"performance_fixture_contract":
			_test_fixture_contract(assertions, context)
		_:
			assertions.expect_true(false, "registered test name")


func _test_nearest_rank_and_memory_median(assertions: Variant) -> void:
	var samples := PackedInt64Array()
	for value: int in range(100, 0, -1):
		samples.append(value)
	assertions.expect_equal(95, MetricsScript.nearest_rank_usec(samples, 0.95), "p95 nearest-rank uses zero-based index ceil(p*N)-1")
	assertions.expect_equal(99, MetricsScript.nearest_rank_usec(samples, 0.99), "p99 nearest-rank uses zero-based index ceil(p*N)-1")
	assertions.expect_equal(0, MetricsScript.nearest_rank_usec(PackedInt64Array(), 0.95), "empty percentile returns zero")

	var even_memory := PackedInt64Array()
	for value: int in range(1, 31):
		even_memory.append(value)
	assertions.expect_float(15.5, MetricsScript.median_bytes(even_memory), "30-sample median averages middle two values")
	assertions.expect_float(2.0, MetricsScript.median_bytes(PackedInt64Array([3, 1, 2])), "odd median selects sorted middle value")


func _test_summary_thresholds(assertions: Variant) -> void:
	var frame_times := PackedInt64Array()
	for _index: int in range(100):
		frame_times.append(16_000)
	var early_memory := PackedInt64Array()
	var late_memory := PackedInt64Array()
	for index: int in range(30):
		early_memory.append(100_000_000 + index)
		late_memory.append(104_000_000 + index)

	var passing: Dictionary = MetricsScript.summarize(
		frame_times,
		early_memory,
		late_memory,
	)
	assertions.expect_equal(100, passing["sample_count"], "summary retains measurement sample count")
	assertions.expect_float(62.5, passing["average_fps"], "average FPS uses one million times N over sum")
	assertions.expect_equal(16_000, passing["p95_frame_time_usec"], "summary p95")
	assertions.expect_equal(16_000, passing["p99_frame_time_usec"], "summary p99")
	assertions.expect_float(62.5, passing["one_percent_low_fps"], "one percent low derives from p99")
	assertions.expect_equal(16_000, passing["worst_frame_time_usec"], "summary worst frame")
	assertions.expect_equal(PackedStringArray(), MetricsScript.threshold_failures(passing), "passing metrics have no threshold failures")

	var memory_boundary: Dictionary = passing.duplicate()
	memory_boundary["early_memory_median_bytes"] = 100.0
	memory_boundary["late_memory_median_bytes"] = 105.0
	assertions.expect_false(
		MetricsScript.threshold_failures(memory_boundary).has(
			"static_memory_growth_above_105_percent"
		),
		"memory growth exactly 105 percent passes",
	)
	var failing: Dictionary = passing.duplicate()
	failing["average_fps"] = 59.999
	failing["p95_frame_time_usec"] = 16_671
	failing["one_percent_low_fps"] = 49.999
	failing["worst_frame_time_usec"] = 33_331
	failing["early_memory_median_bytes"] = 100.0
	failing["late_memory_median_bytes"] = 105.001
	var metric_failures: PackedStringArray = MetricsScript.threshold_failures(failing)
	assertions.expect_true(metric_failures.has("average_fps_below_60"), "average FPS below threshold fails")
	assertions.expect_true(metric_failures.has("p95_frame_time_above_16_67ms"), "p95 above threshold fails")
	assertions.expect_true(metric_failures.has("one_percent_low_fps_below_50"), "one percent low below threshold fails")
	assertions.expect_true(metric_failures.has("worst_frame_time_above_33_33ms"), "worst frame above threshold fails")
	assertions.expect_true(metric_failures.has("static_memory_growth_above_105_percent"), "memory growth above threshold fails")

	var empty_summary: Dictionary = MetricsScript.summarize(
		PackedInt64Array(),
		PackedInt64Array(),
		PackedInt64Array(),
	)
	var empty_failures: PackedStringArray = MetricsScript.threshold_failures(empty_summary)
	assertions.expect_true(empty_failures.has("measurement_sample_count_zero"), "N zero is rejected")
	assertions.expect_true(empty_failures.has("early_memory_sample_count_not_30"), "early memory requires 30 samples")
	assertions.expect_true(empty_failures.has("late_memory_sample_count_not_30"), "late memory requires 30 samples")


func _test_csv_buffer_contract(assertions: Variant) -> void:
	var runner: Variant = RunnerScript.new()
	var values := {
		"active_enemy": 500,
		"active_projectile": 1_200,
		"active_vfx": 800,
		"active_xp": 1_024,
		"active_weapon": 5,
		"projectile_pool_used": 1_200,
		"vfx_pool_used": 800,
		"xp_pool_used": 1_024,
		"static_memory_bytes": 80_000_000,
	}
	runner.call("_record_csv_frame", 1_234, values)
	assertions.expect_equal(
		1,
		int(runner.debug_state()["csv_buffer_count"]),
		"performance CSV frame is buffered without disk I/O",
	)
	assertions.expect_equal(
		PackedInt64Array([1_234]),
		runner.get("_csv_frame_times_usec"),
		"performance CSV buffer preserves frame time",
	)
	assertions.expect_equal(
		PackedInt64Array([80_000_000]),
		runner.get("_csv_static_memory_bytes"),
		"performance CSV buffer preserves raw static memory",
	)
	assertions.expect_equal(
		{},
		runner.get("_csv_count_overrides"),
		"exact fixture counts require no sparse override",
	)
	runner.set("_frame_index", 1)
	values["active_enemy"] = 499
	values["active_projectile"] = 1_199
	values["active_vfx"] = 799
	values["active_xp"] = 1_023
	values["active_weapon"] = 4
	runner.call("_record_csv_frame", 2_345, values)
	var overrides: Dictionary = runner.get("_csv_count_overrides")
	assertions.expect_equal(
		PackedInt64Array([499, 1_199, 799, 1_023, 4]),
		overrides.get(1, PackedInt64Array()),
		"count deviations are retained for exact CSV reconstruction",
	)
	runner.free()


func _test_fixture_contract(assertions: Variant, context: Dictionary) -> void:
	var output_directory := str(context.get("test_user_root", ""))
	assertions.expect_true(
		output_directory.is_absolute_path()
		and DirAccess.dir_exists_absolute(output_directory),
		"performance test output directory exists",
	)
	var catalog := DefinitionCatalog.new()
	assertions.expect_true(catalog.validate_manifest(BalanceTestFixtures.manifest()), "performance fixture catalog valid")
	if not catalog.is_valid:
		return

	var simulation := _new_simulation(RunnerScript.RUN_SEED, catalog)
	var runner: Variant = RunnerScript.new()
	var initialize_error: Error = runner.initialize(simulation, output_directory)
	assertions.expect_equal(OK, initialize_error, "performance runner accepts initialized seed 5002000 simulation")
	assertions.expect_equal(500, simulation.enemy_system.enemy_store.active_count(), "performance fixture enemy count")
	assertions.expect_equal(1_200, simulation.projectile_pool.active_count(), "performance fixture projectile count")
	assertions.expect_equal(800, simulation.vfx_pool.active_count(), "performance fixture VFX count")
	assertions.expect_equal(1_024, simulation.xp_pickup_pool.active_count(), "performance fixture XP count")
	assertions.expect_equal(5, simulation.state.weapons.size(), "performance fixture weapon count")
	assertions.expect_true(simulation.freeze_all_updates, "performance fixture keeps the runner compatibility flag")
	var contract: Dictionary = simulation.performance_profile_contract()
	assertions.expect_equal(&"full_hd_500_2000", contract["profile_name"], "existing performance profile name is unchanged")
	assertions.expect_equal(500, contract["enemy_count"], "profile contract fixes 500 enemies")
	assertions.expect_equal(1_200, contract["projectile_count"], "profile contract fixes 1200 projectiles")
	assertions.expect_equal(800, contract["vfx_count"], "profile contract fixes 800 VFX")
	assertions.expect_equal(1_024, contract["xp_count"], "profile contract includes the XP stress load")
	assertions.expect_equal(5, contract["weapon_count"], "profile contract fixes five weapons")
	assertions.expect_true(bool(contract["active_updates"]), "profile contract requires active simulation updates")
	assertions.expect_true(bool(contract["exact_count_lock"]), "profile contract keeps exact render counts")
	var initial_tick: int = simulation.state.combat_tick
	var movement_cycle: Array[Vector2] = [
		Vector2.RIGHT,
		Vector2.DOWN,
		Vector2.LEFT,
		Vector2.UP,
	]
	for tick_index: int in range(600):
		simulation.advance_tick(movement_cycle[tick_index % movement_cycle.size()])
	assertions.expect_equal(initial_tick + 600, simulation.state.combat_tick, "performance fixture advances active combat ticks")
	assertions.expect_equal(500, simulation.enemy_system.enemy_store.active_count(), "performance enemies remain exact across 600 steps")
	assertions.expect_equal(1_200, simulation.projectile_pool.active_count(), "performance projectiles remain exact across 600 steps")
	assertions.expect_equal(800, simulation.vfx_pool.active_count(), "performance VFX remain exact across 600 steps")
	assertions.expect_equal(1_024, simulation.xp_pickup_pool.active_count(), "performance XP remains exact across 600 steps")
	assertions.expect_equal(5, simulation.state.weapons.size(), "performance weapons remain exact across 600 steps")
	assertions.expect_equal(0, simulation.enemy_system.enemy_store.overflow_count, "performance enemy overflow remains zero")
	assertions.expect_equal(0, simulation.projectile_pool.overflow_count, "performance projectile overflow remains zero")
	assertions.expect_equal(0, simulation.vfx_pool.overflow_count, "performance VFX overflow remains zero")
	assertions.expect_equal(0, simulation.xp_pickup_pool.overflow_merge_count, "performance XP overflow remains zero")
	var workload_metrics: Dictionary = simulation.performance_fixture_metrics()
	assertions.expect_true(bool(workload_metrics["active_workload"]), "performance fixture executes active workload")
	assertions.expect_true(bool(workload_metrics["exact_counts"]), "performance fixture maintains exact active counts")
	assertions.expect_equal(600, workload_metrics["workload_ticks"], "performance workload covers every requested step")
	assertions.expect_equal(600, workload_metrics["grid_updates"], "performance workload updates the grid every step")
	assertions.expect_true(float(workload_metrics["enemy_motion_distance"]) > 0.0, "fixture enemies really move")
	assertions.expect_true(float(workload_metrics["projectile_motion_distance"]) > 0.0, "fixture projectiles really move")
	assertions.expect_true(int(workload_metrics["projectile_collision_resolutions"]) >= 1_200 * 600, "fixture resolves the full projectile collision workload")
	assertions.expect_true(int(workload_metrics["weapon_attacks"]) > 0, "performance workload fires equipped weapons")
	assertions.expect_true(int(workload_metrics["enemy_recycles"]) >= 4, "fixture periodically removes and respawns enemies")
	assertions.expect_true(int(workload_metrics["enemy_pool_reuse"]) > 0, "performance enemy pool reuses slots")
	assertions.expect_true(int(workload_metrics["projectile_pool_reuse"]) > 0, "performance projectile pool reuses slots")
	assertions.expect_true(int(workload_metrics["vfx_pool_reuse"]) > 0, "performance VFX pool reuses slots")
	assertions.expect_true(int(workload_metrics["xp_pool_reuse"]) > 0, "performance XP pool reuses slots")
	assertions.expect_equal(0, workload_metrics["pool_orphan_count"], "performance pools have no orphan indices")
	var tracked_id: int = simulation.enemy_system.enemy_store.snapshot_ids_sorted()[0]
	var tracked_enemy: EnemyEntity = simulation.enemy_system.enemy_store.get_by_id(tracked_id)
	assertions.expect_true(
		simulation.enemy_system.uniform_grid.query_circle_candidates(
			tracked_enemy.position,
			0.1,
			0.0,
		).has(tracked_id),
		"active workload grid owns the current tracked enemy position",
	)
	runner.call("_capture_and_validate_workload_metrics")
	assertions.expect_equal(PackedStringArray(), runner.get("_failure_reasons"), "formal runner accepts active workload counters")
	var summary: Dictionary = runner.call("_build_summary", {})
	assertions.expect_true(bool(summary["active_workload"]), "formal summary records active workload")
	assertions.expect_equal(600, summary["workload_ticks"], "formal summary records workload tick count")
	assertions.expect_equal(0, summary["pool_orphan_count"], "formal summary records zero pool orphans")
	runner.free()

	var wrong_seed_simulation := _new_simulation(RunnerScript.RUN_SEED + 1, catalog)
	var wrong_seed_runner: Variant = RunnerScript.new()
	assertions.expect_equal(
		ERR_INVALID_DATA,
		wrong_seed_runner.initialize(wrong_seed_simulation, output_directory),
		"performance runner rejects a different run seed",
	)
	assertions.expect_equal(
		"performance_run_seed_not_5002000",
		wrong_seed_runner.last_error_message,
		"wrong seed rejection is diagnostic",
	)
	wrong_seed_runner.free()

	var partial_simulation := _new_simulation(RunnerScript.RUN_SEED, catalog)
	partial_simulation.spawn_fixture_enemy(GameTypes.EnemyType.PURSUER, Vector2.ZERO)
	var partial_runner: Variant = RunnerScript.new()
	assertions.expect_equal(
		ERR_INVALID_DATA,
		partial_runner.initialize(partial_simulation, output_directory),
		"performance runner rejects partial pre-existing load",
	)
	assertions.expect_equal(
		"full_load_fixture_requires_empty_or_exact_simulation",
		partial_runner.last_error_message,
		"partial load rejection is diagnostic",
	)
	partial_runner.free()


func _new_simulation(run_seed: int, catalog: DefinitionCatalog) -> CombatSimulation:
	var state: RunState = RunStateFactory.create(run_seed, catalog)
	var simulation := CombatSimulation.new()
	simulation.initialize(state, catalog)
	return simulation
