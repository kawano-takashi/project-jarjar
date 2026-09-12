class_name StageEventScheduler
extends RefCounted


var swarm_warning: SwarmWarningState = null
var boss_transition_started: bool = false

var _state: RunState
var _events: Array[StageEventOccurrence] = []
var _next_event: int = 0
var _pending: Array[StageEventOccurrence] = []
var _finished: bool = false


func initialize(state: RunState, catalog: DefinitionCatalog) -> void:
	_state = state
	_events = catalog.stage_events
	_next_event = 0
	_pending.clear()
	_finished = false
	boss_transition_started = false
	swarm_warning = null


## CombatSimulation calls this before movement and snapshots. A true result
## requests the one-time absorption; enemy creation follows in the spawn phase.
func prepare_tick(current_tick: int) -> bool:
	if _finished or boss_transition_started:
		return false
	var boss_event: StageEventOccurrence = _events.back()
	if current_tick >= boss_event.tick:
		boss_transition_started = true
		swarm_warning = null
		_pending.clear()
		_pending.append(boss_event)
		_next_event = _events.size()
		return true
	while _next_event < _events.size() and _events[_next_event].tick <= current_tick:
		_pending.append(_events[_next_event])
		_next_event += 1
	return false


func resolve_spawns(system: EnemySystem, player_position: Vector2, current_tick: int) -> Array[EnemyEntity]:
	# Also admits due events for isolated callers of the enemy spawn phase.
	prepare_tick(current_tick)
	var spawned: Array[EnemyEntity] = []
	if _finished:
		return spawned
	var occupied_this_tick: bool = swarm_warning != null or system.has_active_swarm()
	var retries: Array[StageEventOccurrence] = []
	for event: StageEventOccurrence in _pending:
		match event.kind:
			StageEventOccurrence.Kind.ELITE_ENCOUNTER:
				var elite: EnemyEntity = system.spawn_elite_encounter(event.elite_serial, player_position, current_tick)
				if elite == null:
					retries.append(event)
				else:
					spawned.append(elite)
			StageEventOccurrence.Kind.BOSS:
				var boss: EnemyEntity = system.spawn_final_boss(player_position, current_tick)
				if boss == null:
					retries.append(event)
				else:
					spawned.append(boss)
	# Important encounters reserve capacity before a warning materializes,
	# matching the combat spawn order. Existing swarms are never retired here.
	if swarm_warning != null and current_tick >= swarm_warning.spawn_tick:
		spawned.append_array(system.spawn_swarm_group(
			swarm_warning.anchor, swarm_warning.direction, current_tick,
			swarm_warning.spawn_distance, swarm_warning.hp_multiplier,
			swarm_warning.damage_multiplier,
		))
		swarm_warning = null
	for event: StageEventOccurrence in _pending:
		if event.kind == StageEventOccurrence.Kind.SWARM:
			if _try_swarm_warning(system, event.definition as SwarmEventScheduleDefinition,
					player_position, current_tick, occupied_this_tick):
				occupied_this_tick = true
	_pending = retries
	return spawned


func _try_swarm_warning(system: EnemySystem, schedule: SwarmEventScheduleDefinition,
		player_position: Vector2, current_tick: int, occupied: bool) -> bool:
	if _state.rng_streams == null:
		return false
	_state.swarm_event_attempt_count += 1
	var attempt_rng := RandomNumberGenerator.new()
	attempt_rng.seed = _state.rng_streams.swarm_event_rng.randi()
	if not WeightedSelector.chance_succeeds_with_value(schedule.spawn_chance, attempt_rng.randf()):
		return false
	_state.swarm_event_roll_success_count += 1
	if occupied:
		_state.swarm_event_skipped_busy_count += 1
		return false
	swarm_warning = system.create_swarm_warning(attempt_rng, player_position, current_tick, schedule)
	return true


func finish() -> void:
	_finished = true
	_pending.clear()
	swarm_warning = null


func shift_origin(displacement: Vector2) -> void:
	if swarm_warning != null:
		swarm_warning.anchor -= displacement
