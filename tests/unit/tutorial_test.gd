extends RefCounted


func test_names() -> PackedStringArray:
	return PackedStringArray([
		"tutorial_revision_four_contextual_sequence",
		"current_revision_skips_contextual_tutorial",
	])


func run_test(test_name: String, assertions: Variant, _context: Dictionary) -> void:
	match test_name:
		"tutorial_revision_four_contextual_sequence":
			_test_contextual_sequence(assertions)
		"current_revision_skips_contextual_tutorial":
			_test_current_revision(assertions)
		_:
			assertions.expect_true(false, "registered survival tutorial test")


func _test_contextual_sequence(assertions: Variant) -> void:
	var tutorial := TutorialController.new()
	var completed_revisions: Array[int] = []
	tutorial.revision_completed.connect(func(revision: int) -> void:
		completed_revisions.append(revision)
	)
	tutorial.begin_run(0)
	assertions.expect_true(tutorial.enabled, "old revision enables contextual hints")
	assertions.expect_equal(TutorialController.MOVE_MESSAGE, tutorial.current_message(), "movement and automatic attack appear first")
	for _tick: int in range(59):
		tutorial.advance_movement(Vector2.RIGHT, 1.0 / 60.0)
	assertions.expect_false(tutorial.move_completed, "59 movement ticks do not complete revision")
	assertions.expect_true(tutorial.advance_movement(Vector2.RIGHT, 1.0 / 60.0), "60th movement tick completes onboarding")
	assertions.expect_equal([TutorialController.REVISION], completed_revisions, "revision four completion emits once")
	assertions.expect_false(tutorial.advance_movement(Vector2.RIGHT, 1.0), "completed movement cannot emit twice")

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


func _test_current_revision(assertions: Variant) -> void:
	var tutorial := TutorialController.new()
	tutorial.begin_run(TutorialController.REVISION)
	assertions.expect_false(tutorial.enabled, "current revision suppresses first-run hints")
	assertions.expect_true(tutorial.move_completed, "current revision never gates movement")
	assertions.expect_equal("", tutorial.current_message(), "current revision has no initial message")
	assertions.expect_false(tutorial.notify_context(&"level_up"), "current revision suppresses context")
