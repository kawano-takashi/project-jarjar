class_name FocusController
extends RefCounted


const DIRECTION_TOP: StringName = &"top"
const DIRECTION_BOTTOM: StringName = &"bottom"
const DIRECTION_LEFT: StringName = &"left"
const DIRECTION_RIGHT: StringName = &"right"
const DIRECTIONS: Array[StringName] = [
	DIRECTION_TOP,
	DIRECTION_BOTTOM,
	DIRECTION_LEFT,
	DIRECTION_RIGHT,
]

var _controls: Dictionary[String, Control] = {}
var _neighbors: Dictionary[String, Dictionary] = {}
var _modal_allowed: Dictionary[String, bool] = {}
var _initial_focus_id: String = ""
var _saved_focus_id: String = ""


static func configure_vertical_cycle(controls: Array) -> void:
	if controls.is_empty():
		return
	for index in controls.size():
		var control: Control = controls[index]
		var previous: Control = controls[(index - 1 + controls.size()) % controls.size()]
		var next: Control = controls[(index + 1) % controls.size()]
		control.focus_mode = Control.FOCUS_ALL
		control.focus_neighbor_top = control.get_path_to(previous)
		control.focus_neighbor_bottom = control.get_path_to(next)
		control.focus_neighbor_left = control.get_path_to(control)
		control.focus_neighbor_right = control.get_path_to(control)


static func configure_horizontal_cycle(controls: Array) -> void:
	if controls.is_empty():
		return
	for index in controls.size():
		var control: Control = controls[index]
		var previous: Control = controls[(index - 1 + controls.size()) % controls.size()]
		var next: Control = controls[(index + 1) % controls.size()]
		control.focus_mode = Control.FOCUS_ALL
		control.focus_neighbor_top = control.get_path_to(control)
		control.focus_neighbor_bottom = control.get_path_to(control)
		control.focus_neighbor_left = control.get_path_to(previous)
		control.focus_neighbor_right = control.get_path_to(next)


func clear() -> void:
	_controls.clear()
	_neighbors.clear()
	_modal_allowed.clear()
	_initial_focus_id = ""
	_saved_focus_id = ""


func configure_graph(
	controls: Dictionary,
	neighbors: Dictionary,
	p_initial_focus_id: String,
) -> void:
	clear()
	for focus_id_value: Variant in controls:
		var focus_id := str(focus_id_value)
		var control := controls[focus_id_value] as Control
		if focus_id.is_empty() or control == null:
			continue
		register_control(focus_id, control)
	for focus_id_value: Variant in neighbors:
		var focus_id := str(focus_id_value)
		var specification := neighbors[focus_id_value] as Dictionary
		set_neighbors(
			focus_id,
			str(specification.get(DIRECTION_TOP, focus_id)),
			str(specification.get(DIRECTION_BOTTOM, focus_id)),
			str(specification.get(DIRECTION_LEFT, focus_id)),
			str(specification.get(DIRECTION_RIGHT, focus_id)),
		)
	_initial_focus_id = p_initial_focus_id if _controls.has(p_initial_focus_id) else ""
	_apply_neighbor_paths()


func register_control(focus_id: String, control: Control) -> void:
	if focus_id.is_empty() or control == null:
		return
	_controls[focus_id] = control
	control.set_meta("focus_id", focus_id)
	control.focus_mode = Control.FOCUS_ALL
	if not _neighbors.has(focus_id):
		_neighbors[focus_id] = _self_neighbors(focus_id)


func unregister_control(focus_id: String) -> void:
	_controls.erase(focus_id)
	_neighbors.erase(focus_id)
	_modal_allowed.erase(focus_id)
	if _initial_focus_id == focus_id:
		_initial_focus_id = ""
	if _saved_focus_id == focus_id:
		_saved_focus_id = ""


func set_neighbors(
	focus_id: String,
	top: String,
	bottom: String,
	left: String,
	right: String,
) -> void:
	if focus_id.is_empty():
		return
	_neighbors[focus_id] = {
		DIRECTION_TOP: top,
		DIRECTION_BOTTOM: bottom,
		DIRECTION_LEFT: left,
		DIRECTION_RIGHT: right,
	}


func refresh_neighbor_paths() -> void:
	_apply_neighbor_paths()


func set_initial_focus_id(focus_id: String) -> void:
	_initial_focus_id = focus_id if _controls.has(focus_id) else ""


func initial_focus_id() -> String:
	return _initial_focus_id


func focus_initial_deferred() -> void:
	var focus_id: String = _first_focusable_from(_initial_focus_id)
	var control: Control = control_for_id(focus_id)
	if control != null:
		control.call_deferred("grab_focus")


func current_focus_id(viewport: Viewport) -> String:
	if viewport == null:
		return ""
	var focused: Control = viewport.gui_get_focus_owner()
	if focused == null:
		return ""
	return str(focused.get_meta("focus_id", ""))


func save_current_focus(viewport: Viewport) -> String:
	_saved_focus_id = current_focus_id(viewport)
	return _saved_focus_id


func save_focus_id(focus_id: String) -> void:
	_saved_focus_id = focus_id


func saved_focus_id() -> String:
	return _saved_focus_id


func restore_saved_focus(fallback_id: String = "") -> bool:
	var target_id: String = _saved_focus_id
	if not is_focusable_id(target_id):
		target_id = fallback_id if not fallback_id.is_empty() else _initial_focus_id
	return grab_focus_id(target_id)


func grab_focus_id(focus_id: String) -> bool:
	if not is_focusable_id(focus_id):
		return false
	var control: Control = control_for_id(focus_id)
	if control == null:
		return false
	control.grab_focus()
	return true


func move(viewport: Viewport, direction: StringName) -> bool:
	if not direction in DIRECTIONS:
		return false
	var origin_id: String = current_focus_id(viewport)
	if origin_id.is_empty() or not _controls.has(origin_id):
		return grab_focus_id(_first_focusable_from(_initial_focus_id))
	var target_id: String = resolve_neighbor(origin_id, direction)
	if target_id.is_empty():
		return false
	return grab_focus_id(target_id)


func resolve_neighbor(origin_id: String, direction: StringName) -> String:
	if not _controls.has(origin_id) or not direction in DIRECTIONS:
		return ""
	var candidate_id: String = _neighbor_id(origin_id, direction)
	var visited: Dictionary[String, bool] = {origin_id: true}
	for _step: int in range(maxi(1, _controls.size())):
		if candidate_id.is_empty() or visited.has(candidate_id):
			break
		if is_focusable_id(candidate_id):
			return candidate_id
		visited[candidate_id] = true
		candidate_id = _neighbor_id(candidate_id, direction)
	return origin_id if is_focusable_id(origin_id) else _first_focusable_from(_initial_focus_id)


func control_for_id(focus_id: String) -> Control:
	return _controls.get(focus_id) as Control


func focus_ids() -> PackedStringArray:
	var result := PackedStringArray()
	for focus_id: String in _controls:
		result.append(focus_id)
	return result


func neighbor_specification(focus_id: String) -> Dictionary:
	return (_neighbors.get(focus_id, {}) as Dictionary).duplicate()


func is_focusable_id(focus_id: String) -> bool:
	if focus_id.is_empty() or not _controls.has(focus_id):
		return false
	if not _modal_allowed.is_empty() and not _modal_allowed.has(focus_id):
		return false
	var control: Control = control_for_id(focus_id)
	if control == null or not is_instance_valid(control):
		return false
	if not control.visible or (control.is_inside_tree() and not control.is_visible_in_tree()):
		return false
	if control.focus_mode == Control.FOCUS_NONE:
		return false
	if bool(control.get_meta("focus_disabled", false)):
		return false
	if control is BaseButton and (control as BaseButton).disabled:
		return false
	return true


func set_modal_allowed(p_focus_ids: PackedStringArray) -> void:
	_modal_allowed.clear()
	for focus_id: String in p_focus_ids:
		if _controls.has(focus_id):
			_modal_allowed[focus_id] = true


func clear_modal_allowed() -> void:
	_modal_allowed.clear()


func modal_allowed_ids() -> PackedStringArray:
	var result := PackedStringArray()
	for focus_id: String in _modal_allowed:
		result.append(focus_id)
	return result


func _apply_neighbor_paths() -> void:
	for focus_id: String in _controls:
		var control: Control = control_for_id(focus_id)
		if control == null:
			continue
		var specification: Dictionary = _neighbors.get(
			focus_id,
			_self_neighbors(focus_id),
		) as Dictionary
		_set_neighbor_path(control, "focus_neighbor_top", str(specification[DIRECTION_TOP]))
		_set_neighbor_path(control, "focus_neighbor_bottom", str(specification[DIRECTION_BOTTOM]))
		_set_neighbor_path(control, "focus_neighbor_left", str(specification[DIRECTION_LEFT]))
		_set_neighbor_path(control, "focus_neighbor_right", str(specification[DIRECTION_RIGHT]))


func _set_neighbor_path(control: Control, property_name: String, target_id: String) -> void:
	var target: Control = control_for_id(target_id)
	if target == null:
		target = control
	control.set(property_name, control.get_path_to(target))


func _neighbor_id(focus_id: String, direction: StringName) -> String:
	var specification: Dictionary = _neighbors.get(
		focus_id,
		_self_neighbors(focus_id),
	) as Dictionary
	return str(specification.get(direction, focus_id))


func _first_focusable_from(preferred_id: String) -> String:
	if is_focusable_id(preferred_id):
		return preferred_id
	for focus_id: String in _controls:
		if is_focusable_id(focus_id):
			return focus_id
	return ""


func _self_neighbors(focus_id: String) -> Dictionary:
	return {
		DIRECTION_TOP: focus_id,
		DIRECTION_BOTTOM: focus_id,
		DIRECTION_LEFT: focus_id,
		DIRECTION_RIGHT: focus_id,
	}
