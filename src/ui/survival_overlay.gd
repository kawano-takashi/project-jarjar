class_name SurvivalOverlay
extends CanvasLayer


signal level_choice_requested(choice_index: int)
signal chest_continue_requested
signal pause_resume_requested
signal title_requested
signal settings_changed(values: Dictionary)

const CHEST_DISPLAY_SECONDS: float = 2.0
const StrictChestActionScript = preload("res://src/ui/strict_chest_action.gd")

@onready var _level_modal: Control = %LevelUpModal
@onready var _level_buttons: Array[Button] = [
	%LevelChoice0,
	%LevelChoice1,
	%LevelChoice2,
]
@onready var _chest_modal: Control = %ChestModal
@onready var _chest_heading: Label = %ChestHeading
@onready var _chest_result: Label = %ChestResult
@onready var _chest_continue: Control = %ChestContinue
@onready var _pause_modal: Control = %PauseModal
@onready var _pause_resume: Button = %PauseResume
@onready var _pause_settings: Button = %PauseSettings
@onready var _pause_title: Button = %PauseTitle
@onready var _pause_build: Label = %PauseBuild
@onready var _evolution_guide: Label = %EvolutionGuide
@onready var _settings: SettingsOverlay = %SettingsOverlay
@onready var _title_confirmation: JarjarConfirmationDialog = %TitleConfirmation

var _catalog: DefinitionCatalog = null
var _active_offer_serial: int = -1
var _active_chest_serial: int = -1
var _chest_remaining: float = 0.0
var _chest_continue_emitted: bool = false
var _pause_build_values: Dictionary = {}


func _ready() -> void:
	for index: int in range(_level_buttons.size()):
		_level_buttons[index].pressed.connect(_on_level_choice_pressed.bind(index))
	_chest_continue.connect("activated", _request_chest_continue)
	_pause_resume.pressed.connect(_request_pause_resume)
	_pause_settings.pressed.connect(_open_settings)
	_pause_title.pressed.connect(_open_title_confirmation)
	_settings.closed.connect(_on_settings_closed)
	_settings.settings_changed.connect(func(values: Dictionary) -> void:
		settings_changed.emit(values)
	)
	_title_confirmation.cancelled.connect(_on_title_confirmation_cancelled)
	_title_confirmation.confirmed.connect(_on_title_confirmation_confirmed)
	FocusController.configure_horizontal_cycle(_level_buttons)
	FocusController.configure_vertical_cycle([
		_pause_resume,
		_pause_settings,
		_pause_title,
	])
	_refresh_evolution_guide()
	_hide_primary_modals()
	set_process_unhandled_input(true)


func initialize(catalog: DefinitionCatalog) -> void:
	_catalog = catalog
	if is_node_ready():
		_refresh_evolution_guide()


func _process(delta: float) -> void:
	if not _chest_modal.visible or _chest_continue_emitted or delta <= 0.0:
		return
	_chest_remaining = maxf(0.0, _chest_remaining - delta)
	if _chest_remaining <= 0.0:
		_request_chest_continue()


func show_level_offer(offer: Variant) -> void:
	_hide_primary_modals()
	_active_offer_serial = int(_read_property(offer, &"serial", -1))
	var options: Array = []
	var options_value: Variant = _read_property(offer, &"options", [])
	if options_value is Array:
		options.assign(options_value)
	var visible_buttons: Array = []
	for index: int in range(_level_buttons.size()):
		var button: Button = _level_buttons[index]
		button.visible = index < options.size()
		button.disabled = index >= options.size()
		if index >= options.size():
			button.text = ""
			continue
		button.text = _option_text(options[index])
		button.accessibility_name = str(_read_property(options[index], &"display_name", "選択肢"))
		visible_buttons.append(button)
	if visible_buttons.is_empty():
		return
	FocusController.configure_horizontal_cycle(visible_buttons)
	_level_modal.visible = true
	FocusController.grab_focus_deferred(visible_buttons[0] as Control)


func show_chest_outcome(outcome: Variant) -> void:
	_hide_primary_modals()
	_active_chest_serial = int(_read_property(outcome, &"serial", -1))
	var display_name: String = str(_read_property(outcome, &"display_name", ""))
	var upgrade_detail: String = str(_read_property(outcome, &"upgrade_detail", ""))
	var source_weapon_id: String = str(_read_property(outcome, &"source_weapon_id", ""))
	var previous_level: int = int(_read_property(outcome, &"previous_level", 0))
	var new_level: int = int(_read_property(outcome, &"new_level", previous_level))
	if not source_weapon_id.is_empty():
		_chest_heading.text = "EVOLUTION"
		_chest_result.text = "%s\n進化完了" % (display_name if not display_name.is_empty() else "武器")
	elif not display_name.is_empty() and new_level > previous_level:
		_chest_heading.text = "宝箱強化"
		_chest_result.text = "%s\nLv %d → %d" % [display_name, previous_level, new_level]
		if not upgrade_detail.is_empty():
			_chest_result.text += "\n%s" % upgrade_detail
	else:
		_chest_heading.text = "宝箱"
		_chest_result.text = "HPを全回復しました"
	_chest_remaining = CHEST_DISPLAY_SECONDS
	_chest_continue_emitted = false
	_chest_modal.visible = true
	FocusController.grab_focus_deferred(_chest_continue)


func update_build_from_values(values: Dictionary) -> void:
	_pause_build_values = values.duplicate(true)
	if is_node_ready():
		_refresh_pause_build()


func hide_automatic_modal() -> void:
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	if (
		focus_owner != null
		and (
			_level_modal.is_ancestor_of(focus_owner)
			or _chest_modal.is_ancestor_of(focus_owner)
		)
	):
		get_viewport().gui_release_focus()
	_level_modal.visible = false
	_chest_modal.visible = false
	_active_offer_serial = -1
	_active_chest_serial = -1
	_chest_remaining = 0.0


func open_pause() -> bool:
	if automatic_modal_visible() or _pause_modal.visible:
		return false
	_pause_modal.visible = true
	_refresh_pause_build()
	FocusController.grab_focus_deferred(_pause_resume)
	return true


func close_pause() -> bool:
	if not _pause_modal.visible or _settings.visible or _title_confirmation.visible:
		return false
	_pause_modal.visible = false
	return true


func pause_visible() -> bool:
	return _pause_modal.visible


func automatic_modal_visible() -> bool:
	return _level_modal.visible or _chest_modal.visible


func active_offer_serial() -> int:
	return _active_offer_serial


func active_chest_serial() -> int:
	return _active_chest_serial


func debug_state() -> Dictionary:
	var option_texts := PackedStringArray()
	for button: Button in _level_buttons:
		if button.visible:
			option_texts.append(button.text)
	return {
		"level_visible": _level_modal.visible,
		"chest_visible": _chest_modal.visible,
		"pause_visible": _pause_modal.visible,
		"settings_visible": _settings.visible,
		"confirmation_visible": _title_confirmation.visible,
		"offer_serial": _active_offer_serial,
		"chest_serial": _active_chest_serial,
		"chest_remaining": _chest_remaining,
		"option_texts": option_texts,
		"chest_heading": _chest_heading.text,
		"chest_result": _chest_result.text,
		"evolution_guide": _evolution_guide.text,
		"pause_build": _pause_build.text,
	}


func test_choose(choice_index: int) -> void:
	_on_level_choice_pressed(choice_index)


func test_skip_chest() -> void:
	_request_chest_continue()


func _unhandled_input(event: InputEvent) -> void:
	if _settings.visible or _title_confirmation.visible:
		return
	if _level_modal.visible:
		if event.is_action_pressed(&"ui_cancel") and not event.is_echo():
			get_viewport().set_input_as_handled()
		return
	if _chest_modal.visible:
		if event is InputEventKey or event is InputEventJoypadButton:
			if StrictChestActionScript.is_activation_event(event):
				_request_chest_continue()
			get_viewport().set_input_as_handled()
		return
	if _pause_modal.visible and event.is_action_pressed(&"ui_cancel") and not event.is_echo():
		_request_pause_resume()
		get_viewport().set_input_as_handled()


func _on_level_choice_pressed(choice_index: int) -> void:
	if not _level_modal.visible or choice_index < 0 or choice_index >= _level_buttons.size():
		return
	if not _level_buttons[choice_index].visible or _level_buttons[choice_index].disabled:
		return
	for button: Button in _level_buttons:
		button.disabled = true
	level_choice_requested.emit(choice_index)


func _request_chest_continue() -> void:
	if not _chest_modal.visible or _chest_continue_emitted:
		return
	_chest_continue_emitted = true
	_chest_continue.set("disabled", true)
	chest_continue_requested.emit()


func _request_pause_resume() -> void:
	if not close_pause():
		return
	pause_resume_requested.emit()


func _open_settings() -> void:
	if not _pause_modal.visible:
		return
	_set_pause_buttons_enabled(false)
	_settings.open_overlay()


func _on_settings_closed() -> void:
	_set_pause_buttons_enabled(true)
	FocusController.grab_focus_deferred(_pause_settings)


func _open_title_confirmation() -> void:
	if not _pause_modal.visible:
		return
	_set_pause_buttons_enabled(false)
	_title_confirmation.open_dialog(
		"タイトルへ戻る",
		"現在のランは終了します。タイトルへ戻りますか？",
		"タイトルへ戻る",
		"pause_title",
	)


func _on_title_confirmation_cancelled() -> void:
	_set_pause_buttons_enabled(true)
	FocusController.grab_focus_deferred(_pause_title)


func _on_title_confirmation_confirmed() -> void:
	_pause_modal.visible = false
	title_requested.emit()


func _set_pause_buttons_enabled(enabled: bool) -> void:
	for button: Button in [_pause_resume, _pause_settings, _pause_title]:
		button.disabled = not enabled


func _hide_primary_modals() -> void:
	hide_automatic_modal()
	_pause_modal.visible = false
	_chest_continue.set("disabled", false)


func _option_text(option: Variant) -> String:
	var display_name: String = str(_read_property(option, &"display_name", "選択肢"))
	var description: String = str(_read_property(option, &"description", ""))
	var upgrade_detail: String = str(_read_property(option, &"upgrade_detail", ""))
	var pairing_hint: String = str(_read_property(option, &"pairing_hint", ""))
	var current_level: int = int(_read_property(option, &"current_level", 0))
	var next_level: int = int(_read_property(option, &"next_level", current_level + 1))
	var level_text: String = "新規 Lv %d" % next_level if current_level <= 0 else "Lv %d → %d" % [current_level, next_level]
	var kind: int = int(_read_property(option, &"kind", -1))
	var lines := PackedStringArray([
		display_name,
		level_text,
		"種別：%s" % _upgrade_kind_label(kind),
	])
	var body_text: String = description if current_level <= 0 else upgrade_detail
	if not body_text.is_empty():
		lines.append("")
		lines.append(body_text)
	if not pairing_hint.is_empty():
		lines.append("")
		lines.append(pairing_hint)
	return "\n".join(lines)


func _upgrade_kind_label(kind: int) -> String:
	match kind:
		GameTypes.UpgradeKind.WEAPON:
			return "武器"
		GameTypes.UpgradeKind.PASSIVE:
			return "パッシブ"
	return "不明"


func _refresh_evolution_guide() -> void:
	if _catalog == null:
		_evolution_guide.text = "進化ペアを読み込み中"
		return
	var lines := PackedStringArray()
	for base_weapon_id: StringName in _catalog.basic_weapon_ids():
		var evolution: EvolutionDefinition = _catalog.evolution_for_weapon(base_weapon_id)
		var base_weapon: WeaponDefinition = _catalog.weapon(base_weapon_id)
		if evolution == null or base_weapon == null:
			continue
		var passive: PassiveDefinition = _catalog.passive(evolution.passive_id)
		var evolved_weapon: WeaponDefinition = _catalog.weapon(evolution.evolved_weapon_id)
		if passive == null or evolved_weapon == null:
			continue
		lines.append("%s Lv8 ＋ 触媒：%s Lv1以上 → %s" % [
			base_weapon.display_name,
			passive.display_name,
			evolved_weapon.display_name,
		])
	_evolution_guide.text = "\n".join(lines)


func _refresh_pause_build() -> void:
	var weapon_lines := PackedStringArray()
	var passive_lines := PackedStringArray()
	var weapons_value: Variant = _pause_build_values.get("weapons", [])
	var passives_value: Variant = _pause_build_values.get("passives", [])
	if weapons_value is Array:
		for entry: Variant in weapons_value as Array:
			var weapon_name: String = str(_read_property(entry, &"display_name", "武器"))
			var weapon_level: int = maxi(1, int(_read_property(entry, &"level", 1)))
			var evolved: bool = bool(_read_property(entry, &"evolved", false))
			weapon_lines.append("%s  %s" % [
				weapon_name,
				"EVOLVED" if evolved else "Lv %d" % weapon_level,
			])
	if passives_value is Array:
		for entry: Variant in passives_value as Array:
			passive_lines.append("%s  Lv %d" % [
				str(_read_property(entry, &"display_name", "パッシブ")),
				maxi(1, int(_read_property(entry, &"level", 1))),
			])
	_pause_build.text = "武器　%s\nパッシブ　%s" % [
		"　｜　".join(weapon_lines) if not weapon_lines.is_empty() else "なし",
		"　｜　".join(passive_lines) if not passive_lines.is_empty() else "なし",
	]


func _read_property(value: Variant, property_name: StringName, fallback: Variant) -> Variant:
	if value is Dictionary:
		return (value as Dictionary).get(property_name, fallback)
	if value is Object:
		var object := value as Object
		for property: Dictionary in object.get_property_list():
			if StringName(property.get("name", "")) == property_name:
				return object.get(property_name)
	return fallback
