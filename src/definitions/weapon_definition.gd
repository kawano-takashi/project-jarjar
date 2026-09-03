class_name WeaponDefinition
extends Resource


const STAT_DAMAGE: StringName = &"damage"
const STAT_COOLDOWN_TICKS: StringName = &"cooldown_ticks"
const STAT_AMOUNT: StringName = &"amount"
const STAT_PROJECTILE_SPEED: StringName = &"projectile_speed"
const STAT_RANGE: StringName = &"range"
const STAT_PROJECTILE_RADIUS: StringName = &"projectile_radius"
const STAT_EFFECT_RADIUS: StringName = &"effect_radius"
const STAT_DURATION_TICKS: StringName = &"duration_ticks"
const STAT_PIERCE: StringName = &"pierce"


class WeaponLevelDelta:
	extends RefCounted

	var stat_id: StringName = &""
	var previous_value: float = 0.0
	var new_value: float = 0.0

	func _init(
		p_stat_id: StringName,
		p_previous_value: float,
		p_new_value: float,
	) -> void:
		stat_id = p_stat_id
		previous_value = p_previous_value
		new_value = p_new_value


@export var weapon_id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var lineage_id: StringName = &""
@export var behavior: GameTypes.WeaponBehavior = GameTypes.WeaponBehavior.MELEE_WAVE
@export var is_evolved: bool = false
@export var max_level: int = 0
@export var selection_weight: float = 0.0
@export var paired_passive_id: StringName = &""
@export var damage_by_level: PackedFloat32Array = PackedFloat32Array()
@export var cooldown_ticks_by_level: PackedInt32Array = PackedInt32Array()
@export var amount_by_level: PackedInt32Array = PackedInt32Array()
@export var projectile_speed_by_level: PackedFloat32Array = PackedFloat32Array()
@export var range_by_level: PackedFloat32Array = PackedFloat32Array()
@export var projectile_radius_by_level: PackedFloat32Array = PackedFloat32Array()
@export var effect_radius_by_level: PackedFloat32Array = PackedFloat32Array()
@export var range_scales_with_area: bool = false
@export var projectile_radius_scales_with_area: bool = false
@export var effect_radius_scales_with_area: bool = false
@export var duration_ticks_by_level: PackedInt32Array = PackedInt32Array()
@export var pierce_by_level: PackedInt32Array = PackedInt32Array()
@export var critical_chance: float = 0.0
@export var critical_multiplier: float = 1.0
@export var life_steal_ratio: float = 0.0


func damage_at(level: int) -> float:
	return _float_at(damage_by_level, level)


func cooldown_ticks_at(level: int) -> int:
	return _int_at(cooldown_ticks_by_level, level)


func amount_at(level: int) -> int:
	return _int_at(amount_by_level, level)


func projectile_speed_at(level: int) -> float:
	return _float_at(projectile_speed_by_level, level)


func range_at(level: int) -> float:
	return _float_at(range_by_level, level)


func projectile_radius_at(level: int) -> float:
	return _float_at(projectile_radius_by_level, level)


func effect_radius_at(level: int) -> float:
	return _float_at(effect_radius_by_level, level)


func effective_range_at(level: int, area_multiplier: float) -> float:
	return range_at(level) * _area_scale(area_multiplier, range_scales_with_area)


func effective_projectile_radius_at(level: int, area_multiplier: float) -> float:
	return (
		projectile_radius_at(level)
		* _area_scale(area_multiplier, projectile_radius_scales_with_area)
	)


func effective_effect_radius_at(level: int, area_multiplier: float) -> float:
	return (
		effect_radius_at(level)
		* _area_scale(area_multiplier, effect_radius_scales_with_area)
	)


func duration_ticks_at(level: int) -> int:
	return _int_at(duration_ticks_by_level, level)


func pierce_at(level: int) -> int:
	return _int_at(pierce_by_level, level)


func level_deltas(next_level: int) -> Array[WeaponLevelDelta]:
	var result: Array[WeaponLevelDelta] = []
	if next_level < 2 or next_level > max_level:
		return result
	var previous_level: int = next_level - 1
	_append_float_delta(
		result,
		STAT_DAMAGE,
		damage_at(previous_level),
		damage_at(next_level),
	)
	_append_int_delta(
		result,
		STAT_COOLDOWN_TICKS,
		cooldown_ticks_at(previous_level),
		cooldown_ticks_at(next_level),
	)
	_append_int_delta(
		result,
		STAT_AMOUNT,
		amount_at(previous_level),
		amount_at(next_level),
	)
	_append_float_delta(
		result,
		STAT_PROJECTILE_SPEED,
		projectile_speed_at(previous_level),
		projectile_speed_at(next_level),
	)
	_append_float_delta(
		result,
		STAT_RANGE,
		range_at(previous_level),
		range_at(next_level),
	)
	_append_float_delta(
		result,
		STAT_PROJECTILE_RADIUS,
		projectile_radius_at(previous_level),
		projectile_radius_at(next_level),
	)
	_append_float_delta(
		result,
		STAT_EFFECT_RADIUS,
		effect_radius_at(previous_level),
		effect_radius_at(next_level),
	)
	_append_int_delta(
		result,
		STAT_DURATION_TICKS,
		duration_ticks_at(previous_level),
		duration_ticks_at(next_level),
	)
	_append_int_delta(
		result,
		STAT_PIERCE,
		pierce_at(previous_level),
		pierce_at(next_level),
	)
	return result


func _append_float_delta(
	result: Array[WeaponLevelDelta],
	stat_id: StringName,
	previous_value: float,
	new_value: float,
) -> void:
	if not is_equal_approx(previous_value, new_value):
		result.append(WeaponLevelDelta.new(stat_id, previous_value, new_value))


func _append_int_delta(
	result: Array[WeaponLevelDelta],
	stat_id: StringName,
	previous_value: int,
	new_value: int,
) -> void:
	if previous_value != new_value:
		result.append(WeaponLevelDelta.new(stat_id, previous_value, new_value))


func _float_at(values: PackedFloat32Array, level: int) -> float:
	if values.is_empty():
		return 0.0
	var index: int = clampi(level - 1, 0, values.size() - 1)
	return values[index]


func _int_at(values: PackedInt32Array, level: int) -> int:
	if values.is_empty():
		return 0
	var index: int = clampi(level - 1, 0, values.size() - 1)
	return values[index]


func _area_scale(area_multiplier: float, enabled: bool) -> float:
	return maxf(0.0, area_multiplier) if enabled else 1.0
