class_name ArenaView
extends RefCounted

## Camera follow, projection and input mapping use the same tick-driven view.
const CAMERA_OFFSET := Vector3(8.912187, 18.0, 8.912187)
const CAMERA_SIZE: float = CombatEnvelope.CAMERA_SIZE
const FOLLOW_TAU_SECONDS: float = CombatEnvelope.CAMERA_FOLLOW_TAU_SECONDS

var viewport_size := Vector2i(1920, 1080)
var camera_transform := Transform3D(Basis.looking_at(-CAMERA_OFFSET), CAMERA_OFFSET)
var _target := Vector3.ZERO
var _initialized: bool = false

func reset(player_position: Vector2) -> void:
	_initialized = false
	advance(player_position, 0.0)


func advance(player_position: Vector2, delta: float) -> void:
	var target := Vector3(player_position.x, 0.0, player_position.y)
	if not _initialized:
		_target = target
		_initialized = true
	elif delta > 0.0:
		_target = _target.lerp(target, 1.0 - exp(-delta / FOLLOW_TAU_SECONDS))
	camera_transform.origin = _target + CAMERA_OFFSET


func screen_to_world_input(screen_input: Vector2) -> Vector2:
	var right := Vector2(camera_transform.basis.x.x, camera_transform.basis.x.z).normalized()
	return right * screen_input.x + Vector2(-right.y, right.x) * screen_input.y


func world_to_screen_input(world_input: Vector2) -> Vector2:
	var right := Vector2(camera_transform.basis.x.x, camera_transform.basis.x.z).normalized()
	return Vector2(world_input.dot(right), world_input.dot(Vector2(-right.y, right.x)))


func project_position(world_position: Vector3) -> Vector2:
	var local: Vector3 = camera_transform.affine_inverse() * world_position
	var pixels_per_meter: float = float(viewport_size.y) / CAMERA_SIZE
	return Vector2(viewport_size) * 0.5 + Vector2(local.x, -local.y) * pixels_per_meter


static func ring_transform(position: Vector2, height: float, radius: float, progress: float, reduce_motion: bool = false) -> Transform3D:
	var pulse: float = 1.0 if reduce_motion else 0.92 + 0.08 * sin(clampf(progress, 0.0, 1.0) * TAU * 2.0)
	return Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * maxf(0.1, radius) * pulse), Vector3(position.x, height, position.y))


static func boss_spoke_transform(position: Vector2, radius: float, angle: float) -> Transform3D:
	var direction := Vector2.from_angle(angle)
	var forward := Vector3(direction.x, 0.0, direction.y)
	var side := Vector3(direction.y, 0.0, -direction.x)
	return Transform3D(
		Basis(side * 0.055, Vector3.UP * 0.025, forward * radius),
		Vector3(position.x + direction.x * radius * 0.5, 0.055, position.y + direction.y * radius * 0.5),
	)


static func swarm_arrow_transform(anchor: Vector2, direction: Vector2, index: int) -> Transform3D:
	var tangent := Vector2(-direction.y, direction.x)
	var side: float = -1.0 if index % 2 == 0 else 1.0
	var tip: Vector2 = anchor + direction * (float(floori(float(index) / 2.0)) - 1.0) * 2.5
	var wing: Vector2 = (direction + tangent * side).normalized()
	var center: Vector2 = tip - wing * 0.6
	return Transform3D(
		Basis(Vector3.UP, -wing.angle()).scaled_local(Vector3(1.2, 1.0, 0.10)),
		Vector3(center.x, 0.09, center.y),
	)
