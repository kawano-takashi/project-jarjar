class_name UniqueDefinition
extends Resource


const Types := preload("res://src/core/game_types.gd")


@export var unique_id: StringName = &""
@export var display_name: String = ""
@export var equipment_slot: Types.EquipmentSlot = Types.EquipmentSlot.MAIN_WEAPON
