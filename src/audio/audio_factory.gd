class_name AudioFactory
extends RefCounted


const SAMPLE_RATE: int = 44_100
const MAX_AMPLITUDE: float = 0.65
const ENVELOPE_SECONDS: float = 0.005
const PCM16_POSITIVE_MAX: float = 32_767.0

const XP_PICKUP_FREQUENCY_HZ: float = 920.0
const XP_PICKUP_DURATION_SECONDS: float = 0.035
const STOP_PICKUP_FREQUENCIES_HZ: Array[float] = [660.0, 440.0]
const LEVEL_UP_FREQUENCIES_HZ: Array[float] = [523.0, 659.0, 784.0]
const CHEST_OPEN_FREQUENCIES_HZ: Array[float] = [392.0, 523.0, 659.0]
const EVOLUTION_START_HZ: float = 330.0
const EVOLUTION_END_HZ: float = 1_320.0
const BOSS_SPAWN_START_HZ: float = 110.0
const BOSS_SPAWN_END_HZ: float = 55.0
const PLAYER_HIT_FREQUENCY_HZ: float = 145.0


static func build_event_streams() -> Dictionary[StringName, AudioStream]:
	return {
		&"xp_pickup": xp_pickup(),
		&"stop_pickup": stop_pickup(),
		&"level_up": level_up(),
		&"chest_pickup": chest_open(),
		&"chest_open": chest_open(),
		&"evolution": evolution(),
		&"boss_spawn": boss_spawn(),
		&"player_hit": player_hit(),
	}


static func xp_pickup() -> AudioStreamWAV:
	return create_tone(XP_PICKUP_FREQUENCY_HZ, XP_PICKUP_DURATION_SECONDS)


static func stop_pickup() -> AudioStreamWAV:
	return create_tone_sequence(STOP_PICKUP_FREQUENCIES_HZ, 0.07)


static func level_up() -> AudioStreamWAV:
	return create_tone_sequence(LEVEL_UP_FREQUENCIES_HZ, 0.09)


static func chest_open() -> AudioStreamWAV:
	return create_tone_sequence(CHEST_OPEN_FREQUENCIES_HZ, 0.11)


static func evolution() -> AudioStreamWAV:
	return create_sweep(EVOLUTION_START_HZ, EVOLUTION_END_HZ, 0.65)


static func boss_spawn() -> AudioStreamWAV:
	return create_sweep(BOSS_SPAWN_START_HZ, BOSS_SPAWN_END_HZ, 0.55)


static func player_hit() -> AudioStreamWAV:
	return create_tone(PLAYER_HIT_FREQUENCY_HZ, 0.09)


static func create_tone(frequency_hz: float, duration_seconds: float) -> AudioStreamWAV:
	if frequency_hz <= 0.0 or duration_seconds <= 0.0:
		return null
	return _stream_from_pcm(_generate_pcm(frequency_hz, frequency_hz, duration_seconds))


static func create_sweep(
	start_frequency_hz: float,
	end_frequency_hz: float,
	duration_seconds: float,
) -> AudioStreamWAV:
	if start_frequency_hz <= 0.0 or end_frequency_hz <= 0.0 or duration_seconds <= 0.0:
		return null
	return _stream_from_pcm(
		_generate_pcm(start_frequency_hz, end_frequency_hz, duration_seconds),
	)


static func create_tone_sequence(
	frequencies_hz: Array[float],
	note_duration_seconds: float,
) -> AudioStreamWAV:
	if frequencies_hz.is_empty() or note_duration_seconds <= 0.0:
		return null
	var data := PackedByteArray()
	for frequency_hz: float in frequencies_hz:
		if frequency_hz <= 0.0:
			return null
		data.append_array(_generate_pcm(frequency_hz, frequency_hz, note_duration_seconds))
	return _stream_from_pcm(data)


static func _generate_pcm(
	start_frequency_hz: float,
	end_frequency_hz: float,
	duration_seconds: float,
) -> PackedByteArray:
	var sample_count: int = roundi(duration_seconds * float(SAMPLE_RATE))
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for sample_index: int in range(sample_count):
		var sample_time: float = float(sample_index) / float(SAMPLE_RATE)
		var frequency_delta: float = end_frequency_hz - start_frequency_hz
		var phase: float = TAU * (
			start_frequency_hz * sample_time
			+ 0.5 * frequency_delta * sample_time * sample_time / duration_seconds
		)
		var normalized_sample: float = (
			sin(phase)
			* MAX_AMPLITUDE
			* _linear_envelope(sample_index, sample_count)
		)
		var pcm_sample: int = clampi(
			roundi(normalized_sample * PCM16_POSITIVE_MAX),
			-32_768,
			32_767,
		)
		_encode_s16_little_endian(data, sample_index * 2, pcm_sample)
	return data


static func _linear_envelope(sample_index: int, sample_count: int) -> float:
	var envelope_sample_span: float = ENVELOPE_SECONDS * float(SAMPLE_RATE)
	var attack: float = minf(1.0, float(sample_index) / envelope_sample_span)
	var samples_after: int = sample_count - 1 - sample_index
	var release: float = minf(1.0, float(samples_after) / envelope_sample_span)
	return minf(attack, release)


static func _encode_s16_little_endian(
	data: PackedByteArray,
	byte_offset: int,
	value: int,
) -> void:
	var word: int = value & 0xffff
	data[byte_offset] = word & 0xff
	data[byte_offset + 1] = (word >> 8) & 0xff


static func _stream_from_pcm(data: PackedByteArray) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.loop_begin = 0
	stream.loop_end = data.size() >> 1
	stream.data = data
	return stream
