class_name LaunchArguments
extends RefCounted


const MODE_NORMAL: StringName = &"normal"
const MODE_SMOKE_QUIT: StringName = &"smoke_quit"
const MODE_QA_SCENARIO: StringName = &"qa_scenario"
const MODE_PERFORMANCE: StringName = &"performance"
const MODE_RELEASE_SMOKE: StringName = &"release_smoke"
const MODE_RELEASE_PACK_AUDIT: StringName = &"release_pack_audit"
const QA_SCENARIOS: Array[String] = [
	"weapon_wood_stick",
	"weapon_bow",
	"weapon_staff",
	"weapon_sword",
	"pre_quota_death",
	"pre_quota_timeout",
	"post_quota_death",
	"reward_controls",
	"inventory_controller",
	"result_controller",
	"immortal_100",
	"boss_299",
]

const DEBUG_OPTIONS: Array[String] = [
	"--qa-scenario",
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
	if values.size() == 1 and values.has("--smoke-quit"):
		var frame_text: String = values["--smoke-quit"]
		if not frame_text.is_valid_int():
			return _rejected("--smoke-quit")
		var frame_count := frame_text.to_int()
		if frame_count < 1:
			return _rejected("--smoke-quit")
		var result := _accepted(MODE_SMOKE_QUIT, "")
		result["smoke_frames"] = frame_count
		return result

	if values.size() == 1 and values.has("--qa-scenario"):
		if not values["--qa-scenario"] in QA_SCENARIOS:
			return _rejected("--qa-scenario")
		var result := _accepted(MODE_QA_SCENARIO, "")
		result["qa_scenario"] = values["--qa-scenario"]
		return result

	if values.size() == 2 and values.has("--performance") and values.has("--run-seed"):
		if values["--performance"] != "full_hd_500_2000" or values["--run-seed"] != "5002000":
			return _rejected("--performance")
		var result := _accepted(MODE_PERFORMANCE, "")
		result["performance"] = values["--performance"]
		result["run_seed"] = 5002000
		return result

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


static func _accepted(mode: StringName, settings_path: String) -> Dictionary:
	return {
		"valid": true,
		"rejected_name": "",
		"mode": mode,
		"settings_path": settings_path,
		"smoke_frames": 0,
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
