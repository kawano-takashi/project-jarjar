class_name InventoryItemTooltip
extends Control


const HOVER_DELAY_SECONDS: float = 0.20
const TARGET_GAP: float = 12.0
const VIEWPORT_MARGIN: float = 16.0
const MINIMUM_TOOLTIP_WIDTH: float = 480.0
const JOYPAD_INPUT_THRESHOLD: float = 0.5

enum InputMode {
	NONE,
	POINTER,
	FOCUS,
}

@onready var _panel: PanelContainer = %TooltipPanel
@onready var _details_label: Label = %TooltipDetails
@onready var _warning_label: Label = %TooltipWarning
@onready var _hover_timer: Timer = %HoverTimer

var _active: bool = false
var _input_mode: InputMode = InputMode.NONE
var _bindings: Dictionary = {}
var _hovered_target: InventoryCardButton = null
var _focused_target: InventoryCardButton = null
var _pending_target: InventoryCardButton = null
var _displayed_target: InventoryCardButton = null
var _displayed_anchor_rect := Rect2()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false
	_warning_label.visible = false
	_warning_label.accessibility_live = AccessibilityServer.LIVE_POLITE
	_hover_timer.wait_time = HOVER_DELAY_SECONDS
	_hover_timer.one_shot = true
	_hover_timer.ignore_time_scale = true
	_hover_timer.timeout.connect(_on_hover_timeout)
	_panel.resized.connect(_on_panel_resized)
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	set_process_input(false)


func begin_session() -> void:
	_active = true
	_input_mode = InputMode.NONE
	_hovered_target = null
	_focused_target = null
	hide_tooltip(false)
	set_process_input(true)


func end_session() -> void:
	_active = false
	set_process_input(false)
	_input_mode = InputMode.NONE
	_hovered_target = null
	_focused_target = null
	hide_tooltip(false)


func bind_target(target: InventoryCardButton, payload_provider: Callable) -> void:
	if target == null or not is_instance_valid(target) or not payload_provider.is_valid():
		return
	var instance_id: int = target.get_instance_id()
	if _bindings.has(instance_id):
		unbind_target(target)
	var mouse_entered_callback: Callable = _on_target_mouse_entered.bind(target)
	var mouse_exited_callback: Callable = _on_target_mouse_exited.bind(target)
	var focus_entered_callback: Callable = _on_target_focus_entered.bind(target)
	var focus_exited_callback: Callable = _on_target_focus_exited.bind(target)
	var tree_exiting_callback: Callable = _on_target_tree_exiting.bind(instance_id)
	_bindings[instance_id] = {
		"target": target,
		"provider": payload_provider,
		"mouse_entered": mouse_entered_callback,
		"mouse_exited": mouse_exited_callback,
		"focus_entered": focus_entered_callback,
		"focus_exited": focus_exited_callback,
		"tree_exiting": tree_exiting_callback,
	}
	target.mouse_entered.connect(mouse_entered_callback)
	target.mouse_exited.connect(mouse_exited_callback)
	target.focus_entered.connect(focus_entered_callback)
	target.focus_exited.connect(focus_exited_callback)
	target.tree_exiting.connect(tree_exiting_callback)
	target.set_managed_tooltip(true)


func unbind_target(target: InventoryCardButton) -> void:
	if target == null:
		return
	_remove_binding(target.get_instance_id(), true)


func clear_targets() -> void:
	var instance_ids: Array[int] = []
	for instance_id_value: Variant in _bindings:
		instance_ids.append(int(instance_id_value))
	for instance_id: int in instance_ids:
		_remove_binding(instance_id, true)


func activate_focus_input() -> void:
	if not _active:
		return
	_input_mode = InputMode.FOCUS
	_hover_timer.stop()
	_pending_target = null
	_show_current_focused_target.call_deferred()


func activate_pointer_input() -> void:
	if not _active:
		return
	_input_mode = InputMode.POINTER
	if _valid_bound_target(_hovered_target):
		if _displayed_target == _hovered_target:
			refresh_active()
		elif _pending_target != _hovered_target:
			_request_hover(_hovered_target)
		else:
			var pending_payload: Dictionary = _payload_for(_hovered_target)
			if bool(pending_payload.get("urgent", false)):
				_show_target(_hovered_target, pending_payload)
	else:
		hide_tooltip(false)


func refresh_active() -> void:
	if not _active:
		return
	if _valid_bound_target(_displayed_target):
		_show_target(_displayed_target)
	elif _valid_bound_target(_pending_target):
		var payload: Dictionary = _payload_for(_pending_target)
		if bool(payload.get("urgent", false)):
			_show_target(_pending_target, payload)


func hide_tooltip(reset_input_mode: bool = false) -> void:
	_hover_timer.stop()
	_pending_target = null
	_displayed_target = null
	_displayed_anchor_rect = Rect2()
	if is_instance_valid(_panel):
		_panel.visible = false
	if is_instance_valid(_warning_label):
		_warning_label.visible = false
		_warning_label.text = ""
	if reset_input_mode:
		_input_mode = InputMode.NONE
		_hovered_target = null
		_focused_target = null


func debug_snapshot() -> Dictionary:
	return {
		"visible": _panel.visible,
		"input_mode": _input_mode_name(),
		"target_focus_id": (
			str(_displayed_target.get_meta("focus_id", ""))
			if _valid_bound_target(_displayed_target)
			else ""
		),
		"pending_focus_id": (
			str(_pending_target.get_meta("focus_id", ""))
			if _valid_bound_target(_pending_target)
			else ""
		),
		"details": _details_label.text if _panel.visible else "",
		"warning": _warning_label.text if _warning_label.visible else "",
		"panel_rect": _panel.get_global_rect() if _panel.visible else Rect2(),
		"anchor_rect": _displayed_anchor_rect,
		"warning_accessibility_live": _warning_label.accessibility_live,
		"bound_target_count": _bindings.size(),
	}


func _input(event: InputEvent) -> void:
	if not _active:
		return
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		activate_pointer_input()
	elif _is_focus_input(event):
		activate_focus_input()


func _is_focus_input(event: InputEvent) -> bool:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		return key_event.pressed and not key_event.echo
	if event is InputEventJoypadButton:
		return (event as InputEventJoypadButton).pressed
	if event is InputEventJoypadMotion:
		return absf((event as InputEventJoypadMotion).axis_value) >= JOYPAD_INPUT_THRESHOLD
	return false


func _on_target_mouse_entered(target: InventoryCardButton) -> void:
	if not _active or not _valid_bound_target(target):
		return
	_hovered_target = target
	if _input_mode == InputMode.POINTER:
		_request_hover(target)


func _on_target_mouse_exited(target: InventoryCardButton) -> void:
	if _hovered_target == target:
		_hovered_target = null
	if _pending_target == target:
		_hover_timer.stop()
		_pending_target = null
	if _input_mode == InputMode.POINTER and _displayed_target == target:
		hide_tooltip(false)


func _on_target_focus_entered(target: InventoryCardButton) -> void:
	if not _active or not _valid_bound_target(target):
		return
	_focused_target = target
	if _input_mode == InputMode.FOCUS:
		_show_target(target)


func _on_target_focus_exited(target: InventoryCardButton) -> void:
	if _focused_target == target:
		_focused_target = null
	if _input_mode == InputMode.FOCUS and _displayed_target == target:
		hide_tooltip(false)


func _on_target_tree_exiting(instance_id: int) -> void:
	_remove_binding(instance_id, false)


func _request_hover(target: InventoryCardButton) -> void:
	var payload: Dictionary = _payload_for(target)
	if payload.is_empty():
		hide_tooltip(false)
		return
	_pending_target = target
	if bool(payload.get("urgent", false)):
		_hover_timer.stop()
		_show_target(target, payload)
	else:
		_hover_timer.start(HOVER_DELAY_SECONDS)


func _on_hover_timeout() -> void:
	if (
		_input_mode != InputMode.POINTER
		or _pending_target == null
		or _pending_target != _hovered_target
	):
		return
	_show_target(_pending_target)


func _show_current_focused_target() -> void:
	if not _active or _input_mode != InputMode.FOCUS:
		return
	var focused: Control = get_viewport().gui_get_focus_owner()
	var target := focused as InventoryCardButton
	if _valid_bound_target(target):
		_focused_target = target
		_show_target(target)
	else:
		_focused_target = null
		hide_tooltip(false)


func _show_target(target: InventoryCardButton, payload_override: Dictionary = {}) -> void:
	if not _active or not _valid_bound_target(target):
		hide_tooltip(false)
		return
	var payload: Dictionary = (
		payload_override
		if not payload_override.is_empty()
		else _payload_for(target)
	)
	var details: String = str(payload.get("details", ""))
	if details.is_empty():
		hide_tooltip(false)
		return
	_hover_timer.stop()
	_pending_target = null
	_displayed_target = target
	_details_label.text = details
	var warning: String = str(payload.get("warning", ""))
	_warning_label.text = warning
	_warning_label.visible = not warning.is_empty()
	_fit_panel_to_content()
	_displayed_anchor_rect = target.get_global_rect()
	_panel.position = _position_for_target(_displayed_anchor_rect, _panel.size)
	_panel.visible = true
	_reposition_displayed.call_deferred()


func _payload_for(target: InventoryCardButton) -> Dictionary:
	if not _valid_bound_target(target):
		return {}
	var binding: Dictionary = _bindings.get(target.get_instance_id(), {}) as Dictionary
	var provider: Callable = binding.get("provider", Callable()) as Callable
	if not provider.is_valid():
		return {}
	var payload_value: Variant = provider.call()
	if not payload_value is Dictionary:
		return {}
	return (payload_value as Dictionary).duplicate(true)


func _fit_panel_to_content() -> void:
	var viewport_rect: Rect2 = get_viewport().get_visible_rect()
	var maximum_width: float = maxf(
		MINIMUM_TOOLTIP_WIDTH,
		viewport_rect.size.x - VIEWPORT_MARGIN * 2.0,
	)
	_details_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_warning_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_panel.custom_minimum_size = Vector2.ZERO
	_panel.reset_size()
	var natural_width: float = _panel.get_combined_minimum_size().x
	var target_width: float = clampf(natural_width, MINIMUM_TOOLTIP_WIDTH, maximum_width)
	_details_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_panel.custom_minimum_size = Vector2(target_width, 0.0)
	_panel.reset_size()


func _position_for_target(anchor_rect: Rect2, panel_size: Vector2) -> Vector2:
	var viewport_rect: Rect2 = get_viewport().get_visible_rect()
	var safe_rect := Rect2(
		viewport_rect.position + Vector2(VIEWPORT_MARGIN, VIEWPORT_MARGIN),
		viewport_rect.size - Vector2(VIEWPORT_MARGIN, VIEWPORT_MARGIN) * 2.0,
	)
	var maximum_position := Vector2(
		maxf(safe_rect.position.x, safe_rect.end.x - panel_size.x),
		maxf(safe_rect.position.y, safe_rect.end.y - panel_size.y),
	)
	var aligned_y: float = clampf(
		anchor_rect.position.y,
		safe_rect.position.y,
		maximum_position.y,
	)
	var right_position := Vector2(anchor_rect.end.x + TARGET_GAP, aligned_y)
	if right_position.x + panel_size.x <= safe_rect.end.x:
		return right_position
	var left_position := Vector2(anchor_rect.position.x - TARGET_GAP - panel_size.x, aligned_y)
	if left_position.x >= safe_rect.position.x:
		return left_position
	var aligned_x: float = clampf(
		anchor_rect.position.x,
		safe_rect.position.x,
		maximum_position.x,
	)
	var bottom_position := Vector2(aligned_x, anchor_rect.end.y + TARGET_GAP)
	if bottom_position.y + panel_size.y <= safe_rect.end.y:
		return bottom_position
	var top_position := Vector2(aligned_x, anchor_rect.position.y - TARGET_GAP - panel_size.y)
	if top_position.y >= safe_rect.position.y:
		return top_position
	return Vector2(
		clampf(right_position.x, safe_rect.position.x, maximum_position.x),
		clampf(right_position.y, safe_rect.position.y, maximum_position.y),
	)


func _reposition_displayed() -> void:
	if not _panel.visible or not _valid_bound_target(_displayed_target):
		return
	_displayed_anchor_rect = _displayed_target.get_global_rect()
	_panel.position = _position_for_target(_displayed_anchor_rect, _panel.size)


func _on_viewport_size_changed() -> void:
	if not _panel.visible:
		return
	_fit_panel_to_content()
	_reposition_displayed.call_deferred()


func _on_panel_resized() -> void:
	if _panel.visible:
		_reposition_displayed.call_deferred()


func _remove_binding(instance_id: int, disconnect_signals: bool) -> void:
	if not _bindings.has(instance_id):
		return
	var binding: Dictionary = _bindings[instance_id] as Dictionary
	var target := binding.get("target") as InventoryCardButton
	if target == _hovered_target:
		_hovered_target = null
	if target == _focused_target:
		_focused_target = null
	if target == _pending_target or target == _displayed_target:
		hide_tooltip(false)
	if disconnect_signals and target != null and is_instance_valid(target):
		_disconnect_target_signal(target.mouse_entered, binding.get("mouse_entered", Callable()) as Callable)
		_disconnect_target_signal(target.mouse_exited, binding.get("mouse_exited", Callable()) as Callable)
		_disconnect_target_signal(target.focus_entered, binding.get("focus_entered", Callable()) as Callable)
		_disconnect_target_signal(target.focus_exited, binding.get("focus_exited", Callable()) as Callable)
		_disconnect_target_signal(target.tree_exiting, binding.get("tree_exiting", Callable()) as Callable)
		target.set_managed_tooltip(false)
	_bindings.erase(instance_id)


func _disconnect_target_signal(target_signal: Signal, callback: Callable) -> void:
	if callback.is_valid() and target_signal.is_connected(callback):
		target_signal.disconnect(callback)


func _valid_bound_target(target: InventoryCardButton) -> bool:
	return (
		target != null
		and is_instance_valid(target)
		and target.is_inside_tree()
		and _bindings.has(target.get_instance_id())
	)


func _input_mode_name() -> StringName:
	match _input_mode:
		InputMode.POINTER:
			return &"pointer"
		InputMode.FOCUS:
			return &"focus"
	return &"none"
