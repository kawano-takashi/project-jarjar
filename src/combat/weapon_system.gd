class_name WeaponSystem
extends RefCounted


const MAX_ENEMY_BODY_RADIUS: float = 1.25
const PLAYER_BODY_RADIUS: float = 0.45
const BOW_ID: StringName = &"bow"
const STAFF_ID: StringName = &"staff"

var attack_elapsed_by_slot: Dictionary[int, float] = {}
var last_attack_direction_by_slot: Dictionary[int, Vector2] = {}

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
	attack_elapsed_by_slot.clear()
	last_attack_direction_by_slot.clear()
	for slot: GameTypes.EquipmentSlot in GameTypes.weapon_slots():
		var item: ItemInstance = _weapon_at(slot)
		if item == null:
			continue
		var interval: float = effective_interval(item)
		var phase_rng := RandomNumberGenerator.new()
		phase_rng.seed = SeedService.derive(
			_state.run_seed,
			StringName("weapon_phase:%d:%s" % [_state.wave_number, item.item_id]),
		)
		attack_elapsed_by_slot[int(slot)] = phase_rng.randf() * interval
		last_attack_direction_by_slot[int(slot)] = Vector2.RIGHT


func effective_interval(item: ItemInstance) -> float:
	var definition: WeaponDefinition = _definition_for_item(item)
	if definition == null:
		return 0.8
	return StatCalculator.effective_attack_interval(
		definition.base_interval,
		StatCalculator.aggregate_affixes(_state.equipped),
	)


func effective_damage(item: ItemInstance) -> float:
	var definition: WeaponDefinition = _definition_for_item(item)
	if definition == null:
		return 0.0
	return definition.damage_for_rarity(item.rarity) * StatCalculator.damage_multiplier(
		StatCalculator.aggregate_affixes(_state.equipped),
	)


func effective_range(item: ItemInstance) -> float:
	var definition: WeaponDefinition = _definition_for_item(item)
	if definition == null:
		return 0.0
	if item.weapon_type == GameTypes.WeaponType.SWORD:
		return definition.range_m * StatCalculator.effective_area_multiplier(
			StatCalculator.aggregate_affixes(_state.equipped),
		)
	return definition.range_m


func advance_attack_timers(delta: float) -> void:
	for slot: GameTypes.EquipmentSlot in GameTypes.weapon_slots():
		var item: ItemInstance = _weapon_at(slot)
		if item == null:
			continue
		var interval: float = effective_interval(item)
		attack_elapsed_by_slot[int(slot)] = TimerMath.advance_clamped(
			float(attack_elapsed_by_slot.get(int(slot), 0.0)),
			interval,
			delta,
		)


func is_attack_ready(slot: GameTypes.EquipmentSlot) -> bool:
	var item: ItemInstance = _weapon_at(slot)
	if item == null:
		return false
	return TimerMath.is_ready(
		float(attack_elapsed_by_slot.get(int(slot), 0.0)),
		effective_interval(item),
	)


func try_attacks_detailed(
	player_position: Vector2,
	enemy_store: EnemyStore,
	grid: UniformGrid,
	current_tick: int,
	damage_override: float = -1.0,
) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for slot: GameTypes.EquipmentSlot in GameTypes.weapon_slots():
		var item: ItemInstance = _weapon_at(slot)
		if item == null or not is_attack_ready(slot):
			continue
		var result: Dictionary = _try_attack(
			slot,
			item,
			player_position,
			enemy_store,
			grid,
			current_tick,
			damage_override,
		)
		if bool(result.get("generated", false)):
			results.append(result)
	return results


func build_hud_weapons() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for slot: GameTypes.EquipmentSlot in GameTypes.weapon_slots():
		var item: ItemInstance = _weapon_at(slot)
		result.append({
			"slot": int(slot),
			"item_id": item.item_id if item != null else "",
			"weapon_type": int(item.weapon_type) if item != null else int(GameTypes.WeaponType.NONE),
			"display_name": item.display_name if item != null else "— 空き —",
			"rarity": int(item.rarity) if item != null else -1,
		})
	return result


func _try_attack(
	slot: GameTypes.EquipmentSlot,
	item: ItemInstance,
	player_position: Vector2,
	enemy_store: EnemyStore,
	grid: UniformGrid,
	current_tick: int,
	damage_override: float,
) -> Dictionary:
	var definition: WeaponDefinition = _definition_for_item(item)
	var result: Dictionary = {
		"generated": false,
		"weapon_id": &"",
		"item_id": item.item_id,
		"slot": int(slot),
		"origin": player_position,
		"source_effect_id": &"",
		"damage_snapshot": 0.0,
		"direction": Vector2.ZERO,
		"range_m": 0.0,
		"aim_distance": 0.0,
		"target_entity_id": -1,
		"hits": [],
	}
	if definition == null:
		return result
	var range_m: float = effective_range(item)
	result["weapon_id"] = definition.weapon_id
	result["range_m"] = range_m
	var target: EnemyEntity = _nearest_target(
		player_position,
		range_m,
		enemy_store,
		grid,
		current_tick,
	)
	if target == null:
		return result
	var direction: Vector2 = (target.position - player_position).normalized()
	if direction == Vector2.ZERO:
		direction = last_attack_direction_by_slot.get(int(slot), Vector2.RIGHT) as Vector2
	last_attack_direction_by_slot[int(slot)] = direction
	attack_elapsed_by_slot[int(slot)] = 0.0
	var damage: float = damage_override if damage_override >= 0.0 else effective_damage(item)
	var source_effect_id := StringName("weapon:%s" % item.item_id)
	var aim_distance: float = player_position.distance_to(target.position)
	var hits: Array[Dictionary] = []
	var generated: bool = false
	match item.weapon_type:
		GameTypes.WeaponType.WOOD_STICK:
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
		GameTypes.WeaponType.BOW:
			var hit_count: int = 1 + StatCalculator.effective_pierce(
				StatCalculator.aggregate_affixes(_state.equipped),
			)
			var projectile: ProjectileState = _projectile_pool.acquire(
				ProjectileState.FACTION_ALLY,
				definition.weapon_id,
				-1,
				player_position,
				direction * definition.projectile_speed,
				definition.projectile_radius,
				damage,
				range_m,
				range_m / definition.projectile_speed,
				target.position,
				hit_count,
				current_tick,
				source_effect_id,
			)
			generated = projectile != null
		GameTypes.WeaponType.STAFF:
			var projectile: ProjectileState = _projectile_pool.acquire(
				ProjectileState.FACTION_ALLY,
				definition.weapon_id,
				-1,
				player_position,
				direction * definition.projectile_speed,
				definition.projectile_radius,
				damage,
				range_m,
				range_m / definition.projectile_speed,
				target.position,
				1,
				current_tick,
				source_effect_id,
			)
			generated = projectile != null
		GameTypes.WeaponType.SWORD:
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
				range_m,
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
					range_m,
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
	var effect_radius: float = definition.aoe_radius * StatCalculator.effective_area_multiplier(
		StatCalculator.aggregate_affixes(_state.equipped),
	)
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
	var event: CombatEvent = _router.create_primary(
		_state,
		&"damage",
		-1,
		source_effect_id,
		projectile.damage,
		position,
		direction,
	)
	return {"entity_id": entity_id, "event": event}


func _definition_for_item(item: ItemInstance) -> WeaponDefinition:
	if item == null or item.category != GameTypes.ItemCategory.WEAPON:
		return null
	return _catalog.weapon_for_type(item.weapon_type)


func _weapon_at(slot: GameTypes.EquipmentSlot) -> ItemInstance:
	var item: ItemInstance = _state.equipped.get(slot, null) as ItemInstance
	return item if item != null and item.category == GameTypes.ItemCategory.WEAPON else null


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
