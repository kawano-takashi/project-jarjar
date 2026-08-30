extends RefCounted


func test_names() -> PackedStringArray:
	return PackedStringArray([
		"qa_fixture_ids_match_parser_and_build",
		"qa_fixtures_do_not_consume_mutable_rng",
	])


func run_test(test_name: String, assertions: Variant, _context: Dictionary) -> void:
	match test_name:
		"qa_fixture_ids_match_parser_and_build":
			_test_ids(assertions)
		"qa_fixtures_do_not_consume_mutable_rng":
			_test_builds(assertions)
		_:
			assertions.expect_true(false, "registered QA fixture test")


func _test_ids(assertions: Variant) -> void:
	assertions.expect_equal(QaScenarioFactory.VALID_IDS, LaunchArguments.QA_SCENARIOS, "factory and argument parser expose exact same QA IDs")
	for scenario_id: String in LaunchArguments.QA_SCENARIOS:
		var parsed: Dictionary = LaunchArguments.parse_debug(PackedStringArray(["--qa-scenario=" + scenario_id]))
		assertions.expect_true(parsed["valid"], "QA argument accepted: %s" % scenario_id)
		assertions.expect_equal(scenario_id, parsed["qa_scenario"], "QA ID parsed: %s" % scenario_id)
	assertions.expect_false(LaunchArguments.parse_debug(PackedStringArray(["--qa-scenario=immortal_100"]))["valid"], "removed unique QA scenario rejected")


func _test_builds(assertions: Variant) -> void:
	var catalog := DefinitionCatalog.new()
	assertions.expect_true(catalog.load_and_validate(), "QA fixture catalog valid")
	if not catalog.is_valid:
		return
	for scenario_id: String in QaScenarioFactory.VALID_IDS:
		var fixture: Dictionary = QaScenarioFactory.build(scenario_id, catalog)
		assertions.expect_true(fixture.get("valid", false), "QA fixture builds: %s" % scenario_id)
		assertions.expect_true(fixture.get("rng_unchanged", false), "QA fixture preserves gameplay RNG: %s" % scenario_id)
		assertions.expect_false(fixture.get("tutorial_active", true), "QA fixture disables tutorial: %s" % scenario_id)
		var state: RunState = fixture.get("state") as RunState
		assertions.expect_true(state != null, "QA fixture has run state: %s" % scenario_id)
		if state == null:
			continue
		if scenario_id == "weapon_stagger":
			_test_weapon_stagger_fixture(assertions, fixture, state)


func _test_weapon_stagger_fixture(
	assertions: Variant,
	fixture: Dictionary,
	state: RunState,
) -> void:
	var item_ids: Dictionary[StringName, bool] = {}
	for slot: GameTypes.EquipmentSlot in GameTypes.weapon_slots():
		var item: ItemInstance = state.equipped.get(slot) as ItemInstance
		assertions.expect_true(item != null, "weapon stagger fills weapon slot %d" % int(slot))
		if item == null:
			continue
		assertions.expect_equal(GameTypes.WeaponType.BOW, item.weapon_type, "weapon stagger uses a bow in slot %d" % int(slot))
		item_ids[item.item_id] = true
	assertions.expect_equal(3, item_ids.size(), "weapon stagger bows have distinct item IDs")
	var simulation: CombatSimulation = fixture.get("simulation") as CombatSimulation
	assertions.expect_true(simulation != null, "weapon stagger fixture has a simulation")
	if simulation == null:
		return
	assertions.expect_float(0.0, simulation.weapon_damage_override, "weapon stagger attacks deal zero damage")
	assertions.expect_true(simulation.freeze_normal_spawn, "weapon stagger stops normal spawning")
	assertions.expect_true(simulation.freeze_enemy_ai, "weapon stagger stops enemy AI")
	assertions.expect_true(simulation.freeze_enemy_timers, "weapon stagger stops enemy timers")
	assertions.expect_true(simulation.freeze_countdown, "weapon stagger stops the wave countdown")
	assertions.expect_equal(1, simulation.enemy_system.enemy_store.active_count(), "weapon stagger keeps one fixed target")
