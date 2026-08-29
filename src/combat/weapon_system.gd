class_name WeaponSystem
extends RefCounted


const MAX_ENEMY_BODY_RADIUS: float = 1.25
const PLAYER_BODY_RADIUS: float = 0.45
const WOOD_STICK_ID: StringName = &"wood_stick"
const BOW_ID: StringName = &"bow"
const STAFF_ID: StringName = &"staff"
const SWORD_ID: StringName = &"sword"

var attack_elapsed: float = 0.0
var last_attack_direction: Vector2 = Vector2.RIGHT

var _state: RunState = null
var _catalog: DefinitionCatalog = null
var _projectile_pool: ProjectilePool = null
var _router: CombatEventRouter = null


func initialize(
	state: RunState,
	catalog: DefinitionCatalog,
	projectile_pool: ProjectilePool,
	router: CombatEventRouter,
) -> void:
	_state = state
	_catalog = catalog
	_projectile_pool = projectile_pool
	_router = router
	attack_elapsed = effective_interval()


func current_weapon_id() -> StringName:
	var item: ItemInstance = _state.equipped.get(
		GameTypes.EquipmentSlot.MAIN_WEAPON,
		null,
	) as ItemInstance
	if item == null:
		return WOOD_STICK_ID
	match item.main_weapon_type:
		GameTypes.MainWeaponType.BOW:
			return BOW_ID
		GameTypes.MainWeaponType.STAFF:
			return STAFF_ID
		GameTypes.MainWeaponType.SWORD:
			return SWORD_ID
	return WOOD_STICK_ID


func current_definition() -> WeaponDefinition:
	return _catalog.weapon(current_weapon_id())


func effective_interval(coward_stationary_active: bool = false) -> float:
	if _state == null or _catalog == null:
		return 0.8
	var definition: WeaponDefinition = current_definition()
	var stats: Dictionary = StatCalculator.aggregate_affixes(_state.equipped)
	var unique_ids: Array[StringName] = StatCalculator.equipped_unique_ids(_state.equipped)
	return StatCalculator.effective_attack_interval(
		definition.base_interval,
		definition.main_weapon_type,
		stats,
		unique_ids,
		_state.wave_kills,
		coward_stationary_active,
	)


func effective_damage(coward_stationary_active: bool = false) -> float:
	var definition: WeaponDefinition = current_definition()
	var stats: Dictionary = StatCalculator.aggregate_affixes(_state.equipped)
	var unique_ids: Array[StringName] = StatCalculator.equipped_unique_ids(_state.equipped)
	return definition.base_damage * StatCalculator.damage_multiplier(
		stats,
		unique_ids,
		false,
		coward_stationary_active,
	)


func advance_attack_timer(delta: float, coward_stationary_active: bool = false) -> void:
	var interval: float = effective_interval(coward_stationary_active)
	attack_elapsed = TimerMath.advance_clamped(attack_elapsed, interval, delta)


func is_attack_ready(coward_stationary_active: bool = false) -> bool:
	return TimerMath.is_ready(
		attack_elapsed,
		effective_interval(coward_stationary_active),
	)


func try_primary_attack(
	player_position: Vector2,
	enemy_store: EnemyStore,
	grid: UniformGrid,
	current_tick: int,
) -> Array[Dictionary]:
	var result: Dictionary = try_primary_attack_detailed(
		player_position,
		enemy_store,
		grid,
		current_tick,
	)
	var hits: Array[Dictionary] = []
	hits.assign(result.get("hits", []))
	return hits


func try_primary_attack_detailed(
	player_position: Vector2,
	enemy_store: EnemyStore,
	grid: UniformGrid,
	current_tick: int,
	coward_stationary_active: bool = false,
	damage_override: float = -1.0,
) -> Dictionary:
	var hits: Array[Dictionary] = []
	var result: Dictionary = {
		"generated": false,
		"weapon_id": &"",
		"origin": player_position,
		"source_effect_id": &"",
		"damage_snapshot": 0.0,
		"direction": Vector2.ZERO,
		"range_m": 0.0,
		"aim_distance": 0.0,
		"target_entity_id": -1,
		"hits": hits,
	}
	if not is_attack_ready(coward_stationary_active):
		return result
	var definition: WeaponDefinition = current_definition()
	result["weapon_id"] = definition.weapon_id
	result["range_m"] = definition.range_m
	var target: EnemyEntity = _nearest_target(
		player_position,
		definition.range_m,
		enemy_store,
		grid,
		current_tick,
	)
	if target == null:
		return result
	var direction: Vector2 = (target.position - player_position).normalized()
	if direction == Vector2.ZERO:
		direction = last_attack_direction
	last_attack_direction = direction
	attack_elapsed = 0.0
	var damage: float = (
		damage_override
		if damage_override >= 0.0
		else effective_damage(coward_stationary_active)
	)
	var source_effect_id := StringName("weapon:%s" % definition.weapon_id)
	var aim_distance: float = player_position.distance_to(target.position)
	var generated: bool = false
	match definition.weapon_id:
		WOOD_STICK_ID:
			var event: CombatEvent = _router.create_primary(
				_state,
				&"damage",
				-1,
				source_effect_id,
				damage,
				player_position,
				direction,
			)
			hits.append({"entity_id": target.entity_id, "event": event})
			generated = true
		BOW_ID:
			var stats: Dictionary = StatCalculator.aggregate_affixes(_state.equipped)
			var hit_count: int = 1 + maxi(0, StatCalculator.effective_pierce(stats))
			var projectile: ProjectileState = _projectile_pool.acquire(
				ProjectileState.FACTION_ALLY,
				definition.weapon_id,
				-1,
				player_position,
				direction * definition.projectile_speed,
				definition.projectile_radius,
				damage,
				definition.range_m,
				definition.range_m / definition.projectile_speed,
				target.position,
				hit_count,
				current_tick,
				source_effect_id,
				&"",
				true,
				PackedStringArray(),
			)
			generated = projectile != null
		STAFF_ID:
			var projectile: ProjectileState = _projectile_pool.acquire(
				ProjectileState.FACTION_ALLY,
				definition.weapon_id,
				-1,
				player_position,
				direction * definition.projectile_speed,
				definition.projectile_radius,
				damage,
				definition.range_m,
				definition.range_m / definition.projectile_speed,
				target.position,
				1,
				current_tick,
				source_effect_id,
				&"",
				true,
				PackedStringArray(),
			)
			generated = projectile != null
		SWORD_ID:
			var event: CombatEvent = _router.create_primary(
				_state,
				&"damage",
				-1,
				source_effect_id,
				damage,
				player_position,
				direction,
			)
			var candidates: Array[int] = grid.query_circle_candidates(
				player_position,
				definition.range_m,
				MAX_ENEMY_BODY_RADIUS,
			)
			candidates.sort()
			for entity_id: int in candidates:
				var enemy: EnemyEntity = enemy_store.get_by_id(entity_id)
				if enemy == null or not enemy.is_targetable(current_tick):
					continue
				if CombatGeometry.point_in_fan(
					player_position,
					direction,
					definition.range_m,
					definition.arc_degrees,
					enemy.position,
					enemy.body_radius(),
				):
					hits.append({"entity_id": entity_id, "event": event})
			generated = true
	result["generated"] = generated
	result["source_effect_id"] = source_effect_id
	result["damage_snapshot"] = damage
	result["direction"] = direction
	result["aim_distance"] = aim_distance
	result["target_entity_id"] = target.entity_id
	result["hits"] = hits
	return result


func replay_weapon(
	replay: ScheduledProcReplay,
	player_position: Vector2,
	enemy_store: EnemyStore,
	grid: UniformGrid,
	current_tick: int,
) -> Dictionary:
	var hits: Array[Dictionary] = []
	var result: Dictionary = {
		"generated": false,
		"weapon_id": &"",
		"origin": player_position,
		"direction": Vector2.ZERO,
		"range_m": 0.0,
		"event": null,
		"hits": hits,
	}
	if (
		replay == null
		or replay.proc_effect_id.is_empty()
		or not String(replay.source_effect_id).begins_with("weapon:")
	):
		return result
	var weapon_id := StringName(String(replay.source_effect_id).trim_prefix("weapon:"))
	var definition: WeaponDefinition = _catalog.weapon(weapon_id)
	if definition == null:
		return result
	var direction: Vector2 = replay.direction.normalized()
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT
	result["weapon_id"] = weapon_id
	result["direction"] = direction
	result["range_m"] = definition.range_m
	match weapon_id:
		WOOD_STICK_ID:
			var target: EnemyEntity = enemy_store.get_by_id(replay.target_entity_id)
			if (
				target == null
				or not target.is_targetable(current_tick)
				or player_position.distance_to(target.position) > definition.range_m
			):
				return result
			var event: CombatEvent = _materialize_replay_event(
				replay,
				player_position,
				direction,
			)
			if event == null:
				return result
			hits.append({"entity_id": target.entity_id, "event": event})
			result["event"] = event
			result["generated"] = true
		BOW_ID:
			var stats: Dictionary = StatCalculator.aggregate_affixes(_state.equipped)
			var hit_count: int = 1 + maxi(0, StatCalculator.effective_pierce(stats))
			var projectile: ProjectileState = _projectile_pool.acquire(
				ProjectileState.FACTION_ALLY,
				weapon_id,
				-1,
				player_position,
				direction * definition.projectile_speed,
				definition.projectile_radius,
				replay.damage_snapshot,
				definition.range_m,
				definition.range_m / definition.projectile_speed,
				player_position + direction * definition.range_m,
				hit_count,
				current_tick,
				replay.source_effect_id,
				replay.proc_effect_id,
				false,
				replay.inherited_effect_chain,
			)
			result["generated"] = projectile != null
		STAFF_ID:
			var aim_distance: float = clampf(replay.aim_distance, 0.0, definition.range_m)
			var projectile: ProjectileState = _projectile_pool.acquire(
				ProjectileState.FACTION_ALLY,
				weapon_id,
				-1,
				player_position,
				direction * definition.projectile_speed,
				definition.projectile_radius,
				replay.damage_snapshot,
				definition.range_m,
				definition.range_m / definition.projectile_speed,
				player_position + direction * aim_distance,
				1,
				current_tick,
				replay.source_effect_id,
				replay.proc_effect_id,
				false,
				replay.inherited_effect_chain,
			)
			result["generated"] = projectile != null
		SWORD_ID:
			var event: CombatEvent = _materialize_replay_event(
				replay,
				player_position,
				direction,
			)
			if event == null:
				return result
			var candidates: Array[int] = grid.query_circle_candidates(
				player_position,
				definition.range_m,
				MAX_ENEMY_BODY_RADIUS,
			)
			candidates.sort()
			for entity_id: int in candidates:
				var enemy: EnemyEntity = enemy_store.get_by_id(entity_id)
				if enemy == null or not enemy.is_targetable(current_tick):
					continue
				if CombatGeometry.point_in_fan(
					player_position,
					direction,
					definition.range_m,
					definition.arc_degrees,
					enemy.position,
					enemy.body_radius(),
				):
					hits.append({"entity_id": entity_id, "event": event})
			result["event"] = event
			result["generated"] = true
	result["hits"] = hits
	return result


func move_snapshot_projectiles(
	snapshot: Array[Vector2i],
	delta: float,
	current_tick: int,
) -> void:
	for entry: Vector2i in snapshot:
		var projectile: ProjectileState = _projectile_pool.resolve_snapshot_entry(entry)
		if projectile == null or projectile.born_physics_tick >= current_tick:
			continue
		projectile.previous_position = projectile.position
		projectile.previous_remaining_distance = projectile.remaining_distance
		var requested_distance: float = projectile.velocity.length() * delta
		var travel_distance: float = requested_distance
		if projectile.remaining_distance > 0.0:
			travel_distance = minf(requested_distance, projectile.remaining_distance)
		var direction: Vector2 = projectile.velocity.normalized()
		projectile.position += direction * travel_distance
		if projectile.remaining_distance > 0.0:
			projectile.remaining_distance = maxf(0.0, projectile.remaining_distance - travel_distance)
		projectile.remaining_lifetime = maxf(0.0, projectile.remaining_lifetime - delta)


func resolve_ally_projectile(
	entry: Vector2i,
	enemy_store: EnemyStore,
	grid: UniformGrid,
	current_tick: int,
) -> Array[Dictionary]:
	var projectile: ProjectileState = _projectile_pool.resolve_snapshot_entry(entry)
	if (
		projectile == null
		or projectile.faction != ProjectileState.FACTION_ALLY
		or projectile.born_physics_tick >= current_tick
	):
		return []
	if projectile.weapon_id == BOW_ID:
		return _resolve_bow(projectile, enemy_store, grid, current_tick)
	if projectile.weapon_id == STAFF_ID:
		return _resolve_staff(projectile, enemy_store, grid, current_tick)
	return []


func resolve_enemy_projectiles(
	snapshot: Array[Vector2i],
	player_position: Vector2,
	current_tick: int,
) -> Array[Dictionary]:
	var hits: Array[Dictionary] = []
	for entry: Vector2i in snapshot:
		var projectile: ProjectileState = _projectile_pool.resolve_snapshot_entry(entry)
		if (
			projectile == null
			or projectile.faction != ProjectileState.FACTION_ENEMY
			or projectile.born_physics_tick >= current_tick
		):
			continue
		var hit_t: float = CombatGeometry.segment_circle_first_t(
			projectile.previous_position,
			projectile.position,
			player_position,
			projectile.radius + PLAYER_BODY_RADIUS,
		)
		if hit_t >= 0.0:
			hits.append({
				"damage": projectile.damage,
				"source_entity_id": projectile.source_entity_id,
				"pool_index": projectile.pool_index,
			})
			_projectile_pool.release(projectile.pool_index, projectile.generation)
		elif projectile.remaining_lifetime <= 0.0 or projectile.remaining_distance <= 0.0:
			_projectile_pool.release(projectile.pool_index, projectile.generation)
	return hits


func _resolve_bow(
	projectile: ProjectileState,
	enemy_store: EnemyStore,
	grid: UniformGrid,
	current_tick: int,
) -> Array[Dictionary]:
	var hits: Array[Dictionary] = []
	var intersections: Array[Dictionary] = []
	var candidates: Array[int] = grid.query_segment_candidates(
		projectile.previous_position,
		projectile.position,
		projectile.radius + MAX_ENEMY_BODY_RADIUS,
	)
	for entity_id: int in candidates:
		if projectile.hit_entity_ids.has(entity_id):
			continue
		var enemy: EnemyEntity = enemy_store.get_by_id(entity_id)
		if enemy == null or not enemy.is_targetable(current_tick):
			continue
		var hit_t: float = CombatGeometry.segment_circle_first_t(
			projectile.previous_position,
			projectile.position,
			enemy.position,
			projectile.radius + enemy.body_radius(),
		)
		if hit_t >= 0.0:
			intersections.append({"entity_id": entity_id, "t": hit_t})
	intersections.sort_custom(_intersection_less)
	for intersection: Dictionary in intersections:
		if projectile.pierce_remaining <= 0:
			break
		var entity_id: int = int(intersection["entity_id"])
		projectile.hit_entity_ids[entity_id] = true
		projectile.pierce_remaining -= 1
		hits.append(_projectile_damage_record(
			entity_id,
			projectile,
			projectile.previous_position.lerp(projectile.position, float(intersection["t"])),
			projectile.velocity.normalized(),
		))
	if projectile.pierce_remaining <= 0 or projectile.remaining_distance <= 0.0:
		_projectile_pool.release(projectile.pool_index, projectile.generation)
	return hits


func _resolve_staff(
	projectile: ProjectileState,
	enemy_store: EnemyStore,
	grid: UniformGrid,
	current_tick: int,
) -> Array[Dictionary]:
	var first_enemy_t: float = -1.0
	var first_enemy_id: int = -1
	var candidates: Array[int] = grid.query_segment_candidates(
		projectile.previous_position,
		projectile.position,
		projectile.radius + MAX_ENEMY_BODY_RADIUS,
	)
	for entity_id: int in candidates:
		var enemy: EnemyEntity = enemy_store.get_by_id(entity_id)
		if enemy == null or not enemy.is_targetable(current_tick):
			continue
		var hit_t: float = CombatGeometry.segment_circle_first_t(
			projectile.previous_position,
			projectile.position,
			enemy.position,
			projectile.radius + enemy.body_radius(),
		)
		if hit_t < 0.0:
			continue
		if first_enemy_t < 0.0 or hit_t < first_enemy_t or (
			hit_t == first_enemy_t and entity_id < first_enemy_id
		):
			first_enemy_t = hit_t
			first_enemy_id = entity_id
	var target_t: float = _point_on_segment_t(
		projectile.previous_position,
		projectile.position,
		projectile.target_position,
	)
	var explosion_t: float = -1.0
	if first_enemy_t >= 0.0 and (target_t < 0.0 or first_enemy_t <= target_t):
		explosion_t = first_enemy_t
	elif target_t >= 0.0:
		explosion_t = target_t
	elif projectile.remaining_distance <= 0.0:
		explosion_t = 1.0
	if explosion_t < 0.0:
		return []
	var center: Vector2 = projectile.previous_position.lerp(projectile.position, explosion_t)
	var definition: WeaponDefinition = _catalog.weapon(STAFF_ID)
	var stats: Dictionary = StatCalculator.aggregate_affixes(_state.equipped)
	var effect_radius: float = definition.aoe_radius * StatCalculator.effective_area_multiplier(stats)
	var explosion_candidates: Array[int] = grid.query_circle_candidates(
		center,
		effect_radius,
		MAX_ENEMY_BODY_RADIUS,
	)
	explosion_candidates.sort()
	var hits: Array[Dictionary] = []
	for entity_id: int in explosion_candidates:
		var enemy: EnemyEntity = enemy_store.get_by_id(entity_id)
		if enemy == null or not enemy.is_targetable(current_tick):
			continue
		if CombatGeometry.circle_intersects(center, effect_radius, enemy.position, enemy.body_radius()):
			hits.append(_projectile_damage_record(
				entity_id,
				projectile,
				center,
				projectile.velocity.normalized(),
			))
	_projectile_pool.release(projectile.pool_index, projectile.generation)
	return hits


func _nearest_target(
	player_position: Vector2,
	range_m: float,
	enemy_store: EnemyStore,
	grid: UniformGrid,
	current_tick: int,
) -> EnemyEntity:
	var candidates: Array[int] = grid.query_circle_candidates(
		player_position,
		range_m,
		MAX_ENEMY_BODY_RADIUS,
	)
	var best: EnemyEntity = null
	var best_distance_squared: float = INF
	for entity_id: int in candidates:
		var enemy: EnemyEntity = enemy_store.get_by_id(entity_id)
		if enemy == null or not enemy.is_targetable(current_tick):
			continue
		var distance_squared: float = player_position.distance_squared_to(enemy.position)
		if distance_squared > range_m * range_m:
			continue
		if distance_squared < best_distance_squared or (
			distance_squared == best_distance_squared
			and (best == null or entity_id < best.entity_id)
		):
			best = enemy
			best_distance_squared = distance_squared
	return best


func _projectile_damage_record(
	entity_id: int,
	projectile: ProjectileState,
	position: Vector2,
	direction: Vector2,
) -> Dictionary:
	var source_effect_id: StringName = projectile.source_effect_id
	if source_effect_id.is_empty():
		source_effect_id = StringName("weapon:%s" % projectile.weapon_id)
	var event: CombatEvent
	if projectile.is_primary and projectile.effect_chain.is_empty():
		event = _router.create_primary(
			_state,
			&"damage",
			-1,
			source_effect_id,
			projectile.damage,
			position,
			direction,
		)
	else:
		event = _router.create_secondary_from_reserved_chain(
			_state,
			projectile.effect_chain,
			&"damage",
			-1,
			source_effect_id,
			projectile.proc_effect_id,
			projectile.damage,
			position,
			direction,
		)
	return {"entity_id": entity_id, "event": event}


func _materialize_replay_event(
	replay: ScheduledProcReplay,
	position: Vector2,
	direction: Vector2,
) -> CombatEvent:
	return _router.create_secondary_from_reserved_chain(
		_state,
		replay.inherited_effect_chain,
		&"damage",
		-1,
		replay.source_effect_id,
		replay.proc_effect_id,
		replay.damage_snapshot,
		position,
		direction,
	)


func _point_on_segment_t(segment_start: Vector2, segment_end: Vector2, point: Vector2) -> float:
	var delta: Vector2 = segment_end - segment_start
	var length_squared: float = delta.length_squared()
	if length_squared <= CombatGeometry.EPSILON:
		return 0.0 if segment_start.is_equal_approx(point) else -1.0
	var projection: float = (point - segment_start).dot(delta) / length_squared
	if projection < -CombatGeometry.EPSILON or projection > 1.0 + CombatGeometry.EPSILON:
		return -1.0
	var closest: Vector2 = segment_start + delta * projection
	return clampf(projection, 0.0, 1.0) if closest.distance_to(point) <= 0.00001 else -1.0


func _intersection_less(left: Dictionary, right: Dictionary) -> bool:
	var left_t: float = float(left["t"])
	var right_t: float = float(right["t"])
	if left_t != right_t:
		return left_t < right_t
	return int(left["entity_id"]) < int(right["entity_id"])
