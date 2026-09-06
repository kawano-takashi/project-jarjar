extends RefCounted

const BotAction = preload("res://dev/bot/bot_action.gd")
const BotObservation = preload("res://dev/bot/bot_observation.gd")
const BotKnowledge = preload("res://dev/bot/bot_knowledge.gd")

## Bot policy parameters, not game balance. All work budgets are tick-based.
const DIRECTION_COUNT: int = 32
const HORIZON_SECONDS: float = 1.0
const MEMORY_TICKS: int = 120
const TRACK_CELL: float = 0.75
const NAV_CELL: float = 1.0
const ROUTE_WALL_MARGIN: float = 4.0
const ENGAGEMENT_DISTANCE: float = 4.0
const SWARM_MEMORY_TICKS: int = 600

class Track:
	extends RefCounted
	var position := Vector2.ZERO
	var velocity := Vector2.ZERO
	var radius: float = 0.0
	var kind: int = 0
	var seen_tick: int = 0
	var materializing: bool = false
	var matched: bool = false
	var relative := Vector2.ZERO
	var avoidance_velocity := Vector2.ZERO
	var fixed_motion: bool = false

var _knowledge: BotKnowledge
var _directions: PackedVector2Array = []
var _enemies: Array[Track] = []
var _bullets: Array[Track] = []
var _swarm_warnings: Array[Dictionary] = []
## Key: quantized position and visible kind. Value: X, Z, scale, last seen tick.
var _loot_memory: Dictionary[Vector3i, Vector4] = {}
var _view := ArenaView.new()
var _last_tick: int = -1
var _last_move := Vector2.RIGHT
var _goal := Vector2.ZERO
var _next_goal_tick: int = 0
var _danger_cells: Dictionary[Vector2i, Array] = {}
var _avoid_reverse: bool = false
var _slow_movement_safe: bool = true
var _engagement_distance: float = ENGAGEMENT_DISTANCE
var _slow_clearance: float = 2.0
var _needle_last_near_tick: int = -1000
var _needle_next_tick: int = -1
var _resume_fire: bool = false
var _needle_definition: Dictionary = {}
var _needle_level: int = 0
var _previous_hp: float = -1.0
var _escape_until_tick: int = -1
var _navigation := AStarGrid2D.new()
var _navigation_origin := Vector2.ZERO
var last_reason: StringName = &""


func _init(knowledge: BotKnowledge) -> void:
	_knowledge = knowledge
	_navigation_origin = knowledge.arena_min + Vector2.ONE * ROUTE_WALL_MARGIN
	var dimensions := Vector2i((knowledge.arena_max - _navigation_origin - Vector2.ONE * ROUTE_WALL_MARGIN) / NAV_CELL) + Vector2i.ONE
	_navigation.region = Rect2i(Vector2i.ZERO, dimensions)
	_navigation.offset = _navigation_origin
	_navigation.cell_size = Vector2.ONE * NAV_CELL
	_navigation.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_navigation.update()
	_directions.append(Vector2.ZERO)
	for index: int in DIRECTION_COUNT:
		_directions.append(Vector2.from_angle(TAU * float(index) / float(DIRECTION_COUNT)))
	for index: int in DIRECTION_COUNT:
		_directions.append(Vector2.from_angle(TAU * float(index) / float(DIRECTION_COUNT)) * 0.5)


func decide(observation: BotObservation) -> BotAction:
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
	if observation.tick != _last_tick:
		_enemies = _track_bodies(observation.enemies, _enemies, observation, false)
		_bullets = _track_bodies(observation.bullets, _bullets, observation, true)
		_remember_loot(observation)
		_remember_warnings(observation)
		_observe_needles(observation)
		_last_tick = observation.tick
	if observation.tick >= _next_goal_tick or observation.player_position.distance_squared_to(_goal) < 0.8:
		_choose_goal(observation)
		_next_goal_tick = observation.tick + 15
	_update_engagement(observation)
	var nearby_enemies: Array[Track] = []
	_slow_movement_safe = true
	for enemy: Track in _enemies:
		if enemy.position.distance_squared_to(observation.player_position) < 81.0:
			enemy.relative = enemy.position - observation.player_position
			if enemy.relative.length() - enemy.radius - _knowledge.player_radius < _slow_clearance:
				_slow_movement_safe = false
			enemy.avoidance_velocity = enemy.velocity
			# Contact can make a pursuer appear stationary for a frame. Its
			# known pursuit rule still predicts motion toward the player.
			if _knowledge.enemy_speeds.has(enemy.kind) and not enemy.fixed_motion:
				var toward_player: Vector2 = -enemy.relative.normalized()
				enemy.avoidance_velocity = toward_player * _knowledge.enemy_speeds[enemy.kind]
			nearby_enemies.append(enemy)
	for bullet: Track in _bullets:
		bullet.relative = bullet.position - observation.player_position
	var best_score: float = -INF
	var best_move := Vector2.ZERO
	for direction: Vector2 in _directions:
		var score: float = _movement_score(direction, observation, nearby_enemies)
		if score > best_score:
			best_score = score
			best_move = direction
	_last_move = best_move
	if _needle_next_tick == observation.tick + 1 and not _needle_definition.is_empty():
		best_move = _aim_needles(nearby_enemies, best_move)
	action.move_input = _view.world_to_screen_input(best_move)
	action.reason = last_reason
	return action


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


func _observe_needles(observation: BotObservation) -> void:
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


func _aim_needles(nearby: Array[Track], navigation_move: Vector2) -> Vector2:
	for enemy: Track in nearby:
		if enemy.relative.length() - enemy.radius - _knowledge.player_radius < 1.5:
			return navigation_move
	for bullet: Track in _bullets:
		var speed_squared: float = bullet.velocity.length_squared()
		var closest_time: float = 0.0 if speed_squared < 0.00001 else clampf(-bullet.relative.dot(bullet.velocity) / speed_squared, 0.0, 1.0 / 60.0)
		if (bullet.relative + bullet.velocity * closest_time).length() < bullet.radius + _knowledge.player_radius + 0.15:
			return navigation_move
	var reach: float = _needle_definition["range"][_needle_level - 1]
	var best: float = 0.0
	var aim := Vector2.ZERO
	for index: int in DIRECTION_COUNT:
		var direction: Vector2 = _directions[index + 1]
		var score: float = 0.0
		for enemy: Track in nearby:
			if enemy.materializing:
				continue
			var relative: Vector2 = enemy.relative + enemy.velocity * 0.2
			var along: float = relative.dot(direction)
			if along > 0.0 and along < reach and absf(relative.cross(direction)) < enemy.radius + 0.25:
				score += 1.0 / (1.0 + along * 0.1)
		if score > best:
			best = score
			aim = direction
	if aim != Vector2.ZERO:
		# A legal small analog step aims this shot, then navigation resumes on
		# the next tick. No weapon timer or hidden target is queried.
		return aim * 0.02
	return navigation_move


func _track_bodies(
	bodies: Array[BotObservation.Body], old: Array[Track], observation: BotObservation, bullet: bool,
) -> Array[Track]:
	var elapsed: float = float(maxi(1, observation.tick - _last_tick)) / 60.0
	var cells: Dictionary[Vector3i, Array] = {}
	for track: Track in old:
		track.matched = false
		var predicted: Vector2 = track.position + track.velocity * elapsed
		var cell := Vector3i(floori(predicted.x / TRACK_CELL), floori(predicted.y / TRACK_CELL), track.kind)
		if not cells.has(cell):
			cells[cell] = []
		cells[cell].append(track)
	var result: Array[Track] = []
	for body: BotObservation.Body in bodies:
		var cell := Vector3i(floori(body.position.x / TRACK_CELL), floori(body.position.y / TRACK_CELL), body.kind)
		var closest: Track = null
		var best_distance: float = TRACK_CELL * TRACK_CELL
		for x_offset: int in range(-1, 2):
			for y_offset: int in range(-1, 2):
				var neighbor_cell: Vector3i = cell + Vector3i(x_offset, y_offset, 0)
				if not cells.has(neighbor_cell):
					continue
				var neighbors: Array = cells[neighbor_cell]
				for track: Track in neighbors:
					if track.matched:
						continue
					var distance: float = body.position.distance_squared_to(track.position + track.velocity * elapsed)
					if distance < best_distance:
						best_distance = distance
						closest = track
		if closest == null:
			closest = Track.new()
			closest.fixed_motion = body.kind == CombatSnapshot.EnemyVisualKind.SWARMER_EVENT_RED
			if not bullet:
				var speed: float = _knowledge.enemy_speeds.get(body.kind, 0.0)
				closest.velocity = (observation.player_position - body.position).normalized() * speed
		else:
			closest.velocity = (body.position - closest.position) / elapsed
			if not bullet and body.kind == CombatSnapshot.EnemyVisualKind.SWARMER:
				var observed_speed: float = closest.velocity.length()
				if absf(observed_speed - _knowledge.swarm_speed) < 0.03:
					closest.fixed_motion = true
				elif absf(observed_speed - float(_knowledge.enemy_speeds[body.kind])) < 0.03:
					closest.fixed_motion = false
			if not bullet and _knowledge.enemy_speeds.has(body.kind):
				var speed_limit: float = _knowledge.enemy_speeds[body.kind]
				# White swarm members share the ordinary swarmer mesh. Identify the
				# faster motion from observations, never from the hidden movement kind.
				if body.kind == CombatSnapshot.EnemyVisualKind.SWARMER and closest.velocity.length() > _knowledge.swarm_speed * 0.7:
					speed_limit = _knowledge.swarm_speed
				closest.velocity = closest.velocity.limit_length(speed_limit)
		closest.position = body.position
		closest.radius = body.radius
		closest.kind = body.kind
		closest.materializing = body.materializing
		closest.seen_tick = observation.tick
		closest.matched = true
		result.append(closest)
	for track: Track in old:
		if track.matched or observation.tick - track.seen_tick > MEMORY_TICKS:
			continue
		track.position += track.velocity * elapsed
		# Forget an absent object only where the observation can actually see.
		var pixel: Vector2 = _view.project_position(Vector3(track.position.x, 0.35, track.position.y))
		if Rect2(Vector2.ZERO, Vector2(observation.viewport_size)).grow(-24.0).has_point(pixel):
			continue
		result.append(track)
	return result


func _remember_loot(observation: BotObservation) -> void:
	for loot: Vector4 in observation.loot:
		var position := Vector2(loot.y, loot.z)
		var key := Vector3i(roundi(position.x * 2.0), roundi(position.y * 2.0), int(loot.x))
		_loot_memory[key] = Vector4(position.x, position.y, loot.w, observation.tick)
	for key: Vector3i in _loot_memory.keys():
		var entry: Vector4 = _loot_memory[key]
		if int(entry.w) == observation.tick:
			continue
		var position := Vector2(entry.x, entry.y)
		var pixel: Vector2 = _view.project_position(Vector3(position.x, 0.3, position.y))
		if (
			Rect2(Vector2.ZERO, Vector2(observation.viewport_size)).grow(-24.0).has_point(pixel)
			or (key.z == BotObservation.LootKind.XP and observation.tick - int(entry.w) > 300)
		):
			_loot_memory.erase(key)


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
	_danger_cells.clear()
	_avoid_reverse = false
	for enemy: Track in _enemies:
		var cell := Vector2i(floori(enemy.position.x / 2.0), floori(enemy.position.y / 2.0))
		if not _danger_cells.has(cell):
			_danger_cells[cell] = []
		_danger_cells[cell].append(enemy.position)
		if enemy.position.distance_squared_to(player) < 25.0:
			_avoid_reverse = true
	if observation.boss_active:
		for enemy: Track in _enemies:
			if enemy.kind == CombatSnapshot.EnemyVisualKind.BOSS:
				var from_boss: Vector2 = (player - enemy.position).normalized()
				if from_boss == Vector2.ZERO:
					from_boss = Vector2.RIGHT
				# Circle the boss so repeated volleys cannot herd us straight into
				# the boundary while we try to maintain the same radial distance.
				_goal = enemy.position + from_boss.rotated(0.65) * 3.8
				last_reason = &"boss"
				return
	var best: float = -INF
	var best_position := Vector2.ZERO
	var evolution_ready: bool = _knowledge.evolution_ready(observation)
	var clusters: Dictionary[Vector2i, Dictionary] = {}
	for key: Vector3i in _loot_memory:
		var entry: Vector4 = _loot_memory[key]
		var position := Vector2(entry.x, entry.y)
		var kind: int = key.z
		if kind != BotObservation.LootKind.XP and not _collect_goal_is_open(position, player):
			continue
		var distance: float = player.distance_to(position)
		var value: float = 0.0
		match kind:
			BotObservation.LootKind.XP:
				if observation.build_maxed:
					continue
				var cell := Vector2i(floori(position.x / 2.0), floori(position.y / 2.0))
				if not clusters.has(cell):
					clusters[cell] = {"sum": Vector2.ZERO, "weight": 0.0}
				var weight: float = float(entry.z) * float(entry.z)
				clusters[cell]["sum"] += position * weight
				clusters[cell]["weight"] += weight
				continue
			BotObservation.LootKind.CHEST:
				value = 28.0
			BotObservation.LootKind.EVOLUTION_CHEST:
				if not evolution_ready and not observation.build_maxed:
					continue
				value = 70.0
			BotObservation.LootKind.POWERUP:
				value = 14.0 + 25.0 * (1.0 - observation.hp / observation.max_hp)
			BotObservation.LootKind.NODE:
				value = 2.0
		var score: float = value / (distance + 2.0)
		if score > best:
			best = score
			best_position = position
	for cluster: Dictionary in clusters.values():
		var weight: float = cluster["weight"]
		var position: Vector2 = cluster["sum"] / weight
		var approach: Vector2 = position + (player - position).normalized() * minf(_knowledge.pickup_radius - 0.5, player.distance_to(position))
		if not _collect_goal_is_open(approach, player):
			continue
		var score: float = (5.0 + sqrt(weight) * 4.0) / (player.distance_to(position) + 2.0)
		if score > best:
			best = score
			best_position = approach
	if best > 0.0:
		_goal = best_position
		last_reason = &"collect"
		return
	var radius: float = minf(_knowledge.arena_max.x, _knowledge.arena_max.y) * 0.52
	var radial: Vector2 = player.normalized()
	if radial == Vector2.ZERO:
		radial = Vector2.RIGHT
	_goal = radial.rotated(0.65) * radius
	last_reason = &"explore"


func _navigation_cell(position: Vector2) -> Vector2i:
	var cell := Vector2i(((position - _navigation_origin) / NAV_CELL).round())
	return cell.clamp(Vector2i.ZERO, _navigation.region.size - Vector2i.ONE)


func _route_to_goal(player: Vector2) -> void:
	_goal = _goal.clamp(_navigation_origin, _navigation.get_point_position(_navigation.region.end - Vector2i.ONE))
	_navigation.fill_weight_scale_region(_navigation.region, 1.0)
	for enemy: Track in _enemies:
		var position: Vector2 = enemy.position + enemy.velocity * 0.3
		var contact_radius: float = enemy.radius + _knowledge.player_radius
		var radius: float = contact_radius + 2.0
		var lower: Vector2i = _navigation_cell(position - Vector2.ONE * radius)
		var upper: Vector2i = _navigation_cell(position + Vector2.ONE * radius)
		for x_index: int in range(lower.x, upper.x + 1):
			for y_index: int in range(lower.y, upper.y + 1):
				var cell := Vector2i(x_index, y_index)
				var clearance: float = _navigation.get_point_position(cell).distance_to(position) - contact_radius
				if clearance < 2.0:
					var danger: float = 20.0 * (2.0 - clearance) * (2.0 - clearance)
					_navigation.set_point_weight_scale(cell, _navigation.get_point_weight_scale(cell) + danger)
	var start: Vector2i = _navigation_cell(player)
	var path: PackedVector2Array = _navigation.get_point_path(start, _navigation_cell(_goal))
	if path.size() >= 2:
		_goal = path[mini(3, path.size() - 1)]


func _collect_goal_is_open(position: Vector2, player: Vector2) -> bool:
	# Drops beyond the playable floor can be visible. Do not chase them into
	# a wall, and retain room to turn while collecting near the boundary.
	var margin: float = 3.0
	if (
		position.x < _knowledge.arena_min.x + margin or position.x > _knowledge.arena_max.x - margin
		or position.y < _knowledge.arena_min.y + margin or position.y > _knowledge.arena_max.y - margin
	):
		return false
	if _avoid_reverse and (position - player).normalized().dot(_last_move.normalized()) < -0.75:
		return false
	var cell := Vector2i(floori(position.x / 2.0), floori(position.y / 2.0))
	for x_offset: int in range(-1, 2):
		for y_offset: int in range(-1, 2):
			var neighbors: Array = _danger_cells.get(cell + Vector2i(x_offset, y_offset), [])
			for enemy_position: Vector2 in neighbors:
				if enemy_position.distance_squared_to(position) < 4.0:
					return false
	return true


func _movement_score(direction: Vector2, observation: BotObservation, nearby: Array[Track]) -> float:
	var player: Vector2 = observation.player_position
	var velocity: Vector2 = direction * _knowledge.move_speed
	var travel_time: float = HORIZON_SECONDS
	if velocity.x > 0.0:
		travel_time = minf(travel_time, (_knowledge.arena_max.x - player.x) / velocity.x)
	elif velocity.x < 0.0:
		travel_time = minf(travel_time, (_knowledge.arena_min.x - player.x) / velocity.x)
	if velocity.y > 0.0:
		travel_time = minf(travel_time, (_knowledge.arena_max.y - player.y) / velocity.y)
	elif velocity.y < 0.0:
		travel_time = minf(travel_time, (_knowledge.arena_min.y - player.y) / velocity.y)
	if travel_time < 1.0 / 60.0:
		return -1.0e12 + direction.dot(-player) * 100.0
	var destination: Vector2 = player + velocity * travel_time
	var score: float = direction.dot((_goal - player).normalized()) * 1000.0
	# Keep a continuous escape path instead of reversing every tick between
	# equally crowded directions and allowing pursuers to surround us.
	score += direction.normalized().dot(_last_move.normalized()) * 1002.0
	score -= (HORIZON_SECONDS - travel_time) * 1000.0
	var wall_distance: float = minf(minf(destination.x - _knowledge.arena_min.x, _knowledge.arena_max.x - destination.x), minf(destination.y - _knowledge.arena_min.y, _knowledge.arena_max.y - destination.y))
	score -= 20.0 / maxf(0.15, wall_distance)
	var immediate_clearance: float = INF
	var body_clearance: float = INF
	var engagement_distance: float = INF
	for enemy: Track in nearby:
		var relative: Vector2 = enemy.relative
		var relative_velocity: Vector2 = enemy.avoidance_velocity - velocity
		engagement_distance = minf(engagement_distance, (relative + relative_velocity * HORIZON_SECONDS).length())
		var speed_squared: float = relative_velocity.length_squared()
		var closest_time: float = 1.0 / 60.0 if speed_squared < 0.00001 else clampf(-relative.dot(relative_velocity) / speed_squared, 1.0 / 60.0, travel_time)
		var clearance: float = (relative + relative_velocity * closest_time).length() - enemy.radius - _knowledge.player_radius
		var next_clearance: float = (relative + relative_velocity / 60.0).length() - enemy.radius - _knowledge.player_radius
		immediate_clearance = minf(immediate_clearance, next_clearance)
		body_clearance = minf(body_clearance, next_clearance)
		# A projectile is consumed on contact; touching the boss damages us on
		# consecutive ticks. Never dodge a single shot by running into its body.
		if enemy.kind == CombatSnapshot.EnemyVisualKind.BOSS and next_clearance < 0.4:
			score -= 1.0e7 + (0.4 - next_clearance) * 1.0e8
		if clearance < 0.5:
			var urgency: float = (1.1 - closest_time) * (1.1 - closest_time)
			score -= (80.0 + (0.5 - clearance) * 200.0) * urgency / (0.2 + closest_time)
		else:
			score -= 1.5 / ((clearance + 0.25) * (clearance + 0.25))
	# Slower legal input can retain attack opportunities without reversing
	# into the pursuing crowd. Always evaluate the same 65 candidates.
	if not observation.boss_active and not nearby.is_empty():
		score -= 300.0 * pow(maxf(0.0, engagement_distance - _engagement_distance), 2.0)
	for bullet: Track in _bullets:
		var relative: Vector2 = bullet.relative
		var relative_velocity: Vector2 = bullet.velocity - velocity
		var speed_squared: float = relative_velocity.length_squared()
		var closest_time: float = 0.0 if speed_squared < 0.00001 else clampf(-relative.dot(relative_velocity) / speed_squared, 0.0, travel_time)
		var clearance: float = (relative + relative_velocity * closest_time).length() - bullet.radius - _knowledge.player_radius
		immediate_clearance = minf(immediate_clearance, (relative + relative_velocity / 60.0).length() - bullet.radius - _knowledge.player_radius)
		if clearance < 0.12:
			score -= 7000.0 / (0.15 + closest_time)
		elif clearance < 1.0:
			score -= 4.0 / (clearance + 0.1)
	var warning_destination: Vector2 = player + velocity * minf(travel_time, 0.25)
	for warning: Dictionary in _swarm_warnings:
		var axis: Vector2 = warning["direction"]
		var tangent := Vector2(-axis.y, axis.x)
		var width: float = float(warning["width"]) * 0.5 + _knowledge.player_radius + 0.5
		var relative: Vector2 = warning_destination - Vector2(warning["position"])
		var side_distance: float = absf(relative.dot(tangent))
		if side_distance >= width:
			continue
		# The visible arrows identify travel direction. Otherwise retain both
		# possible directions. Advance this corridor only from observed time,
		# never from the live group's hidden position or disappearance.
		var age: float = float(observation.tick - int(warning["seen"])) / 60.0
		var front: float = -_knowledge.swarm_spawn_min + _knowledge.swarm_speed * (age + HORIZON_SECONDS) + _knowledge.player_radius
		var back: float = -_knowledge.swarm_spawn_max - _knowledge.swarm_depth + _knowledge.swarm_speed * maxf(0.0, age - HORIZON_SECONDS) - _knowledge.player_radius
		var travel: Vector2 = warning.get("travel_direction", Vector2.ZERO)
		var along: float = relative.dot(travel if travel != Vector2.ZERO else axis)
		if (along >= back and along <= front) or (travel == Vector2.ZERO and -along >= back and -along <= front):
			score -= (width - side_distance) * 5000.0
	for warning: Dictionary in observation.warnings:
		if warning["kind"] == &"boss":
			var relative: Vector2 = destination - Vector2(warning["position"])
			var lane_clearance: float = INF
			for spoke: Vector2 in warning["directions"]:
				var clearance: float = absf(relative.cross(spoke)) if relative.dot(spoke) >= 0.0 else relative.length()
				lane_clearance = minf(lane_clearance, clearance)
			score -= 12.0 / (0.2 + lane_clearance)
	# Escape from a closing crowd instead of maximizing a tiny clearance while
	# standing still. Contact risk remains costly, but cannot freeze the bot.
	if direction == Vector2.ZERO and not nearby.is_empty():
		score -= 1.0e11
	# A crowd's summed future risk must not outweigh an actual contact on the
	# next tick. Keep this separate from projectile risk: bodies keep damaging.
	if body_clearance < 0.1:
		score -= 1.0e7 + (0.1 - body_clearance) * 1.0e8
	if immediate_clearance < 0.1:
		score -= 2000.0 + (0.1 - immediate_clearance) * 20000.0
	# Slow only with room to leave. A slower gap can look safe for one tick
	# while letting a pursuing crowd close all the exits around the player.
	if direction.length_squared() < 0.5 and not _slow_movement_safe:
		score -= 10000.0
	# Leave turning room around an elite's large body. Letting the crowd pin
	# the player against that body can consume all HP before the next volley.
	for enemy: Track in nearby:
		if enemy.kind != CombatSnapshot.EnemyVisualKind.ELITE:
			continue
		var clearance: float = (enemy.relative + (enemy.avoidance_velocity - velocity) / 60.0).length() - enemy.radius - _knowledge.player_radius
		if clearance < 0.8:
			score -= 1.0e7 + (0.8 - clearance) * 1.0e8
	# Armored groups also need turning room, but a smaller buffer preserves
	# the narrow escape gaps a weak loadout needs before it clears the crowd.
	for enemy: Track in nearby:
		if enemy.kind != CombatSnapshot.EnemyVisualKind.BULWARK:
			continue
		var clearance: float = (enemy.relative + (enemy.avoidance_velocity - velocity) / 60.0).length() - enemy.radius - _knowledge.player_radius
		if clearance < 0.4:
			score -= 1.0e7 + (0.4 - clearance) * 1.0e8
	return _escape_score(direction, observation, nearby, score)


func _escape_score(direction: Vector2, observation: BotObservation, nearby: Array[Track], baseline: float) -> float:
	if observation.tick > _escape_until_tick:
		return baseline
	var closest: float = INF
	for enemy: Track in nearby:
		closest = minf(closest, enemy.relative.length() - enemy.radius - _knowledge.player_radius)
	if closest >= 0.6:
		return baseline
	if direction.length_squared() < 0.5:
		return -1.0e13
	# Once the visible HP bar falls during close contact, a tiny improvement in
	# next-tick clearance can keep us trapped. Predict 60 pursuit steps for each
	# full-speed escape, minimizing sustained contact instead. This uses only
	# observed bodies, remembered motion, and the known player/pursuit rules.
	var velocity: Vector2 = direction * _knowledge.move_speed
	var danger: float = 0.0
	for enemy: Track in nearby:
		if enemy.relative.length_squared() > 36.0:
			continue
		var position: Vector2 = enemy.position
		var radius: float = enemy.radius + _knowledge.player_radius
		var enemy_speed: float = float(_knowledge.enemy_speeds.get(enemy.kind, enemy.velocity.length()))
		for step: int in range(1, 61):
			var player: Vector2 = (observation.player_position + velocity * (float(step) / 60.0)).clamp(_knowledge.arena_min, _knowledge.arena_max)
			if enemy.fixed_motion:
				position += enemy.velocity / 60.0
			else:
				var away: Vector2 = position - player
				var distance: float = away.length()
				if distance < radius:
					position = player + away.normalized() * radius
				else:
					position -= away.normalized() * minf(enemy_speed / 60.0, distance - radius)
			var clearance: float = position.distance_to(player) - radius
			if clearance < 0.05:
				danger += 1.0 + float(60 - step) / 60.0
			elif clearance < 0.4:
				danger += (0.4 - clearance) * 0.1
	var destination: Vector2 = observation.player_position + velocity
	var wall_cost: float = destination.distance_to(destination.clamp(_knowledge.arena_min, _knowledge.arena_max))
	return -danger * 1000.0 - wall_cost * 1.0e6 + direction.dot(_last_move.normalized()) * 100.0 + direction.dot((_goal - observation.player_position).normalized()) * 10.0


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
