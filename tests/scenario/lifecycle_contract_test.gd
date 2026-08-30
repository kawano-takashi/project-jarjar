extends RefCounted


func test_names() -> PackedStringArray:
	return PackedStringArray([
		"new_run_starts_with_one_wood_stick_and_five_empty_slots",
		"inventory_gate_requires_overflow_empty_and_one_weapon",
		"run_state_has_no_legacy_compatibility_fields",
	])


func run_test(test_name: String, assertions: Variant, _context: Dictionary) -> void:
	match test_name:
		"new_run_starts_with_one_wood_stick_and_five_empty_slots":
			_test_initial_state(assertions)
		"inventory_gate_requires_overflow_empty_and_one_weapon":
			_test_gate(assertions)
		"run_state_has_no_legacy_compatibility_fields":
			_test_no_compat(assertions)
		_:
			assertions.expect_true(false, "registered lifecycle contract test")


func _test_initial_state(assertions: Variant) -> void:
	var catalog := DefinitionCatalog.new()
	assertions.expect_true(catalog.load_and_validate(), "lifecycle catalog valid")
	var state: RunState = RunStateFactory.create(123456, catalog.wave(1))
	var starter: ItemInstance = state.equipped[GameTypes.EquipmentSlot.WEAPON_1]
	assertions.expect_true(starter != null, "starter weapon exists")
	assertions.expect_equal(GameTypes.WeaponType.WOOD_STICK, starter.weapon_type, "starter is wood stick")
	assertions.expect_equal(GameTypes.Rarity.COMMON, starter.rarity, "starter is common-equivalent")
	assertions.expect_equal(1, InventoryService.equipped_items(state).size(), "other five equipment slots start empty")
	assertions.expect_equal(36, state.inventory.size(), "storage capacity remains 36")
	assertions.expect_equal(1, state.drop_serial, "starter reserves deterministic item serial zero")


func _test_gate(assertions: Variant) -> void:
	var catalog := DefinitionCatalog.new()
	assertions.expect_true(catalog.load_and_validate(), "gate catalog valid")
	var state: RunState = RunStateFactory.create(987, catalog.wave(1))
	state.phase = GameTypes.RunPhase.INVENTORY
	assertions.expect_true(RunStateMachine.can_transition_state(state, GameTypes.RunPhase.COMBAT), "one weapon and empty overflow may continue")
	state.overflow.append(QaItemBuilder.weapon(catalog, "overflow-gate", GameTypes.WeaponType.BOW))
	assertions.expect_false(RunStateMachine.can_transition_state(state, GameTypes.RunPhase.COMBAT), "temporary receiving items block continue")
	state.overflow.clear()
	state.equipped[GameTypes.EquipmentSlot.WEAPON_1] = null
	assertions.expect_false(RunStateMachine.can_transition_state(state, GameTypes.RunPhase.COMBAT), "zero weapons block combat")


func _test_no_compat(assertions: Variant) -> void:
	var state := RunState.new()
	var names: Dictionary[StringName, bool] = {}
	for property: Dictionary in state.get_property_list():
		names[StringName(property["name"])] = true
	for removed: StringName in [
		&"skill_library",
		&"wild_material_count",
		&"scheduled_proc_replays",
		&"wave_main_weapon_type",
	]:
		assertions.expect_false(names.has(removed), "no saved-run compatibility field %s" % removed)
