extends RefCounted

const BotAction = preload("res://dev/bot/bot_action.gd")
const BotObservation = preload("res://dev/bot/bot_observation.gd")
const BotKnowledge = preload("res://dev/bot/bot_knowledge.gd")
const BotBuildPolicy = preload("res://dev/bot/bot_build_policy.gd")
const NativeLoader = preload("res://dev/bot/native_loader.gd")

## Bot policy parameters, not game balance. All work budgets are tick-based.
const DIRECTION_COUNT: int = 32
const HORIZON_SECONDS: float = 1.0
const MEMORY_TICKS: int = 120
const TRACK_CELL: float = 0.75
const NAV_CELL: float = 1.0
const NAV_DIMENSIONS := Vector2i(65, 65)
const ENGAGEMENT_DISTANCE: float = 4.0
const SWARM_MEMORY_TICKS: int = 600

var _knowledge: BotKnowledge
var _build: BotBuildPolicy
var _hold_evolution_chests: bool = false
var _prioritize_loot_goal: bool = false
var _collecting_xp: bool = false
var _kernel: RefCounted
var _directions: PackedVector2Array = []
var _swarm_warnings: Array[Dictionary] = []
var _view := ArenaView.new()
var _last_tick: int = -1
var _last_move := Vector2.RIGHT
var _explore_direction := Vector2.RIGHT
var _world_origin := Vector2i.ZERO
var _goal := Vector2.ZERO
var _next_goal_tick: int = 0
var _engagement_distance: float = ENGAGEMENT_DISTANCE
var _local_attacks: Array[Vector3] = []
var _slow_clearance: float = 2.0
var _needle_nearest_distance_squared: float = INF
var _needle_sequence_start_tick: int = -1
var _needle_cycle_ticks: int = 0
var _needle_weapon_id: StringName = &""
var _needle_next_tick: int = -1
## Development comparison: avoid collecting evolution chests before this combat tick.
var evolution_after_tick: int = 0
var _needle_definition: Dictionary = {}
var _needle_level: int = 0
var _needle_weapons: Array[Dictionary] = []
var _equipment_weapons: Array[Dictionary] = []
var _equipment_passives: Array[Dictionary] = []
var _equipment_ready: bool = false
var _equipment_has_needles: bool = false
var _previous_hp: float = -1.0
var _escape_until_tick: int = -1
var _navigation: RefCounted
var _navigation_origin := Vector2.ZERO
var _boss_was_active: bool = false
var last_reason: StringName = &""


func _init(knowledge: BotKnowledge) -> void:
	_knowledge = knowledge
	_build = BotBuildPolicy.new(knowledge)
	_kernel = NativeLoader.create_kernel()
	_navigation_origin = -Vector2(NAV_DIMENSIONS - Vector2i.ONE) * NAV_CELL * 0.5
	if _kernel != null:
		_navigation = _kernel
		_navigation.configure(_navigation_origin, NAV_DIMENSIONS, NAV_CELL)
		_navigation.configure_tracking({
			"enemy_speeds": _knowledge.enemy_speeds, "track_cell": TRACK_CELL, "memory_ticks": MEMORY_TICKS,
			"swarm_speed": _knowledge.swarm_speed,
			"swarmer_kind": CombatSnapshot.EnemyVisualKind.SWARMER,
			"red_kind": CombatSnapshot.EnemyVisualKind.SWARMER_EVENT_RED,
			"boss_kind": CombatSnapshot.EnemyVisualKind.BOSS,
		})
	_directions.append(Vector2.ZERO)
	for index: int in DIRECTION_COUNT:
		_directions.append(Vector2.from_angle(TAU * float(index) / float(DIRECTION_COUNT)))
	for index: int in DIRECTION_COUNT:
		_directions.append(Vector2.from_angle(TAU * float(index) / float(DIRECTION_COUNT)) * 0.5)


func decide(observation: BotObservation) -> BotAction:
	_shift_observed_origin(observation.world_origin)
	if observation.tick < _last_tick:
		_build.reset()
		_navigation.configure(_navigation_origin, NAV_DIMENSIONS, NAV_CELL)
		_navigation.clear_combat_memory()
		_boss_was_active = false
		_swarm_warnings.clear()
		_last_tick = -1
		_previous_hp = -1.0
		_next_goal_tick = 0
		_needle_next_tick = -1
		_needle_nearest_distance_squared = INF
		_needle_sequence_start_tick = -1
		_needle_weapon_id = &""
		_needle_weapons.clear()
		_equipment_ready = false
		_escape_until_tick = -1
		_last_move = Vector2.RIGHT
		_explore_direction = Vector2.RIGHT
	if observation.boss_active != _boss_was_active:
		_navigation.clear_combat_memory()
		_swarm_warnings.clear()
		_goal = observation.player_position
		_last_move = Vector2.RIGHT
		_explore_direction = Vector2.RIGHT
		_next_goal_tick = 0
		_escape_until_tick = -1
		_boss_was_active = observation.boss_active
	if observation.phase == GameTypes.RunPhase.COMBAT:
		if _previous_hp >= 0.0 and observation.hp < _previous_hp - 0.001:
			_escape_until_tick = observation.tick + 60
		_previous_hp = observation.hp
	var action := BotAction.new()
	if observation.phase in [GameTypes.RunPhase.RESULT, GameTypes.RunPhase.FAILED]:
		_build.reset()
		_navigation.clear_combat_memory()
		_swarm_warnings.clear()
		_next_goal_tick = 0
		return action
	_build.observe(observation)
	var hold_chests: bool = observation.tick < evolution_after_tick or _build.evolution_state == BotBuildPolicy.EvolutionState.PREPARING
	if hold_chests != _hold_evolution_chests:
		_next_goal_tick = 0
	_hold_evolution_chests = hold_chests
	if observation.phase == GameTypes.RunPhase.LEVEL_UP:
		action.kind = BotAction.Kind.CHOOSE_UPGRADE
		action.choice_index = _build.choose_upgrade(observation)
		action.reason = &"upgrade"
		_next_goal_tick = 0
		return action
	if observation.phase == GameTypes.RunPhase.CHEST_REWARD:
		action.kind = BotAction.Kind.CONTINUE_CHEST
		action.reason = &"chest"
		_next_goal_tick = 0
		return action
	_view.camera_transform = observation.camera_transform
	_view.viewport_size = observation.viewport_size
	_navigation_origin = observation.player_position.round() - Vector2(NAV_DIMENSIONS - Vector2i.ONE) * NAV_CELL * 0.5
	_navigation.recenter(_navigation_origin)
	var contact_damage: Dictionary[int, float] = _knowledge.contact_damage_for_tick(observation.tick)
	if observation.tick != _last_tick:
		var inverse: Transform3D = observation.camera_transform.orthonormalized().inverse()
		_navigation.observe_boundaries(observation.boundary_segments, observation.boundary_normals, observation.tick)
		_observe_bodies(observation, inverse, contact_damage)
		_remember_loot(observation, inverse)
		_remember_warnings(observation)
		_observe_needles(observation)
		_last_tick = observation.tick
	if observation.tick >= _next_goal_tick or observation.player_position.distance_squared_to(_goal) < 0.8:
		_choose_goal(observation)
		_next_goal_tick = observation.tick + 15
	if not _equipment_ready or observation.weapons != _equipment_weapons or observation.passives != _equipment_passives or _equipment_has_needles != (not _needle_definition.is_empty()):
		_refresh_equipment(observation)
	var best_move: Vector2 = _choose_move(observation, contact_damage)
	_last_move = best_move
	if best_move != Vector2.ZERO:
		_explore_direction = best_move.normalized()
	if _needle_next_tick == observation.tick + 1 and not _needle_definition.is_empty():
		best_move = _kernel.aim_needles(_directions, DIRECTION_COUNT, best_move, float(_needle_definition["range"][_needle_level - 1]))
	action.move_input = _view.world_to_screen_input(best_move)
	action.reason = last_reason
	return action


func _shift_observed_origin(origin: Vector2i) -> void:
	var displacement := Vector2(origin - _world_origin) * CombatSimulation.ORIGIN_STEP_METERS
	if displacement == Vector2.ZERO:
		return
	_world_origin = origin
	_goal -= displacement
	_navigation_origin -= displacement
	_navigation.shift_origin(displacement)
	for warning: Dictionary in _swarm_warnings:
		warning["position"] -= displacement


func _choose_move(observation: BotObservation, contact_damage: Dictionary[int, float]) -> Vector2:
	if _kernel == null:
		return Vector2(INF, INF)
	var swarms: Array = []
	for warning: Dictionary in _swarm_warnings:
		swarms.append([warning["direction"], warning["position"], warning.get("travel_direction", Vector2.ZERO), float(warning["width"]), float(observation.tick - int(warning["seen"])) / 60.0, warning["spawn_min"], warning["spawn_max"]])
	var bosses: Array = []
	for warning: Dictionary in observation.warnings:
		if warning["kind"] == &"boss":
			bosses.append([warning["position"], warning["directions"]])
	return _kernel.choose_move({
		"player": observation.player_position, "goal": _goal, "last_move": _last_move,
		"move_speed": _knowledge.move_speed, "horizon": HORIZON_SECONDS, "player_radius": _knowledge.player_radius,
		"engagement": _engagement_distance, "slow_clearance": _slow_clearance,
		"local_attacks": _local_attacks,
		"boss_active": observation.boss_active, "escape_active": observation.tick <= _escape_until_tick,
		"swarm_speed": _knowledge.swarm_speed, "swarm_depth": _knowledge.swarm_depth,
		"boss_kind": CombatSnapshot.EnemyVisualKind.BOSS,
		"elite_kind": CombatSnapshot.EnemyVisualKind.ELITE,
		"bulwark_kind": CombatSnapshot.EnemyVisualKind.BULWARK,
		"encircler_kind": CombatSnapshot.EnemyVisualKind.ENCIRCLER,
		"contact_damage": contact_damage,
		"hold_evolution_chests": _hold_evolution_chests,
		"evolution_chest_kind": BotObservation.LootKind.EVOLUTION_CHEST,
		"object_collect_radius": _knowledge.object_collect_radius,
		"prioritize_goal": _prioritize_loot_goal,
		"collecting_xp": _collecting_xp,
		"swarms": swarms, "bosses": bosses,
	}, _directions)


func _update_engagement(observation: BotObservation) -> void:
	_engagement_distance = ENGAGEMENT_DISTANCE
	_slow_clearance = 2.0
	var area_pct: float = 0.0
	for passive: Dictionary in observation.passives:
		var definition: Dictionary = _knowledge.passives[passive["id"]]
		if definition["stat"] == &"area_pct":
			area_pct += float(definition["amount"]) * int(passive["level"])
	var area: float = maxf(_knowledge.minimum_area_multiplier, 1.0 + area_pct / 100.0)
	var area_reach: float = 0.0
	_local_attacks.clear()
	for weapon: Dictionary in observation.weapons:
		var definition: Dictionary = _knowledge.weapons[weapon["id"]]
		var index: int = int(weapon["level"]) - 1
		var reach: float = float(definition["range"][index]) * (area if definition["range_scales_with_area"] else 1.0)
		var radius: float = float(definition["effect_radius"][index]) * (area if definition["effect_radius_scales_with_area"] else 1.0)
		match int(definition["behavior"]):
			GameTypes.WeaponBehavior.MELEE_WAVE:
				area_reach = maxf(area_reach, reach)
				_local_attacks.append(Vector3(reach, cos(deg_to_rad(_knowledge.melee_arc_degrees * 0.5)), float(int(definition["amount"][index]) > 1)))
			GameTypes.WeaponBehavior.ORBITAL:
				# Stay near the orbital path instead of only grazing its outer tip.
				area_reach = maxf(area_reach, reach)
				_local_attacks.append(Vector3(reach, -1.0, 0.0))
			GameTypes.WeaponBehavior.AURA:
				area_reach = maxf(area_reach, radius)
				_local_attacks.append(Vector3(radius, -1.0, 0.0))
	if area_reach > 0.0:
		# Keep a local area in reach even after the starter grows or evolves.
		# Collision prediction still takes precedence over this approach target.
		_engagement_distance = minf(ENGAGEMENT_DISTANCE, maxf(_knowledge.player_radius * 2.0 + 0.1, area_reach - 0.1))
		_slow_clearance = minf(2.0, maxf(0.0, _engagement_distance - _knowledge.player_radius * 2.0))


func _refresh_equipment(observation: BotObservation) -> void:
	# Cache only values already observed; detach them from retained observations.
	_equipment_weapons = observation.weapons.duplicate(true)
	_equipment_passives = observation.passives.duplicate(true)
	_equipment_ready = true
	_equipment_has_needles = not _needle_definition.is_empty()
	_update_engagement(observation)


func _observe_needles(observation: BotObservation) -> void:
	if observation.weapons != _needle_weapons:
		_needle_weapons = observation.weapons.duplicate(true)
		_needle_definition = {}
		for weapon: Dictionary in observation.weapons:
			var definition: Dictionary = _knowledge.weapons[weapon["id"]]
			if int(definition["behavior"]) != GameTypes.WeaponBehavior.DIRECTIONAL_PROJECTILE:
				continue
			if weapon["id"] != _needle_weapon_id or int(weapon["level"]) != _needle_level:
				_needle_sequence_start_tick = -1
				_needle_nearest_distance_squared = INF
			_needle_weapon_id = weapon["id"]
			_needle_definition = definition
			_needle_level = int(weapon["level"])
			break
	if _needle_definition.is_empty():
		return
	var nearest_squared: float = INF
	for position: Vector2 in observation.needles:
		nearest_squared = minf(nearest_squared, position.distance_squared_to(observation.player_position))
	var launch_seen: bool = nearest_squared <= 0.25 and nearest_squared < _needle_nearest_distance_squared - 0.000001
	_needle_nearest_distance_squared = nearest_squared
	var index: int = _needle_level - 1
	var interval: int = _needle_definition["shot_interval"][index]
	var amount: int = _needle_definition["amount"][index]
	if launch_seen and (_needle_sequence_start_tick < 0 or observation.tick >= _needle_sequence_start_tick + _needle_cycle_ticks):
		_needle_sequence_start_tick = observation.tick
		var cooldown_pct: float = 0.0
		for passive: Dictionary in observation.passives:
			var definition: Dictionary = _knowledge.passives[passive["id"]]
			if definition["stat"] == &"cooldown_pct":
				cooldown_pct += float(definition["amount"]) * int(passive["level"])
		var multiplier: float = maxf(_knowledge.minimum_cooldown_multiplier, 1.0 + cooldown_pct / 100.0)
		_needle_cycle_ticks = maxi((amount - 1) * interval + 1,
			maxi(1, roundi(float(_needle_definition["cooldown"][index]) * multiplier)))
	if _needle_sequence_start_tick < 0:
		_needle_next_tick = observation.tick + 1
		return
	# Extrapolate from visible launches, never from the weapon's hidden timer.
	var cycles: int = floori(float(observation.tick - _needle_sequence_start_tick) / float(_needle_cycle_ticks))
	var start: int = _needle_sequence_start_tick + cycles * _needle_cycle_ticks
	var next_shot: int = floori(float(observation.tick - start) / float(interval)) + 1
	_needle_next_tick = start + next_shot * interval if next_shot < amount else start + _needle_cycle_ticks


func _observe_bodies(observation: BotObservation, inverse: Transform3D, contact_damage: Dictionary[int, float]) -> void:
	_navigation.observe_tracks({
		"enemies": observation.enemy_values(), "bullets": observation.bullet_values(),
		"player": observation.player_position, "tick": observation.tick,
		"elapsed": float(maxi(1, observation.tick - _last_tick)) / 60.0,
		"inverse": inverse, "viewport": observation.viewport_size,
		"projection": observation.camera_projection,
		"contact_damage": contact_damage,
	})


func _remember_loot(observation: BotObservation, inverse: Transform3D) -> void:
	_navigation.remember_loot(observation.loot, inverse,
		observation.viewport_size, observation.tick, observation.camera_projection, BotObservation.LootKind.XP)


func _remember_warnings(observation: BotObservation) -> void:
	for warning: Dictionary in observation.warnings:
		if warning["kind"] != &"swarm":
			continue
		var remembered: Dictionary = {}
		for previous: Dictionary in _swarm_warnings:
			if previous["position"] == warning["position"] and previous["direction"] == warning["direction"]:
				remembered = previous
				break
		if remembered.is_empty():
			remembered = warning.duplicate(true)
			var bounds: Rect2 = _view.body_view_rect(_knowledge.swarm_radius)
			var anchor: Vector2 = warning["position"]
			var extent: Vector2 = (bounds.position - anchor).abs().max((bounds.end - anchor).abs())
			remembered["spawn_min"] = extent.dot((warning["direction"] as Vector2).abs())
			remembered["spawn_max"] = float(remembered["spawn_min"]) + _knowledge.spawn_band_width
			_swarm_warnings.append(remembered)
		# A disappearing telegraph announces an approaching wave; it does not
		# announce safety. This expiry uses only the last visible observation.
		remembered["until"] = observation.tick + SWARM_MEMORY_TICKS
		remembered["seen"] = observation.tick
		var travel: Vector2 = warning.get("travel_direction", Vector2.ZERO)
		if travel != Vector2.ZERO:
			remembered["travel_direction"] = travel
	for index: int in range(_swarm_warnings.size() - 1, -1, -1):
		if observation.tick > int(_swarm_warnings[index]["until"]):
			_swarm_warnings.remove_at(index)


func _choose_goal(observation: BotObservation) -> void:
	_choose_target(observation)
	_route_to_goal(observation.player_position)


func _choose_target(observation: BotObservation) -> void:
	_prioritize_loot_goal = false
	_collecting_xp = false
	var player: Vector2 = observation.player_position
	if observation.boss_active:
		var boss: Vector3 = _navigation.first_boss_position()
		if boss.z != 0.0:
			var boss_position := Vector2(boss.x, boss.y)
			var from_boss: Vector2 = (player - boss_position).normalized()
			if from_boss == Vector2.ZERO:
				from_boss = Vector2.RIGHT
			_goal = boss_position + from_boss.rotated(0.65) * 3.8
			last_reason = &"boss"
			return
	if not observation.boss_active and not _hold_evolution_chests and _build.evolution_state == BotBuildPolicy.EvolutionState.READY:
		# A ready evolution must not be starved by a continuous supply of XP.
		# Routing and collision avoidance still decide how to reach the chest.
		var remembered: Vector3 = _navigation.nearest_remembered_loot(BotObservation.LootKind.EVOLUTION_CHEST, player)
		if remembered.z != 0.0:
			_goal = Vector2(remembered.x, remembered.y)
			_prioritize_loot_goal = true
			last_reason = &"collect"
			return
		for cue: Dictionary in observation.chest_guidance:
			if int(cue["kind"]) == GameTypes.ChestKind.EVOLUTION_CAPABLE:
				_prioritize_loot_goal = true
				_goal = player + _view.screen_to_world_input(cue["direction"]).normalized() * 24.0
				last_reason = &"chest_direction"
				return
	var target: Vector3 = _navigation.choose_loot_goal({
		"player": player, "last_move": _last_move,
		"maxed": observation.build_maxed, "evolution_ready": _build.evolution_state == BotBuildPolicy.EvolutionState.READY,
		"hold_evolution_chests": _hold_evolution_chests,
		"hp": observation.hp, "max_hp": observation.max_hp, "pickup_radius": _knowledge.pickup_radius,
		"player_radius": _knowledge.player_radius, "object_collect_radius": _knowledge.object_collect_radius,
		"loot_kinds": PackedInt32Array([BotObservation.LootKind.XP, BotObservation.LootKind.CHEST,
			BotObservation.LootKind.EVOLUTION_CHEST, BotObservation.LootKind.POWERUP, BotObservation.LootKind.NODE]),
	})
	if target.z != 0.0:
		_prioritize_loot_goal = target.z != 2.0
		_collecting_xp = target.z == 3.0
		_goal = Vector2(target.x, target.y)
		last_reason = &"collect"
		return
	for cue: Dictionary in observation.chest_guidance:
		if observation.boss_active:
			break
		if int(cue["kind"]) == GameTypes.ChestKind.EVOLUTION_CAPABLE and _hold_evolution_chests:
			continue
		_prioritize_loot_goal = true
		_goal = player + _view.screen_to_world_input(cue["direction"]).normalized() * 24.0
		last_reason = &"chest_direction"
		return
	_goal = player + _explore_direction * 24.0
	last_reason = &"explore"


func _route_to_goal(player: Vector2) -> void:
	_goal = _navigation.route_tracked(player, _goal, _knowledge.player_radius)
