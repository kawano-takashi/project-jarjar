class_name ModalFocusCoordinator
extends RefCounted


var _viewport: Viewport = null
var _background_roots: Array[Control] = []
var _background_states: Array[Dictionary] = []
var _modal_stack: Array[Dictionary] = []


func configure(viewport: Viewport, background_roots: Array) -> void:
	if not _modal_stack.is_empty():
		push_error("ModalFocusCoordinator cannot be reconfigured while a modal is active.")
		return
	_viewport = viewport
	_background_roots.clear()
	for root_value: Variant in background_roots:
		var root := root_value as Control
		if root != null and not root in _background_roots:
			_background_roots.append(root)


func register_background(root: Control) -> void:
	if root == null or root in _background_roots:
		return
	_background_roots.append(root)
	if not _modal_stack.is_empty():
		var state: Dictionary = _capture_control_state(root)
		_background_states.append(state)
		_set_recursive_behavior(root, false)


func push(modal: Control, fallback_focus: Control = null) -> bool:
	if modal == null or not is_instance_valid(modal) or not modal.is_inside_tree():
		return false
	if _find_modal_index(modal) >= 0:
		return false
	if _modal_stack.is_empty():
		_capture_background_states()
	var restore_focus: Control = null
	if _viewport != null:
		restore_focus = _viewport.gui_get_focus_owner()
		_viewport.gui_release_focus()
	var state: Dictionary = _capture_control_state(modal)
	state["restore_focus"] = restore_focus
	state["fallback_focus"] = fallback_focus
	_modal_stack.append(state)
	modal.move_to_front()
	_apply_stack_state()
	return true


func pop(
	modal: Control,
	restore_override: Control = null,
	fallback_override: Control = null,
) -> bool:
	if _modal_stack.is_empty() or _control_from_state(_modal_stack.back()) != modal:
		return false
	if _viewport != null:
		_viewport.gui_release_focus()
	var state: Dictionary = _modal_stack.pop_back()
	_restore_control_state(state)
	if _modal_stack.is_empty():
		_restore_background_states()
	else:
		_apply_stack_state()
	var restore_focus: Control = restore_override
	if restore_focus == null:
		var restore_value: Variant = state.get("restore_focus")
		if restore_value != null and is_instance_valid(restore_value):
			restore_focus = restore_value as Control
	var fallback_focus: Control = fallback_override
	if fallback_focus == null:
		var fallback_value: Variant = state.get("fallback_focus")
		if fallback_value != null and is_instance_valid(fallback_value):
			fallback_focus = fallback_value as Control
	FocusController.grab_focus_safe(restore_focus, fallback_focus)
	return true


func set_restore_target(modal: Control, restore_focus: Control) -> bool:
	var index: int = _find_modal_index(modal)
	if index < 0:
		return false
	_modal_stack[index]["restore_focus"] = restore_focus
	return true


func has_active_modal() -> bool:
	return not _modal_stack.is_empty()


func active_modal() -> Control:
	if _modal_stack.is_empty():
		return null
	return _control_from_state(_modal_stack.back())


func is_active(modal: Control) -> bool:
	return active_modal() == modal


func stack_size() -> int:
	return _modal_stack.size()


func _capture_background_states() -> void:
	_background_states.clear()
	for root: Control in _background_roots:
		if root != null and is_instance_valid(root):
			_background_states.append(_capture_control_state(root))


func _restore_background_states() -> void:
	for state: Dictionary in _background_states:
		_restore_control_state(state)
	_background_states.clear()


func _apply_stack_state() -> void:
	for root: Control in _background_roots:
		_set_recursive_behavior(root, false)
	var top_index: int = _modal_stack.size() - 1
	for index: int in range(_modal_stack.size()):
		var modal: Control = _control_from_state(_modal_stack[index])
		if modal == null:
			continue
		var is_top: bool = index == top_index
		_set_recursive_behavior(modal, is_top)
		modal.set_process_input(is_top)
		modal.set_process_unhandled_input(is_top)
		if is_top:
			modal.mouse_filter = Control.MOUSE_FILTER_STOP
			modal.mouse_force_pass_scroll_events = false


func _set_recursive_behavior(control: Control, enabled: bool) -> void:
	if control == null or not is_instance_valid(control):
		return
	control.focus_behavior_recursive = (
		Control.FOCUS_BEHAVIOR_ENABLED
		if enabled
		else Control.FOCUS_BEHAVIOR_DISABLED
	)
	control.mouse_behavior_recursive = (
		Control.MOUSE_BEHAVIOR_ENABLED
		if enabled
		else Control.MOUSE_BEHAVIOR_DISABLED
	)


func _capture_control_state(control: Control) -> Dictionary:
	return {
		"control": control,
		"focus_behavior_recursive": control.focus_behavior_recursive,
		"mouse_behavior_recursive": control.mouse_behavior_recursive,
		"mouse_filter": control.mouse_filter,
		"mouse_force_pass_scroll_events": control.mouse_force_pass_scroll_events,
		"process_input": control.is_processing_input(),
		"process_unhandled_input": control.is_processing_unhandled_input(),
	}


func _restore_control_state(state: Dictionary) -> void:
	var control: Control = _control_from_state(state)
	if control == null:
		return
	control.set(
		"focus_behavior_recursive",
		state.get("focus_behavior_recursive", Control.FOCUS_BEHAVIOR_INHERITED),
	)
	control.set(
		"mouse_behavior_recursive",
		state.get("mouse_behavior_recursive", Control.MOUSE_BEHAVIOR_INHERITED),
	)
	control.set("mouse_filter", state.get("mouse_filter", Control.MOUSE_FILTER_STOP))
	control.mouse_force_pass_scroll_events = bool(
		state.get("mouse_force_pass_scroll_events", true)
	)
	control.set_process_input(bool(state.get("process_input", false)))
	control.set_process_unhandled_input(bool(state.get("process_unhandled_input", false)))


func _find_modal_index(modal: Control) -> int:
	for index: int in range(_modal_stack.size()):
		if _control_from_state(_modal_stack[index]) == modal:
			return index
	return -1


func _control_from_state(state: Dictionary) -> Control:
	var value: Variant = state.get("control")
	if value == null or not is_instance_valid(value):
		return null
	return value as Control
