class_name VfxState
extends RefCounted


enum EffectKind { GENERIC, ENERGY_WAVE, AURA_PULSE }


var pool_index: int = -1
var generation: int = 0
var active: bool = false
var position: Vector2 = Vector2.ZERO
var scale_m: float = 1.0
var direction: Vector2 = Vector2.RIGHT
var effect_kind: EffectKind = EffectKind.GENERIC
var sweep_sign: float = 1.0
var total_lifetime: float = 0.0
var remaining_lifetime: float = 0.0
var color: Color = Color.WHITE
var born_tick: int = 0


func activate(
	p_position: Vector2,
	p_scale_m: float,
	p_lifetime: float,
	p_color: Color,
	p_born_tick: int,
	p_effect_kind: EffectKind = EffectKind.GENERIC,
	p_direction: Vector2 = Vector2.RIGHT,
	p_sweep_sign: float = 1.0,
) -> void:
	active = true
	position = p_position
	scale_m = maxf(0.0001, p_scale_m)
	direction = p_direction.normalized()
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT
	effect_kind = p_effect_kind
	sweep_sign = 1.0 if p_sweep_sign >= 0.0 else -1.0
	total_lifetime = maxf(0.0, p_lifetime)
	remaining_lifetime = total_lifetime
	color = p_color
	born_tick = p_born_tick


func normalized_progress() -> float:
	if total_lifetime <= 0.0:
		return 1.0
	return clampf(1.0 - remaining_lifetime / total_lifetime, 0.0, 1.0)


func current_transform(height_m: float) -> Transform3D:
	var forward := Vector3(direction.x, 0.0, direction.y)
	var side := Vector3(direction.y, 0.0, -direction.x)
	var basis := Basis(
		side * scale_m * sweep_sign,
		Vector3.UP,
		forward * scale_m,
	)
	return Transform3D(basis, Vector3(position.x, height_m, position.y))


func shader_custom_data(reduce_motion: bool, reduce_flashes: bool) -> Color:
	return Color(
		normalized_progress(),
		float(effect_kind) / 2.0,
		1.0 if reduce_motion else 0.0,
		1.0 if reduce_flashes else 0.0,
	)


func deactivate() -> void:
	active = false
	position = Vector2.ZERO
	scale_m = 1.0
	direction = Vector2.RIGHT
	effect_kind = EffectKind.GENERIC
	sweep_sign = 1.0
	total_lifetime = 0.0
	remaining_lifetime = 0.0
	color = Color.WHITE
	born_tick = 0
