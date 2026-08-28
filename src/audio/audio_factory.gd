class_name AudioFactory
extends RefCounted


const SAMPLE_RATE: int = 44_100
const MAX_AMPLITUDE: float = 0.65
const ENVELOPE_SECONDS: float = 0.005
const PCM16_POSITIVE_MAX: float = 32_767.0

const PICKUP_FREQUENCY_HZ: float = 880.0
const PICKUP_DURATION_SECONDS: float = 0.05
const NORMAL_OPEN_FREQUENCY_HZ: float = 523.0
const NORMAL_OPEN_DURATION_SECONDS: float = 0.08
const RARE_OPEN_FREQUENCY_HZ: float = 659.0
const RARE_OPEN_DURATION_SECONDS: float = 0.12
const EPIC_PREALERT_START_HZ: float = 220.0
const EPIC_PREALERT_END_HZ: float = 880.0
const EPIC_PREALERT_DURATION_SECONDS: float = 0.55
const LEGENDARY_PREALERT_START_HZ: float = 330.0
const LEGENDARY_PREALERT_END_HZ: float = 1_320.0
const LEGENDARY_PREALERT_DURATION_SECONDS: float = 0.75
const WAVE_CLEAR_FREQUENCIES_HZ: Array[float] = [523.0, 659.0, 784.0]
const WAVE_CLEAR_NOTE_DURATION_SECONDS: float = 0.12
const FUSION_START_HZ: float = 392.0
const FUSION_END_HZ: float = 784.0
const FUSION_DURATION_SECONDS: float = 0.30


static func pickup() -> AudioStreamWAV:
	return create_tone(PICKUP_FREQUENCY_HZ, PICKUP_DURATION_SECONDS)


static func normal_open() -> AudioStreamWAV:
	return create_tone(NORMAL_OPEN_FREQUENCY_HZ, NORMAL_OPEN_DURATION_SECONDS)


static func rare_open() -> AudioStreamWAV:
	return create_tone(RARE_OPEN_FREQUENCY_HZ, RARE_OPEN_DURATION_SECONDS)


static func epic_prealert() -> AudioStreamWAV:
	return create_sweep(
		EPIC_PREALERT_START_HZ,
		EPIC_PREALERT_END_HZ,
		EPIC_PREALERT_DURATION_SECONDS,
	)


static func legendary_prealert() -> AudioStreamWAV:
	return create_sweep(
		LEGENDARY_PREALERT_START_HZ,
		LEGENDARY_PREALERT_END_HZ,
		LEGENDARY_PREALERT_DURATION_SECONDS,
	)


static func wave_clear() -> AudioStreamWAV:
	return create_tone_sequence(
		WAVE_CLEAR_FREQUENCIES_HZ,
		WAVE_CLEAR_NOTE_DURATION_SECONDS,
	)


static func fusion() -> AudioStreamWAV:
	return create_sweep(FUSION_START_HZ, FUSION_END_HZ, FUSION_DURATION_SECONDS)


static func create_pickup() -> AudioStreamWAV:
	return pickup()


static func create_normal_open() -> AudioStreamWAV:
	return normal_open()


static func create_rare_open() -> AudioStreamWAV:
	return rare_open()


static func create_epic_prealert() -> AudioStreamWAV:
	return epic_prealert()


static func create_legendary_prealert() -> AudioStreamWAV:
	return legendary_prealert()


static func create_wave_clear() -> AudioStreamWAV:
	return wave_clear()


static func create_fusion() -> AudioStreamWAV:
	return fusion()


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
