extends RefCounted


func test_tutorial_contextual_sequence(assertions: Variant, _context: Dictionary) -> void:
	var tutorial := TutorialController.new()
	var completions: Array[bool] = []
	tutorial.completed.connect(func() -> void:
		completions.append(true)
	)
	tutorial.begin_run(false, BalanceTestFixtures.catalog())
	assertions.expect_true(tutorial.enabled, "incomplete tutorial enables contextual hints")
	assertions.expect_equal(TutorialController.MOVE_MESSAGE, tutorial.current_message(), "movement and automatic attack appear first")
	for _tick: int in range(59):
		tutorial.advance_movement(Vector2.RIGHT, 1.0 / 60.0)
	assertions.expect_false(tutorial.move_completed, "59 movement ticks do not complete onboarding")
	assertions.expect_true(tutorial.advance_movement(Vector2.RIGHT, 1.0 / 60.0), "60th movement tick completes onboarding")
	assertions.expect_false(tutorial.advance_movement(Vector2.RIGHT, 1.0), "completed movement cannot emit twice")
	assertions.expect_equal([true], completions, "tutorial completion emits exactly once")

	for context_id: StringName in [
		&"xp_pickup",
		&"level_up",
		&"chest_pickup",
		&"evolution",
		&"stop_pickup",
		&"boss_spawn",
	]:
		assertions.expect_true(tutorial.notify_context(context_id), "%s displays on first encounter" % context_id)
		assertions.expect_false(tutorial.current_message().is_empty(), "%s has contextual text" % context_id)
		assertions.expect_false(tutorial.notify_context(context_id), "%s never repeats in the same run" % context_id)
		tutorial.advance(TutorialController.CONTEXT_MESSAGE_SECONDS)
		assertions.expect_equal("", tutorial.current_message(), "%s expires without input" % context_id)


func test_completed_tutorial_skips_contextual_hints(assertions: Variant, _context: Dictionary) -> void:
	var tutorial := TutorialController.new()
	tutorial.begin_run(true, BalanceTestFixtures.catalog())
	assertions.expect_false(tutorial.enabled, "completed tutorial suppresses first-run hints")
	assertions.expect_true(tutorial.move_completed, "completed tutorial never gates movement")
	assertions.expect_equal("", tutorial.current_message(), "completed tutorial has no initial message")
	assertions.expect_false(tutorial.notify_context(&"level_up"), "completed tutorial suppresses context")
