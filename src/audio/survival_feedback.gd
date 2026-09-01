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
	&"enemy_kill": Vector3(0.05, 0.02, 0.025),
	&"elite_kill": Vector3(0.15, 0.08, 0.09),
	&"boss_charge": Vector3(0.08, 0.12, 0.12),
	&"boss_defeated": Vector3(0.24, 0.32, 0.38),
	&"player_defeated": Vector3(0.18, 0.26, 0.24),
}

const PRIORITY_BY_EVENT: Dictionary[StringName, int] = {
	&"xp_pickup": AudioVoicePool.Priority.AMBIENT,
	&"enemy_hit": AudioVoicePool.Priority.NORMAL,
	&"enemy_kill": AudioVoicePool.Priority.NORMAL,
	&"elite_kill": AudioVoicePool.Priority.IMPORTANT,
	&"important_spawn": AudioVoicePool.Priority.IMPORTANT,
	&"boss_spawn": AudioVoicePool.Priority.IMPORTANT,
	&"boss_charge": AudioVoicePool.Priority.IMPORTANT,
	&"boss_volley": AudioVoicePool.Priority.IMPORTANT,
	&"boss_defeated": AudioVoicePool.Priority.TERMINAL,
	&"player_defeated": AudioVoicePool.Priority.TERMINAL,
	&"boss_phase": AudioVoicePool.Priority.IMPORTANT,
	&"chain_milestone": AudioVoicePool.Priority.IMPORTANT,
}

const COOLDOWN_USEC_BY_EVENT: Dictionary[StringName, int] = {
	&"xp_pickup": 20_000,
	&"enemy_hit": 25_000,
	&"enemy_kill": 35_000,
	&"boss_charge": 100_000,
	&"boss_volley": 80_000,
}

var _voice_pool: AudioVoicePool = null
var _settings_store: Variant = null
var _streams: Dictionary[StringName, AudioStream] = {}
var _last_played_usec_by_group: Dictionary[StringName, int] = {}
var admitted_cue_count: int = 0
var suppressed_cue_count: int = 0


func initialize(voice_pool: AudioVoicePool, settings_store: Variant) -> void:
	_voice_pool = voice_pool
	_settings_store = settings_store
	_streams = AudioFactory.build_event_streams()
	reset_run_metrics()


func reset_run_metrics() -> void:
	admitted_cue_count = 0
	suppressed_cue_count = 0
	_last_played_usec_by_group.clear()


func play(
	event_id: StringName,
	priority: int = -1,
	group: StringName = &"",
	pitch_scale: float = 1.0,
	force: bool = false,
) -> bool:
	var stream: AudioStream = _streams.get(event_id) as AudioStream
	if stream == null:
		return false
	var resolved_group: StringName = event_id if group.is_empty() else group
	var now_usec: int = Time.get_ticks_usec()
	var cooldown_usec: int = int(COOLDOWN_USEC_BY_EVENT.get(event_id, 0))
	if (
		not force
		and cooldown_usec > 0
		and now_usec - int(_last_played_usec_by_group.get(resolved_group, -cooldown_usec))
		< cooldown_usec
	):
		suppressed_cue_count += 1
		return false
	_last_played_usec_by_group[resolved_group] = now_usec
	var master_volume: float = 1.0
	var sfx_volume: float = 0.9
	if _settings_store != null:
		master_volume = float(_settings_store.master_volume)
		sfx_volume = float(_settings_store.sfx_volume)
	if _voice_pool != null:
		var resolved_priority: int = int(PRIORITY_BY_EVENT.get(
			event_id,
			AudioVoicePool.Priority.NORMAL,
		)) if priority < 0 else priority
		var voice_index: int = _voice_pool.play_sfx(
			stream,
			master_volume,
			sfx_volume,
			resolved_priority,
			resolved_group,
			pitch_scale,
		)
		if voice_index < 0:
			suppressed_cue_count += 1
			return false
		admitted_cue_count += 1
	_play_vibration(event_id)
	return true


func play_presentation_event(event: CombatPresentationEvent) -> bool:
	if event == null:
		return false
	var event_id: StringName = event.resolved_event_id()
	if (
		event.kind == CombatPresentationEvent.Kind.ENEMY_KILLED
		and event.enemy_visual_kind == CombatSnapshot.EnemyVisualKind.ELITE
	):
		event_id = &"elite_kill"
	if event_id.is_empty():
		return false
	var group: StringName = event_id
	if not event.source_effect_id.is_empty():
		group = StringName("%s:%s" % [event_id, event.source_effect_id])
	var lineage_pitch_offset: float = 0.0
	if not event.source_effect_id.is_empty():
		lineage_pitch_offset = float(absi(String(event.source_effect_id).hash()) % 7 - 3) * 0.025
	var count_pitch_offset: float = minf(0.15, 0.025 * float(maxi(0, event.count - 1)))
	var force: bool = event.priority == CombatPresentationEvent.Priority.TERMINAL
	return play(
		event_id,
		int(event.priority),
		group,
		1.0 + lineage_pitch_offset + count_pitch_offset,
		force,
	)


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
