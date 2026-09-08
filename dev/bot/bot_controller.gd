extends RefCounted

const BotAction = preload("res://dev/bot/bot_action.gd")
const BotObservation = preload("res://dev/bot/bot_observation.gd")
const BotKnowledge = preload("res://dev/bot/bot_knowledge.gd")
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
var _slow_clearance: float = 2.0
var _needle_last_near_tick: int = -1000
var _needle_next_tick: int = -1
var _resume_fire: bool = false
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
var last_reason: StringName = &""


func _init(knowledge: BotKnowledge) -> void:
	_knowledge = knowledge
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
	if observation.phase == GameTypes.RunPhase.COMBAT:
		if _previous_hp >= 0.0 and observation.hp < _previous_hp - 0.001:
			_escape_until_tick = observation.tick + 60
		_previous_hp = observation.hp
	var action := BotAction.new()
	if observation.phase == GameTypes.RunPhase.LEVEL_UP:
		_resume_fire = true
		action.kind = BotAction.Kind.CHOOSE_UPGRADE
		action.choice_index = _choose_upgrade(observation)
		action.reason = &"upgrade"
		_next_goal_tick = 0
		return action
	if observation.phase == GameTypes.RunPhase.CHEST_REWARD:
		_resume_fire = true
		action.kind = BotAction.Kind.CONTINUE_CHEST
		action.reason = &"chest"
		_next_goal_tick = 0
		return action
	_view.camera_transform = observation.camera_transform
	_view.viewport_size = observation.viewport_size
	_navigation_origin = observation.player_position.round() - Vector2(NAV_DIMENSIONS - Vector2i.ONE) * NAV_CELL * 0.5
	_navigation.recenter(_navigation_origin)
	if observation.tick != _last_tick:
		_observe_bodies(observation)
		_remember_loot(observation)
		_remember_warnings(observation)
		_observe_needles(observation)
		_last_tick = observation.tick
	if observation.tick >= _next_goal_tick or observation.player_position.distance_squared_to(_goal) < 0.8:
		_choose_goal(observation)
		_next_goal_tick = observation.tick + 15
	if not _equipment_ready or observation.weapons != _equipment_weapons or observation.passives != _equipment_passives or _equipment_has_needles != (not _needle_definition.is_empty()):
		_refresh_equipment(observation)
	var best_move: Vector2 = _choose_move(observation)
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


func _choose_move(observation: BotObservation) -> Vector2:
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
		"boss_active": observation.boss_active, "escape_active": observation.tick <= _escape_until_tick,
		"swarm_speed": _knowledge.swarm_speed, "swarm_depth": _knowledge.swarm_depth,
		"boss_kind": CombatSnapshot.EnemyVisualKind.BOSS,
		"elite_kind": CombatSnapshot.EnemyVisualKind.ELITE,
		"bulwark_kind": CombatSnapshot.EnemyVisualKind.BULWARK,
		"swarms": swarms, "bosses": bosses,
	}, _directions)


func _update_engagement(observation: BotObservation) -> void:
	_engagement_distance = ENGAGEMENT_DISTANCE
	_slow_clearance = 2.0
	var weak_starter: bool = false
	var field_radius: float = 0.0
	var orbital_reach: float = 0.0
	for weapon: Dictionary in observation.weapons:
		if weapon["id"] == _knowledge.starter_weapon_id and int(weapon["level"]) < 4:
			weak_starter = true
		var definition: Dictionary = _knowledge.weapons[weapon["id"]]
		if int(definition["behavior"]) == GameTypes.WeaponBehavior.AURA and int(weapon["level"]) >= 2:
			field_radius = float(definition["effect_radius"][int(weapon["level"]) - 1])
		elif int(definition["behavior"]) == GameTypes.WeaponBehavior.ORBITAL:
			var index: int = int(weapon["level"]) - 1
			orbital_reach = float(definition["range"][index]) + float(definition["effect_radius"][index])
	if not weak_starter or not _needle_definition.is_empty() or maxf(field_radius, orbital_reach) <= 0.0:
		return
	var area_pct: float = 0.0
	for passive: Dictionary in observation.passives:
		var definition: Dictionary = _knowledge.passives[passive["id"]]
		if definition["stat"] == &"area_pct":
			area_pct += float(definition["amount"]) * int(passive["level"])
	if field_radius <= 0.0:
		# A low-level orbit contributes nothing while every pursuer is kept
		# beyond its reach. Approach its outer edge with room to keep moving.
		_engagement_distance = maxf(1.8, orbital_reach * (1.0 + area_pct / 100.0) + 0.4)
		_slow_clearance = 1.3
		return
	# A weak starter cannot clear a growing crowd while its upgraded aura is
	# kept out of range. Retain contact clearance while bringing the aura to bear.
	_engagement_distance = maxf(1.8, field_radius * (1.0 + area_pct / 100.0) - 0.1)
	_slow_clearance = 0.8


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
			if int(definition["behavior"]) == GameTypes.WeaponBehavior.DIRECTIONAL_PROJECTILE:
				_needle_definition = definition
				_needle_level = int(weapon["level"])
				break
	if _needle_definition.is_empty():
		return
	for position: Vector2 in observation.needles:
		if position.distance_squared_to(observation.player_position) > 0.25:
			continue
		if observation.tick - _needle_last_near_tick > 4:
			var cooldown_pct: float = 0.0
			for passive: Dictionary in observation.passives:
				var definition: Dictionary = _knowledge.passives[passive["id"]]
				if definition["stat"] == &"cooldown_pct":
					cooldown_pct += float(definition["amount"]) * int(passive["level"])
			var multiplier: float = maxf(_knowledge.minimum_cooldown_multiplier, 1.0 + cooldown_pct / 100.0)
			_needle_next_tick = observation.tick + maxi(1, roundi(float(_needle_definition["cooldown"][_needle_level - 1]) * multiplier))
		_needle_last_near_tick = observation.tick
		break
	if _resume_fire:
		# Returning from a modal readies weapons under the public combat rule.
		_needle_next_tick = observation.tick + 1
		_resume_fire = false


func _observe_bodies(observation: BotObservation) -> void:
	_navigation.observe_tracks({
		"enemies": observation.enemy_values(), "bullets": BotObservation.pack_bodies(observation.bullets),
		"player": observation.player_position, "tick": observation.tick,
		"elapsed": float(maxi(1, observation.tick - _last_tick)) / 60.0,
		"inverse": observation.camera_transform.orthonormalized().inverse(), "viewport": observation.viewport_size,
		"projection": observation.camera_projection,
	})


func _remember_loot(observation: BotObservation) -> void:
	_navigation.remember_loot(observation.loot, observation.camera_transform.orthonormalized().inverse(),
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
	var target: Vector3 = _navigation.choose_loot_goal({
		"player": player, "last_move": _last_move,
		"maxed": observation.build_maxed, "evolution_ready": _knowledge.evolution_ready(observation),
		"hp": observation.hp, "max_hp": observation.max_hp, "pickup_radius": _knowledge.pickup_radius,
		"loot_kinds": PackedInt32Array([BotObservation.LootKind.XP, BotObservation.LootKind.CHEST,
			BotObservation.LootKind.EVOLUTION_CHEST, BotObservation.LootKind.POWERUP, BotObservation.LootKind.NODE]),
	})
	if target.z != 0.0:
		_goal = Vector2(target.x, target.y)
		last_reason = &"collect"
		return
	for cue: Dictionary in observation.chest_guidance:
		if int(cue["kind"]) == GameTypes.ChestKind.EVOLUTION_CAPABLE and not _knowledge.evolution_ready(observation) and not observation.build_maxed:
			continue
		_goal = player + _view.screen_to_world_input(cue["direction"]).normalized() * 24.0
		last_reason = &"chest_direction"
		return
	_goal = player + _explore_direction * 24.0
	last_reason = &"explore"


func _route_to_goal(player: Vector2) -> void:
	_goal = _navigation.route_tracked(player, _goal, _knowledge.player_radius)


func _choose_upgrade(observation: BotObservation) -> int:
	var best: float = -INF
	var selected: int = -1
	for index: int in observation.options.size():
		var option: Dictionary = observation.options[index]
		var score: float = _upgrade_score(option, observation)
		if score > best:
			best = score
			selected = index
	return selected


func _upgrade_score(option: Dictionary, observation: BotObservation) -> float:
	var content_id: StringName = option["id"]
	var level: int = option["level"]
	if int(option["kind"]) == GameTypes.UpgradeKind.WEAPON:
		var definition: Dictionary = _knowledge.weapons[content_id]
		var behavior: int = definition["behavior"]
		var weapon_priorities: Array[float] = [110.0, 140.0, 84.0, 60.0, 90.0, 75.0, 85.0, 150.0]
		var weapon_score: float = weapon_priorities[behavior] + float(level) * 3.0
		if level == 0:
			weapon_score += 16.0
		if level > 0 and level + 1 == int(definition["max_level"]):
			weapon_score += 22.0
		return weapon_score
	var passive: Dictionary = _knowledge.passives[content_id]
	var stat: StringName = passive["stat"]
	var priorities: Dictionary[StringName, float] = {
		&"recovery_per_second": 70.0, &"max_hp_pct": 65.0, &"cooldown_pct": 68.0,
		&"might_pct": 52.0, &"area_pct": 50.0, &"duration_pct": 30.0,
		&"projectile_speed_pct": 15.0, &"luck_pct": 18.0,
	}
	var score: float = priorities[stat]
	# With only a weak starting weapon, one luck upgrade improves future
	# owned-item offers instead of repeatedly growing only defensive items.
	if stat == &"luck_pct" and level == 0 and observation.weapons.size() == 1 and int(observation.weapons[0]["level"]) < 4:
		score = maxf(score, 90.0)
	var starter_partner: StringName = _knowledge.evolutions[_knowledge.starter_weapon_id]["passive"]
	var has_starter_partner: bool = false
	for owned: Dictionary in observation.passives:
		if owned["id"] == starter_partner:
			has_starter_partner = true
	# A full passive inventory is permanent. Keep a slot for the initial
	# weapon's evolution instead of losing that route while filling the build.
	if level == 0 and not has_starter_partner and content_id != starter_partner and observation.passives.size() >= _knowledge.passive_slots - 1:
		score -= 1000.0
	if stat in [&"recovery_per_second", &"max_hp_pct"]:
		score += (1.0 - observation.hp / observation.max_hp) * 40.0
	for weapon: Dictionary in observation.weapons:
		var weapon_id: StringName = weapon["id"]
		if _knowledge.evolutions.has(weapon_id) and _knowledge.evolutions[weapon_id]["passive"] == content_id:
			if level == 0:
				score += 200.0 if weapon_id == _knowledge.starter_weapon_id else 50.0
			break
	return score
