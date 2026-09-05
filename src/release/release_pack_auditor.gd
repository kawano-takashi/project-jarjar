class_name ReleasePackAuditor
extends RefCounted


const MANIFEST_RELATIVE_PATH: String = "artifacts/release-tests/pack-manifest.txt"
const REQUIRED_MAIN_SCENE_PATH: String = "res://scenes/main.tscn"
const REQUIRED_SURVIVAL_MANIFEST_PATH: String = "res://data/balance/survival_content_manifest.tres"
const FORBIDDEN_PREFIXES: Array[String] = [
	"res://data/definitions/",
	"res://tests/",
	"res://src/debug/",
	"res://scenes/debug/",
	"res://outputs/",
	"res://docs/",
	"res://tools/",
	"res://build/",
	"res://artifacts/",
	"res://work/",
	"res://.codex/",
	"res://assets/ui/inventory_icons/",
	"res://data/balance/affixes/",
	"res://data/balance/rarities/",
	"res://data/balance/waves/",
	"res://data/balance/score.",
	"res://src/inventory/",
	"res://src/loot/",
	"res://src/core/models/item_instance.",
	"res://src/core/models/reward_roll.",
	"res://src/core/models/affix_roll.",
	"res://src/core/score_service.",
	"res://src/definitions/rarity_definition.",
	"res://src/definitions/affix_definition.",
	"res://src/definitions/wave_definition.",
	"res://src/definitions/score_definition.",
	"res://data/balance/weapons/wood_stick.tres",
	"res://data/balance/weapons/bow.tres",
	"res://data/balance/weapons/staff.tres",
	"res://data/balance/weapons/sword.tres",
	"res://src/ui/inventory_",
	"res://src/ui/fusion_",
	"res://src/ui/reward_reveal_",
	"res://scenes/ui/inventory_",
	"res://scenes/ui/fusion_",
	"res://scenes/ui/reward_reveal_",
]


static func audit(manifest_path: String) -> Dictionary:
	var path_validation: Dictionary = validate_manifest_path(manifest_path)
	if not bool(path_validation["valid"]):
		return _failure(2, path_validation["reason"], {
			"rejected_name": "--release-pack-audit",
		})

	var normalized_manifest_path: String = path_validation["manifest_path"]
	var resource_paths: Array[String] = []
	_collect_resource_paths("res://", resource_paths, {}, {})
	resource_paths.sort_custom(_ordinal_less)

	var unsafe_paths: Array[String] = []
	for resource_path: String in resource_paths:
		if resource_path.contains("\r") or resource_path.contains("\n"):
			unsafe_paths.append(resource_path)
	if not unsafe_paths.is_empty():
		return _failure(3, &"unsafe_resource_path", {
			"manifest_path": normalized_manifest_path,
			"path_count": resource_paths.size(),
			"unsafe_paths": unsafe_paths,
		})

	var manifest_text: String = ""
	if not resource_paths.is_empty():
		manifest_text = "\n".join(PackedStringArray(resource_paths)) + "\n"
	var manifest_file := FileAccess.open(normalized_manifest_path, FileAccess.WRITE)
	if manifest_file == null:
		return _failure(3, &"manifest_open_failed", {
			"manifest_path": normalized_manifest_path,
			"path_count": resource_paths.size(),
		})
	var write_succeeded: bool = manifest_file.store_string(manifest_text)
	var write_error: Error = manifest_file.get_error()
	manifest_file.close()
	if not write_succeeded or write_error != OK:
		return _failure(3, &"manifest_write_failed", {
			"manifest_path": normalized_manifest_path,
			"path_count": resource_paths.size(),
			"write_error": write_error,
		})

	var forbidden_paths: Array[String] = []
	for resource_path: String in resource_paths:
		var lowercase_path := resource_path.to_lower()
		for forbidden_prefix: String in FORBIDDEN_PREFIXES:
			if lowercase_path.begins_with(forbidden_prefix):
				forbidden_paths.append(resource_path)
				break

	var main_resource: Resource = (
		ResourceLoader.load(REQUIRED_MAIN_SCENE_PATH)
		if ResourceLoader.exists(REQUIRED_MAIN_SCENE_PATH)
		else null
	)
	var survival_resource: Resource = (
		ResourceLoader.load(REQUIRED_SURVIVAL_MANIFEST_PATH)
		if ResourceLoader.exists(REQUIRED_SURVIVAL_MANIFEST_PATH)
		else null
	)
	var main_scene_valid: bool = main_resource is PackedScene
	var survival_manifest_valid: bool = survival_resource is SurvivalContentManifest
	if survival_manifest_valid:
		var catalog := DefinitionCatalog.new()
		survival_manifest_valid = catalog.validate_manifest(survival_resource as SurvivalContentManifest)
	var required_count: int = (
		int(main_scene_valid)
		+ int(survival_manifest_valid)
	)

	var details := {
		"manifest_path": normalized_manifest_path,
		"path_count": resource_paths.size(),
		"forbidden_count": forbidden_paths.size(),
		"forbidden_paths": forbidden_paths,
		"required_count": required_count,
		"main_scene_valid": main_scene_valid,
		"survival_manifest_valid": survival_manifest_valid,
	}
	if resource_paths.is_empty():
		return _failure(3, &"empty_manifest", details)
	if not forbidden_paths.is_empty():
		return _failure(3, &"forbidden_prefix", details)
	if not main_scene_valid:
		return _failure(3, &"main_scene_invalid", details)
	if not survival_manifest_valid:
		return _failure(3, &"survival_manifest_invalid", details)

	details["success"] = true
	details["exit_code"] = 0
	details["reason"] = &""
	details["message"] = (
		"PACK_AUDIT_OK paths=%d required=2 forbidden=0"
		% resource_paths.size()
	)
	return details


static func validate_manifest_path(manifest_path: String) -> Dictionary:
	return _validate_manifest_path_for_executable(manifest_path, OS.get_executable_path())


static func _validate_manifest_path_for_executable(
	manifest_path: String,
	executable_path: String,
) -> Dictionary:
	if manifest_path.is_empty():
		return _invalid_path(&"manifest_path_empty")
	var normalized_manifest_path := manifest_path.replace("\\", "/").simplify_path()
	if not normalized_manifest_path.is_absolute_path():
		return _invalid_path(&"manifest_path_not_absolute")

	var executable_directory := (
		executable_path.get_base_dir().replace("\\", "/").simplify_path()
	)
	if (
		executable_directory.get_file().to_lower() != "windows"
		or executable_directory.get_base_dir().get_file().to_lower() != "build"
	):
		return _invalid_path(&"executable_directory_invalid")
	var repository_root := executable_directory.get_base_dir().get_base_dir()
	if not repository_root.is_absolute_path():
		return _invalid_path(&"repository_root_invalid")
	var allowed_path := repository_root.path_join(MANIFEST_RELATIVE_PATH).simplify_path()
	if normalized_manifest_path.to_lower() != allowed_path.to_lower():
		return _invalid_path(&"manifest_path_not_allowed")
	var parent_directory := allowed_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(parent_directory):
		return _invalid_path(&"manifest_parent_missing")
	if DirAccess.dir_exists_absolute(allowed_path):
		return _invalid_path(&"manifest_path_is_directory")
	return {
		"valid": true,
		"reason": &"",
		"manifest_path": allowed_path,
		"repository_root": repository_root,
	}


static func _collect_resource_paths(
	directory_path: String,
	paths: Array[String],
	visited_directories: Dictionary,
	visited_paths: Dictionary,
) -> void:
	var normalized_directory := directory_path
	if normalized_directory != "res://":
		normalized_directory = normalized_directory.trim_suffix("/")
	var directory_key := normalized_directory.to_lower()
	if visited_directories.has(directory_key):
		return
	visited_directories[directory_key] = true

	for entry: String in ResourceLoader.list_directory(normalized_directory):
		var entry_is_directory := entry.ends_with("/")
		var entry_name := entry.trim_suffix("/")
		var full_path := (
			entry_name
			if entry_name.begins_with("res://")
			else normalized_directory.path_join(entry_name)
		)
		full_path = full_path.replace("\\", "/").simplify_path()
		if entry_is_directory:
			_collect_resource_paths(full_path, paths, visited_directories, visited_paths)
		elif not visited_paths.has(full_path):
			visited_paths[full_path] = true
			paths.append(full_path)


static func _ordinal_less(left: String, right: String) -> bool:
	var shared_length := mini(left.length(), right.length())
	for index: int in range(shared_length):
		var left_codepoint := left.unicode_at(index)
		var right_codepoint := right.unicode_at(index)
		if left_codepoint != right_codepoint:
			return left_codepoint < right_codepoint
	return left.length() < right.length()


static func _invalid_path(reason: StringName) -> Dictionary:
	return {"valid": false, "reason": reason, "manifest_path": ""}


static func _failure(exit_code: int, reason: StringName, details: Dictionary) -> Dictionary:
	var result: Dictionary = details.duplicate(true)
	result["success"] = false
	result["exit_code"] = exit_code
	result["reason"] = reason
	result["message"] = ""
	return result
