extends Control


signal back_requested
signal exit_requested

@onready var back_button: Button = %BackButton
@onready var exit_button: Button = %ExitButton


func _ready() -> void:
	FocusController.configure_vertical_cycle([back_button, exit_button])
	back_button.pressed.connect(func() -> void: back_requested.emit())
	exit_button.pressed.connect(func() -> void: exit_requested.emit())
	back_button.call_deferred("grab_focus")
