class_name FusionDialog
extends Control


signal rarity_step_requested(step: int)
signal material_slot_pressed(slot_index: int)
signal material_drag_removed(slot_index: int)
signal material_item_dropped(source: Dictionary, slot_index: int)
signal auto_fill_requested
signal wild_toggle_requested
signal confirm_requested
signal cancelled
signal pointer_event

@onready var _rarity: Button = %FusionRarity
@onready var _material_slots: Array[InventoryCardButton] = [
	%FusionMaterial0,
	%FusionMaterial1,
	%FusionMaterial2,
]
@onready var _auto_fill: Button = %FusionAutoFill
@onready var _wild_toggle: Button = %FusionWildToggle
@onready var _confirm: Button = %FusionConfirm
@onready var _cancel: Button = %FusionCancel
@onready var _preview: Label = %FusionPreview
@onready var _status: Label = %FusionStatus
@onready var _remove_zone: InventoryDropZone = %MaterialRemoveZone

var _origin_focus_id: String = "action_2"


func _ready() -> void:
	_rarity.set_meta("focus_id", "FR")
	for index: int in range(_material_slots.size()):
		var slot: InventoryCardButton = _material_slots[index]
		slot.set_meta("focus_id", "F%d" % index)
		slot.pressed.connect(_on_material_pressed.bind(index))
		slot.pointer_event.connect(_on_pointer_event)
		slot.drop_received.connect(_on_material_item_dropped.bind(index))
	_auto_fill.set_meta("focus_id", "FA0")
	_wild_toggle.set_meta("focus_id", "FA1")
	_confirm.set_meta("focus_id", "FA2")
	_cancel.set_meta("focus_id", "FA3")
	_auto_fill.pressed.connect(func() -> void: auto_fill_requested.emit())
	_wild_toggle.pressed.connect(func() -> void: wild_toggle_requested.emit())
	_confirm.pressed.connect(func() -> void: confirm_requested.emit())
	_cancel.pressed.connect(_cancel_dialog)
	_remove_zone.drop_received.connect(_on_material_drop_removed)
	_remove_zone.pointer_event.connect(_on_pointer_event)
	visible = false
	set_process_input(false)


func open_dialog(p_origin_focus_id: String = "action_2") -> void:
	_origin_focus_id = p_origin_focus_id
	visible = true
	set_process_input(true)


func close_without_signal() -> void:
	visible = false
	set_process_input(false)


func focus_controls() -> Dictionary:
	return {
		"FR": _rarity,
		"F0": _material_slots[0],
		"F1": _material_slots[1],
		"F2": _material_slots[2],
		"FA0": _auto_fill,
		"FA1": _wild_toggle,
		"FA2": _confirm,
		"FA3": _cancel,
	}


func focus_order() -> PackedStringArray:
	return PackedStringArray(["FR", "F0", "F1", "F2", "FA0", "FA1", "FA2", "FA3"])


func origin_focus_id() -> String:
	return _origin_focus_id


func update_view(
	rarity_label: String,
	material_ids: PackedStringArray,
	material_names: PackedStringArray,
	use_wild: bool,
	wild_available: int,
	confirm_enabled: bool,
	preview_text: String,
	status_text: String,
) -> void:
	if not is_node_ready():
		return
	_rarity.text = "レアリティ  ◀ %s ▶" % rarity_label
	for index: int in range(_material_slots.size()):
		var item_id: String = material_ids[index] if index < material_ids.size() else ""
		var item_name: String = material_names[index] if index < material_names.size() else ""
		var slot: InventoryCardButton = _material_slots[index]
		slot.text = "F%d\n%s" % [index, item_name if not item_name.is_empty() else "空き"]
		slot.configure_drag(
			{
				"drag_type": &"fusion_material",
				"slot_index": index,
				"item_id": item_id,
			},
			{},
			not item_id.is_empty(),
			&"item",
		)
	_wild_toggle.disabled = wild_available <= 0
	_wild_toggle.text = (
		"ワイルド解除（予約1）"
		if use_wild
		else "ワイルド投入（所持%d）" % wild_available
	)
	_confirm.disabled = not confirm_enabled
	_preview.text = preview_text
	_status.text = status_text


func debug_state() -> Dictionary:
	return {
		"visible": visible,
		"origin_focus_id": _origin_focus_id,
		"confirm_enabled": not _confirm.disabled,
		"wild_enabled": not _wild_toggle.disabled,
		"rarity_text": _rarity.text,
		"preview": _preview.text,
		"status": _status.text,
	}


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		_cancel_dialog()
		get_viewport().set_input_as_handled()
		return
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused != _rarity or event.is_echo():
		return
	if event.is_action_pressed("ui_left"):
		rarity_step_requested.emit(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		rarity_step_requested.emit(1)
		get_viewport().set_input_as_handled()


func _on_material_pressed(slot_index: int) -> void:
	material_slot_pressed.emit(slot_index)


func _on_material_item_dropped(
	source: Dictionary,
	_target: Dictionary,
	slot_index: int,
) -> void:
	material_item_dropped.emit(source, slot_index)


func _on_material_drop_removed(source: Dictionary) -> void:
	material_drag_removed.emit(int(source.get("slot_index", -1)))


func _on_pointer_event() -> void:
	pointer_event.emit()


func _cancel_dialog() -> void:
	if not visible:
		return
	close_without_signal()
	cancelled.emit()
