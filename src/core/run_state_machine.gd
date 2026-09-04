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
				GameTypes.RunPhase.LEVEL_UP,
				GameTypes.RunPhase.CHEST_REWARD,
				GameTypes.RunPhase.RESULT,
				GameTypes.RunPhase.FAILED,
			]
		GameTypes.RunPhase.LEVEL_UP:
			return to_phase in [
				GameTypes.RunPhase.COMBAT,
				GameTypes.RunPhase.CHEST_REWARD,
				GameTypes.RunPhase.RESULT,
				GameTypes.RunPhase.FAILED,
			]
		GameTypes.RunPhase.CHEST_REWARD:
			return to_phase in [
				GameTypes.RunPhase.COMBAT,
				GameTypes.RunPhase.LEVEL_UP,
				GameTypes.RunPhase.RESULT,
				GameTypes.RunPhase.FAILED,
			]
		GameTypes.RunPhase.RESULT, GameTypes.RunPhase.FAILED:
			return to_phase in [GameTypes.RunPhase.COMBAT, GameTypes.RunPhase.TITLE]
	return false


static func can_transition_state(
	state: RunState,
	to_phase: GameTypes.RunPhase,
) -> bool:
	if state == null or not can_transition(state.phase, to_phase):
		return false
	if to_phase == GameTypes.RunPhase.RESULT:
		return state.boss_defeated
	if to_phase == GameTypes.RunPhase.FAILED:
		return state.current_hp <= 0.0 and not state.boss_defeated
	if to_phase == GameTypes.RunPhase.LEVEL_UP:
		return state.pending_level_ups > 0 and state.active_level_offer != null
	if to_phase == GameTypes.RunPhase.CHEST_REWARD:
		return (
			state.pending_level_ups <= 0
			and state.active_level_offer == null
			and state.active_chest_outcome != null
		)
	if to_phase == GameTypes.RunPhase.COMBAT and state.phase in [
		GameTypes.RunPhase.LEVEL_UP,
		GameTypes.RunPhase.CHEST_REWARD,
	]:
		return (
			state.pending_level_ups <= 0
			and state.active_level_offer == null
			and state.active_chest_outcome == null
		)
	return true


static func transition(state: RunState, to_phase: GameTypes.RunPhase) -> bool:
	if not can_transition_state(state, to_phase):
		return false
	state.phase = to_phase
	return true


static func resolve_terminal(
	state: RunState,
	player_dead: bool,
	boss_defeated: bool,
) -> GameTypes.RunPhase:
	if state == null:
		return GameTypes.RunPhase.BOOT
	if boss_defeated:
		state.boss_defeated = true
		state.phase = GameTypes.RunPhase.RESULT
	elif player_dead:
		state.current_hp = 0.0
		state.phase = GameTypes.RunPhase.FAILED
	return state.phase


static func grant_level_up_resume_invulnerability(state: RunState, ticks: int = 45) -> void:
	if state == null or ticks <= 0:
		return
	state.level_up_invulnerable_until_tick = maxi(
		state.level_up_invulnerable_until_tick,
		state.combat_tick + ticks,
	)
