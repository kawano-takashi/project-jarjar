extends PanelContainer


signal activated

var disabled: bool = false:
	set(value):
		disabled = value
		mouse_filter = Control.MOUSE_FILTER_IGNORE if disabled else Control.MOUSE_FILTER_STOP
		modulate = Color(0.55, 0.55, 0.55, 1.0) if disabled else Color.WHITE


static func is_activation_event(event: InputEvent) -> bool:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		return (
			key_event.pressed
			and not key_event.echo
			and (
				key_event.keycode in [KEY_ENTER, KEY_KP_ENTER]
				or key_event.physical_keycode in [KEY_ENTER, KEY_KP_ENTER]
			)
		)
	if event is InputEventJoypadButton:
		var joy_event := event as InputEventJoypadButton
		return joy_event.pressed and joy_event.button_index == JOY_BUTTON_A
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		return mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT
	return false


func test_handle_input(event: InputEvent) -> void:
	_gui_input(event)


func _gui_input(event: InputEvent) -> void:
	if disabled:
		accept_event()
		return
	if is_activation_event(event):
		activated.emit()
		accept_event()
		return
	if event is InputEventKey or event is InputEventJoypadButton:
		accept_event()
