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
const SPAWN_TARGET_RAMP_TICKS: float = 180.0
const BOSS_CHARGE_TICKS: int = CombatEnvelope.BOSS_CHARGE_TICKS
const BOSS_VOLLEY_BASE_COUNT: int = 8
const BOSS_VOLLEY_PHASE_BONUS: int = 4
const BOSS_PHASE_INTERVAL_MULTIPLIER: float = 0.75
const BOSS_MIN_INTERVAL_MULTIPLIER: float = 0.20
const SWARM_PUSH_DISTANCE_PER_TICK: float = 32.0 / float(RunState.TICKS_PER_SECOND)
const SCREEN_RIGHT_WORLD: Vector2 = Vector2(0.70710678, -0.70710678)
const SCREEN_DOWN_WORLD: Vector2 = Vector2(0.70710678, 0.70710678)
const SPAWN_OUTWARD_DIRECTIONS: Array[Vector2] = [
	-SCREEN_DOWN_WORLD,
	SCREEN_DOWN_WORLD,
	-SCREEN_RIGHT_WORLD,
	SCREEN_RIGHT_WORLD,
]

const ACTION_PLAYER_DAMAGE: StringName = &"player_damage"
const DAMAGE_SOURCE_CONTACT: StringName = &"enemy_contact"

var enemy_store: EnemyStore = EnemyStore.new()
var uniform_grid: UniformGrid = UniformGrid.new()

var _state: RunState = null
var _catalog: DefinitionCatalog = null
var _manifest: SurvivalContentManifest = null
var _spawn_rng: RandomNumberGenerator = null
var _swarm_rng: RandomNumberGenerator = null
var _elite_spawned: PackedByteArray = PackedByteArray()
var _swarm_attempt_ticks: PackedInt32Array = PackedInt32Array()
var _swarm_attempt_chances: PackedFloat32Array = PackedFloat32Array()
var _swarm_attempt_consumed: PackedByteArray = PackedByteArray()


func initialize(state: RunState, catalog: DefinitionCatalog) -> void:
	_state = state
	_catalog = catalog
	_manifest = catalog.manifest()
	_spawn_rng = state.rng_streams.spawn_rng if state.rng_streams != null else null
	_swarm_rng = state.rng_streams.swarm_event_rng if state.rng_streams != null else null
	enemy_store.clear()
	uniform_grid.clear()
	_elite_spawned.resize(_manifest.elite_spawn_ticks.size())
	_elite_spawned.fill(0)
	_build_swarm_attempts()


func snapshot_ids() -> Array[int]:
	return enemy_store.snapshot_ids_sorted()


func advance_snapshot(
	ids: Array[int],
	player_position: Vector2,
	current_tick: int,
) -> void:
	var swarm_sweeps: Array[Dictionary] = []
	var exited_swarm_ids: Array[int] = []
	for entity_id: int in ids:
		var enemy: EnemyEntity = enemy_store.get_by_id(entity_id)
		if enemy == null:
			continue
		if _should_far_despawn_normal(enemy, player_position, current_tick):
			if enemy_store.remove(entity_id):
				_state.normal_far_despawn_count += 1
			continue
		if not enemy.is_targetable(current_tick):
			continue
		var time_scale: float = _time_scale_for(enemy)
		if time_scale <= 0.0:
			continue
		var sweep: Dictionary = _move_enemy(enemy, player_position, time_scale)
		if not sweep.is_empty():
			swarm_sweeps.append(sweep)
			if enemy.remaining_travel_distance <= 0.0:
				exited_swarm_ids.append(enemy.entity_id)
		_advance_enemy_timers(enemy, time_scale)
		_update_boss_state(enemy)
	_apply_swarm_pushes(ids, swarm_sweeps)
	for entity_id: int in exited_swarm_ids:
		if enemy_store.remove(entity_id):
			_state.swarm_event_exit_count += 1
	_rebuild_grid(current_tick)


func accrue_spawn_credit() -> void:
	if _state == null or _state.combat_tick >= _manifest.boss_start_tick:
		return
	var segment: EnemySegmentDefinition = current_segment()
	if segment == null:
		return
	var normal_count: int = _normal_enemy_count()
	var deficit: int = maxi(0, segment.target_active - normal_count)
	if deficit <= 0:
		return
	var base_rate: float = maxf(1.0 / 60.0, float(segment.target_active) / SPAWN_TARGET_RAMP_TICKS)
	_state.spawn_credit = minf(
		float(MAXIMUM_SPAWNS_PER_TICK),
		_state.spawn_credit + minf(base_rate, float(deficit)),
	)


func resolve_scheduled_spawns(_player_position: Vector2, current_tick: int) -> Array[EnemyEntity]:
	var spawned: Array[EnemyEntity] = []
	for elite_index: int in range(_manifest.elite_spawn_ticks.size()):
		if (
			_elite_spawned[elite_index] == 0
			and current_tick >= _manifest.elite_spawn_ticks[elite_index]
		):
			var elite: EnemyEntity = _spawn_enemy(
				GameTypes.EnemyType.ELITE,
				Vector2.ZERO,
				current_tick,
			)
			if elite != null:
				_elite_spawned[elite_index] = 1
				elite.elite_serial = elite_index
				_state.elite_spawn_ticks[elite_index] = current_tick
				spawned.append(elite)
	if not _state.boss_spawned and current_tick >= _manifest.boss_start_tick:
		var boss: EnemyEntity = _spawn_enemy(
			GameTypes.EnemyType.BOSS,
			Vector2.ZERO,
			current_tick,
		)
		if boss != null:
			_state.boss_spawned = true
			_state.boss_spawn_tick = current_tick
			_state.boss_phase = 1
			_state.boss_hp = boss.hp
			_state.boss_max_hp = boss.max_hp
			spawned.append(boss)
	return spawned


func resolve_normal_spawns(player_position: Vector2, current_tick: int) -> Array[EnemyEntity]:
	var spawned: Array[EnemyEntity] = []
	if current_tick >= _manifest.boss_start_tick:
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
			_choose_normal_spawn_position(player_position),
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
		or current_tick >= _manifest.boss_start_tick
	):
		return spawned
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
		if attempt_rng.randf() >= _swarm_attempt_chances[attempt_index]:
			continue
		_state.swarm_event_roll_success_count += 1
		var outward_direction: Vector2 = _sample_spawn_outward_direction(attempt_rng)
		var spawn_distance: float = _sample_spawn_distance(attempt_rng)
		spawned.append_array(_spawn_swarm_group(
			player_position,
			-outward_direction,
			current_tick,
			spawn_distance,
		))
	return spawned

func resolve_ready_enemy_damage_actions(
	ids: Array[int],
	player_position: Vector2,
	current_tick: int,
) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for entity_id: int in ids:
		var enemy: EnemyEntity = enemy_store.get_by_id(entity_id)
		if not _can_resolve_actions(enemy, current_tick):
			continue
		var contact_radius: float = CombatEnvelope.PLAYER_BODY_RADIUS + enemy.definition.body_radius
		if (
			enemy.contact_elapsed_ticks >= float(enemy.definition.contact_interval_ticks)
			and enemy.position.distance_squared_to(player_position)
			<= contact_radius * contact_radius
		):
			records.append(_damage_record(
				enemy,
				DAMAGE_SOURCE_CONTACT,
				enemy.definition.contact_damage * _effective_damage_multiplier(enemy),
				enemy.position,
			))
			enemy.contact_elapsed_ticks = 0.0
	return records


func resolve_ready_enemy_special_actions(
	ids: Array[int],
	_player_position: Vector2,
	current_tick: int,
	projectile_pool: ProjectilePool,
) -> void:
	for entity_id: int in ids:
		var enemy: EnemyEntity = enemy_store.get_by_id(entity_id)
		if not _can_resolve_actions(enemy, current_tick):
			continue
		if enemy.enemy_type == GameTypes.EnemyType.BOSS:
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
	var offset: Vector2 = player_position - enemy.position
	var direction: Vector2 = Vector2.ZERO
	if offset != Vector2.ZERO:
		direction = offset.normalized()
	var next_position: Vector2 = (
		enemy.position
		+ direction * enemy.definition.move_speed * time_scale / float(RunState.TICKS_PER_SECOND)
	)
	if _is_enemy_center_inside_arena(enemy.position, enemy.body_radius()):
		next_position = _clamp_enemy_center(next_position, enemy.body_radius())
	enemy.position = next_position
	return {}


func _apply_swarm_pushes(ids: Array[int], swarm_sweeps: Array[Dictionary]) -> void:
	if swarm_sweeps.is_empty():
		return
	for entity_id: int in ids:
		var target: EnemyEntity = enemy_store.get_by_id(entity_id)
		if target == null or target.is_swarm_event or not target.alive:
			continue
		var total_displacement: Vector2 = Vector2.ZERO
		for sweep: Dictionary in swarm_sweeps:
			var collision_radius: float = target.body_radius() + float(sweep["radius"])
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
			SWARM_PUSH_DISTANCE_PER_TICK * SWARM_PUSH_DISTANCE_PER_TICK
		):
			total_displacement = total_displacement.normalized() * SWARM_PUSH_DISTANCE_PER_TICK
		var pushed_position: Vector2 = target.position + total_displacement
		if _is_enemy_center_inside_arena(target.position, target.body_radius()):
			pushed_position = _clamp_enemy_center(pushed_position, target.body_radius())
		target.position = pushed_position


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


func _advance_enemy_timers(enemy: EnemyEntity, time_scale: float) -> void:
	enemy.contact_elapsed_ticks = minf(
		float(enemy.definition.contact_interval_ticks),
		enemy.contact_elapsed_ticks + time_scale,
	)
	if enemy.definition.special_interval_ticks > 0:
		enemy.special_elapsed_ticks += time_scale
	if enemy.boss_charge_active:
		enemy.boss_charge_elapsed_ticks += time_scale
	if enemy.enemy_type == GameTypes.EnemyType.BOSS:
		enemy.boss_action_age_ticks += time_scale
	if enemy.telegraph_active:
		enemy.telegraph_elapsed_ticks += time_scale


func _fire_ready_boss_volley(
	enemy: EnemyEntity,
	current_tick: int,
	projectile_pool: ProjectilePool,
) -> void:
	if enemy.boss_charge_active:
		if enemy.boss_charge_elapsed_ticks < float(BOSS_CHARGE_TICKS):
			return
		_emit_boss_volley(enemy, current_tick, projectile_pool)
		return
	var interval_ticks: int = _boss_action_interval_ticks(
		enemy.definition.special_interval_ticks,
		enemy.boss_phase,
	)
	if (
		interval_ticks <= 0
		or enemy.special_elapsed_ticks < float(interval_ticks - BOSS_CHARGE_TICKS)
	):
		return
	var charge_start_tick: float = float(interval_ticks - BOSS_CHARGE_TICKS)
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
		float(BOSS_CHARGE_TICKS),
	)
	enemy.boss_charge_interval_ticks = interval_ticks
	enemy.boss_charge_spoke_count = (
		BOSS_VOLLEY_BASE_COUNT
		+ maxi(0, enemy.boss_phase - 1) * BOSS_VOLLEY_PHASE_BONUS
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
		_spawn_enemy_projectile(enemy, direction, current_tick, projectile_pool, 0.5)
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
	if next_interval_ticks == BOSS_CHARGE_TICKS:
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
	var hp_ratio: float = enemy.hp / maxf(1.0, enemy.max_hp)
	var phase: int = 1
	if hp_ratio <= 0.33:
		phase = 3
	elif hp_ratio <= 0.66:
		phase = 2
	enemy.boss_phase = phase
	_state.boss_phase = phase
	_state.boss_hp = enemy.hp
	_state.boss_max_hp = enemy.max_hp
	_state.boss_enrage_stacks = mini(
		_manifest.boss_enrage_max_stacks,
		floori(enemy.boss_action_age_ticks / float(_manifest.boss_enrage_interval_ticks)),
	)


func _boss_action_interval(base_ticks: int, phase: int) -> float:
	return float(_boss_action_interval_ticks(base_ticks, phase))


func _boss_action_interval_ticks(base_ticks: int, phase: int) -> int:
	if base_ticks <= 0:
		return 0
	var phase_multiplier: float = pow(BOSS_PHASE_INTERVAL_MULTIPLIER, maxi(0, phase - 1))
	var enrage_multiplier: float = (
		1.0
		- _manifest.boss_interval_reduction_per_stack
		* float(_state.boss_enrage_stacks)
	)
	var nominal_interval_ticks: float = (
		float(base_ticks)
		/ _manifest.boss_action_rate_multiplier
		* maxf(BOSS_MIN_INTERVAL_MULTIPLIER, phase_multiplier * enrage_multiplier)
	)
	return maxi(BOSS_CHARGE_TICKS, ceili(nominal_interval_ticks))


func _effective_damage_multiplier(enemy: EnemyEntity) -> float:
	var multiplier: float = enemy.damage_multiplier
	if enemy.enemy_type == GameTypes.EnemyType.BOSS:
		multiplier *= 1.0 + (
			_manifest.boss_attack_bonus_per_stack * float(_state.boss_enrage_stacks)
		)
	return multiplier


func _time_scale_for(enemy: EnemyEntity) -> float:
	if not _state.is_stop_active():
		return 1.0
	return 0.5 if enemy.enemy_type == GameTypes.EnemyType.BOSS else 0.0


func _spawn_enemy(
	enemy_type: GameTypes.EnemyType,
	position: Vector2,
	current_tick: int,
) -> EnemyEntity:
	var definition: EnemyDefinition = _catalog.enemy(GameTypes.enemy_type_to_key(enemy_type))
	if definition == null:
		return null
	var segment: EnemySegmentDefinition = current_segment()
	var hp_multiplier: float = segment.hp_multiplier if segment != null else 1.0
	var damage_multiplier: float = segment.damage_multiplier if segment != null else 1.0
	if enemy_type == GameTypes.EnemyType.BOSS:
		hp_multiplier = _manifest.boss_hp_multiplier
		damage_multiplier = _manifest.boss_damage_multiplier
	elif enemy_type in NORMAL_ENEMY_TYPES:
		damage_multiplier *= _manifest.normal_enemy_damage_scale
	var resolved_position: Vector2 = position
	if enemy_type not in NORMAL_ENEMY_TYPES:
		resolved_position = _clamp_enemy_center(position, definition.body_radius)
	return enemy_store.try_spawn(
		_state,
		enemy_type,
		definition,
		resolved_position,
		hp_multiplier,
		damage_multiplier,
		current_tick,
		CombatEnvelope.entry_ticks_for_enemy_type(enemy_type),
	)


func _spawn_swarm_group(
	player_position: Vector2,
	direction: Vector2,
	current_tick: int,
	spawn_distance: float,
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
	var segment: EnemySegmentDefinition = _catalog.segment_for_tick(current_tick)
	var hp_multiplier: float = segment.hp_multiplier if segment != null else 1.0
	var damage_multiplier: float = segment.damage_multiplier if segment != null else 1.0
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
			enemy.contact_elapsed_ticks = float(
				event_definition.unit_definition.contact_interval_ticks
			)
			spawned.append(enemy)
	_state.swarm_event_group_count += 1
	_state.swarm_event_generated_count += spawned.size()
	return spawned


func _build_swarm_attempts() -> void:
	_swarm_attempt_ticks.clear()
	_swarm_attempt_chances.clear()
	if _manifest.swarm_event != null:
		for schedule: SwarmEventScheduleDefinition in _manifest.swarm_event.schedules:
			if schedule == null:
				continue
			for attempt_offset: int in range(schedule.attempt_count):
				_swarm_attempt_ticks.append(
					schedule.first_tick + schedule.interval_ticks * attempt_offset
				)
				_swarm_attempt_chances.append(schedule.spawn_chance)
	_swarm_attempt_consumed.resize(_swarm_attempt_ticks.size())
	_swarm_attempt_consumed.fill(0)


func _select_normal_enemy_type(segment: EnemySegmentDefinition) -> GameTypes.EnemyType:
	if segment == null or _spawn_rng == null:
		return GameTypes.EnemyType.PURSUER
	var total_weight: float = 0.0
	for enemy_type: GameTypes.EnemyType in NORMAL_ENEMY_TYPES:
		total_weight += segment.weight_for(enemy_type)
	var roll: float = _spawn_rng.randf() * maxf(0.000001, total_weight)
	for enemy_type: GameTypes.EnemyType in NORMAL_ENEMY_TYPES:
		roll -= segment.weight_for(enemy_type)
		if roll <= 0.0:
			return enemy_type
	return NORMAL_ENEMY_TYPES.back()


func _choose_normal_spawn_position(player_position: Vector2) -> Vector2:
	if _spawn_rng == null:
		return player_position - SCREEN_DOWN_WORLD * 11.0
	var outward_direction: Vector2 = _sample_spawn_outward_direction(_spawn_rng)
	var spawn_distance: float = _sample_spawn_distance(_spawn_rng)
	var tangent_direction := Vector2(-outward_direction.y, outward_direction.x)
	var lateral_offset: float = _spawn_rng.randf_range(-spawn_distance, spawn_distance)
	return (
		player_position
		+ outward_direction * spawn_distance
		+ tangent_direction * lateral_offset
	)


func _sample_spawn_outward_direction(rng: RandomNumberGenerator) -> Vector2:
	if rng == null:
		return -SCREEN_DOWN_WORLD
	return SPAWN_OUTWARD_DIRECTIONS[rng.randi_range(0, SPAWN_OUTWARD_DIRECTIONS.size() - 1)]


func _sample_spawn_distance(rng: RandomNumberGenerator) -> float:
	if rng == null:
		return 11.0
	return rng.randf_range(
		CombatEnvelope.SPAWN_INNER_HALF_EXTENT,
		CombatEnvelope.SPAWN_OUTER_HALF_EXTENT,
	)


func _should_far_despawn_normal(
	enemy: EnemyEntity,
	player_position: Vector2,
	current_tick: int,
) -> bool:
	if (
		current_tick >= _manifest.boss_start_tick
		or not enemy.alive
		or enemy.is_swarm_event
		or enemy.enemy_type not in NORMAL_ENEMY_TYPES
	):
		return false
	var player_offset: Vector2 = enemy.position - player_position
	return (
		absf(player_offset.dot(SCREEN_RIGHT_WORLD))
		> CombatEnvelope.NORMAL_DESPAWN_HALF_EXTENT
		or absf(player_offset.dot(SCREEN_DOWN_WORLD))
		> CombatEnvelope.NORMAL_DESPAWN_HALF_EXTENT
	)


func _is_enemy_center_inside_arena(position: Vector2, body_radius: float) -> bool:
	var center_limit: float = CombatEnvelope.enemy_center_limit(body_radius)
	return absf(position.x) <= center_limit and absf(position.y) <= center_limit


func _normal_enemy_count() -> int:
	var count: int = 0
	for enemy: EnemyEntity in enemy_store.entities:
		if enemy.enemy_type in NORMAL_ENEMY_TYPES and not enemy.is_swarm_event:
			count += 1
	return count


func _rebuild_grid(current_tick: int) -> void:
	uniform_grid.clear()
	for enemy: EnemyEntity in enemy_store.entities:
		if enemy.is_targetable(current_tick):
			uniform_grid.insert(enemy.entity_id, enemy.position)


func _can_resolve_actions(enemy: EnemyEntity, current_tick: int) -> bool:
	return (
		enemy != null
		and enemy.definition != null
		and enemy.is_targetable(current_tick)
		and _time_scale_for(enemy) > 0.0
	)


func _damage_record(
	enemy: EnemyEntity,
	source_effect_id: StringName,
	raw_damage: float,
	position: Vector2,
) -> Dictionary:
	return {
		"type": ACTION_PLAYER_DAMAGE,
		"source_entity_id": enemy.entity_id,
		"source_effect_id": source_effect_id,
		"raw_damage": raw_damage,
		"position": position,
	}


func _clamp_enemy_center(position: Vector2, body_radius: float) -> Vector2:
	var center_limit: float = CombatEnvelope.enemy_center_limit(body_radius)
	return Vector2(
		clampf(position.x, -center_limit, center_limit),
		clampf(position.y, -center_limit, center_limit),
	)
