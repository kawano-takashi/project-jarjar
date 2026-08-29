class_name RewardRevealScreen
extends Control


signal reveal_completed
signal audio_event_requested(event_id: StringName)

const HOLD_THRESHOLD_SECONDS: float = 0.25
const CURRENT_CARD_SIZE := Vector2(760.0, 340.0)

@onready var _unopened_count: Label = %UnopenedCount
@onready var _accessibility_status: Label = %AccessibilityStatus
@onready var _prealert_banner: Label = %PrealertBanner
@onready var _current_card: PanelContainer = %CurrentCard
@onready var _current_rarity: Label = %CurrentRarity
@onready var _current_name: Label = %CurrentName
@onready var _current_details: Label = %CurrentDetails
@onready var _prealert_targets: HBoxContainer = %PrealertTargets
@onready var _acquired_list: VBoxContainer = %AcquiredList
@onready var _speed_proxy: Control = %RewardSpeedProxy
@onready var _speed_label: Label = %SpeedLabel
@onready var _open_all: Button = %RewardOpenAll
@onready var _settings: Button = %RewardSettings
@onready var _settings_overlay: SettingsOverlay = %SettingsOverlay

var _pending_state: RunState = null
var _controller: RewardRevealController = RewardRevealController.new()
var _automatic_progression: bool = true

var _accept_pressed: bool = false
var _accept_elapsed: float = 0.0
var _accept_origin_focus_id: String = ""
var _mouse_proxy_captured: bool = false
var _mouse_proxy_elapsed: float = 0.0
var _test_mouse_button_origin: String = ""
var _saved_focus_id: String = "reward_speed_proxy"
var _last_joypad_device: int = 0

var _pointer_event_count: int = 0
var _open_all_request_count: int = 0
var _button_click_counts: Dictionary = {
	"reward_open_all": 0,
	"reward_settings": 0,
}
var _vibration_call_count: int = 0
var _last_rendered_revealed_count: int = -1
var _last_prealert_key: String = ""


func _ready() -> void:
	_speed_proxy.set_meta("focus_id", "reward_speed_proxy")
	_open_all.set_meta("focus_id", "reward_open_all")
	_settings.set_meta("focus_id", "reward_settings")
	FocusController.configure_horizontal_cycle([_speed_proxy, _open_all, _settings])
	_speed_proxy.gui_input.connect(_on_speed_proxy_gui_input)
	_open_all.pressed.connect(_on_open_all_pressed)
	_settings.pressed.connect(_on_settings_pressed)
	_settings_overlay.closed.connect(_on_settings_closed)
	_settings_overlay.settings_changed.connect(_on_settings_changed)
	_controller.reward_revealed.connect(_on_reward_revealed)
	_controller.all_revealed.connect(_on_all_revealed)
	_controller.vibration_requested.connect(_on_vibration_requested)
	_controller.prealert_started.connect(_on_prealert_started)
	_refresh_accessibility_from_store()
	FocusController.grab_focus_deferred(_speed_proxy)
	if _pending_state != null:
		_initialize_controller(_pending_state)
	_update_view()
	_stabilize_current_card_layout.call_deferred()


func initialize(state: RunState) -> void:
	_pending_state = state
	if is_node_ready():
		_initialize_controller(state)


func reveal_controller() -> RewardRevealController:
	return _controller


func focus_order() -> PackedStringArray:
	return PackedStringArray([
		"reward_speed_proxy",
		"reward_open_all",
		"reward_settings",
	])


func initial_focus_control() -> Control:
	return _speed_proxy


func set_automatic_progression(enabled: bool) -> void:
	_automatic_progression = enabled


func test_tick(delta: float) -> void:
	_advance(delta)


func test_accept_press(focus_id: String) -> void:
	_grab_focus_id(focus_id)
	_begin_accept(focus_id)


func test_accept_release() -> void:
	_end_accept()


func test_mouse_proxy_press() -> void:
	_pointer_event_count += 1
	_begin_mouse_proxy()


func test_mouse_proxy_release() -> void:
	_pointer_event_count += 1
	_end_mouse_proxy()


func test_mouse_button_press(focus_id: String) -> void:
	_pointer_event_count += 1
	_test_mouse_button_origin = focus_id


func test_mouse_button_release(_focus_id: String = "") -> void:
	_pointer_event_count += 1
	if not _test_mouse_button_origin.is_empty():
		_activate_focus_id(_test_mouse_button_origin)
	_test_mouse_button_origin = ""


func test_press_reward_open_all_action() -> void:
	_request_open_all()


func debug_state() -> Dictionary:
	var result: Dictionary = _controller.presentation_state()
	result["focus_id"] = _current_focus_id()
	result["accept_pressed"] = _accept_pressed
	result["accept_elapsed"] = _accept_elapsed
	result["mouse_proxy_captured"] = _mouse_proxy_captured
	result["mouse_proxy_elapsed"] = _mouse_proxy_elapsed
	result["pointer_event_count"] = _pointer_event_count
	result["open_all_request_count"] = _open_all_request_count
	result["reward_open_all_click_count"] = int(_button_click_counts["reward_open_all"])
	result["reward_settings_click_count"] = int(_button_click_counts["reward_settings"])
	result["settings_open"] = _settings_overlay.visible
	result["accessibility_status"] = _accessibility_status.text
	result["saved_focus_id"] = _saved_focus_id
	result["vibration_call_count"] = _vibration_call_count
	return result


func _process(delta: float) -> void:
	if _automatic_progression:
		_advance(delta)


func _input(event: InputEvent) -> void:
	if _settings_overlay.visible:
		return
	if event is InputEventJoypadButton:
		_last_joypad_device = event.device
	if event is InputEventMouseButton:
		_pointer_event_count += 1
		var mouse_event := event as InputEventMouseButton
		if (
			_mouse_proxy_captured
			and mouse_event.button_index == MOUSE_BUTTON_LEFT
			and not mouse_event.pressed
		):
			_end_mouse_proxy()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("reward_open_all") and not event.is_echo():
		_request_open_all()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_accept") and not event.is_echo():
		_begin_accept(_current_focus_id())
		get_viewport().set_input_as_handled()
	elif event.is_action_released("ui_accept"):
		_end_accept()
		get_viewport().set_input_as_handled()


func _advance(delta: float) -> void:
	if delta <= 0.0 or _settings_overlay.visible:
		return
	_controller.tick(delta)
	if _accept_pressed:
		_accept_elapsed += delta
		if (
			_accept_origin_focus_id == "reward_speed_proxy"
			and _accept_elapsed >= HOLD_THRESHOLD_SECONDS
		):
			_controller.set_fast_open(true)
	if _mouse_proxy_captured:
		_mouse_proxy_elapsed += delta
		if _mouse_proxy_elapsed >= HOLD_THRESHOLD_SECONDS:
			_controller.set_fast_open(true)
	_update_view()


func _begin_accept(focus_id: String) -> void:
	if _accept_pressed or _settings_overlay.visible:
		return
	_accept_pressed = true
	_accept_elapsed = 0.0
	_accept_origin_focus_id = focus_id


func _end_accept() -> void:
	if not _accept_pressed:
		return
	var origin_id: String = _accept_origin_focus_id
	var elapsed: float = _accept_elapsed
	_accept_pressed = false
	_accept_elapsed = 0.0
	_accept_origin_focus_id = ""
	_controller.set_fast_open(false)
	if origin_id != "reward_speed_proxy" and elapsed < HOLD_THRESHOLD_SECONDS:
		_activate_focus_id(origin_id)
	_update_view()


func _begin_mouse_proxy() -> void:
	if _mouse_proxy_captured or _settings_overlay.visible:
		return
	_mouse_proxy_captured = true
	_mouse_proxy_elapsed = 0.0


func _end_mouse_proxy() -> void:
	if not _mouse_proxy_captured:
		return
	_mouse_proxy_captured = false
	_mouse_proxy_elapsed = 0.0
	_controller.set_fast_open(false)
	_update_view()


func _activate_focus_id(focus_id: String) -> void:
	match focus_id:
		"reward_open_all":
			_button_click_counts["reward_open_all"] = (
				int(_button_click_counts["reward_open_all"]) + 1
			)
			_request_open_all()
		"reward_settings":
			_button_click_counts["reward_settings"] = (
				int(_button_click_counts["reward_settings"]) + 1
			)
			_open_settings()


func _request_open_all() -> void:
	_open_all_request_count += 1
	_controller.request_open_all()
	_update_view()


func _open_settings() -> void:
	_saved_focus_id = _current_focus_id()
	_controller.set_fast_open(false)
	_controller.set_paused(true)
	_settings_overlay.open_overlay()


func _on_settings_closed() -> void:
	_controller.set_paused(false)
	_refresh_accessibility_from_store()
	_restore_saved_focus.call_deferred()


func _restore_saved_focus() -> void:
	if (
		not _grab_focus_id(_saved_focus_id)
		and _speed_proxy.is_inside_tree()
		and _speed_proxy.is_visible_in_tree()
	):
		_speed_proxy.grab_focus()


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


func _on_speed_proxy_gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return
	if mouse_event.pressed:
		_begin_mouse_proxy()
	accept_event()


func _on_open_all_pressed() -> void:
	_button_click_counts["reward_open_all"] = int(_button_click_counts["reward_open_all"]) + 1
	_request_open_all()


func _on_settings_pressed() -> void:
	_button_click_counts["reward_settings"] = int(_button_click_counts["reward_settings"]) + 1
	_open_settings()


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
	if reward != null and reward.rarity_for_presentation == GameTypes.Rarity.RARE:
		audio_event_requested.emit(&"rare_open")
	elif reward != null and reward.rarity_for_presentation < GameTypes.Rarity.RARE:
		audio_event_requested.emit(&"normal_open")
	_update_view()


func _on_prealert_started(rarity: int) -> void:
	audio_event_requested.emit(
		&"legendary_prealert"
		if rarity == GameTypes.Rarity.LEGENDARY
		else &"epic_prealert"
	)


func _on_all_revealed() -> void:
	reveal_completed.emit()


func _initialize_controller(state: RunState) -> void:
	_controller.initialize(state)
	_last_rendered_revealed_count = -1
	_last_prealert_key = ""
	_update_view()


func _update_view() -> void:
	if not is_node_ready():
		return
	var presentation: Dictionary = _controller.presentation_state()
	_accessibility_status.text = "動き軽減 %s・点滅軽減 %s" % [
		"ON" if bool(presentation["reduce_motion"]) else "OFF",
		"ON" if bool(presentation["reduce_flashes"]) else "OFF",
	]
	_unopened_count.text = "未開封箱　%d" % _controller.unrevealed_count()
	_speed_label.text = (
		"4倍開封中（離すと通常速度）"
		if _controller.is_fast_open()
		else "長押し4倍　A／Enter またはマウス左"
	)
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
		_current_rarity.text = (
			"%s  %s"
			% [
				RewardRevealController.outline_token(reward),
				RewardRevealController.rarity_label(reward),
			]
		)
		_current_name.text = _reward_display_name(reward)
		_current_details.text = _reward_details(reward)
	else:
		_current_rarity.text = "未公開"
		_current_name.text = "箱を開封しています"
		_current_details.text = "内容は箱獲得時に確定済み"
	var rarity: int = reward.rarity_for_presentation if reward != null else -2
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
	if reward.rarity_for_presentation == -1:
		return str(reward.skill_id) if not reward.skill_id.is_empty() else "スキル"
	if reward.equipment == null:
		return "装備"
	return (
		reward.equipment.display_name
		if not reward.equipment.display_name.is_empty()
		else reward.equipment.item_id
	)


func _reward_details(reward: RewardRoll) -> String:
	if reward.rarity_for_presentation == -1:
		return "スキル報酬"
	if reward.equipment == null:
		return "装備報酬"
	return "部位 %s　item_id %s" % [
		GameTypes.equipment_slot_to_key(reward.equipment.slot),
		reward.equipment.item_id,
	]


func _card_style(rarity: int, outline_thickness: int, stage_light_step: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.content_margin_left = 24.0
	style.content_margin_top = 20.0
	style.content_margin_right = 24.0
	style.content_margin_bottom = 20.0
	var border_color: Color = _rarity_color(rarity)
	var background: Color = Color(0.055, 0.071, 0.09, 0.98)
	if stage_light_step > 0:
		background = background.lightened(0.08 * float(stage_light_step))
	style.bg_color = background
	style.border_color = border_color
	style.border_width_left = outline_thickness
	style.border_width_top = outline_thickness
	style.border_width_right = outline_thickness
	style.border_width_bottom = outline_thickness
	match rarity:
		GameTypes.Rarity.RARE:
			_set_corner_radii(style, 9, 9, 9, 9)
		GameTypes.Rarity.EPIC:
			_set_corner_radii(style, 20, 2, 20, 2)
		GameTypes.Rarity.LEGENDARY:
			_set_corner_radii(style, 28, 28, 28, 28)
		-1:
			_set_corner_radii(style, 32, 32, 32, 32)
		_:
			_set_corner_radii(style, 1, 1, 1, 1)
	return style


func _rarity_color(rarity: int) -> Color:
	match rarity:
		GameTypes.Rarity.COMMON:
			return Color(0.72, 0.76, 0.78, 1.0)
		GameTypes.Rarity.RARE:
			return Color(0.25, 0.67, 1.0, 1.0)
		GameTypes.Rarity.EPIC:
			return Color(0.78, 0.35, 1.0, 1.0)
		GameTypes.Rarity.LEGENDARY:
			return Color(1.0, 0.68, 0.18, 1.0)
		-1:
			return Color(0.35, 0.92, 0.72, 1.0)
	return Color(0.38, 0.44, 0.48, 1.0)


func _set_corner_radii(
	style: StyleBoxFlat,
	top_left: int,
	top_right: int,
	bottom_right: int,
	bottom_left: int,
) -> void:
	style.corner_radius_top_left = top_left
	style.corner_radius_top_right = top_right
	style.corner_radius_bottom_right = bottom_right
	style.corner_radius_bottom_left = bottom_left


func _current_focus_id() -> String:
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused == null:
		return "reward_speed_proxy"
	return str(focused.get_meta("focus_id", ""))


func _grab_focus_id(focus_id: String) -> bool:
	var control: Control = null
	match focus_id:
		"reward_speed_proxy":
			control = _speed_proxy
		"reward_open_all":
			control = _open_all
		"reward_settings":
			control = _settings
	if control == null or not control.is_visible_in_tree():
		return false
	if control is BaseButton and (control as BaseButton).disabled:
		return false
	control.grab_focus()
	return true


func _clear_children(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
