class_name SettingsOverlay
extends Control


signal closed
signal settings_changed(values: Dictionary)

@onready var _master: HSlider = %SettingsMaster
@onready var _sfx: HSlider = %SettingsSfx
@onready var _reduce_motion: CheckButton = %SettingsReduceMotion
@onready var _reduce_flashes: CheckButton = %SettingsReduceFlashes
@onready var _vibration: CheckButton = %SettingsVibration
@onready var _tutorial_again: Button = %SettingsTutorialAgain
@onready var _close: Button = %SettingsClose
@onready var _master_value: Label = %MasterValue
@onready var _sfx_value: Label = %SfxValue

var _settings_store: Variant = null
var _synchronizing: bool = false
var _focus_controller := FocusController.new()


func _ready() -> void:
	_settings_store = get_node_or_null("/root/SettingsStore")
	_configure_focus()
	_master.value_changed.connect(_on_volume_changed)
	_sfx.value_changed.connect(_on_volume_changed)
	_reduce_motion.toggled.connect(_on_toggle_changed)
	_reduce_flashes.toggled.connect(_on_toggle_changed)
	_vibration.toggled.connect(_on_toggle_changed)
	_tutorial_again.pressed.connect(_on_tutorial_again_pressed)
	_close.pressed.connect(close_overlay)
	visible = false
	set_process_input(false)
	set_process_unhandled_input(false)


func open_overlay() -> void:
	_sync_from_store()
	visible = true
	set_process_input(true)
	FocusController.grab_focus_deferred(_master)


func close_overlay() -> void:
	if not visible:
		return
	_apply_to_store()
	if _settings_store != null and not str(_settings_store.active_settings_path).is_empty():
		_settings_store.save_settings()
	visible = false
	set_process_input(false)
	set_process_unhandled_input(false)
	closed.emit()


func focus_order() -> PackedStringArray:
	return PackedStringArray([
		"settings_master",
		"settings_sfx",
		"settings_reduce_motion",
		"settings_reduce_flashes",
		"settings_vibration",
		"settings_tutorial_again",
		"settings_close",
	])


func initial_focus_control() -> Control:
	return _master


func focus_controls() -> Dictionary:
	var result: Dictionary = {}
	for focus_id: String in _focus_controller.focus_ids():
		result[focus_id] = _focus_controller.control_for_id(focus_id)
	return result


func focus_control(focus_id: String) -> Control:
	return _focus_controller.control_for_id(focus_id)


func test_focus(focus_id: String) -> bool:
	return _focus_controller.grab_focus_id(focus_id)


func settings_values() -> Dictionary:
	return {
		"master_volume": _master.value / 100.0,
		"sfx_volume": _sfx.value / 100.0,
		"reduce_motion": _reduce_motion.button_pressed,
		"reduce_flashes": _reduce_flashes.button_pressed,
		"controller_vibration": _vibration.button_pressed,
	}


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		close_overlay()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"ui_focus_next") and not event.is_echo():
		_focus_controller.move_tab(get_viewport(), true)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"ui_focus_prev") and not event.is_echo():
		_focus_controller.move_tab(get_viewport(), false)
		get_viewport().set_input_as_handled()


func _configure_focus() -> void:
	var controls: Array = [
		_master,
		_sfx,
		_reduce_motion,
		_reduce_flashes,
		_vibration,
		_tutorial_again,
		_close,
	]
	var ids: PackedStringArray = focus_order()
	var control_map: Dictionary = {}
	var graph: Dictionary = {}
	for index: int in range(controls.size()):
		var control: Control = controls[index] as Control
		var focus_id: String = ids[index]
		control_map[focus_id] = control
		graph[focus_id] = {
			FocusController.DIRECTION_TOP: ids[posmod(index - 1, ids.size())],
			FocusController.DIRECTION_BOTTOM: ids[(index + 1) % ids.size()],
			FocusController.DIRECTION_LEFT: focus_id,
			FocusController.DIRECTION_RIGHT: focus_id,
		}
	_focus_controller.configure_graph(control_map, graph, ids[0], ids)


func _sync_from_store() -> void:
	_synchronizing = true
	if _settings_store != null:
		_master.value = roundf(float(_settings_store.master_volume) * 100.0)
		_sfx.value = roundf(float(_settings_store.sfx_volume) * 100.0)
		_reduce_motion.button_pressed = bool(_settings_store.reduce_motion)
		_reduce_flashes.button_pressed = bool(_settings_store.reduce_flashes)
		_vibration.button_pressed = bool(_settings_store.controller_vibration)
	else:
		_master.value = 100.0
		_sfx.value = 90.0
		_reduce_motion.button_pressed = false
		_reduce_flashes.button_pressed = false
		_vibration.button_pressed = true
	_synchronizing = false
	_update_value_labels()


func _apply_to_store() -> void:
	if _settings_store == null:
		return
	var values: Dictionary = settings_values()
	_settings_store.master_volume = values["master_volume"]
	_settings_store.sfx_volume = values["sfx_volume"]
	_settings_store.reduce_motion = values["reduce_motion"]
	_settings_store.reduce_flashes = values["reduce_flashes"]
	_settings_store.controller_vibration = values["controller_vibration"]


func _on_volume_changed(_value: float) -> void:
	if _synchronizing:
		return
	_update_value_labels()
	_apply_and_emit()


func _on_toggle_changed(_pressed: bool) -> void:
	if _synchronizing:
		return
	_apply_and_emit()


func _on_tutorial_again_pressed() -> void:
	if _settings_store != null:
		_settings_store.tutorial_revision = 0
	_apply_and_emit()


func _apply_and_emit() -> void:
	_apply_to_store()
	settings_changed.emit(settings_values())


func _update_value_labels() -> void:
	_master_value.text = "%d" % int(roundf(_master.value))
	_sfx_value.text = "%d" % int(roundf(_sfx.value))
