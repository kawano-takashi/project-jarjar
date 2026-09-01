class_name WeaponDefinition
extends Resource


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
@export var area_by_level: PackedFloat32Array = PackedFloat32Array()
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


func area_at(level: int) -> float:
	return _float_at(area_by_level, level)


func duration_ticks_at(level: int) -> int:
	return _int_at(duration_ticks_by_level, level)


func pierce_at(level: int) -> int:
	return _int_at(pierce_by_level, level)


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
