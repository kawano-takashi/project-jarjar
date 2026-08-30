class_name RunStateMachine
extends RefCounted


static func can_transition(
	from_phase: GameTypes.RunPhase,
	to_phase: GameTypes.RunPhase,
) -> bool:
	match from_phase:
		GameTypes.RunPhase.BOOT:
			return to_phase == GameTypes.RunPhase.TITLE
		GameTypes.RunPhase.TITLE:
			return to_phase == GameTypes.RunPhase.COMBAT
		GameTypes.RunPhase.COMBAT:
			return to_phase in [
				GameTypes.RunPhase.REWARD_REVEAL,
				GameTypes.RunPhase.FAILED,
			]
		GameTypes.RunPhase.REWARD_REVEAL:
			return to_phase == GameTypes.RunPhase.INVENTORY
		GameTypes.RunPhase.INVENTORY:
			return to_phase in [GameTypes.RunPhase.COMBAT, GameTypes.RunPhase.RESULT]
		GameTypes.RunPhase.RESULT, GameTypes.RunPhase.FAILED:
			return to_phase in [GameTypes.RunPhase.COMBAT, GameTypes.RunPhase.TITLE]
	return false


static func transition(state: RunState, to_phase: GameTypes.RunPhase) -> bool:
	if not can_transition_state(state, to_phase):
		if OS.is_debug_build():
			assert(false, "Rejected RunPhase transition %s -> %s" % [
				GameTypes.run_phase_to_key(state.phase),
				GameTypes.run_phase_to_key(to_phase),
			])
		else:
			push_error("Rejected RunPhase transition")
		return false
	if state.phase == GameTypes.RunPhase.COMBAT:
		state.recent_damage_samples.clear()
	state.phase = to_phase
	return true


static func can_transition_state(
	state: RunState,
	to_phase: GameTypes.RunPhase,
) -> bool:
	if state == null or not can_transition(state.phase, to_phase):
		return false
	match state.phase:
		GameTypes.RunPhase.COMBAT:
			if to_phase == GameTypes.RunPhase.REWARD_REVEAL:
				return state.wave_cleared
			if to_phase == GameTypes.RunPhase.FAILED:
				return not state.wave_cleared
		GameTypes.RunPhase.REWARD_REVEAL:
			for reward: RewardRoll in state.unopened_rewards:
				if not reward.revealed:
					return false
			return true
		GameTypes.RunPhase.INVENTORY:
			if not state.overflow.is_empty() or _equipped_weapon_count(state) <= 0:
				return false
			if to_phase == GameTypes.RunPhase.COMBAT:
				return state.wave_number >= 1 and state.wave_number <= 7
			if to_phase == GameTypes.RunPhase.RESULT:
				return state.wave_number == 8
	return true


static func quota_reached(state: RunState, wave: WaveDefinition) -> bool:
	if wave.wave_number == 8:
		return state.wave_kills >= wave.kill_quota and state.boss_defeated
	return state.wave_kills >= wave.kill_quota


static func resolve_combat_tick(
	state: RunState,
	wave: WaveDefinition,
	player_dead: bool,
	delta: float,
) -> GameTypes.RunPhase:
	if state.phase != GameTypes.RunPhase.COMBAT:
		return state.phase
	if not state.wave_cleared and quota_reached(state, wave):
		state.wave_cleared = true
	state.time_remaining = TimerMath.countdown(state.time_remaining, delta)
	var timed_out: bool = state.time_remaining <= 0.0
	if player_dead or timed_out:
		var target: GameTypes.RunPhase = (
			GameTypes.RunPhase.REWARD_REVEAL
			if state.wave_cleared
			else GameTypes.RunPhase.FAILED
		)
		transition(state, target)
	return state.phase


static func _equipped_weapon_count(state: RunState) -> int:
	var count: int = 0
	for slot: GameTypes.EquipmentSlot in GameTypes.weapon_slots():
		var item: ItemInstance = state.equipped.get(slot, null) as ItemInstance
		if item != null and item.category == GameTypes.ItemCategory.WEAPON:
			count += 1
	return count
