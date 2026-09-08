class_name ArenaView
extends RefCounted

## Camera follow, projection and input mapping use the same tick-driven view.
## Face the arena squarely while keeping the elevated perspective.
const PITCH_DEGREES: float = 55.0
const YAW_DEGREES: float = 0.0
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
		if viewport_size == value or value.x <= 0 or value.y <= 0:
			return
		viewport_size = value
		projection = _create_projection(value)
		_ground_rects.clear()
var projection: Projection = _create_projection(viewport_size)
var camera_transform := Transform3D(Basis.looking_at(-CAMERA_OFFSET), CAMERA_OFFSET)
var _target := Vector3.ZERO
var _initialized: bool = false
var _ground_rects: Dictionary[float, Rect2] = {}


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


func shift_origin(displacement: Vector2) -> void:
	var offset := Vector3(displacement.x, 0.0, displacement.y)
	_target -= offset
	camera_transform.origin -= offset


## Ground-plane coverage of the fixed perspective camera. Cached in camera-relative
## coordinates; translating the camera never changes the shape of its footprint.
func ground_rect(height: float = 0.0) -> Rect2:
	if not _ground_rects.has(height):
		var minimum := Vector2(INF, INF)
		var maximum := Vector2(-INF, -INF)
		for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var ray: Vector3 = camera_transform.basis * Vector3(corner.x / projection.x.x, corner.y / projection.y.y, -1.0)
			var point: Vector3 = CAMERA_OFFSET + ray * ((height - CAMERA_OFFSET.y) / ray.y)
			var ground := Vector2(point.x, point.z)
			minimum = minimum.min(ground)
			maximum = maximum.max(ground)
		_ground_rects[height] = Rect2(minimum, maximum - minimum)
	var result: Rect2 = _ground_rects[height]
	result.position += Vector2(camera_transform.origin.x - CAMERA_OFFSET.x, camera_transform.origin.z - CAMERA_OFFSET.z)
	return result


## Conservative bounds contain every current body mesh, including its height.
func body_view_rect(body_radius: float) -> Rect2:
	return ground_rect().merge(ground_rect(body_radius * 2.0 + 1.0)).grow(body_radius + 0.05)


func is_body_visible(position: Vector2, body_radius: float) -> bool:
	return is_bounds_visible(AABB(
		Vector3(position.x - body_radius, 0.0, position.y - body_radius),
		Vector3(body_radius * 2.0, body_radius * 2.0 + 1.0, body_radius * 2.0),
	))


func is_bounds_visible(bounds: AABB) -> bool:
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for index: int in 8:
		var projected: Vector2 = project_position(bounds.get_endpoint(index))
		if not projected.is_finite():
			continue
		minimum = minimum.min(projected)
		maximum = maximum.max(projected)
	return minimum.is_finite() and Rect2(Vector2.ZERO, Vector2(viewport_size)).intersects(Rect2(minimum, maximum - minimum), true)


func sample_offscreen_position(rng: RandomNumberGenerator, band_width: float, body_radius: float) -> Vector2:
	var bounds: Rect2 = body_view_rect(body_radius).grow(rng.randf_range(0.0, band_width))
	var side: int = rng.randi_range(0, 3)
	var along: float = rng.randf()
	match side:
		0:
			return Vector2(lerpf(bounds.position.x, bounds.end.x, along), bounds.position.y)
		1:
			return Vector2(lerpf(bounds.position.x, bounds.end.x, along), bounds.end.y)
		2:
			return Vector2(bounds.position.x, lerpf(bounds.position.y, bounds.end.y, along))
		_:
			return Vector2(bounds.end.x, lerpf(bounds.position.y, bounds.end.y, along))


## Public on-screen guidance only: no hidden distance or target world position.
func edge_guidance(position: Vector2) -> Dictionary:
	var direction: Vector2 = (project_position(Vector3(position.x, 0.38, position.y)) - Vector2(viewport_size) * 0.5).normalized()
	if not direction.is_finite() or direction == Vector2.ZERO:
		var focus := Vector2(camera_transform.origin.x - CAMERA_OFFSET.x, camera_transform.origin.z - CAMERA_OFFSET.z)
		direction = world_to_screen_input(position - focus).normalized()
	var padding: float = minf(36.0, minf(viewport_size.x, viewport_size.y) * 0.1)
	# Keep the top and bottom HUD strips clear in both gameplay and headless views.
	var vertical_padding: float = minf(204.0, viewport_size.y * 0.3)
	var extent: Vector2 = Vector2(viewport_size) * 0.5 - Vector2(padding, vertical_padding)
	var distance: float = minf(extent.x / maxf(absf(direction.x), 0.000001), extent.y / maxf(absf(direction.y), 0.000001))
	return {"direction": direction, "screen_position": Vector2(viewport_size) * 0.5 + direction * distance}


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
