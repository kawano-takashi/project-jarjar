class_name WeaponDefinition
extends Resource


const Types := preload("res://src/core/game_types.gd")


@export var weapon_id: StringName = &""
@export var main_weapon_type: Types.MainWeaponType = Types.MainWeaponType.UNCLASSIFIED
@export var base_damage: float = 0.0
@export var base_interval: float = 0.0
@export var range_m: float = 0.0
@export var projectile_speed: float = 0.0
@export var projectile_radius: float = 0.0
@export var aoe_radius: float = 0.0
@export var arc_degrees: float = 0.0
