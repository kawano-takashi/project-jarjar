class_name RewardRevealController
extends RefCounted


signal reward_revealed(reward: RewardRoll)
signal all_revealed
signal vibration_requested(weak_magnitude: float, strong_magnitude: float, duration: float)
signal prealert_started(rarity: int)

const NORMAL_INTERVAL_SECONDS: float = 0.35
const FAST_INTERVAL_SECONDS: float = 0.0875
const PREALERT_DURATION_SECONDS: float = 0.75

enum PrealertMode { NONE, INDIVIDUAL, AGGREGATE }

var _state: RunState = null
var _ordered_rewards: Array[RewardRoll] = []
var _reward_open_accumulator: float = 0.0
var _fast_open: bool = false
var _paused: bool = false
var _prealert_mode: PrealertMode = PrealertMode.NONE
var _prealert_remaining: float = 0.0
var _prealert_elapsed: float = 0.0
var _prealert_target: RewardRoll = null
var _prealert_reward_ids: PackedStringArray = PackedStringArray()
var _last_revealed: RewardRoll = null
var _completion_emitted: bool = false

var _reduce_motion: bool = false
var _reduce_flashes: bool = false
var _controller_vibration: bool = true
var _vibration_request_count: int = 0
var _last_vibration_weak: float = 0.0
var _last_vibration_strong: float = 0.0
var _last_vibration_duration: float = 0.0


func initialize(state: RunState) -> void:
	_state = state
	_ordered_rewards.clear()
	if _state != null:
		_ordered_rewards.assign(_state.unopened_rewards)
	_ordered_rewards.sort_custom(_reward_precedes)
	_reward_open_accumulator = 0.0
	_fast_open = false
	_paused = false
	_clear_prealert()
	_last_revealed = _last_revealed_reward()
	_completion_emitted = false
	_emit_completion_if_ready()


func configure_accessibility(
	reduce_motion: bool,
	reduce_flashes: bool,
	controller_vibration: bool,
) -> void:
	_reduce_motion = reduce_motion
	_reduce_flashes = reduce_flashes
	_controller_vibration = controller_vibration


func set_paused(paused: bool) -> void:
	_paused = paused


func set_fast_open(enabled: bool) -> void:
	_fast_open = enabled and not _paused and not is_prealert_active()


func tick(delta: float) -> void:
	if _state == null or _paused or delta <= 0.0 or is_complete():
		return
	if is_prealert_active():
		_advance_prealert(delta)
		return

	var interval: float = FAST_INTERVAL_SECONDS if _fast_open else NORMAL_INTERVAL_SECONDS
	var timer_result: Dictionary = TimerMath.consume_repeating(
		_reward_open_accumulator,
		interval,
		delta,
		16,
	)
	_reward_open_accumulator = float(timer_result["accumulator"])
	var event_count: int = int(timer_result["events"])
	for _event_index: int in range(event_count):
		var reward: RewardRoll = next_unrevealed_reward()
		if reward == null:
			break
		if is_high_rarity(reward):
			_start_individual_prealert(reward)
			break
		_reveal_reward(reward)
	_emit_completion_if_ready()


func request_open_all() -> void:
	if _state == null or _paused or is_complete():
		return
	_fast_open = false
	_reward_open_accumulator = 0.0
	var high_rewards: Array[RewardRoll] = []
	for reward: RewardRoll in _ordered_rewards:
		if not reward.revealed and is_high_rarity(reward):
			high_rewards.append(reward)
	if high_rewards.is_empty():
		_reveal_all_in_order()
		return
	_start_aggregate_prealert(high_rewards)


func ordered_rewards() -> Array[RewardRoll]:
	return _ordered_rewards.duplicate()


func revealed_rewards() -> Array[RewardRoll]:
	var result: Array[RewardRoll] = []
	for reward: RewardRoll in _ordered_rewards:
		if reward.revealed:
			result.append(reward)
	return result


func next_unrevealed_reward() -> RewardRoll:
	for reward: RewardRoll in _ordered_rewards:
		if not reward.revealed:
			return reward
	return null


func last_revealed_reward() -> RewardRoll:
	return _last_revealed


func unrevealed_count() -> int:
	var count: int = 0
	for reward: RewardRoll in _ordered_rewards:
		if not reward.revealed:
			count += 1
	return count


func is_complete() -> bool:
	return unrevealed_count() == 0 and not is_prealert_active()


func is_fast_open() -> bool:
	return _fast_open


func is_paused() -> bool:
	return _paused


func is_prealert_active() -> bool:
	return _prealert_mode != PrealertMode.NONE


func is_aggregate_prealert() -> bool:
	return _prealert_mode == PrealertMode.AGGREGATE


func prealert_reward_ids() -> PackedStringArray:
	return _prealert_reward_ids.duplicate()


func prealert_progress() -> float:
	if not is_prealert_active():
		return 0.0
	return clampf(_prealert_elapsed / PREALERT_DURATION_SECONDS, 0.0, 1.0)


func presentation_state() -> Dictionary:
	var progress: float = prealert_progress()
	var shake_offset: float = 0.0
	var scale_multiplier: float = 1.0
	if is_prealert_active():
		if _reduce_motion:
			scale_multiplier = 1.0 + 0.02 * (0.5 - 0.5 * cos(progress * TAU * 3.0))
		else:
			shake_offset = sin(_prealert_elapsed * TAU * 10.0) * 8.0
	var stage_light_step: int = 0
	var outline_thickness: int = 3
	if is_prealert_active():
		if _reduce_flashes:
			outline_thickness = 3 + mini(3, int(floor(progress * 4.0))) * 2
		else:
			stage_light_step = 1 + mini(2, int(floor(progress * 3.0)))
	return {
		"fast_open": _fast_open,
		"paused": _paused,
		"complete": is_complete(),
		"unrevealed_count": unrevealed_count(),
		"prealert_active": is_prealert_active(),
		"aggregate_prealert": is_aggregate_prealert(),
		"prealert_progress": progress,
		"prealert_reward_ids": prealert_reward_ids(),
		"shake_offset": shake_offset,
		"scale_multiplier": scale_multiplier,
		"stage_light_step": stage_light_step,
		"outline_thickness": outline_thickness,
		"reduce_motion": _reduce_motion,
		"reduce_flashes": _reduce_flashes,
		"controller_vibration": _controller_vibration,
		"vibration_request_count": _vibration_request_count,
		"last_vibration_weak": _last_vibration_weak,
		"last_vibration_strong": _last_vibration_strong,
		"last_vibration_duration": _last_vibration_duration,
	}


static func is_high_rarity(reward: RewardRoll) -> bool:
	return (
		reward != null
		and reward.rarity_for_presentation >= GameTypes.Rarity.EPIC
		and reward.rarity_for_presentation <= GameTypes.Rarity.LEGENDARY
	)


static func rarity_label(reward: RewardRoll) -> String:
	if reward == null:
		return ""
	match reward.rarity_for_presentation:
		-1:
			return "スキル"
		GameTypes.Rarity.COMMON:
			return "COMMON"
		GameTypes.Rarity.RARE:
			return "RARE"
		GameTypes.Rarity.EPIC:
			return "EPIC"
		GameTypes.Rarity.LEGENDARY:
			return "LEGENDARY"
	return "不明"


static func outline_token(reward: RewardRoll) -> String:
	if reward == null:
		return ""
	match reward.rarity_for_presentation:
		-1:
			return "○"
		GameTypes.Rarity.COMMON:
			return "□"
		GameTypes.Rarity.RARE:
			return "◇"
		GameTypes.Rarity.EPIC:
			return "⬡"
		GameTypes.Rarity.LEGENDARY:
			return "✦"
	return "?"


func _advance_prealert(delta: float) -> void:
	_prealert_elapsed = minf(
		PREALERT_DURATION_SECONDS,
		_prealert_elapsed + delta,
	)
	_prealert_remaining = TimerMath.countdown(_prealert_remaining, delta)
	if _prealert_remaining > 0.0:
		return
	if _prealert_mode == PrealertMode.INDIVIDUAL:
		var target: RewardRoll = _prealert_target
		_clear_prealert()
		_reveal_reward(target)
	else:
		_clear_prealert()
		_reveal_all_in_order()
	_reward_open_accumulator = 0.0
	_emit_completion_if_ready()


func _start_individual_prealert(reward: RewardRoll) -> void:
	_reward_open_accumulator = 0.0
	_prealert_mode = PrealertMode.INDIVIDUAL
	_prealert_remaining = PREALERT_DURATION_SECONDS
	_prealert_elapsed = 0.0
	_prealert_target = reward
	_prealert_reward_ids = PackedStringArray([reward.reward_id])
	prealert_started.emit(reward.rarity_for_presentation)
	_request_vibration_for_rarity(reward.rarity_for_presentation)


func _start_aggregate_prealert(rewards: Array[RewardRoll]) -> void:
	_prealert_mode = PrealertMode.AGGREGATE
	_prealert_remaining = PREALERT_DURATION_SECONDS
	_prealert_elapsed = 0.0
	_prealert_target = null
	_prealert_reward_ids = PackedStringArray()
	var highest_rarity: int = GameTypes.Rarity.EPIC
	for reward: RewardRoll in rewards:
		_prealert_reward_ids.append(reward.reward_id)
		highest_rarity = maxi(highest_rarity, reward.rarity_for_presentation)
	prealert_started.emit(highest_rarity)
	_request_vibration_for_rarity(highest_rarity)


func _request_vibration_for_rarity(rarity: int) -> void:
	if not _controller_vibration:
		return
	var weak_magnitude: float = 0.30
	var strong_magnitude: float = 0.50
	var duration: float = 0.30
	if rarity == GameTypes.Rarity.LEGENDARY:
		weak_magnitude = 0.50
		strong_magnitude = 0.80
		duration = 0.50
	_vibration_request_count += 1
	_last_vibration_weak = weak_magnitude
	_last_vibration_strong = strong_magnitude
	_last_vibration_duration = duration
	vibration_requested.emit(weak_magnitude, strong_magnitude, duration)


func _reveal_all_in_order() -> void:
	for reward: RewardRoll in _ordered_rewards:
		if not reward.revealed:
			_reveal_reward(reward)
	_emit_completion_if_ready()


func _reveal_reward(reward: RewardRoll) -> void:
	if reward == null or reward.revealed:
		return
	reward.revealed = true
	_last_revealed = reward
	reward_revealed.emit(reward)


func _emit_completion_if_ready() -> void:
	if _completion_emitted or not is_complete():
		return
	_completion_emitted = true
	all_revealed.emit()


func _clear_prealert() -> void:
	_prealert_mode = PrealertMode.NONE
	_prealert_remaining = 0.0
	_prealert_elapsed = 0.0
	_prealert_target = null
	_prealert_reward_ids = PackedStringArray()


func _last_revealed_reward() -> RewardRoll:
	var result: RewardRoll = null
	for reward: RewardRoll in _ordered_rewards:
		if reward.revealed:
			result = reward
	return result


static func _reward_precedes(left: RewardRoll, right: RewardRoll) -> bool:
	if left.acquired_tick != right.acquired_tick:
		return left.acquired_tick < right.acquired_tick
	return left.reward_id < right.reward_id
