class_name WeaponSystem
extends RefCounted


const PLAYER_BODY_RADIUS: float = CombatEnvelope.PLAYER_BODY_RADIUS
const MAX_ENEMY_BODY_RADIUS: float = 1.4
const MIN_COOLDOWN_TICKS: int = 1
const MELEE_ARC_DEGREES: float = 82.0
const PROJECTILE_HEIGHT_M: float = 0.35
const ORBITAL_DAMAGE_INTERVAL_TICKS: int = 15

var _state: RunState = null
var _catalog: DefinitionCatalog = null
var _projectile_pool: ProjectilePool = null
var _router: CombatEventRouter = null
var _last_move_direction: Vector2 = Vector2.RIGHT
var _orbital_active_until_by_lineage: Dictionary[StringName, int] = {}
var _orbital_next_damage_tick_by_lineage: Dictionary[StringName, int] = {}


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
	_last_move_direction = Vector2.RIGHT
	_orbital_active_until_by_lineage.clear()
	_orbital_next_damage_tick_by_lineage.clear()


func update_move_direction(move_direction: Vector2) -> void:
	if move_direction.length_squared() > 0.000001:
		_last_move_direction = move_direction.normalized()


func advance_and_fire(
	player_position: Vector2,
	enemy_store: EnemyStore,
	uniform_grid: UniformGrid,
	current_tick: int,
) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var stats: Dictionary = StatCalculator.aggregate(_state, _catalog)
	for slot_index: int in range(_state.weapons.size()):
		var runtime: RunWeapon = _state.weapons[slot_index]
		var definition: WeaponDefinition = _catalog.weapon(runtime.weapon_id)
		if definition == null:
			continue
		if definition.behavior == GameTypes.WeaponBehavior.ORBITAL:
			var orbital_result: Dictionary = _advance_orbital(
				runtime,
				definition,
				slot_index,
				player_position,
				enemy_store,
				uniform_grid,
				current_tick,
				stats,
			)
			if bool(orbital_result.get("generated", false)):
				results.append(orbital_result)
			continue
		if runtime.ready_on_resume:
			runtime.cooldown_remaining_ticks = 0
			runtime.ready_on_resume = false
		elif runtime.cooldown_remaining_ticks > 0:
			runtime.cooldown_remaining_ticks -= 1
		if runtime.cooldown_remaining_ticks > 0:
			continue
		var result: Dictionary = _fire_weapon(
			runtime,
			definition,
			slot_index,
			player_position,
			enemy_store,
			uniform_grid,
			current_tick,
			stats,
		)
		if not bool(result.get("generated", false)):
			continue
		runtime.cooldown_remaining_ticks = effective_cooldown_ticks(definition, runtime.level, stats)
		results.append(result)
	return results


func effective_cooldown_ticks(
	definition: WeaponDefinition,
	level: int,
	stats: Dictionary,
) -> int:
	return maxi(
		MIN_COOLDOWN_TICKS,
		roundi(float(definition.cooldown_ticks_at(level)) * StatCalculator.cooldown_multiplier(stats)),
	)


func move_snapshot_projectiles(
	entries: Array[Vector2i],
	enemy_store: EnemyStore,
	player_position: Vector2,
	current_tick: int,
	stop_active: bool,
) -> void:
	for entry: Vector2i in entries:
		var projectile: ProjectileState = _projectile_pool.resolve_snapshot_entry(entry)
		if projectile == null or projectile.born_tick >= current_tick:
			continue
		var time_scale: float = 1.0
		if stop_active and projectile.faction == ProjectileState.FACTION_ENEMY:
			time_scale = projectile.stop_time_scale
		projectile.previous_position = projectile.position
		projectile.previous_remaining_distance = projectile.remaining_distance
		projectile.expired_this_tick = false
		if time_scale <= 0.0:
			continue
		if projectile.movement_kind == ProjectileState.MovementKind.HOMING:
			_update_homing_velocity(
				projectile,
				enemy_store,
				player_position,
				current_tick,
			)
		elif projectile.movement_kind == ProjectileState.MovementKind.RETURNING:
			_update_returning_velocity(projectile, player_position)
		var movement: Vector2 = (
			projectile.velocity * time_scale / float(RunState.TICKS_PER_SECOND)
		)
		var movement_limit: float = projectile.remaining_distance
		if (
			projectile.movement_kind == ProjectileState.MovementKind.RETURNING
			and not projectile.return_phase_started
		):
			movement_limit = minf(
				movement_limit,
				projectile.outbound_distance_remaining,
			)
		movement = movement.limit_length(maxf(0.0, movement_limit))
		projectile.position += movement
		projectile.remaining_distance = maxf(
			0.0,
			projectile.remaining_distance - movement.length(),
		)
		if (
			projectile.movement_kind == ProjectileState.MovementKind.RETURNING
			and not projectile.return_phase_started
		):
			projectile.outbound_distance_remaining = maxf(
				0.0,
				projectile.outbound_distance_remaining - movement.length(),
			)
		projectile.remaining_lifetime = maxf(
			0.0,
			projectile.remaining_lifetime
			- time_scale / float(RunState.TICKS_PER_SECOND),
		)
		projectile.elapsed_ticks += time_scale
		projectile.expired_this_tick = (
			projectile.remaining_distance <= 0.0
			or projectile.remaining_lifetime <= 0.0
		)


func resolve_ally_projectile(
	entry: Vector2i,
	enemy_store: EnemyStore,
	uniform_grid: UniformGrid,
	player_position: Vector2,
	current_tick: int,
	resolution: Dictionary = {},
) -> Array[Dictionary]:
	resolution.clear()
	var records: Array[Dictionary] = []
	var projectile: ProjectileState = _projectile_pool.resolve_snapshot_entry(entry)
	if (
		projectile == null
		or projectile.faction != ProjectileState.FACTION_ALLY
		or projectile.born_tick >= current_tick
	):
		return records
	var effect_outer_distance: float = 0.0
	var candidates: Array[int] = uniform_grid.query_segment_candidates(
		projectile.previous_position,
		projectile.position,
		projectile.radius + MAX_ENEMY_BODY_RADIUS,
	)
	var intersections: Array[Dictionary] = []
	for entity_id: int in candidates:
		if projectile.hit_entity_ids.has(entity_id):
			continue
		var enemy: EnemyEntity = enemy_store.get_by_id(entity_id)
		if not _is_ally_damageable(enemy, player_position, current_tick):
			continue
		var first_t: float = CombatGeometry.segment_circle_first_t(
			projectile.previous_position,
			projectile.position,
			enemy.position,
			projectile.radius + enemy.body_radius(),
		)
		if first_t >= 0.0:
			intersections.append({"entity_id": entity_id, "t": first_t})
	intersections.sort_custom(_intersection_less)
	if projectile.movement_kind == ProjectileState.MovementKind.ARC:
		if not intersections.is_empty():
			var impact_t: float = float(intersections[0]["t"])
			projectile.position = projectile.previous_position.lerp(
				projectile.position,
				impact_t,
			)
		if not intersections.is_empty() or projectile.expired_this_tick:
			effect_outer_distance = _projectile_effect_outer_distance(
				projectile,
				player_position,
			)
			if effect_outer_distance > CombatEnvelope.EFFECT_OUTER_RADIUS + 0.0001:
				_projectile_pool.release(projectile.pool_index, projectile.generation)
				return records
			resolution[&"arc_impact_position"] = projectile.position
			resolution[&"arc_explosion_radius"] = projectile.explosion_radius
			resolution[&"arc_damage"] = projectile.damage
			records = _resolve_projectile_explosion(
				projectile,
				enemy_store,
				uniform_grid,
				player_position,
				current_tick,
				effect_outer_distance,
			)
			_projectile_pool.release(projectile.pool_index, projectile.generation)
		elif (
			_projectile_effect_outer_distance(projectile, player_position)
			> CombatEnvelope.EFFECT_OUTER_RADIUS + 0.0001
		):
			_projectile_pool.release(projectile.pool_index, projectile.generation)
		return records
	for intersection: Dictionary in intersections:
		var entity_id: int = int(intersection["entity_id"])
		var hit_position: Vector2 = projectile.previous_position.lerp(
			projectile.position,
			float(intersection["t"]),
		)
		var hit_outer_distance: float = (
			player_position.distance_to(hit_position) + projectile.radius
		)
		if hit_outer_distance > CombatEnvelope.EFFECT_OUTER_RADIUS + 0.0001:
			continue
		projectile.hit_entity_ids[entity_id] = true
		records.append(_projectile_damage_record(
			projectile,
			entity_id,
			hit_position,
			hit_outer_distance,
		))
		projectile.pierce_remaining -= 1
		if projectile.pierce_remaining < 0:
			_projectile_pool.release(projectile.pool_index, projectile.generation)
			break
	if (
		projectile.active
		and (
			projectile.expired_this_tick
			or _projectile_effect_outer_distance(projectile, player_position)
			> CombatEnvelope.EFFECT_OUTER_RADIUS + 0.0001
		)
	):
		_projectile_pool.release(projectile.pool_index, projectile.generation)
	return records


func resolve_enemy_projectile(
	entry: Vector2i,
	player_position: Vector2,
	current_tick: int,
) -> Dictionary:
	var projectile: ProjectileState = _projectile_pool.resolve_snapshot_entry(entry)
	if (
		projectile == null
		or projectile.faction != ProjectileState.FACTION_ENEMY
		or projectile.born_tick >= current_tick
	):
		return {}
	if (
		_state != null
		and _state.is_stop_active()
		and projectile.stop_time_scale <= 0.0
	):
		return {}
	var hit_t: float = CombatGeometry.segment_circle_first_t(
		projectile.previous_position,
		projectile.position,
		player_position,
		projectile.radius + PLAYER_BODY_RADIUS,
	)
	if hit_t >= 0.0:
		var record: Dictionary = {
			"damage": projectile.damage,
			"source_effect_id": projectile.source_effect_id,
		}
		_projectile_pool.release(projectile.pool_index, projectile.generation)
		return record
	if projectile.expired_this_tick:
		_projectile_pool.release(projectile.pool_index, projectile.generation)
	return {}


func orbital_transforms(player_position: Vector2, current_tick: int) -> Array[Transform3D]:
	var transforms: Array[Transform3D] = []
	var stats: Dictionary = StatCalculator.aggregate(_state, _catalog)
	for runtime: RunWeapon in _state.weapons:
		var definition: WeaponDefinition = _catalog.weapon(runtime.weapon_id)
		if definition == null or definition.behavior != GameTypes.WeaponBehavior.ORBITAL:
			continue
		if not orbital_is_active(runtime.lineage_id, current_tick):
			continue
		var visual_diameter: float = maxf(
			0.1,
			definition.effective_effect_radius_at(
				runtime.level,
				StatCalculator.area_multiplier(stats),
			) * 2.0,
		)
		for position: Vector2 in _orbital_positions(
			runtime,
			definition,
			player_position,
			current_tick,
			stats,
		):
			transforms.append(Transform3D(
				Basis.IDENTITY.scaled(Vector3.ONE * visual_diameter),
				Vector3(position.x, PROJECTILE_HEIGHT_M, position.y),
			))
	return transforms


func orbital_is_active(lineage_id: StringName, current_tick: int) -> bool:
	if _is_continuous_orbit(lineage_id):
		return true
	return current_tick < int(_orbital_active_until_by_lineage.get(lineage_id, 0))


func orbital_active_until_tick(lineage_id: StringName) -> int:
	if _is_continuous_orbit(lineage_id):
		return -1
	return int(_orbital_active_until_by_lineage.get(lineage_id, 0))


func deterministic_state_values() -> Array:
	return [
		_last_move_direction,
		_sorted_orbital_tick_entries(_orbital_active_until_by_lineage),
		_sorted_orbital_tick_entries(_orbital_next_damage_tick_by_lineage),
	]


func build_hud_weapons() -> Array[Dictionary]:
	var values: Array[Dictionary] = []
	for runtime: RunWeapon in _state.weapons:
		var definition: WeaponDefinition = _catalog.weapon(runtime.weapon_id)
		if definition == null:
			continue
		values.append({
			"weapon_id": runtime.weapon_id,
			"lineage_id": runtime.lineage_id,
			"display_name": definition.display_name,
			"level": runtime.level,
			"max_level": definition.max_level,
			"evolved": runtime.evolved,
		})
	return values


func life_steal_for_lineage(lineage_id: StringName) -> float:
	var runtime: RunWeapon = _state.weapon_for_lineage(lineage_id)
	if runtime == null:
		return 0.0
	var definition: WeaponDefinition = _catalog.weapon(runtime.weapon_id)
	return 0.0 if definition == null else maxf(0.0, definition.life_steal_ratio)


func _fire_weapon(
	runtime: RunWeapon,
	definition: WeaponDefinition,
	slot_index: int,
	player_position: Vector2,
	enemy_store: EnemyStore,
	uniform_grid: UniformGrid,
	current_tick: int,
	stats: Dictionary,
) -> Dictionary:
	match definition.behavior:
		GameTypes.WeaponBehavior.MELEE_WAVE:
			return _fire_melee_wave(runtime, definition, player_position, enemy_store, uniform_grid, current_tick, stats)
		GameTypes.WeaponBehavior.HOMING_PROJECTILE:
			return _fire_homing(runtime, definition, player_position, enemy_store, current_tick, stats)
		GameTypes.WeaponBehavior.DIRECTIONAL_PROJECTILE:
			return _fire_directional(runtime, definition, player_position, enemy_store, current_tick, stats)
		GameTypes.WeaponBehavior.ARC_PROJECTILE:
			return _fire_arc(runtime, definition, player_position, enemy_store, current_tick, stats)
		GameTypes.WeaponBehavior.RETURNING_RING:
			return _fire_returning(runtime, definition, player_position, enemy_store, current_tick, stats)
		GameTypes.WeaponBehavior.ORBITAL:
			return _fire_orbital(runtime, definition, player_position, enemy_store, uniform_grid, current_tick, stats)
		GameTypes.WeaponBehavior.MASS_PROJECTILE:
			return _fire_mass(runtime, definition, player_position, enemy_store, current_tick, stats)
		GameTypes.WeaponBehavior.AURA:
			return _fire_aura(runtime, definition, player_position, enemy_store, uniform_grid, current_tick, stats)
	return {"generated": false, "slot_index": slot_index}


func _fire_melee_wave(
	runtime: RunWeapon,
	definition: WeaponDefinition,
	player_position: Vector2,
	enemy_store: EnemyStore,
	uniform_grid: UniformGrid,
	current_tick: int,
	stats: Dictionary,
) -> Dictionary:
	var range_m: float = minf(
		CombatEnvelope.EFFECT_OUTER_RADIUS,
		maxf(
			0.5,
			definition.effective_range_at(
				runtime.level,
				StatCalculator.area_multiplier(stats),
			),
		),
	)
	var amount: int = maxi(2, definition.amount_at(runtime.level))
	var hits: Array[Dictionary] = []
	var zones: Array[Dictionary] = []
	for swing_index: int in range(amount):
		# Every emitted wave owns its hit set. Later amount upgrades therefore add
		# real damage instead of being discarded by a lineage-wide de-duplication.
		var hit_ids: Dictionary[int, bool] = {}
		var direction: Vector2 = _last_move_direction
		if swing_index % 2 == 1:
			direction = -direction
		zones.append({
			"center": player_position,
			"radius": range_m,
			"damage": _base_damage(definition, runtime, stats),
		})
		for entity_id: int in uniform_grid.query_circle_candidates(player_position, range_m, MAX_ENEMY_BODY_RADIUS):
			if hit_ids.has(entity_id):
				continue
			var enemy: EnemyEntity = enemy_store.get_by_id(entity_id)
			if not _is_ally_damageable(enemy, player_position, current_tick):
				continue
			if not CombatGeometry.point_in_fan(player_position, direction, range_m, MELEE_ARC_DEGREES, enemy.position, enemy.body_radius()):
				continue
			hit_ids[entity_id] = true
			hits.append(_instant_damage_record(
				runtime,
				definition,
				enemy.entity_id,
				_roll_damage(definition, runtime, stats),
				enemy.position,
				range_m,
			))
	return {
		"generated": true,
		"weapon_id": runtime.weapon_id,
		"lineage_id": runtime.lineage_id,
		"origin": player_position,
		"direction": _last_move_direction,
		"range_m": range_m,
		"hits": hits,
		"node_damage_zones": zones,
	}


func _fire_homing(
	runtime: RunWeapon,
	definition: WeaponDefinition,
	player_position: Vector2,
	enemy_store: EnemyStore,
	current_tick: int,
	stats: Dictionary,
) -> Dictionary:
	var targets: Array[EnemyEntity] = _targets_by_distance(
		enemy_store,
		player_position,
		player_position,
		current_tick,
	)
	if targets.is_empty():
		return {"generated": false}
	var amount: int = maxi(1, definition.amount_at(runtime.level))
	var target: EnemyEntity = targets[0]
	for _projectile_index: int in range(amount):
		var direction: Vector2 = (target.position - player_position).normalized()
		_spawn_ally_projectile(runtime, definition, player_position, direction, target.entity_id, stats, current_tick, ProjectileState.MovementKind.HOMING)
	return _projectile_result(
		runtime,
		player_position,
		(targets[0].position - player_position).normalized(),
		definition.effective_range_at(runtime.level, StatCalculator.area_multiplier(stats)),
	)


func _fire_directional(
	runtime: RunWeapon,
	definition: WeaponDefinition,
	player_position: Vector2,
	enemy_store: EnemyStore,
	current_tick: int,
	stats: Dictionary,
) -> Dictionary:
	if _first_target(enemy_store, player_position, player_position, current_tick) == null:
		return {"generated": false}
	var amount: int = maxi(1, definition.amount_at(runtime.level))
	var side := Vector2(-_last_move_direction.y, _last_move_direction.x)
	for projectile_index: int in range(amount):
		var centered_index: float = float(projectile_index) - float(amount - 1) * 0.5
		var origin: Vector2 = player_position + side * centered_index * 0.28
		_spawn_ally_projectile(runtime, definition, origin, _last_move_direction, -1, stats, current_tick, ProjectileState.MovementKind.STRAIGHT)
	return _projectile_result(
		runtime,
		player_position,
		_last_move_direction,
		definition.effective_range_at(runtime.level, StatCalculator.area_multiplier(stats)),
	)


func _fire_arc(
	runtime: RunWeapon,
	definition: WeaponDefinition,
	player_position: Vector2,
	enemy_store: EnemyStore,
	current_tick: int,
	stats: Dictionary,
) -> Dictionary:
	var targets: Array[EnemyEntity] = _targets_by_distance(
		enemy_store,
		player_position,
		player_position,
		current_tick,
	)
	if targets.is_empty():
		return {"generated": false}
	var amount: int = maxi(1, definition.amount_at(runtime.level))
	if runtime.weapon_id == &"spiral_crystal":
		for projectile_index: int in range(amount):
			var angle: float = TAU * float(projectile_index) / float(amount)
			_spawn_ally_projectile(runtime, definition, player_position, Vector2.from_angle(angle), -1, stats, current_tick, ProjectileState.MovementKind.STRAIGHT)
		return _projectile_result(
			runtime,
			player_position,
			Vector2.RIGHT,
			definition.effective_range_at(runtime.level, StatCalculator.area_multiplier(stats)),
		)
	for projectile_index: int in range(amount):
		var target: EnemyEntity = targets[projectile_index % targets.size()]
		var direction: Vector2 = (target.position - player_position).normalized()
		_spawn_ally_projectile(runtime, definition, player_position, direction, target.entity_id, stats, current_tick, ProjectileState.MovementKind.ARC, target.position)
	return _projectile_result(
		runtime,
		player_position,
		(targets[0].position - player_position).normalized(),
		definition.effective_range_at(runtime.level, StatCalculator.area_multiplier(stats)),
	)


func _fire_returning(
	runtime: RunWeapon,
	definition: WeaponDefinition,
	player_position: Vector2,
	enemy_store: EnemyStore,
	current_tick: int,
	stats: Dictionary,
) -> Dictionary:
	var target: EnemyEntity = _first_target(
		enemy_store,
		player_position,
		player_position,
		current_tick,
	)
	if target == null:
		return {"generated": false}
	var amount: int = maxi(1, definition.amount_at(runtime.level))
	var base_angle: float = (target.position - player_position).angle()
	for projectile_index: int in range(amount):
		var spread: float = deg_to_rad(12.0) * (float(projectile_index) - float(amount - 1) * 0.5)
		_spawn_ally_projectile(runtime, definition, player_position, Vector2.from_angle(base_angle + spread), target.entity_id, stats, current_tick, ProjectileState.MovementKind.RETURNING)
	return _projectile_result(
		runtime,
		player_position,
		Vector2.from_angle(base_angle),
		definition.effective_range_at(runtime.level, StatCalculator.area_multiplier(stats)),
	)


func _fire_orbital(
	runtime: RunWeapon,
	definition: WeaponDefinition,
	player_position: Vector2,
	enemy_store: EnemyStore,
	uniform_grid: UniformGrid,
	current_tick: int,
	stats: Dictionary,
) -> Dictionary:
	var area_multiplier: float = StatCalculator.area_multiplier(stats)
	var orbit_radius: float = maxf(
		1.0,
		definition.effective_range_at(runtime.level, area_multiplier),
	)
	var hit_radius: float = minf(
		definition.effective_effect_radius_at(runtime.level, area_multiplier),
		maxf(0.0, CombatEnvelope.EFFECT_OUTER_RADIUS - orbit_radius),
	)
	var hits: Array[Dictionary] = []
	var zones: Array[Dictionary] = []
	var hit_ids: Dictionary[int, bool] = {}
	for position: Vector2 in _orbital_positions(
		runtime,
		definition,
		player_position,
		current_tick,
		stats,
	):
		zones.append({"center": position, "radius": hit_radius, "damage": _base_damage(definition, runtime, stats)})
		for entity_id: int in uniform_grid.query_circle_candidates(position, hit_radius, MAX_ENEMY_BODY_RADIUS):
			if hit_ids.has(entity_id):
				continue
			var enemy: EnemyEntity = enemy_store.get_by_id(entity_id)
			if (
				_is_ally_damageable(enemy, player_position, current_tick)
				and CombatGeometry.circle_intersects(
					position,
					hit_radius,
					enemy.position,
					enemy.body_radius(),
				)
			):
				hit_ids[entity_id] = true
				hits.append(_instant_damage_record(
					runtime,
					definition,
					entity_id,
					_roll_damage(definition, runtime, stats),
					enemy.position,
					orbit_radius + hit_radius,
				))
	return {
		"generated": true,
		"weapon_id": runtime.weapon_id,
		"lineage_id": runtime.lineage_id,
		"origin": player_position,
		"direction": Vector2.RIGHT,
		"range_m": orbit_radius,
		"hits": hits,
		"node_damage_zones": zones,
	}


func _advance_orbital(
	runtime: RunWeapon,
	definition: WeaponDefinition,
	slot_index: int,
	player_position: Vector2,
	enemy_store: EnemyStore,
	uniform_grid: UniformGrid,
	current_tick: int,
	stats: Dictionary,
) -> Dictionary:
	var lineage_id: StringName = runtime.lineage_id
	if definition.is_evolved:
		if runtime.ready_on_resume:
			runtime.ready_on_resume = false
			runtime.cooldown_remaining_ticks = 0
			_orbital_active_until_by_lineage.erase(lineage_id)
			_orbital_next_damage_tick_by_lineage.erase(lineage_id)
		var continuous_next_damage_tick: int = int(
			_orbital_next_damage_tick_by_lineage.get(lineage_id, current_tick)
		)
		if current_tick < continuous_next_damage_tick:
			return {"generated": false, "slot_index": slot_index}
		_orbital_next_damage_tick_by_lineage[lineage_id] = (
			current_tick + ORBITAL_DAMAGE_INTERVAL_TICKS
		)
		return _fire_orbital(
			runtime,
			definition,
			player_position,
			enemy_store,
			uniform_grid,
			current_tick,
			stats,
		)
	if runtime.ready_on_resume:
		runtime.ready_on_resume = false
		runtime.cooldown_remaining_ticks = 0
		_orbital_active_until_by_lineage.erase(lineage_id)
		_orbital_next_damage_tick_by_lineage.erase(lineage_id)
	if orbital_is_active(lineage_id, current_tick):
		var next_damage_tick: int = int(
			_orbital_next_damage_tick_by_lineage.get(lineage_id, current_tick)
		)
		if current_tick < next_damage_tick:
			return {"generated": false, "slot_index": slot_index}
		_orbital_next_damage_tick_by_lineage[lineage_id] = (
			current_tick + ORBITAL_DAMAGE_INTERVAL_TICKS
		)
		return _fire_orbital(
			runtime,
			definition,
			player_position,
			enemy_store,
			uniform_grid,
			current_tick,
			stats,
		)
	if _orbital_active_until_by_lineage.has(lineage_id):
		_orbital_active_until_by_lineage.erase(lineage_id)
		_orbital_next_damage_tick_by_lineage.erase(lineage_id)
		runtime.cooldown_remaining_ticks = effective_cooldown_ticks(
			definition,
			runtime.level,
			stats,
		)
		return {"generated": false, "slot_index": slot_index}
	if runtime.cooldown_remaining_ticks > 0:
		runtime.cooldown_remaining_ticks -= 1
		if runtime.cooldown_remaining_ticks > 0:
			return {"generated": false, "slot_index": slot_index}
	var duration_ticks: int = maxi(
		1,
		roundi(
			float(definition.duration_ticks_at(runtime.level))
			* StatCalculator.duration_multiplier(stats)
		),
	)
	_orbital_active_until_by_lineage[lineage_id] = current_tick + duration_ticks
	_orbital_next_damage_tick_by_lineage[lineage_id] = (
		current_tick + ORBITAL_DAMAGE_INTERVAL_TICKS
	)
	return _fire_orbital(
		runtime,
		definition,
		player_position,
		enemy_store,
		uniform_grid,
		current_tick,
		stats,
	)


func _orbital_positions(
	runtime: RunWeapon,
	definition: WeaponDefinition,
	player_position: Vector2,
	current_tick: int,
	stats: Dictionary,
) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var amount: int = maxi(1, definition.amount_at(runtime.level))
	var orbit_radius: float = maxf(
		1.0,
		definition.effective_range_at(
			runtime.level,
			StatCalculator.area_multiplier(stats),
		),
	)
	var tangential_speed: float = maxf(
		0.1,
		definition.projectile_speed_at(runtime.level)
		* StatCalculator.projectile_speed_multiplier(stats),
	)
	var phase: float = (
		float(current_tick)
		/ float(RunState.TICKS_PER_SECOND)
		* tangential_speed
		/ orbit_radius
	)
	for orbit_index: int in range(amount):
		var angle: float = phase + TAU * float(orbit_index) / float(amount)
		result.append(player_position + Vector2.from_angle(angle) * orbit_radius)
	return result


func _sorted_orbital_tick_entries(source: Dictionary) -> Array:
	var keys: Array[String] = []
	for key_value: Variant in source:
		keys.append(String(key_value))
	keys.sort()
	var result: Array = []
	for key_text: String in keys:
		var lineage_id := StringName(key_text)
		result.append([key_text, int(source[lineage_id])])
	return result


func _is_continuous_orbit(lineage_id: StringName) -> bool:
	if _state == null or _catalog == null:
		return false
	var runtime: RunWeapon = _state.weapon_for_lineage(lineage_id)
	if runtime == null:
		return false
	var definition: WeaponDefinition = _catalog.weapon(runtime.weapon_id)
	return (
		definition != null
		and definition.is_evolved
		and definition.behavior == GameTypes.WeaponBehavior.ORBITAL
	)


func _fire_mass(
	runtime: RunWeapon,
	definition: WeaponDefinition,
	player_position: Vector2,
	enemy_store: EnemyStore,
	current_tick: int,
	stats: Dictionary,
) -> Dictionary:
	var targets: Array[EnemyEntity] = []
	var area_multiplier: float = StatCalculator.area_multiplier(stats)
	var travel_distance: float = definition.effective_range_at(
		runtime.level,
		area_multiplier,
	)
	var projectile_radius: float = maxf(
		0.08,
		definition.effective_projectile_radius_at(runtime.level, area_multiplier),
	)
	for candidate: EnemyEntity in _targets_by_entity_id(
		enemy_store,
		player_position,
		current_tick,
	):
		if (
			player_position.distance_to(candidate.position)
			<= travel_distance + projectile_radius + candidate.body_radius()
		):
			targets.append(candidate)
	if targets.is_empty():
		return {"generated": false}
	var amount: int = maxi(1, definition.amount_at(runtime.level))
	for _projectile_index: int in range(amount):
		var target_index: int = runtime.rng.randi_range(0, targets.size() - 1) if runtime.rng != null else 0
		var target: EnemyEntity = targets[target_index]
		var direction: Vector2 = (target.position - player_position).normalized()
		_spawn_ally_projectile(runtime, definition, player_position, direction, target.entity_id, stats, current_tick, ProjectileState.MovementKind.STRAIGHT)
	return _projectile_result(
		runtime,
		player_position,
		(targets[0].position - player_position).normalized(),
		travel_distance,
	)


func _fire_aura(
	runtime: RunWeapon,
	definition: WeaponDefinition,
	player_position: Vector2,
	enemy_store: EnemyStore,
	uniform_grid: UniformGrid,
	current_tick: int,
	stats: Dictionary,
) -> Dictionary:
	var radius: float = minf(
		CombatEnvelope.EFFECT_OUTER_RADIUS,
		maxf(
			0.5,
			definition.effective_effect_radius_at(
				runtime.level,
				StatCalculator.area_multiplier(stats),
			),
		),
	)
	var hits: Array[Dictionary] = []
	for entity_id: int in uniform_grid.query_circle_candidates(player_position, radius, MAX_ENEMY_BODY_RADIUS):
		var enemy: EnemyEntity = enemy_store.get_by_id(entity_id)
		if (
			_is_ally_damageable(enemy, player_position, current_tick)
			and CombatGeometry.circle_intersects(
				player_position,
				radius,
				enemy.position,
				enemy.body_radius(),
			)
		):
			hits.append(_instant_damage_record(
				runtime,
				definition,
				entity_id,
				_roll_damage(definition, runtime, stats),
				enemy.position,
				radius,
			))
	return {
		"generated": true,
		"weapon_id": runtime.weapon_id,
		"lineage_id": runtime.lineage_id,
		"origin": player_position,
		"direction": Vector2.RIGHT,
		"range_m": radius,
		"hits": hits,
		"node_damage_zones": [{"center": player_position, "radius": radius, "damage": _base_damage(definition, runtime, stats)}],
	}


func _spawn_ally_projectile(
	runtime: RunWeapon,
	definition: WeaponDefinition,
	origin: Vector2,
	direction: Vector2,
	target_entity_id: int,
	stats: Dictionary,
	current_tick: int,
	movement_kind: ProjectileState.MovementKind,
	arc_target: Vector2 = Vector2.ZERO,
) -> void:
	var speed: float = maxf(0.1, definition.projectile_speed_at(runtime.level) * StatCalculator.projectile_speed_multiplier(stats))
	var duration_ticks: int = maxi(1, roundi(float(definition.duration_ticks_at(runtime.level)) * StatCalculator.duration_multiplier(stats)))
	var lifetime_seconds: float = float(duration_ticks) / float(RunState.TICKS_PER_SECOND)
	var area_multiplier: float = StatCalculator.area_multiplier(stats)
	var range_m: float = maxf(
		0.0,
		definition.effective_range_at(runtime.level, area_multiplier),
	)
	var projectile_radius: float = maxf(
		0.08,
		definition.effective_projectile_radius_at(runtime.level, area_multiplier),
	)
	var effect_radius: float = maxf(
		0.0,
		definition.effective_effect_radius_at(runtime.level, area_multiplier),
	)
	var remaining_distance: float = (
		range_m * 2.0
		if movement_kind == ProjectileState.MovementKind.RETURNING
		else range_m
	)
	var target_position: Vector2 = origin + direction * remaining_distance
	if movement_kind == ProjectileState.MovementKind.ARC and arc_target != Vector2.ZERO:
		var target_distance: float = minf(range_m, origin.distance_to(arc_target))
		target_position = origin + direction * target_distance
		remaining_distance = target_distance
		lifetime_seconds = minf(
			lifetime_seconds,
			maxf(1.0 / float(RunState.TICKS_PER_SECOND), remaining_distance / speed),
		)
		duration_ticks = maxi(1, ceili(lifetime_seconds * float(RunState.TICKS_PER_SECOND)))
	var projectile: ProjectileState = _projectile_pool.acquire(
		ProjectileState.FACTION_ALLY,
		runtime.weapon_id,
		-1,
		origin,
		direction.normalized() * speed,
		projectile_radius,
		_roll_damage(definition, runtime, stats),
		remaining_distance,
		lifetime_seconds,
		target_position,
		maxi(0, definition.pierce_at(runtime.level)),
		current_tick,
		runtime.lineage_id,
		movement_kind,
		target_entity_id,
		duration_ticks,
		floori(float(duration_ticks) / 2.0),
		effect_radius if movement_kind == ProjectileState.MovementKind.ARC else 0.0,
		0.0,
	)
	if projectile != null and movement_kind == ProjectileState.MovementKind.RETURNING:
		projectile.outbound_distance_remaining = range_m


func _resolve_projectile_explosion(
	projectile: ProjectileState,
	enemy_store: EnemyStore,
	uniform_grid: UniformGrid,
	player_position: Vector2,
	current_tick: int,
	effect_outer_distance: float,
) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	var radius: float = maxf(projectile.radius, projectile.explosion_radius)
	for entity_id: int in uniform_grid.query_circle_candidates(projectile.position, radius, MAX_ENEMY_BODY_RADIUS):
		var enemy: EnemyEntity = enemy_store.get_by_id(entity_id)
		if (
			_is_ally_damageable(enemy, player_position, current_tick)
			and CombatGeometry.circle_intersects(
				projectile.position,
				radius,
				enemy.position,
				enemy.body_radius(),
			)
		):
			records.append(_projectile_damage_record(
				projectile,
				entity_id,
				projectile.position,
				effect_outer_distance,
			))
	return records


func _update_homing_velocity(
	projectile: ProjectileState,
	enemy_store: EnemyStore,
	player_position: Vector2,
	current_tick: int,
) -> void:
	var target: EnemyEntity = enemy_store.get_by_id(projectile.target_entity_id)
	if not _is_ally_acquirable(target, player_position, current_tick):
		target = _first_target(
			enemy_store,
			projectile.position,
			player_position,
			current_tick,
		)
		projectile.target_entity_id = target.entity_id if target != null else -1
	if target != null:
		projectile.velocity = (target.position - projectile.position).normalized() * projectile.speed


func _update_returning_velocity(projectile: ProjectileState, player_position: Vector2) -> void:
	if projectile.outbound_distance_remaining > 0.0001:
		return
	if not projectile.return_phase_started:
		projectile.hit_entity_ids.clear()
		projectile.return_phase_started = true
	projectile.target_position = player_position
	projectile.velocity = (player_position - projectile.position).normalized() * projectile.speed
	projectile.remaining_distance = minf(
		projectile.remaining_distance,
		projectile.position.distance_to(player_position),
	)


func _base_damage(definition: WeaponDefinition, runtime: RunWeapon, stats: Dictionary) -> float:
	var damage: float = definition.damage_at(runtime.level) * StatCalculator.might_multiplier(stats)
	if runtime.weapon_id == &"absorption_field":
		damage *= 1.0 + StatCalculator.recovery_per_second(stats)
	return maxf(0.0, damage)


func _roll_damage(definition: WeaponDefinition, runtime: RunWeapon, stats: Dictionary) -> float:
	var damage: float = _base_damage(definition, runtime, stats)
	if definition.critical_chance > 0.0 and runtime.rng != null and runtime.rng.randf() < definition.critical_chance:
		damage *= maxf(1.0, definition.critical_multiplier)
	return damage


func _instant_damage_record(
	runtime: RunWeapon,
	definition: WeaponDefinition,
	entity_id: int,
	damage: float,
	hit_position: Vector2,
	effect_outer_distance: float,
) -> Dictionary:
	return {
		"entity_id": entity_id,
		"event": _router.create_primary(
			_state,
			&"weapon_hit",
			-1,
			runtime.lineage_id,
			damage,
			hit_position,
		),
		"weapon_id": definition.weapon_id,
		"effect_outer_distance": effect_outer_distance,
	}


func _projectile_damage_record(
	projectile: ProjectileState,
	entity_id: int,
	hit_position: Vector2,
	effect_outer_distance: float,
) -> Dictionary:
	return {
		"entity_id": entity_id,
		"event": _router.create_primary(
			_state,
			&"projectile_hit",
			projectile.source_entity_id,
			projectile.source_effect_id,
			projectile.damage,
			hit_position,
			projectile.velocity.normalized(),
		),
		"weapon_id": projectile.weapon_id,
		"effect_outer_distance": effect_outer_distance,
	}


func _projectile_result(
	runtime: RunWeapon,
	origin: Vector2,
	direction: Vector2,
	range_m: float,
) -> Dictionary:
	return {
		"generated": true,
		"weapon_id": runtime.weapon_id,
		"lineage_id": runtime.lineage_id,
		"origin": origin,
		"direction": direction,
		"range_m": range_m,
		"hits": [],
		"node_damage_zones": [],
	}


func _targets_by_distance(
	enemy_store: EnemyStore,
	sort_origin: Vector2,
	player_position: Vector2,
	current_tick: int,
) -> Array[EnemyEntity]:
	var targets: Array[EnemyEntity] = []
	for enemy: EnemyEntity in enemy_store.entities:
		if _is_ally_acquirable(enemy, player_position, current_tick):
			targets.append(enemy)
	targets.sort_custom(func(left: EnemyEntity, right: EnemyEntity) -> bool:
		var left_distance: float = left.position.distance_squared_to(sort_origin)
		var right_distance: float = right.position.distance_squared_to(sort_origin)
		if not is_equal_approx(left_distance, right_distance):
			return left_distance < right_distance
		return left.entity_id < right.entity_id
	)
	return targets


func _targets_by_entity_id(
	enemy_store: EnemyStore,
	player_position: Vector2,
	current_tick: int,
) -> Array[EnemyEntity]:
	var targets: Array[EnemyEntity] = []
	for enemy: EnemyEntity in enemy_store.entities:
		if _is_ally_acquirable(enemy, player_position, current_tick):
			targets.append(enemy)
	targets.sort_custom(func(left: EnemyEntity, right: EnemyEntity) -> bool:
		return left.entity_id < right.entity_id
	)
	return targets


func _first_target(
	enemy_store: EnemyStore,
	sort_origin: Vector2,
	player_position: Vector2,
	current_tick: int,
) -> EnemyEntity:
	var targets: Array[EnemyEntity] = _targets_by_distance(
		enemy_store,
		sort_origin,
		player_position,
		current_tick,
	)
	return null if targets.is_empty() else targets[0]


func _is_ally_targetable(enemy: EnemyEntity, current_tick: int) -> bool:
	return enemy != null and enemy.hp > 0.0 and enemy.is_targetable(current_tick)


func _is_ally_acquirable(
	enemy: EnemyEntity,
	player_position: Vector2,
	current_tick: int,
) -> bool:
	return (
		_is_ally_targetable(enemy, current_tick)
		and enemy.position.distance_squared_to(player_position)
		<= CombatEnvelope.TARGET_CENTER_RADIUS * CombatEnvelope.TARGET_CENTER_RADIUS
	)


func _is_ally_damageable(
	enemy: EnemyEntity,
	player_position: Vector2,
	current_tick: int,
) -> bool:
	return (
		_is_ally_targetable(enemy, current_tick)
		and enemy.position.distance_squared_to(player_position)
		<= CombatEnvelope.DAMAGE_CENTER_RADIUS * CombatEnvelope.DAMAGE_CENTER_RADIUS
	)


func _projectile_effect_outer_distance(
	projectile: ProjectileState,
	player_position: Vector2,
) -> float:
	return (
		player_position.distance_to(projectile.position)
		+ maxf(projectile.radius, projectile.explosion_radius)
	)


func _intersection_less(left: Dictionary, right: Dictionary) -> bool:
	var left_t: float = float(left["t"])
	var right_t: float = float(right["t"])
	if not is_equal_approx(left_t, right_t):
		return left_t < right_t
	return int(left["entity_id"]) < int(right["entity_id"])
