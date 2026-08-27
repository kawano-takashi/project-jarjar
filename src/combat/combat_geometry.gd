class_name CombatGeometry
extends RefCounted


const EPSILON: float = 0.000001


static func circle_intersects(
	left_center: Vector2,
	left_radius: float,
	right_center: Vector2,
	right_radius: float,
) -> bool:
	var combined_radius: float = maxf(0.0, left_radius) + maxf(0.0, right_radius)
	return left_center.distance_squared_to(right_center) <= combined_radius * combined_radius


static func segment_circle_first_t(
	segment_start: Vector2,
	segment_end: Vector2,
	circle_center: Vector2,
	combined_radius: float,
) -> float:
	var delta: Vector2 = segment_end - segment_start
	var length_squared: float = delta.length_squared()
	var radius: float = maxf(0.0, combined_radius) + EPSILON
	if length_squared <= EPSILON:
		return 0.0 if segment_start.distance_squared_to(circle_center) <= radius * radius else -1.0
	var offset: Vector2 = segment_start - circle_center
	var a: float = length_squared
	var b: float = 2.0 * offset.dot(delta)
	var c: float = offset.length_squared() - radius * radius
	if c <= 0.0:
		return 0.0
	var discriminant: float = b * b - 4.0 * a * c
	if discriminant < -EPSILON:
		return -1.0
	var root: float = sqrt(maxf(0.0, discriminant))
	var first: float = (-b - root) / (2.0 * a)
	if first >= -EPSILON and first <= 1.0 + EPSILON:
		return clampf(first, 0.0, 1.0)
	var second: float = (-b + root) / (2.0 * a)
	if second >= -EPSILON and second <= 1.0 + EPSILON:
		return clampf(second, 0.0, 1.0)
	return -1.0


static func point_in_fan(
	origin: Vector2,
	forward: Vector2,
	range_m: float,
	arc_degrees: float,
	point: Vector2,
	point_radius: float,
) -> bool:
	var offset: Vector2 = point - origin
	var effective_range: float = maxf(0.0, range_m) + maxf(0.0, point_radius)
	if offset.length_squared() > effective_range * effective_range:
		return false
	if offset.length_squared() <= EPSILON:
		return true
	var normalized_forward: Vector2 = forward.normalized()
	if normalized_forward == Vector2.ZERO:
		return false
	var half_angle: float = deg_to_rad(maxf(0.0, arc_degrees) * 0.5)
	return normalized_forward.dot(offset.normalized()) >= cos(half_angle) - EPSILON
