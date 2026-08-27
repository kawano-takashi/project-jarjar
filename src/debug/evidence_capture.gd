extends Node


const LogicDiagnosticsScript = preload("res://src/debug/logic_diagnostics.gd")

@onready var _diagnostics_layer: CanvasLayer = $DiagnosticsLayer
@onready var _seed_line: Label = $DiagnosticsLayer/Backdrop/Margin/Content/SeedLine
@onready var _left_text: RichTextLabel = $DiagnosticsLayer/Backdrop/Margin/Content/Columns/LeftPanel/Margin/Text
@onready var _right_text: RichTextLabel = $DiagnosticsLayer/Backdrop/Margin/Content/Columns/RightPanel/Margin/Text


func _ready() -> void:
	match _evidence_argument():
		"gate_02:logic_diagnostics":
			_capture_logic_diagnostics.call_deferred()
		"gate_03:arena_combat":
			_capture_combat.bind("arena_combat").call_deferred()
		"gate_03:weapon_shapes":
			_capture_combat.bind("weapon_shapes").call_deferred()
		"gate_03:boss_gate":
			_capture_combat.bind("boss_gate").call_deferred()
		_:
			print("EVIDENCE_ARGUMENT_REJECTED name=--evidence")
			get_tree().quit(2)


func _capture_combat(scenario_name: String) -> void:
	_diagnostics_layer.visible = false
	await _capture_png("gate-03", scenario_name)


func _capture_logic_diagnostics() -> void:
	var diagnostics: Dictionary = LogicDiagnosticsScript.build()
	if not diagnostics["valid"]:
		print("EVIDENCE_CAPTURE_FAILED reason=%s" % diagnostics.get("reason", "diagnostics"))
		get_tree().quit(1)
		return
	_seed_line.text = diagnostics["seed_line"]
	_left_text.text = diagnostics["left_text"]
	_right_text.text = diagnostics["right_text"]
	_diagnostics_layer.visible = true
	await _capture_png("gate-02", "logic_diagnostics")


func _capture_png(gate_directory: String, scenario_name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	if image.get_width() < 1280 or image.get_height() < 720:
		print("EVIDENCE_CAPTURE_FAILED reason=resolution")
		get_tree().quit(1)
		return
	var output_directory: String = ProjectSettings.globalize_path(
		"res://artifacts/%s" % gate_directory
	)
	if not DirAccess.dir_exists_absolute(output_directory):
		var directory_error: Error = DirAccess.make_dir_recursive_absolute(output_directory)
		if directory_error != OK:
			print("EVIDENCE_CAPTURE_FAILED reason=directory")
			get_tree().quit(1)
			return
	var output_path: String = output_directory.path_join("%s.png" % scenario_name)
	var save_error: Error = image.save_png(output_path)
	if save_error != OK:
		print("EVIDENCE_CAPTURE_FAILED reason=save")
		get_tree().quit(1)
		return
	print("EVIDENCE_OK path=%s" % output_path)
	get_tree().quit(0)


func _evidence_argument() -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--evidence="):
			return argument.trim_prefix("--evidence=")
	return ""
