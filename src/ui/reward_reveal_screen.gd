class_name RewardRevealScreen
extends Control


signal reveal_completed
signal audio_event_requested(event_id: StringName)

const CURRENT_CARD_SIZE := Vector2(760.0, 340.0)
const NO_BULK_OPEN_AUDIO_RARITY: int = -1
const UiPolishScript := preload("res://src/ui/ui_polish.gd")
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
	&"damage_pct", &"attack_speed_pct", &"area_pct",
	&"damage_reduction_pct", &"move_speed_pct",
]

@onready var _unopened_count: Label = %UnopenedCount
@onready var _accessibility_status: Label = %AccessibilityStatus
@onready var _prealert_banner: Label = %PrealertBanner
@onready var _current_card: PanelContainer = %CurrentCard
@onready var _current_rarity: Label = %CurrentRarity
@onready var _current_name: Label = %CurrentName
@onready var _current_details: Label = %CurrentDetails
@onready var _prealert_targets: HBoxContainer = %PrealertTargets
@onready var _acquired_list: VBoxContainer = %AcquiredList
@onready var _open_all: Button = %RewardOpenAll
@onready var _settings: Button = %RewardSettings
@onready var _content_root: Control = $RootMargin
@onready var _settings_overlay: SettingsOverlay = %SettingsOverlay

var _pending_state: RunState = null
var _pending_catalog: DefinitionCatalog = null
var _controller: RewardRevealController = RewardRevealController.new()
var _automatic_progression: bool = true
var _modal_focus := ModalFocusCoordinator.new()

var _saved_focus_id: String = "reward_open_all"
var _last_joypad_device: int = 0

var _open_all_request_count: int = 0
var _button_click_counts: Dictionary = {
	"reward_open_all": 0,
	"reward_settings": 0,
}
var _vibration_call_count: int = 0
var _last_rendered_revealed_count: int = -1
var _last_prealert_key: String = ""
var _bulk_open_audio_active: bool = false
var _bulk_open_audio_rarity: int = NO_BULK_OPEN_AUDIO_RARITY


func _ready() -> void:
	_open_all.set_meta("focus_id", "reward_open_all")
	_settings.set_meta("focus_id", "reward_settings")
	FocusController.configure_horizontal_cycle([_open_all, _settings])
	_open_all.button_down.connect(_mark_current_input_as_handled)
	_open_all.pressed.connect(_on_open_all_pressed)
	_settings.pressed.connect(_on_settings_pressed)
	_settings_overlay.closed.connect(_on_settings_closed)
	_settings_overlay.settings_changed.connect(_on_settings_changed)
	_modal_focus.configure(get_viewport(), [_content_root])
	_controller.reward_revealed.connect(_on_reward_revealed)
	_controller.all_revealed.connect(_on_all_revealed)
	_controller.vibration_requested.connect(_on_vibration_requested)
	_controller.prealert_started.connect(_on_prealert_started)
	_refresh_accessibility_from_store()
	FocusController.grab_focus_deferred(_open_all)
	if _pending_state != null:
		_initialize_controller(_pending_state)
	_update_view()
	_stabilize_current_card_layout.call_deferred()


func initialize(
	state: RunState,
	catalog: DefinitionCatalog = null,
) -> void:
	_pending_state = state
	_pending_catalog = catalog
	if is_node_ready():
		_initialize_controller(state)


func reveal_controller() -> RewardRevealController:
	return _controller


func focus_order() -> PackedStringArray:
	return PackedStringArray([
		"reward_open_all",
		"reward_settings",
	])


func initial_focus_control() -> Control:
	return _open_all


func set_automatic_progression(enabled: bool) -> void:
	_automatic_progression = enabled


func test_tick(delta: float) -> void:
	_advance(delta)


func test_press_reward_open_all_action() -> void:
	_request_open_all()


func debug_state() -> Dictionary:
	var result: Dictionary = _controller.presentation_state()
	result["focus_id"] = _current_focus_id()
	result["open_all_request_count"] = _open_all_request_count
	result["reward_open_all_click_count"] = int(_button_click_counts["reward_open_all"])
	result["reward_settings_click_count"] = int(_button_click_counts["reward_settings"])
	result["settings_open"] = _settings_overlay.visible
	result["modal_stack_size"] = _modal_focus.stack_size()
	result["accessibility_status"] = _accessibility_status.text
	result["saved_focus_id"] = _saved_focus_id
	result["vibration_call_count"] = _vibration_call_count
	return result


func _process(delta: float) -> void:
	if _automatic_progression:
		_advance(delta)


func _input(event: InputEvent) -> void:
	if _modal_focus.has_active_modal():
		return
	if event is InputEventJoypadButton:
		_last_joypad_device = event.device
	if event.is_action_pressed(&"reward_open_all") and not event.is_echo():
		_mark_current_input_as_handled()
		_request_open_all()


func _advance(delta: float) -> void:
	if delta <= 0.0 or _settings_overlay.visible:
		return
	_controller.tick(delta)
	_update_view()


func _request_open_all() -> void:
	if _modal_focus.has_active_modal():
		return
	_open_all_request_count += 1
	if _controller.is_paused() or _controller.is_complete():
		return
	_bulk_open_audio_active = true
	_bulk_open_audio_rarity = NO_BULK_OPEN_AUDIO_RARITY
	_controller.request_open_all()
	_update_view()


func _open_settings() -> void:
	if _modal_focus.has_active_modal():
		return
	_saved_focus_id = _current_focus_id()
	_controller.set_paused(true)
	if not _modal_focus.push(_settings_overlay, _open_all):
		_controller.set_paused(false)
		return
	_settings_overlay.open_overlay()


func _on_settings_closed() -> void:
	_controller.set_paused(false)
	_refresh_accessibility_from_store()
	_modal_focus.pop(_settings_overlay, null, _open_all)


func _on_settings_changed(values: Dictionary) -> void:
	_controller.configure_accessibility(
		bool(values.get("reduce_motion", false)),
		bool(values.get("reduce_flashes", false)),
		bool(values.get("controller_vibration", true)),
	)
	_update_view()


func _refresh_accessibility_from_store() -> void:
	var store: Variant = get_node_or_null("/root/SettingsStore")
	_controller.configure_accessibility(
		bool(store.reduce_motion) if store != null else false,
		bool(store.reduce_flashes) if store != null else false,
		bool(store.controller_vibration) if store != null else true,
	)


func _on_open_all_pressed() -> void:
	_mark_current_input_as_handled()
	_button_click_counts["reward_open_all"] = int(_button_click_counts["reward_open_all"]) + 1
	_request_open_all()


func _on_settings_pressed() -> void:
	_button_click_counts["reward_settings"] = int(_button_click_counts["reward_settings"]) + 1
	_open_settings()


func _mark_current_input_as_handled() -> void:
	var viewport: Viewport = get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


func _on_vibration_requested(
	weak_magnitude: float,
	strong_magnitude: float,
	duration: float,
) -> void:
	_vibration_call_count += 1
	Input.start_joy_vibration(
		_last_joypad_device,
		weak_magnitude,
		strong_magnitude,
		duration,
	)


func _on_reward_revealed(reward: RewardRoll) -> void:
	if _bulk_open_audio_active:
		_remember_bulk_open_audio(reward)
	elif reward != null:
		_emit_reward_open_audio(reward.rarity_for_presentation)
	_update_view()


func _on_prealert_started(rarity: int) -> void:
	audio_event_requested.emit(
		&"legendary_prealert"
		if rarity == GameTypes.Rarity.LEGENDARY
		else &"epic_prealert"
	)


func _on_all_revealed() -> void:
	var should_emit_bulk_audio: bool = _bulk_open_audio_active
	var bulk_audio_rarity: int = _bulk_open_audio_rarity
	_reset_bulk_open_audio()
	if should_emit_bulk_audio:
		_emit_reward_open_audio(bulk_audio_rarity)
	reveal_completed.emit()


func _initialize_controller(state: RunState) -> void:
	_reset_bulk_open_audio()
	_controller.initialize(state)
	_last_rendered_revealed_count = -1
	_last_prealert_key = ""
	_update_view()


func _remember_bulk_open_audio(reward: RewardRoll) -> void:
	if reward == null:
		return
	match reward.rarity_for_presentation:
		GameTypes.Rarity.COMMON, GameTypes.Rarity.RARE:
			_bulk_open_audio_rarity = maxi(
				_bulk_open_audio_rarity,
				reward.rarity_for_presentation,
			)


func _emit_reward_open_audio(rarity: int) -> void:
	match rarity:
		GameTypes.Rarity.COMMON:
			audio_event_requested.emit(&"normal_open")
		GameTypes.Rarity.RARE:
			audio_event_requested.emit(&"rare_open")


func _reset_bulk_open_audio() -> void:
	_bulk_open_audio_active = false
	_bulk_open_audio_rarity = NO_BULK_OPEN_AUDIO_RARITY


func _update_view() -> void:
	if not is_node_ready() or not is_inside_tree():
		return
	var presentation: Dictionary = _controller.presentation_state()
	_accessibility_status.text = "動き軽減 %s・点滅軽減 %s" % [
		"ON" if bool(presentation["reduce_motion"]) else "OFF",
		"ON" if bool(presentation["reduce_flashes"]) else "OFF",
	]
	_unopened_count.text = "未開封箱　%d" % _controller.unrevealed_count()
	_prealert_banner.visible = bool(presentation["prealert_active"])
	_prealert_banner.text = (
		"高レア予告　EPIC以上"
		if bool(presentation["aggregate_prealert"])
		else "高レア予告"
	)
	_update_current_card(presentation)
	_update_prealert_targets(presentation)
	var revealed_count: int = _controller.revealed_rewards().size()
	if revealed_count != _last_rendered_revealed_count:
		_last_rendered_revealed_count = revealed_count
		_rebuild_acquired_list()


func _update_current_card(presentation: Dictionary) -> void:
	_current_card.size = CURRENT_CARD_SIZE
	var reward: RewardRoll = _controller.last_revealed_reward()
	var prealert_active: bool = bool(presentation["prealert_active"])
	if prealert_active:
		reward = _prealert_primary_reward()
		_current_rarity.text = (
			"EPIC以上"
			if bool(presentation["aggregate_prealert"])
			else RewardRevealController.rarity_label(reward)
		)
		_current_name.text = "内容は公開前です"
		_current_details.text = "真の高レア予告 • 結果は獲得時に確定済み"
	elif reward != null:
		_current_rarity.text = "%s  %s" % [
			RewardRevealController.outline_token(reward),
			RewardRevealController.rarity_label(reward),
		]
		_current_name.text = _reward_display_name(reward)
		_current_details.text = _reward_details(reward)
	else:
		_current_rarity.text = "未公開"
		_current_name.text = "箱を開封しています"
		_current_details.text = "内容は箱獲得時に確定済み"
	var rarity: int = (
		int(presentation.get("prealert_rarity", -2))
		if prealert_active
		else (reward.rarity_for_presentation if reward != null else -2)
	)
	var outline_thickness: int = int(presentation["outline_thickness"])
	var stage_light_step: int = int(presentation["stage_light_step"])
	_current_card.add_theme_stylebox_override(
		"panel",
		_card_style(rarity, outline_thickness, stage_light_step),
	)
	_current_card.position = Vector2(float(presentation["shake_offset"]), 0.0)
	_current_card.pivot_offset = _current_card.size * 0.5
	_current_card.scale = Vector2.ONE * float(presentation["scale_multiplier"])


func _stabilize_current_card_layout() -> void:
	_current_card.size = CURRENT_CARD_SIZE
	_current_card.pivot_offset = CURRENT_CARD_SIZE * 0.5


func _update_prealert_targets(presentation: Dictionary) -> void:
	var ids: PackedStringArray = presentation["prealert_reward_ids"] as PackedStringArray
	var key: String = "|".join(ids)
	if key != _last_prealert_key:
		_last_prealert_key = key
		_clear_children(_prealert_targets)
		if bool(presentation["aggregate_prealert"]):
			for reward_id: String in ids:
				var panel: PanelContainer = _build_hidden_prealert_card(reward_id)
				_prealert_targets.add_child(panel)
	_prealert_targets.visible = bool(presentation["aggregate_prealert"])
	if not _prealert_targets.visible:
		return
	var index: int = 0
	for child: Node in _prealert_targets.get_children():
		var panel := child as PanelContainer
		if panel == null:
			continue
		panel.add_theme_stylebox_override(
			"panel",
			_card_style(
				GameTypes.Rarity.EPIC,
				int(presentation["outline_thickness"]),
				int(presentation["stage_light_step"]),
			),
		)
		panel.position.x = float(presentation["shake_offset"]) * (1.0 if index % 2 == 0 else -1.0)
		panel.pivot_offset = panel.size * 0.5
		panel.scale = Vector2.ONE * float(presentation["scale_multiplier"])
		index += 1


func _rebuild_acquired_list() -> void:
	_clear_children(_acquired_list)
	var rewards: Array[RewardRoll] = _controller.revealed_rewards()
	for reward: RewardRoll in rewards:
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(0.0, 92.0)
		panel.add_theme_stylebox_override(
			"panel",
			_card_style(reward.rarity_for_presentation, 3, 0),
		)
		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 14)
		margin.add_theme_constant_override("margin_top", 8)
		margin.add_theme_constant_override("margin_right", 14)
		margin.add_theme_constant_override("margin_bottom", 8)
		panel.add_child(margin)
		var label := Label.new()
		label.text = "%s %s\n%s" % [
			RewardRevealController.outline_token(reward),
			RewardRevealController.rarity_label(reward),
			_reward_display_name(reward),
		]
		label.add_theme_font_size_override("font_size", 18)
		margin.add_child(label)
		_acquired_list.add_child(panel)


func _build_hidden_prealert_card(reward_id: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(180.0, 92.0)
	panel.set_meta("reward_id", reward_id)
	var label := Label.new()
	label.text = "⬡ EPIC以上\n内容非公開"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 18)
	panel.add_child(label)
	return panel


func _prealert_primary_reward() -> RewardRoll:
	var ids: PackedStringArray = _controller.prealert_reward_ids()
	if ids.is_empty():
		return null
	for reward: RewardRoll in _controller.ordered_rewards():
		if reward.reward_id == ids[0]:
			return reward
	return null


func _reward_display_name(reward: RewardRoll) -> String:
	if reward.item == null:
		return "アイテム"
	return (
		reward.item.display_name
		if not reward.item.display_name.is_empty()
		else reward.item.item_id
	)


func _reward_details(reward: RewardRoll) -> String:
	if reward.item == null:
		return "アイテム報酬"
	var item: ItemInstance = reward.item
	if item.category == GameTypes.ItemCategory.WEAPON:
		var definition: WeaponDefinition = (
			_pending_catalog.weapon_for_type(item.weapon_type)
			if _pending_catalog != null
			else null
		)
		if definition == null:
			return "武器"
		return "%s\n基礎ダメージ %.0f　基準間隔 %.2f秒　射程 %.2fm" % [
			InventoryItemVisualsScript.weapon_type_label(item.weapon_type),
			definition.damage_for_rarity(item.rarity),
			definition.base_interval,
			definition.range_m,
		]
	var lines := PackedStringArray(["お守り"])
	for affix: AffixRoll in item.affixes:
		lines.append("%s +%.0f%s" % [
			AFFIX_LABELS.get(affix.affix_id, String(affix.affix_id)),
			affix.value,
			"%" if affix.affix_id in PERCENT_AFFIX_IDS else "",
		])
	return "\n".join(lines)


func _card_style(rarity: int, outline_thickness: int, stage_light_step: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.content_margin_left = 24.0
	style.content_margin_top = 20.0
	style.content_margin_right = 24.0
	style.content_margin_bottom = 20.0
	var border_color: Color = UiPolishScript.rarity_color(rarity)
	var background: Color = Color(0.055, 0.071, 0.09, 0.98)
	if stage_light_step > 0:
		background = background.lightened(0.08 * float(stage_light_step))
	style.bg_color = background
	style.border_color = border_color
	style.border_width_left = outline_thickness
	style.border_width_top = outline_thickness
	style.border_width_right = outline_thickness
	style.border_width_bottom = outline_thickness
	UiPolishScript.apply_rarity_corner_shape(style, rarity)
	return style


func _current_focus_id() -> String:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return "reward_open_all"
	var focused: Control = viewport.gui_get_focus_owner()
	if focused == null:
		return "reward_open_all"
	return str(focused.get_meta("focus_id", ""))


func _clear_children(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
