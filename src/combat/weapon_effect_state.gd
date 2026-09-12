class_name WeaponEffectState
extends RefCounted

## One actual attack shape. Radius is metres, angle is degrees, time is 60 Hz ticks.
var position: Vector2
var direction: Vector2
var radius_m: float
var arc_degrees: float
var visual_kind: int
var evolved: bool
var born_tick: int
var duration_ticks: int


func _init(shape: Dictionary, kind: int, is_evolved: bool, tick: int, lifetime_ticks: int) -> void:
	position = shape["center"]
	direction = shape.get("direction", Vector2.RIGHT)
	if direction.is_zero_approx():
		direction = Vector2.RIGHT
	direction = direction.normalized()
	radius_m = shape["radius"]
	arc_degrees = shape.get("arc_degrees", 360.0)
	visual_kind = kind
	evolved = is_evolved
	born_tick = tick
	duration_ticks = lifetime_ticks


func transform() -> Transform3D:
	return Transform3D(Basis(
		Vector3(direction.y, 0.0, -direction.x) * radius_m,
		Vector3.UP,
		Vector3(direction.x, 0.0, direction.y) * radius_m,
	), Vector3(position.x, WeaponVisualStyle.GROUND_HEIGHT_M, position.y))


func custom_data(tick: int) -> Color:
	return Color(
		clampf(float(tick - born_tick) / float(duration_ticks), 0.0, 1.0),
		float(visual_kind), arc_degrees / 360.0, 1.0 if evolved else 0.0,
	)
