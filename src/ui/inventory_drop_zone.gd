class_name InventoryDropZone
extends Control


signal pointer_event
signal drop_received(source: Dictionary)

@export var accepted_drag_type: StringName = &"fusion_material"


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		pointer_event.emit()


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return (
		data is Dictionary
		and StringName((data as Dictionary).get("drag_type", &"")) == accepted_drag_type
	)


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if _can_drop_data(Vector2.ZERO, data):
		drop_received.emit((data as Dictionary).duplicate(true))
