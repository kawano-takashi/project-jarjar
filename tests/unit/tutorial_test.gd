extends RefCounted


const TutorialControllerScript = preload("res://src/tutorial/tutorial_controller.gd")


func test_names() -> PackedStringArray:
	return PackedStringArray([
		"tutorial_sequence_and_timers",
		"tutorial_move_only_freezes_combat",
	])


func run_test(test_name: String, assertions: Variant, _context: Dictionary) -> void:
	match test_name:
		"tutorial_sequence_and_timers":
			_test_sequence_and_timers(assertions)
		"tutorial_move_only_freezes_combat":
			_test_move_only_freezes_combat(assertions)
		_:
			assertions.expect_true(false, "registered release readiness tutorial test")


func _test_sequence_and_timers(assertions: Variant) -> void:
	var tutorial: RefCounted = TutorialControllerScript.new()
	tutorial.begin_run(false)
	assertions.expect_true(tutorial.should_gate_combat(1), "unseen W1 tutorial gates combat")
	assertions.expect_false(tutorial.should_gate_combat(2), "tutorial gate is W1 only")
	tutorial.advance_move(Vector2.ZERO, 1.0)
	assertions.expect_float(0.0, float(tutorial.move_elapsed), "stationary time does not count")
	for _tick: int in range(59):
		tutorial.advance_move(Vector2.RIGHT, 1.0 / 60.0)
	assertions.expect_false(bool(tutorial.move_completed), "59 moving ticks remain gated")
	assertions.expect_true(tutorial.advance_move(Vector2.RIGHT, 1.0 / 60.0), "60th moving tick completes")
	assertions.expect_float(1.0, float(tutorial.move_elapsed), "movement timer clamps to one second")
	assertions.expect_false(tutorial.should_gate_combat(1), "completed movement releases combat")

	assertions.expect_true(tutorial.notify_first_pickup(), "first pickup starts message")
	assertions.expect_false(tutorial.notify_first_pickup(), "later pickups do not restart message")
	for _tick: int in range(119):
		tutorial.advance_combat(1.0 / 60.0)
	assertions.expect_true(float(tutorial.pickup_remaining) > 0.0, "pickup message lasts through tick 119")
	tutorial.advance_combat(1.0 / 60.0)
	assertions.expect_float(0.0, float(tutorial.pickup_remaining), "pickup message ends at two seconds")

	assertions.expect_true(tutorial.enter_reward(1), "first W1 reward message shown")
	assertions.expect_equal(TutorialControllerScript.REWARD_MESSAGE, tutorial.noncombat_message, "reward certainty wording")
	assertions.expect_true(tutorial.dismiss_noncombat(), "noncombat tutorial closes with cancel")
	assertions.expect_true(tutorial.enter_inventory(1), "first W1 inventory message shown")
	var inventory_message: String = str(tutorial.noncombat_message)
	var expected_tokens: Array[String] = ["装備", "LOCK", "3対1合成", "一時受取欄"]
	var previous_index: int = -1
	for token: String in expected_tokens:
		var token_index: int = inventory_message.find(token)
		assertions.expect_true(token_index > previous_index, "%s appears in required order" % token)
		previous_index = token_index
	assertions.expect_true(tutorial.leave_w1_inventory(1), "leaving W1 inventory completes tutorial")
	assertions.expect_false(bool(tutorial.enabled), "completed tutorial becomes inactive")

	var seen_tutorial: RefCounted = TutorialControllerScript.new()
	seen_tutorial.begin_run(true)
	assertions.expect_false(seen_tutorial.should_gate_combat(1), "seen tutorial never gates combat")


func _test_move_only_freezes_combat(assertions: Variant) -> void:
	var catalog := DefinitionCatalog.new()
	assertions.expect_true(catalog.load_and_validate(), "release readiness tutorial catalog valid")
	if not catalog.is_valid:
		return
	var state: RunState = RunStateFactory.create(20260827, catalog.wave(1))
	var simulation := CombatSimulation.new()
	simulation.initialize(state, catalog)
	var initial_time: float = state.time_remaining
	var combat_rng_state: int = state.rng_streams.combat_rng.state
	var loot_rng_state: int = state.rng_streams.loot_rng.state
	var fusion_rng_state: int = state.rng_streams.fusion_rng.state
	var initial_position: Vector2 = simulation.player_position
	for _tick: int in range(60):
		simulation.step_tutorial_movement(Vector2.RIGHT, 1.0 / 60.0)
	assertions.expect_true(simulation.player_position.x > initial_position.x, "tutorial move-only path moves player")
	assertions.expect_equal(0, state.physics_tick, "tutorial move-only path does not increment physics tick")
	assertions.expect_float(initial_time, state.time_remaining, "tutorial move-only path freezes countdown")
	assertions.expect_float(0.0, state.spawn_credit, "tutorial move-only path freezes spawn credit")
	assertions.expect_equal(0, state.non_boss_spawned, "tutorial move-only path creates no enemies")
	assertions.expect_equal(combat_rng_state, state.rng_streams.combat_rng.state, "tutorial move-only path preserves combat RNG")
	assertions.expect_equal(loot_rng_state, state.rng_streams.loot_rng.state, "tutorial move-only path preserves loot RNG")
	assertions.expect_equal(fusion_rng_state, state.rng_streams.fusion_rng.state, "tutorial move-only path preserves fusion RNG")
