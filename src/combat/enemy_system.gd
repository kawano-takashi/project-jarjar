class_name EnemySystem
extends RefCounted


const NORMAL_ENEMY_TYPES: Array[GameTypes.EnemyType] = [
	GameTypes.EnemyType.PURSUER,
	GameTypes.EnemyType.SWARMER,
	GameTypes.EnemyType.BULWARK,
	GameTypes.EnemyType.SHOOTER,
]
const NORMAL_ENEMY_IDS: Array[StringName] = [
	&"pursuer",
	&"swarmer",
	&"bulwark",
	&"shooter",
]
const MAXIMUM_SPAWNS_PER_TICK: int = 16
const EMPTY_SWEEP: Dictionary = {}
const CONTACT_SEPARATION_DIRECTIONS: Array[Vector2] = [
	Vector2.RIGHT,
	Vector2.DOWN,
	Vector2.LEFT,
	Vector2.UP,
]
const CONTACT_DISTANCE_EPSILON: float = 0.000001

const CANDIDATE_PLAYER_DAMAGE: StringName = &"player_damage"
const DAMAGE_SOURCE_CONTACT: StringName = &"enemy_contact"

var enemy_store: EnemyStore = EnemyStore.new()
var uniform_grid: UniformGrid = UniformGrid.new()
var encounters: EncounterSystem = EncounterSystem.new()
var _swarm_sweep_grid: UniformGrid = UniformGrid.new()

var _state: RunState = null
var _catalog: DefinitionCatalog = null
var _manifest: SurvivalContentManifest = null
var _view: ArenaView = null
var _spawn_rng: RandomNumberGenerator = null
var _swarm_rng: RandomNumberGenerator = null
var _elite_spawned: PackedByteArray = PackedByteArray()
var _swarm_attempt_ticks: PackedInt32Array = PackedInt32Array()
var _swarm_attempt_chances: PackedFloat32Array = PackedFloat32Array()
var _swarm_attempt_hp: PackedFloat64Array = PackedFloat64Array()
var _swarm_attempt_damage: PackedFloat64Array = PackedFloat64Array()
var _swarm_attempt_consumed: PackedByteArray = PackedByteArray()
var swarm_warning: SwarmWarningState = null


func initialize(state: RunState, catalog: DefinitionCatalog, view: ArenaView = null) -> void:
	_state = state
	_catalog = catalog
	_manifest = catalog.manifest()
	encounters.initialize(_manifest.encounters)
	_view = view if view != null else ArenaView.new()
	_spawn_rng = state.rng_streams.spawn_rng if state.rng_streams != null else null
	_swarm_rng = state.rng_streams.swarm_event_rng if state.rng_streams != null else null
	enemy_store.clear()
	uniform_grid.clear()
	_swarm_sweep_grid.clear()
	_elite_spawned.resize(_catalog.elite_spawn_ticks.size())
	_elite_spawned.fill(0)
	cancel_swarm_warning()
	_build_swarm_attempts()


func snapshot_ids() -> Array[int]:
	return enemy_store.snapshot_ids_sorted()


func advance_snapshot(
	ids: Array[int],
	player_position: Vector2,
	current_tick: int,
) -> Array[int]:
	var swarm_sweeps: Array[Dictionary] = []
	var exited_swarm_ids: Array[int] = []
	var special_ids: Array[int] = []
	var stop_active: bool = _state.is_stop_active()
	# The camera is fixed during this update; each body radius shares its bounds.
	var retention_rects: Dictionary[float, Rect2] = {}
	for entity_id: int in ids:
		var enemy: EnemyEntity = enemy_store.get_by_id(entity_id)
		if enemy == null:
			continue
		if enemy.enemy_type == GameTypes.EnemyType.BOSS:
			special_ids.append(entity_id)
		if _should_far_despawn_normal(enemy, player_position, current_tick, retention_rects):
			if enemy_store.remove(entity_id):
				_state.normal_far_despawn_count += 1
			continue
		_reposition_important_enemy(enemy, current_tick, retention_rects)
		if not enemy.is_targetable(current_tick):
			continue
		var time_scale: float = 1.0
		if stop_active:
			time_scale = _manifest.combat.boss_stop_time_scale if enemy.enemy_type == GameTypes.EnemyType.BOSS else 0.0
		if time_scale <= 0.0:
			continue
		var sweep: Dictionary = _move_enemy(enemy, player_position, time_scale)
		if enemy.enemy_type == GameTypes.EnemyType.BOSS:
			enemy.position = encounters.constrain_body(enemy.position, enemy.body_radius())
		if not sweep.is_empty():
			swarm_sweeps.append(sweep)
			if enemy.remaining_travel_distance <= 0.0:
				exited_swarm_ids.append(enemy.entity_id)
		if enemy.definition.special_interval_ticks > 0:
			enemy.special_elapsed_ticks += time_scale
		if enemy.boss_charge_active:
			enemy.boss_charge_elapsed_ticks += time_scale
		if enemy.enemy_type == GameTypes.EnemyType.BOSS:
			enemy.boss_action_age_ticks += time_scale
		if enemy.telegraph_active:
			enemy.telegraph_elapsed_ticks += time_scale
		if enemy.enemy_type == GameTypes.EnemyType.BOSS:
			_update_boss_state(enemy)
	_apply_swarm_pushes(ids, swarm_sweeps)
	for entity_id: int in exited_swarm_ids:
		if enemy_store.remove(entity_id):
			_state.swarm_event_exit_count += 1
	_rebuild_grid(current_tick)
	# Preserve every boss in the tick-start order, including stopped/entering
	# bosses. The action stage applies its usual eligibility checks later.
	return special_ids


func accrue_spawn_credit() -> void:
	if _state == null or _state.combat_tick >= _catalog.boss_start_tick:
		return
	var segment: EnemySegmentDefinition = current_segment()
	if segment == null:
		return
	var normal_count: int = _normal_enemy_count()
	var deficit: int = maxi(0, segment.target_active - normal_count)
	if deficit <= 0:
		return
	var base_rate: float = maxf(_manifest.spawn.minimum_spawns_per_second / float(RunState.TICKS_PER_SECOND), float(segment.target_active) / _manifest.spawn.target_ramp_ticks)
	_state.spawn_credit = minf(
		float(MAXIMUM_SPAWNS_PER_TICK),
		_state.spawn_credit + minf(base_rate, float(deficit)),
	)


func resolve_scheduled_spawns(player_position: Vector2, current_tick: int) -> Array[EnemyEntity]:
	var spawned: Array[EnemyEntity] = []
	if current_tick >= _catalog.boss_start_tick:
		_elite_spawned.fill(1)
	for elite_index: int in range(_catalog.elite_spawn_ticks.size()):
		if (
			_elite_spawned[elite_index] == 0
			and current_tick >= _catalog.elite_spawn_ticks[elite_index]
		):
			if not _reserve_encounter_capacity(_manifest.encounters.member_count + 1, player_position):
				continue
			var elite: EnemyEntity = _spawn_enemy(
				GameTypes.EnemyType.ELITE,
				_encounter_opponent_position(player_position),
				current_tick,
			)
			if elite != null:
				_elite_spawned[elite_index] = 1
				elite.elite_serial = elite_index
				_state.elite_spawn_ticks[elite_index] = current_tick
				spawned.append(elite)
				encounters.spawn_ring(elite, player_position, _state, enemy_store, current_segment().damage_multiplier * _manifest.combat.normal_enemy_damage_scale)
	if not _state.boss_spawned and current_tick >= _catalog.boss_start_tick:
		var boss: EnemyEntity = _spawn_enemy(
			GameTypes.EnemyType.BOSS,
			_encounter_opponent_position(player_position),
			current_tick,
		)
		if boss != null:
			encounters.begin_boss(player_position, boss.activation_tick)
			_state.boss_spawned = true
			_state.boss_spawn_tick = current_tick
			_state.boss_phase = 1
			_state.boss_hp = boss.hp
			_state.boss_max_hp = boss.max_hp
			spawned.append(boss)
	return spawned


func _encounter_opponent_position(center: Vector2) -> Vector2:
	return center + Vector2.from_angle(_spawn_rng.randf() * TAU) * _manifest.encounters.opponent_distance


func _reserve_encounter_capacity(count: int, center: Vector2) -> bool:
	if enemy_store.free_count() >= count:
		return true
	var candidates: Array[EnemyEntity] = []
	for enemy: EnemyEntity in enemy_store.entities:
		if enemy.enemy_type in NORMAL_ENEMY_TYPES and not enemy.is_swarm_event and enemy.encounter_owner_id < 0:
			candidates.append(enemy)
	if candidates.size() + enemy_store.free_count() < count:
		return false
	candidates.sort_custom(func(left: EnemyEntity, right: EnemyEntity) -> bool:
		var left_distance: float = left.position.distance_squared_to(center)
		var right_distance: float = right.position.distance_squared_to(center)
		return left_distance > right_distance if left_distance != right_distance else left.entity_id < right.entity_id
	)
	for enemy: EnemyEntity in candidates:
		if enemy_store.free_count() >= count:
			break
		enemy_store.remove(enemy.entity_id)
	return true


func resolve_normal_spawns(_player_position: Vector2, current_tick: int) -> Array[EnemyEntity]:
	var spawned: Array[EnemyEntity] = []
	if current_tick >= _catalog.boss_start_tick:
		return spawned
	var segment: EnemySegmentDefinition = current_segment()
	if segment == null:
		return spawned
	var remaining_target: int = maxi(0, segment.target_active - _normal_enemy_count())
	var spawn_count: int = mini(
		mini(floori(_state.spawn_credit), remaining_target),
		MAXIMUM_SPAWNS_PER_TICK,
	)
	for _spawn_index: int in range(spawn_count):
		var enemy_type: GameTypes.EnemyType = _select_normal_enemy_type(segment)
		var enemy: EnemyEntity = _spawn_enemy(
			enemy_type,
			_spawn_position_for_type(enemy_type),
			current_tick,
		)
		if enemy == null:
			break
		spawned.append(enemy)
		_state.spawn_credit = maxf(0.0, _state.spawn_credit - 1.0)
	return spawned


func resolve_swarm_event_spawns(
	player_position: Vector2,
	current_tick: int,
) -> Array[EnemyEntity]:
	var spawned: Array[EnemyEntity] = []
	if (
		_manifest.swarm_event == null
		or _swarm_rng == null
		or current_tick >= _catalog.boss_start_tick
	):
		cancel_swarm_warning()
		return spawned
	var occupied_this_tick: bool = swarm_warning != null or has_active_swarm()
	if swarm_warning != null and current_tick >= swarm_warning.spawn_tick:
		spawned.append_array(_spawn_swarm_group(
			swarm_warning.anchor,
			swarm_warning.direction,
			current_tick,
			swarm_warning.spawn_distance,
			swarm_warning.hp_multiplier,
			swarm_warning.damage_multiplier,
		))
		cancel_swarm_warning()
	for attempt_index: int in range(_swarm_attempt_ticks.size()):
		if (
			_swarm_attempt_consumed[attempt_index] != 0
			or current_tick < _swarm_attempt_ticks[attempt_index]
		):
			continue
		_swarm_attempt_consumed[attempt_index] = 1
		_state.swarm_event_attempt_count += 1
		var attempt_rng := RandomNumberGenerator.new()
		attempt_rng.seed = _swarm_rng.randi()
		if not WeightedSelector.chance_succeeds_with_value(_swarm_attempt_chances[attempt_index], attempt_rng.randf()):
			continue
		_state.swarm_event_roll_success_count += 1
		if occupied_this_tick:
			_state.swarm_event_skipped_busy_count += 1
			continue
		var outward_direction: Vector2 = _sample_spawn_outward_direction(attempt_rng)
		var spawn_distance: float = _sample_spawn_distance(attempt_rng, player_position, outward_direction)
		swarm_warning = SwarmWarningState.new()
		swarm_warning.anchor = player_position
		swarm_warning.direction = -outward_direction
		swarm_warning.spawn_distance = spawn_distance
		swarm_warning.start_tick = current_tick
		swarm_warning.spawn_tick = current_tick + _manifest.swarm_event.telegraph_ticks
		swarm_warning.hp_multiplier = _swarm_attempt_hp[attempt_index]
		swarm_warning.damage_multiplier = _swarm_attempt_damage[attempt_index]
		occupied_this_tick = true
	return spawned


func has_active_swarm() -> bool:
	for enemy: EnemyEntity in enemy_store.entities:
		if enemy.alive and enemy.is_swarm_event:
			return true
	return false


func cancel_swarm_warning() -> void:
	swarm_warning = null


func resolve_contact_damage_candidates(
	ids: Array[int],
	player_position: Vector2,
	current_tick: int,
) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	for entity_id: int in ids:
		var enemy: EnemyEntity = enemy_store.get_by_id(entity_id)
		if not _can_resolve_actions(enemy, current_tick):
			continue
		var contact_radius: float = _catalog.envelope.player_body_radius + enemy.definition.body_radius
		if enemy.position.distance_squared_to(player_position) <= (
			contact_radius * contact_radius + CONTACT_DISTANCE_EPSILON
		):
			candidates.append(_damage_candidate(
				enemy,
				DAMAGE_SOURCE_CONTACT,
				enemy.definition.contact_damage * _effective_damage_multiplier(enemy),
				enemy.position,
			))
	return candidates


func resolve_ready_enemy_special_actions(
	ids: Array[int],
	_player_position: Vector2,
	current_tick: int,
	projectile_pool: ProjectilePool,
) -> void:
	for entity_id: int in ids:
		var enemy: EnemyEntity = enemy_store.get_by_id(entity_id)
		if enemy == null or enemy.enemy_type != GameTypes.EnemyType.BOSS:
			continue
		if not _can_resolve_actions(enemy, current_tick):
			continue
		_fire_ready_boss_volley(enemy, current_tick, projectile_pool)


func current_segment() -> EnemySegmentDefinition:
	if _catalog == null:
		return null
	return _catalog.segment_for_tick(_state.combat_tick)


func boss_entity() -> EnemyEntity:
	for enemy: EnemyEntity in enemy_store.entities:
		if enemy.enemy_type == GameTypes.EnemyType.BOSS and enemy.alive:
			return enemy
	return null


func _move_enemy(
	enemy: EnemyEntity,
	player_position: Vector2,
	time_scale: float,
) -> Dictionary:
	if enemy.movement_kind == EnemyEntity.MovementKind.FIXED_DIRECTION:
		var previous_position: Vector2 = enemy.position
		var maximum_step: float = (
			enemy.definition.move_speed
			* time_scale
			/ float(RunState.TICKS_PER_SECOND)
		)
		var travel_step: float = minf(enemy.remaining_travel_distance, maximum_step)
		enemy.position += enemy.fixed_direction * travel_step
		enemy.remaining_travel_distance = maxf(
			0.0,
			enemy.remaining_travel_distance - travel_step,
		)
		return {
			"from": previous_position,
			"to": enemy.position,
			"radius": enemy.body_radius(),
			"group_id": enemy.swarm_group_id,
			"displacement": enemy.fixed_direction * travel_step,
		}
	if enemy.encounter_owner_id >= 0:
		# Ring members pursue independently; player motion can cross their body.
		enemy.position = enemy.position.move_toward(player_position, enemy.definition.move_speed * time_scale / RunState.TICKS_PER_SECOND)
		return EMPTY_SWEEP
	var from_player: Vector2 = enemy.position - player_position
	var distance_to_player: float = from_player.length()
	var separation_direction: Vector2 = (
		from_player / distance_to_player
		if distance_to_player > 0.0
		else _deterministic_contact_direction(enemy.entity_id)
	)
	var body_radius: float = enemy.body_radius()
	var contact_radius: float = _catalog.envelope.player_body_radius + body_radius
	var next_position: Vector2 = enemy.position
	if distance_to_player < contact_radius:
		# Player motion is authoritative. Resolve only the current penetration.
		next_position = player_position + separation_direction * contact_radius
	elif distance_to_player > contact_radius:
		var maximum_step: float = (
			enemy.definition.move_speed
			* time_scale
			/ float(RunState.TICKS_PER_SECOND)
		)
		var travel_step: float = minf(maximum_step, distance_to_player - contact_radius)
		next_position -= separation_direction * travel_step
	enemy.position = next_position
	return EMPTY_SWEEP


func _deterministic_contact_direction(entity_id: int) -> Vector2:
	var direction_index: int = entity_id % CONTACT_SEPARATION_DIRECTIONS.size()
	if direction_index < 0:
		direction_index += CONTACT_SEPARATION_DIRECTIONS.size()
	return CONTACT_SEPARATION_DIRECTIONS[direction_index]


func _apply_swarm_pushes(ids: Array[int], swarm_sweeps: Array[Dictionary]) -> void:
	if swarm_sweeps.is_empty():
		return
	var push_distance_per_tick: float = _swarm_push_distance_per_tick()
	if push_distance_per_tick <= 0.0:
		return
	_swarm_sweep_grid.clear()
	var sweep_extent: float = 0.0
	var sweep_min: Vector2 = swarm_sweeps[0]["from"]
	var sweep_max: Vector2 = sweep_min
	for index: int in swarm_sweeps.size():
		var sweep: Dictionary = swarm_sweeps[index]
		var start: Vector2 = sweep["from"]
		var end: Vector2 = sweep["to"]
		_swarm_sweep_grid.insert(index, start)
		sweep_min = sweep_min.min(start)
		sweep_max = sweep_max.max(start)
		# Round outwards: this broad phase may include extras, never discard a hit.
		sweep_extent = maxf(sweep_extent, ceilf(start.distance_to(end) + float(sweep["radius"])) + 1.0)
	for entity_id: int in ids:
		var target: EnemyEntity = enemy_store.get_by_id(entity_id)
		if target == null or target.is_swarm_event or not target.alive:
			continue
		var body_radius: float = target.body_radius()
		var broad_extent: float = sweep_extent + maxf(0.0, body_radius)
		if (
			target.position.x < sweep_min.x - broad_extent
			or target.position.x > sweep_max.x + broad_extent
			or target.position.y < sweep_min.y - broad_extent
			or target.position.y > sweep_max.y + broad_extent
		):
			continue
		var total_displacement: Vector2 = Vector2.ZERO
		var sweep_indices: Array[int] = _swarm_sweep_grid.query_circle_candidates(target.position, body_radius, sweep_extent)
		# Accumulation order matters for Vector2 rounding.
		sweep_indices.sort()
		for sweep_index: int in sweep_indices:
			var sweep: Dictionary = swarm_sweeps[sweep_index]
			var collision_radius: float = body_radius + float(sweep["radius"])
			if not _segment_intersects_circle(
				sweep["from"],
				sweep["to"],
				target.position,
				collision_radius,
			):
				continue
			total_displacement += sweep["displacement"]
		if total_displacement == Vector2.ZERO:
			continue
		if total_displacement.length_squared() > (
			push_distance_per_tick * push_distance_per_tick
		):
			total_displacement = total_displacement.normalized() * push_distance_per_tick
		var pushed_position: Vector2 = target.position + total_displacement
		target.position = pushed_position


func _swarm_push_distance_per_tick() -> float:
	if _manifest == null or _manifest.swarm_event == null:
		return 0.0
	var unit: EnemyDefinition = _manifest.swarm_event.unit_definition
	if unit == null:
		return 0.0
	return maxf(0.0, unit.move_speed) / float(RunState.TICKS_PER_SECOND)


func _segment_intersects_circle(
	segment_start: Vector2,
	segment_end: Vector2,
	circle_center: Vector2,
	circle_radius: float,
) -> bool:
	var segment: Vector2 = segment_end - segment_start
	var length_squared: float = segment.length_squared()
	var closest: Vector2 = segment_start
	if length_squared > 0.0:
		var ratio: float = clampf(
			(circle_center - segment_start).dot(segment) / length_squared,
			0.0,
			1.0,
		)
		closest += segment * ratio
	return closest.distance_squared_to(circle_center) <= circle_radius * circle_radius


func _fire_ready_boss_volley(
	enemy: EnemyEntity,
	current_tick: int,
	projectile_pool: ProjectilePool,
) -> void:
	if enemy.boss_charge_active:
		if enemy.boss_charge_elapsed_ticks < float(_catalog.enemy_for_type(GameTypes.EnemyType.BOSS).telegraph_ticks):
			return
		_emit_boss_volley(enemy, current_tick, projectile_pool)
		return
	var interval_ticks: int = _boss_action_interval_ticks(
		enemy.definition.special_interval_ticks,
		enemy.boss_phase,
	)
	if (
		interval_ticks <= 0
		or enemy.special_elapsed_ticks < float(interval_ticks - _catalog.enemy_for_type(GameTypes.EnemyType.BOSS).telegraph_ticks)
	):
		return
	var charge_start_tick: float = float(interval_ticks - _catalog.enemy_for_type(GameTypes.EnemyType.BOSS).telegraph_ticks)
	_start_boss_charge(
		enemy,
		interval_ticks,
		maxf(0.0, enemy.special_elapsed_ticks - charge_start_tick),
	)


func _start_boss_charge(
	enemy: EnemyEntity,
	interval_ticks: int,
	initial_elapsed_ticks: float = 0.0,
) -> void:
	enemy.boss_charge_active = true
	enemy.boss_charge_elapsed_ticks = clampf(
		initial_elapsed_ticks,
		0.0,
		float(_catalog.enemy_for_type(GameTypes.EnemyType.BOSS).telegraph_ticks),
	)
	enemy.boss_charge_interval_ticks = interval_ticks
	enemy.boss_charge_spoke_count = (
		enemy.definition.volley_count
		+ maxi(0, enemy.boss_phase - 1) * _manifest.combat.boss_volley_phase_bonus
	)
	enemy.boss_charge_half_step = enemy.barrage_alternate


func _emit_boss_volley(
	enemy: EnemyEntity,
	current_tick: int,
	projectile_pool: ProjectilePool,
) -> void:
	var volley_count: int = enemy.boss_charge_spoke_count
	var angle_step: float = TAU / float(maxi(1, volley_count))
	var offset: float = angle_step * 0.5 if enemy.boss_charge_half_step else 0.0
	for angle_index: int in range(volley_count):
		var direction: Vector2 = Vector2.from_angle(offset + angle_step * float(angle_index))
		_spawn_enemy_projectile(enemy, direction, current_tick, projectile_pool, _manifest.combat.boss_stop_time_scale)
	enemy.barrage_alternate = not enemy.barrage_alternate
	enemy.special_elapsed_ticks = 0.0
	enemy.boss_charge_active = false
	enemy.boss_charge_elapsed_ticks = 0.0
	enemy.boss_charge_interval_ticks = 0
	enemy.boss_charge_spoke_count = 0
	enemy.boss_charge_half_step = false
	var next_interval_ticks: int = _boss_action_interval_ticks(
		enemy.definition.special_interval_ticks,
		enemy.boss_phase,
	)
	if next_interval_ticks == _catalog.enemy_for_type(GameTypes.EnemyType.BOSS).telegraph_ticks:
		_start_boss_charge(enemy, next_interval_ticks)


func _spawn_enemy_projectile(
	enemy: EnemyEntity,
	direction: Vector2,
	current_tick: int,
	projectile_pool: ProjectilePool,
	stop_time_scale: float,
) -> void:
	if enemy.enemy_type != GameTypes.EnemyType.BOSS:
		return
	var lifetime_seconds: float = (
		float(enemy.definition.projectile_lifetime_ticks)
		/ float(RunState.TICKS_PER_SECOND)
	)
	projectile_pool.acquire(
		ProjectileState.FACTION_ENEMY,
		enemy.definition.enemy_id,
		enemy.entity_id,
		enemy.position,
		direction * enemy.definition.projectile_speed,
		enemy.definition.projectile_radius,
		enemy.definition.projectile_damage * _effective_damage_multiplier(enemy),
		enemy.definition.projectile_speed * lifetime_seconds,
		lifetime_seconds,
		enemy.position + direction * enemy.definition.projectile_speed * lifetime_seconds,
		0,
		current_tick,
		&"boss_projectile" if enemy.enemy_type == GameTypes.EnemyType.BOSS else &"enemy_projectile",
		ProjectileState.MovementKind.STRAIGHT,
		-1,
		enemy.definition.projectile_lifetime_ticks,
		0,
		0.0,
		stop_time_scale,
	)


func _update_boss_state(enemy: EnemyEntity) -> void:
	if enemy.enemy_type != GameTypes.EnemyType.BOSS:
		return
	var hp_ratio: float = enemy.hp / enemy.max_hp
	var phase: int = 1
	if hp_ratio <= _manifest.combat.boss_phase_three_hp_ratio:
		phase = 3
	elif hp_ratio <= _manifest.combat.boss_phase_two_hp_ratio:
		phase = 2
	enemy.boss_phase = phase
	_state.boss_phase = phase
	_state.boss_hp = enemy.hp
	_state.boss_max_hp = enemy.max_hp
	_state.boss_enrage_stacks = mini(
		_manifest.combat.boss_enrage_max_stacks,
		floori(enemy.boss_action_age_ticks / float(_manifest.combat.boss_enrage_interval_ticks)),
	)


func _boss_action_interval(base_ticks: int, phase: int) -> float:
	return float(_boss_action_interval_ticks(base_ticks, phase))


func _boss_action_interval_ticks(base_ticks: int, phase: int) -> int:
	if base_ticks <= 0:
		return 0
	var phase_multiplier: float = pow(_manifest.combat.boss_phase_interval_multiplier, maxi(0, phase - 1))
	var enrage_multiplier: float = (
		1.0
		- _manifest.combat.boss_interval_reduction_per_stack
		* float(_state.boss_enrage_stacks)
	)
	var nominal_interval_ticks: float = (
		float(base_ticks)
		/ _manifest.combat.boss_action_rate_multiplier
		* maxf(_manifest.combat.boss_min_interval_multiplier, phase_multiplier * enrage_multiplier)
	)
	return maxi(_catalog.enemy_for_type(GameTypes.EnemyType.BOSS).telegraph_ticks, ceili(nominal_interval_ticks))


func _effective_damage_multiplier(enemy: EnemyEntity) -> float:
	var multiplier: float = enemy.damage_multiplier
	if enemy.enemy_type == GameTypes.EnemyType.BOSS:
		multiplier *= 1.0 + (
			_manifest.combat.boss_attack_bonus_per_stack * float(_state.boss_enrage_stacks)
		)
	return multiplier


func _time_scale_for(enemy: EnemyEntity) -> float:
	if not _state.is_stop_active():
		return 1.0
	return _manifest.combat.boss_stop_time_scale if enemy.enemy_type == GameTypes.EnemyType.BOSS else 0.0


func _spawn_enemy(
	enemy_type: GameTypes.EnemyType,
	position: Vector2,
	current_tick: int,
) -> EnemyEntity:
	var definition: EnemyDefinition = _catalog.enemy_for_type(enemy_type)
	if definition == null:
		return null
	var segment: EnemySegmentDefinition = current_segment()
	var hp_multiplier: float = segment.hp_multiplier
	var damage_multiplier: float = segment.damage_multiplier
	if enemy_type == GameTypes.EnemyType.BOSS:
		hp_multiplier = _manifest.combat.boss_hp_multiplier
		damage_multiplier = _manifest.combat.boss_damage_multiplier
	elif enemy_type in NORMAL_ENEMY_TYPES:
		damage_multiplier *= _manifest.combat.normal_enemy_damage_scale
	return enemy_store.try_spawn(
		_state,
		enemy_type,
		definition,
		position,
		hp_multiplier,
		damage_multiplier,
		current_tick,
		_catalog.envelope.entry_ticks_for_enemy_type(enemy_type),
	)


func _spawn_swarm_group(
	player_position: Vector2,
	direction: Vector2,
	current_tick: int,
	spawn_distance: float,
	hp_multiplier: float,
	damage_multiplier: float,
) -> Array[EnemyEntity]:
	var spawned: Array[EnemyEntity] = []
	var event_definition: SwarmEventDefinition = _manifest.swarm_event
	if (
		event_definition == null
		or event_definition.unit_definition == null
		or enemy_store.free_count() < event_definition.member_count
	):
		_state.swarm_event_spawn_failure_count += 1
		return spawned
	var group_id: int = _state.allocate_swarm_group_id()
	var lateral_direction := Vector2(-direction.y, direction.x)
	var formation_depth: float = (
		float(maxi(0, event_definition.depth_count - 1))
		* event_definition.depth_pitch
	)
	var travel_distance: float = 2.0 * spawn_distance + formation_depth
	for depth_index: int in range(event_definition.depth_count):
		var stagger: float = (
			-0.25 if depth_index % 2 == 0 else 0.25
		) * event_definition.lateral_pitch
		for lateral_index: int in range(event_definition.lateral_count):
			var lateral_offset: float = (
				float(lateral_index)
				- float(event_definition.lateral_count - 1) * 0.5
			) * event_definition.lateral_pitch + stagger
			var depth_offset: float = float(depth_index) * event_definition.depth_pitch
			var spawn_position: Vector2 = (
				player_position
				- direction * (spawn_distance + depth_offset)
				+ lateral_direction * lateral_offset
			)
			var enemy: EnemyEntity = enemy_store.try_spawn(
				_state,
				GameTypes.EnemyType.SWARMER,
				event_definition.unit_definition,
				spawn_position,
				hp_multiplier,
				damage_multiplier,
				current_tick,
				0,
			)
			if enemy == null:
				for created: EnemyEntity in spawned:
					enemy_store.remove(created.entity_id)
				spawned.clear()
				_state.swarm_event_spawn_failure_count += 1
				return spawned
			enemy.configure_swarm_event(
				group_id,
				direction,
				travel_distance,
				(lateral_index + depth_index) % 2 == 1,
			)
			spawned.append(enemy)
	_state.swarm_event_group_count += 1
	_state.swarm_event_generated_count += spawned.size()
	return spawned


func _build_swarm_attempts() -> void:
	_swarm_attempt_ticks.clear()
	_swarm_attempt_chances.clear()
	_swarm_attempt_hp.clear()
	_swarm_attempt_damage.clear()
	for attempt: Dictionary in _catalog.swarm_attempts:
		_swarm_attempt_ticks.append(int(attempt[&"tick"]))
		_swarm_attempt_chances.append(float(attempt[&"chance"]))
		_swarm_attempt_hp.append(float(attempt[&"hp_multiplier"]))
		_swarm_attempt_damage.append(float(attempt[&"damage_multiplier"]))
	_swarm_attempt_consumed.resize(_swarm_attempt_ticks.size())
	_swarm_attempt_consumed.fill(0)


func _select_normal_enemy_type(segment: EnemySegmentDefinition) -> GameTypes.EnemyType:
	var total: float = 0.0
	var last_positive: GameTypes.EnemyType = GameTypes.EnemyType.PURSUER
	for type: GameTypes.EnemyType in NORMAL_ENEMY_TYPES:
		total += segment.weight_for(type)
	var roll: float = _spawn_rng.randf() * total
	for type: GameTypes.EnemyType in NORMAL_ENEMY_TYPES:
		var weight: float = segment.weight_for(type)
		if weight <= 0.0:
			continue
		last_positive = type
		if roll < weight:
			return type
		roll -= weight
	return last_positive


func _spawn_position_for_type(enemy_type: GameTypes.EnemyType) -> Vector2:
	return _view.sample_offscreen_position(_spawn_rng, _manifest.spawn.offscreen_band_width, _catalog.enemy_for_type(enemy_type).body_radius)


func _sample_spawn_outward_direction(rng: RandomNumberGenerator) -> Vector2:
	return _view.screen_to_world_input(CONTACT_SEPARATION_DIRECTIONS[rng.randi_range(0, 3)])


func _sample_spawn_distance(rng: RandomNumberGenerator, anchor: Vector2, outward: Vector2) -> float:
	var bounds: Rect2 = _view.body_view_rect(_manifest.swarm_event.unit_definition.body_radius)
	var extent: Vector2 = (bounds.position - anchor).abs().max((bounds.end - anchor).abs())
	return extent.dot(outward.abs()) + rng.randf_range(0.0, _manifest.spawn.offscreen_band_width)


func _outside_retention(enemy: EnemyEntity, retention_rects: Dictionary[float, Rect2]) -> bool:
	var radius: float = enemy.body_radius()
	if not retention_rects.has(radius):
		retention_rects[radius] = _view.body_view_rect(radius).grow(
			_manifest.spawn.offscreen_band_width + _manifest.spawn.despawn_margin,
		)
	return not retention_rects[radius].has_point(enemy.position)


func _should_far_despawn_normal(enemy: EnemyEntity, _player_position: Vector2, current_tick: int, retention_rects: Dictionary[float, Rect2]) -> bool:
	return (
		current_tick < _catalog.boss_start_tick and enemy.alive and not enemy.is_swarm_event and enemy.encounter_owner_id < 0
		and enemy.enemy_type in NORMAL_ENEMY_TYPES and _outside_retention(enemy, retention_rects)
	)


func _reposition_important_enemy(enemy: EnemyEntity, current_tick: int, retention_rects: Dictionary[float, Rect2]) -> void:
	if enemy.enemy_type == GameTypes.EnemyType.BOSS and encounters.boss_active:
		return
	if not enemy.alive or enemy.enemy_type not in [GameTypes.EnemyType.ELITE, GameTypes.EnemyType.BOSS] or not _outside_retention(enemy, retention_rects):
		return
	enemy.position = _spawn_position_for_type(enemy.enemy_type)
	enemy.spawn_tick = current_tick
	enemy.activation_tick = current_tick + _catalog.envelope.entry_ticks_for_enemy_type(enemy.enemy_type)
	enemy.telegraph_active = false
	enemy.telegraph_elapsed_ticks = 0.0
	enemy.telegraph_position = enemy.position
	enemy.special_elapsed_ticks = 0.0
	enemy.boss_charge_active = false
	enemy.boss_charge_elapsed_ticks = 0.0


func shift_origin(displacement: Vector2) -> void:
	encounters.shift_origin(displacement)
	for enemy: EnemyEntity in enemy_store.entities:
		enemy.position -= displacement
		enemy.telegraph_position -= displacement
	if swarm_warning != null:
		swarm_warning.anchor -= displacement
	_rebuild_grid(_state.combat_tick)
	_swarm_sweep_grid.clear()


func _normal_enemy_count() -> int:
	var count: int = 0
	for enemy: EnemyEntity in enemy_store.entities:
		if enemy.enemy_type in NORMAL_ENEMY_TYPES and not enemy.is_swarm_event and enemy.encounter_owner_id < 0:
			count += 1
	return count


func _rebuild_grid(current_tick: int) -> void:
	uniform_grid.rebuild_enemies(enemy_store, current_tick)


func _can_resolve_actions(enemy: EnemyEntity, current_tick: int) -> bool:
	return (
		enemy != null
		and enemy.definition != null
		and enemy.is_targetable(current_tick)
		and _time_scale_for(enemy) > 0.0
	)


func _damage_candidate(
	enemy: EnemyEntity,
	source_effect_id: StringName,
	raw_damage: float,
	position: Vector2,
) -> Dictionary:
	return {
		"type": CANDIDATE_PLAYER_DAMAGE,
		"source_entity_id": enemy.entity_id,
		"source_pool_index": enemy.pool_index,
		"source_generation": enemy.generation,
		"source_effect_id": source_effect_id,
		"raw_damage": raw_damage,
		"position": position,
	}
