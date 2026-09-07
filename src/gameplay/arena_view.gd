class_name ArenaView
extends RefCounted

## Camera follow, projection and input mapping use the same tick-driven view.
## Funguys Swarm-inspired view, selected by comparing rendered scenes.
const PITCH_DEGREES: float = 55.0
const YAW_DEGREES: float = 45.0
## Metres from the ground focus. Includes the ten-metre combat envelope and
## movement follow lag at 60 Hz, rounded up to the next tenth of a metre.
const DISTANCE_METERS: float = 71.1
const CAMERA_OFFSET := Vector3(
	sin(deg_to_rad(YAW_DEGREES)) * cos(deg_to_rad(PITCH_DEGREES)),
	sin(deg_to_rad(PITCH_DEGREES)),
	cos(deg_to_rad(YAW_DEGREES)) * cos(deg_to_rad(PITCH_DEGREES)),
) * DISTANCE_METERS
## Vertical field of view in degrees; wider windows gain horizontal coverage.
const VERTICAL_FOV_DEGREES: float = 15.0
const NEAR_METERS: float = 0.1
const FAR_METERS: float = 120.0
const FOLLOW_TAU_SECONDS: float = 0.12

var viewport_size := Vector2i(1920, 1080):
	set(value):
		if viewport_size == value:
			return
		viewport_size = value
		projection = _create_projection(value)
var projection: Projection = _create_projection(viewport_size)
var camera_transform := Transform3D(Basis.looking_at(-CAMERA_OFFSET), CAMERA_OFFSET)
var _target := Vector3.ZERO
var _initialized: bool = false


func configure_camera(camera: Camera3D) -> void:
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.set_perspective(VERTICAL_FOV_DEGREES, NEAR_METERS, FAR_METERS)
	camera.transform = camera_transform


static func _create_projection(dimensions: Vector2i) -> Projection:
	return Projection.create_perspective(
		VERTICAL_FOV_DEGREES, float(dimensions.x) / float(dimensions.y),
		NEAR_METERS, FAR_METERS,
	)


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
	# Camera3D removes scale and subtracts the origin before rotating. Match
	# that order to avoid cancellation for points close to a distant camera.
	var local: Vector3 = world_position * camera_transform.orthonormalized()
	var clip: Vector4 = projection * Vector4(local.x, local.y, local.z, 1.0)
	if clip.w <= 0.0:
		return Vector2(INF, INF)
	return (Vector2(clip.x, -clip.y) / clip.w + Vector2.ONE) * Vector2(viewport_size) * 0.5


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
