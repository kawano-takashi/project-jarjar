extends Control


signal start_requested
signal exit_requested

@onready var version_value: Label = %VersionValue
@onready var renderer_value: Label = %RendererValue
@onready var title_start: Button = %TitleStart
@onready var title_settings: Button = %TitleSettings
@onready var title_exit: Button = %TitleExit
@onready var _settings_overlay: SettingsOverlay = %SettingsOverlay

var _saved_focus_id: String = "title_start"


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
	start_requested.emit()


func _on_settings_pressed() -> void:
	var focused: Control = get_viewport().gui_get_focus_owner()
	_saved_focus_id = (
		str(focused.get_meta("focus_id", "title_start"))
		if focused != null
		else "title_start"
	)
	_settings_overlay.open_overlay()


func _on_settings_closed() -> void:
	var target: Control = title_start
	if _saved_focus_id == "title_settings":
		target = title_settings
	elif _saved_focus_id == "title_exit":
		target = title_exit
	FocusController.grab_focus_deferred(target)


func _on_exit_pressed() -> void:
	exit_requested.emit()
