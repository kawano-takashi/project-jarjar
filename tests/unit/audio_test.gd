extends RefCounted


func test_survival_feedback_streams_generate(assertions: Variant, _context: Dictionary) -> void:
	var streams: Dictionary[StringName, AudioStream] = AudioFactory.build_event_streams()
	assertions.expect_false(streams.is_empty(), "combat audio cues are available")
	for event_id: StringName in streams:
		var stream := streams[event_id] as AudioStreamWAV
		assertions.expect_true(stream != null, "%s generates an audio stream" % event_id)
		if stream != null:
			assertions.expect_true(stream.data.size() > 0, "%s contains sound data" % event_id)
