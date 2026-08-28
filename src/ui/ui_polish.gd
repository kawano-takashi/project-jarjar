class_name UiPolish
extends RefCounted


const FOCUS_FRAME_NODE_NAME: StringName = &"__FocusShapeFrame"
const FOCUS_FRAME_WIDTH: int = 4
const FOCUS_FRAME_COLOR := Color(1.0, 0.78, 0.22, 1.0)


static func install_focus_frame(control: Control) -> void:
	if control == null:
		return
	var existing := control.get_node_or_null(NodePath(FOCUS_FRAME_NODE_NAME)) as Panel
	if existing != null:
		return

	var frame := Panel.new()
	frame.name = FOCUS_FRAME_NODE_NAME
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.focus_mode = Control.FOCUS_NONE
	frame.z_index = 4096
	control.add_child(frame)
	frame.anchor_left = 0.0
	frame.anchor_top = 0.0
	frame.anchor_right = 1.0
	frame.anchor_bottom = 1.0
	frame.offset_left = 0.0
	frame.offset_top = 0.0
	frame.offset_right = 0.0
	frame.offset_bottom = 0.0
	frame.add_theme_stylebox_override("panel", _focus_frame_style())
	frame.visible = control.has_focus()

	control.set_meta("focus_shape_kind", "asymmetric_outline")
	control.set_meta("focus_shape_border_width", FOCUS_FRAME_WIDTH)
	control.focus_entered.connect(_set_frame_visible.bind(frame, true))
	control.focus_exited.connect(_set_frame_visible.bind(frame, false))


static func _focus_frame_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	style.border_color = FOCUS_FRAME_COLOR
	style.border_width_left = FOCUS_FRAME_WIDTH
	style.border_width_top = FOCUS_FRAME_WIDTH
	style.border_width_right = FOCUS_FRAME_WIDTH
	style.border_width_bottom = FOCUS_FRAME_WIDTH
	style.corner_radius_top_left = 14
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_right = 14
	style.corner_radius_bottom_left = 2
	return style


static func _set_frame_visible(frame: Panel, should_show: bool) -> void:
	if is_instance_valid(frame):
		frame.visible = should_show
