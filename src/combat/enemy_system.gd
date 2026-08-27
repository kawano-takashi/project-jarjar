class_name EnemySystem
extends RefCounted


const NORMAL_ENEMY_TYPES: Array[GameTypes.EnemyType] = [
	GameTypes.EnemyType.ARMORED,
	GameTypes.EnemyType.FAST,
	GameTypes.EnemyType.RANGED,
	GameTypes.EnemyType.TRACKER,
]
const NORMAL_ENEMY_IDS: Array[StringName] = [
	&"armored",
	&"fast",
	&"ranged",
	&"tracker",
]
const ARENA_SPAWN_MIN: Vector2 = Vector2(-14.25, -8.25)
const ARENA_SPAWN_MAX: Vector2 = Vector2(14.25, 8.25)
const FALLBACK_CORNERS: Array[Vector2] = [
	Vector2(14.25, 8.25),
	Vector2(-14.25, 8.25),
	Vector2(-14.25, -8.25),
	Vector2(14.25, -8.25),
]
const PLAYER_BODY_RADIUS: float = 0.45
const MINIMUM_NORMAL_SPAWN_DISTANCE: float = 8.0
const MAXIMUM_SPAWN_POSITION_TRIALS: int = 16
const MAXIMUM_SPAWN_CREDIT: float = 8.0
const MAXIMUM_NON_BOSS_BEFORE_BOSS_DEFEAT: int = 299
const BOSS_SUMMON_RADIUS: float = 2.0
const BOSS_VOLLEY_STEP_DEGREES: float = 30.0
const BOSS_VOLLEY_ALTERNATE_DEGREES: float = 15.0

const ACTION_PLAYER_DAMAGE: StringName = &"player_damage"
const DAMAGE_SOURCE_CONTACT: StringName = &"enemy_contact"
const DAMAGE_SOURCE_ELITE_AREA: StringName = &"elite_area"

var enemy_store: EnemyStore = EnemyStore.new()
var uniform_grid: UniformGrid = UniformGrid.new()

var _state: RunState = null
var _catalog: DefinitionCatalog = null
var _wave: WaveDefinition = null
var _rng_source: Object = null
var _elite_spawned: bool = false


func initialize(
	state: RunState,
	catalog: DefinitionCatalog,
	wave: WaveDefinition,
	rng_source: Variant = null,
) -> void:
	_state = state
	_catalog = catalog
	_wave = wave
	_rng_source = rng_source as Object
	if _rng_source == null and _state != null and _state.rng_streams != null:
		_rng_source = _state.rng_streams.combat_rng
	_elite_spawned = false
	enemy_store.clear()
	uniform_grid.clear()
	if _wave != null and _wave.boss_at_start:
		_spawn_boss_at_wave_start()


func snapshot_ids() -> Array[int]:
	return enemy_store.snapshot_ids_sorted()


func advance_snapshot(
	ids: Array[int],
	player_position: Vector2,
	delta: float,
	current_tick: int,
) -> void:
	for entity_id: int in ids:
		var enemy: EnemyEntity = enemy_store.get_by_id(entity_id)
		if enemy == null or not enemy.is_targetable(current_tick):
			continue
		_move_enemy(enemy, player_position, delta)
		_advance_enemy_timers(enemy, delta)

	uniform_grid.clear()
	for entity_id: int in ids:
		var enemy: EnemyEntity = enemy_store.get_by_id(entity_id)
		if enemy == null or not enemy.is_targetable(current_tick):
			continue
		uniform_grid.insert(enemy.entity_id, enemy.position)


func accrue_spawn_credit(delta: float) -> void:
	if _state == null or _wave == null or _wave.duration_seconds <= 0.0:
		return
	var elapsed_at_tick_start: float = _wave.duration_seconds - _state.time_remaining
	var progress: float = clampf(elapsed_at_tick_start / _wave.duration_seconds, 0.0, 1.0)
	var current_spawn_rate: float = lerpf(
		_wave.spawn_rate_start,
		_wave.spawn_rate_end,
		progress,
	)
	_state.spawn_credit = minf(
		MAXIMUM_SPAWN_CREDIT,
		_state.spawn_credit + current_spawn_rate * delta,
	)


func resolve_ready_boss_summons(
	ids: Array[int],
	_player_position: Vector2,
	current_tick: int,
) -> Array[EnemyEntity]:
	var spawned: Array[EnemyEntity] = []
	if _state == null or _wave == null:
		return spawned
	for entity_id: int in ids:
		var boss: EnemyEntity = enemy_store.get_by_id(entity_id)
		if (
			boss == null
			or boss.enemy_type != GameTypes.EnemyType.BOSS
			or not boss.is_targetable(current_tick)
			or boss.definition == null
			or boss.definition.summon_interval <= 0.0
			or not TimerMath.is_ready(boss.summon_elapsed, boss.definition.summon_interval)
		):
			continue

		boss.summon_elapsed = 0.0
		var available_count: int = enemy_store.free_count()
		if _wave.wave_number == 8 and not _state.boss_defeated:
			available_count = mini(
				available_count,
				maxi(0, MAXIMUM_NON_BOSS_BEFORE_BOSS_DEFEAT - _state.non_boss_spawned),
			)
		var spawn_count: int = mini(boss.definition.summon_count, available_count)
		if spawn_count <= 0:
			continue

		var start_angle: float = _rng_randf_range(0.0, TAU)
		for slot_index: int in range(spawn_count):
			var enemy_type: GameTypes.EnemyType = _select_normal_enemy_type()
			var definition: EnemyDefinition = _definition_for_type(enemy_type)
			if definition == null:
				continue
			var angle: float = start_angle + TAU * float(slot_index) / float(spawn_count)
			var position: Vector2 = _clamp_enemy_center(
				boss.position + Vector2(cos(angle), sin(angle)) * BOSS_SUMMON_RADIUS
			)
			var summoned: EnemyEntity = enemy_store.try_spawn(
				_state,
				enemy_type,
				definition,
				position,
				_wave.hp_multiplier,
				_wave.damage_multiplier,
				current_tick,
				true,
			)
			if summoned == null:
				break
			spawned.append(summoned)
			if _wave.wave_number == 8:
				_state.non_boss_spawned += 1
	return spawned


func resolve_normal_spawns(
	player_position: Vector2,
	current_tick: int,
) -> Array[EnemyEntity]:
	var spawned: Array[EnemyEntity] = []
	if _state == null or _wave == null:
		return spawned
	while _state.spawn_credit >= 1.0:
		if _normal_spawn_is_blocked_by_boss_gate():
			break
		if enemy_store.free_count() <= 0:
			enemy_store.record_overflow()
			break

		var enemy_type: GameTypes.EnemyType = _select_normal_enemy_type()
		var definition: EnemyDefinition = _definition_for_type(enemy_type)
		if definition == null:
			break
		var spawn_position: Vector2 = _choose_normal_spawn_position(player_position)
		var enemy: EnemyEntity = enemy_store.try_spawn(
			_state,
			enemy_type,
			definition,
			spawn_position,
			_wave.hp_multiplier,
			_wave.damage_multiplier,
			current_tick,
		)
		if enemy == null:
			break
		spawned.append(enemy)
		_state.spawn_credit = maxf(0.0, _state.spawn_credit - 1.0)
		if _wave.wave_number == 8:
			_state.non_boss_spawned += 1
	return spawned


func resolve_w4_elite_after_countdown(
	player_position: Vector2,
	current_tick: int,
) -> EnemyEntity:
	if (
		_state == null
		or _wave == null
		or _state.phase != GameTypes.RunPhase.COMBAT
		or _elite_spawned
	):
		return null
	if _wave.elite_spawn_elapsed < 0.0:
		return null
	var elapsed: float = _wave.duration_seconds - _state.time_remaining
	if elapsed < _wave.elite_spawn_elapsed - TimerMath.TIME_EPSILON_SECONDS:
		return null
	_elite_spawned = true
	var definition: EnemyDefinition = _catalog.enemy(&"elite")
	if definition == null:
		return null
	return enemy_store.try_spawn(
		_state,
		GameTypes.EnemyType.ELITE,
		definition,
		_farthest_fallback_corner(player_position),
		1.0,
		1.0,
		current_tick,
	)


func resolve_ready_enemy_actions(
	ids: Array[int],
	player_position: Vector2,
	current_tick: int,
	projectile_pool: ProjectilePool,
) -> Array[Dictionary]:
	var damage_records: Array[Dictionary] = resolve_ready_enemy_damage_actions(
		ids,
		player_position,
		current_tick,
	)
	resolve_ready_enemy_special_actions(
		ids,
		player_position,
		current_tick,
		projectile_pool,
	)
	return damage_records


func resolve_ready_enemy_damage_actions(
	ids: Array[int],
	player_position: Vector2,
	current_tick: int,
) -> Array[Dictionary]:
	var damage_records: Array[Dictionary] = []

	# Completed ELITE telegraphs resolve before every contact action.
	for entity_id: int in ids:
		var enemy: EnemyEntity = enemy_store.get_by_id(entity_id)
		if not _can_resolve_actions(enemy, current_tick):
			continue
		if (
			enemy.enemy_type == GameTypes.EnemyType.ELITE
			and enemy.telegraph_active
			and TimerMath.is_ready(enemy.telegraph_elapsed, enemy.definition.telegraph_seconds)
		):
			if (
				player_position.distance_squared_to(enemy.telegraph_position)
				<= enemy.definition.area_radius * enemy.definition.area_radius
			):
				damage_records.append(_damage_record(
					enemy,
					DAMAGE_SOURCE_ELITE_AREA,
					enemy.definition.projectile_damage * enemy.damage_multiplier,
					enemy.telegraph_position,
				))
			enemy.telegraph_active = false
			enemy.telegraph_elapsed = 0.0

	# Contact timers remain full while separated and reset only on a contact hit.
	for entity_id: int in ids:
		var enemy: EnemyEntity = enemy_store.get_by_id(entity_id)
		if not _can_resolve_actions(enemy, current_tick):
			continue
		var contact_radius: float = PLAYER_BODY_RADIUS + enemy.definition.body_radius
		if (
			TimerMath.is_ready(enemy.contact_elapsed, enemy.definition.contact_interval)
			and enemy.position.distance_squared_to(player_position)
			<= contact_radius * contact_radius
		):
			damage_records.append(_damage_record(
				enemy,
				DAMAGE_SOURCE_CONTACT,
				enemy.definition.contact_damage * enemy.damage_multiplier,
				enemy.position,
			))
			enemy.contact_elapsed = 0.0

	return damage_records


func resolve_ready_enemy_special_actions(
	ids: Array[int],
	player_position: Vector2,
	current_tick: int,
	projectile_pool: ProjectilePool,
) -> void:
	# Non-summon special actions are generated last in source entity_id order.
	for entity_id: int in ids:
		var enemy: EnemyEntity = enemy_store.get_by_id(entity_id)
		if not _can_resolve_actions(enemy, current_tick):
			continue
		match enemy.enemy_type:
			GameTypes.EnemyType.ELITE:
				_start_ready_elite_telegraph(enemy, player_position)
			GameTypes.EnemyType.RANGED:
				_fire_ready_ranged_projectile(enemy, player_position, current_tick, projectile_pool)
			GameTypes.EnemyType.BOSS:
				_fire_ready_boss_volley(enemy, current_tick, projectile_pool)


func _move_enemy(enemy: EnemyEntity, player_position: Vector2, delta: float) -> void:
	var offset: Vector2 = player_position - enemy.position
	var movement_direction: Vector2 = Vector2.ZERO
	if enemy.enemy_type == GameTypes.EnemyType.RANGED:
		var distance: float = offset.length()
		if distance > enemy.definition.preferred_distance_max:
			movement_direction = offset.normalized()
		elif distance < enemy.definition.preferred_distance_min and distance > 0.0:
			movement_direction = -offset.normalized()
	elif offset != Vector2.ZERO:
		movement_direction = offset.normalized()
	enemy.position = _clamp_enemy_center(
		enemy.position + movement_direction * enemy.definition.move_speed * delta
	)


func _advance_enemy_timers(enemy: EnemyEntity, delta: float) -> void:
	enemy.contact_elapsed = TimerMath.advance_clamped(
		enemy.contact_elapsed,
		enemy.definition.contact_interval,
		delta,
	)
	if enemy.definition.special_interval > 0.0:
		enemy.special_elapsed = TimerMath.advance_clamped(
			enemy.special_elapsed,
			enemy.definition.special_interval,
			delta,
		)
	if enemy.definition.summon_interval > 0.0:
		enemy.summon_elapsed = TimerMath.advance_clamped(
			enemy.summon_elapsed,
			enemy.definition.summon_interval,
			delta,
		)
	if enemy.telegraph_active and enemy.definition.telegraph_seconds > 0.0:
		enemy.telegraph_elapsed = TimerMath.advance_clamped(
			enemy.telegraph_elapsed,
			enemy.definition.telegraph_seconds,
			delta,
		)


func _start_ready_elite_telegraph(enemy: EnemyEntity, player_position: Vector2) -> void:
	if (
		enemy.telegraph_active
		or enemy.definition.special_interval <= 0.0
		or not TimerMath.is_ready(enemy.special_elapsed, enemy.definition.special_interval)
	):
		return
	enemy.special_elapsed = 0.0
	enemy.telegraph_active = true
	enemy.telegraph_elapsed = 0.0
	enemy.telegraph_position = player_position


func _fire_ready_ranged_projectile(
	enemy: EnemyEntity,
	player_position: Vector2,
	current_tick: int,
	projectile_pool: ProjectilePool,
) -> void:
	if (
		enemy.definition.special_interval <= 0.0
		or not TimerMath.is_ready(enemy.special_elapsed, enemy.definition.special_interval)
	):
		return
	enemy.special_elapsed = 0.0
	var direction: Vector2 = (player_position - enemy.position).normalized()
	projectile_pool.acquire(
		ProjectileState.FACTION_ENEMY,
		enemy.definition.enemy_id,
		enemy.entity_id,
		enemy.position,
		direction * enemy.definition.projectile_speed,
		enemy.definition.projectile_radius,
		enemy.definition.projectile_damage * enemy.damage_multiplier,
		enemy.definition.projectile_speed * enemy.definition.projectile_lifetime,
		enemy.definition.projectile_lifetime,
		player_position,
		0,
		current_tick,
	)


func _fire_ready_boss_volley(
	enemy: EnemyEntity,
	current_tick: int,
	projectile_pool: ProjectilePool,
) -> void:
	if (
		enemy.definition.special_interval <= 0.0
		or not TimerMath.is_ready(enemy.special_elapsed, enemy.definition.special_interval)
	):
		return
	enemy.special_elapsed = 0.0
	var offset_degrees: float = BOSS_VOLLEY_ALTERNATE_DEGREES if enemy.barrage_alternate else 0.0
	for angle_index: int in range(enemy.definition.volley_count):
		var angle: float = deg_to_rad(offset_degrees + BOSS_VOLLEY_STEP_DEGREES * angle_index)
		var direction := Vector2(cos(angle), sin(angle))
		projectile_pool.acquire(
			ProjectileState.FACTION_ENEMY,
			enemy.definition.enemy_id,
			enemy.entity_id,
			enemy.position,
			direction * enemy.definition.projectile_speed,
			enemy.definition.projectile_radius,
			enemy.definition.projectile_damage * enemy.damage_multiplier,
			enemy.definition.projectile_speed * enemy.definition.projectile_lifetime,
			enemy.definition.projectile_lifetime,
			enemy.position + direction * enemy.definition.projectile_speed * enemy.definition.projectile_lifetime,
			0,
			current_tick,
		)
	enemy.barrage_alternate = not enemy.barrage_alternate


func _can_resolve_actions(enemy: EnemyEntity, current_tick: int) -> bool:
	return (
		enemy != null
		and enemy.definition != null
		and enemy.is_targetable(current_tick)
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


func _select_normal_enemy_type() -> GameTypes.EnemyType:
	var weights := PackedFloat64Array()
	weights.resize(NORMAL_ENEMY_TYPES.size())
	for index: int in range(NORMAL_ENEMY_TYPES.size()):
		weights[index] = float(_wave.enemy_weights.get(NORMAL_ENEMY_TYPES[index], 0.0))
	var selected_id: StringName = WeightedSelector.select_with_value(
		NORMAL_ENEMY_IDS,
		weights,
		_rng_randf(),
	)
	var selected_index: int = NORMAL_ENEMY_IDS.find(selected_id)
	return NORMAL_ENEMY_TYPES[maxi(0, selected_index)]


func _choose_normal_spawn_position(player_position: Vector2) -> Vector2:
	var minimum_distance_squared: float = (
		MINIMUM_NORMAL_SPAWN_DISTANCE * MINIMUM_NORMAL_SPAWN_DISTANCE
	)
	for _trial_index: int in range(MAXIMUM_SPAWN_POSITION_TRIALS):
		var edge: int = _rng_randi_range(0, 3)
		var coordinate: float = _rng_randf()
		var candidate: Vector2
		match edge:
			0:
				candidate = Vector2(
					ARENA_SPAWN_MIN.x,
					lerpf(ARENA_SPAWN_MIN.y, ARENA_SPAWN_MAX.y, coordinate),
				)
			1:
				candidate = Vector2(
					ARENA_SPAWN_MAX.x,
					lerpf(ARENA_SPAWN_MIN.y, ARENA_SPAWN_MAX.y, coordinate),
				)
			2:
				candidate = Vector2(
					lerpf(ARENA_SPAWN_MIN.x, ARENA_SPAWN_MAX.x, coordinate),
					ARENA_SPAWN_MIN.y,
				)
			_:
				candidate = Vector2(
					lerpf(ARENA_SPAWN_MIN.x, ARENA_SPAWN_MAX.x, coordinate),
					ARENA_SPAWN_MAX.y,
				)
		if candidate.distance_squared_to(player_position) >= minimum_distance_squared:
			return candidate
	return _farthest_fallback_corner(player_position)


func _farthest_fallback_corner(player_position: Vector2) -> Vector2:
	var farthest: Vector2 = FALLBACK_CORNERS[0]
	var farthest_distance_squared: float = farthest.distance_squared_to(player_position)
	for index: int in range(1, FALLBACK_CORNERS.size()):
		var candidate: Vector2 = FALLBACK_CORNERS[index]
		var distance_squared: float = candidate.distance_squared_to(player_position)
		if distance_squared > farthest_distance_squared:
			farthest = candidate
			farthest_distance_squared = distance_squared
	return farthest


func _normal_spawn_is_blocked_by_boss_gate() -> bool:
	return (
		_wave.wave_number == 8
		and not _state.boss_defeated
		and _state.non_boss_spawned >= MAXIMUM_NON_BOSS_BEFORE_BOSS_DEFEAT
	)


func _spawn_boss_at_wave_start() -> EnemyEntity:
	var definition: EnemyDefinition = _catalog.enemy(&"boss")
	if definition == null:
		return null
	return enemy_store.try_spawn(
		_state,
		GameTypes.EnemyType.BOSS,
		definition,
		FALLBACK_CORNERS[0],
		1.0,
		1.0,
		_state.physics_tick,
	)


func _definition_for_type(enemy_type: GameTypes.EnemyType) -> EnemyDefinition:
	return _catalog.enemy(GameTypes.enemy_type_to_key(enemy_type))


func _clamp_enemy_center(position: Vector2) -> Vector2:
	return Vector2(
		clampf(position.x, UniformGrid.ARENA_MIN.x, UniformGrid.ARENA_MAX.x),
		clampf(position.y, UniformGrid.ARENA_MIN.y, UniformGrid.ARENA_MAX.y),
	)


func _rng_randf() -> float:
	return float(_rng_source.call(&"randf"))


func _rng_randf_range(minimum: float, maximum: float) -> float:
	return float(_rng_source.call(&"randf_range", minimum, maximum))


func _rng_randi_range(minimum: int, maximum: int) -> int:
	return int(_rng_source.call(&"randi_range", minimum, maximum))
