extends RefCounted


func test_names() -> PackedStringArray:
	return PackedStringArray([
		"qa_fixture_ids_match_parser_and_build",
		"qa_fixtures_preserve_gameplay_rng_and_survival_contract",
	])


func run_test(test_name: String, assertions: Variant, _context: Dictionary) -> void:
	match test_name:
		"qa_fixture_ids_match_parser_and_build":
			_test_ids(assertions)
		"qa_fixtures_preserve_gameplay_rng_and_survival_contract":
			_test_builds(assertions)
		_:
			assertions.expect_true(false, "registered QA fixture test")


func _test_ids(assertions: Variant) -> void:
	assertions.expect_equal(
		QaScenarioFactory.VALID_IDS,
		LaunchArguments.QA_SCENARIOS,
		"factory and argument parser expose exact same survival QA IDs",
	)
	for scenario_id: String in LaunchArguments.QA_SCENARIOS:
		var parsed: Dictionary = LaunchArguments.parse_debug(
			PackedStringArray(["--qa-scenario=" + scenario_id])
		)
		assertions.expect_true(parsed["valid"], "QA argument accepted: %s" % scenario_id)
		assertions.expect_equal(
			scenario_id,
			parsed["qa_scenario"],
			"QA ID parsed: %s" % scenario_id,
		)
	assertions.expect_false(
		LaunchArguments.parse_debug(
			PackedStringArray(["--qa-scenario=inventory_controller"])
		)["valid"],
		"removed equipment QA scenario rejected",
	)


func _test_builds(assertions: Variant) -> void:
	var catalog := DefinitionCatalog.new()
	assertions.expect_true(catalog.load_and_validate(), "QA fixture catalog valid")
	if not catalog.is_valid:
		return
	for scenario_id: String in QaScenarioFactory.VALID_IDS:
		var fixture: Dictionary = QaScenarioFactory.build(scenario_id, catalog)
		assertions.expect_true(
			fixture.get("valid", false),
			"QA fixture builds: %s" % scenario_id,
		)
		assertions.expect_true(
			fixture.get("rng_unchanged", false),
			"QA fixture preserves gameplay RNG: %s" % scenario_id,
		)
		assertions.expect_false(
			fixture.get("tutorial_active", true),
			"QA fixture disables tutorial: %s" % scenario_id,
		)
		var state: RunState = fixture.get("state") as RunState
		var simulation: CombatSimulation = fixture.get("simulation") as CombatSimulation
		assertions.expect_true(state != null, "QA fixture has run state: %s" % scenario_id)
		assertions.expect_true(
			simulation != null,
			"QA fixture has simulation: %s" % scenario_id,
		)
		if state == null or simulation == null:
			continue
		if QaScenarioFactory.WEAPON_SCENARIO_IDS.has(scenario_id):
			_assert_weapon_fixture(assertions, scenario_id, state, simulation, catalog)
		elif scenario_id == "level_up_modal":
			_assert_level_fixture(assertions, state)
		elif scenario_id == "chest_reward":
			_assert_chest_fixture(assertions, state)
		elif scenario_id == "boss_phase_three":
			_assert_boss_fixture(assertions, state, simulation)
		elif scenario_id == "result":
			_assert_result_fixture(assertions, state)


func _assert_weapon_fixture(
	assertions: Variant,
	scenario_id: String,
	state: RunState,
	simulation: CombatSimulation,
	catalog: DefinitionCatalog,
) -> void:
	assertions.expect_equal(1, state.weapons.size(), "%s has one focused weapon" % scenario_id)
	if state.weapons.is_empty():
		return
	var runtime: RunWeapon = state.weapons[0]
	var expected_id: StringName = QaScenarioFactory.WEAPON_SCENARIO_IDS[scenario_id]
	var definition: WeaponDefinition = catalog.weapon(expected_id)
	assertions.expect_equal(expected_id, runtime.weapon_id, "%s selects exact weapon" % scenario_id)
	assertions.expect_equal(definition.max_level, runtime.level, "%s demonstrates level 8" % scenario_id)
	assertions.expect_equal(
		1,
		simulation.enemy_system.enemy_store.active_count(),
		"%s has one fixed durability target" % scenario_id,
	)


func _assert_level_fixture(assertions: Variant, state: RunState) -> void:
	assertions.expect_equal(GameTypes.RunPhase.LEVEL_UP, state.phase, "level fixture opens modal")
	assertions.expect_true(state.active_level_offer != null, "level fixture owns an offer")
	if state.active_level_offer == null:
		return
	assertions.expect_equal(3, state.active_level_offer.options.size(), "level fixture has three choices")
	var ids: Dictionary[StringName, bool] = {}
	for option: UpgradeOption in state.active_level_offer.options:
		ids[option.content_id] = true
	assertions.expect_equal(3, ids.size(), "level fixture choices do not repeat")


func _assert_chest_fixture(assertions: Variant, state: RunState) -> void:
	assertions.expect_equal(
		GameTypes.RunPhase.CHEST_REWARD,
		state.phase,
		"chest fixture opens modal",
	)
	assertions.expect_true(state.active_chest_outcome != null, "chest fixture owns outcome")
	if state.active_chest_outcome == null:
		return
	assertions.expect_equal(
		GameTypes.ChestOutcomeKind.EVOLUTION,
		state.active_chest_outcome.kind,
		"chest fixture demonstrates an evolution",
	)
	assertions.expect_equal(
		&"infinite_homing",
		state.active_chest_outcome.content_id,
		"chest fixture evolves the homing starter lineage",
	)


func _assert_boss_fixture(
	assertions: Variant,
	state: RunState,
	simulation: CombatSimulation,
) -> void:
	assertions.expect_true(state.boss_spawned, "boss fixture marks boss spawned")
	assertions.expect_equal(3, state.boss_phase, "boss fixture starts in phase three")
	assertions.expect_equal(3, state.boss_enrage_stacks, "boss fixture shows enrage stacks")
	assertions.expect_true(simulation.enemy_system.boss_entity() != null, "boss fixture owns boss")


func _assert_result_fixture(assertions: Variant, state: RunState) -> void:
	assertions.expect_equal(GameTypes.RunPhase.RESULT, state.phase, "result fixture is victory")
	assertions.expect_true(state.boss_defeated, "result fixture records boss victory")
	assertions.expect_equal(4, state.elite_kills, "result fixture includes four elites")
	assertions.expect_equal(2, state.evolution_count, "result fixture includes evolution count")
	assertions.expect_true(
		state.weapon_damage_by_lineage.has(&"resonance_wave"),
		"result fixture includes lineage damage",
	)
