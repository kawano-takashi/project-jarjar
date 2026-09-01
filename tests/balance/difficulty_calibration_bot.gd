class_name DifficultyCalibrationBot
extends RefCounted


enum Policy { CAUTIOUS, NORMAL, EVOLUTION }

const DECISION_INTERVAL_TICKS: int = 15
const AWARENESS_RADIUS: float = CombatEnvelope.BOT_AWARENESS_RADIUS
const MAX_THREATS_PER_KIND: int = 8
const PLAYER_RADIUS: float = 0.45
const WALL_MARGIN: float = 2.0
const WALL_WEIGHT: float = 4.0
const TANGENT_WEIGHT: float = 0.35
const LOW_CONFIDENCE_THRESHOLD: float = 0.35
const ESCAPE_DIRECTION_COUNT: int = 16
const OBJECTIVE_XP: int = -1
const PATROL_WAYPOINTS: Array[Vector2] = [
	Vector2(-10.0, -10.0),
	Vector2(10.0, -10.0),
	Vector2(10.0, 10.0),
	Vector2(-10.0, 10.0),
]
const ENEMY_CLEARANCE_BY_POLICY: Array[float] = [5.0, 4.0, 3.25]
const PROJECTILE_CLEARANCE_BY_POLICY: Array[float] = [4.0, 3.5, 3.0]
const TELEGRAPH_MARGIN_BY_POLICY: Array[float] = [2.0, 1.5, 1.25]
const DANGER_WEIGHT_BY_POLICY: Array[float] = [3.0, 2.25, 1.75]
const OBJECTIVE_WEIGHT_BY_POLICY: Array[float] = [0.75, 1.5, 2.25]
const CAUTIOUS_UPGRADE_PRIORITY: Array[StringName] = [
	&"repair_core",
	&"life_lattice",
	&"zero_field",
	&"resonance_wave",
]

var policy: int = Policy.NORMAL
var _held_input: Vector2 = Vector2.ZERO
var _last_decision_tick: int = -DECISION_INTERVAL_TICKS
var _handedness: float = 1.0
var _patrol_index: int = 0
var _prefer_lower_id: bool = true
var _seen_chests: Dictionary[int, Vector2] = {}
var _normal_focus_lineage: StringName = &""
var _last_threat_counts: Dictionary[String, int] = {
	"enemy": 0,
	"projectile": 0,
	"telegraph": 0,
}
var _last_avoidance_debug: Dictionary = {
	"pressure": 0.0,
	"resultant": 0.0,
	"confidence": 1.0,
	"used_low_confidence_escape": false,
}


func initialize(p_policy: int, run_seed: int) -> bool:
	if p_policy < Policy.CAUTIOUS or p_policy > Policy.EVOLUTION:
		return false
	policy = p_policy
	_held_input = Vector2.ZERO
	_last_decision_tick = -DECISION_INTERVAL_TICKS
	_handedness = -1.0 if (absi(run_seed) % 2) == 0 else 1.0
	_patrol_index = absi(run_seed) % PATROL_WAYPOINTS.size()
	_prefer_lower_id = (absi(run_seed) % 2) != 0
	_seen_chests.clear()
	_normal_focus_lineage = &""
	_last_threat_counts = {"enemy": 0, "projectile": 0, "telegraph": 0}
	_last_avoidance_debug = {
		"pressure": 0.0,
		"resultant": 0.0,
		"confidence": 1.0,
		"used_low_confidence_escape": false,
	}
	return true


func movement_input(simulation: CombatSimulation) -> Vector2:
	if simulation == null or simulation.state == null:
		return Vector2.ZERO
	var current_tick: int = simulation.state.combat_tick
	if current_tick - _last_decision_tick < DECISION_INTERVAL_TICKS:
		return _held_input
	_last_decision_tick = current_tick
	_held_input = _decide_movement(simulation)
	return _held_input


func choose_upgrade(
	offer: LevelOffer,
	state: RunState,
	catalog: DefinitionCatalog,
) -> int:
	if offer == null or state == null or catalog == null or offer.options.is_empty():
		return -1
	if policy == Policy.CAUTIOUS:
		for preferred_id: StringName in CAUTIOUS_UPGRADE_PRIORITY:
			var preferred_index: int = _find_option(offer, preferred_id)
			if preferred_index >= 0:
				return preferred_index
	elif policy == Policy.EVOLUTION:
		if state.passive(&"cycle_crystal") == null:
			var cycle_index: int = _find_option(offer, &"cycle_crystal")
			if cycle_index >= 0:
				return cycle_index
		var homing: RunWeapon = state.weapon_for_lineage(&"homing_core")
		if homing != null and not homing.evolved and homing.level < 8:
			var homing_index: int = _find_option(offer, &"homing_core")
			if homing_index >= 0:
				return homing_index
	return _normal_upgrade_choice(offer, state, catalog)


static func policy_name_for(value: int) -> String:
	match value:
		Policy.CAUTIOUS:
			return "cautious"
		Policy.NORMAL:
			return "normal"
		Policy.EVOLUTION:
			return "evolution"
	return "invalid"


func debug_state() -> Dictionary:
	return {
		"seen_chest_count": _seen_chests.size(),
		"threat_counts": _last_threat_counts.duplicate(),
		"avoidance": _last_avoidance_debug.duplicate(),
	}


func deterministic_state_values() -> Array:
	var chest_ids: Array[int] = []
	for pickup_id: int in _seen_chests:
		chest_ids.append(pickup_id)
	chest_ids.sort()
	var chest_entries: Array = []
	for pickup_id: int in chest_ids:
		chest_entries.append([pickup_id, _seen_chests[pickup_id]])
	return [
		policy,
		_held_input,
		_last_decision_tick,
		_handedness,
		_patrol_index,
		_prefer_lower_id,
		chest_entries,
		_last_threat_counts.duplicate(),
		String(_normal_focus_lineage),
	]


func _decide_movement(simulation: CombatSimulation) -> Vector2:
	var player_position: Vector2 = simulation.player_position
	_observe_chests(simulation, player_position)
	var threats: Array[Dictionary] = _collect_threats(simulation, player_position)
	var danger_resultant: Vector2 = Vector2.ZERO
	var danger_pressure: float = 0.0
	var nearest_away: Vector2 = Vector2.ZERO
	for threat_index: int in range(threats.size()):
		var threat: Dictionary = threats[threat_index]
		var away: Vector2 = threat.get("away", Vector2.ZERO)
		var weight: float = float(threat.get("weight", 0.0))
		if threat_index == 0:
			nearest_away = away
		danger_resultant += away * weight
		danger_pressure += weight

	var resultant_length: float = danger_resultant.length()
	var confidence: float = (
		resultant_length / danger_pressure
		if danger_pressure > 0.000001
		else 1.0
	)
	var used_low_confidence_escape: bool = false
	var objective: Vector2 = _objective_direction(simulation, player_position)
	var wall: Vector2 = _wall_correction(player_position)
	var combined: Vector2 = Vector2.ZERO
	if danger_pressure > 0.000001 and not threats.is_empty():
		# A summed steering vector can both cancel in a crowd and still point into
		# one of its members. Score deterministic current-information headings;
		# close/multiple threats increase only the penalty for heading toward them.
		combined = _threat_aware_heading(
			threats,
			objective,
			wall,
			danger_pressure,
			danger_resultant,
			nearest_away,
		)
		used_low_confidence_escape = confidence < LOW_CONFIDENCE_THRESHOLD
	else:
		combined = (
			objective * OBJECTIVE_WEIGHT_BY_POLICY[policy]
			+ wall * WALL_WEIGHT
		)
	_last_avoidance_debug = {
		"pressure": danger_pressure,
		"resultant": resultant_length,
		"confidence": confidence,
		"used_low_confidence_escape": used_low_confidence_escape,
	}
	combined = _enforce_wall_inward(combined, wall)
	if combined.length_squared() <= 0.000001:
		return Vector2.ZERO
	return combined.normalized()


func _threat_aware_heading(
	threats: Array[Dictionary],
	objective: Vector2,
	wall: Vector2,
	danger_pressure: float,
	danger_resultant: Vector2,
	nearest_away: Vector2,
) -> Vector2:
	var nearest_id: int = int(threats[0].get("stable_id", 0))
	var start_index: int = absi(nearest_id) % ESCAPE_DIRECTION_COUNT
	var index_step: int = 1 if _prefer_lower_id else -1
	var candidates: Array[Vector2] = []
	if _held_input.length_squared() > 0.000001:
		candidates.append(_held_input.normalized())
	if objective.length_squared() > 0.000001:
		candidates.append(objective.normalized())
	if danger_resultant.length_squared() > 0.000001:
		candidates.append(danger_resultant.normalized())
	var tangent: Vector2 = Vector2(-nearest_away.y, nearest_away.x) * _handedness
	var kite_direction: Vector2 = nearest_away + tangent * TANGENT_WEIGHT
	if kite_direction.length_squared() > 0.000001:
		candidates.append(kite_direction.normalized())
	for offset: int in range(ESCAPE_DIRECTION_COUNT):
		var direction_index: int = wrapi(
			start_index + offset * index_step,
			0,
			ESCAPE_DIRECTION_COUNT,
		)
		candidates.append(Vector2.from_angle(
			TAU * float(direction_index) / float(ESCAPE_DIRECTION_COUNT)
		))
	var best_direction: Vector2 = Vector2.ZERO
	var best_score: float = -INF
	var continuity_weight: float = (
		TANGENT_WEIGHT * (1.0 + minf(3.0, danger_pressure))
	)
	for direction: Vector2 in candidates:
		var score: float = (
			direction.dot(objective) * OBJECTIVE_WEIGHT_BY_POLICY[policy]
			+ direction.dot(wall) * WALL_WEIGHT
			+ direction.dot(_held_input) * continuity_weight
		)
		for threat: Dictionary in threats:
			var away: Vector2 = threat.get("away", Vector2.ZERO)
			var weight: float = float(threat.get("weight", 0.0))
			var alignment: float = direction.dot(away)
			var alignment_scale: float = (
				1.0 + danger_pressure
				if alignment < 0.0
				else TANGENT_WEIGHT
			)
			score += (
				alignment
				* weight
				* DANGER_WEIGHT_BY_POLICY[policy]
				* alignment_scale
			)
		if score > best_score + 0.000001:
			best_score = score
			best_direction = direction
	return best_direction


func _collect_threats(
	simulation: CombatSimulation,
	player_position: Vector2,
) -> Array[Dictionary]:
	var enemy_threats: Array[Dictionary] = []
	var projectile_threats: Array[Dictionary] = []
	var telegraph_threats: Array[Dictionary] = []
	var enemy_clearance_limit: float = ENEMY_CLEARANCE_BY_POLICY[policy]
	var projectile_clearance_limit: float = PROJECTILE_CLEARANCE_BY_POLICY[policy]
	var telegraph_margin: float = TELEGRAPH_MARGIN_BY_POLICY[policy]
	for entity_id: int in simulation.enemy_system.enemy_store.snapshot_ids_sorted():
		var enemy: EnemyEntity = simulation.enemy_system.enemy_store.get_by_id(entity_id)
		if enemy == null or not enemy.is_targetable(simulation.state.combat_tick):
			continue
		var offset: Vector2 = player_position - enemy.position
		var distance: float = offset.length()
		if distance <= AWARENESS_RADIUS:
			var clearance: float = distance - PLAYER_RADIUS - enemy.body_radius()
			if clearance <= enemy_clearance_limit:
				var type_multiplier: float = 1.0
				if enemy.enemy_type == GameTypes.EnemyType.ELITE:
					type_multiplier = 2.0
				elif enemy.enemy_type == GameTypes.EnemyType.BOSS:
					type_multiplier = 3.0
				enemy_threats.append(_threat(
					clearance,
					_away_direction(offset, entity_id),
					_normalized_urgency(clearance, enemy_clearance_limit) * type_multiplier,
					entity_id * 4,
				))
		if enemy.telegraph_active:
			var telegraph_offset: Vector2 = player_position - enemy.telegraph_position
			var telegraph_distance: float = telegraph_offset.length()
			var telegraph_clearance: float = (
				telegraph_distance - PLAYER_RADIUS - enemy.definition.area_radius
			)
			if telegraph_distance <= AWARENESS_RADIUS and telegraph_clearance <= telegraph_margin:
				telegraph_threats.append(_threat(
					telegraph_clearance,
					_away_direction(telegraph_offset, entity_id + 1),
					3.0 * _normalized_urgency(telegraph_clearance, telegraph_margin),
					entity_id * 4 + 1,
				))

	for pool_index: int in simulation.projectile_pool.active_indices_snapshot():
		var projectile: ProjectileState = simulation.projectile_pool.slots[pool_index]
		if projectile.faction != ProjectileState.FACTION_ENEMY:
			continue
		var projectile_offset: Vector2 = player_position - projectile.position
		var projectile_distance: float = projectile_offset.length()
		if projectile_distance > AWARENESS_RADIUS:
			continue
		var projectile_clearance: float = (
			projectile_distance - PLAYER_RADIUS - projectile.radius
		)
		if projectile_clearance > projectile_clearance_limit:
			continue
		projectile_threats.append(_threat(
			projectile_clearance,
			_away_direction(projectile_offset, pool_index + 1),
			2.0 * _normalized_urgency(projectile_clearance, projectile_clearance_limit),
			1_000_000 + pool_index,
		))
	enemy_threats.sort_custom(_threat_less)
	projectile_threats.sort_custom(_threat_less)
	telegraph_threats.sort_custom(_threat_less)
	var threats: Array[Dictionary] = []
	_append_top_threats(threats, enemy_threats)
	_append_top_threats(threats, projectile_threats)
	_append_top_threats(threats, telegraph_threats)
	_last_threat_counts = {
		"enemy": mini(MAX_THREATS_PER_KIND, enemy_threats.size()),
		"projectile": mini(MAX_THREATS_PER_KIND, projectile_threats.size()),
		"telegraph": mini(MAX_THREATS_PER_KIND, telegraph_threats.size()),
	}
	threats.sort_custom(_threat_less)
	return threats


func _objective_direction(
	simulation: CombatSimulation,
	player_position: Vector2,
) -> Vector2:
	var categories: Array[int] = _objective_categories(simulation.state)
	for category: int in categories:
		var target: Dictionary = (
			_nearest_xp(simulation, player_position)
			if category == OBJECTIVE_XP
			else (
				_nearest_seen_chest(player_position)
				if category == int(ArenaPickup.Kind.CHEST)
				else _nearest_arena_pickup(simulation, player_position, category)
			)
		)
		if bool(target.get("found", false)):
			var target_position: Vector2 = target.get("position", player_position)
			var offset: Vector2 = target_position - player_position
			if offset.length_squared() > 0.000001:
				return offset.normalized()
	return _patrol_direction(player_position)


func _objective_categories(state: RunState) -> Array[int]:
	var hp_ratio: float = state.current_hp / maxf(1.0, state.max_hp)
	if policy == Policy.CAUTIOUS:
		var cautious: Array[int] = []
		if hp_ratio <= 0.70:
			cautious.append(int(ArenaPickup.Kind.HEAL))
		cautious.append_array([
			int(ArenaPickup.Kind.CHEST),
			int(ArenaPickup.Kind.STOP),
			int(ArenaPickup.Kind.VACUUM),
			OBJECTIVE_XP,
		])
		return cautious
	var result: Array[int] = [int(ArenaPickup.Kind.CHEST)]
	var heal_threshold: float = 0.60 if policy == Policy.NORMAL else 0.50
	if hp_ratio <= heal_threshold:
		result.append(int(ArenaPickup.Kind.HEAL))
	result.append_array([
		OBJECTIVE_XP,
		int(ArenaPickup.Kind.VACUUM),
		int(ArenaPickup.Kind.STOP),
	])
	return result


func _nearest_arena_pickup(
	simulation: CombatSimulation,
	player_position: Vector2,
	kind_value: int,
) -> Dictionary:
	var result: Dictionary = {"found": false}
	var best_distance_squared: float = AWARENESS_RADIUS * AWARENESS_RADIUS
	var best_id: int = -1
	for pickup: ArenaPickup in simulation.arena_object_system.pickups:
		if not pickup.active or int(pickup.kind) != kind_value:
			continue
		var distance_squared: float = pickup.position.distance_squared_to(player_position)
		if (
			distance_squared < best_distance_squared
			or (
				is_equal_approx(distance_squared, best_distance_squared)
				and _id_wins_tie(pickup.pickup_id, best_id)
			)
		):
			best_distance_squared = distance_squared
			best_id = pickup.pickup_id
			result = {"found": true, "position": pickup.position}
	return result


func _nearest_xp(
	simulation: CombatSimulation,
	player_position: Vector2,
) -> Dictionary:
	var result: Dictionary = {"found": false}
	var best_distance_squared: float = AWARENESS_RADIUS * AWARENESS_RADIUS
	var best_pool_index: int = -1
	for pool_index: int in simulation.xp_pickup_pool.active_indices_snapshot():
		var pickup: XpPickupState = simulation.xp_pickup_pool.slots[pool_index]
		var distance_squared: float = pickup.position.distance_squared_to(player_position)
		if (
			distance_squared < best_distance_squared
			or (
				is_equal_approx(distance_squared, best_distance_squared)
				and _id_wins_tie(pool_index, best_pool_index)
			)
		):
			best_distance_squared = distance_squared
			best_pool_index = pool_index
			result = {"found": true, "position": pickup.position}
	return result


func _observe_chests(
	simulation: CombatSimulation,
	player_position: Vector2,
) -> void:
	var visible_chest_ids: Dictionary[int, bool] = {}
	var awareness_squared: float = AWARENESS_RADIUS * AWARENESS_RADIUS
	for pickup: ArenaPickup in simulation.arena_object_system.pickups:
		if not pickup.active or pickup.kind != ArenaPickup.Kind.CHEST:
			continue
		if pickup.position.distance_squared_to(player_position) > awareness_squared:
			continue
		visible_chest_ids[pickup.pickup_id] = true
		_seen_chests[pickup.pickup_id] = pickup.position
	var forgotten_ids: Array[int] = []
	for pickup_id: int in _seen_chests:
		var known_position: Vector2 = _seen_chests[pickup_id]
		if (
			known_position.distance_squared_to(player_position) <= awareness_squared
			and not visible_chest_ids.has(pickup_id)
		):
			forgotten_ids.append(pickup_id)
	for pickup_id: int in forgotten_ids:
		_seen_chests.erase(pickup_id)


func _nearest_seen_chest(player_position: Vector2) -> Dictionary:
	var result: Dictionary = {"found": false}
	var best_distance_squared: float = INF
	var best_id: int = -1
	for pickup_id: int in _seen_chests:
		var position: Vector2 = _seen_chests[pickup_id]
		var distance_squared: float = position.distance_squared_to(player_position)
		if (
			distance_squared < best_distance_squared
			or (
				is_equal_approx(distance_squared, best_distance_squared)
				and _id_wins_tie(pickup_id, best_id)
			)
		):
			best_distance_squared = distance_squared
			best_id = pickup_id
			result = {"found": true, "position": position}
	return result


func _patrol_direction(player_position: Vector2) -> Vector2:
	var target: Vector2 = PATROL_WAYPOINTS[_patrol_index]
	if player_position.distance_squared_to(target) <= 1.0:
		_patrol_index = wrapi(_patrol_index + int(_handedness), 0, PATROL_WAYPOINTS.size())
		target = PATROL_WAYPOINTS[_patrol_index]
	var offset: Vector2 = target - player_position
	return offset.normalized() if offset.length_squared() > 0.000001 else Vector2.ZERO


func _wall_correction(player_position: Vector2) -> Vector2:
	var correction: Vector2 = Vector2.ZERO
	var left_distance: float = player_position.x - CombatSimulation.ARENA_MIN.x
	var right_distance: float = CombatSimulation.ARENA_MAX.x - player_position.x
	var top_distance: float = player_position.y - CombatSimulation.ARENA_MIN.y
	var bottom_distance: float = CombatSimulation.ARENA_MAX.y - player_position.y
	if left_distance < WALL_MARGIN:
		correction.x += (WALL_MARGIN - left_distance) / WALL_MARGIN
	if right_distance < WALL_MARGIN:
		correction.x -= (WALL_MARGIN - right_distance) / WALL_MARGIN
	if top_distance < WALL_MARGIN:
		correction.y += (WALL_MARGIN - top_distance) / WALL_MARGIN
	if bottom_distance < WALL_MARGIN:
		correction.y -= (WALL_MARGIN - bottom_distance) / WALL_MARGIN
	return correction


func _enforce_wall_inward(movement: Vector2, wall: Vector2) -> Vector2:
	# WALL_WEIGHT is the ordinary soft steering. This final constraint covers the
	# crowded edge case where summed danger pressure would otherwise overpower it
	# and repeatedly request motion farther outside the finite arena.
	var corrected: Vector2 = movement
	if wall.x > 0.0:
		corrected.x = maxf(corrected.x, wall.x)
	elif wall.x < 0.0:
		corrected.x = minf(corrected.x, wall.x)
	if wall.y > 0.0:
		corrected.y = maxf(corrected.y, wall.y)
	elif wall.y < 0.0:
		corrected.y = minf(corrected.y, wall.y)
	return corrected


func _normal_upgrade_choice(
	offer: LevelOffer,
	state: RunState,
	catalog: DefinitionCatalog,
) -> int:
	var focus_index: int = _normal_focus_choice(offer, state, catalog)
	if focus_index >= 0:
		return focus_index
	var best_index: int = -1
	var best_priority: int = -1
	var best_ratio: float = -1.0
	for index: int in range(offer.options.size()):
		var option: UpgradeOption = offer.options[index]
		var counterpart_owned: bool = _counterpart_is_owned(option, state, catalog)
		var priority: int = 0
		if option.kind == GameTypes.UpgradeKind.WEAPON and option.current_level > 0 and counterpart_owned:
			priority = 4
		elif option.current_level <= 0 and counterpart_owned:
			priority = 3
		elif option.current_level > 0:
			priority = 2
		else:
			priority = 1
		var ratio: float = float(option.current_level) / float(maxi(1, option.max_level))
		if (
			priority > best_priority
			or (
				priority == best_priority
				and (
					ratio > best_ratio
					or (
						is_equal_approx(ratio, best_ratio)
						and best_index >= 0
						and _option_id_wins_tie(
							option.content_id,
							offer.options[best_index].content_id,
						)
					)
				)
			)
		):
			best_priority = priority
			best_ratio = ratio
			best_index = index
	return best_index


func _normal_focus_choice(
	offer: LevelOffer,
	state: RunState,
	catalog: DefinitionCatalog,
) -> int:
	var focused_weapon: RunWeapon = state.weapon_for_lineage(_normal_focus_lineage)
	if focused_weapon == null or focused_weapon.evolved:
		_normal_focus_lineage = &""
		for weapon: RunWeapon in state.weapons:
			if not weapon.evolved:
				_normal_focus_lineage = weapon.lineage_id
				focused_weapon = weapon
				break
	if focused_weapon == null or _normal_focus_lineage.is_empty():
		return -1
	var definition: WeaponDefinition = catalog.weapon(_normal_focus_lineage)
	if definition == null:
		return -1
	if state.passive(definition.paired_passive_id) == null:
		var passive_index: int = _find_option(offer, definition.paired_passive_id)
		if passive_index >= 0:
			return passive_index
	if focused_weapon.level < definition.max_level:
		return _find_option(offer, _normal_focus_lineage)
	return -1


func _counterpart_is_owned(
	option: UpgradeOption,
	state: RunState,
	catalog: DefinitionCatalog,
) -> bool:
	if option.kind == GameTypes.UpgradeKind.WEAPON:
		var weapon_definition: WeaponDefinition = catalog.weapon(option.content_id)
		return (
			weapon_definition != null
			and not weapon_definition.paired_passive_id.is_empty()
			and state.passive(weapon_definition.paired_passive_id) != null
		)
	var passive_definition: PassiveDefinition = catalog.passive(option.content_id)
	return (
		passive_definition != null
		and not passive_definition.paired_weapon_id.is_empty()
		and state.weapon_for_lineage(passive_definition.paired_weapon_id) != null
	)


func _find_option(offer: LevelOffer, content_id: StringName) -> int:
	for index: int in range(offer.options.size()):
		if offer.options[index].content_id == content_id:
			return index
	return -1


func _append_top_threats(
	target: Array[Dictionary],
	source: Array[Dictionary],
) -> void:
	for index: int in range(mini(MAX_THREATS_PER_KIND, source.size())):
		target.append(source[index])


func _id_wins_tie(candidate_id: int, incumbent_id: int) -> bool:
	if incumbent_id < 0:
		return true
	return candidate_id < incumbent_id if _prefer_lower_id else candidate_id > incumbent_id


func _option_id_wins_tie(candidate_id: StringName, incumbent_id: StringName) -> bool:
	var candidate: String = String(candidate_id)
	var incumbent: String = String(incumbent_id)
	return candidate < incumbent if _prefer_lower_id else candidate > incumbent


func _threat(
	clearance: float,
	away: Vector2,
	weight: float,
	stable_id: int,
) -> Dictionary:
	return {
		"clearance": clearance,
		"away": away,
		"weight": weight,
		"stable_id": stable_id,
	}


func _normalized_urgency(clearance: float, limit: float) -> float:
	if limit <= 0.0:
		return 1.0
	return clampf((limit - clearance) / limit, 0.0, 1.0)


func _away_direction(offset: Vector2, stable_id: int) -> Vector2:
	if offset.length_squared() > 0.000001:
		return offset.normalized()
	var angle: float = TAU * float(absi(stable_id) % 360) / 360.0
	return Vector2.from_angle(angle)


func _threat_less(left: Dictionary, right: Dictionary) -> bool:
	var left_clearance: float = float(left.get("clearance", INF))
	var right_clearance: float = float(right.get("clearance", INF))
	if not is_equal_approx(left_clearance, right_clearance):
		return left_clearance < right_clearance
	return _id_wins_tie(
		int(left.get("stable_id", 0)),
		int(right.get("stable_id", 0)),
	)
