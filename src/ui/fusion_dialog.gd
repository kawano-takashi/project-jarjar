class_name FusionDialog
extends Control


const UiPolishScript := preload("res://src/ui/ui_polish.gd")
const InventoryItemVisualsScript := preload("res://src/ui/inventory_item_visuals.gd")
const CANDIDATE_COLUMNS: int = 8
const MATERIAL_COUNT: int = 3


signal rarity_step_requested(step: int)
signal material_slot_pressed(slot_index: int)
signal material_drag_removed(slot_index: int)
signal material_item_dropped(source: Dictionary, slot_index: int)
signal candidate_toggled(item_id: String)
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
@onready var _candidate_empty: Label = %FusionCandidateEmpty
@onready var _candidate_scroll: ScrollContainer = %FusionCandidateScroll
@onready var _candidate_grid: GridContainer = %FusionCandidateGrid
@onready var _auto_fill: Button = %FusionAutoFill
@onready var _wild_toggle: Button = %FusionWildToggle
@onready var _confirm: Button = %FusionConfirm
@onready var _cancel: Button = %FusionCancel
@onready var _preview: Label = %FusionPreview
@onready var _status: Label = %FusionStatus
@onready var _remove_zone: InventoryDropZone = %MaterialRemoveZone
@onready var _item_tooltip: Variant = %InventoryItemTooltip

var _origin_focus_id: String = "action_2"
var _focus_controller := FocusController.new()
var _candidate_entries: Array[Dictionary] = []
var _candidate_cards: Array[InventoryCardButton] = []
var _candidate_item_ids := PackedStringArray()
var _material_ids := PackedStringArray()
var _material_entries: Array[Dictionary] = []


func _ready() -> void:
	_rarity.set_meta("focus_id", "FR")
	_rarity.pressed.connect(_on_rarity_pressed)
	for index: int in range(_material_slots.size()):
		var slot: InventoryCardButton = _material_slots[index]
		slot.set_meta("focus_id", "F%d" % index)
		slot.pressed.connect(_on_material_pressed.bind(index))
		slot.pointer_event.connect(_on_pointer_event)
		slot.drop_received.connect(_on_material_item_dropped.bind(index))
		var empty_details: String = "合成材料枠%d\n空き\n配置可否: 対象レアリティの装備をドロップ可能\n操作: 候補で A／Enter、または装備をドロップして配置" % (index + 1)
		slot.configure_item_visual(
			null,
			-2,
			false,
			false,
			"",
			true,
			"合成材料枠%d、空き、対象レアリティの装備を配置可能" % (index + 1),
			empty_details,
		)
		_item_tooltip.bind_target(slot, _material_tooltip_payload.bind(index))
	_auto_fill.set_meta("focus_id", "FA0")
	_wild_toggle.set_meta("focus_id", "FA1")
	_confirm.set_meta("focus_id", "FA2")
	_cancel.set_meta("focus_id", "FA3")
	for control: Control in [
		_rarity,
		_material_slots[0],
		_material_slots[1],
		_material_slots[2],
		_auto_fill,
		_wild_toggle,
		_confirm,
		_cancel,
	]:
		UiPolishScript.install_focus_frame(control)
	_auto_fill.pressed.connect(func() -> void: auto_fill_requested.emit())
	_wild_toggle.pressed.connect(func() -> void: wild_toggle_requested.emit())
	_confirm.pressed.connect(func() -> void: confirm_requested.emit())
	_cancel.pressed.connect(_cancel_dialog)
	_remove_zone.drop_received.connect(_on_material_drop_removed)
	_remove_zone.pointer_event.connect(_on_pointer_event)
	visible = false
	set_process_input(false)
	set_process_unhandled_input(false)


func open_dialog(p_origin_focus_id: String = "action_2") -> void:
	_origin_focus_id = p_origin_focus_id
	visible = true
	_item_tooltip.begin_session()
	set_process_input(true)


func close_without_signal() -> void:
	_item_tooltip.end_session()
	visible = false
	set_process_input(false)
	set_process_unhandled_input(false)


func focus_controls() -> Dictionary:
	var result: Dictionary = {}
	for focus_id: String in _focus_controller.focus_ids():
		result[focus_id] = _focus_controller.control_for_id(focus_id)
	return result


func focus_order() -> PackedStringArray:
	return _focus_controller.tab_order()


func focus_ids() -> PackedStringArray:
	return _focus_controller.focus_ids()


func focus_control(focus_id: String) -> Control:
	return _focus_controller.control_for_id(focus_id)


func neighbor_specification(focus_id: String) -> Dictionary:
	return _focus_controller.neighbor_specification(focus_id)


func origin_focus_id() -> String:
	return _origin_focus_id


func status_control() -> Label:
	return _status


func hide_tooltip(reset_input_mode: bool = false) -> void:
	_item_tooltip.hide_tooltip(reset_input_mode)


func focus_initial_deferred() -> void:
	_focus_controller.focus_initial_deferred()


func focus_after_success() -> bool:
	if _focus_controller.grab_focus_id("FA0"):
		return true
	return _focus_controller.grab_focus_id("FR")


func focus_id_for_candidate(item_id: String) -> String:
	var index: int = _candidate_item_ids.find(item_id)
	return "FC%d" % index if index >= 0 else ""


func test_focus(focus_id: String) -> bool:
	_item_tooltip.activate_focus_input()
	return _focus_controller.grab_focus_id(focus_id)


func test_direction(direction: StringName) -> bool:
	_item_tooltip.activate_focus_input()
	return _focus_controller.move(get_viewport(), direction)


func test_tab(forward: bool) -> bool:
	return _focus_controller.move_tab(get_viewport(), forward)


func test_accept() -> void:
	_activate_focus_id(_focus_controller.current_focus_id(get_viewport()))


func update_view(
	rarity_label: String,
	material_entries: Array[Dictionary],
	use_wild: bool,
	wild_available: int,
	confirm_enabled: bool,
	preview_text: String,
	status_text: String,
	candidate_entries: Array[Dictionary],
) -> void:
	if not is_node_ready():
		return
	var previous_focus_id: String = _focus_controller.current_focus_id(get_viewport())
	_material_ids = PackedStringArray()
	_material_entries.clear()
	_rarity.text = "レアリティ　◀ %s ▶\n←→／方向パッド左右" % rarity_label
	for index: int in range(_material_slots.size()):
		var entry: Dictionary = (
			material_entries[index]
			if index < material_entries.size()
			else {
				"slot_index": index,
				"item_id": "",
				"item": null,
				"material_number": 0,
				"details": "合成材料枠%d、空き" % (index + 1),
				"accessibility_name": "合成材料枠%d、空き" % (index + 1),
			}
		)
		_material_entries.append(entry.duplicate(true))
		var item_id: String = str(entry.get("item_id", ""))
		_material_ids.append(item_id)
		var item: ItemInstance = entry.get("item") as ItemInstance
		var details: String = str(entry.get("details", ""))
		var slot: InventoryCardButton = _material_slots[index]
		slot.focus_mode = Control.FOCUS_ALL
		slot.configure_item_visual(
			InventoryItemVisualsScript.icon_for_item(item),
			item.rarity if item != null else -2,
			item != null and not item.unique_id.is_empty(),
			item != null and item.locked,
			str(index + 1) if item != null else "",
			item == null,
			str(entry.get("accessibility_name", "合成材料枠%d" % (index + 1))),
			details,
		)
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
		"ワイルド解除（予約1）\n実行 A／Enter"
		if use_wild
		else "ワイルド投入（所持%d）\n実行 A／Enter" % wild_available
	)
	_confirm.disabled = not confirm_enabled
	_preview.text = preview_text
	_status.text = status_text
	_sync_candidates(candidate_entries)
	_configure_focus_graph()
	if not previous_focus_id.is_empty():
		_focus_controller.grab_focus_id(previous_focus_id)
	_item_tooltip.refresh_active()


func debug_state() -> Dictionary:
	return {
		"visible": visible,
		"origin_focus_id": _origin_focus_id,
		"confirm_enabled": not _confirm.disabled,
		"wild_enabled": not _wild_toggle.disabled,
		"rarity_text": _rarity.text,
		"preview": _preview.text,
		"status": _status.text,
		"candidate_count": _candidate_cards.size(),
		"candidate_columns": CANDIDATE_COLUMNS,
		"candidate_item_ids": _candidate_item_ids.duplicate(),
		"tooltip": _item_tooltip.debug_snapshot(),
		"candidate_scroll": _candidate_scroll.scroll_vertical,
		"material_presentations": _presentation_snapshots(_material_slots),
		"candidate_presentations": _presentation_snapshots(_candidate_cards),
		"focus_ids": focus_ids(),
		"focus_order": focus_order(),
	}


func _notification(what: int) -> void:
	if not is_node_ready():
		return
	if what == NOTIFICATION_DRAG_BEGIN:
		_item_tooltip.refresh_active.call_deferred()
	elif what == NOTIFICATION_DRAG_END:
		_item_tooltip.hide_tooltip(false)


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
	var focused: Control = get_viewport().gui_get_focus_owner()
	var direction: StringName = FocusController.direction_for_event(event)
	if focused == _rarity and not event.is_echo():
		if direction == FocusController.DIRECTION_LEFT:
			rarity_step_requested.emit(-1)
			get_viewport().set_input_as_handled()
			return
		if direction == FocusController.DIRECTION_RIGHT:
			rarity_step_requested.emit(1)
			get_viewport().set_input_as_handled()
			return
	if not direction.is_empty():
		_focus_controller.move(get_viewport(), direction)
		get_viewport().set_input_as_handled()
	elif FocusController.is_left_stick_focus_motion(event):
		get_viewport().set_input_as_handled()


func _sync_candidates(candidate_entries: Array[Dictionary]) -> void:
	var next_ids := PackedStringArray()
	for entry: Dictionary in candidate_entries:
		next_ids.append(str(entry.get("item_id", "")))
	if next_ids != _candidate_item_ids:
		_rebuild_candidate_cards(candidate_entries)
	_candidate_entries.clear()
	for entry: Dictionary in candidate_entries:
		_candidate_entries.append(entry.duplicate(true))
	_candidate_item_ids = next_ids
	for index: int in range(_candidate_cards.size()):
		var card: InventoryCardButton = _candidate_cards[index]
		var entry: Dictionary = _candidate_entries[index]
		var item: ItemInstance = entry.get("item") as ItemInstance
		var material_number: int = int(entry.get("material_number", 0))
		card.button_pressed = material_number > 0
		card.configure_item_visual(
			InventoryItemVisualsScript.icon_for_item(item),
			item.rarity if item != null else -2,
			item != null and not item.unique_id.is_empty(),
			item != null and item.locked,
			str(material_number) if material_number > 0 else "",
			item == null,
			str(entry.get("accessibility_name", "合成候補")),
			str(entry.get("details", "")),
		)
		var source: Dictionary = entry.get("source", {}) as Dictionary
		card.configure_drag(
			{
				"drag_type": &"item",
				"kind": source.get("kind", &""),
				"index": source.get("index", -1),
				"item_id": entry.get("item_id", ""),
			},
			{},
			true,
			&"",
		)
	_candidate_empty.visible = _candidate_cards.is_empty()


func _rebuild_candidate_cards(candidate_entries: Array[Dictionary]) -> void:
	for child: Node in _candidate_grid.get_children():
		if child is InventoryCardButton:
			_item_tooltip.unbind_target(child as InventoryCardButton)
		_candidate_grid.remove_child(child)
		child.queue_free()
	_candidate_cards.clear()
	for index: int in range(candidate_entries.size()):
		var entry: Dictionary = candidate_entries[index]
		var item_id: String = str(entry.get("item_id", ""))
		var card := InventoryCardButton.new()
		card.name = "FusionCandidate%d" % index
		card.custom_minimum_size = Vector2(96.0, 96.0)
		card.focus_mode = Control.FOCUS_ALL
		card.toggle_mode = true
		card.set_meta("focus_id", "FC%d" % index)
		card.pressed.connect(_on_candidate_pressed.bind(item_id))
		card.pointer_event.connect(_on_pointer_event)
		card.focus_entered.connect(_on_candidate_focused.bind(card))
		_candidate_grid.add_child(card)
		_item_tooltip.bind_target(card, _candidate_tooltip_payload.bind(item_id))
		UiPolishScript.install_focus_frame(card)
		_candidate_cards.append(card)


func _configure_focus_graph() -> void:
	var controls: Dictionary = {"FR": _rarity}
	var graph: Dictionary = {}
	var tab_order := PackedStringArray(["FR"])
	for index: int in range(_material_slots.size()):
		var focus_id := "F%d" % index
		controls[focus_id] = _material_slots[index]
		tab_order.append(focus_id)
	for index: int in range(_candidate_cards.size()):
		var focus_id := "FC%d" % index
		controls[focus_id] = _candidate_cards[index]
		tab_order.append(focus_id)
	for index: int in range(4):
		var focus_id := "FA%d" % index
		controls[focus_id] = _action_control(index)
		tab_order.append(focus_id)
	graph["FR"] = _graph_entry("FA3", "F0", "FR", "FR")
	for slot_index: int in range(_material_slots.size()):
		var focus_id := "F%d" % slot_index
		var below: String = _candidate_id_for_material(slot_index)
		if below.is_empty():
			below = _action_id_for_material(slot_index)
		graph[focus_id] = _graph_entry(
			"FR",
			below,
			"F%d" % posmod(slot_index - 1, MATERIAL_COUNT),
			"F%d" % ((slot_index + 1) % MATERIAL_COUNT),
		)
	for index: int in range(_candidate_cards.size()):
		var focus_id := "FC%d" % index
		var row: int = floori(float(index) / float(CANDIDATE_COLUMNS))
		var column: int = index % CANDIDATE_COLUMNS
		var row_start: int = row * CANDIDATE_COLUMNS
		var row_size: int = mini(CANDIDATE_COLUMNS, _candidate_cards.size() - row_start)
		var top: String
		if row == 0:
			top = _material_id_for_candidate_column(column)
		else:
			top = "FC%d" % (index - CANDIDATE_COLUMNS)
		var bottom: String = (
			"FC%d" % (index + CANDIDATE_COLUMNS)
			if index + CANDIDATE_COLUMNS < _candidate_cards.size()
			else _action_id_for_candidate_column(column)
		)
		graph[focus_id] = _graph_entry(
			top,
			bottom,
			"FC%d" % (row_start + posmod(column - 1, row_size)),
			"FC%d" % (row_start + (column + 1) % row_size),
		)
	for index: int in range(4):
		var focus_id := "FA%d" % index
		var top: String = _last_candidate_id_for_action(index)
		if top.is_empty():
			top = _material_id_for_action(index)
		graph[focus_id] = _graph_entry(
			top,
			"FR",
			"FA%d" % posmod(index - 1, 4),
			"FA%d" % ((index + 1) % 4),
		)
	_focus_controller.configure_graph(controls, graph, "FR", tab_order)


func _candidate_id_for_material(material_index: int) -> String:
	if _candidate_cards.is_empty():
		return ""
	var preferred_columns: Array[int] = [0, 3, 6]
	return "FC%d" % mini(preferred_columns[material_index], _candidate_cards.size() - 1)


func _last_candidate_id_for_action(action_index: int) -> String:
	if _candidate_cards.is_empty():
		return ""
	var column: int = action_index * 2
	var last_row: int = floori(
		float(_candidate_cards.size() - 1) / float(CANDIDATE_COLUMNS)
	)
	var index: int = last_row * CANDIDATE_COLUMNS + column
	if index >= _candidate_cards.size():
		index = _candidate_cards.size() - 1
	return "FC%d" % index


func _material_id_for_candidate_column(column: int) -> String:
	if column <= 1:
		return "F0"
	if column <= 4:
		return "F1"
	return "F2"


func _action_id_for_candidate_column(column: int) -> String:
	return "FA%d" % mini(floori(float(column) / 2.0), 3)


func _action_id_for_material(material_index: int) -> String:
	return ["FA0", "FA2", "FA3"][material_index]


func _material_id_for_action(action_index: int) -> String:
	return ["F0", "F1", "F1", "F2"][action_index]


func _action_control(index: int) -> Control:
	return [_auto_fill, _wild_toggle, _confirm, _cancel][index] as Control


func _graph_entry(top: String, bottom: String, left: String, right: String) -> Dictionary:
	return {
		FocusController.DIRECTION_TOP: top,
		FocusController.DIRECTION_BOTTOM: bottom,
		FocusController.DIRECTION_LEFT: left,
		FocusController.DIRECTION_RIGHT: right,
	}


func _candidate_tooltip_payload(item_id: String) -> Dictionary:
	var index: int = _candidate_item_ids.find(item_id)
	if index < 0 or index >= _candidate_entries.size():
		return {}
	return {
		"details": str(_candidate_entries[index].get("details", "")),
		"warning": "",
		"urgent": false,
	}


func _material_tooltip_payload(slot_index: int) -> Dictionary:
	if slot_index < 0 or slot_index >= _material_entries.size():
		return {}
	var item: ItemInstance = _material_entries[slot_index].get("item") as ItemInstance
	if item == null:
		return {}
	return {
		"details": str(_material_entries[slot_index].get("details", "")),
		"warning": "",
		"urgent": _item_drag_is_active(),
	}


func _item_drag_is_active() -> bool:
	var viewport: Viewport = get_viewport()
	if viewport == null or not viewport.gui_is_dragging():
		return false
	var drag_data: Variant = viewport.gui_get_drag_data()
	if not drag_data is Dictionary:
		return false
	return StringName((drag_data as Dictionary).get("drag_type", &"")) == &"item"


func _on_candidate_focused(card: Control) -> void:
	_ensure_candidate_visible.bind(card).call_deferred()


func _ensure_candidate_visible(card: Control) -> void:
	if card != null and is_instance_valid(card) and card.is_inside_tree():
		_candidate_scroll.ensure_control_visible(card)


func _presentation_snapshots(cards: Array[InventoryCardButton]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for card: InventoryCardButton in cards:
		var snapshot: Dictionary = card.presentation_snapshot()
		snapshot["minimum_size"] = card.custom_minimum_size
		result.append(snapshot)
	return result


func _activate_focus_id(focus_id: String) -> void:
	if focus_id == "FR":
		_on_rarity_pressed()
	elif focus_id.begins_with("FC"):
		var index: int = focus_id.trim_prefix("FC").to_int()
		if index >= 0 and index < _candidate_item_ids.size():
			candidate_toggled.emit(_candidate_item_ids[index])
	elif focus_id.begins_with("F") and focus_id.length() == 2:
		material_slot_pressed.emit(focus_id.trim_prefix("F").to_int())
	elif focus_id.begins_with("FA"):
		match focus_id.trim_prefix("FA").to_int():
			0: auto_fill_requested.emit()
			1: wild_toggle_requested.emit()
			2: confirm_requested.emit()
			3: _cancel_dialog()


func _on_rarity_pressed() -> void:
	rarity_step_requested.emit(1)


func _on_candidate_pressed(item_id: String) -> void:
	candidate_toggled.emit(item_id)


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
