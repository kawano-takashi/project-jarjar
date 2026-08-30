class_name UiPolish
extends RefCounted


const FOCUS_FRAME_NODE_NAME: StringName = &"__FocusShapeFrame"
const FOCUS_FRAME_WIDTH: int = 4
const FOCUS_FRAME_COLOR := Color(1.0, 0.78, 0.22, 1.0)
const COMMON_COLOR := Color(0.72, 0.76, 0.78, 1.0)
const RARE_COLOR := Color(0.25, 0.67, 1.0, 1.0)
const EPIC_COLOR := Color(0.78, 0.35, 1.0, 1.0)
const LEGENDARY_COLOR := Color(1.0, 0.68, 0.18, 1.0)
const UNIQUE_COLOR := Color(0.95, 0.16, 0.22, 1.0)
const SKILL_COLOR := Color(0.35, 0.92, 0.72, 1.0)
const NEUTRAL_COLOR := Color(0.38, 0.44, 0.48, 1.0)


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


static func rarity_color(rarity: int) -> Color:
	match rarity:
		GameTypes.Rarity.COMMON:
			return COMMON_COLOR
		GameTypes.Rarity.RARE:
			return RARE_COLOR
		GameTypes.Rarity.EPIC:
			return EPIC_COLOR
		GameTypes.Rarity.LEGENDARY:
			return LEGENDARY_COLOR
		GameTypes.Rarity.UNIQUE:
			return UNIQUE_COLOR
		-1:
			return SKILL_COLOR
	return NEUTRAL_COLOR


static func rarity_corner_radii(rarity: int) -> PackedInt32Array:
	match rarity:
		GameTypes.Rarity.RARE:
			return PackedInt32Array([9, 9, 9, 9])
		GameTypes.Rarity.EPIC:
			return PackedInt32Array([20, 2, 20, 2])
		GameTypes.Rarity.LEGENDARY:
			return PackedInt32Array([28, 28, 28, 28])
		GameTypes.Rarity.UNIQUE:
			return PackedInt32Array([2, 28, 2, 28])
		-1:
			return PackedInt32Array([32, 32, 32, 32])
	return PackedInt32Array([1, 1, 1, 1])


static func apply_rarity_corner_shape(style: StyleBoxFlat, rarity: int) -> void:
	if style == null:
		return
	var radii: PackedInt32Array = rarity_corner_radii(rarity)
	style.corner_radius_top_left = radii[0]
	style.corner_radius_top_right = radii[1]
	style.corner_radius_bottom_right = radii[2]
	style.corner_radius_bottom_left = radii[3]


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
