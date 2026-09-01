class_name ArenaPresenter
extends Node3D


signal phase_changed(phase: GameTypes.RunPhase)
signal audio_event_requested(event_id: StringName)


const CAMERA_TARGET_X_LIMIT: float = 9.0
const CAMERA_TARGET_Z_LIMIT: float = 4.5
const CAMERA_FOLLOW_TAU_SECONDS: float = 0.18
const CAMERA_OFFSET: Vector3 = Vector3(8.912187, 18.0, 8.912187)
const CAMERA_INPUT_AXIS_EPSILON_SQUARED: float = 0.000001

@onready var _player_mesh: MeshInstance3D = %PlayerMesh
@onready var _camera: Camera3D = %ArenaCamera
@onready var _enemy_instances: MultiMeshInstance3D = %EnemyInstances
@onready var _projectile_instances: MultiMeshInstance3D = %ProjectileInstances
@onready var _vfx_instances: MultiMeshInstance3D = %VfxInstances
@onready var _chest_instances: MultiMeshInstance3D = %ChestInstances
@onready var _combat_hud: CombatHud = %CombatHUD

var _simulation: CombatSimulation = null
var _tutorial: RefCounted = null
var _simulation_paused: bool = false
var _smoothed_camera_target: Vector3 = Vector3.ZERO
var _camera_target_initialized: bool = false


func _ready() -> void:
	set_physics_process(_simulation != null)
	if _simulation != null:
		_apply_snapshot(_simulation.build_snapshot(), 0.0)


func initialize(
	simulation: CombatSimulation,
	tutorial: RefCounted = null,
) -> void:
	_simulation = simulation
	_tutorial = tutorial
	_camera_target_initialized = false
	_apply_accessibility_settings()
	if not is_node_ready():
		return
	set_physics_process(_simulation != null)
	if _simulation != null:
		_apply_snapshot(_simulation.build_snapshot(), 0.0)


func set_simulation_paused(paused: bool) -> void:
	_simulation_paused = paused
	if _simulation != null and is_node_ready():
		_apply_snapshot(_simulation.build_snapshot(), 0.0)


func _physics_process(delta: float) -> void:
	if _simulation == null:
		return
	var snapshot: CombatSnapshot
	var previous_phase: GameTypes.RunPhase = _simulation.state.phase
	var previous_hp: float = _simulation.state.current_hp
	var previous_wave_cleared: bool = _simulation.state.wave_cleared
	var previous_absorb_count: int = _simulation.chest_visual_pool.completed_absorb_count
	if _simulation_paused:
		snapshot = _simulation.build_snapshot()
	else:
		var move_input := Input.get_vector(
			"move_left",
			"move_right",
			"move_up",
			"move_down",
			0.2
		)
		move_input = _camera_relative_move_input(move_input)
		if (
			_tutorial != null
			and _tutorial.should_gate_combat(_simulation.state.wave_number)
		):
			var previous_position: Vector2 = _simulation.player_position
			snapshot = _simulation.step_tutorial_movement(move_input, delta)
			_tutorial.advance_move(
				_simulation.player_position - previous_position,
				delta,
			)
		else:
			snapshot = _simulation.step(move_input, delta)
			if _tutorial != null:
				_tutorial.advance_combat(delta)
				if (
					_simulation.chest_visual_pool.completed_absorb_count
					> previous_absorb_count
				):
					_tutorial.notify_first_pickup()
			if (
				_simulation.chest_visual_pool.completed_absorb_count
				> previous_absorb_count
			):
				var absorbed_count := (
					_simulation.chest_visual_pool.completed_absorb_count
					- previous_absorb_count
				)
				_combat_hud.present_pickup(
					absorbed_count,
					_reduce_motion_enabled(),
					_reduce_flashes_enabled(),
				)
				audio_event_requested.emit(&"pickup")
	_apply_snapshot(snapshot, delta)
	if _simulation.state.current_hp < previous_hp:
		_combat_hud.present_damage(_reduce_motion_enabled(), _reduce_flashes_enabled())
	if not previous_wave_cleared and _simulation.state.wave_cleared:
		_combat_hud.present_wave_clear(_reduce_motion_enabled(), _reduce_flashes_enabled())
		audio_event_requested.emit(&"wave_clear")
	if _simulation.state.phase != previous_phase:
		phase_changed.emit(_simulation.state.phase)


func refresh_accessibility() -> void:
	_apply_accessibility_settings()


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
		snapshot.player_position.y
	)
	_copy_transform_prefix(snapshot.enemy_transforms, _enemy_instances)
	_copy_transform_prefix(snapshot.projectile_transforms, _projectile_instances)
	_copy_vfx_prefix(snapshot, _vfx_instances)
	_copy_transform_prefix(snapshot.chest_transforms, _chest_instances)
	_combat_hud.update_from_snapshot(snapshot)
	_update_camera(snapshot.player_position, delta)


func _copy_transform_prefix(
	transforms: Array[Transform3D],
	instance: MultiMeshInstance3D
) -> void:
	var multimesh: MultiMesh = instance.multimesh
	if multimesh == null:
		return
	var visible_count := mini(transforms.size(), multimesh.instance_count)
	for index: int in range(visible_count):
		multimesh.set_instance_transform(index, transforms[index])
	multimesh.visible_instance_count = visible_count


func _copy_vfx_prefix(
	snapshot: CombatSnapshot,
	instance: MultiMeshInstance3D,
) -> void:
	var multimesh: MultiMesh = instance.multimesh
	if multimesh == null:
		return
	var visible_count := mini(snapshot.vfx_transforms.size(), multimesh.instance_count)
	for index: int in range(visible_count):
		multimesh.set_instance_transform(index, snapshot.vfx_transforms[index])
		var color := (
			snapshot.vfx_colors[index]
			if index < snapshot.vfx_colors.size()
			else Color.WHITE
		)
		var custom_data := (
			snapshot.vfx_custom_data[index]
			if index < snapshot.vfx_custom_data.size()
			else Color(0.0, 0.0, 0.0, 0.0)
		)
		multimesh.set_instance_color(index, color)
		multimesh.set_instance_custom_data(index, custom_data)
	multimesh.visible_instance_count = visible_count


func _update_camera(player_position: Vector2, delta: float) -> void:
	var target := Vector3(
		clampf(player_position.x, -CAMERA_TARGET_X_LIMIT, CAMERA_TARGET_X_LIMIT),
		0.0,
		clampf(player_position.y, -CAMERA_TARGET_Z_LIMIT, CAMERA_TARGET_Z_LIMIT)
	)
	if not _camera_target_initialized:
		_smoothed_camera_target = target
		_camera_target_initialized = true
	elif delta > 0.0:
		var alpha := 1.0 - exp(-delta / CAMERA_FOLLOW_TAU_SECONDS)
		_smoothed_camera_target = _smoothed_camera_target.lerp(target, alpha)
	_camera.position = _smoothed_camera_target + CAMERA_OFFSET
	_camera.look_at(_smoothed_camera_target, Vector3.UP)


func _apply_accessibility_settings() -> void:
	if _simulation == null:
		return
	_simulation.configure_accessibility(
		_reduce_motion_enabled(),
		_reduce_flashes_enabled(),
	)


func _reduce_motion_enabled() -> bool:
	var store: Variant = (
		get_node_or_null("/root/SettingsStore") if is_inside_tree() else null
	)
	return bool(store.reduce_motion) if store != null else false


func _reduce_flashes_enabled() -> bool:
	var store: Variant = (
		get_node_or_null("/root/SettingsStore") if is_inside_tree() else null
	)
	return bool(store.reduce_flashes) if store != null else false
