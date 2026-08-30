class_name InventoryScreen
extends Control


signal item_move_requested(source: Dictionary, target: Dictionary)
signal item_lock_requested(item_id: String)
signal sort_requested
signal discard_requested(item_ids: PackedStringArray)
signal fusion_requested(material_ids: PackedStringArray)
signal continue_requested

const EQUIPMENT_COUNT: int = 6
const INVENTORY_COLUMNS: int = 6
const INVENTORY_ROWS: int = 6
const INVENTORY_COUNT: int = INVENTORY_COLUMNS * INVENTORY_ROWS
const NORMAL_ITEM_CARD_SIZE := Vector2(76.0, 76.0)
const LARGE_ITEM_CARD_SIZE := Vector2(96.0, 96.0)
const InventoryItemVisualsScript := preload("res://src/ui/inventory_item_visuals.gd")
const AFFIX_LABELS: Dictionary = {
	&"damage_pct": "与ダメージ",
	&"attack_speed_pct": "攻撃速度",
	&"area_pct": "効果範囲",
	&"pierce": "貫通数",
	&"max_hp": "最大HP",
	&"damage_reduction_pct": "被ダメージ軽減",
	&"move_speed_pct": "移動速度",
}
const PERCENT_AFFIX_IDS: Array[StringName] = [
	&"damage_pct",
	&"attack_speed_pct",
	&"area_pct",
	&"damage_reduction_pct",
	&"move_speed_pct",
]
const ACTION_LABELS: Array[String] = [
	"ロック切替\n実行 A／Enter",
	"廃棄\n実行 A／Enter",
	"合成\n実行 A／Enter",
	"高レア順に整理\n実行 A／Enter",
	"次戦／結果へ\n実行 A／Enter",
	"設定\n実行 A／Enter",
]

@onready var _wave_label: Label = %InventoryWave
@onready var _count_label: Label = %InventoryCounts
@onready var _status_label: Label = %InventoryStatus
@onready var _equip_row: HBoxContainer = %EquipRow
@onready var _grid: GridContainer = %InventoryGrid
@onready var _overflow_panel: Control = %OverflowPanel
@onready var _overflow_scroll: ScrollContainer = %OverflowScroll
@onready var _overflow_row: HBoxContainer = %OverflowRow
@onready var _action_row: HBoxContainer = %ActionRow
@onready var _content_root: Control = $Margin
@onready var _settings_overlay: SettingsOverlay = %SettingsOverlay
@onready var _fusion_dialog: FusionDialog = %FusionDialog
@onready var _confirmation_dialog: JarjarConfirmationDialog = %ConfirmationDialog
@onready var _item_tooltip: InventoryItemTooltip = %InventoryItemTooltip

var _controller := InventoryController.new()
var _focus_controller := FocusController.new()
var _modal_focus := ModalFocusCoordinator.new()
var _pending_state: RunState = null
var _pending_catalog: DefinitionCatalog = null
var _equip_cards: Array[InventoryCardButton] = []
var _grid_cards: Array[InventoryCardButton] = []
var _overflow_cards: Array[InventoryCardButton] = []
var _action_buttons: Array[Button] = []
var _locations_by_focus_id: Dictionary[String, Dictionary] = {}
var _last_valid_focus_id: String = "equip_0"
var _status_text: String = ""
var _pending_discard_ids := PackedStringArray()
var _pointer_event_count: int = 0


func _ready() -> void:
	_build_fixed_controls()
	_connect_overlays()
	_modal_focus.configure(get_viewport(), [_content_root])
	_item_tooltip.begin_session()
	if _pending_state != null:
		_controller.initialize(_pending_state, _pending_catalog)
	_refresh_from_state(false)


func initialize(state: RunState, catalog: DefinitionCatalog) -> void:
	_pending_state = state
	_pending_catalog = catalog
	if is_node_ready():
		_controller.initialize(state, catalog)
		_refresh_from_state(false)


func refresh_from_state(preserve_focus: bool = true) -> void:
	_refresh_from_state(preserve_focus)


func apply_command_result(command_kind: StringName, result: Dictionary) -> void:
	var success: bool = bool(result.get("success", false))
	_status_text = str(result.get("message", ""))
	if _status_text.is_empty() and not success:
		_status_text = str(result.get("error", "操作に失敗しました"))
	if command_kind == &"item_move" and success:
		_controller.complete_lift()
	if command_kind == &"fusion":
		if success:
			_controller.complete_fusion_success("合成成功")
		else:
			_controller.set_fusion_result_status(_status_text)
	_refresh_from_state(true)
	if _fusion_dialog.visible:
		_refresh_fusion_dialog()


func focus_ids() -> PackedStringArray:
	return _fusion_dialog.focus_ids() if _fusion_dialog.visible else _focus_controller.focus_ids()


func focus_control(focus_id: String) -> Control:
	return _fusion_dialog.focus_control(focus_id) if _fusion_dialog.visible else _focus_controller.control_for_id(focus_id)


func neighbor_specification(focus_id: String) -> Dictionary:
	return _fusion_dialog.neighbor_specification(focus_id) if _fusion_dialog.visible else _focus_controller.neighbor_specification(focus_id)


func initial_focus_control() -> Control:
	return _equip_cards[0] if not _equip_cards.is_empty() else null


func item_card_presentation(focus_id: String) -> Dictionary:
	var card := _focus_controller.control_for_id(focus_id) as InventoryCardButton
	return card.presentation_snapshot() if card != null else {}


func debug_state() -> Dictionary:
	return {
		"focus_id": _focus_controller.current_focus_id(get_viewport()),
		"pointer_event_count": _pointer_event_count,
		"status": _status_text,
		"tooltip": _item_tooltip.debug_snapshot(),
		"overflow_count": _overflow_cards.size(),
		"overflow_scroll": _overflow_scroll.scroll_horizontal,
		"fusion_open": _fusion_dialog.visible,
		"confirmation_open": _confirmation_dialog.visible,
		"settings_open": _settings_overlay.visible,
		"modal_stack_size": _modal_focus.stack_size(),
		"held_item_source": _controller.held_item_source.duplicate(true),
		"equipment_slot_count": _equip_cards.size(),
		"inventory_slot_count": _grid_cards.size(),
	}


func test_focus(focus_id: String) -> bool:
	_item_tooltip.activate_focus_input()
	return _fusion_dialog.test_focus(focus_id) if _fusion_dialog.visible else _focus_controller.grab_focus_id(focus_id)


func test_direction(direction: StringName) -> bool:
	_item_tooltip.activate_focus_input()
	return _fusion_dialog.test_direction(direction) if _fusion_dialog.visible else _focus_controller.move(get_viewport(), direction)


func test_accept() -> void:
	if _fusion_dialog.visible:
		_fusion_dialog.test_accept()
		return
	var control: Control = get_viewport().gui_get_focus_owner()
	if control is BaseButton and not (control as BaseButton).disabled:
		(control as BaseButton).pressed.emit()


func _input(event: InputEvent) -> void:
	if _modal_focus.has_active_modal():
		return
	if event.is_action_pressed(&"ui_cancel") and not event.is_echo():
		if not _controller.held_item_source.is_empty():
			_controller.cancel_lift()
			_status_text = "移動を取り消しました"
			_refresh_from_state(true)
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


func _build_fixed_controls() -> void:
	for slot_value: int in GameTypes.EquipmentSlot.values():
		var column := VBoxContainer.new()
		column.custom_minimum_size = Vector2(142.0, 124.0)
		var label := Label.new()
		label.text = InventoryItemVisualsScript.slot_label(slot_value)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override(&"font_size", 18)
		column.add_child(label)
		var card := _new_item_card("equip_%d" % slot_value, LARGE_ITEM_CARD_SIZE)
		column.add_child(card)
		_equip_row.add_child(column)
		_equip_cards.append(card)
	for index: int in range(INVENTORY_COUNT):
		var card := _new_item_card("grid_%d" % index, NORMAL_ITEM_CARD_SIZE)
		_grid.add_child(card)
		_grid_cards.append(card)
	for index: int in range(ACTION_LABELS.size()):
		var button := Button.new()
		button.custom_minimum_size = Vector2(220.0, 58.0)
		button.text = ACTION_LABELS[index]
		button.pressed.connect(_on_action_pressed.bind(index))
		_action_row.add_child(button)
		_action_buttons.append(button)


func _new_item_card(focus_id: String, minimum_size: Vector2) -> InventoryCardButton:
	var card := InventoryCardButton.new()
	card.custom_minimum_size = minimum_size
	card.pressed.connect(_on_item_card_pressed.bind(focus_id))
	card.pointer_event.connect(_on_pointer_event)
	card.drop_received.connect(_on_item_drop_received)
	card.focus_entered.connect(_on_item_focused.bind(focus_id))
	_item_tooltip.bind_target(card, _tooltip_payload.bind(focus_id))
	return card


func _connect_overlays() -> void:
	_fusion_dialog.rarity_step_requested.connect(_on_fusion_rarity_step)
	_fusion_dialog.material_slot_pressed.connect(_on_fusion_material_slot_pressed)
	_fusion_dialog.material_drag_removed.connect(_on_fusion_material_slot_pressed)
	_fusion_dialog.material_item_dropped.connect(_on_fusion_material_dropped)
	_fusion_dialog.candidate_toggled.connect(_on_fusion_candidate_toggled)
	_fusion_dialog.auto_fill_requested.connect(_on_fusion_auto_fill)
	_fusion_dialog.confirm_requested.connect(_on_fusion_confirm)
	_fusion_dialog.cancelled.connect(_on_fusion_cancelled)
	_fusion_dialog.pointer_event.connect(_on_pointer_event)
	_confirmation_dialog.confirmed.connect(_on_discard_confirmed)
	_confirmation_dialog.cancelled.connect(_on_confirmation_cancelled)
	_settings_overlay.closed.connect(_on_settings_closed)


func _refresh_from_state(preserve_focus: bool) -> void:
	if not is_node_ready() or _controller.state == null:
		return
	var preserved_focus_id: String = (
		_focus_controller.current_focus_id(get_viewport()) if preserve_focus else ""
	)
	_locations_by_focus_id.clear()
	_wave_label.text = "INVENTORY　WAVE %d" % _controller.state.wave_number
	var stored_count: int = 0
	for item: ItemInstance in _controller.state.inventory:
		if item != null:
			stored_count += 1
	_count_label.text = "通常枠 %d / %d　　一時受取 %d" % [stored_count, RunState.INVENTORY_CAPACITY, _controller.state.overflow.size()]
	_status_label.text = _status_text
	for slot_value: int in GameTypes.EquipmentSlot.values():
		var focus_id := "equip_%d" % slot_value
		var item: ItemInstance = _controller.state.equipped.get(slot_value) as ItemInstance
		_configure_card(_equip_cards[slot_value], focus_id, &"equipped", slot_value, item)
	for index: int in range(INVENTORY_COUNT):
		var focus_id := "grid_%d" % index
		_configure_card(_grid_cards[index], focus_id, &"inventory", index, _controller.state.inventory[index])
	_rebuild_overflow_cards()
	_configure_focus_graph()
	_update_action_states()
	_item_tooltip.refresh_active()
	if preserve_focus and not preserved_focus_id.is_empty() and _focus_controller.grab_focus_id(preserved_focus_id):
		return
	_focus_controller.set_initial_focus_id(_last_valid_focus_id)
	_focus_controller.focus_initial_deferred()


func _configure_card(
	card: InventoryCardButton,
	focus_id: String,
	kind: StringName,
	index: int,
	item: ItemInstance,
) -> void:
	var location: Dictionary = {"kind": kind, "index": index, "item": item}
	_locations_by_focus_id[focus_id] = location
	var card_accessibility_name: String = _card_accessibility_name(kind, index, item)
	var details: String = _item_details(item) if item != null else _empty_details(kind, index)
	var accessibility_details: String = details + "\n操作: A／Enterまたはクリックで持ち上げ、移動先で決定"
	card.configure_item_visual(
		InventoryItemVisualsScript.icon_for_item(item) if item != null else _empty_icon(kind, index),
		item.rarity if item != null else -2,
		item.locked if item != null else false,
		"移" if item != null and item.item_id == str(_controller.held_item_source.get("item_id", "")) else "",
		item == null,
		card_accessibility_name,
		accessibility_details,
	)
	card.configure_drag(
		{"drag_type": &"item", "kind": kind, "index": index, "item_id": item.item_id if item != null else ""},
		{"kind": kind, "index": index},
		item != null,
		&"item",
	)


func _rebuild_overflow_cards() -> void:
	for card: InventoryCardButton in _overflow_cards:
		_item_tooltip.unbind_target(card)
		card.queue_free()
	_overflow_cards.clear()
	_overflow_panel.visible = not _controller.state.overflow.is_empty()
	for index: int in range(_controller.state.overflow.size()):
		var focus_id := "overflow_%d" % index
		var card := _new_item_card(focus_id, LARGE_ITEM_CARD_SIZE)
		_overflow_row.add_child(card)
		_overflow_cards.append(card)
		_configure_card(card, focus_id, &"overflow", index, _controller.state.overflow[index])


func _configure_focus_graph() -> void:
	var controls: Dictionary = {}
	var graph: Dictionary = {}
	var order := PackedStringArray()
	for column: int in range(EQUIPMENT_COUNT):
		var focus_id := "equip_%d" % column
		controls[focus_id] = _equip_cards[column]
		order.append(focus_id)
		graph[focus_id] = _focus_graph_entry(
			"action_%d" % column,
			"grid_%d" % column,
			"equip_%d" % posmod(column - 1, EQUIPMENT_COUNT),
			"equip_%d" % ((column + 1) % EQUIPMENT_COUNT),
		)
	for index: int in range(_grid_cards.size()):
		var row: int = floori(float(index) / float(INVENTORY_COLUMNS))
		var column: int = index % INVENTORY_COLUMNS
		var focus_id := "grid_%d" % index
		controls[focus_id] = _grid_cards[index]
		order.append(focus_id)
		var top: String = (
			"equip_%d" % column
			if row == 0
			else "grid_%d" % (index - INVENTORY_COLUMNS)
		)
		var bottom: String
		if row < INVENTORY_ROWS - 1:
			bottom = "grid_%d" % (index + INVENTORY_COLUMNS)
		elif not _overflow_cards.is_empty():
			bottom = "overflow_%d" % mini(column, _overflow_cards.size() - 1)
		else:
			bottom = "action_%d" % column
		graph[focus_id] = _focus_graph_entry(
			top,
			bottom,
			"grid_%d" % (row * INVENTORY_COLUMNS + posmod(column - 1, INVENTORY_COLUMNS)),
			"grid_%d" % (row * INVENTORY_COLUMNS + (column + 1) % INVENTORY_COLUMNS),
		)
	for index: int in range(_overflow_cards.size()):
		var column: int = mini(index, INVENTORY_COLUMNS - 1)
		var focus_id := "overflow_%d" % index
		controls[focus_id] = _overflow_cards[index]
		order.append(focus_id)
		graph[focus_id] = _focus_graph_entry(
			"grid_%d" % ((INVENTORY_ROWS - 1) * INVENTORY_COLUMNS + column),
			"action_%d" % column,
			"overflow_%d" % posmod(index - 1, _overflow_cards.size()),
			"overflow_%d" % ((index + 1) % _overflow_cards.size()),
		)
	for column: int in range(_action_buttons.size()):
		var focus_id := "action_%d" % column
		controls[focus_id] = _action_buttons[column]
		order.append(focus_id)
		var top: String = (
			"overflow_%d" % mini(column, _overflow_cards.size() - 1)
			if not _overflow_cards.is_empty()
			else "grid_%d" % ((INVENTORY_ROWS - 1) * INVENTORY_COLUMNS + column)
		)
		graph[focus_id] = _focus_graph_entry(
			top,
			"equip_%d" % column,
			"action_%d" % posmod(column - 1, _action_buttons.size()),
			"action_%d" % ((column + 1) % _action_buttons.size()),
		)
	_focus_controller.configure_graph(controls, graph, "equip_0", order)


func _focus_graph_entry(top: String, bottom: String, left: String, right: String) -> Dictionary:
	return {
		FocusController.DIRECTION_TOP: top,
		FocusController.DIRECTION_BOTTOM: bottom,
		FocusController.DIRECTION_LEFT: left,
		FocusController.DIRECTION_RIGHT: right,
	}


func _update_action_states() -> void:
	var item: ItemInstance = _focused_item()
	_action_buttons[0].disabled = item == null
	_action_buttons[1].disabled = item == null or _focused_kind() == &"equipped" or item.locked
	_action_buttons[2].disabled = not _controller.has_fusion_material_set()
	_action_buttons[4].disabled = not _controller.state.overflow.is_empty()


func _on_item_card_pressed(focus_id: String) -> void:
	var location: Dictionary = _locations_by_focus_id.get(focus_id, {}) as Dictionary
	if location.is_empty():
		return
	var item: ItemInstance = location.get("item") as ItemInstance
	if _controller.held_item_source.is_empty():
		if item == null:
			return
		_controller.set_last_item_focus(item.item_id)
		_controller.begin_item_lift(StringName(location["kind"]), int(location["index"]))
		_status_text = "%s を移動中。移動先を選択してください" % item.display_name
		_refresh_from_state(true)
		return
	var request: Dictionary = _controller.item_move_request(
		StringName(location["kind"]),
		int(location["index"]),
	)
	if request.is_empty():
		return
	item_move_requested.emit(request["source"], request["target"])


func _on_item_drop_received(source: Dictionary, target: Dictionary) -> void:
	item_move_requested.emit(source, target)


func _on_item_focused(focus_id: String) -> void:
	_last_valid_focus_id = focus_id
	var location: Dictionary = _locations_by_focus_id.get(focus_id, {}) as Dictionary
	var item: ItemInstance = location.get("item") as ItemInstance
	if item != null:
		_controller.set_last_item_focus(item.item_id)
	_update_action_states()


func _on_action_pressed(index: int) -> void:
	match index:
		0:
			var item: ItemInstance = _focused_item()
			if item != null:
				item_lock_requested.emit(item.item_id)
		1:
			_request_discard()
		2:
			_open_fusion_dialog()
		3:
			sort_requested.emit()
		4:
			continue_requested.emit()
		5:
			_open_settings()


func _request_discard() -> void:
	var item: ItemInstance = _focused_item()
	if item == null or _focused_kind() == &"equipped" or item.locked:
		return
	_pending_discard_ids = PackedStringArray([item.item_id])
	if not _modal_focus.push(_confirmation_dialog, _action_buttons[1]):
		return
	_confirmation_dialog.open_dialog("廃棄確認", "%s を廃棄します。" % item.display_name, "廃棄", "action_1")


func _on_discard_confirmed() -> void:
	_modal_focus.pop(_confirmation_dialog, null, _action_buttons[1])
	if not _pending_discard_ids.is_empty():
		discard_requested.emit(_pending_discard_ids.duplicate())
	_pending_discard_ids = PackedStringArray()


func _on_confirmation_cancelled() -> void:
	_modal_focus.pop(_confirmation_dialog, null, _action_buttons[1])
	_pending_discard_ids = PackedStringArray()


func _open_fusion_dialog() -> void:
	_controller.open_fusion()
	if not _modal_focus.push(_fusion_dialog, _action_buttons[2]):
		_controller.reset_fusion()
		return
	_fusion_dialog.open_dialog("action_2")
	_refresh_fusion_dialog()
	_fusion_dialog.focus_initial_deferred()


func _refresh_fusion_dialog() -> void:
	if not _fusion_dialog.visible:
		return
	var material_entries: Array[Dictionary] = []
	for index: int in range(3):
		var item: ItemInstance = null
		var item_id: String = ""
		if index < _controller.fusion_material_ids.size():
			item_id = _controller.fusion_material_ids[index]
			item = _controller.find_item(item_id).get("item") as ItemInstance
		material_entries.append({
			"slot_index": index,
			"item_id": item_id,
			"item": item,
			"accessibility_name": "合成材料%d、%s" % [index + 1, item.display_name if item != null else "空き"],
			"details": _item_details(item) if item != null else "合成材料枠%d\n空き" % (index + 1),
		})
	var candidates: Array[Dictionary] = []
	for location: Dictionary in _controller.fusion_candidate_locations():
		var item: ItemInstance = location.get("item") as ItemInstance
		candidates.append({
			"item_id": item.item_id,
			"item": item,
			"source": {"kind": location["kind"], "index": location["index"]},
			"material_number": _controller.fusion_material_ids.find(item.item_id) + 1,
			"accessibility_name": "合成候補、%s" % item.display_name,
			"details": _item_details(item),
		})
	_fusion_dialog.update_view(
		_controller.rarity_label(_controller.fusion_rarity),
		material_entries,
		_controller.fusion_is_valid(),
		_controller.fusion_preview_text(),
		_controller.fusion_status,
		candidates,
	)


func _on_fusion_rarity_step(step: int) -> void:
	_controller.change_fusion_rarity(step)
	_refresh_fusion_dialog()


func _on_fusion_material_slot_pressed(slot_index: int) -> void:
	_controller.remove_fusion_material(slot_index)
	_refresh_fusion_dialog()


func _on_fusion_material_dropped(source: Dictionary, slot_index: int) -> void:
	var item_id: String = str(source.get("item_id", ""))
	if item_id.is_empty():
		return
	_controller.replace_fusion_material(slot_index, item_id)
	_refresh_fusion_dialog()


func _on_fusion_candidate_toggled(item_id: String) -> void:
	_controller.toggle_fusion_material(item_id)
	_refresh_fusion_dialog()


func _on_fusion_auto_fill() -> void:
	_controller.auto_fill_fusion()
	_refresh_fusion_dialog()


func _on_fusion_confirm() -> void:
	if _controller.fusion_is_valid():
		fusion_requested.emit(_controller.fusion_material_ids.duplicate())


func _on_fusion_cancelled() -> void:
	_controller.reset_fusion()
	_modal_focus.pop(_fusion_dialog, null, _action_buttons[2])


func _open_settings() -> void:
	if _modal_focus.push(_settings_overlay, _action_buttons[5]):
		_settings_overlay.open_overlay()


func _on_settings_closed() -> void:
	_modal_focus.pop(_settings_overlay, null, _action_buttons[5])


func _tooltip_payload(focus_id: String) -> Dictionary:
	var location: Dictionary = _locations_by_focus_id.get(focus_id, {}) as Dictionary
	if location.is_empty():
		return {}
	var target_item: ItemInstance = location.get("item") as ItemInstance
	if _controller.held_item_source.is_empty():
		return {"details": _item_details(target_item) if target_item != null else _empty_details(StringName(location["kind"]), int(location["index"])), "warning": ""}
	var source_item: ItemInstance = _controller.item_at(
		StringName(_controller.held_item_source.get("kind", &"")),
		int(_controller.held_item_source.get("index", -1)),
	)
	if source_item == null:
		return {}
	var comparison: String = "移動後: %s" % source_item.display_name
	if target_item != null:
		comparison += " ↔ %s" % target_item.display_name
	var source_kind := StringName(_controller.held_item_source["kind"])
	var source_index: int = int(_controller.held_item_source["index"])
	var target_kind := StringName(location["kind"])
	var target_index: int = int(location["index"])
	var validation: Dictionary = InventoryService.validate_move(
		_controller.state,
		source_kind,
		source_index,
		target_kind,
		target_index,
	)
	if not bool(validation.get("success", false)):
		return {"details": comparison, "warning": str(validation.get("message", "配置できません")), "urgent": true}
	if source_kind == &"equipped" and source_kind == target_kind and source_index == target_index:
		comparison += "\n" + _removal_comparison_details(source_item)
	elif target_kind == &"equipped":
		comparison += "\n" + _comparison_details(source_item, target_index)
	elif source_kind == &"equipped":
		comparison += "\n" + (
			_comparison_details(target_item, source_index)
			if target_item != null
			else _removal_comparison_details(source_item)
		)
	else:
		comparison += "\n装備性能は変化しません"
	return {"details": comparison, "warning": "", "urgent": true}


func _comparison_details(candidate: ItemInstance, target_slot: int) -> String:
	var result: Dictionary = InventoryService.compare_item(
		_controller.state,
		candidate.item_id,
		target_slot as GameTypes.EquipmentSlot,
		_controller.catalog,
	)
	if not bool(result.get("success", false)):
		return ""
	if candidate.category == GameTypes.ItemCategory.WEAPON:
		return "基礎ダメージ %.0f → %.0f" % [float(result.get("equipped_damage", 0.0)), float(result.get("candidate_damage", 0.0))]
	var lines := PackedStringArray()
	var deltas: Dictionary = result.get("deltas", {}) as Dictionary
	for affix_id: StringName in StatCalculator.AFFIX_IDS:
		var delta: float = float(deltas.get(affix_id, 0.0))
		if is_zero_approx(delta):
			continue
		lines.append("%s %+.0f%s" % [AFFIX_LABELS.get(affix_id, String(affix_id)), delta, "%" if affix_id in PERCENT_AFFIX_IDS else ""])
	return "補正差分なし" if lines.is_empty() else "\n".join(lines)


func _removal_comparison_details(current: ItemInstance) -> String:
	if current.category == GameTypes.ItemCategory.WEAPON:
		var definition: WeaponDefinition = _controller.catalog.weapon_for_type(current.weapon_type)
		var current_damage: float = definition.damage_for_rarity(current.rarity) if definition != null else 0.0
		return "基礎ダメージ %.0f → 0" % current_damage
	var lines := PackedStringArray()
	for affix: AffixRoll in current.affixes:
		lines.append("%s %+.0f%s" % [
			AFFIX_LABELS.get(affix.affix_id, String(affix.affix_id)),
			-affix.value,
			"%" if affix.affix_id in PERCENT_AFFIX_IDS else "",
		])
	return "補正差分なし" if lines.is_empty() else "\n".join(lines)


func _item_details(item: ItemInstance) -> String:
	if item == null:
		return "空き"
	var lines := PackedStringArray([
		item.display_name,
		"%s　%s" % [_rarity_label(item.rarity), InventoryItemVisualsScript.item_type_label(item)],
	])
	if item.category == GameTypes.ItemCategory.WEAPON:
		var definition: WeaponDefinition = _controller.catalog.weapon_for_type(item.weapon_type)
		if definition != null:
			lines.append("基礎ダメージ %.0f" % definition.damage_for_rarity(item.rarity))
			lines.append("基準間隔 %.2f秒　射程 %.2fm" % [definition.base_interval, definition.range_m])
			match item.weapon_type:
				GameTypes.WeaponType.BOW:
					lines.append("直線弾")
				GameTypes.WeaponType.STAFF:
					lines.append("爆発半径 %.2fm" % definition.aoe_radius)
				GameTypes.WeaponType.SWORD:
					lines.append("扇角 %.0f度" % definition.arc_degrees)
	else:
		for affix: AffixRoll in item.affixes:
			lines.append("%s +%.0f%s" % [AFFIX_LABELS.get(affix.affix_id, String(affix.affix_id)), affix.value, "%" if affix.affix_id in PERCENT_AFFIX_IDS else ""])
	if item.locked:
		lines.append("ロック中")
	return "\n".join(lines)


func _empty_details(kind: StringName, index: int) -> String:
	if kind == &"equipped":
		return "%s\n空き" % InventoryItemVisualsScript.slot_label(index)
	return "空き"


func _empty_icon(kind: StringName, index: int) -> Texture2D:
	return InventoryItemVisualsScript.icon_for_slot(index) if kind == &"equipped" else null


func _card_accessibility_name(kind: StringName, index: int, item: ItemInstance) -> String:
	var prefix: String = InventoryItemVisualsScript.slot_label(index) if kind == &"equipped" else "保管枠"
	return "%s、%s" % [prefix, item.display_name if item != null else "空き"]


func _focused_location() -> Dictionary:
	var focus_id: String = _focus_controller.current_focus_id(get_viewport())
	if not _locations_by_focus_id.has(focus_id):
		focus_id = _last_valid_focus_id
	return _locations_by_focus_id.get(focus_id, {}) as Dictionary


func _focused_item() -> ItemInstance:
	return _focused_location().get("item") as ItemInstance


func _focused_kind() -> StringName:
	return StringName(_focused_location().get("kind", &""))


func _on_pointer_event() -> void:
	_pointer_event_count += 1
	_item_tooltip.activate_pointer_input()


func _rarity_label(rarity: GameTypes.Rarity) -> String:
	match rarity:
		GameTypes.Rarity.RARE:
			return "RARE"
		GameTypes.Rarity.EPIC:
			return "EPIC"
		GameTypes.Rarity.LEGENDARY:
			return "LEGENDARY"
	return "COMMON"
