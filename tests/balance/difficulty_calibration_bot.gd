class_name DifficultyCalibrationBot
extends RefCounted


enum Policy { CAUTIOUS, NORMAL, EVOLUTION }

const PREDICTION_HORIZON_TICKS: int = 120
const SEEK_RECURSION_STEP_TICKS: int = 30
const HEADING_DIRECTION_COUNT: int = 32
const DENSITY_SECTOR_COUNT: int = 16
const DETAIL_THREAT_LIMIT: int = 32
const SAFETY_MARGIN: float = 0.20
const VIEW_HALF_WIDTH: float = 16.0
const VIEW_HALF_DEPTH: float = 10.9869713097598
const PLAYER_RADIUS: float = CombatEnvelope.PLAYER_BODY_RADIUS
const PLAYER_SPEED: float = CombatSimulation.PLAYER_SPEED
const SECONDS_PER_TICK: float = 1.0 / float(RunState.TICKS_PER_SECOND)
const PREDICTION_SECONDS: float = (
	float(PREDICTION_HORIZON_TICKS) / float(RunState.TICKS_PER_SECOND)
)
const SCREEN_RIGHT_WORLD: Vector2 = Vector2(0.70710678, -0.70710678)
const SCREEN_DOWN_WORLD: Vector2 = Vector2(0.70710678, 0.70710678)
const WALL_MARGIN: float = 2.0
const WALL_WEIGHT: float = 4.0
const CONTINUITY_WEIGHT: float = 0.35
const DENSITY_WEIGHT: float = 0.12
const END_CLEARANCE_WEIGHT: float = 0.02
const VECTOR_EPSILON: float = 0.000001
const SCORE_EPSILON: float = 0.000001
const TIME_EPSILON: float = 0.000001
const PICKUP_VISIBILITY_RADIUS: float = 0.5
const CHEST_VISIBILITY_RADIUS: float = 0.7
const XP_VISIBILITY_RADIUS: float = 0.22
const OBJECTIVE_XP: int = -1
const SHAPE_CIRCLE: StringName = &"circle"
const SHAPE_SWARM_ENVELOPE: StringName = &"swarm_envelope"
const KIND_ENEMY: StringName = &"enemy"
const KIND_SWARM_MEMBER: StringName = &"swarm_member"
const KIND_PROJECTILE: StringName = &"projectile"
const KIND_MATERIALIZING: StringName = &"materializing"
const KIND_TELEGRAPH: StringName = &"telegraph"
const KIND_BOSS_SPOKE: StringName = &"boss_spoke"
const KIND_SWARM_ENVELOPE: StringName = &"swarm_envelope"
const PATROL_WAYPOINTS: Array[Vector2] = [
	Vector2(-10.0, -10.0),
	Vector2(10.0, -10.0),
	Vector2(10.0, 10.0),
	Vector2(-10.0, 10.0),
]
const OBJECTIVE_WEIGHT_BY_POLICY: Array[float] = [0.75, 1.5, 2.25]
const CAUTIOUS_UPGRADE_PRIORITY: Array[StringName] = [
	&"repair_core",
	&"life_lattice",
	&"zero_field",
	&"resonance_wave",
]

var policy: int = Policy.NORMAL
var _held_input: Vector2 = Vector2.ZERO
var _last_decision_tick: int = -1
var _handedness: float = 1.0
var _direction_offset: int = 0
var _patrol_index: int = 0
var _prefer_lower_id: bool = true
var _seen_chests: Dictionary[int, Vector2] = {}
var _observations: Dictionary[String, Dictionary] = {}
var _normal_focus_lineage: StringName = &""
var _last_threat_counts: Dictionary[String, int] = {
	"enemy": 0,
	"projectile": 0,
	"materializing": 0,
	"telegraph": 0,
	"boss_warning": 0,
	"swarm_member": 0,
}
var _last_avoidance_debug: Dictionary = {
	"visible_threat_count": 0,
	"detailed_threat_count": 0,
	"safe_candidate_count": 0,
	"candidate_count": 0,
	"selected_first_collision_tick": -1,
	"selected_contact_tick_count": 0,
	"selected_peak_damage": 0.0,
	"selected_end_clearance": INF,
	"used_unavoidable_fallback": false,
}


func initialize(p_policy: int, run_seed: int) -> bool:
	if p_policy < Policy.CAUTIOUS or p_policy > Policy.EVOLUTION:
		return false
	policy = p_policy
	_held_input = Vector2.ZERO
	_last_decision_tick = -1
	_handedness = -1.0 if (absi(run_seed) % 2) == 0 else 1.0
	_direction_offset = absi(run_seed) % HEADING_DIRECTION_COUNT
	_patrol_index = absi(run_seed) % PATROL_WAYPOINTS.size()
	_prefer_lower_id = (absi(run_seed) % 2) != 0
	_seen_chests.clear()
	_observations.clear()
	_normal_focus_lineage = &""
	_last_threat_counts = {
		"enemy": 0,
		"projectile": 0,
		"materializing": 0,
		"telegraph": 0,
		"boss_warning": 0,
		"swarm_member": 0,
	}
	_last_avoidance_debug = {
		"visible_threat_count": 0,
		"detailed_threat_count": 0,
		"safe_candidate_count": 0,
		"candidate_count": 0,
		"selected_first_collision_tick": -1,
		"selected_contact_tick_count": 0,
		"selected_peak_damage": 0.0,
		"selected_end_clearance": INF,
		"used_unavoidable_fallback": false,
	}
	return true


func movement_input(simulation: CombatSimulation) -> Vector2:
	if simulation == null or simulation.state == null:
		return Vector2.ZERO
	var current_tick: int = simulation.state.combat_tick
	if current_tick == _last_decision_tick:
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
		"observation_count": _observations.size(),
		"threat_counts": _last_threat_counts.duplicate(),
		"avoidance": _last_avoidance_debug.duplicate(true),
		"prediction_horizon_ticks": PREDICTION_HORIZON_TICKS,
		"heading_direction_count": HEADING_DIRECTION_COUNT,
		"detail_threat_limit": DETAIL_THREAT_LIMIT,
		"safety_margin": SAFETY_MARGIN,
		"view_half_width": VIEW_HALF_WIDTH,
		"view_half_depth": VIEW_HALF_DEPTH,
	}


func deterministic_state_values() -> Array:
	var chest_ids: Array[int] = []
	for pickup_id: int in _seen_chests:
		chest_ids.append(pickup_id)
	chest_ids.sort()
	var chest_entries: Array = []
	for pickup_id: int in chest_ids:
		chest_entries.append([pickup_id, _seen_chests[pickup_id]])
	var observation_keys: Array[String] = []
	for observation_key: String in _observations:
		observation_keys.append(observation_key)
	observation_keys.sort()
	var observation_entries: Array = []
	for observation_key: String in observation_keys:
		var observation: Dictionary = _observations[observation_key]
		observation_entries.append([
			observation_key,
			observation.get("position", Vector2.ZERO),
			int(observation.get("tick", -1)),
		])
	return [
		policy,
		_held_input,
		_last_decision_tick,
		_handedness,
		_direction_offset,
		_patrol_index,
		_prefer_lower_id,
		chest_entries,
		observation_entries,
		_last_threat_counts.duplicate(),
		String(_normal_focus_lineage),
	]


func _decide_movement(simulation: CombatSimulation) -> Vector2:
	var player_position: Vector2 = simulation.player_position
	_observe_chests(simulation, player_position)
	var collected: Dictionary = _collect_visible_threats(simulation, player_position)
	var visible_threats: Array[Dictionary] = collected.get("visible", [])
	var mandatory_threats: Array[Dictionary] = collected.get("mandatory", [])
	var detailed_threats: Array[Dictionary] = _select_detailed_threats(
		visible_threats,
		mandatory_threats,
		player_position,
	)
	_prepare_threat_paths(detailed_threats, simulation.state)
	var density: PackedFloat32Array = _build_directional_density(
		visible_threats,
		player_position,
	)
	var objective: Vector2 = _objective_direction(simulation, player_position)
	var wall: Vector2 = _wall_correction(player_position)
	var nearest: Dictionary = _nearest_threat(visible_threats, player_position)
	var nearest_id: int = int(nearest.get("stable_id", 0))
	var candidates: Array[Dictionary] = _candidate_directions(
		objective,
		nearest,
		player_position,
		nearest_id,
		wall,
	)
	var evaluated: Array[Dictionary] = []
	var safe_candidate_count: int = 0
	for candidate: Dictionary in candidates:
		var metrics: Dictionary = _evaluate_candidate(
			candidate,
			detailed_threats,
			density,
			objective,
			wall,
			player_position,
		)
		evaluated.append(metrics)
		if bool(metrics.get("safe", false)):
			safe_candidate_count += 1
	var use_fallback: bool = safe_candidate_count == 0
	var swarm_envelope_count: int = 0
	var boss_spoke_count: int = 0
	for threat: Dictionary in detailed_threats:
		var threat_kind: StringName = threat.get("kind", &"")
		if threat_kind == KIND_SWARM_ENVELOPE:
			swarm_envelope_count += 1
		elif threat_kind == KIND_BOSS_SPOKE:
			boss_spoke_count += 1
	var best: Dictionary = {}
	for metrics: Dictionary in evaluated:
		if best.is_empty() or _candidate_is_better(metrics, best, use_fallback):
			best = metrics
	if best.is_empty():
		best = {
			"direction": Vector2.ZERO,
			"first_collision_tick": PREDICTION_HORIZON_TICKS + 1,
			"contact_tick_count": 0,
			"peak_damage": 0.0,
			"end_clearance": INF,
		}
	var selected_first_tick: int = int(best.get(
		"first_collision_tick",
		PREDICTION_HORIZON_TICKS + 1,
	))
	_last_avoidance_debug = {
		"visible_threat_count": visible_threats.size(),
		"detailed_threat_count": detailed_threats.size(),
		"regular_detailed_threat_count": (
			detailed_threats.size() - swarm_envelope_count - boss_spoke_count
		),
		"swarm_envelope_count": swarm_envelope_count,
		"boss_spoke_count": boss_spoke_count,
		"safe_candidate_count": safe_candidate_count,
		"candidate_count": candidates.size(),
		"selected_first_collision_tick": (
			-1 if selected_first_tick > PREDICTION_HORIZON_TICKS else selected_first_tick
		),
		"selected_contact_tick_count": int(best.get("contact_tick_count", 0)),
		"selected_peak_damage": float(best.get("peak_damage", 0.0)),
		"selected_end_clearance": float(best.get("end_clearance", INF)),
		"used_unavoidable_fallback": use_fallback,
	}
	return best.get("direction", Vector2.ZERO)


func _collect_visible_threats(
	simulation: CombatSimulation,
	player_position: Vector2,
) -> Dictionary:
	var current_tick: int = simulation.state.combat_tick
	var visible: Array[Dictionary] = []
	var mandatory: Array[Dictionary] = []
	var visible_observation_keys: Dictionary[String, bool] = {}
	var swarm_members: Dictionary[int, Array] = {}
	var enemy_count: int = 0
	var projectile_count: int = 0
	var materializing_count: int = 0
	var telegraph_count: int = 0
	var boss_warning_count: int = 0
	var swarm_member_count: int = 0
	for entity_id: int in simulation.enemy_system.enemy_store.snapshot_ids_sorted():
		var enemy: EnemyEntity = simulation.enemy_system.enemy_store.get_by_id(entity_id)
		if enemy == null or not enemy.alive or enemy.definition == null:
			continue
		var radius: float = enemy.body_radius()
		if not _circle_intersects_view(player_position, enemy.position, radius):
			continue
		var observation_key: String = "enemy:%d:%d" % [enemy.entity_id, enemy.generation]
		visible_observation_keys[observation_key] = true
		var fallback_velocity: Vector2 = _known_enemy_velocity(enemy, player_position)
		var velocity: Vector2 = _observe_velocity(
			observation_key,
			enemy.position,
			current_tick,
			fallback_velocity,
		)
		var first_active_tick: int = maxi(1, enemy.activation_tick - current_tick)
		var kind: StringName = KIND_ENEMY
		if enemy.is_materializing(current_tick):
			kind = KIND_MATERIALIZING
			materializing_count += 1
		elif enemy.is_swarm_event:
			kind = KIND_SWARM_MEMBER
			swarm_member_count += 1
		else:
			enemy_count += 1
		var damage: float = _enemy_damage(simulation, enemy)
		var speed: float = fallback_velocity.length()
		var travel_seconds: float = -1.0
		if enemy.movement_kind == EnemyEntity.MovementKind.FIXED_DIRECTION:
			travel_seconds = (
				enemy.remaining_travel_distance / speed
				if speed > VECTOR_EPSILON
				else 0.0
			)
		var threat: Dictionary = {
			"shape": SHAPE_CIRCLE,
			"kind": kind,
			"stable_key": observation_key,
			"stable_id": enemy.entity_id * 8,
			"position": enemy.position,
			"velocity": velocity,
			"fallback_velocity": fallback_velocity,
			"radius": radius,
			"damage": damage,
			"first_active_tick": first_active_tick,
			"travel_seconds": travel_seconds,
			"seek_player": enemy.movement_kind == EnemyEntity.MovementKind.SEEK_PLAYER,
			"stop_scale": (
				0.5 if enemy.enemy_type == GameTypes.EnemyType.BOSS else 0.0
			),
			"suppress_damage_during_full_stop": true,
			"mandatory": false,
		}
		visible.append(threat)
		if enemy.is_swarm_event and not enemy.is_materializing(current_tick):
			if not swarm_members.has(enemy.swarm_group_id):
				swarm_members[enemy.swarm_group_id] = []
			var group_members: Array = swarm_members[enemy.swarm_group_id]
			group_members.append(threat)
		if enemy.telegraph_active:
			var telegraph_radius: float = maxf(0.0, enemy.definition.area_radius)
			if _circle_intersects_view(
				player_position,
				enemy.telegraph_position,
				telegraph_radius,
			):
				telegraph_count += 1
				visible.append({
					"shape": SHAPE_CIRCLE,
					"kind": KIND_TELEGRAPH,
					"stable_key": "telegraph:%d:%d" % [enemy.entity_id, enemy.generation],
					"stable_id": enemy.entity_id * 8 + 1,
					"position": enemy.telegraph_position,
					"velocity": Vector2.ZERO,
					"fallback_velocity": Vector2.ZERO,
					"radius": telegraph_radius,
					"damage": damage,
					"first_active_tick": 1,
					"travel_seconds": -1.0,
					"stop_scale": 1.0,
					"suppress_damage_during_full_stop": false,
					"mandatory": false,
				})
		if enemy.enemy_type == GameTypes.EnemyType.BOSS and enemy.boss_charge_active:
			var warning_radius: float = maxf(2.4, radius * 1.6)
			if _circle_intersects_view(player_position, enemy.position, warning_radius):
				boss_warning_count += 1
				var spokes: Array[Dictionary] = _boss_warning_spokes(
					simulation,
					enemy,
					velocity,
				)
				for spoke: Dictionary in spokes:
					visible.append(spoke)
					mandatory.append(spoke)
	var group_ids: Array[int] = []
	for group_id: int in swarm_members:
		group_ids.append(group_id)
	group_ids.sort()
	for group_id: int in group_ids:
		var envelope: Dictionary = _swarm_envelope(group_id, swarm_members[group_id])
		if not envelope.is_empty():
			mandatory.append(envelope)
	for pool_index: int in simulation.projectile_pool.active_indices_snapshot():
		var projectile: ProjectileState = simulation.projectile_pool.slots[pool_index]
		if (
			projectile == null
			or not projectile.active
			or projectile.faction != ProjectileState.FACTION_ENEMY
		):
			continue
		if not _circle_intersects_view(
			player_position,
			projectile.position,
			projectile.radius,
		):
			continue
		var observation_key: String = "projectile:%d:%d" % [
			pool_index,
			projectile.generation,
		]
		visible_observation_keys[observation_key] = true
		var fallback_velocity: Vector2 = projectile.velocity
		var velocity: Vector2 = _observe_velocity(
			observation_key,
			projectile.position,
			current_tick,
			fallback_velocity,
		)
		var speed: float = maxf(fallback_velocity.length(), velocity.length())
		var travel_seconds: float = maxf(0.0, projectile.remaining_lifetime)
		if speed > VECTOR_EPSILON:
			travel_seconds = minf(
				travel_seconds,
				maxf(0.0, projectile.remaining_distance) / speed,
			)
		projectile_count += 1
		visible.append({
			"shape": SHAPE_CIRCLE,
			"kind": KIND_PROJECTILE,
			"stable_key": observation_key,
			"stable_id": 1_000_000 + pool_index * 32 + projectile.generation,
			"position": projectile.position,
			"velocity": velocity,
			"fallback_velocity": fallback_velocity,
			"radius": projectile.radius,
			"damage": projectile.damage,
			"first_active_tick": 1,
			"travel_seconds": travel_seconds,
			"stop_scale": projectile.stop_time_scale,
			"suppress_damage_during_full_stop": true,
			"mandatory": false,
		})
	_prune_observations(visible_observation_keys)
	_last_threat_counts = {
		"enemy": enemy_count,
		"projectile": projectile_count,
		"materializing": materializing_count,
		"telegraph": telegraph_count,
		"boss_warning": boss_warning_count,
		"swarm_member": swarm_member_count,
	}
	return {"visible": visible, "mandatory": mandatory}


func _known_enemy_velocity(enemy: EnemyEntity, player_position: Vector2) -> Vector2:
	if enemy.definition == null:
		return Vector2.ZERO
	if enemy.movement_kind == EnemyEntity.MovementKind.FIXED_DIRECTION:
		return enemy.fixed_direction.normalized() * enemy.definition.move_speed
	var direction: Vector2 = player_position - enemy.position
	if direction.length_squared() <= VECTOR_EPSILON:
		return Vector2.from_angle(
			TAU * float(absi(enemy.entity_id) % HEADING_DIRECTION_COUNT)
			/ float(HEADING_DIRECTION_COUNT)
		) * enemy.definition.move_speed
	return direction.normalized() * enemy.definition.move_speed


func _observe_velocity(
	observation_key: String,
	position: Vector2,
	current_tick: int,
	fallback_velocity: Vector2,
) -> Vector2:
	var result: Vector2 = fallback_velocity
	if _observations.has(observation_key):
		var previous: Dictionary = _observations[observation_key]
		var previous_tick: int = int(previous.get("tick", -2))
		if previous_tick == current_tick - 1:
			var previous_position: Vector2 = previous.get("position", position)
			var measured: Vector2 = (
				(position - previous_position) * float(RunState.TICKS_PER_SECOND)
			)
			if measured.length_squared() > VECTOR_EPSILON:
				var known_speed: float = fallback_velocity.length()
				result = (
					measured.normalized() * known_speed
					if known_speed > VECTOR_EPSILON
					else measured
				)
	_observations[observation_key] = {"position": position, "tick": current_tick}
	return result


func _prune_observations(visible_keys: Dictionary[String, bool]) -> void:
	var forgotten: Array[String] = []
	for observation_key: String in _observations:
		if not visible_keys.has(observation_key):
			forgotten.append(observation_key)
	for observation_key: String in forgotten:
		_observations.erase(observation_key)


func _enemy_damage(simulation: CombatSimulation, enemy: EnemyEntity) -> float:
	var damage: float = enemy.definition.contact_damage * enemy.damage_multiplier
	if enemy.enemy_type == GameTypes.EnemyType.BOSS and simulation.catalog != null:
		var manifest: SurvivalContentManifest = simulation.catalog.manifest()
		if manifest != null:
			damage *= 1.0 + (
				manifest.boss_attack_bonus_per_stack
				* float(simulation.state.boss_enrage_stacks)
			)
	return damage


func _boss_warning_spokes(
	simulation: CombatSimulation,
	boss: EnemyEntity,
	boss_velocity: Vector2,
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var fire_delay: int = _boss_fire_delay_ticks(simulation.state, boss)
	if fire_delay < 1 or fire_delay > PREDICTION_HORIZON_TICKS:
		return result
	var origin: Vector2 = boss.position + boss_velocity * _scaled_future_seconds(
		simulation.state,
		fire_delay,
		0.5,
	)
	var spoke_count: int = maxi(1, boss.boss_charge_spoke_count)
	var angle_step: float = TAU / float(spoke_count)
	var angle_offset: float = angle_step * 0.5 if boss.boss_charge_half_step else 0.0
	var lifetime_seconds: float = (
		float(boss.definition.projectile_lifetime_ticks)
		/ float(RunState.TICKS_PER_SECOND)
	)
	var damage: float = boss.definition.projectile_damage * boss.damage_multiplier
	var manifest: SurvivalContentManifest = simulation.catalog.manifest()
	if manifest != null:
		damage *= 1.0 + (
			manifest.boss_attack_bonus_per_stack
			* float(simulation.state.boss_enrage_stacks)
		)
	for spoke_index: int in range(spoke_count):
		var direction: Vector2 = Vector2.from_angle(
			angle_offset + angle_step * float(spoke_index)
		)
		result.append({
			"shape": SHAPE_CIRCLE,
			"kind": KIND_BOSS_SPOKE,
			"stable_key": "boss_spoke:%d:%d:%d" % [
				boss.entity_id,
				boss.generation,
				spoke_index,
			],
			"stable_id": 2_000_000 + boss.entity_id * 32 + spoke_index,
			"position": origin,
			"velocity": direction * boss.definition.projectile_speed,
			"fallback_velocity": direction * boss.definition.projectile_speed,
			"radius": boss.definition.projectile_radius,
			"damage": damage,
			"first_active_tick": fire_delay + 1,
			"travel_seconds": lifetime_seconds,
			"stop_scale": 0.5,
			"suppress_damage_during_full_stop": true,
			"mandatory": true,
		})
	return result


func _boss_fire_delay_ticks(state: RunState, boss: EnemyEntity) -> int:
	var elapsed: float = boss.boss_charge_elapsed_ticks
	for future_tick: int in range(1, PREDICTION_HORIZON_TICKS + 1):
		var absolute_tick: int = state.combat_tick + future_tick
		var time_scale: float = 0.5 if absolute_tick < state.stop_until_tick else 1.0
		elapsed += time_scale
		if elapsed + TIME_EPSILON >= float(CombatEnvelope.BOSS_CHARGE_TICKS):
			return future_tick
	return -1


func _scaled_future_seconds(
	state: RunState,
	future_ticks: int,
	stop_scale: float,
) -> float:
	var scaled_ticks: float = 0.0
	for future_tick: int in range(1, future_ticks + 1):
		var absolute_tick: int = state.combat_tick + future_tick
		scaled_ticks += stop_scale if absolute_tick < state.stop_until_tick else 1.0
	return scaled_ticks / float(RunState.TICKS_PER_SECOND)


func _swarm_envelope(group_id: int, members: Array) -> Dictionary:
	if members.is_empty():
		return {}
	var first: Dictionary = members[0]
	var velocity: Vector2 = first.get("fallback_velocity", Vector2.ZERO)
	var forward: Vector2 = velocity.normalized()
	if forward.length_squared() <= VECTOR_EPSILON:
		forward = Vector2.RIGHT
	var side: Vector2 = Vector2(-forward.y, forward.x)
	var min_forward: float = INF
	var max_forward: float = -INF
	var min_side: float = INF
	var max_side: float = -INF
	var maximum_damage: float = 0.0
	var maximum_travel_seconds: float = 0.0
	var minimum_id: int = 2_100_000 + group_id
	for member_value: Variant in members:
		var member: Dictionary = member_value
		var position: Vector2 = member.get("position", Vector2.ZERO)
		var radius: float = float(member.get("radius", 0.0))
		var forward_value: float = position.dot(forward)
		var side_value: float = position.dot(side)
		min_forward = minf(min_forward, forward_value - radius)
		max_forward = maxf(max_forward, forward_value + radius)
		min_side = minf(min_side, side_value - radius)
		max_side = maxf(max_side, side_value + radius)
		maximum_damage = maxf(maximum_damage, float(member.get("damage", 0.0)))
		maximum_travel_seconds = maxf(
			maximum_travel_seconds,
			float(member.get("travel_seconds", 0.0)),
		)
		minimum_id = mini(minimum_id, int(member.get("stable_id", minimum_id)))
	var center: Vector2 = (
		forward * (min_forward + max_forward) * 0.5
		+ side * (min_side + max_side) * 0.5
	)
	return {
		"shape": SHAPE_SWARM_ENVELOPE,
		"kind": KIND_SWARM_ENVELOPE,
		"stable_key": "swarm_envelope:%d" % group_id,
		"stable_id": minimum_id,
		"position": center,
		"motion_position": Vector2.ZERO,
		"velocity": velocity,
		"fallback_velocity": velocity,
		"radius": 0.0,
		"damage": maximum_damage,
		"first_active_tick": 1,
		"travel_seconds": maximum_travel_seconds,
		"stop_scale": 0.0,
		"suppress_damage_during_full_stop": true,
		"mandatory": true,
		"forward": forward,
		"side": side,
		"min_forward": min_forward,
		"max_forward": max_forward,
		"min_side": min_side,
		"max_side": max_side,
	}


func _select_detailed_threats(
	visible: Array[Dictionary],
	mandatory: Array[Dictionary],
	player_position: Vector2,
) -> Array[Dictionary]:
	var regular: Array[Dictionary] = []
	for threat: Dictionary in visible:
		if bool(threat.get("mandatory", false)):
			continue
		if threat.get("kind", &"") == KIND_SWARM_MEMBER:
			continue
		var ranked: Dictionary = threat.duplicate()
		ranked["estimated_ttc"] = _estimated_threat_ttc(threat, player_position)
		regular.append(ranked)
	regular.sort_custom(_threat_priority_less)
	var selected: Array[Dictionary] = []
	var selected_keys: Dictionary[String, bool] = {}
	var sector_best: Dictionary[int, Dictionary] = {}
	for threat: Dictionary in regular:
		var sector: int = _sector_for_offset(
			threat.get("position", player_position) - player_position,
		)
		if not sector_best.has(sector):
			sector_best[sector] = threat
	for sector: int in range(DENSITY_SECTOR_COUNT):
		if not sector_best.has(sector):
			continue
		var representative: Dictionary = sector_best[sector]
		var key: String = str(representative.get("stable_key", ""))
		selected.append(representative)
		selected_keys[key] = true
	for threat: Dictionary in regular:
		if selected.size() >= DETAIL_THREAT_LIMIT:
			break
		var key: String = str(threat.get("stable_key", ""))
		if selected_keys.has(key):
			continue
		selected.append(threat)
		selected_keys[key] = true
	for threat: Dictionary in mandatory:
		var key: String = str(threat.get("stable_key", ""))
		if selected_keys.has(key):
			continue
		selected.append(threat)
		selected_keys[key] = true
	return selected


func _estimated_threat_ttc(threat: Dictionary, player_position: Vector2) -> float:
	var radius: float = float(threat.get("radius", 0.0))
	var clearance: float = maxf(
		0.0,
		player_position.distance_to(threat.get("position", player_position))
		- PLAYER_RADIUS
		- radius
		- SAFETY_MARGIN,
	)
	var velocity: Vector2 = threat.get("fallback_velocity", Vector2.ZERO)
	var closing_speed: float = PLAYER_SPEED + velocity.length()
	var active_delay: int = maxi(0, int(threat.get("first_active_tick", 1)) - 1)
	return (
		float(active_delay)
		+ clearance / maxf(0.001, closing_speed) * float(RunState.TICKS_PER_SECOND)
	)


func _threat_priority_less(left: Dictionary, right: Dictionary) -> bool:
	var left_ttc: float = float(left.get("estimated_ttc", INF))
	var right_ttc: float = float(right.get("estimated_ttc", INF))
	if not is_equal_approx(left_ttc, right_ttc):
		return left_ttc < right_ttc
	return _stable_id_wins(
		int(left.get("stable_id", 0)),
		int(right.get("stable_id", 0)),
	)


func _prepare_threat_paths(threats: Array[Dictionary], state: RunState) -> void:
	for threat: Dictionary in threats:
		threat["motion_segments"] = _threat_motion_segments(threat, state)


func _threat_motion_segments(threat: Dictionary, state: RunState) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var first_active_tick: int = maxi(1, int(threat.get("first_active_tick", 1)))
	var active_start: float = (
		float(first_active_tick - 1) / float(RunState.TICKS_PER_SECOND)
	)
	var stop_end: float = maxf(
		0.0,
		float(state.stop_until_tick - state.combat_tick - 1)
		/ float(RunState.TICKS_PER_SECOND),
	)
	var breakpoints: Array[float] = [0.0, PREDICTION_SECONDS]
	_append_time_breakpoint(breakpoints, active_start)
	_append_time_breakpoint(breakpoints, stop_end)
	breakpoints.sort()
	var position: Vector2 = threat.get(
		"motion_position",
		threat.get("position", Vector2.ZERO),
	)
	var base_velocity: Vector2 = threat.get("velocity", Vector2.ZERO)
	if base_velocity.length_squared() <= VECTOR_EPSILON:
		base_velocity = threat.get("fallback_velocity", Vector2.ZERO)
	var stop_scale: float = clampf(float(threat.get("stop_scale", 0.0)), 0.0, 1.0)
	var remaining_scaled_seconds: float = float(threat.get("travel_seconds", -1.0))
	var suppress_during_stop: bool = bool(
		threat.get("suppress_damage_during_full_stop", true)
	)
	for index: int in range(breakpoints.size() - 1):
		var segment_start: float = breakpoints[index]
		var segment_end: float = breakpoints[index + 1]
		if segment_end <= segment_start + TIME_EPSILON:
			continue
		var midpoint: float = (segment_start + segment_end) * 0.5
		var active: bool = midpoint + TIME_EPSILON >= active_start
		var scale: float = stop_scale if midpoint < stop_end - TIME_EPSILON else 1.0
		var velocity: Vector2 = base_velocity * scale if active else Vector2.ZERO
		var damaging: bool = active and (not suppress_during_stop or scale > TIME_EPSILON)
		var resolved_end: float = segment_end
		if active and remaining_scaled_seconds >= 0.0:
			if remaining_scaled_seconds <= TIME_EPSILON:
				break
			if scale > TIME_EPSILON:
				resolved_end = minf(
					segment_end,
					segment_start + remaining_scaled_seconds / scale,
				)
		if resolved_end > segment_start + TIME_EPSILON:
			result.append({
				"start": segment_start,
				"end": resolved_end,
				"position": position,
				"velocity": velocity,
				"damaging": damaging,
			})
			var duration: float = resolved_end - segment_start
			position += velocity * duration
			if active and remaining_scaled_seconds >= 0.0:
				remaining_scaled_seconds = maxf(
					0.0,
					remaining_scaled_seconds - scale * duration,
				)
		if resolved_end < segment_end - TIME_EPSILON:
			break
	return result


func _append_time_breakpoint(values: Array[float], value: float) -> void:
	if value <= TIME_EPSILON or value >= PREDICTION_SECONDS - TIME_EPSILON:
		return
	for existing: float in values:
		if is_equal_approx(existing, value):
			return
	values.append(value)


func _build_directional_density(
	threats: Array[Dictionary],
	player_position: Vector2,
) -> PackedFloat32Array:
	var density := PackedFloat32Array()
	density.resize(DENSITY_SECTOR_COUNT)
	density.fill(0.0)
	for threat: Dictionary in threats:
		var position: Vector2 = threat.get("position", player_position)
		var offset: Vector2 = position - player_position
		if offset.length_squared() <= VECTOR_EPSILON:
			continue
		var radius: float = float(threat.get("radius", 0.0))
		var clearance: float = maxf(
			0.05,
			offset.length() - PLAYER_RADIUS - radius - SAFETY_MARGIN,
		)
		var damage_scale: float = 1.0 + minf(4.0, float(threat.get("damage", 0.0)) * 0.05)
		var delay_scale: float = 1.0 / float(maxi(1, int(threat.get("first_active_tick", 1))))
		var weight: float = damage_scale * (1.0 / clearance + delay_scale)
		var sector: int = _sector_for_offset(offset)
		density[sector] += weight
		density[wrapi(sector - 1, 0, DENSITY_SECTOR_COUNT)] += weight * 0.5
		density[wrapi(sector + 1, 0, DENSITY_SECTOR_COUNT)] += weight * 0.5
	return density


func _sector_for_offset(offset: Vector2) -> int:
	if offset.length_squared() <= VECTOR_EPSILON:
		return 0
	var normalized_angle: float = fposmod(offset.angle(), TAU)
	return wrapi(
		floori(
			(normalized_angle + TAU / float(DENSITY_SECTOR_COUNT * 2))
			/ TAU
			* float(DENSITY_SECTOR_COUNT)
		),
		0,
		DENSITY_SECTOR_COUNT,
	)


func _nearest_threat(
	threats: Array[Dictionary],
	player_position: Vector2,
) -> Dictionary:
	var nearest: Dictionary = {}
	var best_distance_squared: float = INF
	for threat: Dictionary in threats:
		var position: Vector2 = threat.get("position", player_position)
		var distance_squared: float = position.distance_squared_to(player_position)
		if (
			distance_squared < best_distance_squared - SCORE_EPSILON
			or (
				is_equal_approx(distance_squared, best_distance_squared)
				and (
					nearest.is_empty()
					or _stable_id_wins(
						int(threat.get("stable_id", 0)),
						int(nearest.get("stable_id", 0)),
					)
				)
			)
		):
			nearest = threat
			best_distance_squared = distance_squared
	return nearest


func _candidate_directions(
	objective: Vector2,
	nearest: Dictionary,
	player_position: Vector2,
	nearest_id: int,
	wall: Vector2,
) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	var start_index: int = wrapi(
		_direction_offset + absi(nearest_id),
		0,
		HEADING_DIRECTION_COUNT,
	)
	var step: int = 1 if _prefer_lower_id else -1
	for offset: int in range(HEADING_DIRECTION_COUNT):
		var direction_index: int = wrapi(
			start_index + offset * step,
			0,
			HEADING_DIRECTION_COUNT,
		)
		_append_candidate(candidates, _enforce_wall_inward(Vector2.from_angle(
			TAU * float(direction_index) / float(HEADING_DIRECTION_COUNT)
		), wall))
	_append_candidate(candidates, _enforce_wall_inward(Vector2.ZERO, wall))
	_append_candidate(candidates, _enforce_wall_inward(_held_input, wall))
	_append_candidate(candidates, _enforce_wall_inward(objective, wall))
	if not nearest.is_empty():
		var threat_position: Vector2 = nearest.get("position", player_position)
		var away: Vector2 = player_position - threat_position
		if away.length_squared() > VECTOR_EPSILON:
			away = away.normalized()
			var left_tangent: Vector2 = Vector2(-away.y, away.x)
			if _handedness < 0.0:
				_append_candidate(candidates, _enforce_wall_inward(-left_tangent, wall))
				_append_candidate(candidates, _enforce_wall_inward(left_tangent, wall))
			else:
				_append_candidate(candidates, _enforce_wall_inward(left_tangent, wall))
				_append_candidate(candidates, _enforce_wall_inward(-left_tangent, wall))
	return candidates


func _append_candidate(candidates: Array[Dictionary], direction: Vector2) -> void:
	var resolved: Vector2 = (
		Vector2.ZERO
		if direction.length_squared() <= VECTOR_EPSILON
		else direction.normalized()
	)
	for candidate: Dictionary in candidates:
		var existing: Vector2 = candidate.get("direction", Vector2.ZERO)
		if resolved == Vector2.ZERO and existing == Vector2.ZERO:
			return
		if (
			resolved != Vector2.ZERO
			and existing != Vector2.ZERO
			and resolved.dot(existing) >= 0.999999
		):
			return
	candidates.append({"direction": resolved, "stable_rank": candidates.size()})


func _evaluate_candidate(
	candidate: Dictionary,
	threats: Array[Dictionary],
	density: PackedFloat32Array,
	objective: Vector2,
	wall: Vector2,
	player_position: Vector2,
) -> Dictionary:
	var direction: Vector2 = candidate.get("direction", Vector2.ZERO)
	var player_segments: Array[Dictionary] = _player_motion_segments(
		player_position,
		direction,
	)
	var contact_ticks := PackedByteArray()
	contact_ticks.resize(PREDICTION_HORIZON_TICKS + 1)
	contact_ticks.fill(0)
	var damage_by_tick := PackedFloat32Array()
	damage_by_tick.resize(PREDICTION_HORIZON_TICKS + 1)
	damage_by_tick.fill(0.0)
	var end_clearance: float = INF
	for threat: Dictionary in threats:
		var contact: Dictionary = _evaluate_threat_contact(player_segments, threat)
		end_clearance = minf(
			end_clearance,
			float(contact.get("end_clearance", INF)),
		)
		var damage: float = float(threat.get("damage", 0.0))
		var ranges: Array[Vector2i] = contact.get("tick_ranges", [])
		for tick_range: Vector2i in ranges:
			for tick: int in range(tick_range.x, tick_range.y + 1):
				contact_ticks[tick] = 1
				damage_by_tick[tick] = maxf(damage_by_tick[tick], damage)
	var first_collision_tick: int = PREDICTION_HORIZON_TICKS + 1
	var contact_tick_count: int = 0
	var peak_damage: float = 0.0
	for tick: int in range(1, PREDICTION_HORIZON_TICKS + 1):
		if contact_ticks[tick] == 0:
			continue
		if first_collision_tick > PREDICTION_HORIZON_TICKS:
			first_collision_tick = tick
		contact_tick_count += 1
		peak_damage = maxf(peak_damage, damage_by_tick[tick])
	var density_penalty: float = 0.0
	if direction.length_squared() > VECTOR_EPSILON:
		var sector: int = _sector_for_offset(direction)
		density_penalty = density[sector]
	var clearance_bonus: float = (
		0.0 if is_inf(end_clearance) else minf(8.0, end_clearance) * END_CLEARANCE_WEIGHT
	)
	var utility: float = (
		direction.dot(objective) * OBJECTIVE_WEIGHT_BY_POLICY[policy]
		+ direction.dot(wall) * WALL_WEIGHT
		+ direction.dot(_held_input) * CONTINUITY_WEIGHT
		- density_penalty * DENSITY_WEIGHT
		+ clearance_bonus
	)
	return {
		"direction": direction,
		"stable_rank": int(candidate.get("stable_rank", 0)),
		"safe": contact_tick_count == 0,
		"first_collision_tick": first_collision_tick,
		"contact_tick_count": contact_tick_count,
		"peak_damage": peak_damage,
		"end_clearance": end_clearance,
		"utility": utility,
	}


func _candidate_is_better(
	candidate: Dictionary,
	incumbent: Dictionary,
	use_fallback: bool,
) -> bool:
	var candidate_safe: bool = bool(candidate.get("safe", false))
	var incumbent_safe: bool = bool(incumbent.get("safe", false))
	if candidate_safe != incumbent_safe:
		return candidate_safe
	if use_fallback or not candidate_safe:
		var candidate_first: int = int(candidate.get("first_collision_tick", 0))
		var incumbent_first: int = int(incumbent.get("first_collision_tick", 0))
		if candidate_first != incumbent_first:
			return candidate_first > incumbent_first
		var candidate_contacts: int = int(candidate.get("contact_tick_count", 0))
		var incumbent_contacts: int = int(incumbent.get("contact_tick_count", 0))
		if candidate_contacts != incumbent_contacts:
			return candidate_contacts < incumbent_contacts
		var candidate_damage: float = float(candidate.get("peak_damage", 0.0))
		var incumbent_damage: float = float(incumbent.get("peak_damage", 0.0))
		if not is_equal_approx(candidate_damage, incumbent_damage):
			return candidate_damage < incumbent_damage
		var candidate_clearance: float = float(candidate.get("end_clearance", -INF))
		var incumbent_clearance: float = float(incumbent.get("end_clearance", -INF))
		if not is_equal_approx(candidate_clearance, incumbent_clearance):
			return candidate_clearance > incumbent_clearance
	var candidate_utility: float = float(candidate.get("utility", -INF))
	var incumbent_utility: float = float(incumbent.get("utility", -INF))
	if candidate_utility > incumbent_utility + SCORE_EPSILON:
		return true
	if candidate_utility < incumbent_utility - SCORE_EPSILON:
		return false
	return int(candidate.get("stable_rank", 0)) < int(incumbent.get("stable_rank", 0))


func _player_motion_segments(
	player_position: Vector2,
	direction: Vector2,
) -> Array[Dictionary]:
	var velocity: Vector2 = direction.limit_length(1.0) * PLAYER_SPEED
	var x_stop: float = _axis_stop_time(
		player_position.x,
		velocity.x,
		CombatSimulation.ARENA_MIN.x,
		CombatSimulation.ARENA_MAX.x,
	)
	var y_stop: float = _axis_stop_time(
		player_position.y,
		velocity.y,
		CombatSimulation.ARENA_MIN.y,
		CombatSimulation.ARENA_MAX.y,
	)
	var breakpoints: Array[float] = [0.0, PREDICTION_SECONDS]
	_append_time_breakpoint(breakpoints, x_stop)
	_append_time_breakpoint(breakpoints, y_stop)
	breakpoints.sort()
	var result: Array[Dictionary] = []
	for index: int in range(breakpoints.size() - 1):
		var segment_start: float = breakpoints[index]
		var segment_end: float = breakpoints[index + 1]
		var segment_position := Vector2(
			clampf(
				player_position.x + velocity.x * minf(segment_start, x_stop),
				CombatSimulation.ARENA_MIN.x,
				CombatSimulation.ARENA_MAX.x,
			),
			clampf(
				player_position.y + velocity.y * minf(segment_start, y_stop),
				CombatSimulation.ARENA_MIN.y,
				CombatSimulation.ARENA_MAX.y,
			),
		)
		var segment_velocity := Vector2(
			velocity.x if segment_start < x_stop - TIME_EPSILON else 0.0,
			velocity.y if segment_start < y_stop - TIME_EPSILON else 0.0,
		)
		result.append({
			"start": segment_start,
			"end": segment_end,
			"position": segment_position,
			"velocity": segment_velocity,
		})
	return result


func _axis_stop_time(value: float, velocity: float, minimum: float, maximum: float) -> float:
	if absf(velocity) <= VECTOR_EPSILON:
		return PREDICTION_SECONDS
	var target: float = maximum if velocity > 0.0 else minimum
	return clampf((target - value) / velocity, 0.0, PREDICTION_SECONDS)


func _evaluate_threat_contact(
	player_segments: Array[Dictionary],
	threat: Dictionary,
) -> Dictionary:
	var threat_segments: Array[Dictionary] = threat.get("motion_segments", [])
	if bool(threat.get("seek_player", false)):
		return _evaluate_seek_contact(player_segments, threat, threat_segments)
	var intervals: Array[Vector2] = []
	for player_segment: Dictionary in player_segments:
		for threat_segment: Dictionary in threat_segments:
			if not bool(threat_segment.get("damaging", false)):
				continue
			var overlap_start: float = maxf(
				float(player_segment.get("start", 0.0)),
				float(threat_segment.get("start", 0.0)),
			)
			var overlap_end: float = minf(
				float(player_segment.get("end", 0.0)),
				float(threat_segment.get("end", 0.0)),
			)
			if overlap_end < overlap_start + TIME_EPSILON:
				continue
			var local_interval: Vector2
			if threat.get("shape", SHAPE_CIRCLE) == SHAPE_SWARM_ENVELOPE:
				local_interval = _swarm_contact_interval(
					player_segment,
					threat_segment,
					threat,
					overlap_start,
					overlap_end,
				)
			else:
				local_interval = _circle_contact_interval_for_segments(
					player_segment,
					threat_segment,
					float(threat.get("radius", 0.0)),
					overlap_start,
					overlap_end,
				)
			if local_interval.x >= 0.0:
				intervals.append(local_interval)
	return {
		"tick_ranges": _intervals_to_tick_ranges(intervals),
		"end_clearance": _threat_end_clearance(player_segments, threat, threat_segments),
	}


func _evaluate_seek_contact(
	player_segments: Array[Dictionary],
	threat: Dictionary,
	threat_segments: Array[Dictionary],
) -> Dictionary:
	var breakpoints: Array[float] = [0.0, PREDICTION_SECONDS]
	for player_segment: Dictionary in player_segments:
		_append_time_breakpoint(
			breakpoints,
			float(player_segment.get("start", 0.0)),
		)
		_append_time_breakpoint(
			breakpoints,
			float(player_segment.get("end", PREDICTION_SECONDS)),
		)
	for threat_segment: Dictionary in threat_segments:
		_append_time_breakpoint(
			breakpoints,
			float(threat_segment.get("start", 0.0)),
		)
		_append_time_breakpoint(
			breakpoints,
			float(threat_segment.get("end", PREDICTION_SECONDS)),
		)
	for prediction_tick: int in range(
		SEEK_RECURSION_STEP_TICKS,
		PREDICTION_HORIZON_TICKS,
		SEEK_RECURSION_STEP_TICKS,
	):
		_append_time_breakpoint(
			breakpoints,
			float(prediction_tick) * SECONDS_PER_TICK,
		)
	breakpoints.sort()
	var intervals: Array[Vector2] = []
	var enemy_position: Vector2 = threat.get("position", Vector2.ZERO)
	var safety_radius: float = (
		PLAYER_RADIUS + float(threat.get("radius", 0.0)) + SAFETY_MARGIN
	)
	var body_contact_radius: float = (
		PLAYER_RADIUS + float(threat.get("radius", 0.0))
	)
	var path_exists_at_horizon: bool = false
	for index: int in range(breakpoints.size() - 1):
		var segment_start: float = breakpoints[index]
		var segment_end: float = breakpoints[index + 1]
		if segment_end <= segment_start + TIME_EPSILON:
			continue
		var midpoint: float = (segment_start + segment_end) * 0.5
		var player_segment: Dictionary = _segment_covering(player_segments, midpoint)
		var threat_segment: Dictionary = _segment_covering(threat_segments, midpoint)
		if player_segment.is_empty() or threat_segment.is_empty():
			continue
		if segment_end >= PREDICTION_SECONDS - TIME_EPSILON:
			path_exists_at_horizon = true
		var duration: float = segment_end - segment_start
		var player_position: Vector2 = _segment_position_at(player_segment, segment_start)
		var player_velocity: Vector2 = player_segment.get("velocity", Vector2.ZERO)
		if not bool(threat_segment.get("damaging", false)):
			enemy_position += threat_segment.get("velocity", Vector2.ZERO) * duration
			continue
		var offset: Vector2 = player_position - enemy_position
		var distance: float = offset.length()
		var away: Vector2 = (
			offset / distance
			if distance > VECTOR_EPSILON
			else Vector2.from_angle(
				TAU * float(absi(int(threat.get("stable_id", 0))) % HEADING_DIRECTION_COUNT)
				/ float(HEADING_DIRECTION_COUNT)
			)
		)
		var enemy_speed: float = (
			threat_segment.get("velocity", Vector2.ZERO) as Vector2
		).length()
		var enemy_velocity: Vector2 = away * enemy_speed
		var local_interval: Vector2 = _circle_contact_interval(
			enemy_position - player_position,
			enemy_velocity - player_velocity,
			safety_radius,
			duration,
		)
		if local_interval.x >= 0.0:
			intervals.append(Vector2(
				segment_start + local_interval.x,
				segment_start + local_interval.y,
			))
		var player_end_position: Vector2 = _segment_position_at(
			player_segment,
			segment_end,
		)
		var maximum_travel: float = maxf(
			0.0,
			player_end_position.distance_to(enemy_position) - body_contact_radius,
		)
		enemy_position += away * minf(enemy_speed * duration, maximum_travel)
	var end_clearance: float = INF
	if path_exists_at_horizon and not player_segments.is_empty():
		var final_player_position: Vector2 = _segment_position_at(
			player_segments[player_segments.size() - 1],
			PREDICTION_SECONDS,
		)
		end_clearance = final_player_position.distance_to(enemy_position) - safety_radius
	return {
		"tick_ranges": _intervals_to_tick_ranges(intervals),
		"end_clearance": end_clearance,
	}


func _segment_covering(segments: Array[Dictionary], time_seconds: float) -> Dictionary:
	for segment: Dictionary in segments:
		if (
			time_seconds >= float(segment.get("start", 0.0)) - TIME_EPSILON
			and time_seconds <= float(segment.get("end", 0.0)) + TIME_EPSILON
		):
			return segment
	return {}


func _intervals_to_tick_ranges(intervals: Array[Vector2]) -> Array[Vector2i]:
	var merged: Array[Vector2] = _merge_intervals(intervals)
	var tick_ranges: Array[Vector2i] = []
	for interval: Vector2 in merged:
		var start_tick: int = maxi(
			1,
			ceili(interval.x * float(RunState.TICKS_PER_SECOND) - TIME_EPSILON),
		)
		var end_tick: int = mini(
			PREDICTION_HORIZON_TICKS,
			ceili(interval.y * float(RunState.TICKS_PER_SECOND) - TIME_EPSILON),
		)
		if end_tick >= start_tick:
			tick_ranges.append(Vector2i(start_tick, end_tick))
	return tick_ranges


func _circle_contact_interval_for_segments(
	player_segment: Dictionary,
	threat_segment: Dictionary,
	threat_radius: float,
	overlap_start: float,
	overlap_end: float,
) -> Vector2:
	var player_position: Vector2 = _segment_position_at(player_segment, overlap_start)
	var threat_position: Vector2 = _segment_position_at(threat_segment, overlap_start)
	var relative_position: Vector2 = threat_position - player_position
	var relative_velocity: Vector2 = (
		threat_segment.get("velocity", Vector2.ZERO)
		- player_segment.get("velocity", Vector2.ZERO)
	)
	var radius: float = PLAYER_RADIUS + threat_radius + SAFETY_MARGIN
	var local: Vector2 = _circle_contact_interval(
		relative_position,
		relative_velocity,
		radius,
		overlap_end - overlap_start,
	)
	if local.x < 0.0:
		return local
	return Vector2(overlap_start + local.x, overlap_start + local.y)


func _circle_contact_interval(
	relative_position: Vector2,
	relative_velocity: Vector2,
	radius: float,
	duration: float,
) -> Vector2:
	var c: float = relative_position.length_squared() - radius * radius
	var a: float = relative_velocity.length_squared()
	if a <= VECTOR_EPSILON:
		return Vector2(0.0, duration) if c <= 0.0 else Vector2(-1.0, -1.0)
	var b: float = 2.0 * relative_position.dot(relative_velocity)
	var discriminant: float = b * b - 4.0 * a * c
	if discriminant < 0.0:
		return Vector2(-1.0, -1.0)
	var root: float = sqrt(maxf(0.0, discriminant))
	var entry: float = (-b - root) / (2.0 * a)
	var exit_time: float = (-b + root) / (2.0 * a)
	if c <= 0.0:
		entry = 0.0
	var clipped_entry: float = maxf(0.0, entry)
	var clipped_exit: float = minf(duration, exit_time)
	if clipped_exit < clipped_entry - TIME_EPSILON:
		return Vector2(-1.0, -1.0)
	return Vector2(clipped_entry, maxf(clipped_entry, clipped_exit))


func _swarm_contact_interval(
	player_segment: Dictionary,
	threat_segment: Dictionary,
	threat: Dictionary,
	overlap_start: float,
	overlap_end: float,
) -> Vector2:
	var player_position: Vector2 = _segment_position_at(player_segment, overlap_start)
	var envelope_translation: Vector2 = _segment_position_at(threat_segment, overlap_start)
	var relative_position: Vector2 = player_position - envelope_translation
	var relative_velocity: Vector2 = (
		player_segment.get("velocity", Vector2.ZERO)
		- threat_segment.get("velocity", Vector2.ZERO)
	)
	var forward: Vector2 = threat.get("forward", Vector2.RIGHT)
	var side: Vector2 = threat.get("side", Vector2.DOWN)
	var expanded_radius: float = PLAYER_RADIUS + SAFETY_MARGIN
	var local_position := Vector2(relative_position.dot(forward), relative_position.dot(side))
	var local_velocity := Vector2(relative_velocity.dot(forward), relative_velocity.dot(side))
	var minimum := Vector2(
		float(threat.get("min_forward", 0.0)) - expanded_radius,
		float(threat.get("min_side", 0.0)) - expanded_radius,
	)
	var maximum := Vector2(
		float(threat.get("max_forward", 0.0)) + expanded_radius,
		float(threat.get("max_side", 0.0)) + expanded_radius,
	)
	var local: Vector2 = _ray_box_interval(
		local_position,
		local_velocity,
		minimum,
		maximum,
		overlap_end - overlap_start,
	)
	if local.x < 0.0:
		return local
	return Vector2(overlap_start + local.x, overlap_start + local.y)


func _ray_box_interval(
	position: Vector2,
	velocity: Vector2,
	minimum: Vector2,
	maximum: Vector2,
	duration: float,
) -> Vector2:
	var entry: float = 0.0
	var exit_time: float = duration
	var x_interval: Vector2 = _axis_box_interval(
		position.x,
		velocity.x,
		minimum.x,
		maximum.x,
		duration,
	)
	if x_interval.x < 0.0:
		return Vector2(-1.0, -1.0)
	entry = maxf(entry, x_interval.x)
	exit_time = minf(exit_time, x_interval.y)
	var y_interval: Vector2 = _axis_box_interval(
		position.y,
		velocity.y,
		minimum.y,
		maximum.y,
		duration,
	)
	if y_interval.x < 0.0:
		return Vector2(-1.0, -1.0)
	entry = maxf(entry, y_interval.x)
	exit_time = minf(exit_time, y_interval.y)
	if exit_time < entry - TIME_EPSILON:
		return Vector2(-1.0, -1.0)
	return Vector2(entry, maxf(entry, exit_time))


func _axis_box_interval(
	position: float,
	velocity: float,
	minimum: float,
	maximum: float,
	duration: float,
) -> Vector2:
	if absf(velocity) <= VECTOR_EPSILON:
		return (
			Vector2(0.0, duration)
			if position >= minimum and position <= maximum
			else Vector2(-1.0, -1.0)
		)
	var first: float = (minimum - position) / velocity
	var second: float = (maximum - position) / velocity
	var entry: float = minf(first, second)
	var exit_time: float = maxf(first, second)
	if exit_time < 0.0 or entry > duration:
		return Vector2(-1.0, -1.0)
	return Vector2(maxf(0.0, entry), minf(duration, exit_time))


func _merge_intervals(intervals: Array[Vector2]) -> Array[Vector2]:
	if intervals.is_empty():
		return []
	intervals.sort_custom(func(left: Vector2, right: Vector2) -> bool:
		if not is_equal_approx(left.x, right.x):
			return left.x < right.x
		return left.y < right.y
	)
	var result: Array[Vector2] = []
	var current: Vector2 = intervals[0]
	for index: int in range(1, intervals.size()):
		var next: Vector2 = intervals[index]
		if next.x <= current.y + TIME_EPSILON:
			current.y = maxf(current.y, next.y)
		else:
			result.append(current)
			current = next
	result.append(current)
	return result


func _segment_position_at(segment: Dictionary, time_seconds: float) -> Vector2:
	var start: float = float(segment.get("start", 0.0))
	var position: Vector2 = segment.get("position", Vector2.ZERO)
	var velocity: Vector2 = segment.get("velocity", Vector2.ZERO)
	return position + velocity * maxf(0.0, time_seconds - start)


func _threat_end_clearance(
	player_segments: Array[Dictionary],
	threat: Dictionary,
	threat_segments: Array[Dictionary],
) -> float:
	if player_segments.is_empty() or threat_segments.is_empty():
		return INF
	var final_threat_segment: Dictionary = threat_segments[threat_segments.size() - 1]
	if float(final_threat_segment.get("end", 0.0)) < PREDICTION_SECONDS - TIME_EPSILON:
		return INF
	var player_position: Vector2 = _segment_position_at(
		player_segments[player_segments.size() - 1],
		PREDICTION_SECONDS,
	)
	var threat_translation: Vector2 = _segment_position_at(
		final_threat_segment,
		PREDICTION_SECONDS,
	)
	if threat.get("shape", SHAPE_CIRCLE) == SHAPE_SWARM_ENVELOPE:
		var forward: Vector2 = threat.get("forward", Vector2.RIGHT)
		var side: Vector2 = threat.get("side", Vector2.DOWN)
		var relative: Vector2 = player_position - threat_translation
		var local := Vector2(relative.dot(forward), relative.dot(side))
		var closest := Vector2(
			clampf(
				local.x,
				float(threat.get("min_forward", 0.0)),
				float(threat.get("max_forward", 0.0)),
			),
			clampf(
				local.y,
				float(threat.get("min_side", 0.0)),
				float(threat.get("max_side", 0.0)),
			),
		)
		return local.distance_to(closest) - PLAYER_RADIUS - SAFETY_MARGIN
	return (
		player_position.distance_to(threat_translation)
		- PLAYER_RADIUS
		- float(threat.get("radius", 0.0))
		- SAFETY_MARGIN
	)


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
			if offset.length_squared() > VECTOR_EPSILON:
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
	var best_distance_squared: float = INF
	var best_id: int = -1
	for pickup: ArenaPickup in simulation.arena_object_system.pickups:
		if not pickup.active or int(pickup.kind) != kind_value:
			continue
		var radius: float = (
			CHEST_VISIBILITY_RADIUS
			if pickup.kind == ArenaPickup.Kind.CHEST
			else PICKUP_VISIBILITY_RADIUS
		)
		if not _circle_intersects_view(player_position, pickup.position, radius):
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
	var best_distance_squared: float = INF
	var best_pool_index: int = -1
	for pool_index: int in simulation.xp_pickup_pool.active_indices_snapshot():
		var pickup: XpPickupState = simulation.xp_pickup_pool.slots[pool_index]
		if not _circle_intersects_view(
			player_position,
			pickup.position,
			XP_VISIBILITY_RADIUS,
		):
			continue
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
	for pickup: ArenaPickup in simulation.arena_object_system.pickups:
		if not pickup.active or pickup.kind != ArenaPickup.Kind.CHEST:
			continue
		if not _circle_intersects_view(
			player_position,
			pickup.position,
			CHEST_VISIBILITY_RADIUS,
		):
			continue
		visible_chest_ids[pickup.pickup_id] = true
		_seen_chests[pickup.pickup_id] = pickup.position
	var forgotten_ids: Array[int] = []
	for pickup_id: int in _seen_chests:
		var known_position: Vector2 = _seen_chests[pickup_id]
		if (
			_circle_intersects_view(
				player_position,
				known_position,
				CHEST_VISIBILITY_RADIUS,
			)
			and not visible_chest_ids.has(pickup_id)
		):
			forgotten_ids.append(pickup_id)
	for pickup_id: int in forgotten_ids:
		_seen_chests.erase(pickup_id)


func _circle_intersects_view(
	player_position: Vector2,
	target_position: Vector2,
	radius: float,
) -> bool:
	var offset: Vector2 = target_position - player_position
	return (
		absf(offset.dot(SCREEN_RIGHT_WORLD)) <= VIEW_HALF_WIDTH + maxf(0.0, radius)
		and absf(offset.dot(SCREEN_DOWN_WORLD)) <= VIEW_HALF_DEPTH + maxf(0.0, radius)
	)


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
	return offset.normalized() if offset.length_squared() > VECTOR_EPSILON else Vector2.ZERO


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
	var corrected: Vector2 = movement
	if wall.x > 0.0:
		corrected.x = maxf(corrected.x, wall.x)
	elif wall.x < 0.0:
		corrected.x = minf(corrected.x, wall.x)
	if wall.y > 0.0:
		corrected.y = maxf(corrected.y, wall.y)
	elif wall.y < 0.0:
		corrected.y = minf(corrected.y, wall.y)
	if corrected.length_squared() <= VECTOR_EPSILON:
		return Vector2.ZERO
	return corrected.normalized()


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


func _id_wins_tie(candidate_id: int, incumbent_id: int) -> bool:
	if incumbent_id < 0:
		return true
	return _stable_id_wins(candidate_id, incumbent_id)


func _stable_id_wins(candidate_id: int, incumbent_id: int) -> bool:
	return candidate_id < incumbent_id if _prefer_lower_id else candidate_id > incumbent_id


func _option_id_wins_tie(candidate_id: StringName, incumbent_id: StringName) -> bool:
	var candidate: String = String(candidate_id)
	var incumbent: String = String(incumbent_id)
	return candidate < incumbent if _prefer_lower_id else candidate > incumbent
