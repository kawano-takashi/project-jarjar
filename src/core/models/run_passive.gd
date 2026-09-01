class_name RunPassive
extends RefCounted


var passive_id: StringName = &""
var level: int = 1


static func create(p_passive_id: StringName) -> RunPassive:
	var runtime := RunPassive.new()
	runtime.passive_id = p_passive_id
	return runtime
