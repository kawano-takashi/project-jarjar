class_name InventoryCardButton
extends Button


const UiPolishScript := preload("res://src/ui/ui_polish.gd")
const ICON_MAX_WIDTH: int = 64
const EMPTY_ICON_COLOR := Color(0.44, 0.47, 0.49, 0.28)
const CARD_BACKGROUND := Color(0.035, 0.049, 0.065, 0.98)
const SELECTED_BACKGROUND := Color(0.10, 0.24, 0.19, 0.98)
const ICON_COLOR_NAMES: Array[StringName] = [
	&"icon_normal_color",
	&"icon_focus_color",
	&"icon_hover_color",
	&"icon_pressed_color",
	&"icon_hover_pressed_color",
]

signal pointer_event
signal drop_received(source: Dictionary, target: Dictionary)

var drag_payload: Dictionary = {}
var drop_payload: Dictionary = {}
var drag_enabled: bool = false
var accepted_drag_type: StringName = &""
var _visual_mode: bool = false
var _visual_rarity: int = -2
var _visual_unique: bool = false
var _visual_locked: bool = false
var _visual_state_badge: String = ""
var _visual_muted: bool = false
var _managed_tooltip: bool = false
var _unique_badge: Label = null
var _lock_badge: Label = null
var _state_badge: Label = null


func configure_item_visual(
	texture: Texture2D,
	rarity: int,
	show_unique: bool,
	show_locked: bool,
	state_badge: String,
	muted: bool,
	p_accessibility_name: String,
	p_accessibility_description: String,
) -> void:
	_ensure_badges()
	_visual_mode = true
	_visual_rarity = rarity
	_visual_unique = show_unique
	_visual_locked = show_locked
	_visual_state_badge = state_badge
	_visual_muted = muted
	text = ""
	icon = texture
	expand_icon = true
	icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_theme_constant_override("icon_max_width", ICON_MAX_WIDTH)
	accessibility_name = p_accessibility_name
	accessibility_description = p_accessibility_description
	tooltip_text = p_accessibility_description
	_unique_badge.text = "★" if show_unique else ""
	_lock_badge.text = "🔒" if show_locked else ""
	_state_badge.text = state_badge
	_apply_icon_colors(UiPolishScript.rarity_color(rarity) if not muted else EMPTY_ICON_COLOR)
	_apply_item_styles(rarity, muted)
	set_meta("item_visual", true)
	set_meta("item_icon_path", texture.resource_path if texture != null else "")
	set_meta("item_rarity", rarity)
	set_meta("item_unique_badge", show_unique)
	set_meta("item_lock_badge", show_locked)
	set_meta("item_state_badge", state_badge)
	set_meta("item_icon_muted", muted)


func set_managed_tooltip(enabled: bool) -> void:
	_managed_tooltip = enabled
	set_meta("managed_tooltip", enabled)


func _get_tooltip(_at_position: Vector2) -> String:
	return "" if _managed_tooltip else tooltip_text


func clear_item_visual() -> void:
	_visual_mode = false
	_visual_rarity = -2
	_visual_unique = false
	_visual_locked = false
	_visual_state_badge = ""
	_visual_muted = false
	icon = null
	accessibility_name = ""
	accessibility_description = ""
	if _unique_badge != null:
		_unique_badge.text = ""
		_lock_badge.text = ""
		_state_badge.text = ""
	for color_name: StringName in ICON_COLOR_NAMES:
		remove_theme_color_override(color_name)
	remove_theme_color_override(&"icon_disabled_color")
	for style_name: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed", &"disabled", &"focus"]:
		remove_theme_stylebox_override(style_name)
	set_meta("item_visual", false)


func presentation_snapshot() -> Dictionary:
	var normal_style := get_theme_stylebox(&"normal") as StyleBoxFlat
	return {
		"visual_mode": _visual_mode,
		"text": text,
		"icon_path": icon.resource_path if icon != null else "",
		"rarity": _visual_rarity,
		"unique_badge": _visual_unique,
		"lock_badge": _visual_locked,
		"state_badge": _visual_state_badge,
		"muted": _visual_muted,
		"icon_color": get_theme_color(&"icon_normal_color"),
		"accessibility_name": accessibility_name,
		"accessibility_description": accessibility_description,
		"tooltip": tooltip_text,
		"managed_tooltip": _managed_tooltip,
		"icon_max_width": get_theme_constant(&"icon_max_width"),
		"texture_filter": texture_filter,
		"corner_radii": PackedInt32Array([
			normal_style.corner_radius_top_left if normal_style != null else -1,
			normal_style.corner_radius_top_right if normal_style != null else -1,
			normal_style.corner_radius_bottom_right if normal_style != null else -1,
			normal_style.corner_radius_bottom_left if normal_style != null else -1,
		]),
	}


func drag_preview_snapshot() -> Dictionary:
	var preview: Control = _build_drag_preview()
	var result: Dictionary
	if preview is InventoryCardButton:
		result = (preview as InventoryCardButton).presentation_snapshot()
	else:
		result = {
			"visual_mode": false,
			"text": (preview as Label).text if preview is Label else "",
		}
	preview.free()
	return result


func configure_drag(
	p_drag_payload: Dictionary,
	p_drop_payload: Dictionary,
	p_drag_enabled: bool,
	p_accepted_drag_type: StringName,
) -> void:
	drag_payload = p_drag_payload.duplicate(true)
	drop_payload = p_drop_payload.duplicate(true)
	drag_enabled = p_drag_enabled
	accepted_drag_type = p_accepted_drag_type


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		pointer_event.emit()


func _get_drag_data(_at_position: Vector2) -> Variant:
	if not drag_enabled or drag_payload.is_empty():
		return null
	var preview: Control = _build_drag_preview()
	set_drag_preview(preview)
	return drag_payload.duplicate(true)


func _build_drag_preview() -> Control:
	var preview: Control
	if _visual_mode:
		var icon_preview := InventoryCardButton.new()
		icon_preview.custom_minimum_size = size if size.x > 0.0 and size.y > 0.0 else Vector2(96.0, 96.0)
		icon_preview.focus_mode = Control.FOCUS_NONE
		icon_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_preview.configure_item_visual(
			icon,
			_visual_rarity,
			_visual_unique,
			_visual_locked,
			_visual_state_badge,
			_visual_muted,
			accessibility_name,
			accessibility_description,
		)
		preview = icon_preview
	else:
		var text_preview := Label.new()
		text_preview.text = text
		text_preview.add_theme_font_size_override("font_size", 16)
		preview = text_preview
	return preview


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not data is Dictionary:
		return false
	var payload := data as Dictionary
	return (
		not accepted_drag_type.is_empty()
		and StringName(payload.get("drag_type", &"")) == accepted_drag_type
	)


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if not _can_drop_data(Vector2.ZERO, data):
		return
	drop_received.emit((data as Dictionary).duplicate(true), drop_payload.duplicate(true))


func _ensure_badges() -> void:
	if _unique_badge != null:
		return
	_unique_badge = _new_badge("UniqueBadge", HORIZONTAL_ALIGNMENT_LEFT)
	_unique_badge.anchor_left = 0.0
	_unique_badge.anchor_top = 0.0
	_unique_badge.anchor_right = 0.0
	_unique_badge.anchor_bottom = 0.0
	_unique_badge.offset_left = 5.0
	_unique_badge.offset_top = 2.0
	_unique_badge.offset_right = 31.0
	_unique_badge.offset_bottom = 28.0
	_unique_badge.add_theme_color_override("font_color", Color(1.0, 0.82, 0.24, 1.0))
	_lock_badge = _new_badge("LockBadge", HORIZONTAL_ALIGNMENT_RIGHT)
	_lock_badge.anchor_left = 1.0
	_lock_badge.anchor_top = 0.0
	_lock_badge.anchor_right = 1.0
	_lock_badge.anchor_bottom = 0.0
	_lock_badge.offset_left = -33.0
	_lock_badge.offset_top = 2.0
	_lock_badge.offset_right = -5.0
	_lock_badge.offset_bottom = 30.0
	_state_badge = _new_badge("StateBadge", HORIZONTAL_ALIGNMENT_RIGHT)
	_state_badge.anchor_left = 1.0
	_state_badge.anchor_top = 1.0
	_state_badge.anchor_right = 1.0
	_state_badge.anchor_bottom = 1.0
	_state_badge.offset_left = -34.0
	_state_badge.offset_top = -31.0
	_state_badge.offset_right = -5.0
	_state_badge.offset_bottom = -3.0
	_state_badge.add_theme_color_override("font_color", Color(0.45, 1.0, 0.68, 1.0))


func _new_badge(node_name: String, horizontal_alignment: HorizontalAlignment) -> Label:
	var badge := Label.new()
	badge.name = node_name
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.focus_mode = Control.FOCUS_NONE
	badge.z_index = 0
	badge.z_as_relative = true
	badge.horizontal_alignment = horizontal_alignment
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_theme_font_size_override("font_size", 18)
	badge.add_theme_color_override("font_outline_color", Color(0.01, 0.015, 0.02, 1.0))
	badge.add_theme_constant_override("outline_size", 4)
	add_child(badge)
	return badge


func _apply_icon_colors(color: Color) -> void:
	for color_name: StringName in ICON_COLOR_NAMES:
		add_theme_color_override(color_name, color)
	var disabled_color := color
	disabled_color.a *= 0.45
	add_theme_color_override("icon_disabled_color", disabled_color)


func _apply_item_styles(rarity: int, muted: bool) -> void:
	var border_color: Color = (
		UiPolishScript.NEUTRAL_COLOR * Color(1.0, 1.0, 1.0, 0.55)
		if muted
		else UiPolishScript.rarity_color(rarity)
	)
	var border_width: int = 1 if muted else 3
	add_theme_stylebox_override("normal", _item_style(CARD_BACKGROUND, border_color, border_width, rarity))
	add_theme_stylebox_override(
		"hover",
		_item_style(CARD_BACKGROUND.lightened(0.10), border_color, border_width, rarity),
	)
	add_theme_stylebox_override(
		"pressed",
		_item_style(SELECTED_BACKGROUND, border_color, border_width, rarity),
	)
	add_theme_stylebox_override(
		"hover_pressed",
		_item_style(SELECTED_BACKGROUND.lightened(0.08), border_color, border_width, rarity),
	)
	add_theme_stylebox_override(
		"disabled",
		_item_style(CARD_BACKGROUND.darkened(0.18), border_color * Color(1.0, 1.0, 1.0, 0.45), border_width, rarity),
	)
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())


func _item_style(
	background: Color,
	border_color: Color,
	border_width: int,
	rarity: int,
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.content_margin_left = 6.0
	style.content_margin_top = 6.0
	style.content_margin_right = 6.0
	style.content_margin_bottom = 6.0
	UiPolishScript.apply_rarity_corner_shape(
		style,
		rarity if rarity >= GameTypes.Rarity.COMMON else GameTypes.Rarity.COMMON,
	)
	return style
