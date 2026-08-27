class_name BootstrapFlow
extends RefCounted


const BOOT: StringName = &"BOOT"
const TITLE: StringName = &"TITLE"

var current_state: StringName = BOOT


func transition_to_title() -> bool:
	if current_state != BOOT:
		return false
	current_state = TITLE
	return true
