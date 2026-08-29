class_name TutorialOverlay
extends CanvasLayer


signal cancel_input_observed


var _panel: PanelContainer = null
var _label: Label = null


func _ready() -> void:
	layer = 90
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.focus_mode = Control.FOCUS_NONE
	add_child(root)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_CENTER_TOP)
	center.anchor_left = 0.0
	center.anchor_right = 1.0
	center.offset_top = 28.0
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.focus_mode = Control.FOCUS_NONE
	root.add_child(center)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(640.0, 0.0)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.focus_mode = Control.FOCUS_NONE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.045, 0.052, 0.96)
	style.border_color = Color(0.95, 0.43, 0.28, 1.0)
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	style.content_margin_left = 24.0
	style.content_margin_top = 16.0
	style.content_margin_right = 24.0
	style.content_margin_bottom = 16.0
	_panel.add_theme_stylebox_override("panel", style)
	center.add_child(_panel)

	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_font_size_override("font_size", 22)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.focus_mode = Control.FOCUS_NONE
	_panel.add_child(_label)
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		cancel_input_observed.emit()
		get_viewport().set_input_as_handled()


func show_message(message: String) -> void:
	if message.is_empty():
		hide_message()
		return
	_label.text = message
	visible = true


func hide_message() -> void:
	visible = false
	if _label != null:
		_label.text = ""


func message_text() -> String:
	return _label.text if _label != null else ""
