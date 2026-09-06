extends SceneTree

## Dedicated development entrypoint. Options follow "--"; see README.md.


func _initialize() -> void:
	_start.call_deferred()


func _start() -> void:
	var app_script := load("res://dev/bot/bot_app.gd") as Script
	if app_script == null or not app_script.can_instantiate():
		print("BOT_ERROR application_load_failed")
		quit(2)
		return
	var app: Node = app_script.new()
	root.add_child(app)
	current_scene = app
	if not app.get("_launch_valid"):
		quit(2)
