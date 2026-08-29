class_name InventoryScreen
extends Control


signal item_move_requested(source: Dictionary, target: Dictionary)
signal item_lock_requested(item_id: String)
signal sort_requested
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
const FUSION_FEEDBACK_DURATION_SECONDS: float = 0.40
const FUSION_FEEDBACK_SCALE: float = 1.06
const FUSION_FEEDBACK_TINT := Color(1.0, 0.82, 0.48, 1.0)
const FUSION_FEEDBACK_OUTLINE_COLOR := Color(0.10, 0.05, 0.02, 1.0)
const FUSION_FEEDBACK_OUTLINE_SIZE: int = 4
const FUSION_SUCCESS_FALLBACK_TEXT: String = "合成成功"
const SORT_ACTION_FOCUS_ID: String = "action_sort"
const SORT_ACTION_LABEL: String = "高レア順に整理\n実行 A／Enter"
const UNKNOWN_AFFIX_LABEL: String = "不明な効果"
const AFFIX_LABELS: Dictionary = {
	&"damage_pct": "与ダメージ",
	&"attack_speed_pct": "攻撃速度",
	&"cooldown_reduction_pct": "クールダウン短縮",
	&"area_pct": "効果範囲",
	&"pierce": "貫通数",
	&"max_hp": "最大HP",
	&"damage_reduction_pct": "被ダメージ軽減",
	&"move_speed_pct": "移動速度",
	&"skill_power_pct": "スキルダメージ",
}
const PERCENT_AFFIX_IDS: Array[StringName] = [
	&"damage_pct",
	&"attack_speed_pct",
	&"cooldown_reduction_pct",
	&"area_pct",
	&"damage_reduction_pct",
	&"move_speed_pct",
	&"skill_power_pct",
]
const ACTION_LABELS: Array[String] = [
	"一括選択\n実行 A／Enter",
	"廃棄\n実行 A／Enter",
	"合成\n実行 A／Enter",
	"ワイルド投入\n実行 A／Enter",
	"次戦／結果へ\n実行 A／Enter",
	"設定\n実行 A／Enter",
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
@onready var _content_root: Control = $Margin
@onready var _settings_overlay: SettingsOverlay = %SettingsOverlay
@onready var _bulk_dialog: BulkSelectDialog = %BulkSelectDialog
@onready var _fusion_dialog: FusionDialog = %FusionDialog
@onready var _confirmation_dialog: JarjarConfirmationDialog = %ConfirmationDialog

var _controller := InventoryController.new()
var _focus_controller := FocusController.new()
var _modal_focus := ModalFocusCoordinator.new()
var _pending_state: RunState = null
var _pending_catalog: DefinitionCatalog = null

var _equip_cards: Array[InventoryCardButton] = []
var _grid_cards: Array[InventoryCardButton] = []
var _overflow_cards: Array[InventoryCardButton] = []
var _action_buttons: Array[Button] = []
var _sort_button: Button = null
var _skill_cards: Array[InventoryCardButton] = []

var _pointer_event_count: int = 0
var _status_text: String = ""
var _pending_command_kind: StringName = &""
var _confirmation_kind: StringName = &""
var _confirmation_payload: Dictionary = {}
var _confirmation_origin_focus_id: String = ""
var _last_valid_focus_id: String = "equip_0"
var _fusion_feedback_presented: bool = false
var _fusion_feedback_reduce_motion: bool = false
var _fusion_feedback_reduce_flashes: bool = false
var _fusion_feedback_motion_enabled: bool = false
var _fusion_feedback_flash_enabled: bool = false
var _fusion_feedback_static_outline: bool = false
var _fusion_feedback_animating: bool = false
var _fusion_feedback_remaining: float = 0.0
var _fusion_feedback_target: Label = null


func _ready() -> void:
	_build_fixed_controls()
	_connect_overlays()
	_modal_focus.configure(get_viewport(), [_content_root])
	_settings_overlay.closed.connect(_on_settings_closed)
	set_process(false)
	_reset_fusion_feedback_visuals()
	if _pending_state != null:
		_controller.initialize(_pending_state, _pending_catalog)
	_refresh_from_state(false)


func initialize(state: RunState, catalog: DefinitionCatalog) -> void:
	_pending_state = state
	_pending_catalog = catalog
	if is_node_ready():
		_clear_fusion_feedback()
		_controller.initialize(state, catalog)
		_refresh_from_state(false)


func refresh_from_state(preserve_focus: bool = true) -> void:
	_refresh_from_state(preserve_focus)


func apply_command_result(command_kind: StringName, result: Dictionary) -> void:
	_clear_fusion_feedback()
	_pending_command_kind = &""
	var success: bool = bool(result.get("success", false))
	var result_text: String = str(result.get("message", result.get("error", "")))
	if command_kind == &"fusion" and success and result_text.is_empty():
		result_text = FUSION_SUCCESS_FALLBACK_TEXT
	var fusion_modal_active: bool = (
		command_kind == &"fusion" and _modal_focus.is_active(_fusion_dialog)
	)
	_status_text = "" if fusion_modal_active else result_text
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
				if fusion_modal_active:
					_controller.complete_fusion_success(result_text)
					_modal_focus.set_restore_target(
						_fusion_dialog,
						_action_buttons[2],
					)
				else:
					_controller.reset_fusion()
					_fusion_dialog.close_without_signal()
	elif command_kind == &"fusion" and fusion_modal_active:
		_controller.set_fusion_result_status(result_text)
	if command_kind == &"discard" and not success and StringName(result.get("error", &"")) in [
		&"missing",
		&"item_missing",
		&"target_missing",
	]:
		_controller.clear_marks()
	_refresh_from_state(true)
	if command_kind == &"fusion" and success:
		if fusion_modal_active:
			_present_fusion_feedback(_fusion_dialog.status_control())
			_fusion_dialog.focus_after_success()
		else:
			_present_fusion_feedback(_status_label)
	if command_kind == &"discard":
		_focus_controller.grab_focus_id("action_1")
	elif command_kind == &"fusion":
		if not success and fusion_modal_active:
			_fusion_dialog.test_focus("FA2")


func focus_ids() -> PackedStringArray:
	if _fusion_dialog.visible:
		return _fusion_dialog.focus_ids()
	return _focus_controller.focus_ids()


func focus_control(focus_id: String) -> Control:
	if _fusion_dialog.visible:
		return _fusion_dialog.focus_control(focus_id)
	return _focus_controller.control_for_id(focus_id)


func neighbor_specification(focus_id: String) -> Dictionary:
	if _fusion_dialog.visible:
		return _fusion_dialog.neighbor_specification(focus_id)
	return _focus_controller.neighbor_specification(focus_id)


func initial_focus_control() -> Control:
	return _equip_cards[0] if not _equip_cards.is_empty() else null


func debug_state() -> Dictionary:
	var result: Dictionary = _controller.debug_state()
	var feedback_target: Label = _fusion_feedback_control()
	result.merge({
		"focus_id": str(
			get_viewport().gui_get_focus_owner().get_meta("focus_id", "")
			if get_viewport().gui_get_focus_owner() != null
			else ""
		),
		"pointer_event_count": _pointer_event_count,
		"status": _status_text,
		"comparison": _comparison_label.text,
		"overflow_count": _overflow_cards.size(),
		"overflow_scroll": _overflow_scroll.scroll_horizontal,
		"bulk_open": _bulk_dialog.visible,
		"fusion_open": _fusion_dialog.visible,
		"confirmation_open": _confirmation_dialog.visible,
		"settings_open": _settings_overlay.visible,
		"modal_stack_size": _modal_focus.stack_size(),
		"active_modal": (
			_modal_focus.active_modal().name
			if _modal_focus.active_modal() != null
			else &""
		),
		"pending_command_kind": _pending_command_kind,
		"skill_slots": _skill_slot_snapshot(),
		"fusion_feedback_presented": _fusion_feedback_presented,
		"fusion_feedback_reduce_motion": _fusion_feedback_reduce_motion,
		"fusion_feedback_reduce_flashes": _fusion_feedback_reduce_flashes,
		"fusion_feedback_motion_enabled": _fusion_feedback_motion_enabled,
		"fusion_feedback_flash_enabled": _fusion_feedback_flash_enabled,
		"fusion_feedback_static_outline": _fusion_feedback_static_outline,
		"fusion_feedback_animating": _fusion_feedback_animating,
		"fusion_feedback_target": str(feedback_target.name) if feedback_target != null else "",
		"fusion_feedback_status_scale": (
			feedback_target.scale if feedback_target != null else Vector2.ONE
		),
		"fusion_feedback_status_modulate": (
			feedback_target.modulate if feedback_target != null else Color.WHITE
		),
		"fusion_feedback_outline_size": (
			feedback_target.get_theme_constant("outline_size")
			if feedback_target != null
			else 0
		),
		"fusion_feedback_background_scale": _status_label.scale,
		"fusion_feedback_background_modulate": _status_label.modulate,
		"fusion_feedback_background_outline_size": _status_label.get_theme_constant(
			"outline_size"
		),
	}, true)
	return result


func test_focus(focus_id: String) -> bool:
	if _fusion_dialog.visible:
		return _fusion_dialog.test_focus(focus_id)
	return _focus_controller.grab_focus_id(focus_id)


func test_direction(direction: StringName) -> bool:
	if _fusion_dialog.visible:
		return _fusion_dialog.test_direction(direction)
	return _focus_controller.move(get_viewport(), direction)


func test_fusion_candidate_focus(item_id: String) -> bool:
	if not _fusion_dialog.visible:
		return false
	return _fusion_dialog.test_focus(_fusion_dialog.focus_id_for_candidate(item_id))


func test_accept() -> void:
	if _fusion_dialog.visible:
		_fusion_dialog.test_accept()
		return
	_activate_focus_id(_focus_controller.current_focus_id(get_viewport()))


func test_cancel() -> void:
	if _modal_focus.is_active(_fusion_dialog):
		_on_fusion_cancelled()
	elif _modal_focus.is_active(_bulk_dialog):
		_bulk_dialog.close_without_signal()
		_on_bulk_cancelled()
	elif _modal_focus.is_active(_confirmation_dialog):
		_confirmation_dialog.close_without_signal()
		_on_confirmation_cancelled()
	elif _modal_focus.is_active(_settings_overlay):
		_settings_overlay.close_overlay()
	else:
		_handle_cancel()


func test_lock() -> void:
	_handle_item_lock()


func test_mouse_drop(source: Dictionary, target: Dictionary) -> void:
	if _modal_focus.has_active_modal():
		return
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


func test_tick_fusion_feedback(delta: float) -> void:
	_advance_fusion_feedback(delta)


func _process(delta: float) -> void:
	_advance_fusion_feedback(delta)


func _present_fusion_feedback(target: Label = null) -> void:
	_fusion_feedback_target = (
		target if target != null and is_instance_valid(target) else _status_label
	)
	var settings: Dictionary = _fusion_accessibility_settings()
	_fusion_feedback_presented = true
	_fusion_feedback_reduce_motion = bool(settings["reduce_motion"])
	_fusion_feedback_reduce_flashes = bool(settings["reduce_flashes"])
	_fusion_feedback_motion_enabled = not _fusion_feedback_reduce_motion
	_fusion_feedback_flash_enabled = not _fusion_feedback_reduce_flashes
	_fusion_feedback_static_outline = _fusion_feedback_reduce_flashes
	_fusion_feedback_remaining = FUSION_FEEDBACK_DURATION_SECONDS
	_fusion_feedback_animating = (
		_fusion_feedback_motion_enabled or _fusion_feedback_flash_enabled
	)
	var feedback_target: Label = _fusion_feedback_control()
	feedback_target.pivot_offset = feedback_target.size * 0.5
	feedback_target.scale = Vector2.ONE
	feedback_target.modulate = Color.WHITE
	feedback_target.add_theme_color_override(
		"font_outline_color",
		FUSION_FEEDBACK_OUTLINE_COLOR,
	)
	feedback_target.add_theme_constant_override(
		"outline_size",
		FUSION_FEEDBACK_OUTLINE_SIZE if _fusion_feedback_static_outline else 0,
	)
	set_process(_fusion_feedback_animating)


func _advance_fusion_feedback(delta: float) -> void:
	if not _fusion_feedback_animating:
		return
	_fusion_feedback_remaining = maxf(0.0, _fusion_feedback_remaining - maxf(0.0, delta))
	var progress: float = (
		1.0 - _fusion_feedback_remaining / FUSION_FEEDBACK_DURATION_SECONDS
	)
	var pulse: float = sin(progress * PI)
	var feedback_target: Label = _fusion_feedback_control()
	feedback_target.scale = (
		Vector2.ONE * (1.0 + (FUSION_FEEDBACK_SCALE - 1.0) * pulse)
		if _fusion_feedback_motion_enabled
		else Vector2.ONE
	)
	feedback_target.modulate = (
		Color.WHITE.lerp(FUSION_FEEDBACK_TINT, pulse)
		if _fusion_feedback_flash_enabled
		else Color.WHITE
	)
	if _fusion_feedback_remaining <= 0.0:
		_fusion_feedback_animating = false
		feedback_target.scale = Vector2.ONE
		feedback_target.modulate = Color.WHITE
		set_process(false)


func _clear_fusion_feedback() -> void:
	_fusion_feedback_presented = false
	_fusion_feedback_reduce_motion = false
	_fusion_feedback_reduce_flashes = false
	_fusion_feedback_motion_enabled = false
	_fusion_feedback_flash_enabled = false
	_fusion_feedback_static_outline = false
	_fusion_feedback_animating = false
	_fusion_feedback_remaining = 0.0
	set_process(false)
	_reset_fusion_feedback_visuals()
	_fusion_feedback_target = _status_label


func _reset_fusion_feedback_visuals() -> void:
	var feedback_target: Label = _fusion_feedback_control()
	if feedback_target == null:
		return
	feedback_target.scale = Vector2.ONE
	feedback_target.modulate = Color.WHITE
	feedback_target.add_theme_constant_override("outline_size", 0)


func _fusion_feedback_control() -> Label:
	if _fusion_feedback_target != null and is_instance_valid(_fusion_feedback_target):
		return _fusion_feedback_target
	return _status_label


func _clear_fusion_success_presentation() -> void:
	if not _fusion_feedback_presented:
		return
	_clear_fusion_feedback()
	_controller.set_fusion_result_status("")
	_status_text = ""


func _fusion_accessibility_settings() -> Dictionary:
	var store: Variant = get_node_or_null("/root/SettingsStore")
	return {
		"reduce_motion": bool(store.reduce_motion) if store != null else false,
		"reduce_flashes": bool(store.reduce_flashes) if store != null else false,
	}


func _input(event: InputEvent) -> void:
	if _modal_focus.has_active_modal():
		return
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		if _handle_cancel():
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("item_lock") and not event.is_echo():
		_handle_item_lock()
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
		_track_current_focus()
		get_viewport().set_input_as_handled()
	elif FocusController.is_left_stick_focus_motion(event):
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
		if index == 0:
			_sort_button = Button.new()
			_sort_button.name = "SortByRarity"
			_sort_button.custom_minimum_size = Vector2(235.0, 58.0)
			_sort_button.focus_mode = Control.FOCUS_ALL
			_sort_button.text = SORT_ACTION_LABEL
			_sort_button.pressed.connect(_request_inventory_sort)
			_action_row.add_child(_sort_button)
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
	_fusion_dialog.candidate_toggled.connect(_on_fusion_candidate_toggled)
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
		if preserve_focus and not _modal_focus.has_active_modal()
		else ""
	)
	_render_header()
	_render_equipment()
	_render_inventory()
	_rebuild_overflow()
	_render_actions()
	_render_skills()
	_render_fusion()
	_configure_normal_focus_graph()
	if _modal_focus.has_active_modal():
		return
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
	_action_buttons[4].text += "\n実行 A／Enter"


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
			card.text = "K%d 装着枠%d　A／Enter\n%s" % [
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
			card.text = "K%d　A／Enter\n%s%s" % [
				index,
				_skill_card_text(skill_id),
				badge,
			]
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
		_fusion_candidate_entries(),
	)


func _fusion_candidate_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for location: Dictionary in _controller.fusion_candidate_locations():
		var item: ItemInstance = location.get("item") as ItemInstance
		if item == null:
			continue
		var kind := StringName(location.get("kind", &""))
		var index: int = int(location.get("index", -1))
		var source_label: String = (
			"通常枠 G%d,%d" % [
				floori(float(index) / float(INVENTORY_COLUMNS)),
				index % INVENTORY_COLUMNS,
			]
			if kind == &"inventory"
			else "一時受取 O%d" % index
		)
		var selected_slot: int = _controller.fusion_material_ids.find(item.item_id)
		var selected_badge: String = "✓ 材料%d　" % (selected_slot + 1) if selected_slot >= 0 else ""
		var unique_badge: String = "⚠ ユニーク　" if not item.unique_id.is_empty() else ""
		var details: String = "%s\n保管位置: %s" % [_item_details(item), source_label]
		if selected_slot >= 0:
			details += "\n選択中: 材料枠%d" % (selected_slot + 1)
		if not item.unique_id.is_empty():
			details += "\n⚠ 合成すると固定名と固有効果が失われます。"
		result.append({
			"item_id": item.item_id,
			"source": {"kind": kind, "index": index},
			"selected_slot": selected_slot,
			"text": "%s%s%s\n%s\nA／Enter 切替" % [
				selected_badge,
				unique_badge,
				_controller.rarity_label(item.rarity),
				item.display_name,
			],
			"details": details,
		})
	return result


func _render_item_card(
	card: InventoryCardButton,
	kind: StringName,
	index: int,
	token: String,
) -> void:
	var item: ItemInstance = _controller.item_at(kind, index)
	var item_id: String = item.item_id if item != null else ""
	var marked: bool = _controller.marked_item_ids.has(item_id)
	card.text = "%s　A／Enter\n%s" % [
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
	_add_overflow_to_graph(controls, graph)
	var action_focus_ids := PackedStringArray([
		"action_0",
		SORT_ACTION_FOCUS_ID,
		"action_1",
		"action_2",
		"action_3",
		"action_4",
		"action_5",
	])
	for action_position: int in range(action_focus_ids.size()):
		var focus_id: String = action_focus_ids[action_position]
		var column: int = (
			1
			if focus_id == SORT_ACTION_FOCUS_ID
			else focus_id.trim_prefix("action_").to_int()
		)
		controls[focus_id] = (
			_sort_button
			if focus_id == SORT_ACTION_FOCUS_ID
			else _action_buttons[column]
		)
		var top: String = (
			"overflow_%d" % mini(column, _overflow_cards.size() - 1)
			if not _overflow_cards.is_empty()
			else "grid_%d" % ((INVENTORY_ROWS - 1) * INVENTORY_COLUMNS + column)
		)
		graph[focus_id] = _graph_entry(
			top,
			"skill_%d" % column,
			action_focus_ids[posmod(action_position - 1, action_focus_ids.size())],
			action_focus_ids[(action_position + 1) % action_focus_ids.size()],
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

func _add_overflow_to_graph(
	controls: Dictionary,
	graph: Dictionary,
) -> void:
	for index: int in range(_overflow_cards.size()):
		var focus_id := "overflow_%d" % index
		controls[focus_id] = _overflow_cards[index]
		graph[focus_id] = _graph_entry(
			"grid_%d" % ((INVENTORY_ROWS - 1) * INVENTORY_COLUMNS + mini(index, 5)),
			"action_%d" % mini(index, 5),
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
	if _modal_focus.has_active_modal():
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
	if _modal_focus.has_active_modal():
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
	if _modal_focus.has_active_modal():
		return
	_pointer_event_count += 1
	var drag_type := StringName(source.get("drag_type", &""))
	if drag_type == &"item":
		_pending_command_kind = &"item_move"
		item_move_requested.emit(
			{"kind": source.get("kind"), "index": source.get("index"), "item_id": source.get("item_id")},
			target,
		)
	elif drag_type == &"skill":
		_pending_command_kind = &"skill_move"
		skill_move_requested.emit(
			StringName(source.get("source_kind", &"")),
			source.get("source_id"),
			StringName(target.get("kind", &"")),
			target.get("id"),
		)


func _on_action_pressed(index: int) -> void:
	if _modal_focus.has_active_modal():
		return
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
	elif focus_id == SORT_ACTION_FOCUS_ID:
		_request_inventory_sort()
	elif focus_id.begins_with("action_"):
		_on_action_pressed(focus_id.trim_prefix("action_").to_int())
	elif focus_id.begins_with("skill_"):
		_on_skill_card_pressed(focus_id.trim_prefix("skill_").to_int())


func _request_inventory_sort() -> void:
	if _modal_focus.has_active_modal():
		return
	_controller.cancel_lift()
	_pending_command_kind = &"sort"
	sort_requested.emit()


func _open_bulk_dialog() -> void:
	var item: ItemInstance = _controller.find_item(_controller.last_item_focus_id).get("item") as ItemInstance
	var rarity: GameTypes.Rarity = item.rarity if item != null else GameTypes.Rarity.COMMON
	if not _modal_focus.push(_bulk_dialog, _action_buttons[0]):
		return
	_bulk_dialog.open_dialog(rarity, "action_0")


func _on_bulk_rarity_selected(rarity: GameTypes.Rarity) -> void:
	var selected: PackedStringArray = _controller.auto_select(rarity)
	_status_text = "候補がありません" if selected.is_empty() else "%d件を選択しました" % selected.size()
	_refresh_from_state(true)
	_modal_focus.pop(_bulk_dialog, null, _action_buttons[0])


func _on_bulk_cancelled() -> void:
	_modal_focus.pop(_bulk_dialog, null, _action_buttons[0])


func _request_discard() -> void:
	var targets: PackedStringArray = _controller.discard_targets()
	if targets.is_empty():
		return
	var names: PackedStringArray = _controller.unique_names(targets)
	if not names.is_empty():
		_confirmation_kind = &"discard"
		_confirmation_payload = {"item_ids": targets}
		_confirmation_origin_focus_id = "action_1"
		if not _modal_focus.push(_confirmation_dialog, _action_buttons[1]):
			return
		_modal_focus.set_restore_target(_confirmation_dialog, _action_buttons[1])
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
	var origin_index: int = 3 if use_wild else 2
	if not _modal_focus.push(_fusion_dialog, _action_buttons[origin_index]):
		return
	_clear_fusion_success_presentation()
	_controller.open_fusion(use_wild)
	_fusion_dialog.open_dialog("action_%d" % origin_index)
	_render_fusion()
	_fusion_dialog.focus_initial_deferred()


func _on_fusion_rarity_step(step: int) -> void:
	_clear_fusion_success_presentation()
	_controller.change_fusion_rarity(step)
	_render_fusion()


func _on_fusion_material_slot_pressed(slot_index: int) -> void:
	_clear_fusion_success_presentation()
	_controller.remove_fusion_material(slot_index)
	_render_fusion()


func _on_fusion_material_dropped(source: Dictionary, _slot_index: int) -> void:
	_clear_fusion_success_presentation()
	_pointer_event_count += 1
	_controller.toggle_fusion_material(str(source.get("item_id", "")), true)
	_render_fusion()


func _on_fusion_candidate_toggled(item_id: String) -> void:
	_clear_fusion_success_presentation()
	_controller.toggle_fusion_material(item_id, true)
	_render_fusion()


func _on_fusion_auto_fill() -> void:
	_clear_fusion_success_presentation()
	_controller.auto_fill_fusion()
	_render_fusion()


func _on_fusion_wild_toggle() -> void:
	_clear_fusion_success_presentation()
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
		var confirm_focus: Control = _fusion_dialog.focus_control("FA2")
		if not _modal_focus.push(_confirmation_dialog, confirm_focus):
			return
		_modal_focus.set_restore_target(_confirmation_dialog, confirm_focus)
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
	var fallback_id: String = _fusion_dialog.origin_focus_id()
	var fallback_control: Control = _focus_controller.control_for_id(fallback_id)
	_clear_fusion_success_presentation()
	_controller.reset_fusion()
	_fusion_dialog.close_without_signal()
	_refresh_from_state(false)
	_modal_focus.pop(_fusion_dialog, null, fallback_control)


func _on_confirmation_confirmed() -> void:
	var command_kind: StringName = _confirmation_kind
	var payload: Dictionary = _confirmation_payload.duplicate(true)
	_modal_focus.pop(_confirmation_dialog)
	_confirmation_kind = &""
	_confirmation_payload.clear()
	match command_kind:
		&"discard":
			_pending_command_kind = &"discard"
			discard_requested.emit(
				payload.get("item_ids", PackedStringArray()) as PackedStringArray,
				true,
			)
		&"fusion":
			_pending_command_kind = &"fusion"
			fusion_requested.emit(
				payload.get("material_ids", PackedStringArray()) as PackedStringArray,
				bool(payload.get("use_wild", false)),
				true,
			)


func _on_confirmation_cancelled() -> void:
	_confirmation_kind = &""
	_confirmation_payload.clear()
	_modal_focus.pop(_confirmation_dialog)


func _open_confirmation_for_result(command_kind: StringName, result: Dictionary) -> void:
	var names: PackedStringArray = result.get("unique_names", PackedStringArray()) as PackedStringArray
	_confirmation_kind = command_kind
	_confirmation_payload = result.get("retry_payload", {}) as Dictionary
	_confirmation_origin_focus_id = "FA2" if command_kind == &"fusion" else "action_1"
	var origin_control: Control = (
		_fusion_dialog.focus_control("FA2")
		if command_kind == &"fusion" and _fusion_dialog.visible
		else _action_buttons[1]
	)
	if not _modal_focus.push(_confirmation_dialog, origin_control):
		return
	_modal_focus.set_restore_target(_confirmation_dialog, origin_control)
	_confirmation_dialog.open_dialog(
		"確認",
		"対象: %s" % "、".join(names),
		"実行",
		_confirmation_origin_focus_id,
	)


func _open_settings() -> void:
	if not _modal_focus.push(_settings_overlay, initial_focus_control()):
		return
	_settings_overlay.open_overlay()


func _on_settings_closed() -> void:
	_modal_focus.pop(_settings_overlay, null, initial_focus_control())


func _handle_cancel() -> bool:
	if not _controller.held_item_source.is_empty() or not _controller.held_skill_source.is_empty():
		_controller.cancel_lift()
		_status_text = "持ち上げを取り消しました"
		_refresh_from_state(true)
		return true
	return false


func _handle_item_lock() -> void:
	if _modal_focus.has_active_modal():
		return
	var focus_id: String = _focus_controller.current_focus_id(get_viewport())
	var item: ItemInstance = _item_for_focus_id(focus_id)
	if item == null:
		return
	_pending_command_kind = &"item_lock"
	item_lock_requested.emit(item.item_id)


func _on_item_focus_entered(kind: StringName, index: int) -> void:
	if _modal_focus.has_active_modal():
		return
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
		deltas.append("%s %s" % [shape, _format_affix_effect(affix_id, delta)])
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
		affixes.append(_format_affix_effect(affix.affix_id, affix.value))
	return "%s  %s\n%s" % [
		_controller.rarity_label(item.rarity),
		item.display_name,
		" / ".join(affixes) if not affixes.is_empty() else "特性なし",
	]


func _format_affix_effect(affix_id: StringName, value: float) -> String:
	var label: String = str(AFFIX_LABELS.get(affix_id, UNKNOWN_AFFIX_LABEL))
	return "%s %s" % [
		label,
		_format_effect_value(value, PERCENT_AFFIX_IDS.has(affix_id)),
	]


func _format_effect_value(value: float, is_percent: bool) -> String:
	var magnitude: String = ("%.1f" % absf(value)).trim_suffix(".0")
	var value_prefix: String = ""
	if magnitude != "0":
		value_prefix = "+" if value > 0.0 else "-"
	return "%s%s%s" % [value_prefix, magnitude, "%" if is_percent else ""]


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


func _on_pointer_event() -> void:
	_pointer_event_count += 1
