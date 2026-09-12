class_name WeaponSystem
extends RefCounted


const MIN_COOLDOWN_TICKS: int = 1
const PROJECTILE_HEIGHT_M: float = 0.35
const AIM_DIRECTION_EPSILON_SQUARED: float = 0.000001


class AttackSequenceState:
	extends RefCounted

	var remaining_shots: int = 0
	var shot_index: int = 0
	var next_shot_tick: int = 0
	var target_entity_id: int = -1
	var last_direction: Vector2 = Vector2.RIGHT


var _state: RunState = null
var _catalog: DefinitionCatalog = null
var _projectile_pool: ProjectilePool = null
var _router: CombatEventRouter = null
var _last_move_direction: Vector2 = Vector2.RIGHT
var _orbital_active_until_by_lineage: Dictionary[StringName, int] = {}
var _orbital_next_damage_tick_by_lineage: Dictionary[StringName, int] = {}
var _attack_sequences: Dictionary[StringName, AttackSequenceState] = {}


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
	_attack_sequences.clear()


func update_move_direction(move_direction: Vector2) -> void:
	if move_direction.length_squared() > 0.000001:
		_last_move_direction = move_direction.normalized()


func advance_and_fire(
	player_position: Vector2,
	enemy_store: EnemyStore,
	uniform_grid: UniformGrid,
	current_tick: int,
) -> Array[Dictionary]:
	_projectile_pool.world.set_context(CombatNative.context(_catalog, _state, player_position, current_tick))
	var results: Array[Dictionary] = []
	var stats: Dictionary = StatCalculator.aggregate(_state, _catalog)
	for slot_index: int in range(_state.weapons.size()):
		var runtime: RunWeapon = _state.weapons[slot_index]
		var definition: WeaponDefinition = _catalog.weapon(runtime.weapon_id)
		if definition == null:
			continue
		if definition.uses_attack_sequence():
			var sequence_result: Dictionary = _advance_attack_sequence(
				runtime,
				definition,
				slot_index,
				player_position,
				enemy_store,
				current_tick,
				stats,
			)
			if bool(sequence_result.get("generated", false)):
				results.append(sequence_result)
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
			_attack_sequences.erase(runtime.lineage_id)
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
		roundi(float(definition.cooldown_ticks_at(level)) * StatCalculator.cooldown_multiplier(stats, _catalog.manifest().combat)),
	)


func move_snapshot_projectiles(entries: PackedInt64Array, _enemy_store: EnemyStore,
	player_position: Vector2, current_tick: int, stop_active: bool) -> void:
	var context: Dictionary = CombatNative.context(_catalog, _state, player_position, current_tick)
	context.stopped = stop_active
	_projectile_pool.world.set_context(context)
	_projectile_pool.world.move_projectiles(entries)


func resolve_ally_projectile(entry: PackedInt64Array, _enemy_store: EnemyStore, _uniform_grid: UniformGrid,
	player_position: Vector2, current_tick: int, resolution: Dictionary = {}) -> Array[Dictionary]:
	# Explicit inspection API: production resolves the complete stage without hit records.
	resolution.clear()
	if entry.size() != 2:
		return []
	_projectile_pool.world.set_context(CombatNative.context(_catalog, _state, player_position, current_tick))
	var result: Dictionary = _projectile_pool.world.resolve_projectiles(entry, false, false)
	if not result.resolutions.is_empty():
		resolution.merge(result.resolutions[0])
	var records: Array[Dictionary] = []
	for row: Dictionary in result.hits:
		row.event = _router.create_primary(_state, &"projectile_hit", int(row.source_entity_id),
			row.source_effect_id, float(row.damage), row.position, row.direction)
		records.append(row)
	return records


func resolve_enemy_projectile(entry: PackedInt64Array, player_position: Vector2, current_tick: int) -> Dictionary:
	if entry.size() != 2:
		return {}
	_projectile_pool.world.set_context(CombatNative.context(_catalog, _state, player_position, current_tick))
	var hits: Array = _projectile_pool.world.hostile_projectile_hits(entry)
	return hits[0] if not hits.is_empty() else {}


func orbital_transforms(player_position: Vector2, current_tick: int) -> Array[Transform3D]:
	var transforms: Array[Transform3D] = []
	var stats: Dictionary = StatCalculator.aggregate(_state, _catalog)
	for runtime: RunWeapon in _state.weapons:
		var definition: WeaponDefinition = _catalog.weapon(runtime.weapon_id)
		if definition == null or definition.behavior != GameTypes.WeaponBehavior.ORBITAL:
			continue
		if not orbital_is_active(runtime.lineage_id, current_tick):
			continue
		var area: float = StatCalculator.area_multiplier(stats, _catalog.manifest().combat)
		var orbit_radius: float = StatCalculator.weapon_range(definition, runtime.level, area)
		var visual_radius: float = minf(
			maxf(0.0, _catalog.envelope.effect_outer_radius - orbit_radius),
			maxf(0.0, StatCalculator.weapon_effect_radius(definition, runtime.level, area)),
		)
		for position: Vector2 in _orbital_positions(
			runtime,
			definition,
			player_position,
			current_tick,
			stats,
		):
			var radial: Vector2 = (position - player_position).normalized()
			var tangent := Vector3(-radial.y, 0.0, radial.x)
			transforms.append(Transform3D(
				Basis(Vector3(radial.x, 0.0, radial.y) * visual_radius, Vector3.UP, tangent * visual_radius),
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
		_sorted_attack_sequence_entries(),
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
		GameTypes.WeaponBehavior.HOMING_PROJECTILE:
			return _fire_homing(runtime, definition, player_position, enemy_store, current_tick, stats)
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


func _fire_melee_swing(
	runtime: RunWeapon,
	definition: WeaponDefinition,
	player_position: Vector2,
	stats: Dictionary,
	sequence: AttackSequenceState,
) -> Dictionary:
	var range_m: float = StatCalculator.weapon_range(definition, runtime.level,
		StatCalculator.area_multiplier(stats, _catalog.manifest().combat))
	var direction: Vector2 = sequence.last_direction if sequence.shot_index % 2 == 0 else -sequence.last_direction
	var shapes: Array[Dictionary] = [{"center": player_position, "radius": range_m,
		"direction": direction, "arc_degrees": _catalog.manifest().combat.melee_arc_degrees}]
	return {
		"generated": true,
		"weapon_id": runtime.weapon_id,
		"lineage_id": runtime.lineage_id,
		"origin": player_position,
		"direction": direction,
		"range_m": range_m,
		"native_result": _native_attack(runtime, definition, stats, shapes, range_m, false),
		"visual_shapes": shapes,
		"node_damage_zones": [],
	}


func _fire_homing(
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
	var direction: Vector2 = _homing_aim_direction(player_position, target.position, _last_move_direction)
	for _projectile_index: int in range(amount):
		_spawn_ally_projectile(runtime, definition, player_position, direction, target.entity_id, stats, current_tick, ProjectileState.MovementKind.HOMING)
	return _projectile_result(
		runtime,
		player_position,
		direction,
		StatCalculator.weapon_range(definition, runtime.level, StatCalculator.area_multiplier(stats, _catalog.manifest().combat)),
	)


func _advance_attack_sequence(
	runtime: RunWeapon,
	definition: WeaponDefinition,
	slot_index: int,
	player_position: Vector2,
	enemy_store: EnemyStore,
	current_tick: int,
	stats: Dictionary,
) -> Dictionary:
	var lineage_id: StringName = runtime.lineage_id
	if runtime.ready_on_resume:
		runtime.ready_on_resume = false
		runtime.cooldown_remaining_ticks = 0
		_attack_sequences.erase(lineage_id)
	elif runtime.cooldown_remaining_ticks > 0:
		runtime.cooldown_remaining_ticks -= 1
	var sequence: AttackSequenceState = _attack_sequences.get(lineage_id) as AttackSequenceState
	if sequence != null and current_tick < sequence.next_shot_tick:
		return {"generated": false}
	if sequence == null:
		if runtime.cooldown_remaining_ticks > 0:
			return {"generated": false}
		var target: EnemyEntity = null
		if definition.behavior != GameTypes.WeaponBehavior.MELEE_WAVE:
			target = _first_target(enemy_store, player_position, player_position, current_tick)
			if target == null:
				return {"generated": false}
		sequence = AttackSequenceState.new()
		sequence.remaining_shots = definition.amount_at(runtime.level)
		sequence.last_direction = _last_move_direction
		if target != null:
			sequence.target_entity_id = target.entity_id
		runtime.cooldown_remaining_ticks = effective_cooldown_ticks(definition, runtime.level, stats)
	var result: Dictionary
	match definition.behavior:
		GameTypes.WeaponBehavior.MELEE_WAVE:
			result = _fire_melee_swing(runtime, definition, player_position, stats, sequence)
		GameTypes.WeaponBehavior.DIRECTIONAL_PROJECTILE:
			_spawn_ally_projectile(runtime, definition, player_position, _last_move_direction,
				-1, stats, current_tick, ProjectileState.MovementKind.STRAIGHT)
			result = _projectile_result(runtime, player_position, _last_move_direction,
				StatCalculator.weapon_range(definition, runtime.level,
					StatCalculator.area_multiplier(stats, _catalog.manifest().combat)))
		_:
			result = _fire_pending_homing_core_shot(runtime, definition, player_position,
				enemy_store, current_tick, stats, sequence)
	sequence.remaining_shots -= 1
	sequence.shot_index += 1
	if sequence.remaining_shots > 0:
		sequence.next_shot_tick = current_tick + definition.shot_interval_ticks_at(runtime.level)
		_attack_sequences[lineage_id] = sequence
	else:
		_attack_sequences.erase(lineage_id)
	result["slot_index"] = slot_index
	return result


func _fire_pending_homing_core_shot(
	runtime: RunWeapon,
	definition: WeaponDefinition,
	player_position: Vector2,
	enemy_store: EnemyStore,
	current_tick: int,
	stats: Dictionary,
	burst: AttackSequenceState,
) -> Dictionary:
	var target: EnemyEntity = enemy_store.get_by_id(burst.target_entity_id)
	if not _is_ally_acquirable(target, player_position, current_tick):
		target = _first_target(
			enemy_store,
			player_position,
			player_position,
			current_tick,
		)
	var target_entity_id: int = -1
	var direction: Vector2 = burst.last_direction
	if target != null:
		target_entity_id = target.entity_id
		direction = _homing_aim_direction(
			player_position,
			target.position,
			burst.last_direction,
		)
		burst.target_entity_id = target_entity_id
		burst.last_direction = direction
	else:
		burst.target_entity_id = -1
	_spawn_ally_projectile(
		runtime,
		definition,
		player_position,
		direction,
		target_entity_id,
		stats,
		current_tick,
		ProjectileState.MovementKind.STRAIGHT,
	)
	return _projectile_result(
		runtime,
		player_position,
		direction,
		StatCalculator.weapon_range(definition,
			runtime.level,
			StatCalculator.area_multiplier(stats, _catalog.manifest().combat),
		),
	)


func _homing_aim_direction(
	origin: Vector2,
	target_position: Vector2,
	fallback: Vector2,
) -> Vector2:
	var offset: Vector2 = target_position - origin
	if offset.length_squared() > AIM_DIRECTION_EPSILON_SQUARED:
		return offset.normalized()
	if fallback.length_squared() > AIM_DIRECTION_EPSILON_SQUARED:
		return fallback.normalized()
	if _last_move_direction.length_squared() > AIM_DIRECTION_EPSILON_SQUARED:
		return _last_move_direction.normalized()
	return Vector2.RIGHT


func _fire_arc(
	runtime: RunWeapon,
	definition: WeaponDefinition,
	player_position: Vector2,
	enemy_store: EnemyStore,
	current_tick: int,
	stats: Dictionary,
) -> Dictionary:
	var targets: Array[EnemyEntity] = []
	if runtime.weapon_id == &"spiral_crystal":
		if _first_target(enemy_store, player_position, player_position, current_tick) == null:
			return {"generated": false}
	else:
		targets = _targets_by_distance(enemy_store, player_position, player_position, current_tick)
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
			StatCalculator.weapon_range(definition, runtime.level, StatCalculator.area_multiplier(stats, _catalog.manifest().combat)),
		)
	for projectile_index: int in range(amount):
		var target: EnemyEntity = targets[projectile_index % targets.size()]
		var direction: Vector2 = (target.position - player_position).normalized()
		_spawn_ally_projectile(runtime, definition, player_position, direction, target.entity_id, stats, current_tick, ProjectileState.MovementKind.ARC, target.position)
	return _projectile_result(
		runtime,
		player_position,
		(targets[0].position - player_position).normalized(),
		StatCalculator.weapon_range(definition, runtime.level, StatCalculator.area_multiplier(stats, _catalog.manifest().combat)),
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
		var spread: float = deg_to_rad(_catalog.manifest().combat.returning_ring_spread_degrees) * (float(projectile_index) - float(amount - 1) * 0.5)
		_spawn_ally_projectile(runtime, definition, player_position, Vector2.from_angle(base_angle + spread), target.entity_id, stats, current_tick, ProjectileState.MovementKind.RETURNING)
	return _projectile_result(
		runtime,
		player_position,
		Vector2.from_angle(base_angle),
		StatCalculator.weapon_range(definition, runtime.level, StatCalculator.area_multiplier(stats, _catalog.manifest().combat)),
	)


func _fire_orbital(
	runtime: RunWeapon,
	definition: WeaponDefinition,
	player_position: Vector2,
	_enemy_store: EnemyStore,
	_uniform_grid: UniformGrid,
	current_tick: int,
	stats: Dictionary,
) -> Dictionary:
	var area_multiplier: float = StatCalculator.area_multiplier(stats, _catalog.manifest().combat)
	var orbit_radius: float = maxf(
		0.0,
		StatCalculator.weapon_range(definition, runtime.level, area_multiplier),
	)
	var hit_radius: float = minf(
		StatCalculator.weapon_effect_radius(definition, runtime.level, area_multiplier),
		maxf(0.0, _catalog.envelope.effect_outer_radius - orbit_radius),
	)
	var shapes: Array[Dictionary] = []
	for position: Vector2 in _orbital_positions(runtime, definition, player_position, current_tick, stats):
		shapes.append({"center": position, "radius": hit_radius})
	var native_result: Dictionary = _native_attack(runtime, definition, stats, shapes, orbit_radius + hit_radius, true)
	return {
		"generated": true,
		"weapon_id": runtime.weapon_id,
		"lineage_id": runtime.lineage_id,
		"origin": player_position,
		"direction": Vector2.RIGHT,
		"range_m": orbit_radius,
		"native_result": native_result,
		"node_damage_zones": [],
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
			current_tick + _catalog.manifest().combat.orbital_damage_interval_ticks
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
			current_tick + _catalog.manifest().combat.orbital_damage_interval_ticks
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
			* StatCalculator.duration_multiplier(stats, _catalog.manifest().combat)
		),
	)
	_orbital_active_until_by_lineage[lineage_id] = current_tick + duration_ticks
	_orbital_next_damage_tick_by_lineage[lineage_id] = (
		current_tick + _catalog.manifest().combat.orbital_damage_interval_ticks
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
		0.0,
		StatCalculator.weapon_range(definition,
			runtime.level,
			StatCalculator.area_multiplier(stats, _catalog.manifest().combat),
		),
	)
	var tangential_speed: float = maxf(
		0.0,
		definition.projectile_speed_at(runtime.level)
		* StatCalculator.projectile_speed_multiplier(stats, _catalog.manifest().combat),
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


func _sorted_attack_sequence_entries() -> Array:
	var keys: Array[String] = []
	for key_value: Variant in _attack_sequences:
		keys.append(String(key_value))
	keys.sort()
	var result: Array = []
	for key_text: String in keys:
		var lineage_id := StringName(key_text)
		var burst: AttackSequenceState = (
			_attack_sequences.get(lineage_id) as AttackSequenceState
		)
		if burst == null:
			continue
		result.append([
			key_text,
			burst.remaining_shots,
			burst.shot_index,
			burst.next_shot_tick,
			burst.target_entity_id,
			burst.last_direction,
		])
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
	_enemy_store: EnemyStore,
	current_tick: int,
	stats: Dictionary,
) -> Dictionary:
	var area_multiplier: float = StatCalculator.area_multiplier(stats, _catalog.manifest().combat)
	var travel_distance: float = StatCalculator.weapon_range(definition,
		runtime.level,
		area_multiplier,
	)
	var projectile_radius: float = maxf(
		0.0,
		StatCalculator.weapon_projectile_radius(definition, runtime.level, area_multiplier),
	)
	_projectile_pool.world.set_context(CombatNative.context(_catalog, _state, player_position, current_tick))
	var selected: Dictionary = _projectile_pool.world.choose_target_shots(maxi(1, definition.amount_at(runtime.level)),
		travel_distance + projectile_radius, {"base": _base_damage(definition, runtime, stats),
			"chance": definition.critical_chance, "multiplier": definition.critical_multiplier}, runtime.rng)
	if selected.shots.is_empty():
		return {"generated": false}
	for shot: Dictionary in selected.shots:
		_spawn_ally_projectile(runtime, definition, player_position, shot.direction, int(shot.id), stats,
			current_tick, ProjectileState.MovementKind.STRAIGHT, Vector2.ZERO, float(shot.damage))
	return _projectile_result(
		runtime,
		player_position,
		selected.direction,
		travel_distance,
	)


func _fire_aura(
	runtime: RunWeapon,
	definition: WeaponDefinition,
	player_position: Vector2,
	_enemy_store: EnemyStore,
	_uniform_grid: UniformGrid,
	_current_tick: int,
	stats: Dictionary,
) -> Dictionary:
	var radius: float = minf(
		_catalog.envelope.effect_outer_radius,
		maxf(
			0.0,
			StatCalculator.weapon_effect_radius(definition,
				runtime.level,
				StatCalculator.area_multiplier(stats, _catalog.manifest().combat),
			),
		),
	)
	var shapes: Array[Dictionary] = [{"center": player_position, "radius": radius}]
	var native_result: Dictionary = _native_attack(runtime, definition, stats, shapes, radius, true)
	return {
		"generated": true,
		"weapon_id": runtime.weapon_id,
		"lineage_id": runtime.lineage_id,
		"origin": player_position,
		"direction": Vector2.RIGHT,
		"range_m": radius,
		"native_result": native_result,
		"visual_shapes": shapes,
		"node_damage_zones": [],
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
	damage_override: float = -1.0,
) -> void:
	var speed: float = maxf(0.0, definition.projectile_speed_at(runtime.level) * StatCalculator.projectile_speed_multiplier(stats, _catalog.manifest().combat))
	var duration_ticks: int = maxi(1, roundi(float(definition.duration_ticks_at(runtime.level)) * StatCalculator.duration_multiplier(stats, _catalog.manifest().combat)))
	var lifetime_seconds: float = float(duration_ticks) / float(RunState.TICKS_PER_SECOND)
	var area_multiplier: float = StatCalculator.area_multiplier(stats, _catalog.manifest().combat)
	var range_m: float = maxf(
		0.0,
		StatCalculator.weapon_range(definition, runtime.level, area_multiplier),
	)
	var projectile_radius: float = maxf(
		0.0,
		StatCalculator.weapon_projectile_radius(definition, runtime.level, area_multiplier),
	)
	var effect_radius: float = maxf(
		0.0,
		StatCalculator.weapon_effect_radius(definition, runtime.level, area_multiplier),
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
		if speed > 0.0:
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
		damage_override if damage_override >= 0.0 else _roll_damage(definition, runtime, stats),
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


func _base_damage(definition: WeaponDefinition, runtime: RunWeapon, stats: Dictionary) -> float:
	var damage: float = definition.damage_at(runtime.level) * StatCalculator.might_multiplier(stats)
	if runtime.weapon_id == &"absorption_field":
		damage *= 1.0 + StatCalculator.recovery_per_second(stats)
	return maxf(0.0, damage)


func _roll_damage(definition: WeaponDefinition, runtime: RunWeapon, stats: Dictionary) -> float:
	var damage: float = _base_damage(definition, runtime, stats)
	if definition.critical_chance > 0.0 and runtime.rng != null and WeightedSelector.chance_succeeds_with_value(definition.critical_chance, runtime.rng.randf()):
		damage *= maxf(1.0, definition.critical_multiplier)
	return damage


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


func _targets_by_distance(enemy_store: EnemyStore, sort_origin: Vector2, player_position: Vector2, current_tick: int) -> Array[EnemyEntity]:
	enemy_store.world.set_context(CombatNative.context(_catalog, _state, player_position, current_tick))
	var targets: Array[EnemyEntity] = []
	for id: int in enemy_store.world.target_ids(sort_origin, true, -1.0):
		targets.append(enemy_store.get_by_id(id))
	return targets


func _first_target(enemy_store: EnemyStore, sort_origin: Vector2, player_position: Vector2, current_tick: int) -> EnemyEntity:
	enemy_store.world.set_context(CombatNative.context(_catalog, _state, player_position, current_tick))
	return enemy_store.get_by_id(enemy_store.world.nearest_enemy(sort_origin))


func _is_ally_acquirable(
	enemy: EnemyEntity,
	player_position: Vector2,
	current_tick: int,
) -> bool:
	return (
		enemy != null and enemy.hp > 0.0 and enemy.alive and current_tick >= enemy.activation_tick
		and enemy.position.distance_squared_to(player_position)
		<= _catalog.envelope.target_center_radius * _catalog.envelope.target_center_radius
	)


func _native_attack(runtime: RunWeapon, definition: WeaponDefinition, stats: Dictionary,
	shapes: Array[Dictionary], outer: float, deduplicate: bool) -> Dictionary:
	return _projectile_pool.world.attack_shapes(shapes, {
		"damage": _base_damage(definition, runtime, stats), "critical_chance": definition.critical_chance,
		"critical_multiplier": definition.critical_multiplier, "outer": outer,
		"source": runtime.lineage_id, "weapon_id": runtime.weapon_id, "deduplicate": deduplicate,
	}, runtime.rng)
