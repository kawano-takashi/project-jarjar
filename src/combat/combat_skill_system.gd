class_name CombatSkillSystem
extends RefCounted


const SKILL_ORDER: Array[StringName] = [
	&"starfall",
	&"thousand_blades",
	&"soul_chain",
	&"bell_of_retribution",
]
const SKILL_DISPLAY_NAMES: Dictionary = {
	&"starfall": "星落とし",
	&"thousand_blades": "千刃陣",
	&"soul_chain": "魂の連鎖",
	&"bell_of_retribution": "報復の鐘",
}
const ECHO_PROC_ID: StringName = &"unique:echo_gauntlet"
const CROWN_PROC_ID: StringName = &"unique:hollow_crown"
const COWARD_WAIT_SECONDS: float = 0.25
const COWARD_MOVEMENT_THRESHOLD: float = 0.05
const REPLAY_DELAY_TICKS: int = 9

var _state: RunState = null
var _catalog: DefinitionCatalog = null
var _router: CombatEventRouter = null


func initialize(
	state: RunState,
	catalog: DefinitionCatalog,
	router: CombatEventRouter,
) -> void:
	_state = state
	_catalog = catalog
	_router = router
	synchronize_unique_state()


func prepare_for_combat() -> void:
	if not _is_ready():
		return
	synchronize_unique_state()
	for skill_id: StringName in SKILL_ORDER:
		var skill_state: SkillState = _skill_state(skill_id)
		if not _is_skill_active(skill_state):
			continue
		_drain_threshold(skill_state, null)


func synchronize_unique_state() -> void:
	if _state == null:
		return
	var echo_item: ItemInstance = _equipped_item(GameTypes.EquipmentSlot.HANDS)
	if echo_item == null or echo_item.unique_id != &"echo_gauntlet":
		_state.echo_progress_item_id = ""
		_state.echo_primary_attack_progress = 0
		return
	if _state.echo_progress_item_id != echo_item.item_id:
		_state.echo_progress_item_id = echo_item.item_id
		_state.echo_primary_attack_progress = 0


func update_coward_motion(
	previous_clamped_position: Vector2,
	current_clamped_position: Vector2,
	delta: float,
) -> void:
	if _state == null or not _has_unique(&"coward_boots"):
		return
	var safe_delta: float = maxf(delta, TimerMath.TIME_EPSILON_SECONDS)
	var actual_speed: float = (
		previous_clamped_position.distance_to(current_clamped_position) / safe_delta
	)
	if actual_speed > COWARD_MOVEMENT_THRESHOLD:
		_state.coward_stationary_elapsed = 0.0
		return
	_state.coward_stationary_elapsed = TimerMath.advance_clamped(
		_state.coward_stationary_elapsed,
		COWARD_WAIT_SECONDS,
		maxf(0.0, delta),
	)


func combat_progress_paused() -> bool:
	return (
		_state != null
		and _has_unique(&"coward_boots")
		and not TimerMath.is_ready(
			_state.coward_stationary_elapsed,
			COWARD_WAIT_SECONDS,
		)
	)


func coward_stationary_active() -> bool:
	return (
		_state != null
		and _has_unique(&"coward_boots")
		and TimerMath.is_ready(
			_state.coward_stationary_elapsed,
			COWARD_WAIT_SECONDS,
		)
	)


func advance_time_progress(delta: float) -> void:
	if combat_progress_paused() or delta <= 0.0:
		return
	_register_progress(GameTypes.TriggerType.TIME, delta, null)


func register_primary_attack(payload: Dictionary, current_tick: int) -> void:
	if combat_progress_paused() or not bool(payload.get("generated", false)):
		return
	_register_progress(GameTypes.TriggerType.PRIMARY_ATTACK_COUNT, 1.0, null)
	_register_echo_primary_attack(payload, current_tick)


func register_kill(event: CombatEvent) -> void:
	if event == null or combat_progress_paused():
		return
	_register_progress(GameTypes.TriggerType.KILL_COUNT, 1.0, event)


func register_hit(event: CombatEvent) -> void:
	if event == null or combat_progress_paused():
		return
	_register_progress(GameTypes.TriggerType.HIT_COUNT, 1.0, event)


func take_due_replays(current_tick: int) -> Array[ScheduledProcReplay]:
	var due: Array[ScheduledProcReplay] = []
	if _state == null or combat_progress_paused():
		return due
	_state.scheduled_proc_replays.sort_custom(_replay_precedes)
	var retained: Array[ScheduledProcReplay] = []
	for replay: ScheduledProcReplay in _state.scheduled_proc_replays:
		if replay.due_physics_tick <= current_tick:
			due.append(replay)
		else:
			retained.append(replay)
	_state.scheduled_proc_replays = retained
	return due


func resolve_scheduled_skill(
	replay: ScheduledProcReplay,
	enemy_snapshot: Array[int],
	enemy_store: EnemyStore,
	grid: UniformGrid,
	player_position: Vector2,
	current_tick: int,
) -> Dictionary:
	if (
		replay == null
		or replay.proc_effect_id != CROWN_PROC_ID
		or not String(replay.source_effect_id).begins_with("skill:")
	):
		return _failed_resolution()
	var skill_id := StringName(String(replay.source_effect_id).trim_prefix("skill:"))
	var allow_empty_area_event: bool = skill_id in [
		&"thousand_blades",
		&"bell_of_retribution",
	]
	return _resolve_skill_attack(
		skill_id,
		replay.proc_effect_id,
		replay.inherited_effect_chain,
		replay.damage_snapshot,
		enemy_snapshot,
		enemy_store,
		grid,
		player_position,
		current_tick,
		allow_empty_area_event,
	)


func pending_activation_snapshot() -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	if not _is_ready() or combat_progress_paused():
		return candidates
	for skill_id: StringName in SKILL_ORDER:
		var skill_state: SkillState = _skill_state(skill_id)
		if not _is_skill_active(skill_state) or skill_state.pending_queue.is_empty():
			continue
		candidates.append({
			"skill_state": skill_state,
			"pending": skill_state.pending_queue[0],
		})
	candidates.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_pending: PendingSkillActivation = left["pending"] as PendingSkillActivation
		var right_pending: PendingSkillActivation = right["pending"] as PendingSkillActivation
		return left_pending.activation_serial < right_pending.activation_serial
	)
	return candidates


func resolve_pending_candidate(
	candidate: Dictionary,
	enemy_snapshot: Array[int],
	enemy_store: EnemyStore,
	grid: UniformGrid,
	player_position: Vector2,
	current_tick: int,
) -> Dictionary:
	if combat_progress_paused():
		return _failed_resolution()
	var skill_state: SkillState = candidate.get("skill_state") as SkillState
	var pending: PendingSkillActivation = candidate.get("pending") as PendingSkillActivation
	if (
		not _is_skill_active(skill_state)
		or pending == null
		or skill_state.pending_queue.is_empty()
		or skill_state.pending_queue[0] != pending
	):
		return _failed_resolution()
	var valid_ids: Array[int] = _valid_enemy_ids(
		enemy_snapshot,
		enemy_store,
		current_tick,
	)
	if valid_ids.is_empty():
		return _failed_resolution()
	var proc_effect_id := StringName("skill:%s" % skill_state.skill_id)
	var reserved_chain: PackedStringArray = _router.reserve_secondary_chain_from_values(
		pending.inherited_effect_chain,
		pending.inherited_effect_chain.size(),
		proc_effect_id,
	)
	if reserved_chain.is_empty():
		return _failed_resolution()
	var result: Dictionary = _resolve_skill_attack(
		skill_state.skill_id,
		proc_effect_id,
		reserved_chain,
		-1.0,
		enemy_snapshot,
		enemy_store,
		grid,
		player_position,
		current_tick,
		false,
	)
	if not bool(result.get("success", false)):
		return result
	skill_state.pending_queue.pop_front()
	var event: CombatEvent = result.get("event") as CombatEvent
	if event != null:
		_schedule_crown_replay(event, skill_state.skill_id, current_tick)
	return result


func build_hud_slots() -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	if not _is_ready():
		return slots
	for slot_index: int in range(2):
		if slot_index == 1 and _has_unique(&"hollow_crown"):
			slots.append(_empty_hud_slot("sealed"))
			continue
		var skill_state: SkillState = _skill_in_slot(slot_index)
		if skill_state == null:
			slots.append(_empty_hud_slot("empty"))
			continue
		var definition: SkillDefinition = _catalog.skill(skill_state.skill_id)
		var threshold: float = _effective_threshold(skill_state)
		slots.append({
			"status": "active",
			"skill_id": String(skill_state.skill_id),
			"display_name": str(SKILL_DISPLAY_NAMES.get(skill_state.skill_id, skill_state.skill_id)),
			"level": skill_state.level,
			"trigger_type": definition.trigger_type if definition != null else -1,
			"progress": skill_state.trigger_progress,
			"threshold": threshold,
			"remaining": maxf(0.0, threshold - skill_state.trigger_progress),
			"pending_count": skill_state.pending_queue.size(),
		})
	return slots


func _register_progress(
	trigger_type: GameTypes.TriggerType,
	amount: float,
	origin_event: CombatEvent,
) -> void:
	if not _is_ready() or amount <= 0.0:
		return
	for skill_id: StringName in SKILL_ORDER:
		var skill_state: SkillState = _skill_state(skill_id)
		if not _is_skill_active(skill_state):
			continue
		var definition: SkillDefinition = _catalog.skill(skill_id)
		if definition == null or definition.trigger_type != trigger_type:
			continue
		var own_proc_id := StringName("skill:%s" % skill_id)
		if (
			origin_event != null
			and origin_event.effect_chain.has(String(own_proc_id))
		):
			continue
		skill_state.trigger_progress += amount
		_drain_threshold(skill_state, origin_event)


func _drain_threshold(
	skill_state: SkillState,
	origin_event: CombatEvent,
) -> void:
	var threshold: float = _effective_threshold(skill_state)
	if threshold <= 0.0:
		return
	while skill_state.trigger_progress >= threshold - TimerMath.TIME_EPSILON_SECONDS:
		skill_state.trigger_progress = maxf(
			0.0,
			skill_state.trigger_progress - threshold,
		)
		if skill_state.trigger_progress <= TimerMath.TIME_EPSILON_SECONDS:
			skill_state.trigger_progress = 0.0
		var pending := PendingSkillActivation.new()
		pending.activation_serial = _reserve_activation_serial()
		pending.origin_event_serial = origin_event.event_serial if origin_event != null else -1
		pending.inherited_effect_chain = (
			origin_event.effect_chain.duplicate()
			if origin_event != null
			else PackedStringArray()
		)
		skill_state.pending_queue.append(pending)


func _register_echo_primary_attack(payload: Dictionary, current_tick: int) -> void:
	synchronize_unique_state()
	if _state.echo_progress_item_id.is_empty():
		return
	_state.echo_primary_attack_progress += 1
	if _state.echo_primary_attack_progress < 3:
		return
	_state.echo_primary_attack_progress -= 3
	var reserved_chain: PackedStringArray = _router.reserve_secondary_chain_from_values(
		PackedStringArray(),
		0,
		ECHO_PROC_ID,
	)
	if reserved_chain.is_empty():
		return
	var replay := ScheduledProcReplay.new()
	replay.due_physics_tick = current_tick + REPLAY_DELAY_TICKS
	replay.schedule_serial = _reserve_activation_serial()
	replay.source_effect_id = StringName(payload.get("source_effect_id", &""))
	replay.proc_effect_id = ECHO_PROC_ID
	replay.inherited_effect_chain = reserved_chain.duplicate()
	replay.damage_snapshot = float(payload.get("damage_snapshot", 0.0))
	replay.direction = payload.get("direction", Vector2.ZERO) as Vector2
	replay.aim_distance = float(payload.get("aim_distance", 0.0))
	replay.target_entity_id = int(payload.get("target_entity_id", -1))
	_state.scheduled_proc_replays.append(replay)


func _schedule_crown_replay(
	parent_event: CombatEvent,
	skill_id: StringName,
	current_tick: int,
) -> void:
	if not _has_unique(&"hollow_crown"):
		return
	var reserved_chain: PackedStringArray = _router.reserve_secondary_chain(
		parent_event,
		CROWN_PROC_ID,
	)
	if reserved_chain.is_empty():
		return
	var replay := ScheduledProcReplay.new()
	replay.due_physics_tick = current_tick + REPLAY_DELAY_TICKS
	replay.schedule_serial = _reserve_activation_serial()
	replay.source_effect_id = StringName("skill:%s" % skill_id)
	replay.proc_effect_id = CROWN_PROC_ID
	replay.inherited_effect_chain = reserved_chain.duplicate()
	replay.damage_snapshot = parent_event.damage_snapshot
	replay.direction = Vector2.ZERO
	replay.aim_distance = 0.0
	replay.target_entity_id = -1
	_state.scheduled_proc_replays.append(replay)


func _resolve_skill_attack(
	skill_id: StringName,
	proc_effect_id: StringName,
	reserved_chain: PackedStringArray,
	damage_override: float,
	enemy_snapshot: Array[int],
	enemy_store: EnemyStore,
	grid: UniformGrid,
	player_position: Vector2,
	current_tick: int,
	allow_empty_area_event: bool,
) -> Dictionary:
	var skill_state: SkillState = _skill_state(skill_id)
	var definition: SkillDefinition = _catalog.skill(skill_id) if _catalog != null else null
	if skill_state == null or definition == null:
		return _failed_resolution()
	var valid_ids: Array[int] = _valid_enemy_ids(enemy_snapshot, enemy_store, current_tick)
	if valid_ids.is_empty() and not allow_empty_area_event:
		return _failed_resolution()
	var plan: Dictionary = _build_target_plan(
		skill_id,
		skill_state,
		valid_ids,
		enemy_store,
		grid,
		player_position,
		current_tick,
		allow_empty_area_event,
	)
	if not bool(plan.get("can_activate", false)):
		return _failed_resolution()
	var damage: float = (
		damage_override
		if damage_override >= 0.0
		else _skill_damage(skill_state, definition)
	)
	var event: CombatEvent = _router.create_secondary_from_reserved_chain(
		_state,
		reserved_chain,
		&"damage",
		-1,
		StringName("skill:%s" % skill_id),
		proc_effect_id,
		damage,
		plan.get("position", player_position) as Vector2,
		Vector2.ZERO,
	)
	if event == null:
		return _failed_resolution()
	var hits: Array[Dictionary] = []
	var target_ids: Array[int] = []
	target_ids.assign(plan.get("entity_ids", []))
	for entity_id: int in target_ids:
		hits.append({"entity_id": entity_id, "event": event})
	return {
		"success": true,
		"event": event,
		"hits": hits,
	}


func _build_target_plan(
	skill_id: StringName,
	skill_state: SkillState,
	valid_ids: Array[int],
	enemy_store: EnemyStore,
	grid: UniformGrid,
	player_position: Vector2,
	current_tick: int,
	allow_empty_area_event: bool,
) -> Dictionary:
	match skill_id:
		&"starfall":
			return _starfall_plan(
				skill_state,
				valid_ids,
				enemy_store,
				grid,
				current_tick,
			)
		&"soul_chain":
			return _soul_chain_plan(skill_state, valid_ids, enemy_store, player_position)
		&"thousand_blades", &"bell_of_retribution":
			if valid_ids.is_empty() and not allow_empty_area_event:
				return {"can_activate": false}
			var radius: float = _skill_radius(skill_state)
			return {
				"can_activate": true,
				"position": player_position,
				"entity_ids": _circle_target_ids(
					valid_ids,
					enemy_store,
					grid,
					player_position,
					radius,
					current_tick,
				),
			}
	return {"can_activate": false}


func _starfall_plan(
	skill_state: SkillState,
	valid_ids: Array[int],
	enemy_store: EnemyStore,
	grid: UniformGrid,
	current_tick: int,
) -> Dictionary:
	if valid_ids.is_empty():
		return {"can_activate": false}
	var ids_by_key: Dictionary = {}
	for entity_id: int in valid_ids:
		var enemy: EnemyEntity = enemy_store.get_by_id(entity_id)
		if enemy == null:
			continue
		var key: int = grid.cell_key_for_position(enemy.position)
		if not ids_by_key.has(key):
			ids_by_key[key] = []
		var cell_ids: Array = ids_by_key[key]
		cell_ids.append(entity_id)
	var occupied_keys: Array[int] = []
	for raw_key: Variant in ids_by_key.keys():
		occupied_keys.append(int(raw_key))
	occupied_keys.sort()
	var best_key: int = occupied_keys[0]
	var best_count: int = -1
	for key: int in occupied_keys:
		var neighbor_count: int = 0
		for neighbor_key: int in _neighbor_keys(key):
			neighbor_count += (ids_by_key.get(neighbor_key, []) as Array).size()
		if neighbor_count > best_count:
			best_key = key
			best_count = neighbor_count
	var neighborhood_ids: Array[int] = []
	for neighbor_key: int in _neighbor_keys(best_key):
		for raw_entity_id: Variant in (ids_by_key.get(neighbor_key, []) as Array):
			neighborhood_ids.append(int(raw_entity_id))
	neighborhood_ids.sort()
	var center := Vector2.ZERO
	for entity_id: int in neighborhood_ids:
		var enemy: EnemyEntity = enemy_store.get_by_id(entity_id)
		if enemy != null:
			center += enemy.position
	center /= float(neighborhood_ids.size())
	return {
		"can_activate": true,
		"position": center,
		"entity_ids": _circle_target_ids(
			valid_ids,
			enemy_store,
			grid,
			center,
			_skill_radius(skill_state),
			current_tick,
		),
	}


func _soul_chain_plan(
	skill_state: SkillState,
	valid_ids: Array[int],
	enemy_store: EnemyStore,
	player_position: Vector2,
) -> Dictionary:
	if valid_ids.is_empty():
		return {"can_activate": false}
	var ordered_ids: Array[int] = valid_ids.duplicate()
	ordered_ids.sort_custom(func(left: int, right: int) -> bool:
		var left_enemy: EnemyEntity = enemy_store.get_by_id(left)
		var right_enemy: EnemyEntity = enemy_store.get_by_id(right)
		if left_enemy == null:
			return false
		if right_enemy == null:
			return true
		var left_distance: float = player_position.distance_squared_to(left_enemy.position)
		var right_distance: float = player_position.distance_squared_to(right_enemy.position)
		if left_distance != right_distance:
			return left_distance < right_distance
		return left < right
	)
	var definition: SkillDefinition = _catalog.skill(skill_state.skill_id)
	var level_index: int = clampi(skill_state.level - 1, 0, 2)
	var target_count: int = definition.target_count_by_level[level_index]
	if ordered_ids.size() > target_count:
		ordered_ids.resize(target_count)
	return {
		"can_activate": true,
		"position": player_position,
		"entity_ids": ordered_ids,
	}


func _circle_target_ids(
	valid_ids: Array[int],
	enemy_store: EnemyStore,
	grid: UniformGrid,
	center: Vector2,
	radius: float,
	current_tick: int,
) -> Array[int]:
	var result: Array[int] = []
	var valid_lookup: Dictionary[int, bool] = {}
	for entity_id: int in valid_ids:
		valid_lookup[entity_id] = true
	var candidates: Array[int] = grid.query_circle_candidates(center, radius, 0.0)
	for entity_id: int in candidates:
		if not valid_lookup.has(entity_id):
			continue
		var enemy: EnemyEntity = enemy_store.get_by_id(entity_id)
		if enemy == null or not enemy.is_targetable(current_tick):
			continue
		if center.distance_squared_to(enemy.position) <= radius * radius:
			result.append(entity_id)
	return result


func _neighbor_keys(key: int) -> Array[int]:
	var result: Array[int] = []
	var column: int = key % UniformGrid.COLUMN_COUNT
	var row: int = floori(float(key) / float(UniformGrid.COLUMN_COUNT))
	for row_offset: int in range(-1, 2):
		var neighbor_row: int = row + row_offset
		if neighbor_row < 0 or neighbor_row >= UniformGrid.ROW_COUNT:
			continue
		for column_offset: int in range(-1, 2):
			var neighbor_column: int = column + column_offset
			if neighbor_column < 0 or neighbor_column >= UniformGrid.COLUMN_COUNT:
				continue
			result.append(neighbor_column + neighbor_row * UniformGrid.COLUMN_COUNT)
	return result


func _valid_enemy_ids(
	enemy_snapshot: Array[int],
	enemy_store: EnemyStore,
	current_tick: int,
) -> Array[int]:
	var result: Array[int] = []
	for entity_id: int in enemy_snapshot:
		var enemy: EnemyEntity = enemy_store.get_by_id(entity_id)
		if enemy != null and enemy.is_targetable(current_tick):
			result.append(entity_id)
	result.sort()
	return result


func _skill_damage(
	skill_state: SkillState,
	definition: SkillDefinition,
) -> float:
	var level_index: int = clampi(skill_state.level - 1, 0, 2)
	var stats: Dictionary = StatCalculator.aggregate_affixes(_state.equipped)
	var unique_ids: Array[StringName] = StatCalculator.equipped_unique_ids(_state.equipped)
	return definition.damage_by_level[level_index] * StatCalculator.damage_multiplier(
		stats,
		unique_ids,
		true,
		coward_stationary_active(),
	)


func _skill_radius(skill_state: SkillState) -> float:
	var definition: SkillDefinition = _catalog.skill(skill_state.skill_id)
	if definition == null:
		return 0.0
	var level_index: int = clampi(skill_state.level - 1, 0, 2)
	var stats: Dictionary = StatCalculator.aggregate_affixes(_state.equipped)
	return definition.radius_by_level[level_index] * StatCalculator.effective_area_multiplier(stats)


func _effective_threshold(skill_state: SkillState) -> float:
	if skill_state == null or _catalog == null:
		return 0.0
	var stats: Dictionary = StatCalculator.aggregate_affixes(_state.equipped)
	var unique_ids: Array[StringName] = StatCalculator.equipped_unique_ids(_state.equipped)
	return StatCalculator.effective_skill_threshold(
		_catalog.skill(skill_state.skill_id),
		stats,
		unique_ids,
	)


func _skill_state(skill_id: StringName) -> SkillState:
	if _state == null:
		return null
	return _state.skill_library.get(skill_id) as SkillState


func _skill_in_slot(slot_index: int) -> SkillState:
	for skill_id: StringName in SKILL_ORDER:
		var skill_state: SkillState = _skill_state(skill_id)
		if skill_state != null and skill_state.equipped_slot == slot_index:
			return skill_state
	return null


func _is_skill_active(skill_state: SkillState) -> bool:
	if skill_state == null or skill_state.equipped_slot < 0 or skill_state.equipped_slot > 1:
		return false
	return not (skill_state.equipped_slot == 1 and _has_unique(&"hollow_crown"))


func _equipped_item(slot: GameTypes.EquipmentSlot) -> ItemInstance:
	if _state == null:
		return null
	return _state.equipped.get(slot, null) as ItemInstance


func _has_unique(unique_id: StringName) -> bool:
	if _state == null:
		return false
	for value: Variant in _state.equipped.values():
		var item: ItemInstance = value as ItemInstance
		if item != null and item.unique_id == unique_id:
			return true
	return false


func _reserve_activation_serial() -> int:
	var serial: int = _state.next_activation_serial
	_state.next_activation_serial += 1
	return serial


func _empty_hud_slot(status: String) -> Dictionary:
	return {
		"status": status,
		"skill_id": "",
		"display_name": "",
		"level": 0,
		"trigger_type": -1,
		"progress": 0.0,
		"threshold": 0.0,
		"remaining": 0.0,
		"pending_count": 0,
	}


func _failed_resolution() -> Dictionary:
	return {
		"success": false,
		"event": null,
		"hits": [],
	}


func _is_ready() -> bool:
	return _state != null and _catalog != null and _router != null


func _replay_precedes(
	left: ScheduledProcReplay,
	right: ScheduledProcReplay,
) -> bool:
	if left.due_physics_tick != right.due_physics_tick:
		return left.due_physics_tick < right.due_physics_tick
	return left.schedule_serial < right.schedule_serial
