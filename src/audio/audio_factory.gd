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
const ENEMY_HIT_START_HZ: float = 310.0
const ENEMY_HIT_END_HZ: float = 190.0
const ENEMY_KILL_FREQUENCIES_HZ: Array[float] = [330.0, 520.0]
const ELITE_KILL_FREQUENCIES_HZ: Array[float] = [220.0, 440.0, 660.0]
const BOSS_CHARGE_START_HZ: float = 72.0
const BOSS_CHARGE_END_HZ: float = 180.0
const BOSS_VOLLEY_FREQUENCY_HZ: float = 92.0
const BOSS_DEFEAT_FREQUENCIES_HZ: Array[float] = [196.0, 147.0, 98.0, 392.0]
const PLAYER_DEFEAT_START_HZ: float = 180.0
const PLAYER_DEFEAT_END_HZ: float = 52.0
const ABSORPTION_START_HZ: float = 280.0
const ABSORPTION_END_HZ: float = 90.0


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
		&"enemy_hit": enemy_hit(),
		&"enemy_kill": enemy_kill(),
		&"elite_kill": elite_kill(),
		&"important_spawn": important_spawn(),
		&"boss_charge": boss_charge(),
		&"boss_volley": boss_volley(),
		&"boss_defeated": boss_defeated(),
		&"player_defeated": player_defeated(),
		&"absorption": absorption(),
		&"boss_phase": important_spawn(),
		&"chain_milestone": elite_kill(),
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


static func enemy_hit() -> AudioStreamWAV:
	return create_sweep(ENEMY_HIT_START_HZ, ENEMY_HIT_END_HZ, 0.045)


static func enemy_kill() -> AudioStreamWAV:
	return create_tone_sequence(ENEMY_KILL_FREQUENCIES_HZ, 0.04)


static func elite_kill() -> AudioStreamWAV:
	return create_tone_sequence(ELITE_KILL_FREQUENCIES_HZ, 0.065)


static func important_spawn() -> AudioStreamWAV:
	return create_sweep(140.0, 360.0, 0.24)


static func boss_charge() -> AudioStreamWAV:
	return create_sweep(BOSS_CHARGE_START_HZ, BOSS_CHARGE_END_HZ, 0.30)


static func boss_volley() -> AudioStreamWAV:
	return create_tone(BOSS_VOLLEY_FREQUENCY_HZ, 0.12)


static func boss_defeated() -> AudioStreamWAV:
	return create_tone_sequence(BOSS_DEFEAT_FREQUENCIES_HZ, 0.11)


static func player_defeated() -> AudioStreamWAV:
	return create_sweep(PLAYER_DEFEAT_START_HZ, PLAYER_DEFEAT_END_HZ, 0.42)


static func absorption() -> AudioStreamWAV:
	return create_sweep(ABSORPTION_START_HZ, ABSORPTION_END_HZ, 0.16)


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
