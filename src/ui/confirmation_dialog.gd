class_name JarjarConfirmationDialog
extends Control


signal confirmed
signal cancelled

@onready var _heading: Label = %DialogHeading
@onready var _message: Label = %DialogMessage
@onready var _cancel: Button = %DialogCancel
@onready var _confirm: Button = %DialogConfirm

var _focus_controller := FocusController.new()
var _pending_heading: String = "確認"
var _pending_message: String = ""
var _pending_confirm_text: String = "実行"
var _origin_focus_id: String = ""


func _ready() -> void:
	_focus_controller.configure_graph(
		{
			"dialog_cancel": _cancel,
			"dialog_confirm": _confirm,
		},
		{
			"dialog_cancel": _neighbors("dialog_cancel", "dialog_confirm"),
			"dialog_confirm": _neighbors("dialog_confirm", "dialog_cancel"),
		},
		"dialog_cancel",
		PackedStringArray(["dialog_cancel", "dialog_confirm"]),
	)
	_cancel.pressed.connect(_cancel_dialog)
	_confirm.pressed.connect(_confirm_dialog)
	visible = false
	set_process_input(false)
	set_process_unhandled_input(false)
	_apply_pending_text()


func open_dialog(
	heading: String,
	message: String,
	confirm_text: String,
	p_origin_focus_id: String,
) -> void:
	_pending_heading = heading
	_pending_message = message
	_pending_confirm_text = confirm_text
	_origin_focus_id = p_origin_focus_id
	_apply_pending_text()
	visible = true
	set_process_input(true)
	_focus_controller.focus_initial_deferred()


func close_without_signal() -> void:
	visible = false
	set_process_input(false)
	set_process_unhandled_input(false)


func origin_focus_id() -> String:
	return _origin_focus_id


func focus_order() -> PackedStringArray:
	return PackedStringArray(["dialog_cancel", "dialog_confirm"])


func focus_controls() -> Dictionary:
	return {
		"dialog_cancel": _cancel,
		"dialog_confirm": _confirm,
	}


func focus_ids() -> PackedStringArray:
	return _focus_controller.focus_ids()


func focus_control(focus_id: String) -> Control:
	return _focus_controller.control_for_id(focus_id)


func test_focus(focus_id: String) -> bool:
	return _focus_controller.grab_focus_id(focus_id)


func initial_focus_control() -> Control:
	return _cancel


func debug_state() -> Dictionary:
	return {
		"visible": visible,
		"origin_focus_id": _origin_focus_id,
		"focus_id": _focus_controller.current_focus_id(get_viewport()),
		"message": _pending_message,
	}


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		_cancel_dialog()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"ui_focus_next") and not event.is_echo():
		_focus_controller.move_tab(get_viewport(), true)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"ui_focus_prev") and not event.is_echo():
		_focus_controller.move_tab(get_viewport(), false)
		get_viewport().set_input_as_handled()
		return
	var direction: StringName = FocusController.direction_for_event(event)
	if not direction.is_empty():
		_focus_controller.move(get_viewport(), direction)
		get_viewport().set_input_as_handled()
	elif FocusController.is_left_stick_focus_motion(event):
		get_viewport().set_input_as_handled()


func _cancel_dialog() -> void:
	if not visible:
		return
	close_without_signal()
	cancelled.emit()


func _confirm_dialog() -> void:
	if not visible:
		return
	close_without_signal()
	confirmed.emit()


func _apply_pending_text() -> void:
	if not is_node_ready():
		return
	_heading.text = _pending_heading
	_message.text = _pending_message
	_confirm.text = "%s　A／Enter" % _pending_confirm_text


func _neighbors(self_id: String, other_id: String) -> Dictionary:
	return {
		FocusController.DIRECTION_TOP: self_id,
		FocusController.DIRECTION_BOTTOM: self_id,
		FocusController.DIRECTION_LEFT: other_id,
		FocusController.DIRECTION_RIGHT: other_id,
	}
