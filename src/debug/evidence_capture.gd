extends Node


func _ready() -> void:
	var scenario := _evidence_argument()
	if scenario != "gate_01:bootstrap":
		print("EVIDENCE_ARGUMENT_REJECTED name=--evidence")
		get_tree().quit(2)
		return
	_capture_bootstrap.call_deferred()


func _capture_bootstrap() -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image.get_width() < 1280 or image.get_height() < 720:
		print("EVIDENCE_CAPTURE_FAILED reason=resolution")
		get_tree().quit(1)
		return
	var output_directory := ProjectSettings.globalize_path("res://artifacts/gate-01")
	if not DirAccess.dir_exists_absolute(output_directory):
		var directory_error := DirAccess.make_dir_recursive_absolute(output_directory)
		if directory_error != OK:
			print("EVIDENCE_CAPTURE_FAILED reason=directory")
			get_tree().quit(1)
			return
	var output_path := output_directory.path_join("bootstrap.png")
	var save_error := image.save_png(output_path)
	if save_error != OK:
		print("EVIDENCE_CAPTURE_FAILED reason=save")
		get_tree().quit(1)
		return
	print("EVIDENCE_OK path=%s" % output_path)
	get_tree().quit(0)


func _evidence_argument() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--evidence="):
			return argument.trim_prefix("--evidence=")
	return ""
