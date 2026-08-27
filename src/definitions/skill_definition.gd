class_name SkillDefinition
extends Resource


const Types := preload("res://src/core/game_types.gd")


@export var skill_id: StringName = &""
@export var trigger_type: Types.TriggerType = Types.TriggerType.TIME
@export var base_threshold: float = 0.0
@export var damage_by_level: PackedFloat32Array = PackedFloat32Array()
@export var radius_by_level: PackedFloat32Array = PackedFloat32Array()
@export var target_count_by_level: PackedInt32Array = PackedInt32Array()
