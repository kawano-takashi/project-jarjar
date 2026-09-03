class_name SwarmEventDefinition
extends Resource


@export var event_id: StringName = &""
@export var unit_definition: EnemyDefinition = null
@export var member_count: int = 0
@export var lateral_count: int = 0
@export var depth_count: int = 0
@export var lateral_pitch: float = 0.0
@export var depth_pitch: float = 0.0
@export var schedules: Array[SwarmEventScheduleDefinition] = []
