class_name CombatEvent
extends RefCounted


var event_serial: int = 0
var event_type: StringName = &""
var source_entity_id: int = -1
var source_effect_id: StringName = &""
var proc_effect_id: StringName = &""
var is_primary: bool = false
var effect_chain: PackedStringArray = PackedStringArray()
var chain_depth: int = 0
var damage_snapshot: float = 0.0
var position: Vector2 = Vector2.ZERO
var direction: Vector2 = Vector2.ZERO
