extends RefCounted


func test_names() -> PackedStringArray:
	return PackedStringArray([
		"new_run_starts_with_survival_build_contract",
		"automatic_modal_queue_resumes_with_protection",
		"run_phase_contract_is_exact",
	])


func run_test(test_name: String, assertions: Variant, _context: Dictionary) -> void:
	match test_name:
		"new_run_starts_with_survival_build_contract":
			_test_initial_state(assertions)
		"automatic_modal_queue_resumes_with_protection":
			_test_modal_lifecycle(assertions)
		"run_phase_contract_is_exact":
			_test_phase_contract(assertions)
		_:
			assertions.expect_true(false, "registered survival lifecycle contract test")


func _test_initial_state(assertions: Variant) -> void:
	var catalog := DefinitionCatalog.new()
	assertions.expect_true(catalog.load_and_validate(), "survival catalog valid")
	var state: RunState = RunStateFactory.create(123456, catalog)
	assertions.expect_equal(GameTypes.RunPhase.COMBAT, state.phase, "new run enters continuous combat")
	assertions.expect_equal(1, state.weapons.size(), "starter occupies one of five weapon slots")
	assertions.expect_equal(0, state.passives.size(), "five passive slots start available")
	assertions.expect_equal(&"homing_core", state.weapons[0].weapon_id, "starter attacks the nearest enemy")
	assertions.expect_equal(1, state.weapons[0].level, "starter begins at level one")
	assertions.expect_equal(1, state.level, "player begins at level one")
	assertions.expect_equal(0, state.combat_tick, "ten-minute clock begins at zero")
	assertions.expect_equal(0, state.pending_level_ups, "no initial level modal")
	assertions.expect_equal(0, state.pending_chest_count(), "no initial chest modal")


func _test_modal_lifecycle(assertions: Variant) -> void:
	var catalog := DefinitionCatalog.new()
	assertions.expect_true(catalog.load_and_validate(), "modal lifecycle catalog valid")
	var state: RunState = RunStateFactory.create(654321, catalog)
	var simulation := CombatSimulation.new()
	simulation.initialize(state, catalog)
	state.pending_level_ups = 2
	state.pending_chest_sources.append(0)
	var max_hp_option := UpgradeOption.new()
	max_hp_option.kind = GameTypes.UpgradeKind.PASSIVE
	max_hp_option.content_id = &"life_lattice"
	var offer := LevelOffer.new()
	offer.serial = state.next_offer_serial
	state.next_offer_serial += 1
	offer.options.append(max_hp_option)
	state.active_level_offer = offer
	assertions.expect_true(RunStateMachine.transition(state, GameTypes.RunPhase.LEVEL_UP), "combat enters level-up modal")
	assertions.expect_true(simulation.apply_upgrade_choice(0), "first queued level choice applies")
	assertions.expect_equal(120.0, state.max_hp, "max-HP passive refreshes derived max HP immediately")
	assertions.expect_equal(120.0, state.current_hp, "new max HP adds the gained capacity to current HP")
	assertions.expect_equal(GameTypes.RunPhase.LEVEL_UP, state.phase, "second level modal stays queued")
	assertions.expect_equal(0, state.modal_invulnerable_until_tick, "intermediate level modal grants no protection")
	assertions.expect_true(state.active_level_offer != null, "second level offer is active")
	assertions.expect_true(simulation.apply_upgrade_choice(0), "second queued level choice applies")
	assertions.expect_equal(GameTypes.RunPhase.CHEST_REWARD, state.phase, "chest follows all queued level choices")
	assertions.expect_equal(0, state.modal_invulnerable_until_tick, "intermediate chest grants no protection")
	assertions.expect_true(state.active_chest_outcome != null, "queued chest outcome is active")
	assertions.expect_true(simulation.skip_chest_animation(), "chest outcome applies once")
	assertions.expect_equal(GameTypes.RunPhase.COMBAT, state.phase, "final automatic modal returns to combat")
	assertions.expect_equal(46, state.modal_invulnerable_until_tick, "exclusive deadline protects the next 45 steps")
	state.combat_tick = 45
	assertions.expect_true(state.is_invulnerable(), "protection includes automatic-resume step 45")
	state.combat_tick = 46
	assertions.expect_false(state.is_invulnerable(), "protection expires before step 46")
	assertions.expect_equal(0, state.pending_level_ups, "all queued levels are consumed")
	assertions.expect_equal(0, state.pending_chest_count(), "applied chest consumes one queued chest")
	assertions.expect_equal(1, state.opened_chests, "opened chest statistic increments")
	assertions.expect_true(state.active_chest_outcome == null, "applied chest clears active modal data")


func _test_phase_contract(assertions: Variant) -> void:
	assertions.expect_equal(7, GameTypes.RunPhase.size(), "run lifecycle has seven phases")
	assertions.expect_equal(0, GameTypes.RunPhase.BOOT, "boot phase ordinal fixed")
	assertions.expect_equal(1, GameTypes.RunPhase.TITLE, "title phase ordinal fixed")
	assertions.expect_equal(2, GameTypes.RunPhase.COMBAT, "combat phase ordinal fixed")
	assertions.expect_equal(3, GameTypes.RunPhase.LEVEL_UP, "level-up phase ordinal fixed")
	assertions.expect_equal(4, GameTypes.RunPhase.CHEST_REWARD, "chest phase ordinal fixed")
	assertions.expect_equal(5, GameTypes.RunPhase.RESULT, "result phase ordinal fixed")
	assertions.expect_equal(6, GameTypes.RunPhase.FAILED, "failed phase ordinal fixed")
