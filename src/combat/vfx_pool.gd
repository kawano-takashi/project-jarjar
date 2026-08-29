class_name VfxPool
extends RefCounted


const CAPACITY: int = 4096
const MELEE_TRAIL_SWEEP_SECONDS: float = 0.12
const MELEE_TRAIL_FADE_SECONDS: float = 0.06
const MELEE_TRAIL_LIFETIME_SECONDS: float = (
	MELEE_TRAIL_SWEEP_SECONDS + MELEE_TRAIL_FADE_SECONDS
)
const WOOD_STICK_ID: StringName = &"wood_stick"
const SWORD_ID: StringName = &"sword"
const WOOD_STICK_COLOR: Color = Color(1.0, 0.58, 0.15, 0.76)
const SWORD_COLOR: Color = Color(0.72, 0.93, 1.0, 0.80)
const ECHO_COLOR: Color = Color(0.77, 0.52, 1.0, 0.70)

var slots: Array[VfxState] = []
var overflow_count: int = 0
var reduce_motion: bool = false
var reduce_flashes: bool = false

var _next_melee_sweep_sign: float = 1.0


func _init() -> void:
	slots.resize(CAPACITY)
	for index: int in range(CAPACITY):
		var slot := VfxState.new()
		slot.pool_index = index
		slots[index] = slot


func acquire(
	position: Vector2,
	scale_m: float,
	lifetime: float,
	color: Color,
	born_physics_tick: int,
) -> VfxState:
	return _acquire_state(
		position,
		scale_m,
		lifetime,
		color,
		born_physics_tick,
		VfxState.EffectKind.GENERIC,
		Vector2.RIGHT,
		1.0,
	)


func acquire_melee_trail(
	weapon_id: StringName,
	position: Vector2,
	direction: Vector2,
	range_m: float,
	is_echo: bool,
	born_physics_tick: int,
) -> VfxState:
	var effect_kind: VfxState.EffectKind
	var color: Color
	match weapon_id:
		WOOD_STICK_ID:
			effect_kind = VfxState.EffectKind.WOOD_STICK_TRAIL
			color = WOOD_STICK_COLOR
		SWORD_ID:
			effect_kind = VfxState.EffectKind.SWORD_TRAIL
			color = SWORD_COLOR
		_:
			return null
	if is_echo:
		color = ECHO_COLOR
	var sweep_sign: float = _next_melee_sweep_sign
	_next_melee_sweep_sign = -_next_melee_sweep_sign
	return _acquire_state(
		position,
		range_m,
		MELEE_TRAIL_LIFETIME_SECONDS,
		color,
		born_physics_tick,
		effect_kind,
		direction,
		sweep_sign,
	)


func _acquire_state(
	position: Vector2,
	scale_m: float,
	lifetime: float,
	color: Color,
	born_physics_tick: int,
	effect_kind: VfxState.EffectKind,
	direction: Vector2,
	sweep_sign: float,
) -> VfxState:
	for slot: VfxState in slots:
		if slot.active:
			continue
		slot.generation += 1
		slot.activate(
			position,
			scale_m,
			lifetime,
			color,
			born_physics_tick,
			effect_kind,
			direction,
			sweep_sign,
		)
		return slot
	overflow_count += 1
	return null


func release(pool_index: int, generation: int = -1) -> bool:
	if pool_index < 0 or pool_index >= CAPACITY:
		return false
	var slot: VfxState = slots[pool_index]
	if not slot.active or (generation >= 0 and slot.generation != generation):
		return false
	slot.deactivate()
	return true


func advance(delta: float, current_tick: int) -> void:
	for slot: VfxState in slots:
		if not slot.active or slot.born_physics_tick >= current_tick:
			continue
		slot.remaining_lifetime = maxf(0.0, slot.remaining_lifetime - delta)
		if slot.remaining_lifetime <= 0.0:
			slot.deactivate()


func active_count() -> int:
	var count: int = 0
	for slot: VfxState in slots:
		if slot.active:
			count += 1
	return count


func clear() -> void:
	for slot: VfxState in slots:
		if slot.active:
			slot.deactivate()
	_next_melee_sweep_sign = 1.0
