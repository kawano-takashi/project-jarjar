extends RefCounted

const BotObservation = preload("res://dev/bot/bot_observation.gd")

const ARENA_SCENE: PackedScene = preload("res://scenes/gameplay/arena_combat.tscn")
const ENEMY_MESH_NAMES: Array[StringName] = [
	&"EnemyInstances", &"EnemySwarmerInstances", &"EnemyBulwarkInstances",
	&"EnemyShooterInstances", &"EnemyEliteInstances", &"EnemyBossInstances",
	&"EnemySwarmerEventRedInstances",
	&"EnemyEncirclerInstances",
]
## A frame-local culler shares the inverse camera matrix across all objects.
class Culler:
	extends RefCounted
	var inverse: Transform3D
	var projection: Projection
	var planes: Array[Plane] = []

	func _init(view: ArenaView) -> void:
		inverse = view.camera_transform.orthonormalized().inverse()
		projection = view.projection
		for plane_index: int in 6:
			planes.append(projection.get_projection_plane(plane_index))

	func contains_visual(world_transform: Transform3D, bounds: AABB) -> bool:
		var projected: AABB = (inverse * world_transform) * bounds
		return contains_projected(projected)

	func contains_projected(projected: AABB) -> bool:
		var center: Vector3 = projected.get_center()
		var half_size: Vector3 = projected.size * 0.5
		for plane: Plane in planes:
			if plane.distance_to(center) > plane.normal.abs().dot(half_size):
				return false
		return true

	func encloses_projected(projected: AABB) -> bool:
		var center: Vector3 = projected.get_center()
		var half_size: Vector3 = projected.size * 0.5
		for plane: Plane in planes:
			if plane.distance_to(center) > -plane.normal.abs().dot(half_size):
				return false
		return true


## Mesh culling accepts geometry only; it never reads combat state.
class Visual:
	extends RefCounted
	var bounds: AABB
	var _native: RefCounted

	func _init(mesh: Mesh) -> void:
		bounds = mesh.get_aabb()
		if not preload("res://dev/bot/native_loader.gd").ensure_loaded():
			return
		_native = ClassDB.instantiate(&"JarjarBotVisual") as RefCounted
		_native.setup(mesh)

	func is_visible(culler: Culler, world_transform: Transform3D) -> bool:
		return _native.is_visible(culler.inverse, culler.projection, world_transform)

	func visible_loot(culler: Culler, transforms: PackedVector3Array, indices: PackedInt32Array, kind: int) -> PackedVector4Array:
		return _native.visible_loot(culler.inverse, culler.projection, transforms, indices, kind)

var _visuals: Dictionary[StringName, Visual] = {}
var _native_observer: RefCounted


func _init() -> void:
	# Read the actual render meshes, without instantiating the arena in fast mode.
	var scene: SceneState = ARENA_SCENE.get_state()
	for node_index: int in scene.get_node_count():
		var node_name := StringName(str(scene.get_node_path(node_index)).get_file())
		for property_index: int in scene.get_node_property_count(node_index):
			var property_name: StringName = scene.get_node_property_name(node_index, property_index)
			var value: Variant = scene.get_node_property_value(node_index, property_index)
			if property_name == &"multimesh" and value is MultiMesh:
				_visuals[node_name] = Visual.new((value as MultiMesh).mesh)
			elif property_name == &"mesh" and value is Mesh:
				_visuals[node_name] = Visual.new(value as Mesh)

	if preload("res://dev/bot/native_loader.gd").ensure_loaded():
		_native_observer = ClassDB.instantiate(&"JarjarBotObserver") as RefCounted
		var enemy_visuals: Array[RefCounted] = []
		for mesh_name: StringName in ENEMY_MESH_NAMES:
			enemy_visuals.append(_visuals[mesh_name]._native)
		_native_observer.configure(enemy_visuals)


func capture(simulation: CombatSimulation, view: ArenaView) -> BotObservation:
	var observation := BotObservation.new()
	var state: RunState = simulation.state
	observation.tick = state.combat_tick
	observation.phase = state.phase
	observation.player_position = simulation.player_position
	observation.world_origin = simulation.world_origin
	observation.chest_guidance = simulation.arena_object_system.chest_guidance(simulation.player_position)
	observation.camera_transform = view.camera_transform
	observation.camera_projection = view.projection
	observation.viewport_size = view.viewport_size
	observation.hp = state.current_hp
	observation.max_hp = state.max_hp
	observation.level = state.level
	observation.build_maxed = state.build_maxed
	observation.boss_active = state.boss_spawned and not state.boss_defeated
	observation.boss_hp = state.boss_hp if observation.boss_active else 0.0
	for weapon: RunWeapon in state.weapons:
		observation.weapons.append({"id": weapon.weapon_id, "level": weapon.level, "evolved": weapon.evolved})
	for passive: RunPassive in state.passives:
		observation.passives.append({"id": passive.passive_id, "level": passive.level})
	if state.phase == GameTypes.RunPhase.LEVEL_UP and state.active_level_offer != null:
		for option: UpgradeOption in state.active_level_offer.options:
			observation.options.append({
				"id": option.content_id, "kind": option.kind,
				"level": option.current_level, "next": option.next_level,
			})
	if state.phase != GameTypes.RunPhase.COMBAT:
		return observation
	var culler := Culler.new(view)
	_capture_enemies(simulation, culler, observation)
	_capture_projectiles(simulation, culler, observation)
	_capture_xp(simulation, culler, observation)
	_capture_arena_loot(simulation, culler, observation)
	_capture_warnings(simulation, culler, observation)
	# Internal pool/spawn order is not observable, even when hidden objects change.
	observation.needles.sort()
	observation.loot.sort()
	return observation


func _capture_enemies(simulation: CombatSimulation, culler: Culler, observation: BotObservation) -> void:
	var geometry: Dictionary = simulation.world.public_enemy_geometry(observation.tick)
	geometry["inverse"] = culler.inverse
	geometry["projection"] = culler.projection
	observation.set_enemy_values(_native_observer.observe_bodies(geometry))


func _capture_projectiles(simulation: CombatSimulation, culler: Culler, observation: BotObservation) -> void:
	var geometry: Dictionary = simulation.world.public_projectile_geometry()
	observation.set_bullet_values(_visuals[&"ProjectileEnemyInstances"]._native.visible_bodies(
		culler.inverse, culler.projection, geometry.hostile, geometry.hostile_indices, 0.18))
	for needle: Vector4 in _visuals[&"ProjectileNeedleInstances"].visible_loot(culler, geometry.needles, geometry.needle_indices, 0):
		observation.needles.append(Vector2(needle.y, needle.z))


func _capture_xp(simulation: CombatSimulation, culler: Culler, observation: BotObservation) -> void:
	observation.loot.append_array(_visuals[&"XpInstances"].visible_loot(
		culler, simulation.xp_pickup_pool.visual_columns_by_slot(), simulation.xp_pickup_pool.visual_slot_indices(), BotObservation.LootKind.XP,
	))


func _capture_arena_loot(simulation: CombatSimulation, culler: Culler, observation: BotObservation) -> void:
	for pickup: ArenaPickup in simulation.arena_object_system.pickups:
		if not pickup.active:
			continue
		var kind: BotObservation.LootKind = BotObservation.LootKind.POWERUP
		var mesh_name: StringName = &"PickupInstances"
		if pickup.kind == ArenaPickup.Kind.CHEST:
			kind = BotObservation.LootKind.CHEST
			mesh_name = &"ChestInstances"
			if pickup.chest_kind == GameTypes.ChestKind.EVOLUTION_CAPABLE:
				kind = BotObservation.LootKind.EVOLUTION_CHEST
				mesh_name = &"EvolutionChestInstances"
		_add_loot(observation, culler, pickup.transform(), mesh_name, kind)
	for transform: Transform3D in simulation.arena_object_system.node_transforms():
		_add_loot(observation, culler, transform, &"NodeInstances", BotObservation.LootKind.NODE)


func _add_loot(
	observation: BotObservation, culler: Culler, transform: Transform3D,
	mesh_name: StringName, kind: BotObservation.LootKind,
) -> void:
	if not _visuals[mesh_name].is_visible(culler, transform):
		return
	observation.loot.append(Vector4(kind, transform.origin.x, transform.origin.z, transform.basis.x.length()))


func _capture_boundary(snapshot: CombatSnapshot, culler: Culler, observation: BotObservation) -> void:
	var points: PackedVector2Array = EncounterGeometry.points(snapshot.boss_boundary_center, snapshot.boss_boundary_radius)
	for index: int in points.size():
		var start: Vector2 = points[index]
		var end: Vector2 = points[(index + 1) % points.size()]
		var local_start: Vector3 = culler.inverse * Vector3(start.x, EncounterGeometry.BOUNDARY_HEIGHT, start.y)
		var local_end: Vector3 = culler.inverse * Vector3(end.x, EncounterGeometry.BOUNDARY_HEIGHT, end.y)
		var lower: float = 0.0
		var upper: float = 1.0
		for plane: Plane in culler.planes:
			var first: float = plane.distance_to(local_start)
			var last: float = plane.distance_to(local_end)
			if first > 0.0 and last > 0.0:
				upper = -1.0
				break
			if (first > 0.0) != (last > 0.0):
				var fraction: float = first / (first - last)
				if first > 0.0:
					lower = maxf(lower, fraction)
				else:
					upper = minf(upper, fraction)
		if upper <= lower:
			continue
		var clipped_start: Vector2 = start.lerp(end, lower)
		var clipped_end: Vector2 = start.lerp(end, upper)
		var tangent: Vector2 = (end - start).normalized()
		observation.boundary_segments.append(Vector4(clipped_start.x, clipped_start.y, clipped_end.x, clipped_end.y))
		observation.boundary_normals.append(Vector2(-tangent.y, tangent.x))


func _capture_warnings(simulation: CombatSimulation, culler: Culler, observation: BotObservation) -> void:
	var snapshot := CombatSnapshot.new()
	simulation._apply_snapshot_markers(snapshot)
	if snapshot.boss_boundary_active:
		_capture_boundary(snapshot, culler, observation)
	var reduce_motion: bool = simulation.vfx_pool.reduce_motion
	if snapshot.important_marker_active:
		var entry_transform: Transform3D = ArenaView.ring_transform(snapshot.important_marker_position, 0.05, snapshot.important_marker_radius, snapshot.important_marker_progress, reduce_motion)
		if _visuals[&"ImportantMarker"].is_visible(culler, entry_transform):
			observation.warnings.append({"kind": &"entry", "position": snapshot.important_marker_position, "radius": snapshot.important_marker_radius})
	if snapshot.boss_charge_active:
		var position: Vector2 = snapshot.boss_charge_position
		var radius: float = snapshot.boss_charge_radius
		var boss_transform: Transform3D = ArenaView.ring_transform(position, 0.055, radius, snapshot.boss_charge_progress, reduce_motion)
		var directions: PackedVector2Array = []
		for index: int in snapshot.boss_charge_spoke_count:
			var angle: float = snapshot.boss_charge_angle_offset + TAU * float(index) / float(snapshot.boss_charge_spoke_count)
			if _visuals[&"BossChargeSpokes"].is_visible(culler, ArenaView.boss_spoke_transform(position, radius, angle)):
				directions.append(Vector2.from_angle(angle))
		if not directions.is_empty() or _visuals[&"BossChargeMarker"].is_visible(culler, boss_transform):
			observation.warnings.append({
				"kind": &"boss", "position": position, "radius": radius,
				"directions": directions,
			})
	var warning: SwarmWarningState = simulation.enemy_system.stage_events.swarm_warning
	if warning == null:
		return
	var definition: SwarmEventDefinition = simulation.catalog.manifest().swarm_event
	var width: float = (float(definition.lateral_count - 1) + 0.5) * definition.lateral_pitch + 2.0 * definition.unit_definition.body_radius
	var length: float = 2.0 * (warning.spawn_distance + float(definition.depth_count - 1) * definition.depth_pitch + definition.unit_definition.body_radius)
	var transform := Transform3D(
		Basis(Vector3.UP, -warning.direction.angle()).scaled_local(Vector3(length, 1.0, width)),
		Vector3(warning.anchor.x, 0.07, warning.anchor.y),
	)
	if _visuals[&"SwarmWarningMarker"].is_visible(culler, transform):
		# The band alone reveals an axis, not its travel sign; the arrows can
		# be outside the view. Keep that unobservable sign out of the values.
		var axis: Vector2 = warning.direction
		if axis.x < 0.0 or (axis.x == 0.0 and axis.y < 0.0):
			axis = -axis
		var travel_direction := Vector2.ZERO
		for arrow: int in 3:
			var complete: bool = true
			for wing: int in 2:
				var arrow_transform: Transform3D = ArenaView.swarm_arrow_transform(warning.anchor, warning.direction, arrow * 2 + wing)
				var projected: AABB = (culler.inverse * arrow_transform) * _visuals[&"SwarmWarningArrows"].bounds
				if not culler.encloses_projected(projected):
					complete = false
			if complete:
				travel_direction = warning.direction
				break
		observation.warnings.append({
			"kind": &"swarm", "position": warning.anchor, "direction": axis,
			"width": width, "travel_direction": travel_direction,
		})


static func _sort_bodies(bodies: Array[BotObservation.Body]) -> void:
	# Native Vector4 sorting avoids a GDScript callback for every comparison.
	var keys := PackedVector4Array()
	keys.resize(bodies.size())
	for index: int in bodies.size():
		var body: BotObservation.Body = bodies[index]
		keys[index] = Vector4(body.kind, body.position.x, body.position.y, index)
	keys.sort()
	var ordered: Array[BotObservation.Body] = []
	ordered.resize(bodies.size())
	for index: int in keys.size():
		ordered[index] = bodies[int(keys[index].w)]
	# Only ties need a script comparator. Distinct visible attributes must not
	# inherit the pool order when objects happen to occupy the same position.
	var first: int = 0
	while first < ordered.size():
		var end: int = first + 1
		while end < ordered.size() and ordered[end].kind == ordered[first].kind and ordered[end].position == ordered[first].position:
			end += 1
		if end - first > 1:
			var group: Array[BotObservation.Body] = ordered.slice(first, end)
			group.sort_custom(_visible_body_less)
			for index: int in group.size():
				ordered[first + index] = group[index]
		first = end
	bodies.assign(ordered)


static func _visible_body_less(left: BotObservation.Body, right: BotObservation.Body) -> bool:
	if left.radius != right.radius:
		return left.radius < right.radius
	return not left.materializing and right.materializing
