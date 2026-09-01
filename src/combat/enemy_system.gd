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
const MAXIMUM_SPAWN_POSITION_TRIALS: int = 16
const MAXIMUM_SPAWNS_PER_TICK: int = 16
const SPAWN_TARGET_RAMP_TICKS: float = 180.0
const BOSS_CHARGE_TICKS: int = CombatEnvelope.BOSS_CHARGE_TICKS
const BOSS_VOLLEY_BASE_COUNT: int = 8
const BOSS_VOLLEY_PHASE_BONUS: int = 4
const BOSS_PHASE_INTERVAL_MULTIPLIER: float = 0.75
const BOSS_MIN_INTERVAL_MULTIPLIER: float = 0.20

const ACTION_PLAYER_DAMAGE: StringName = &"player_damage"
const DAMAGE_SOURCE_CONTACT: StringName = &"enemy_contact"

var enemy_store: EnemyStore = EnemyStore.new()
var uniform_grid: UniformGrid = UniformGrid.new()

var _state: RunState = null
var _catalog: DefinitionCatalog = null
var _manifest: SurvivalContentManifest = null
var _spawn_rng: RandomNumberGenerator = null
var _elite_spawned: PackedByteArray = PackedByteArray()


func initialize(state: RunState, catalog: DefinitionCatalog) -> void:
	_state = state
	_catalog = catalog
	_manifest = catalog.manifest()
	_spawn_rng = state.rng_streams.spawn_rng if state.rng_streams != null else null
	enemy_store.clear()
	uniform_grid.clear()
	_elite_spawned.resize(_manifest.elite_spawn_ticks.size())
	_elite_spawned.fill(0)


func snapshot_ids() -> Array[int]:
	return enemy_store.snapshot_ids_sorted()


func advance_snapshot(
	ids: Array[int],
	player_position: Vector2,
	current_tick: int,
) -> void:
	for entity_id: int in ids:
		var enemy: EnemyEntity = enemy_store.get_by_id(entity_id)
		if enemy == null or not enemy.is_targetable(current_tick):
			continue
		var time_scale: float = _time_scale_for(enemy)
		if time_scale <= 0.0:
			continue
		_move_enemy(enemy, player_position, time_scale)
		_advance_enemy_timers(enemy, time_scale)
		_update_boss_state(enemy)
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
				spawned.append(elite)
	if not _state.boss_spawned and current_tick >= _manifest.boss_start_tick:
		var boss: EnemyEntity = _spawn_enemy(
			GameTypes.EnemyType.BOSS,
			Vector2.ZERO,
			current_tick,
		)
		if boss != null:
			_state.boss_spawned = true
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
			_choose_normal_spawn_position(player_position, enemy_type),
			current_tick,
		)
		if enemy == null:
			break
		spawned.append(enemy)
		_state.spawn_credit = maxf(0.0, _state.spawn_credit - 1.0)
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


func _move_enemy(enemy: EnemyEntity, player_position: Vector2, time_scale: float) -> void:
	var offset: Vector2 = player_position - enemy.position
	var direction: Vector2 = Vector2.ZERO
	if offset != Vector2.ZERO:
		direction = offset.normalized()
	enemy.position = _clamp_enemy_center(
		enemy.position
		+ direction * enemy.definition.move_speed * time_scale / float(RunState.TICKS_PER_SECOND),
		enemy.body_radius(),
	)


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
	var resolved_position: Vector2 = _clamp_enemy_center(position, definition.body_radius)
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


func _choose_normal_spawn_position(
	player_position: Vector2,
	enemy_type: GameTypes.EnemyType,
) -> Vector2:
	var definition: EnemyDefinition = _catalog.enemy(GameTypes.enemy_type_to_key(enemy_type))
	var body_radius: float = definition.body_radius if definition != null else 0.0
	var center_limit: float = CombatEnvelope.enemy_center_limit(body_radius)
	if _spawn_rng == null:
		return _farthest_fallback_corner(player_position, body_radius)
	var minimum_distance_squared: float = (
		CombatEnvelope.NORMAL_SPAWN_MIN_DISTANCE
		* CombatEnvelope.NORMAL_SPAWN_MIN_DISTANCE
	)
	for _trial_index: int in range(MAXIMUM_SPAWN_POSITION_TRIALS):
		var edge: int = _spawn_rng.randi_range(0, 3)
		var coordinate: float = _spawn_rng.randf_range(-center_limit, center_limit)
		var candidate: Vector2
		match edge:
			0:
				candidate = Vector2(-center_limit, coordinate)
			1:
				candidate = Vector2(center_limit, coordinate)
			2:
				candidate = Vector2(coordinate, -center_limit)
			_:
				candidate = Vector2(coordinate, center_limit)
		if candidate.distance_squared_to(player_position) >= minimum_distance_squared:
			return candidate
	return _farthest_fallback_corner(player_position, body_radius)


func _farthest_fallback_corner(player_position: Vector2, body_radius: float) -> Vector2:
	var center_limit: float = CombatEnvelope.enemy_center_limit(body_radius)
	var fallback_corners: Array[Vector2] = [
		Vector2(center_limit, center_limit),
		Vector2(-center_limit, center_limit),
		Vector2(-center_limit, -center_limit),
		Vector2(center_limit, -center_limit),
	]
	var farthest: Vector2 = fallback_corners[0]
	var farthest_distance_squared: float = farthest.distance_squared_to(player_position)
	for index: int in range(1, fallback_corners.size()):
		var candidate: Vector2 = fallback_corners[index]
		var distance_squared: float = candidate.distance_squared_to(player_position)
		if distance_squared > farthest_distance_squared:
			farthest = candidate
			farthest_distance_squared = distance_squared
	return farthest


func _normal_enemy_count() -> int:
	var count: int = 0
	for enemy: EnemyEntity in enemy_store.entities:
		if enemy.enemy_type in NORMAL_ENEMY_TYPES:
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
