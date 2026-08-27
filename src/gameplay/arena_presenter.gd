class_name ArenaPresenter
extends Node3D


signal phase_changed(phase: GameTypes.RunPhase)


const CAMERA_TARGET_X_LIMIT: float = 9.0
const CAMERA_TARGET_Z_LIMIT: float = 4.5
const CAMERA_FOLLOW_TAU_SECONDS: float = 0.18
const CAMERA_OFFSET: Vector3 = Vector3(8.912187, 18.0, 8.912187)

@onready var _player_mesh: MeshInstance3D = %PlayerMesh
@onready var _camera: Camera3D = %ArenaCamera
@onready var _enemy_instances: MultiMeshInstance3D = %EnemyInstances
@onready var _projectile_instances: MultiMeshInstance3D = %ProjectileInstances
@onready var _vfx_instances: MultiMeshInstance3D = %VfxInstances
@onready var _chest_instances: MultiMeshInstance3D = %ChestInstances
@onready var _combat_hud: CombatHud = %CombatHUD

var _simulation: CombatSimulation = null
var _simulation_paused: bool = false
var _smoothed_camera_target: Vector3 = Vector3.ZERO
var _camera_target_initialized: bool = false


func _ready() -> void:
	set_physics_process(_simulation != null)
	if _simulation != null:
		_apply_snapshot(_simulation.build_snapshot(), 0.0)


func initialize(simulation: CombatSimulation) -> void:
	_simulation = simulation
	_camera_target_initialized = false
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
		snapshot = _simulation.step(move_input, delta)
	_apply_snapshot(snapshot, delta)
	if _simulation.state.phase != previous_phase:
		phase_changed.emit(_simulation.state.phase)


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
	_copy_transform_prefix(snapshot.vfx_transforms, _vfx_instances)
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
