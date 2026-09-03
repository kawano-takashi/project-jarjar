class_name SwarmEventScheduleDefinition
extends Resource


@export var schedule_id: StringName = &""
@export var first_tick: int = 0
@export var interval_ticks: int = 0
@export var attempt_count: int = 0
@export_range(0.0, 1.0, 0.01) var spawn_chance: float = 0.0
