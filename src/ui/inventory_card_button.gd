class_name InventoryCardButton
extends Button


signal pointer_event
signal drop_received(source: Dictionary, target: Dictionary)

var drag_payload: Dictionary = {}
var drop_payload: Dictionary = {}
var drag_enabled: bool = false
var accepted_drag_type: StringName = &""


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
	var preview := Label.new()
	preview.text = text
	preview.add_theme_font_size_override("font_size", 16)
	set_drag_preview(preview)
	return drag_payload.duplicate(true)


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
