class_name AudioVoicePool
extends Node


signal voice_started(voice_index: int, started_usec: int, gain_linear: float)

const VOICE_COUNT: int = 16
const CRITICAL_VOICE_START: int = 0
const CRITICAL_VOICE_COUNT: int = 4
const COMBAT_VOICE_START: int = CRITICAL_VOICE_START + CRITICAL_VOICE_COUNT
const COMBAT_VOICE_COUNT: int = 8
const PICKUP_VOICE_START: int = COMBAT_VOICE_START + COMBAT_VOICE_COUNT
const PICKUP_VOICE_COUNT: int = 4
const ADMISSION_WINDOW_USEC: int = 1_000_000
const MAX_CUES_PER_WINDOW: int = AudioCueAdmission.MAX_CUES_PER_WINDOW
const MAX_NONCRITICAL_CUES_PER_WINDOW: int = (
	AudioCueAdmission.MAX_NONCRITICAL_CUES_PER_WINDOW
)
const MAX_PICKUP_CUES_PER_WINDOW: int = AudioCueAdmission.MAX_PICKUP_CUES_PER_WINDOW

enum Priority {
	AMBIENT,
	NORMAL,
	IMPORTANT,
	TERMINAL,
}

var steal_count: int = 0
var last_stolen_index: int = -1
var admission_drop_count: int = 0

var _voices: Array[AudioStreamPlayer] = []
var _voice_active: Array[bool] = []
var _voice_started_usec: Array[int] = []
var _voice_priorities: PackedInt32Array = PackedInt32Array()
var _voice_groups: Array[StringName] = []
var _cue_admission: AudioCueAdmission = AudioCueAdmission.new()


func _init() -> void:
	for voice_index: int in range(VOICE_COUNT):
		var player := AudioStreamPlayer.new()
		player.name = "Voice%02d" % voice_index
		player.bus = &"Master"
		player.max_polyphony = 1
		player.finished.connect(_on_voice_finished.bind(voice_index))
		add_child(player)
		_voices.append(player)
		_voice_active.append(false)
		_voice_started_usec.append(-1)
		_voice_priorities.append(Priority.AMBIENT)
		_voice_groups.append(&"")


func play_stream(
	stream: AudioStream,
	master_volume: float,
	sfx_volume: float,
	priority: int = Priority.NORMAL,
	group: StringName = &"",
	pitch_scale: float = 1.0,
) -> int:
	if stream == null:
		return -1
	var resolved_priority: int = clampi(priority, Priority.AMBIENT, Priority.TERMINAL)
	var voice_index: int = select_reserved_voice_index(
		_voice_active,
		_voice_started_usec,
		_voice_priorities,
		resolved_priority,
	)
	if voice_index < 0:
		admission_drop_count += 1
		return -1
	var started_usec: int = Time.get_ticks_usec()
	if not _admit_cue(started_usec, resolved_priority):
		admission_drop_count += 1
		return -1
	var player: AudioStreamPlayer = _voices[voice_index]
	if _voice_active[voice_index]:
		player.stop()
		steal_count += 1
		last_stolen_index = voice_index
	var gain_linear: float = (
		clampf(master_volume, 0.0, 1.0)
		* clampf(sfx_volume, 0.0, 1.0)
	)
	player.stream = stream
	player.volume_linear = gain_linear
	player.pitch_scale = clampf(pitch_scale, 0.5, 2.0)
	_voice_active[voice_index] = true
	_voice_started_usec[voice_index] = started_usec
	_voice_priorities[voice_index] = resolved_priority
	_voice_groups[voice_index] = group
	player.play()
	voice_started.emit(voice_index, started_usec, gain_linear)
	return voice_index


func play_sfx(
	stream: AudioStream,
	master_volume: float,
	sfx_volume: float,
	priority: int = Priority.NORMAL,
	group: StringName = &"",
	pitch_scale: float = 1.0,
) -> int:
	return play_stream(stream, master_volume, sfx_volume, priority, group, pitch_scale)


func stop_all() -> void:
	for voice_index: int in range(VOICE_COUNT):
		_voices[voice_index].stop()
		_voice_active[voice_index] = false
		_voice_started_usec[voice_index] = -1
		_voice_priorities[voice_index] = Priority.AMBIENT
		_voice_groups[voice_index] = &""
	_cue_admission.reset()


func reset_admission_metrics() -> void:
	admission_drop_count = 0
	_cue_admission.reset()


func admitted_cue_count() -> int:
	return _cue_admission.admitted_count


func voice_count() -> int:
	return _voices.size()


func active_voice_count() -> int:
	var count: int = 0
	for active: bool in _voice_active:
		if active:
			count += 1
	return count


func voice(voice_index: int) -> AudioStreamPlayer:
	if voice_index < 0 or voice_index >= _voices.size():
		return null
	return _voices[voice_index]


func voice_started_usec(voice_index: int) -> int:
	if voice_index < 0 or voice_index >= _voice_started_usec.size():
		return -1
	return _voice_started_usec[voice_index]


func is_voice_active(voice_index: int) -> bool:
	return (
		voice_index >= 0
		and voice_index < _voice_active.size()
		and _voice_active[voice_index]
	)


static func select_voice_index(
	voice_active: Array[bool],
	p_voice_started_usec: Array[int],
) -> int:
	if voice_active.is_empty() or voice_active.size() != p_voice_started_usec.size():
		return -1
	for voice_index: int in range(voice_active.size()):
		if not voice_active[voice_index]:
			return voice_index
	var oldest_index: int = 0
	var oldest_started_usec: int = p_voice_started_usec[0]
	for voice_index: int in range(1, p_voice_started_usec.size()):
		if p_voice_started_usec[voice_index] < oldest_started_usec:
			oldest_index = voice_index
			oldest_started_usec = p_voice_started_usec[voice_index]
	return oldest_index


static func select_voice_index_for_priority(
	voice_active: Array[bool],
	p_voice_started_usec: Array[int],
	voice_priorities: PackedInt32Array,
	incoming_priority: int,
) -> int:
	if (
		voice_active.is_empty()
		or voice_active.size() != p_voice_started_usec.size()
		or voice_active.size() != voice_priorities.size()
	):
		return -1
	for voice_index: int in range(voice_active.size()):
		if not voice_active[voice_index]:
			return voice_index
	var oldest_index: int = -1
	var oldest_started_usec: int = 0
	for voice_index: int in range(voice_active.size()):
		if voice_priorities[voice_index] > incoming_priority:
			continue
		if oldest_index < 0 or p_voice_started_usec[voice_index] < oldest_started_usec:
			oldest_index = voice_index
			oldest_started_usec = p_voice_started_usec[voice_index]
	return oldest_index


static func select_reserved_voice_index(
	voice_active: Array[bool],
	p_voice_started_usec: Array[int],
	voice_priorities: PackedInt32Array,
	incoming_priority: int,
) -> int:
	if (
		voice_active.size() != VOICE_COUNT
		or p_voice_started_usec.size() != VOICE_COUNT
		or voice_priorities.size() != VOICE_COUNT
	):
		return -1
	var slot_start: int = CRITICAL_VOICE_START
	var slot_count: int = CRITICAL_VOICE_COUNT
	if incoming_priority <= Priority.AMBIENT:
		slot_start = PICKUP_VOICE_START
		slot_count = PICKUP_VOICE_COUNT
	elif incoming_priority == Priority.NORMAL:
		slot_start = COMBAT_VOICE_START
		slot_count = COMBAT_VOICE_COUNT
	for voice_index: int in range(slot_start, slot_start + slot_count):
		if not voice_active[voice_index]:
			return voice_index
	var oldest_index: int = -1
	var oldest_started_usec: int = 0
	for voice_index: int in range(slot_start, slot_start + slot_count):
		if voice_priorities[voice_index] > incoming_priority:
			continue
		if oldest_index < 0 or p_voice_started_usec[voice_index] < oldest_started_usec:
			oldest_index = voice_index
			oldest_started_usec = p_voice_started_usec[voice_index]
	return oldest_index


func _admit_cue(now_usec: int, incoming_priority: int) -> bool:
	return _cue_admission.try_admit(
		now_usec,
		ADMISSION_WINDOW_USEC,
		incoming_priority,
	)


func _on_voice_finished(voice_index: int) -> void:
	if voice_index < 0 or voice_index >= VOICE_COUNT:
		return
	_voice_active[voice_index] = false
	_voice_started_usec[voice_index] = -1
	_voice_priorities[voice_index] = Priority.AMBIENT
	_voice_groups[voice_index] = &""
