extends RefCounted


const AudioFactoryScript := preload("res://src/audio/audio_factory.gd")
const AudioVoicePoolScript := preload("res://src/audio/audio_voice_pool.gd")


func test_names() -> PackedStringArray:
	return PackedStringArray([
		"gate06_audio_factory_stream_contract",
		"gate06_audio_factory_pcm_contract",
		"gate06_audio_voice_pool_contract",
	])


func run_test(test_name: String, assertions: Variant, context: Dictionary) -> void:
	match test_name:
		"gate06_audio_factory_stream_contract":
			_test_stream_contract(assertions)
		"gate06_audio_factory_pcm_contract":
			_test_pcm_contract(assertions)
		"gate06_audio_voice_pool_contract":
			_test_voice_pool_contract(assertions, context)
		_:
			assertions.expect_true(false, "registered Gate 6 audio test")


func _test_stream_contract(assertions: Variant) -> void:
	var cases: Array[Dictionary] = [
		{"label": "pickup", "stream": AudioFactoryScript.pickup(), "samples": 2_205},
		{"label": "normal open", "stream": AudioFactoryScript.normal_open(), "samples": 3_528},
		{"label": "Rare open", "stream": AudioFactoryScript.rare_open(), "samples": 5_292},
		{"label": "Epic prealert", "stream": AudioFactoryScript.epic_prealert(), "samples": 24_255},
		{"label": "Legendary prealert", "stream": AudioFactoryScript.legendary_prealert(), "samples": 33_075},
		{"label": "wave clear", "stream": AudioFactoryScript.wave_clear(), "samples": 15_876},
		{"label": "fusion", "stream": AudioFactoryScript.fusion(), "samples": 13_230},
	]
	for test_case: Dictionary in cases:
		var stream: AudioStreamWAV = test_case["stream"] as AudioStreamWAV
		var label: String = str(test_case["label"])
		assertions.expect_true(stream != null, "%s stream exists" % label)
		if stream == null:
			continue
		assertions.expect_equal(AudioStreamWAV.FORMAT_16_BITS, stream.format, "%s is PCM16" % label)
		assertions.expect_equal(AudioFactoryScript.SAMPLE_RATE, stream.mix_rate, "%s is 44.1 kHz" % label)
		assertions.expect_false(stream.stereo, "%s is mono" % label)
		assertions.expect_equal(AudioStreamWAV.LOOP_DISABLED, stream.loop_mode, "%s does not loop" % label)
		assertions.expect_equal(int(test_case["samples"]) * 2, stream.data.size(), "%s exact byte count" % label)


func _test_pcm_contract(assertions: Variant) -> void:
	var tone: AudioStreamWAV = AudioFactoryScript.pickup()
	var tone_samples: int = tone.data.size() >> 1
	assertions.expect_equal(0, _decode_s16(tone.data, 0), "tone starts at phase zero")
	assertions.expect_equal(0, _decode_s16(tone.data, tone_samples - 1), "tone release ends at zero")
	var maximum_sample: int = 0
	for sample_index: int in range(tone_samples):
		maximum_sample = maxi(maximum_sample, absi(_decode_s16(tone.data, sample_index)))
	assertions.expect_true(maximum_sample <= 21_300, "tone maximum amplitude is at most 0.65")
	assertions.expect_true(maximum_sample >= 21_000, "tone reaches the intended audible amplitude")

	var sweep: AudioStreamWAV = AudioFactoryScript.epic_prealert()
	var probe_index: int = 1_000
	var probe_time: float = float(probe_index) / float(AudioFactoryScript.SAMPLE_RATE)
	var expected_phase: float = TAU * (
		AudioFactoryScript.EPIC_PREALERT_START_HZ * probe_time
		+ 0.5
		* (AudioFactoryScript.EPIC_PREALERT_END_HZ - AudioFactoryScript.EPIC_PREALERT_START_HZ)
		* probe_time
		* probe_time
		/ AudioFactoryScript.EPIC_PREALERT_DURATION_SECONDS
	)
	var expected_sample: int = roundi(
		sin(expected_phase)
		* AudioFactoryScript.MAX_AMPLITUDE
		* AudioFactoryScript.PCM16_POSITIVE_MAX
	)
	assertions.expect_equal(expected_sample, _decode_s16(sweep.data, probe_index), "sweep phase integrates linearly interpolated frequency")

	var wave_clear: AudioStreamWAV = AudioFactoryScript.wave_clear()
	var note_samples: int = roundi(
		AudioFactoryScript.WAVE_CLEAR_NOTE_DURATION_SECONDS
		* float(AudioFactoryScript.SAMPLE_RATE)
	)
	for boundary_index: int in [0, note_samples - 1, note_samples, note_samples * 2 - 1, note_samples * 2, note_samples * 3 - 1]:
		assertions.expect_equal(0, _decode_s16(wave_clear.data, boundary_index), "wave-clear note boundary %d is phase/envelope zero" % boundary_index)


func _test_voice_pool_contract(assertions: Variant, context: Dictionary) -> void:
	var pool: Variant = AudioVoicePoolScript.new()
	(context["tree"] as SceneTree).root.add_child(pool)
	assertions.expect_equal(AudioVoicePoolScript.VOICE_COUNT, pool.voice_count(), "voice pool contains exactly 16 players")
	assertions.expect_equal(AudioVoicePoolScript.VOICE_COUNT, pool.get_child_count(), "voice pool never allocates an extra child")

	var active: Array[bool] = []
	var started: Array[int] = []
	for voice_index: int in range(AudioVoicePoolScript.VOICE_COUNT):
		active.append(true)
		started.append(1_000 + voice_index)
	started[4] = 100
	started[9] = 100
	assertions.expect_equal(4, AudioVoicePoolScript.select_voice_index(active, started), "oldest tie steals the lowest index")
	active[7] = false
	assertions.expect_equal(7, AudioVoicePoolScript.select_voice_index(active, started), "free voice is preferred before stealing")

	var selected_index: int = pool.play_stream(AudioFactoryScript.legendary_prealert(), 0.5, 0.4)
	assertions.expect_equal(0, selected_index, "first sound uses lowest free voice")
	assertions.expect_float(0.2, pool.voice(selected_index).volume_linear, "final gain is master times sfx")
	assertions.expect_equal(1, pool.active_voice_count(), "started voice is tracked as active")
	pool.stop_all()
	assertions.expect_equal(0, pool.active_voice_count(), "stop_all releases every voice")
	(context["tree"] as SceneTree).root.remove_child(pool)
	pool.free()


func _decode_s16(data: PackedByteArray, sample_index: int) -> int:
	var byte_offset: int = sample_index * 2
	var value: int = int(data[byte_offset]) | (int(data[byte_offset + 1]) << 8)
	return value - 65_536 if value >= 32_768 else value
