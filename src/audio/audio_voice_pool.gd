class_name AudioVoicePool
extends Node


signal voice_started(voice_index: int, started_usec: int, gain_linear: float)

const VOICE_COUNT: int = 16

var steal_count: int = 0
var last_stolen_index: int = -1

var _voices: Array[AudioStreamPlayer] = []
var _voice_active: Array[bool] = []
var _voice_started_usec: Array[int] = []


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


func play_stream(
	stream: AudioStream,
	master_volume: float,
	sfx_volume: float,
) -> int:
	if stream == null:
		return -1
	var voice_index: int = select_voice_index(_voice_active, _voice_started_usec)
	if voice_index < 0:
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
	var started_usec: int = Time.get_ticks_usec()
	_voice_active[voice_index] = true
	_voice_started_usec[voice_index] = started_usec
	player.play()
	voice_started.emit(voice_index, started_usec, gain_linear)
	return voice_index


func play_sfx(
	stream: AudioStream,
	master_volume: float,
	sfx_volume: float,
) -> int:
	return play_stream(stream, master_volume, sfx_volume)


func stop_all() -> void:
	for voice_index: int in range(VOICE_COUNT):
		_voices[voice_index].stop()
		_voice_active[voice_index] = false
		_voice_started_usec[voice_index] = -1


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


func _on_voice_finished(voice_index: int) -> void:
	if voice_index < 0 or voice_index >= VOICE_COUNT:
		return
	_voice_active[voice_index] = false
	_voice_started_usec[voice_index] = -1
