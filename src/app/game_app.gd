extends Node


const LaunchArgumentsScript = preload("res://src/app/launch_arguments.gd")
const BootstrapFlowScript = preload("res://src/core/bootstrap_flow.gd")
const DefinitionCatalogScript = preload("res://src/core/definition_catalog.gd")
const TITLE_SCENE: PackedScene = preload("res://scenes/ui/title_screen.tscn")
const BOOTSTRAP_CONFIRMATION_SCENE: PackedScene = preload("res://scenes/ui/bootstrap_confirmation.tscn")

var _launch_valid: bool = false
var _launch: Dictionary = {}
var _bootstrap_flow: Variant = null
var _definition_catalog: DefinitionCatalog = null
var _active_screen: Control = null
var _smoke_frames_remaining: int = 0


func _enter_tree() -> void:
	_launch = (
		LaunchArgumentsScript.parse_debug(OS.get_cmdline_user_args())
		if OS.is_debug_build()
		else LaunchArgumentsScript.parse_release(OS.get_cmdline_user_args())
	)
	if not _launch["valid"]:
		_reject_arguments(_launch["rejected_name"])
		return

	var settings_store: Variant = get_node_or_null("/root/SettingsStore")
	if settings_store == null:
		print("SETTINGS_INITIALIZATION_FAILED code=%d" % ERR_DOES_NOT_EXIST)
		_quit_deferred(1)
		return

	var initialize_error: Error = OK
	match _launch["mode"]:
		LaunchArgumentsScript.MODE_RELEASE_SMOKE:
			initialize_error = settings_store.initialize_ephemeral()
		LaunchArgumentsScript.MODE_RELEASE_PACK_AUDIT:
			_launch_valid = true
			_quit_deferred(0)
			return
		_:
			initialize_error = settings_store.initialize_for_game(_launch["settings_path"])
	if initialize_error != OK:
		print("SETTINGS_INITIALIZATION_FAILED code=%d" % initialize_error)
		_quit_deferred(1)
		return

	_definition_catalog = DefinitionCatalogScript.new()
	if not _definition_catalog.load_and_validate():
		print(
			"DEFINITION_CATALOG_INVALID count=%d"
			% _definition_catalog.validation_errors.size()
		)
		_quit_deferred(2)
		return

	_bootstrap_flow = BootstrapFlowScript.new()
	_launch_valid = true


func _ready() -> void:
	if not _launch_valid or _launch["mode"] == LaunchArgumentsScript.MODE_RELEASE_PACK_AUDIT:
		return
	_show_title()


func _physics_process(_delta: float) -> void:
	if _smoke_frames_remaining <= 0:
		return
	_smoke_frames_remaining -= 1
	if _smoke_frames_remaining == 0:
		get_tree().quit(0)


func current_bootstrap_state() -> StringName:
	if _bootstrap_flow == null:
		return &""
	return _bootstrap_flow.current_state


func _show_title() -> void:
	_clear_active_screen()
	if _bootstrap_flow.current_state == BootstrapFlowScript.BOOT:
		if not _bootstrap_flow.transition_to_title():
			print("BOOTSTRAP_TRANSITION_FAILED")
			get_tree().quit(1)
			return
	var title_screen := TITLE_SCENE.instantiate() as Control
	_active_screen = title_screen
	title_screen.connect("start_requested", _show_bootstrap_confirmation)
	title_screen.connect("exit_requested", _exit_game)
	add_child(title_screen)

	match _launch["mode"]:
		LaunchArgumentsScript.MODE_SMOKE_QUIT:
			_smoke_frames_remaining = _launch["smoke_frames"]
		LaunchArgumentsScript.MODE_RELEASE_SMOKE:
			_smoke_frames_remaining = 1
		LaunchArgumentsScript.MODE_EVIDENCE:
			_attach_evidence_capture()


func _show_bootstrap_confirmation() -> void:
	_clear_active_screen()
	var confirmation := BOOTSTRAP_CONFIRMATION_SCENE.instantiate() as Control
	_active_screen = confirmation
	confirmation.connect("back_requested", _show_title)
	confirmation.connect("exit_requested", _exit_game)
	add_child(confirmation)


func _attach_evidence_capture() -> void:
	var evidence_scene_resource := load("res://scenes/debug/evidence_scene.tscn")
	if not evidence_scene_resource is PackedScene:
		print("EVIDENCE_CAPTURE_FAILED reason=scene")
		get_tree().quit(1)
		return
	add_child((evidence_scene_resource as PackedScene).instantiate())


func _clear_active_screen() -> void:
	if _active_screen != null:
		_active_screen.queue_free()
		_active_screen = null


func _reject_arguments(argument_name: String) -> void:
	if OS.is_debug_build():
		print("DEBUG_ARGUMENT_REJECTED name=%s child_nodes=0 run_state=0" % argument_name)
	else:
		print("RELEASE_ARGUMENT_REJECTED name=%s" % argument_name)
	_quit_deferred(2)


func _quit_deferred(exit_code: int) -> void:
	get_tree().call_deferred("quit", exit_code)


func _exit_game() -> void:
	get_tree().quit(0)
