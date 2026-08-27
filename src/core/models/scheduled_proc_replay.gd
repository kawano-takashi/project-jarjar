class_name ScheduledProcReplay
extends RefCounted


var due_physics_tick: int = 0
var schedule_serial: int = 0
var source_effect_id: StringName = &""
var proc_effect_id: StringName = &""
var inherited_effect_chain: PackedStringArray = PackedStringArray()
var damage_snapshot: float = 0.0
var direction: Vector2 = Vector2.ZERO
var aim_distance: float = 0.0
var target_entity_id: int = -1
