extends RefCounted

const BotAction = preload("res://dev/bot/bot_action.gd")
const BotObservation = preload("res://dev/bot/bot_observation.gd")
const BotKnowledge = preload("res://dev/bot/bot_knowledge.gd")
const BotController = preload("res://dev/bot/bot_controller.gd")
const BotObserver = preload("res://dev/bot/bot_observer.gd")

const MAX_COMBAT_TICKS: int = 30 * 60 * RunState.TICKS_PER_SECOND

var simulation: RecordedSimulation
var view := ArenaView.new()
var controller: BotController
var observer := BotObserver.new()
var last_action: BotAction = null
var last_observation: BotObservation = null
var result: StringName = &""
var error_message: String = ""
var action_digest: int = 0
var action_count: int = 0
var _started_usec: int = 0
var _finished_usec: int = 0
var observation_usec: int = 0
var decision_usec: int = 0
var combat_usec: int = 0


class RecordedSimulation extends CombatSimulation:
	## Accepted damage capped at the remaining HP, before recovery; reporting only.
	var total_damage_taken: float = 0.0

	func _apply_raw_player_damage(raw_damage: float) -> void:
		var hp_before: float = state.current_hp
		super(raw_damage)
		if state.current_hp < hp_before:
			total_damage_taken += minf(hp_before, raw_damage)


func initialize(catalog: DefinitionCatalog, seed_value: int, viewport_size: Vector2i) -> bool:
	var state: RunState = RunStateFactory.create(seed_value, catalog)
	if state == null:
		fail("run_initialization")
		return false
	simulation = RecordedSimulation.new()
	simulation.initialize(state, catalog)
	view.viewport_size = viewport_size
	view.reset(simulation.player_position)
	controller = BotController.new(BotKnowledge.new(catalog))
	_started_usec = Time.get_ticks_usec()
	return true


func advance() -> bool:
	if not result.is_empty():
		return false
	if simulation.state.combat_tick >= MAX_COMBAT_TICKS:
		_finish(&"timeout")
		return false
	var observe_started: int = Time.get_ticks_usec()
	last_observation = observer.capture(simulation, view)
	var decide_started: int = Time.get_ticks_usec()
	observation_usec += decide_started - observe_started
	last_action = controller.decide(last_observation)
	var combat_started: int = Time.get_ticks_usec()
	decision_usec += combat_started - decide_started
	if not last_action.is_valid_for(last_observation):
		fail("invalid_action")
		return false
	var succeeded: bool = false
	match last_action.kind:
		BotAction.Kind.MOVE:
			succeeded = simulation.advance_tick(view.screen_to_world_input(last_action.move_input))
			if succeeded:
				view.advance(simulation.player_position, CombatSimulation.FIXED_DELTA_SECONDS)
		BotAction.Kind.CHOOSE_UPGRADE:
			var queued_before: int = simulation.state.pending_level_ups
			succeeded = simulation.apply_upgrade_choice(last_action.choice_index)
			if succeeded and simulation.state.pending_level_ups >= queued_before:
				fail("upgrade_did_not_advance")
				return false
		BotAction.Kind.CONTINUE_CHEST:
			var opened_before: int = simulation.state.opened_chests
			succeeded = simulation.skip_chest_animation()
			if succeeded and simulation.state.opened_chests != opened_before + 1:
				fail("chest_did_not_advance")
				return false
	if not succeeded:
		fail("action_rejected")
		return false
	if last_action.kind == BotAction.Kind.MOVE and simulation.state.combat_tick != last_observation.tick + 1:
		fail("combat_clock_did_not_advance")
		return false
	combat_usec += Time.get_ticks_usec() - combat_started
	action_digest = hash([action_digest, last_observation.tick, last_action.kind, last_action.move_input, last_action.choice_index])
	action_count += 1
	if simulation.state.phase == GameTypes.RunPhase.RESULT:
		_finish(&"won")
	elif simulation.state.phase == GameTypes.RunPhase.FAILED:
		_finish(&"lost")
	return true


func fail(message: String) -> void:
	error_message = message
	_finish(&"error")


func summary() -> Dictionary:
	var state: RunState = simulation.state
	var elapsed_usec: int = (_finished_usec if _finished_usec > 0 else Time.get_ticks_usec()) - _started_usec
	var wall_seconds: float = float(maxi(1, elapsed_usec)) / 1_000_000.0
	var build: PackedStringArray = []
	for weapon: RunWeapon in state.weapons:
		build.append("%s:%d" % [weapon.weapon_id, weapon.level])
	for passive: RunPassive in state.passives:
		build.append("%s:%d" % [passive.passive_id, passive.level])
	return {
		"seed": state.run_seed, "result": result, "tick": state.combat_tick,
		"game_seconds": state.elapsed_seconds(), "wall_seconds": snappedf(wall_seconds, 0.001),
		"speedup": snappedf(state.elapsed_seconds() / wall_seconds, 0.01),
		"damage_taken": simulation.total_damage_taken, "hp": state.current_hp, "level": state.level,
		"kills": state.total_kills, "build": build, "action_digest": action_digest, "actions": action_count,
		"view": "%dx%d" % [view.viewport_size.x, view.viewport_size.y], "error": error_message,
		"observation_ms": observation_usec / 1000.0, "decision_ms": decision_usec / 1000.0, "combat_ms": combat_usec / 1000.0,
	}


func _finish(outcome: StringName) -> void:
	result = outcome
	_finished_usec = Time.get_ticks_usec()
