extends RefCounted


func test_names() -> PackedStringArray:
	return PackedStringArray([
		"survival_manifest_global_contract",
		"survival_run_phase_contract",
	])


func run_test(test_name: String, assertions: Variant, _context: Dictionary) -> void:
	match test_name:
		"survival_manifest_global_contract":
			_test_manifest_globals(assertions)
		"survival_run_phase_contract":
			_test_run_phases(assertions)
		_:
			assertions.expect_true(false, "registered survival domain test")


func _test_manifest_globals(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	if not catalog.is_valid:
		return
	var manifest: SurvivalContentManifest = catalog.manifest()
	assertions.expect_equal(Vector2(32.0, 32.0), manifest.arena_size, "finite 32x32 arena")
	assertions.expect_equal(60, manifest.ticks_per_second, "fixed 60Hz domain clock")
	assertions.expect_equal(36000, manifest.boss_start_tick, "boss starts at ten minutes")
	assertions.expect_equal(19, manifest.xp_early_max_level, "early XP band ends at level nineteen")
	assertions.expect_equal(10, manifest.xp_early_coefficient, "early XP coefficient")
	assertions.expect_equal(-5, manifest.xp_early_offset, "early XP offset")
	assertions.expect_equal(795, manifest.xp_level_20_requirement, "level twenty compensated requirement")
	assertions.expect_equal(39, manifest.xp_middle_max_level, "middle XP band ends at level thirty-nine")
	assertions.expect_equal(13, manifest.xp_middle_coefficient, "middle XP coefficient")
	assertions.expect_equal(-65, manifest.xp_middle_offset, "middle XP offset")
	assertions.expect_equal(2855, manifest.xp_level_40_requirement, "level forty compensated requirement")
	assertions.expect_equal(16, manifest.xp_late_coefficient, "late XP coefficient")
	assertions.expect_equal(-185, manifest.xp_late_offset, "late XP offset")
	assertions.expect_equal(PackedInt32Array([20, 40]), manifest.xp_growth_compensation_levels, "Growth compensation levels")
	assertions.expect_float(2.0, manifest.xp_growth_compensation_multiplier, "Growth compensation multiplier")
	assertions.expect_equal(2048, manifest.xp_pool_capacity, "XP pool capacity")
	assertions.expect_float(2.25, manifest.xp_pickup_attract_radius, "XP pickup attract radius")
	assertions.expect_float(0.7, manifest.xp_pickup_collect_radius, "XP pickup collect radius")
	assertions.expect_float(14.0, manifest.xp_pickup_speed, "XP pickup movement speed")
	assertions.expect_equal(5, manifest.weapon_slot_count, "five weapon slots")
	assertions.expect_equal(5, manifest.passive_slot_count, "five passive slots")
	assertions.expect_equal(3, manifest.level_offer_count, "three level-up choices")
	assertions.expect_equal(PackedInt32Array([7200, 14400, 21600, 28800]), manifest.elite_spawn_ticks, "four scheduled elites")
	assertions.expect_equal(PackedFloat32Array([0.55, 0.35, 0.07, 0.03]), manifest.node_drop_weights, "approved node drop weights")
	assertions.expect_equal(1800, manifest.boss_enrage_interval_ticks, "boss enrage every thirty seconds")
	assertions.expect_equal(10, manifest.boss_enrage_max_stacks, "boss enrage stack cap")
	assertions.expect_float(0.10, manifest.boss_attack_bonus_per_stack, "boss attack bonus per stack")
	assertions.expect_float(0.10, manifest.boss_interval_reduction_per_stack, "boss interval reduction per stack")


func _test_run_phases(assertions: Variant) -> void:
	assertions.expect_equal(7, GameTypes.RunPhase.size(), "seven run phases")
	var expected := PackedStringArray([
		"boot", "title", "combat", "level_up", "chest_reward", "result", "failed",
	])
	var actual := PackedStringArray()
	for phase_value: int in GameTypes.RunPhase.values():
		actual.append(GameTypes.run_phase_to_key(phase_value as GameTypes.RunPhase))
	assertions.expect_equal(expected, actual, "run phase keys exclude old reward and inventory phases")
	assertions.expect_true(RunStateMachine.can_transition(GameTypes.RunPhase.COMBAT, GameTypes.RunPhase.LEVEL_UP), "combat can open level modal")
	assertions.expect_true(RunStateMachine.can_transition(GameTypes.RunPhase.COMBAT, GameTypes.RunPhase.CHEST_REWARD), "combat can open chest modal")
	assertions.expect_false(RunStateMachine.can_transition(GameTypes.RunPhase.TITLE, GameTypes.RunPhase.RESULT), "invalid phase jump rejected")


func _catalog(assertions: Variant) -> DefinitionCatalog:
	var catalog := DefinitionCatalog.new()
	assertions.expect_true(catalog.load_and_validate(), "survival catalog valid: %s" % catalog.error_text)
	return catalog
