class_name ArenaPresenter
extends Node3D


signal terminal_presentation_finished(phase: GameTypes.RunPhase)

const CAMERA_FOLLOW_TAU_SECONDS: float = CombatEnvelope.CAMERA_FOLLOW_TAU_SECONDS
const CAMERA_OFFSET: Vector3 = Vector3(8.912187, 18.0, 8.912187)
const CAMERA_INPUT_AXIS_EPSILON_SQUARED: float = 0.000001
const GRID_SPACING_M: float = 2.5
const BOSS_DEFEAT_SECONDS: float = 0.80
const PLAYER_DEFEAT_SECONDS: float = 0.45
const ABSORPTION_EVENT_SECONDS: float = 0.24

@onready var _player_mesh: MeshInstance3D = %PlayerMesh
@onready var _camera: Camera3D = %ArenaCamera
@onready var _enemy_instances: Array[MultiMeshInstance3D] = [
	%EnemyInstances,
	%EnemySwarmerInstances,
	%EnemyBulwarkInstances,
	%EnemyShooterInstances,
	%EnemyEliteInstances,
	%EnemyBossInstances,
	%EnemySwarmerEventRedInstances,
]
@onready var _projectile_instances: Array[MultiMeshInstance3D] = [
	%ProjectileInstances,
	%ProjectileResonanceInstances,
	%ProjectileHomingInstances,
	%ProjectileNeedleInstances,
	%ProjectileArcInstances,
	%ProjectileReturningInstances,
	%ProjectileOrbitalInstances,
	%ProjectileMassInstances,
	%ProjectileFieldInstances,
	%ProjectileEnemyInstances,
]
@onready var _evolved_outline_inner_instances: MultiMeshInstance3D = %EvolvedOutlineInnerInstances
@onready var _evolved_outline_outer_instances: MultiMeshInstance3D = %EvolvedOutlineOuterInstances
@onready var _evolved_core_instances: MultiMeshInstance3D = %EvolvedCoreInstances
@onready var _vfx_instances: MultiMeshInstance3D = %VfxInstances
@onready var _chest_instances: MultiMeshInstance3D = %ChestInstances
@onready var _evolution_chest_instances: MultiMeshInstance3D = %EvolutionChestInstances
@onready var _swarm_warning_marker: MeshInstance3D = %SwarmWarningMarker
@onready var _swarm_warning_arrows: MultiMeshInstance3D = %SwarmWarningArrows
@onready var _xp_instances: MultiMeshInstance3D = %XpInstances
@onready var _pickup_instances: MultiMeshInstance3D = %PickupInstances
@onready var _node_instances: MultiMeshInstance3D = %NodeInstances
@onready var _grid_lines: MultiMeshInstance3D = %GridLines
@onready var _important_marker: MeshInstance3D = %ImportantMarker
@onready var _important_countdown: Label3D = %ImportantCountdown
@onready var _boss_charge_marker: MeshInstance3D = %BossChargeMarker
@onready var _boss_charge_spokes: MultiMeshInstance3D = %BossChargeSpokes
@onready var _absorption_marker: MeshInstance3D = %AbsorptionMarker
@onready var _absorption_event_instances: MultiMeshInstance3D = %AbsorptionEventInstances
@onready var _terminal_boss_ring: MeshInstance3D = %TerminalBossRing
@onready var _terminal_player_ring: MeshInstance3D = %TerminalPlayerRing
@onready var _combat_hud: CombatHud = %CombatHUD

var _simulation: RefCounted = null
var _smoothed_camera_target: Vector3 = Vector3.ZERO
var _camera_target_initialized: bool = false
var _reduce_motion: bool = false
var _reduce_flashes: bool = false
var _last_important_position: Vector2 = Vector2.ZERO
var _terminal_phase: GameTypes.RunPhase = GameTypes.RunPhase.BOOT
var _terminal_position: Vector2 = Vector2.ZERO
var _terminal_elapsed: float = 0.0
var _terminal_duration: float = 0.0
var _terminal_active: bool = false
var _player_base_scale: Vector3 = Vector3.ONE
var _absorption_event_positions: PackedVector2Array = PackedVector2Array()
var _absorption_event_remaining: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	set_physics_process(false)
	set_process(false)
	_player_base_scale = _player_mesh.scale
	_configure_camera()
	_hide_presentation_markers()
	if _simulation != null:
		_configure_static_grid()
		_configure_render_capacity()
		_apply_snapshot(_simulation.build_snapshot(), 0.0)


func initialize(simulation: RefCounted) -> void:
	_simulation = simulation
	_camera_target_initialized = false
	_apply_accessibility_settings()
	if not is_node_ready():
		return
	set_physics_process(false)
	if _simulation != null:
		_configure_static_grid()
		_configure_render_capacity()
		_apply_snapshot(_simulation.build_snapshot(), 0.0)


func set_simulation_paused(_paused: bool) -> void:
	if _simulation != null and is_node_ready():
		_apply_snapshot(_simulation.build_snapshot(), 0.0)


func present_snapshot(snapshot: CombatSnapshot, delta: float) -> void:
	_apply_snapshot(snapshot, maxf(0.0, delta))


func present_event(event: CombatPresentationEvent) -> void:
	if event == null:
		return
	_combat_hud.present_event(event)
	if event.kind in [
		CombatPresentationEvent.Kind.IMPORTANT_SPAWN,
		CombatPresentationEvent.Kind.BOSS_DEFEATED,
	]:
		_last_important_position = event.position
	if event.kind == CombatPresentationEvent.Kind.ABSORPTION:
		_register_absorption_event(event.position)


func refresh_accessibility() -> void:
	_apply_accessibility_settings()


func set_debug_overlay_visible(should_show: bool) -> void:
	_combat_hud.set_debug_visible(should_show)


func camera_relative_move_input(screen_input: Vector2) -> Vector2:
	return _camera_relative_move_input(screen_input)


func terminal_focus_position(prefer_important: bool) -> Vector2:
	return _last_important_position if prefer_important else Vector2(
		_player_mesh.position.x,
		_player_mesh.position.z,
	)


func begin_terminal_presentation(
	phase: GameTypes.RunPhase,
	world_position: Vector2,
) -> void:
	if phase not in [GameTypes.RunPhase.RESULT, GameTypes.RunPhase.FAILED]:
		return
	_terminal_phase = phase
	_terminal_position = world_position
	_terminal_elapsed = 0.0
	_terminal_duration = (
		BOSS_DEFEAT_SECONDS if phase == GameTypes.RunPhase.RESULT else PLAYER_DEFEAT_SECONDS
	)
	_terminal_active = true
	_terminal_boss_ring.visible = phase == GameTypes.RunPhase.RESULT
	_terminal_player_ring.visible = phase == GameTypes.RunPhase.FAILED
	_player_mesh.scale = _player_base_scale
	set_process(true)


func terminal_presentation_active() -> bool:
	return _terminal_active


func _process(delta: float) -> void:
	if delta <= 0.0:
		return
	_advance_absorption_events(delta)
	if not _terminal_active:
		_update_process_state()
		return
	_terminal_elapsed = minf(_terminal_duration, _terminal_elapsed + delta)
	var progress: float = clampf(_terminal_elapsed / maxf(0.0001, _terminal_duration), 0.0, 1.0)
	if _terminal_phase == GameTypes.RunPhase.RESULT:
		_update_boss_terminal(progress)
	else:
		_update_player_terminal(progress)
	if progress < 1.0:
		return
	_terminal_active = false
	_update_process_state()
	terminal_presentation_finished.emit(_terminal_phase)


func _camera_relative_move_input(screen_input: Vector2) -> Vector2:
	if _camera == null:
		return screen_input
	var camera_right_3d: Vector3 = _camera.global_basis.x
	var camera_right := Vector2(camera_right_3d.x, camera_right_3d.z)
	if (
		not camera_right.is_finite()
		or camera_right.length_squared() <= CAMERA_INPUT_AXIS_EPSILON_SQUARED
	):
		return screen_input
	camera_right = camera_right.normalized()
	var camera_back := Vector2(-camera_right.y, camera_right.x)
	return camera_right * screen_input.x + camera_back * screen_input.y


func _apply_snapshot(snapshot: CombatSnapshot, delta: float) -> void:
	if snapshot == null:
		return
	_player_mesh.position = Vector3(
		snapshot.player_position.x,
		_player_mesh.position.y,
		snapshot.player_position.y,
	)
	_copy_visual_buckets(
		snapshot.enemy_transforms,
		snapshot.enemy_visual_kinds,
		snapshot.enemy_visual_custom_data,
		_enemy_instances,
		true,
	)
	_copy_visual_buckets(
		snapshot.projectile_transforms,
		snapshot.projectile_visual_kinds,
		snapshot.projectile_visual_custom_data,
		_projectile_instances,
		false,
	)
	_copy_evolved_projectile_accents(
		snapshot.projectile_transforms,
		snapshot.projectile_visual_custom_data,
	)
	_copy_vfx_prefix(snapshot, _vfx_instances)
	_copy_transform_prefix(snapshot.normal_chest_transforms, _chest_instances)
	_copy_transform_prefix(snapshot.evolution_chest_transforms, _evolution_chest_instances)
	_copy_transform_prefix(snapshot.xp_transforms, _xp_instances)
	_copy_transform_prefix(snapshot.pickup_transforms, _pickup_instances)
	_copy_transform_prefix(snapshot.node_transforms, _node_instances)
	_update_snapshot_markers(snapshot)
	_combat_hud.update_from_snapshot(snapshot)
	_update_camera(snapshot.player_position, delta)


func _copy_visual_buckets(
	transforms: Array[Transform3D],
	visual_kinds: PackedInt32Array,
	custom_data_values: PackedColorArray,
	instances: Array[MultiMeshInstance3D],
	materialize_enemy: bool,
) -> void:
	var counts := PackedInt32Array()
	counts.resize(instances.size())
	counts.fill(0)
	for source_index: int in range(transforms.size()):
		var visual_kind: int = (
			visual_kinds[source_index] if source_index < visual_kinds.size() else 0
		)
		visual_kind = clampi(visual_kind, 0, instances.size() - 1)
		var multimesh: MultiMesh = instances[visual_kind].multimesh
		if multimesh == null:
			continue
		var destination_index: int = counts[visual_kind]
		if destination_index >= multimesh.instance_count:
			continue
		var custom_data := (
			custom_data_values[source_index]
			if source_index < custom_data_values.size()
			else Color(1.0 if materialize_enemy else 0.0, 0.0, 0.0, 0.0)
		)
		var rendered_transform: Transform3D = transforms[source_index]
		if materialize_enemy:
			var progress: float = clampf(custom_data.r, 0.0, 1.0)
			var smooth_progress: float = progress * progress * (3.0 - 2.0 * progress)
			var materialization_scale: float = lerpf(0.12, 1.0, smooth_progress)
			rendered_transform.basis = rendered_transform.basis.scaled(
				Vector3.ONE * materialization_scale
			)
		custom_data.b = 1.0 if _reduce_motion else 0.0
		custom_data.a = 1.0 if _reduce_flashes else 0.0
		multimesh.set_instance_transform(destination_index, rendered_transform)
		multimesh.set_instance_custom_data(destination_index, custom_data)
		counts[visual_kind] += 1
	for visual_kind: int in range(instances.size()):
		var multimesh: MultiMesh = instances[visual_kind].multimesh
		if multimesh != null:
			multimesh.visible_instance_count = counts[visual_kind]


func _copy_transform_prefix(
	transforms: Array[Transform3D],
	instance: MultiMeshInstance3D,
) -> void:
	var multimesh: MultiMesh = instance.multimesh
	if multimesh == null:
		return
	var visible_count: int = transforms.size()
	if visible_count > multimesh.instance_count:
		multimesh.instance_count = visible_count
	for index: int in range(visible_count):
		multimesh.set_instance_transform(index, transforms[index])
	multimesh.visible_instance_count = visible_count


func _copy_evolved_projectile_accents(
	transforms: Array[Transform3D],
	custom_data_values: PackedColorArray,
) -> void:
	var inner_multimesh: MultiMesh = _evolved_outline_inner_instances.multimesh
	var outer_multimesh: MultiMesh = _evolved_outline_outer_instances.multimesh
	var core_multimesh: MultiMesh = _evolved_core_instances.multimesh
	if inner_multimesh == null or outer_multimesh == null or core_multimesh == null:
		return
	var capacity: int = mini(
		inner_multimesh.instance_count,
		mini(outer_multimesh.instance_count, core_multimesh.instance_count),
	)
	var evolved_count: int = 0
	for source_index: int in range(transforms.size()):
		if evolved_count >= capacity:
			break
		if (
			source_index >= custom_data_values.size()
			or custom_data_values[source_index].r < 0.5
		):
			continue
		var base_transform: Transform3D = transforms[source_index]
		var inner_transform: Transform3D = base_transform
		inner_transform.basis = inner_transform.basis * Basis(Vector3.UP, PI / 12.0)
		var outer_transform: Transform3D = base_transform
		outer_transform.basis = outer_transform.basis * Basis(Vector3.UP, PI / 18.0)
		var core_transform: Transform3D = base_transform
		core_transform.basis = core_transform.basis.scaled(Vector3.ONE * 1.2)
		inner_multimesh.set_instance_transform(evolved_count, inner_transform)
		outer_multimesh.set_instance_transform(evolved_count, outer_transform)
		core_multimesh.set_instance_transform(evolved_count, core_transform)
		evolved_count += 1
	inner_multimesh.visible_instance_count = evolved_count
	outer_multimesh.visible_instance_count = evolved_count
	core_multimesh.visible_instance_count = evolved_count


func _copy_vfx_prefix(snapshot: CombatSnapshot, instance: MultiMeshInstance3D) -> void:
	var multimesh: MultiMesh = instance.multimesh
	if multimesh == null:
		return
	var visible_count := mini(snapshot.vfx_transforms.size(), multimesh.instance_count)
	for index: int in range(visible_count):
		multimesh.set_instance_transform(index, snapshot.vfx_transforms[index])
		var color := snapshot.vfx_colors[index] if index < snapshot.vfx_colors.size() else Color.WHITE
		var custom_data := (
			snapshot.vfx_custom_data[index]
			if index < snapshot.vfx_custom_data.size()
			else Color(0.0, 0.0, 0.0, 0.0)
		)
		multimesh.set_instance_color(index, color)
		multimesh.set_instance_custom_data(index, custom_data)
	multimesh.visible_instance_count = visible_count


func _update_camera(player_position: Vector2, delta: float) -> void:
	var target := Vector3(player_position.x, 0.0, player_position.y)
	if not _camera_target_initialized:
		_smoothed_camera_target = target
		_camera_target_initialized = true
	elif delta > 0.0:
		var alpha := 1.0 - exp(-delta / CAMERA_FOLLOW_TAU_SECONDS)
		_smoothed_camera_target = _smoothed_camera_target.lerp(target, alpha)
	_camera.position = _smoothed_camera_target + CAMERA_OFFSET
	_camera.look_at(_smoothed_camera_target, Vector3.UP)


func _update_snapshot_markers(snapshot: CombatSnapshot) -> void:
	_update_swarm_warning(snapshot)
	if snapshot.important_marker_active:
		_last_important_position = snapshot.important_marker_position
	_update_ring(
		_important_marker,
		snapshot.important_marker_active,
		snapshot.important_marker_position,
		snapshot.important_marker_radius,
		snapshot.important_marker_progress,
	)
	_update_important_countdown(snapshot)
	_update_ring(
		_boss_charge_marker,
		snapshot.boss_charge_active,
		snapshot.boss_charge_position,
		snapshot.boss_charge_radius,
		snapshot.boss_charge_progress,
	)
	_update_boss_charge_spokes(snapshot)
	_update_ring(
		_absorption_marker,
		snapshot.absorption_active,
		snapshot.absorption_position,
		snapshot.absorption_radius,
		snapshot.absorption_progress,
	)


func _update_swarm_warning(snapshot: CombatSnapshot) -> void:
	_swarm_warning_marker.visible = snapshot.swarm_warning_active
	var arrows: MultiMesh = _swarm_warning_arrows.multimesh
	arrows.visible_instance_count = 6 if snapshot.swarm_warning_active else 0
	if not snapshot.swarm_warning_active:
		return
	var direction: Vector2 = snapshot.swarm_warning_direction
	var angle: float = direction.angle()
	_swarm_warning_marker.transform = Transform3D(
		Basis(Vector3.UP, -angle).scaled_local(Vector3(snapshot.swarm_warning_length, 1.0, snapshot.swarm_warning_width)),
		Vector3(snapshot.swarm_warning_anchor.x, 0.07, snapshot.swarm_warning_anchor.y),
	)
	_swarm_warning_marker.transparency = 0.78 if _reduce_flashes else 0.66
	var tangent := Vector2(-direction.y, direction.x)
	for index: int in range(6):
		var side: float = -1.0 if index % 2 == 0 else 1.0
		var tip: Vector2 = snapshot.swarm_warning_anchor + direction * (float(floori(float(index) / 2.0)) - 1.0) * 2.5
		var wing: Vector2 = (direction + tangent * side).normalized()
		var center: Vector2 = tip - wing * 0.6
		arrows.set_instance_transform(index, Transform3D(
			Basis(Vector3.UP, -wing.angle()).scaled_local(Vector3(1.2, 1.0, 0.10)),
			Vector3(center.x, 0.09, center.y),
		))


func _update_ring(
	marker: MeshInstance3D,
	active: bool,
	world_position: Vector2,
	radius: float,
	progress: float,
) -> void:
	marker.visible = active
	if not active:
		return
	marker.position = Vector3(world_position.x, marker.position.y, world_position.y)
	var pulse: float = 1.0
	if not _reduce_motion:
		pulse = 0.92 + 0.08 * sin(clampf(progress, 0.0, 1.0) * TAU * 2.0)
	marker.scale = Vector3.ONE * maxf(0.1, radius) * pulse
	marker.transparency = 0.48 if _reduce_flashes else 0.18


func _update_boss_charge_spokes(snapshot: CombatSnapshot) -> void:
	var multimesh: MultiMesh = _boss_charge_spokes.multimesh
	if multimesh == null:
		return
	if not snapshot.boss_charge_active:
		multimesh.visible_instance_count = 0
		return
	var spoke_count: int = maxi(0, snapshot.boss_charge_spoke_count)
	if spoke_count > multimesh.instance_count:
		multimesh.instance_count = spoke_count
	var radius: float = maxf(0.2, snapshot.boss_charge_radius)
	for spoke_index: int in range(spoke_count):
		var angle: float = (
			snapshot.boss_charge_angle_offset
			+ TAU * float(spoke_index) / float(maxi(1, spoke_count))
		)
		var direction := Vector2.from_angle(angle)
		var forward := Vector3(direction.x, 0.0, direction.y)
		var side := Vector3(direction.y, 0.0, -direction.x)
		var spoke_basis := Basis(side * 0.055, Vector3.UP * 0.025, forward * radius)
		var origin := Vector3(
			snapshot.boss_charge_position.x + direction.x * radius * 0.5,
			0.055,
			snapshot.boss_charge_position.y + direction.y * radius * 0.5,
		)
		multimesh.set_instance_transform(spoke_index, Transform3D(spoke_basis, origin))
	multimesh.visible_instance_count = spoke_count


func _update_important_countdown(snapshot: CombatSnapshot) -> void:
	_important_countdown.visible = snapshot.important_marker_active
	if not snapshot.important_marker_active:
		return
	var total_ticks: int = (
		_simulation.envelope.boss_entry_ticks
		if snapshot.important_marker_kind == CombatSnapshot.ImportantMarkerKind.BOSS
		else _simulation.envelope.elite_entry_ticks
	)
	var remaining_seconds: float = (
		float(total_ticks)
		* (1.0 - clampf(snapshot.important_marker_progress, 0.0, 1.0))
		/ 60.0
	)
	_important_countdown.position = Vector3(
		snapshot.important_marker_position.x,
		1.65,
		snapshot.important_marker_position.y,
	)
	_important_countdown.text = "%s  %.1f" % [
		"BOSS" if snapshot.important_marker_kind == CombatSnapshot.ImportantMarkerKind.BOSS else "ELITE",
		remaining_seconds,
	]
	_important_countdown.modulate.a = 0.78 if _reduce_flashes else 1.0


func _configure_static_grid() -> void:
	if _simulation == null:
		return
	var extent: Vector2 = _simulation.envelope.arena_max
	var dimensions: Vector2 = _simulation.envelope.arena_size
	var exterior_mesh: BoxMesh = ($Exterior as MeshInstance3D).mesh.duplicate() as BoxMesh
	exterior_mesh.size = Vector3(dimensions.x + 48.0, 0.08, dimensions.y + 48.0)
	($Exterior as MeshInstance3D).mesh = exterior_mesh
	var player_mesh: CapsuleMesh = _player_mesh.mesh.duplicate() as CapsuleMesh
	player_mesh.radius = _simulation.catalog.manifest().player.body_radius
	player_mesh.height = maxf(1.2, player_mesh.radius * 2.0)
	_player_mesh.mesh = player_mesh
	var floor_mesh: BoxMesh = ($Floor as MeshInstance3D).mesh.duplicate() as BoxMesh
	floor_mesh.size = Vector3(dimensions.x, 0.1, dimensions.y)
	($Floor as MeshInstance3D).mesh = floor_mesh
	for name_key: String in ["BoundaryNorth", "BoundarySouth", "BoundaryWest", "BoundaryEast"]:
		var wall: MeshInstance3D = get_node(name_key) as MeshInstance3D
		var mesh: BoxMesh = wall.mesh.duplicate() as BoxMesh
		if name_key in ["BoundaryNorth", "BoundarySouth"]:
			mesh.size = Vector3(dimensions.x + 0.5, 0.28, 0.24)
			wall.position.z = -extent.y if name_key == "BoundaryNorth" else extent.y
		else:
			mesh.size = Vector3(0.24, 0.28, dimensions.y)
			wall.position.x = -extent.x if name_key == "BoundaryWest" else extent.x
		wall.mesh = mesh
	var multimesh: MultiMesh = _grid_lines.multimesh.duplicate() as MultiMesh
	_grid_lines.multimesh = multimesh
	var half_x_lines: int = floori(extent.x / GRID_SPACING_M)
	var half_y_lines: int = floori(extent.y / GRID_SPACING_M)
	multimesh.instance_count = (half_x_lines + half_y_lines) * 2 + 2
	var line_index: int = 0
	for grid_index: int in range(-half_y_lines, half_y_lines + 1):
		multimesh.set_instance_transform(line_index, Transform3D(
			Basis.IDENTITY.scaled(Vector3(dimensions.x, 1.0, 1.0)),
			Vector3(0.0, 0.006, float(grid_index) * GRID_SPACING_M),
		))
		line_index += 1
	for grid_index: int in range(-half_x_lines, half_x_lines + 1):
		multimesh.set_instance_transform(line_index, Transform3D(
			Basis.IDENTITY.scaled(Vector3(1.0, 1.0, dimensions.y)),
			Vector3(float(grid_index) * GRID_SPACING_M, 0.006, 0.0),
		))
		line_index += 1
	multimesh.visible_instance_count = line_index


func _configure_render_capacity() -> void:
	var catalog: DefinitionCatalog = _simulation.catalog
	_resize_multimesh(_xp_instances, catalog.manifest().progression.xp_pool_capacity)
	_resize_multimesh(_node_instances, catalog.manifest().arena.node_site_positions.size())
	_resize_multimesh(_chest_instances, catalog.elite_spawn_ticks.size())
	_resize_multimesh(_evolution_chest_instances, catalog.elite_spawn_ticks.size())
	_resize_multimesh(_swarm_warning_arrows, 6)
	var boss: EnemyDefinition = catalog.enemy_for_type(GameTypes.EnemyType.BOSS)
	_resize_multimesh(_boss_charge_spokes, boss.volley_count + 2 * catalog.manifest().combat.boss_volley_phase_bonus)


func _resize_multimesh(instance: MultiMeshInstance3D, capacity: int) -> void:
	var multimesh: MultiMesh = instance.multimesh.duplicate() as MultiMesh
	multimesh.instance_count = capacity
	multimesh.visible_instance_count = 0
	instance.multimesh = multimesh


func _configure_camera() -> void:
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = CombatEnvelope.CAMERA_SIZE
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT


func _register_absorption_event(world_position: Vector2) -> void:
	var multimesh: MultiMesh = _absorption_event_instances.multimesh
	if multimesh == null:
		return
	if _absorption_event_positions.size() >= multimesh.instance_count:
		_absorption_event_positions.remove_at(0)
		_absorption_event_remaining.remove_at(0)
	_absorption_event_positions.append(world_position)
	_absorption_event_remaining.append(ABSORPTION_EVENT_SECONDS)
	_refresh_absorption_event_instances()
	set_process(true)


func _advance_absorption_events(delta: float) -> void:
	var event_index: int = _absorption_event_remaining.size() - 1
	while event_index >= 0:
		_absorption_event_remaining[event_index] = maxf(
			0.0,
			_absorption_event_remaining[event_index] - delta,
		)
		if _absorption_event_remaining[event_index] <= 0.0:
			_absorption_event_remaining.remove_at(event_index)
			_absorption_event_positions.remove_at(event_index)
		event_index -= 1
	_refresh_absorption_event_instances()


func _refresh_absorption_event_instances() -> void:
	var multimesh: MultiMesh = _absorption_event_instances.multimesh
	if multimesh == null:
		return
	for event_index: int in range(_absorption_event_positions.size()):
		var progress: float = 1.0 - (
			_absorption_event_remaining[event_index] / ABSORPTION_EVENT_SECONDS
		)
		var scale_value: float = 0.8 if _reduce_motion else lerpf(0.35, 1.4, progress)
		var world_position: Vector2 = _absorption_event_positions[event_index]
		multimesh.set_instance_transform(event_index, Transform3D(
			Basis.IDENTITY.scaled(Vector3.ONE * scale_value),
			Vector3(world_position.x, 0.065, world_position.y),
		))
	multimesh.visible_instance_count = _absorption_event_positions.size()


func _update_process_state() -> void:
	set_process(_terminal_active or not _absorption_event_positions.is_empty())


func _apply_accessibility_settings() -> void:
	var store: Variant = get_node_or_null("/root/SettingsStore") if is_inside_tree() else null
	_reduce_motion = bool(store.reduce_motion) if store != null else false
	_reduce_flashes = bool(store.reduce_flashes) if store != null else false
	if _simulation != null and _simulation.has_method(&"configure_accessibility"):
		_simulation.call(&"configure_accessibility", _reduce_motion, _reduce_flashes)
	if is_node_ready():
		_combat_hud.set_accessibility(_reduce_motion, _reduce_flashes)


func _hide_presentation_markers() -> void:
	for marker: MeshInstance3D in [
		_important_marker,
		_boss_charge_marker,
		_absorption_marker,
		_swarm_warning_marker,
		_terminal_boss_ring,
		_terminal_player_ring,
	]:
		marker.visible = false
	_important_countdown.visible = false
	_swarm_warning_arrows.multimesh.visible_instance_count = 0
	if _boss_charge_spokes.multimesh != null:
		_boss_charge_spokes.multimesh.visible_instance_count = 0


func _update_boss_terminal(progress: float) -> void:
	_terminal_boss_ring.position = Vector3(_terminal_position.x, 0.08, _terminal_position.y)
	var scale_value: float = 2.2 if _reduce_motion else lerpf(0.25, 4.8, progress)
	_terminal_boss_ring.scale = Vector3.ONE * scale_value
	_terminal_boss_ring.transparency = maxf(
		0.42 if _reduce_flashes else 0.0,
		clampf(progress, 0.0, 1.0),
	)


func _update_player_terminal(progress: float) -> void:
	_terminal_player_ring.position = Vector3(_terminal_position.x, 0.08, _terminal_position.y)
	var ring_scale: float = 1.0 if _reduce_motion else lerpf(1.8, 0.25, progress)
	_terminal_player_ring.scale = Vector3.ONE * ring_scale
	_terminal_player_ring.transparency = maxf(
		0.42 if _reduce_flashes else 0.0,
		clampf(progress * 0.8, 0.0, 1.0),
	)
	if _reduce_motion:
		_player_mesh.scale = _player_base_scale
		return
	var height_scale: float = maxf(0.08, 1.0 - progress * 0.92)
	_player_mesh.scale = Vector3(
		_player_base_scale.x * (1.0 + progress * 0.18),
		_player_base_scale.y * height_scale,
		_player_base_scale.z * (1.0 + progress * 0.18),
	)
