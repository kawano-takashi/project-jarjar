extends RefCounted


const MetricsScript = preload("res://src/debug/performance_metrics.gd")
const RunnerScript = preload("res://src/debug/performance_runner.gd")


func test_names() -> PackedStringArray:
	return PackedStringArray([
		"gate06_performance_nearest_rank_and_memory_median",
		"gate06_performance_summary_thresholds",
		"gate06_performance_csv_buffer_contract",
		"gate06_performance_fixture_contract",
	])


func run_test(test_name: String, assertions: Variant, context: Dictionary) -> void:
	match test_name:
		"gate06_performance_nearest_rank_and_memory_median":
			_test_nearest_rank_and_memory_median(assertions)
		"gate06_performance_summary_thresholds":
			_test_summary_thresholds(assertions)
		"gate06_performance_csv_buffer_contract":
			_test_csv_buffer_contract(assertions)
		"gate06_performance_fixture_contract":
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
		"projectile_pool_used": 1_200,
		"vfx_pool_used": 800,
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
	runner.call("_record_csv_frame", 2_345, values)
	var overrides: Dictionary = runner.get("_csv_count_overrides")
	assertions.expect_equal(
		PackedInt64Array([499, 1_199, 799]),
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
	assertions.expect_true(catalog.load_and_validate(), "performance fixture catalog valid")
	if not catalog.is_valid:
		return

	var simulation := _new_simulation(RunnerScript.RUN_SEED, catalog)
	var runner: Variant = RunnerScript.new()
	var initialize_error: Error = runner.initialize(simulation, output_directory)
	assertions.expect_equal(OK, initialize_error, "performance runner accepts initialized seed 5002000 simulation")
	assertions.expect_equal(500, simulation.enemy_system.enemy_store.active_count(), "performance fixture enemy count")
	assertions.expect_equal(1_200, simulation.projectile_pool.active_count(), "performance fixture projectile count")
	assertions.expect_equal(800, simulation.vfx_pool.active_count(), "performance fixture VFX count")
	assertions.expect_true(simulation.freeze_enemy_ai, "performance fixture freezes enemy AI")
	assertions.expect_true(simulation.freeze_enemy_timers, "performance fixture freezes enemy timers")
	assertions.expect_true(simulation.freeze_normal_spawn, "performance fixture freezes normal spawn")
	assertions.expect_true(simulation.freeze_countdown, "performance fixture freezes countdown")
	assertions.expect_true(simulation.freeze_all_updates, "performance fixture freezes state updates")
	var initial_tick: int = simulation.state.physics_tick
	var initial_rng := {
		"combat": simulation.state.rng_streams.combat_rng.state,
		"loot": simulation.state.rng_streams.loot_rng.state,
		"fusion": simulation.state.rng_streams.fusion_rng.state,
	}
	for _tick: int in range(600):
		simulation.step(Vector2.RIGHT, 1.0 / 60.0)
	assertions.expect_equal(initial_tick, simulation.state.physics_tick, "performance fixture does not advance combat ticks")
	assertions.expect_equal(500, simulation.enemy_system.enemy_store.active_count(), "performance enemies remain exact across 600 steps")
	assertions.expect_equal(1_200, simulation.projectile_pool.active_count(), "performance projectiles remain exact across 600 steps")
	assertions.expect_equal(800, simulation.vfx_pool.active_count(), "performance VFX remain exact across 600 steps")
	assertions.expect_equal(0, simulation.enemy_system.enemy_store.overflow_count, "performance enemy overflow remains zero")
	assertions.expect_equal(0, simulation.projectile_pool.overflow_count, "performance projectile overflow remains zero")
	assertions.expect_equal(0, simulation.vfx_pool.overflow_count, "performance VFX overflow remains zero")
	assertions.expect_equal(initial_rng, {
		"combat": simulation.state.rng_streams.combat_rng.state,
		"loot": simulation.state.rng_streams.loot_rng.state,
		"fusion": simulation.state.rng_streams.fusion_rng.state,
	}, "performance fixture preserves all RNG states")
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
	partial_simulation.spawn_fixture_enemy(GameTypes.EnemyType.TRACKER, Vector2.ZERO)
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
	var state: RunState = RunStateFactory.create(run_seed, catalog.wave(1))
	var simulation := CombatSimulation.new()
	simulation.initialize(state, catalog)
	return simulation
