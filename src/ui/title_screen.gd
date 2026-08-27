extends Control


signal start_requested
signal exit_requested

@onready var version_value: Label = %VersionValue
@onready var renderer_value: Label = %RendererValue
@onready var title_start: Button = %TitleStart
@onready var title_exit: Button = %TitleExit


func _ready() -> void:
	version_value.text = str(Engine.get_version_info().get("string", "unknown"))
	renderer_value.text = str(RenderingServer.get_current_rendering_method())
	title_start.set_meta("focus_id", "title_start")
	title_exit.set_meta("focus_id", "title_exit")
	FocusController.configure_vertical_cycle([title_start, title_exit])
	title_start.pressed.connect(_on_start_pressed)
	title_exit.pressed.connect(_on_exit_pressed)
	title_start.call_deferred("grab_focus")


func focus_order() -> PackedStringArray:
	return PackedStringArray(["title_start", "title_exit"])


func initial_focus_control() -> Control:
	return title_start


func exit_focus_control() -> Control:
	return title_exit


func _on_start_pressed() -> void:
	start_requested.emit()


func _on_exit_pressed() -> void:
	exit_requested.emit()
