class_name InventoryScreen
extends Control


signal item_move_requested(source: Dictionary, target: Dictionary)
signal item_lock_requested(item_id: String)
signal discard_requested(item_ids: PackedStringArray, unique_confirmed: bool)
signal fusion_requested(
	material_ids: PackedStringArray,
	use_wild: bool,
	unique_confirmed: bool,
)
signal skill_move_requested(
	source_kind: StringName,
	source_id: Variant,
	target_kind: StringName,
	target_id: Variant,
)
signal continue_requested

const EQUIPMENT_COUNT: int = 6
const INVENTORY_COLUMNS: int = 6
const INVENTORY_ROWS: int = 6
const INVENTORY_COUNT: int = INVENTORY_COLUMNS * INVENTORY_ROWS
const EVIDENCE_MODES: Array[String] = [
	"",
	"inventory_full",
	"fusion_unique_warning",
]
const ACTION_LABELS: Array[String] = [
	"一括選択",
	"廃棄",
	"合成",
	"ワイルド投入",
	"次戦／結果へ",
	"設定",
]

@onready var _wave_label: Label = %InventoryWave
@onready var _count_label: Label = %InventoryCounts
@onready var _status_label: Label = %InventoryStatus
@onready var _comparison_label: Label = %ComparisonText
@onready var _equip_row: HBoxContainer = %EquipRow
@onready var _grid: GridContainer = %InventoryGrid
@onready var _overflow_panel: Control = %OverflowPanel
@onready var _overflow_scroll: ScrollContainer = %OverflowScroll
@onready var _overflow_row: HBoxContainer = %OverflowRow
@onready var _action_row: HBoxContainer = %ActionRow
@onready var _skill_row: HBoxContainer = %SkillRow
@onready var _settings_overlay: SettingsOverlay = %SettingsOverlay
@onready var _bulk_dialog: BulkSelectDialog = %BulkSelectDialog
@onready var _fusion_dialog: FusionDialog = %FusionDialog
@onready var _confirmation_dialog: JarjarConfirmationDialog = %ConfirmationDialog

var _controller := InventoryController.new()
var _focus_controller := FocusController.new()
var _pending_state: RunState = null
var _pending_catalog: DefinitionCatalog = null

var _equip_cards: Array[InventoryCardButton] = []
var _grid_cards: Array[InventoryCardButton] = []
var _overflow_cards: Array[InventoryCardButton] = []
var _action_buttons: Array[Button] = []
var _skill_cards: Array[InventoryCardButton] = []

var _pointer_event_count: int = 0
var _status_text: String = ""
var _pending_command_kind: StringName = &""
var _confirmation_kind: StringName = &""
var _confirmation_payload: Dictionary = {}
var _confirmation_origin_focus_id: String = ""
var _last_valid_focus_id: String = "equip_0"
var _pending_evidence_mode: String = ""
var _evidence_mode: String = ""


func _ready() -> void:
	_build_fixed_controls()
	_connect_overlays()
	_settings_overlay.closed.connect(_on_settings_closed)
	if _pending_state != null:
		_controller.initialize(_pending_state, _pending_catalog)
	_refresh_from_state(false)
	_apply_pending_evidence_mode.call_deferred()


func initialize(state: RunState, catalog: DefinitionCatalog) -> void:
	_pending_state = state
	_pending_catalog = catalog
	if is_node_ready():
		_controller.initialize(state, catalog)
		_refresh_from_state(false)
		_apply_pending_evidence_mode.call_deferred()


func refresh_from_state(preserve_focus: bool = true) -> void:
	_refresh_from_state(preserve_focus)


func apply_command_result(command_kind: StringName, result: Dictionary) -> void:
	_pending_command_kind = &""
	var success: bool = bool(result.get("success", false))
	_status_text = str(result.get("message", result.get("error", "")))
	if bool(result.get("needs_unique_confirmation", false)):
		_open_confirmation_for_result(command_kind, result)
		return
	if success:
		match command_kind:
			&"item_move", &"skill_move":
				_controller.complete_lift()
			&"discard":
				_controller.clear_marks()
			&"fusion":
				_controller.reset_fusion()
				_fusion_dialog.close_without_signal()
	if command_kind == &"discard" and not success and StringName(result.get("error", &"")) in [
		&"missing",
		&"item_missing",
		&"target_missing",
	]:
		_controller.clear_marks()
	_refresh_from_state(true)
	if command_kind == &"discard":
		_focus_controller.grab_focus_id("action_1")
	elif command_kind == &"fusion":
		_focus_controller.grab_focus_id("action_2" if success else "FA2")


func set_evidence_mode(mode: String) -> bool:
	if not mode in EVIDENCE_MODES:
		return false
	_pending_evidence_mode = mode
	if is_node_ready() and _controller.state != null:
		return _apply_pending_evidence_mode()
	return true


func focus_ids() -> PackedStringArray:
	return _focus_controller.focus_ids()


func focus_control(focus_id: String) -> Control:
	return _focus_controller.control_for_id(focus_id)


func neighbor_specification(focus_id: String) -> Dictionary:
	return _focus_controller.neighbor_specification(focus_id)


func initial_focus_control() -> Control:
	return _equip_cards[0] if not _equip_cards.is_empty() else null


func debug_state() -> Dictionary:
	var result: Dictionary = _controller.debug_state()
	result.merge({
		"focus_id": _focus_controller.current_focus_id(get_viewport()),
		"pointer_event_count": _pointer_event_count,
		"status": _status_text,
		"comparison": _comparison_label.text,
		"overflow_count": _overflow_cards.size(),
		"overflow_scroll": _overflow_scroll.scroll_horizontal,
		"bulk_open": _bulk_dialog.visible,
		"fusion_open": _fusion_dialog.visible,
		"confirmation_open": _confirmation_dialog.visible,
		"settings_open": _settings_overlay.visible,
		"pending_command_kind": _pending_command_kind,
		"skill_slots": _skill_slot_snapshot(),
		"evidence_mode": _evidence_mode,
	}, true)
	return result


func test_focus(focus_id: String) -> bool:
	return _focus_controller.grab_focus_id(focus_id)


func test_direction(direction: StringName) -> bool:
	return _focus_controller.move(get_viewport(), direction)


func test_accept() -> void:
	_activate_focus_id(_focus_controller.current_focus_id(get_viewport()))


func test_cancel() -> void:
	_handle_cancel()


func test_lock() -> void:
	_handle_item_lock()


func test_mouse_drop(source: Dictionary, target: Dictionary) -> void:
	_pointer_event_count += 1
	_on_card_drop_received(source, target)


func test_open_bulk() -> void:
	_open_bulk_dialog()


func test_select_bulk(rarity: GameTypes.Rarity) -> void:
	_on_bulk_rarity_selected(rarity)


func test_confirm_dialog(confirm: bool) -> void:
	if not _confirmation_dialog.visible:
		return
	_confirmation_dialog.close_without_signal()
	if confirm:
		_on_confirmation_confirmed()
	else:
		_on_confirmation_cancelled()


func _apply_pending_evidence_mode() -> bool:
	if not is_node_ready() or _controller.state == null:
		return false
	var mode: String = _pending_evidence_mode
	_evidence_mode = mode
	_bulk_dialog.close_without_signal()
	_confirmation_dialog.close_without_signal()
	if mode == "":
		_controller.reset_fusion()
		_fusion_dialog.close_without_signal()
		_refresh_from_state(false)
		return true
	if mode == "inventory_full":
		_controller.reset_fusion()
		_fusion_dialog.close_without_signal()
		_status_text = "36枠満杯・一時受取 %d件" % _controller.state.overflow.size()
		_refresh_from_state(false)
		return (
			_count_inventory_items() == INVENTORY_COUNT
			and not _controller.state.overflow.is_empty()
		)
	var material_ids := PackedStringArray([
		"qa-inventory-18",
		"qa-inventory-19",
		"qa-inventory-33",
	])
	for item_id: String in material_ids:
		var item: ItemInstance = _controller.find_item(item_id).get("item") as ItemInstance
		if item == null or item.rarity != GameTypes.Rarity.RARE:
			return false
	_controller.open_fusion(false)
	_controller.fusion_rarity = GameTypes.Rarity.RARE
	for item_id: String in material_ids:
		if not _controller.toggle_fusion_material(item_id, true):
			return false
	_fusion_dialog.open_dialog("action_2")
	_render_fusion()
	_configure_fusion_focus_graph()
	_on_fusion_confirm()
	return _confirmation_dialog.visible


func _input(event: InputEvent) -> void:
	if _settings_overlay.visible or _bulk_dialog.visible or _confirmation_dialog.visible:
		return
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		_handle_cancel()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("item_lock") and not event.is_echo():
		_handle_item_lock()
		get_viewport().set_input_as_handled()
		return
	var focus_id: String = _focus_controller.current_focus_id(get_viewport())
	if _fusion_dialog.visible and focus_id == "FR" and (
		event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right")
	):
		return
	var direction: StringName = _direction_for_event(event)
	if not direction.is_empty():
		_focus_controller.move(get_viewport(), direction)
		_track_current_focus()
		get_viewport().set_input_as_handled()


func _build_fixed_controls() -> void:
	for index: int in range(EQUIPMENT_COUNT):
		var card: InventoryCardButton = _new_card(Vector2(210.0, 96.0))
		_equip_row.add_child(card)
		_equip_cards.append(card)
		_connect_item_card(card, &"equipped", index)
	for index: int in range(INVENTORY_COUNT):
		var card: InventoryCardButton = _new_card(Vector2(154.0, 76.0))
		_grid.add_child(card)
		_grid_cards.append(card)
		_connect_item_card(card, &"inventory", index)
	for index: int in range(ACTION_LABELS.size()):
		var button := Button.new()
		button.custom_minimum_size = Vector2(235.0, 58.0)
		button.focus_mode = Control.FOCUS_ALL
		button.text = ACTION_LABELS[index]
		button.pressed.connect(_on_action_pressed.bind(index))
		_action_row.add_child(button)
		_action_buttons.append(button)
	for index: int in range(6):
		var card: InventoryCardButton = _new_card(Vector2(235.0, 84.0))
		_skill_row.add_child(card)
		_skill_cards.append(card)
		card.pressed.connect(_on_skill_card_pressed.bind(index))
		card.drop_received.connect(_on_card_drop_received)
		card.pointer_event.connect(_on_pointer_event)
		card.focus_entered.connect(_on_focus_entered.bind("skill_%d" % index, ""))


func _connect_overlays() -> void:
	_bulk_dialog.rarity_selected.connect(_on_bulk_rarity_selected)
	_bulk_dialog.cancelled.connect(_on_bulk_cancelled)
	_fusion_dialog.rarity_step_requested.connect(_on_fusion_rarity_step)
	_fusion_dialog.material_slot_pressed.connect(_on_fusion_material_slot_pressed)
	_fusion_dialog.material_drag_removed.connect(_on_fusion_material_slot_pressed)
	_fusion_dialog.material_item_dropped.connect(_on_fusion_material_dropped)
	_fusion_dialog.auto_fill_requested.connect(_on_fusion_auto_fill)
	_fusion_dialog.wild_toggle_requested.connect(_on_fusion_wild_toggle)
	_fusion_dialog.confirm_requested.connect(_on_fusion_confirm)
	_fusion_dialog.cancelled.connect(_on_fusion_cancelled)
	_fusion_dialog.pointer_event.connect(_on_pointer_event)
	_confirmation_dialog.confirmed.connect(_on_confirmation_confirmed)
	_confirmation_dialog.cancelled.connect(_on_confirmation_cancelled)


func _refresh_from_state(preserve_focus: bool) -> void:
	if not is_node_ready():
		return
	var previous_focus: String = (
		_focus_controller.current_focus_id(get_viewport())
		if preserve_focus
		else ""
	)
	_render_header()
	_render_equipment()
	_render_inventory()
	_rebuild_overflow()
	_render_actions()
	_render_skills()
	_render_fusion()
	if _fusion_dialog.visible:
		_configure_fusion_focus_graph()
	else:
		_configure_normal_focus_graph()
	if preserve_focus and _focus_controller.grab_focus_id(previous_focus):
		_last_valid_focus_id = previous_focus
	else:
		_focus_controller.focus_initial_deferred()
	_track_current_focus.call_deferred()


func _render_header() -> void:
	var state: RunState = _controller.state
	_wave_label.text = "INVENTORY  •  WAVE %d 整理" % (state.wave_number if state != null else 0)
	_count_label.text = "通常枠 %d / 36　 一時受取 %d　 ワイルド %d" % [
		_count_inventory_items(),
		state.overflow.size() if state != null else 0,
		state.wild_material_count if state != null else 0,
	]
	_status_label.text = _status_text


func _render_equipment() -> void:
	for index: int in range(_equip_cards.size()):
		_render_item_card(_equip_cards[index], &"equipped", index, "E%d" % index)


func _render_inventory() -> void:
	for index: int in range(_grid_cards.size()):
		_render_item_card(_grid_cards[index], &"inventory", index, "G%d,%d" % [
			floori(float(index) / float(INVENTORY_COLUMNS)),
			index % INVENTORY_COLUMNS,
		])


func _rebuild_overflow() -> void:
	for child: Node in _overflow_row.get_children():
		_overflow_row.remove_child(child)
		child.queue_free()
	_overflow_cards.clear()
	var state: RunState = _controller.state
	var overflow_count: int = state.overflow.size() if state != null else 0
	_overflow_panel.visible = overflow_count > 0
	for index: int in range(overflow_count):
		var card: InventoryCardButton = _new_card(Vector2(144.0, 104.0))
		_overflow_row.add_child(card)
		_overflow_cards.append(card)
		_connect_item_card(card, &"overflow", index)
		_render_item_card(card, &"overflow", index, "O%d" % index)


func _render_actions() -> void:
	var state: RunState = _controller.state
	var targets: PackedStringArray = _controller.discard_targets()
	_action_buttons[1].disabled = targets.is_empty()
	_action_buttons[3].disabled = state == null or state.wild_material_count <= 0
	var main_weapon: ItemInstance = (
		state.equipped.get(GameTypes.EquipmentSlot.MAIN_WEAPON) as ItemInstance
		if state != null
		else null
	)
	_action_buttons[4].disabled = state == null or not state.overflow.is_empty() or main_weapon == null
	_action_buttons[4].text = "結果へ" if state != null and state.wave_number == 8 else "次のウェーブ"
	if state != null and not state.overflow.is_empty():
		_action_buttons[4].text += "（残り%d）" % state.overflow.size()
	elif main_weapon == null:
		_action_buttons[4].text += "（主武器必須）"


func _render_skills() -> void:
	var equipped_ids: Array[StringName] = _controller.equipped_skill_ids()
	var crown_sealed: bool = _is_crown_sealed()
	for index: int in range(_skill_cards.size()):
		var card: InventoryCardButton = _skill_cards[index]
		var focus_id := "skill_%d" % index
		var skill_id: StringName = &""
		var source_kind: StringName = &"slot" if index < 2 else &"catalog"
		var source_id: Variant = index
		if index >= 2:
			source_id = _controller.skill_id_at_catalog_index(index - 2)
		if index < 2:
			skill_id = equipped_ids[index]
			card.visible = true
			card.disabled = index == 1 and crown_sealed
			card.text = "K%d  装着枠%d\n%s" % [
				index,
				index + 1,
				"封印" if card.disabled else (_skill_card_text(skill_id) if not skill_id.is_empty() else "未装着"),
			]
		else:
			skill_id = source_id as StringName
			card.visible = _controller.skill_is_owned(skill_id)
			card.disabled = false
			var state_skill: SkillState = (
				_controller.state.skill_library.get(skill_id) as SkillState
				if _controller.state != null
				else null
			)
			var badge: String = "  [装着中]" if state_skill != null and state_skill.equipped_slot >= 0 else ""
			card.text = "K%d  %s%s" % [index, _skill_card_text(skill_id), badge]
		card.set_meta("focus_id", focus_id)
		card.configure_drag(
			{
				"drag_type": &"skill",
				"source_kind": source_kind,
				"source_id": source_id,
			},
			{
				"kind": source_kind,
				"id": source_id,
			},
			not skill_id.is_empty() and not card.disabled,
			&"skill",
		)
	if crown_sealed and not _controller.held_skill_source.is_empty():
		var held: Dictionary = _controller.held_skill_source
		if StringName(held.get("kind", &"")) == &"slot" and int(held.get("id", -1)) == 1:
			_controller.cancel_lift()


func _render_fusion() -> void:
	if not _fusion_dialog.visible:
		return
	var state: RunState = _controller.state
	_fusion_dialog.update_view(
		_controller.rarity_label(_controller.fusion_rarity),
		_controller.fusion_material_ids,
		_controller.fusion_material_names(),
		_controller.fusion_use_wild,
		state.wild_material_count if state != null else 0,
		_controller.fusion_is_valid(),
		_controller.fusion_preview_text(),
		_controller.fusion_status,
	)


func _render_item_card(
	card: InventoryCardButton,
	kind: StringName,
	index: int,
	token: String,
) -> void:
	var item: ItemInstance = _controller.item_at(kind, index)
	var item_id: String = item.item_id if item != null else ""
	var marked: bool = _controller.marked_item_ids.has(item_id)
	card.text = "%s\n%s" % [
		token,
		_item_card_text(item, marked),
	]
	card.tooltip_text = _item_details(item)
	card.configure_drag(
		{
			"drag_type": &"item",
			"kind": kind,
			"index": index,
			"item_id": item_id,
		},
		{"kind": kind, "index": index},
		item != null,
		&"item",
	)


func _configure_normal_focus_graph() -> void:
	var controls: Dictionary = {}
	var graph: Dictionary = {}
	for column: int in range(EQUIPMENT_COUNT):
		var focus_id := "equip_%d" % column
		controls[focus_id] = _equip_cards[column]
		graph[focus_id] = _graph_entry(
			"skill_%d" % column,
			"grid_%d" % column,
			"equip_%d" % posmod(column - 1, EQUIPMENT_COUNT),
			"equip_%d" % ((column + 1) % EQUIPMENT_COUNT),
		)
	for index: int in range(INVENTORY_COUNT):
		var row: int = floori(float(index) / float(INVENTORY_COLUMNS))
		var column: int = index % INVENTORY_COLUMNS
		var focus_id := "grid_%d" % index
		controls[focus_id] = _grid_cards[index]
		var top: String = "equip_%d" % column if row == 0 else "grid_%d" % (index - INVENTORY_COLUMNS)
		var bottom: String
		if row < INVENTORY_ROWS - 1:
			bottom = "grid_%d" % (index + INVENTORY_COLUMNS)
		elif not _overflow_cards.is_empty():
			bottom = "overflow_%d" % mini(column, _overflow_cards.size() - 1)
		else:
			bottom = "action_%d" % column
		graph[focus_id] = _graph_entry(
			top,
			bottom,
			"grid_%d" % (row * INVENTORY_COLUMNS + posmod(column - 1, INVENTORY_COLUMNS)),
			"grid_%d" % (row * INVENTORY_COLUMNS + (column + 1) % INVENTORY_COLUMNS),
		)
	_add_overflow_to_graph(controls, graph, false)
	for index: int in range(_action_buttons.size()):
		var focus_id := "action_%d" % index
		controls[focus_id] = _action_buttons[index]
		var top: String = (
			"overflow_%d" % mini(index, _overflow_cards.size() - 1)
			if not _overflow_cards.is_empty()
			else "grid_%d" % ((INVENTORY_ROWS - 1) * INVENTORY_COLUMNS + index)
		)
		graph[focus_id] = _graph_entry(
			top,
			"skill_%d" % index,
			"action_%d" % posmod(index - 1, _action_buttons.size()),
			"action_%d" % ((index + 1) % _action_buttons.size()),
		)
	for index: int in range(_skill_cards.size()):
		var focus_id := "skill_%d" % index
		controls[focus_id] = _skill_cards[index]
		graph[focus_id] = _graph_entry(
			"action_%d" % index,
			"equip_%d" % index,
			"skill_%d" % posmod(index - 1, _skill_cards.size()),
			"skill_%d" % ((index + 1) % _skill_cards.size()),
		)
	_focus_controller.configure_graph(controls, graph, "equip_0")


func _configure_fusion_focus_graph() -> void:
	var controls: Dictionary = _fusion_dialog.focus_controls()
	var graph: Dictionary = {
		"FR": _graph_entry("FA3", "F0", "FR", "FR"),
		"F0": _graph_entry("FR", "grid_0", "F2", "F1"),
		"F1": _graph_entry("FR", "grid_2", "F0", "F2"),
		"F2": _graph_entry("FR", "grid_4", "F1", "F0"),
	}
	for index: int in range(INVENTORY_COUNT):
		var row: int = floori(float(index) / float(INVENTORY_COLUMNS))
		var column: int = index % INVENTORY_COLUMNS
		var focus_id := "grid_%d" % index
		controls[focus_id] = _grid_cards[index]
		var fusion_slot: int = mini(floori(float(column) / 2.0), 2)
		var top: String = "F%d" % fusion_slot if row == 0 else "grid_%d" % (index - INVENTORY_COLUMNS)
		var bottom: String
		if row < INVENTORY_ROWS - 1:
			bottom = "grid_%d" % (index + INVENTORY_COLUMNS)
		elif not _overflow_cards.is_empty():
			bottom = "overflow_%d" % mini(column, _overflow_cards.size() - 1)
		else:
			bottom = "FA%d" % mini(column, 3)
		graph[focus_id] = _graph_entry(
			top,
			bottom,
			"grid_%d" % (row * INVENTORY_COLUMNS + posmod(column - 1, INVENTORY_COLUMNS)),
			"grid_%d" % (row * INVENTORY_COLUMNS + (column + 1) % INVENTORY_COLUMNS),
		)
	_add_overflow_to_graph(controls, graph, true)
	for index: int in range(4):
		var focus_id := "FA%d" % index
		var top: String = (
			"overflow_%d" % mini(index, _overflow_cards.size() - 1)
			if not _overflow_cards.is_empty()
			else "grid_%d" % ((INVENTORY_ROWS - 1) * INVENTORY_COLUMNS + mini(index, 5))
		)
		graph[focus_id] = _graph_entry(
			top,
			"FR",
			"FA%d" % posmod(index - 1, 4),
			"FA%d" % ((index + 1) % 4),
		)
	_focus_controller.configure_graph(controls, graph, "FR")
	_focus_controller.set_modal_allowed(_focus_controller.focus_ids())


func _add_overflow_to_graph(
	controls: Dictionary,
	graph: Dictionary,
	fusion_mode: bool,
) -> void:
	for index: int in range(_overflow_cards.size()):
		var focus_id := "overflow_%d" % index
		controls[focus_id] = _overflow_cards[index]
		graph[focus_id] = _graph_entry(
			"grid_%d" % ((INVENTORY_ROWS - 1) * INVENTORY_COLUMNS + mini(index, 5)),
			("FA%d" if fusion_mode else "action_%d") % mini(index, 3 if fusion_mode else 5),
			"overflow_%d" % posmod(index - 1, _overflow_cards.size()),
			"overflow_%d" % ((index + 1) % _overflow_cards.size()),
		)


func _connect_item_card(card: InventoryCardButton, kind: StringName, index: int) -> void:
	card.pressed.connect(_on_item_card_pressed.bind(kind, index))
	card.drop_received.connect(_on_card_drop_received)
	card.pointer_event.connect(_on_pointer_event)
	card.focus_entered.connect(_on_item_focus_entered.bind(kind, index))


func _on_item_card_pressed(kind: StringName, index: int) -> void:
	var item: ItemInstance = _controller.item_at(kind, index)
	if _fusion_dialog.visible:
		if item != null and kind in [&"inventory", &"overflow"]:
			_controller.toggle_fusion_material(item.item_id, true)
			_render_fusion()
		return
	if _controller.held_item_source.is_empty():
		if _controller.begin_item_lift(kind, index):
			_status_text = (
				"%s を持ち上げました。同じ装備枠でAなら外す、配置先でA、Bで取消"
				% item.display_name
				if kind == &"equipped"
				else "%s を持ち上げました。配置先でA、Bで取消" % item.display_name
			)
	else:
		var request: Dictionary = _controller.item_move_request(kind, index)
		if not request.is_empty():
			_pending_command_kind = &"item_move"
			item_move_requested.emit(request["source"], request["target"])
	_render_header()


func _on_skill_card_pressed(index: int) -> void:
	if _fusion_dialog.visible:
		return
	var source_kind: StringName = &"slot" if index < 2 else &"catalog"
	var source_id: Variant = index
	if index >= 2:
		source_id = _controller.skill_id_at_catalog_index(index - 2)
	if _controller.held_skill_source.is_empty():
		if _controller.begin_skill_lift(source_kind, source_id):
			_status_text = "スキルを持ち上げました。配置先でA、Bで取消"
	else:
		var request: Dictionary = _controller.skill_move_request(source_kind, source_id)
		if not request.is_empty():
			_pending_command_kind = &"skill_move"
			skill_move_requested.emit(
				request["source_kind"],
				request["source_id"],
				request["target_kind"],
				request["target_id"],
			)
	_render_header()


func _on_card_drop_received(source: Dictionary, target: Dictionary) -> void:
	_pointer_event_count += 1
	var drag_type := StringName(source.get("drag_type", &""))
	if drag_type == &"item" and not _fusion_dialog.visible:
		_pending_command_kind = &"item_move"
		item_move_requested.emit(
			{"kind": source.get("kind"), "index": source.get("index"), "item_id": source.get("item_id")},
			target,
		)
	elif drag_type == &"skill" and not _fusion_dialog.visible:
		_pending_command_kind = &"skill_move"
		skill_move_requested.emit(
			StringName(source.get("source_kind", &"")),
			source.get("source_id"),
			StringName(target.get("kind", &"")),
			target.get("id"),
		)


func _on_action_pressed(index: int) -> void:
	match index:
		0:
			_open_bulk_dialog()
		1:
			_request_discard()
		2:
			_open_fusion(false)
		3:
			_open_fusion(true)
		4:
			if not _action_buttons[4].disabled:
				continue_requested.emit()
		5:
			_open_settings()


func _activate_focus_id(focus_id: String) -> void:
	if focus_id.begins_with("equip_"):
		_on_item_card_pressed(&"equipped", focus_id.trim_prefix("equip_").to_int())
	elif focus_id.begins_with("grid_"):
		_on_item_card_pressed(&"inventory", focus_id.trim_prefix("grid_").to_int())
	elif focus_id.begins_with("overflow_"):
		_on_item_card_pressed(&"overflow", focus_id.trim_prefix("overflow_").to_int())
	elif focus_id.begins_with("action_"):
		_on_action_pressed(focus_id.trim_prefix("action_").to_int())
	elif focus_id.begins_with("skill_"):
		_on_skill_card_pressed(focus_id.trim_prefix("skill_").to_int())
	elif focus_id.begins_with("F") and focus_id.length() == 2:
		_on_fusion_material_slot_pressed(focus_id.substr(1).to_int())
	elif focus_id.begins_with("FA"):
		match focus_id.substr(2).to_int():
			0: _on_fusion_auto_fill()
			1: _on_fusion_wild_toggle()
			2: _on_fusion_confirm()
			3: _on_fusion_cancelled()


func _open_bulk_dialog() -> void:
	var item: ItemInstance = _controller.find_item(_controller.last_item_focus_id).get("item") as ItemInstance
	var rarity: GameTypes.Rarity = item.rarity if item != null else GameTypes.Rarity.COMMON
	_bulk_dialog.open_dialog(rarity, "action_0")


func _on_bulk_rarity_selected(rarity: GameTypes.Rarity) -> void:
	var selected: PackedStringArray = _controller.auto_select(rarity)
	_status_text = "候補がありません" if selected.is_empty() else "%d件を選択しました" % selected.size()
	_refresh_from_state(true)
	_focus_controller.grab_focus_id("action_0")


func _on_bulk_cancelled() -> void:
	_configure_normal_focus_graph()
	_focus_controller.grab_focus_id("action_0")


func _request_discard() -> void:
	var targets: PackedStringArray = _controller.discard_targets()
	if targets.is_empty():
		return
	var names: PackedStringArray = _controller.unique_names(targets)
	if not names.is_empty():
		_confirmation_kind = &"discard"
		_confirmation_payload = {"item_ids": targets}
		_confirmation_origin_focus_id = "action_1"
		_confirmation_dialog.open_dialog(
			"ユニーク装備を廃棄します",
			"対象: %s" % "、".join(names),
			"ユニークを含めて廃棄",
			"action_1",
		)
		return
	_pending_command_kind = &"discard"
	discard_requested.emit(targets, false)


func _open_fusion(use_wild: bool) -> void:
	_controller.open_fusion(use_wild)
	_fusion_dialog.open_dialog("action_3" if use_wild else "action_2")
	_render_fusion()
	_configure_fusion_focus_graph()
	_focus_controller.focus_initial_deferred()


func _on_fusion_rarity_step(step: int) -> void:
	_controller.change_fusion_rarity(step)
	_render_fusion()


func _on_fusion_material_slot_pressed(slot_index: int) -> void:
	_controller.remove_fusion_material(slot_index)
	_render_fusion()


func _on_fusion_material_dropped(source: Dictionary, _slot_index: int) -> void:
	_pointer_event_count += 1
	_controller.toggle_fusion_material(str(source.get("item_id", "")), true)
	_render_fusion()


func _on_fusion_auto_fill() -> void:
	_controller.auto_fill_fusion()
	_render_fusion()


func _on_fusion_wild_toggle() -> void:
	_controller.toggle_fusion_wild()
	_render_fusion()


func _on_fusion_confirm() -> void:
	if not _controller.fusion_is_valid():
		return
	var names: PackedStringArray = _controller.unique_names(_controller.fusion_material_ids)
	if not names.is_empty():
		_confirmation_kind = &"fusion"
		_confirmation_payload = {
			"material_ids": _controller.fusion_material_ids.duplicate(),
			"use_wild": _controller.fusion_use_wild,
		}
		_confirmation_origin_focus_id = "FA2"
		_confirmation_dialog.open_dialog(
			"ユニーク装備を合成します",
			"固有効果と固定名が失われます。対象: %s" % "、".join(names),
			"ユニークを失って合成",
			"FA2",
		)
		return
	_pending_command_kind = &"fusion"
	fusion_requested.emit(
		_controller.fusion_material_ids.duplicate(),
		_controller.fusion_use_wild,
		false,
	)


func _on_fusion_cancelled() -> void:
	_controller.reset_fusion()
	_fusion_dialog.close_without_signal()
	_refresh_from_state(false)
	_focus_controller.grab_focus_id("action_2")


func _on_confirmation_confirmed() -> void:
	match _confirmation_kind:
		&"discard":
			_pending_command_kind = &"discard"
			discard_requested.emit(
				_confirmation_payload.get("item_ids", PackedStringArray()) as PackedStringArray,
				true,
			)
		&"fusion":
			_pending_command_kind = &"fusion"
			fusion_requested.emit(
				_confirmation_payload.get("material_ids", PackedStringArray()) as PackedStringArray,
				bool(_confirmation_payload.get("use_wild", false)),
				true,
			)
	_confirmation_kind = &""
	_confirmation_payload.clear()


func _on_confirmation_cancelled() -> void:
	var target: String = _confirmation_origin_focus_id
	_confirmation_kind = &""
	_confirmation_payload.clear()
	if _fusion_dialog.visible:
		_configure_fusion_focus_graph()
	else:
		_configure_normal_focus_graph()
	_focus_controller.grab_focus_id(target)


func _open_confirmation_for_result(command_kind: StringName, result: Dictionary) -> void:
	var names: PackedStringArray = result.get("unique_names", PackedStringArray()) as PackedStringArray
	_confirmation_kind = command_kind
	_confirmation_payload = result.get("retry_payload", {}) as Dictionary
	_confirmation_origin_focus_id = "FA2" if command_kind == &"fusion" else "action_1"
	_confirmation_dialog.open_dialog(
		"確認",
		"対象: %s" % "、".join(names),
		"実行",
		_confirmation_origin_focus_id,
	)


func _open_settings() -> void:
	_focus_controller.save_current_focus(get_viewport())
	_settings_overlay.open_overlay()


func _on_settings_closed() -> void:
	var saved_focus_id: String = _focus_controller.saved_focus_id()
	if _fusion_dialog.visible:
		_configure_fusion_focus_graph()
	else:
		_configure_normal_focus_graph()
	_focus_controller.save_focus_id(saved_focus_id)
	_focus_controller.restore_saved_focus("equip_0")


func _handle_cancel() -> void:
	if _fusion_dialog.visible:
		_on_fusion_cancelled()
		return
	if not _controller.held_item_source.is_empty() or not _controller.held_skill_source.is_empty():
		_controller.cancel_lift()
		_status_text = "持ち上げを取り消しました"
		_refresh_from_state(true)


func _handle_item_lock() -> void:
	if _fusion_dialog.visible:
		return
	var focus_id: String = _focus_controller.current_focus_id(get_viewport())
	var item: ItemInstance = _item_for_focus_id(focus_id)
	if item == null:
		return
	_pending_command_kind = &"item_lock"
	item_lock_requested.emit(item.item_id)


func _on_item_focus_entered(kind: StringName, index: int) -> void:
	var item: ItemInstance = _controller.item_at(kind, index)
	var focus_id: String = _focus_id_for_location(kind, index)
	_on_focus_entered(focus_id, item.item_id if item != null else "")
	if item != null and kind in [&"inventory", &"overflow"]:
		_controller.set_last_item_focus(item.item_id)
	_update_comparison(item)
	if kind == &"overflow":
		_ensure_overflow_visible.bind(index).call_deferred()
	_render_actions()


func _on_focus_entered(focus_id: String, _item_id: String) -> void:
	_last_valid_focus_id = focus_id


func _track_current_focus() -> void:
	var focus_id: String = _focus_controller.current_focus_id(get_viewport())
	if not focus_id.is_empty() and _focus_controller.is_focusable_id(focus_id):
		_last_valid_focus_id = focus_id


func _ensure_overflow_visible(index: int) -> void:
	if index < 0 or index >= _overflow_cards.size():
		return
	var card: InventoryCardButton = _overflow_cards[index]
	var card_left: float = card.position.x
	var card_right: float = card.position.x + card.size.x
	var visible_left: float = float(_overflow_scroll.scroll_horizontal)
	var visible_width: float = _overflow_scroll.size.x
	var target_scroll: int = _overflow_scroll.scroll_horizontal
	if card_left < visible_left:
		target_scroll = floori(card_left)
	elif card_right > visible_left + visible_width:
		target_scroll = ceili(card_right - visible_width)
	_overflow_scroll.scroll_horizontal = maxi(0, target_scroll)


func _update_comparison(item: ItemInstance) -> void:
	if item == null or _controller.state == null:
		_comparison_label.text = "アイテムへfocusまたはhoverすると比較を表示します"
		return
	var equipped: ItemInstance = _controller.state.equipped.get(item.slot) as ItemInstance
	if equipped == item:
		_comparison_label.text = "%s\n現在装備中" % _item_details(item)
		return
	var deltas: Array[String] = []
	var equipped_values: Dictionary[StringName, float] = {}
	if equipped != null:
		for affix: AffixRoll in equipped.affixes:
			equipped_values[affix.affix_id] = affix.value
	var item_values: Dictionary[StringName, float] = {}
	for affix: AffixRoll in item.affixes:
		item_values[affix.affix_id] = affix.value
	var ids: Array[StringName] = []
	for affix_id: StringName in equipped_values:
		if not affix_id in ids:
			ids.append(affix_id)
	for affix_id: StringName in item_values:
		if not affix_id in ids:
			ids.append(affix_id)
	ids.sort_custom(func(left: StringName, right: StringName) -> bool: return String(left) < String(right))
	for affix_id: StringName in ids:
		var delta: float = float(item_values.get(affix_id, 0.0)) - float(equipped_values.get(affix_id, 0.0))
		var shape: String = "▲" if delta > 0.0 else ("▼" if delta < 0.0 else "◆")
		deltas.append("%s %s %+.1f" % [shape, affix_id, delta])
	_comparison_label.text = "%s\n比較: %s" % [
		_item_details(item),
		" / ".join(deltas) if not deltas.is_empty() else "特性差なし",
	]


func _new_card(minimum_size: Vector2) -> InventoryCardButton:
	var card := InventoryCardButton.new()
	card.custom_minimum_size = minimum_size
	card.focus_mode = Control.FOCUS_ALL
	card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.mouse_entered.connect(func() -> void:
		var item_id := str(card.drag_payload.get("item_id", ""))
		var item: ItemInstance = _controller.find_item(item_id).get("item") as ItemInstance
		_update_comparison(item)
	)
	return card


func _item_card_text(item: ItemInstance, marked: bool) -> String:
	if item == null:
		return "— 空き —"
	return "%s%s%s\n%s" % [
		"✓ " if marked else "",
		"🔒 " if item.locked else "",
		_controller.rarity_label(item.rarity),
		item.display_name,
	]


func _item_details(item: ItemInstance) -> String:
	if item == null:
		return "空き"
	var affixes: Array[String] = []
	for affix: AffixRoll in item.affixes:
		affixes.append("%s %.1f" % [affix.affix_id, affix.value])
	return "%s  %s\n%s" % [
		_controller.rarity_label(item.rarity),
		item.display_name,
		" / ".join(affixes) if not affixes.is_empty() else "特性なし",
	]


func _skill_card_text(skill_id: StringName) -> String:
	if skill_id.is_empty():
		return "未装着"
	var skill: SkillState = (
		_controller.state.skill_library.get(skill_id) as SkillState
		if _controller.state != null
		else null
	)
	return "%s  Lv%d" % [_controller.skill_name(skill_id), skill.level if skill != null else 1]


func _skill_slot_snapshot() -> Array[String]:
	var result: Array[String] = []
	for skill_id: StringName in _controller.equipped_skill_ids():
		result.append(String(skill_id))
	return result


func _is_crown_sealed() -> bool:
	if _controller.state == null:
		return false
	var head: ItemInstance = _controller.state.equipped.get(GameTypes.EquipmentSlot.HEAD) as ItemInstance
	return head != null and head.unique_id == &"hollow_crown"


func _item_for_focus_id(focus_id: String) -> ItemInstance:
	if focus_id.begins_with("equip_"):
		return _controller.item_at(&"equipped", focus_id.trim_prefix("equip_").to_int())
	if focus_id.begins_with("grid_"):
		return _controller.item_at(&"inventory", focus_id.trim_prefix("grid_").to_int())
	if focus_id.begins_with("overflow_"):
		return _controller.item_at(&"overflow", focus_id.trim_prefix("overflow_").to_int())
	return null


func _focus_id_for_location(kind: StringName, index: int) -> String:
	match kind:
		&"equipped": return "equip_%d" % index
		&"inventory": return "grid_%d" % index
		&"overflow": return "overflow_%d" % index
	return ""


func _count_inventory_items() -> int:
	var count: int = 0
	if _controller.state != null:
		for item: ItemInstance in _controller.state.inventory:
			if item != null:
				count += 1
	return count


func _graph_entry(top: String, bottom: String, left: String, right: String) -> Dictionary:
	return {
		FocusController.DIRECTION_TOP: top,
		FocusController.DIRECTION_BOTTOM: bottom,
		FocusController.DIRECTION_LEFT: left,
		FocusController.DIRECTION_RIGHT: right,
	}


func _direction_for_event(event: InputEvent) -> StringName:
	if event.is_action_pressed("ui_up"):
		return FocusController.DIRECTION_TOP
	if event.is_action_pressed("ui_down"):
		return FocusController.DIRECTION_BOTTOM
	if event.is_action_pressed("ui_left"):
		return FocusController.DIRECTION_LEFT
	if event.is_action_pressed("ui_right"):
		return FocusController.DIRECTION_RIGHT
	return &""


func _on_pointer_event() -> void:
	_pointer_event_count += 1
