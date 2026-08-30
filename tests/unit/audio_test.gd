extends RefCounted


func test_names() -> PackedStringArray:
	return PackedStringArray([
		"current_reward_and_combat_audio_streams_generate",
	])


func run_test(test_name: String, assertions: Variant, _context: Dictionary) -> void:
	if test_name != "current_reward_and_combat_audio_streams_generate":
		assertions.expect_true(false, "registered audio test")
		return
	var streams: Array[AudioStreamWAV] = [
		AudioFactory.pickup(),
		AudioFactory.normal_open(),
		AudioFactory.rare_open(),
		AudioFactory.epic_prealert(),
		AudioFactory.legendary_prealert(),
		AudioFactory.wave_clear(),
		AudioFactory.fusion(),
	]
	for index: int in range(streams.size()):
		assertions.expect_true(streams[index] != null, "current audio stream %d exists" % index)
		if streams[index] != null:
			assertions.expect_true(streams[index].data.size() > 0, "current audio stream %d has PCM" % index)
