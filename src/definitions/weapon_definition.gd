class_name WeaponDefinition
extends Resource


const Types := preload("res://src/core/game_types.gd")


@export var weapon_id: StringName = &""
@export var weapon_type: Types.WeaponType = Types.WeaponType.NONE
@export var lootable: bool = true
@export var damage_by_rarity: PackedFloat32Array = PackedFloat32Array()
@export var base_interval: float = 0.0
@export var range_m: float = 0.0
@export var projectile_speed: float = 0.0
@export var projectile_radius: float = 0.0
@export var aoe_radius: float = 0.0
@export var arc_degrees: float = 0.0


func damage_for_rarity(rarity: Types.Rarity) -> float:
	var index: int = int(rarity)
	if index < 0 or index >= damage_by_rarity.size():
		return 0.0
	return damage_by_rarity[index]
