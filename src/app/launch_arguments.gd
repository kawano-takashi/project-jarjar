class_name LaunchArguments
extends RefCounted


const MODE_NORMAL: StringName = &"normal"
const MODE_EVIDENCE: StringName = &"evidence"
const MODE_SMOKE_QUIT: StringName = &"smoke_quit"
const MODE_QA_SCENARIO: StringName = &"qa_scenario"
const MODE_PERFORMANCE: StringName = &"performance"
const MODE_RELEASE_SMOKE: StringName = &"release_smoke"
const MODE_RELEASE_PACK_AUDIT: StringName = &"release_pack_audit"

const DEBUG_OPTIONS: Array[String] = [
	"--evidence",
	"--qa-scenario",
	"--settings-path",
	"--smoke-quit",
	"--performance",
	"--run-seed",
]


static func parse_debug(arguments: PackedStringArray) -> Dictionary:
	if arguments.is_empty():
		return _accepted(MODE_NORMAL, "user://settings.cfg")

	var parsed := _parse_named_values(arguments, DEBUG_OPTIONS)
	if not parsed["valid"]:
		return parsed

	var values: Dictionary = parsed["values"]
	var settings_path := ""
	if values.has("--settings-path"):
		settings_path = _normalize_test_settings_path(values["--settings-path"])
		if settings_path.is_empty():
			return _rejected("--settings-path")

	if values.size() == 2 and values.has("--evidence") and values.has("--settings-path"):
		if values["--evidence"] != "gate_01:bootstrap":
			return _rejected("--evidence")
		var result := _accepted(MODE_EVIDENCE, settings_path)
		result["evidence"] = values["--evidence"]
		return result

	if values.size() == 2 and values.has("--smoke-quit") and values.has("--settings-path"):
		var frame_text: String = values["--smoke-quit"]
		if not frame_text.is_valid_int():
			return _rejected("--smoke-quit")
		var frame_count := frame_text.to_int()
		if frame_count < 1:
			return _rejected("--smoke-quit")
		var result := _accepted(MODE_SMOKE_QUIT, settings_path)
		result["smoke_frames"] = frame_count
		return result

	if values.size() == 2 and values.has("--qa-scenario") and values.has("--settings-path"):
		var result := _accepted(MODE_QA_SCENARIO, settings_path)
		result["qa_scenario"] = values["--qa-scenario"]
		return result

	if (
		values.size() == 3
		and values.has("--performance")
		and values.has("--run-seed")
		and values.has("--settings-path")
	):
		if values["--performance"] != "full_hd_500_2000" or values["--run-seed"] != "5002000":
			return _rejected("--performance")
		var result := _accepted(MODE_PERFORMANCE, settings_path)
		result["performance"] = values["--performance"]
		result["run_seed"] = 5002000
		return result

	if values.size() == 1 and values.has("--settings-path"):
		return _rejected("--settings-path")
	return _rejected(_first_option_name(arguments))


static func parse_release(arguments: PackedStringArray) -> Dictionary:
	if arguments.is_empty():
		return _accepted(MODE_NORMAL, "user://settings.cfg")
	if arguments.size() != 1:
		return _rejected(_first_option_name(arguments))
	if arguments[0] == "--smoke-run":
		return _accepted(MODE_RELEASE_SMOKE, "")
	if arguments[0].begins_with("--release-pack-audit="):
		var manifest_path := arguments[0].trim_prefix("--release-pack-audit=").replace("\\", "/").simplify_path()
		if manifest_path.is_empty() or not manifest_path.is_absolute_path():
			return _rejected("--release-pack-audit")
		var result := _accepted(MODE_RELEASE_PACK_AUDIT, "")
		result["manifest_path"] = manifest_path
		return result
	return _rejected(_option_name(arguments[0]))


static func _parse_named_values(arguments: PackedStringArray, allowed: Array[String]) -> Dictionary:
	var values: Dictionary = {}
	for argument in arguments:
		var option_name := _option_name(argument)
		if not option_name in allowed:
			return _rejected(option_name)
		if values.has(option_name):
			return _rejected(option_name)
		if not argument.contains("="):
			return _rejected(option_name)
		var value := argument.substr(argument.find("=") + 1)
		if value.is_empty():
			return _rejected(option_name)
		values[option_name] = value
	return {"valid": true, "values": values}


static func _normalize_test_settings_path(path: String) -> String:
	var normalized := path.replace("\\", "/").simplify_path()
	if not normalized.is_absolute_path() or normalized.get_file().to_lower() != "settings.cfg":
		return ""
	var repository_root := _repository_root()
	if repository_root.is_empty():
		return ""
	for gate_number in range(1, 7):
		var root := repository_root.path_join("artifacts/gate-%02d/test-user" % gate_number)
		if normalized.to_lower().begins_with(root.to_lower() + "/"):
			return normalized
	return ""


static func _repository_root() -> String:
	var repository_root := ProjectSettings.globalize_path("res://").replace("\\", "/").simplify_path().trim_suffix("/")
	var executable_directory := OS.get_executable_path().get_base_dir().replace("\\", "/").simplify_path()
	if executable_directory.get_file().to_lower() == "windows":
		var build_directory := executable_directory.get_base_dir()
		if build_directory.get_file().to_lower() == "build":
			repository_root = build_directory.get_base_dir()
	return repository_root if repository_root.is_absolute_path() else ""


static func _accepted(mode: StringName, settings_path: String) -> Dictionary:
	return {
		"valid": true,
		"rejected_name": "",
		"mode": mode,
		"settings_path": settings_path,
		"smoke_frames": 0,
		"evidence": "",
	}


static func _rejected(name: String) -> Dictionary:
	return {"valid": false, "rejected_name": name if not name.is_empty() else "missing"}


static func _first_option_name(arguments: PackedStringArray) -> String:
	if arguments.is_empty():
		return "missing"
	return _option_name(arguments[0])


static func _option_name(argument: String) -> String:
	if argument.is_empty():
		return "missing"
	var equals_index := argument.find("=")
	if equals_index < 0:
		return argument
	return argument.substr(0, equals_index)
