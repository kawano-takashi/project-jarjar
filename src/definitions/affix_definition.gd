class_name AffixDefinition
extends Resource


const Types := preload("res://src/core/game_types.gd")


@export var affix_id: StringName = &""
@export var values_by_rarity: PackedFloat32Array = PackedFloat32Array()
@export var slot_pool: Array[Types.EquipmentSlot] = []
@export var in_common_pool: bool = false
@export var affinity_weapon_types: Array[Types.MainWeaponType] = []
