extends RefCounted


func test_names() -> PackedStringArray:
	return PackedStringArray([
		"survival_feedback_streams_generate",
	])


func run_test(test_name: String, assertions: Variant, _context: Dictionary) -> void:
	if test_name != "survival_feedback_streams_generate":
		assertions.expect_true(false, "registered audio test")
		return
	var streams: Array[AudioStreamWAV] = [
		AudioFactory.xp_pickup(),
		AudioFactory.stop_pickup(),
		AudioFactory.level_up(),
		AudioFactory.chest_open(),
		AudioFactory.evolution(),
		AudioFactory.boss_spawn(),
		AudioFactory.player_hit(),
	]
	for index: int in range(streams.size()):
		assertions.expect_true(streams[index] != null, "survival audio stream %d exists" % index)
		if streams[index] != null:
			assertions.expect_true(streams[index].data.size() > 0, "survival audio stream %d has PCM" % index)
	var event_streams: Dictionary[StringName, AudioStream] = AudioFactory.build_event_streams()
	for event_id: StringName in [
		&"xp_pickup",
		&"stop_pickup",
		&"level_up",
		&"chest_pickup",
		&"chest_open",
		&"evolution",
		&"boss_spawn",
		&"player_hit",
	]:
		assertions.expect_true(event_streams.has(event_id), "event stream registered for %s" % event_id)
