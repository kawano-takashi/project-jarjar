class_name ChestVisual
extends RefCounted


const BOUNCE_SECONDS: float = 0.25
const BASE_HEIGHT: float = 0.24
const BOUNCE_HEIGHT: float = 0.90

var active: bool = false
var reward_id: String = ""
var origin: Vector2 = Vector2.ZERO
var acquired_tick: int = 0
var activation_serial: int = -1
var elapsed: float = 0.0


func activate(
	p_reward_id: String,
	p_origin: Vector2,
	p_acquired_tick: int,
	p_activation_serial: int,
) -> void:
	active = true
	reward_id = p_reward_id
	origin = p_origin
	acquired_tick = p_acquired_tick
	activation_serial = p_activation_serial
	elapsed = 0.0


func advance(delta: float) -> bool:
	if not active:
		return false
	elapsed = TimerMath.advance_clamped(elapsed, BOUNCE_SECONDS, maxf(0.0, delta))
	if TimerMath.is_ready(elapsed, BOUNCE_SECONDS):
		deactivate()
		return true
	return false


func deactivate() -> void:
	active = false
	reward_id = ""
	elapsed = 0.0


func current_transform() -> Transform3D:
	var progress: float = clampf(elapsed / BOUNCE_SECONDS, 0.0, 1.0)
	var height: float = BASE_HEIGHT + BOUNCE_HEIGHT * 4.0 * progress * (1.0 - progress)
	return Transform3D(
		Basis.IDENTITY,
		Vector3(origin.x, height, origin.y),
	)
