class_name SurvivalFeedback
extends RefCounted


const VIBRATION_BY_EVENT: Dictionary[StringName, Vector3] = {
	&"xp_pickup": Vector3(0.08, 0.0, 0.025),
	&"stop_pickup": Vector3(0.16, 0.08, 0.08),
	&"level_up": Vector3(0.16, 0.10, 0.10),
	&"chest_pickup": Vector3(0.12, 0.08, 0.08),
	&"chest_open": Vector3(0.20, 0.12, 0.12),
	&"evolution": Vector3(0.28, 0.22, 0.24),
	&"boss_spawn": Vector3(0.18, 0.32, 0.30),
	&"player_hit": Vector3(0.12, 0.30, 0.16),
}

var _voice_pool: AudioVoicePool = null
var _settings_store: Variant = null
var _streams: Dictionary[StringName, AudioStream] = {}


func initialize(voice_pool: AudioVoicePool, settings_store: Variant) -> void:
	_voice_pool = voice_pool
	_settings_store = settings_store
	_streams = AudioFactory.build_event_streams()


func play(event_id: StringName) -> bool:
	var stream: AudioStream = _streams.get(event_id) as AudioStream
	if stream == null:
		return false
	var master_volume: float = 1.0
	var sfx_volume: float = 0.9
	if _settings_store != null:
		master_volume = float(_settings_store.master_volume)
		sfx_volume = float(_settings_store.sfx_volume)
	if _voice_pool != null:
		_voice_pool.play_sfx(stream, master_volume, sfx_volume)
	_play_vibration(event_id)
	return true


func event_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for event_id: StringName in _streams:
		result.append(event_id)
	result.sort()
	return result


func _play_vibration(event_id: StringName) -> void:
	if (
		_settings_store == null
		or not bool(_settings_store.controller_vibration)
		or not VIBRATION_BY_EVENT.has(event_id)
	):
		return
	var values: Vector3 = VIBRATION_BY_EVENT[event_id]
	for device_id: int in Input.get_connected_joypads():
		Input.start_joy_vibration(device_id, values.x, values.y, values.z)
