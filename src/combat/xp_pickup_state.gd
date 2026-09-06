class_name XpPickupState
extends RefCounted

signal visual_changed(pool_index: int)

var pool_index: int = -1
var generation: int = 0
var active: bool = false
var position: Vector2 = Vector2.ZERO:
	set(next_position):
		position = next_position
		visual_transform.origin = Vector3(position.x, 0.22, position.y)
		if active:
			visual_changed.emit(pool_index)
var value: int = 0:
	set(next_value):
		value = next_value
		var scale_factor: float = 1.0 + minf(1.0, log(float(maxi(1, value))) * 0.08)
		visual_transform.basis = Basis.IDENTITY.scaled(Vector3.ONE * scale_factor)
		if active:
			visual_changed.emit(pool_index)
var born_tick: int = 0
## Rendering data changes only when the pickup moves or absorbs more XP.
var visual_transform := Transform3D(Basis.IDENTITY, Vector3(0.0, 0.22, 0.0))


func activate(p_position: Vector2, p_value: int, p_born_tick: int) -> void:
	active = true
	position = p_position
	value = maxi(1, p_value)
	born_tick = p_born_tick


func deactivate() -> void:
	active = false
	position = Vector2.ZERO
	value = 0
	born_tick = 0
