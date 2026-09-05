extends RefCounted


func test_names() -> PackedStringArray:
	return PackedStringArray([
		"survival_run_phase_contract",
	])


func run_test(test_name: String, assertions: Variant, _context: Dictionary) -> void:
	match test_name:
		"survival_run_phase_contract":
			_test_run_phases(assertions)
		_:
			assertions.expect_true(false, "registered survival domain test")



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
	assertions.expect_true(catalog.validate_manifest(BalanceTestFixtures.manifest()), "survival catalog valid: %s" % catalog.error_text)
	return catalog
