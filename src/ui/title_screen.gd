extends Control


signal start_requested
signal exit_requested

@onready var version_value: Label = %VersionValue
@onready var renderer_value: Label = %RendererValue
@onready var title_start: Button = %TitleStart
@onready var title_settings: Button = %TitleSettings
@onready var title_exit: Button = %TitleExit
@onready var _content_root: Control = $ContentMargin
@onready var _settings_overlay: SettingsOverlay = %SettingsOverlay

var _saved_focus_id: String = "title_start"
var _modal_focus := ModalFocusCoordinator.new()


func _ready() -> void:
	version_value.text = str(Engine.get_version_info().get("string", "unknown"))
	renderer_value.text = str(RenderingServer.get_current_rendering_method())
	title_start.set_meta("focus_id", "title_start")
	title_settings.set_meta("focus_id", "title_settings")
	title_exit.set_meta("focus_id", "title_exit")
	FocusController.configure_vertical_cycle([title_start, title_settings, title_exit])
	title_start.pressed.connect(_on_start_pressed)
	title_settings.pressed.connect(_on_settings_pressed)
	title_exit.pressed.connect(_on_exit_pressed)
	_settings_overlay.closed.connect(_on_settings_closed)
	_modal_focus.configure(get_viewport(), [_content_root])
	FocusController.grab_focus_deferred(title_start)


func focus_order() -> PackedStringArray:
	return PackedStringArray(["title_start", "title_settings", "title_exit"])


func initial_focus_control() -> Control:
	return title_start


func exit_focus_control() -> Control:
	return title_exit


func settings_focus_control() -> Control:
	return title_settings


func _on_start_pressed() -> void:
	if _modal_focus.has_active_modal():
		return
	start_requested.emit()


func _on_settings_pressed() -> void:
	if _modal_focus.has_active_modal():
		return
	var focused: Control = get_viewport().gui_get_focus_owner()
	_saved_focus_id = (
		str(focused.get_meta("focus_id", "title_start"))
		if focused != null
		else "title_start"
	)
	if not _modal_focus.push(_settings_overlay, title_start):
		return
	_settings_overlay.open_overlay()


func _on_settings_closed() -> void:
	_modal_focus.pop(_settings_overlay, null, title_start)


func _on_exit_pressed() -> void:
	if _modal_focus.has_active_modal():
		return
	exit_requested.emit()
