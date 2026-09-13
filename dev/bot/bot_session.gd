extends RefCounted

const BotAction = preload("res://dev/bot/bot_action.gd")
const BotObservation = preload("res://dev/bot/bot_observation.gd")
const BotKnowledge = preload("res://dev/bot/bot_knowledge.gd")
const BotController = preload("res://dev/bot/bot_controller.gd")
const BotObserver = preload("res://dev/bot/bot_observer.gd")

const RecordedSimulation = preload("res://dev/bot/recorded_simulation.gd")
const BotProfile = preload("res://dev/bot/bot_profile.gd")

const MAX_COMBAT_TICKS: int = 30 * 60 * RunState.TICKS_PER_SECOND

var profile: BotProfile = null
var simulation: RecordedSimulation
var view := ArenaView.new()
var controller: BotController
var observer: BotObserver
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
var first_evolution_tick: int = -1
var build_complete_tick: int = -1
var evolution_ready_tick: int = -1
var chest_collection_ticks: PackedInt32Array = []
var _last_report_damage: float = 0.0
var _last_report_kills: int = 0


func initialize(catalog: DefinitionCatalog, seed_value: int, viewport_size: Vector2i, detailed_profile: bool = false, evolution_after_tick: int = 0) -> bool:
	if not preload("res://dev/bot/native_loader.gd").ensure_loaded():
		fail(preload("res://dev/bot/native_loader.gd").error_message)
		return false
	var state: RunState = RunStateFactory.create(seed_value, catalog)
	if state == null:
		fail("run_initialization")
		return false
	if detailed_profile:
		profile = BotProfile.new()
	simulation = profile.create_simulation() if profile != null else RecordedSimulation.new()
	simulation.set_viewport_size(viewport_size)
	simulation.initialize(state, catalog)
	view = simulation.view
	var knowledge := BotKnowledge.new(catalog)
	controller = profile.create_controller(knowledge) if profile != null else BotController.new(knowledge)
	controller.evolution_after_tick = evolution_after_tick
	observer = profile.create_observer() if profile != null else BotObserver.new()
	chest_collection_ticks.resize(catalog.elite_spawn_ticks.size())
	chest_collection_ticks.fill(-1)
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
	if simulation.recording_enabled:
		_record_progress()
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
		"first_evolution_tick": first_evolution_tick, "build_complete_tick": build_complete_tick,
		"evolution_ready_tick": evolution_ready_tick,
		"elite_kill_ticks": state.elite_kill_ticks.duplicate(), "chest_collection_ticks": chest_collection_ticks.duplicate(),
		"damage_by_source": simulation.damage_by_source.duplicate(), "fatal_hit": simulation.fatal_hit.duplicate(),
		"uncollected_xp": simulation.xp_pickup_pool.total_value(), "boss_hp": state.boss_hp,
		"evolution_after_tick": controller.evolution_after_tick,
		"observation_ms": observation_usec / 1000.0, "decision_ms": decision_usec / 1000.0, "combat_ms": combat_usec / 1000.0,
	}


func _record_progress() -> void:
	var state: RunState = simulation.state
	if first_evolution_tick < 0 and state.evolution_count > 0:
		first_evolution_tick = state.combat_tick
	if build_complete_tick < 0 and state.build_maxed:
		build_complete_tick = state.combat_tick
	if evolution_ready_tick < 0:
		for weapon: RunWeapon in state.weapons:
			var evolution: EvolutionDefinition = simulation.catalog.evolutions.get(weapon.lineage_id)
			if not weapon.evolved and evolution != null and weapon.level == simulation.catalog.weapon(weapon.weapon_id).max_level and state.passive_level(evolution.passive_id) > 0:
				evolution_ready_tick = state.combat_tick
				break
	for source: int in state.pending_chest_sources:
		if source >= 0 and source < chest_collection_ticks.size() and chest_collection_ticks[source] < 0:
			chest_collection_ticks[source] = state.combat_tick


## Reporting reads real state only after an action; none of these values enter observations.
func progress_report() -> Dictionary:
	var state: RunState = simulation.state
	var enemies: Dictionary[StringName, int] = {}
	for enemy: EnemyEntity in simulation.enemy_system.enemy_store.entities:
		var id: StringName = enemy.definition.enemy_id
		enemies[id] = enemies.get(id, 0) + 1
	var result_row: Dictionary = {
		"seed": state.run_seed, "tick": state.combat_tick, "hp": state.current_hp, "level": state.level,
		"damage": simulation.total_damage_taken - _last_report_damage,
		"kills": state.total_kills - _last_report_kills, "enemies": enemies,
		"uncollected_xp": simulation.xp_pickup_pool.total_value(), "evolutions": state.evolution_count,
		"build": summary().build, "damage_by_source": simulation.damage_by_source.duplicate(),
	}
	_last_report_damage = simulation.total_damage_taken
	_last_report_kills = state.total_kills
	return result_row


func _finish(outcome: StringName) -> void:
	result = outcome
	_finished_usec = Time.get_ticks_usec()
