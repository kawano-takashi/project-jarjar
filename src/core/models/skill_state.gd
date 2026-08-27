class_name SkillState
extends RefCounted


var skill_id: StringName = &""
var level: int = 1
var equipped_slot: int = -1
var trigger_progress: float = 0.0
var pending_queue: Array[PendingSkillActivation] = []
