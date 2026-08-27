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
		"gate_04:chest_absorb":
			_capture_gate_four.bind("chest_absorb").call_deferred()
		"gate_04:epic_prealert":
			_capture_gate_four.bind("epic_prealert").call_deferred()
		"gate_04:reward_grid":
			_capture_gate_four.bind("reward_grid").call_deferred()
		"gate_05:inventory_full":
			_capture_gate_five.bind("inventory_full").call_deferred()
		"gate_05:fusion_unique_warning":
			_capture_gate_five.bind("fusion_unique_warning").call_deferred()
		"gate_05:broken_build":
			_capture_gate_five.bind("broken_build").call_deferred()
		"gate_05:final_result":
			_capture_gate_five.bind("final_result").call_deferred()
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


func _capture_gate_four(scenario_name: String) -> void:
	_diagnostics_layer.visible = false
	await _capture_png("gate-04", scenario_name)


func _capture_gate_five(scenario_name: String) -> void:
	_diagnostics_layer.visible = false
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var game_app: Node = get_parent()
	if game_app == null or not game_app.has_method("validate_evidence_capture_state"):
		_fail_capture("gate05_validator")
		return
	var evidence_id := "gate_05:%s" % scenario_name
	var validation_value: Variant = game_app.call(
		"validate_evidence_capture_state",
		evidence_id,
	)
	if not validation_value is Dictionary:
		_fail_capture("gate05_validation")
		return
	var validation: Dictionary = validation_value as Dictionary
	if not bool(validation.get("valid", false)):
		_fail_capture(str(validation.get("reason", "gate05_validation")))
		return
	await _capture_png("gate-05", scenario_name, true)


func _capture_png(
	gate_directory: String,
	scenario_name: String,
	require_visual_variation: bool = false,
) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	if image.get_width() < 1280 or image.get_height() < 720:
		_fail_capture("resolution")
		return
	if require_visual_variation and not _has_visual_variation(image):
		_fail_capture("blank_frame")
		return
	var output_directory: String = ProjectSettings.globalize_path(
		"res://artifacts/%s" % gate_directory
	)
	if not DirAccess.dir_exists_absolute(output_directory):
		var directory_error: Error = DirAccess.make_dir_recursive_absolute(output_directory)
		if directory_error != OK:
			_fail_capture("directory")
			return
	var output_path: String = output_directory.path_join("%s.png" % scenario_name)
	var save_error: Error = image.save_png(output_path)
	if save_error != OK:
		_fail_capture("save")
		return
	print("EVIDENCE_OK path=%s" % output_path)
	get_tree().quit(0)


func _has_visual_variation(image: Image) -> bool:
	var width: int = image.get_width()
	var height: int = image.get_height()
	if width <= 0 or height <= 0:
		return false
	var baseline: Color = image.get_pixel(0, 0)
	var step_x: int = maxi(1, floori(float(width) / 32.0))
	var step_y: int = maxi(1, floori(float(height) / 18.0))
	for y: int in range(0, height, step_y):
		for x: int in range(0, width, step_x):
			var sample: Color = image.get_pixel(x, y)
			if (
				absf(sample.r - baseline.r) > 0.01
				or absf(sample.g - baseline.g) > 0.01
				or absf(sample.b - baseline.b) > 0.01
				or absf(sample.a - baseline.a) > 0.01
			):
				return true
	return false


func _fail_capture(reason: String) -> void:
	print("EVIDENCE_CAPTURE_FAILED reason=%s" % reason)
	get_tree().quit(1)


func _evidence_argument() -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--evidence="):
			return argument.trim_prefix("--evidence=")
	return ""
