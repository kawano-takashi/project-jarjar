extends Node


const USER_SETTINGS_PATH := "user://settings.cfg"
const SETTINGS_SECTION := "settings"

const DEFAULT_SETTINGS: Dictionary = {
	"master_volume": 1.0,
	"sfx_volume": 0.9,
	"reduce_motion": false,
	"reduce_flashes": false,
	"controller_vibration": true,
	"tutorial_completed": false,
}

var initialized: bool = false
var runner_safe_mode: bool = false
var active_settings_path: String = ""

var master_volume: float = 1.0
var sfx_volume: float = 0.9
var reduce_motion: bool = false
var reduce_flashes: bool = false
var controller_vibration: bool = true
var tutorial_completed: bool = false

var _runner_bootstrap_path: String = ""
var _runner_test_user_root: String = ""
var _runner_directory: DirAccess = null


func _enter_tree() -> void:
	pass


func _ready() -> void:
	pass


func initialize_for_game(settings_path: String = USER_SETTINGS_PATH) -> Error:
	if initialized:
		return ERR_ALREADY_IN_USE

	var resolved_path := _resolve_game_settings_path(settings_path)
	if resolved_path.is_empty():
		return ERR_INVALID_PARAMETER

	var load_result := _load_or_create_settings(resolved_path)
	var load_error: Error = load_result["error"]
	if load_error != OK:
		return load_error

	_apply_values(load_result["values"])
	active_settings_path = resolved_path
	runner_safe_mode = false
	initialized = true
	return OK


func initialize_for_runner() -> Error:
	if initialized:
		return ERR_ALREADY_IN_USE

	_runner_directory = DirAccess.create_temp("jarjar-tests")
	if _runner_directory == null:
		return DirAccess.get_open_error()
	var test_user_root := _runner_directory.get_current_dir().replace("\\", "/").simplify_path()
	var resolved_path := test_user_root.path_join("runner/settings.cfg")
	var load_result := _create_default_settings(resolved_path)
	var load_error: Error = load_result["error"]
	if load_error != OK:
		_runner_directory = null
		return load_error

	_apply_values(load_result["values"])
	_runner_bootstrap_path = resolved_path
	_runner_test_user_root = test_user_root
	active_settings_path = resolved_path
	runner_safe_mode = true
	initialized = true
	return OK


func finish_runner() -> Error:
	if not initialized or not runner_safe_mode:
		return ERR_UNAUTHORIZED
	var temporary_path := _runner_test_user_root
	_runner_directory = null
	_runner_bootstrap_path = ""
	_runner_test_user_root = ""
	active_settings_path = ""
	runner_safe_mode = false
	initialized = false
	_apply_values(DEFAULT_SETTINGS)
	return FAILED if DirAccess.dir_exists_absolute(temporary_path) else OK


func initialize_ephemeral() -> Error:
	if initialized:
		return ERR_ALREADY_IN_USE

	_apply_values(DEFAULT_SETTINGS)
	active_settings_path = ""
	runner_safe_mode = false
	initialized = true
	return OK


func use_test_path(test_settings_path: String) -> Error:
	if not initialized or not runner_safe_mode:
		return ERR_UNAUTHORIZED

	var resolved_path := _normalize_absolute_path(test_settings_path)
	if resolved_path.is_empty():
		return ERR_INVALID_PARAMETER
	if not _is_path_within(resolved_path, _runner_test_user_root):
		return ERR_INVALID_PARAMETER

	return _activate_clean_runner_path(resolved_path)


func restore_runner_bootstrap_path() -> Error:
	if not initialized or not runner_safe_mode:
		return ERR_UNAUTHORIZED
	if _runner_bootstrap_path.is_empty() or _runner_test_user_root.is_empty():
		return ERR_UNCONFIGURED
	if not _is_path_within(_runner_bootstrap_path, _runner_test_user_root):
		return ERR_INVALID_PARAMETER

	return _activate_clean_runner_path(_runner_bootstrap_path)


func save_settings() -> Error:
	if not initialized or active_settings_path.is_empty():
		return ERR_UNCONFIGURED

	var ensure_error := _ensure_parent_directory(active_settings_path)
	if ensure_error != OK:
		return ensure_error

	var config := ConfigFile.new()
	_write_values(config, get_settings())
	return config.save(active_settings_path)


func reload_settings() -> Error:
	if not initialized or active_settings_path.is_empty():
		return ERR_UNCONFIGURED

	var load_result := _load_or_create_settings(active_settings_path)
	var load_error: Error = load_result["error"]
	if load_error != OK:
		return load_error

	_apply_values(load_result["values"])
	return OK


func get_settings() -> Dictionary:
	return {
		"master_volume": master_volume,
		"sfx_volume": sfx_volume,
		"reduce_motion": reduce_motion,
		"reduce_flashes": reduce_flashes,
		"controller_vibration": controller_vibration,
		"tutorial_completed": tutorial_completed,
	}


func _activate_clean_runner_path(resolved_path: String) -> Error:
	if FileAccess.file_exists(resolved_path):
		var remove_error := DirAccess.remove_absolute(resolved_path)
		if remove_error != OK:
			return remove_error

	var create_result := _create_default_settings(resolved_path)
	var create_error: Error = create_result["error"]
	if create_error != OK:
		return create_error

	_apply_values(create_result["values"])
	active_settings_path = resolved_path
	return OK


func _load_or_create_settings(settings_path: String) -> Dictionary:
	if not FileAccess.file_exists(settings_path):
		return _create_default_settings(settings_path)

	var config := ConfigFile.new()
	var load_error := config.load(settings_path)
	if load_error != OK:
		return _io_result(load_error)

	return _io_result(OK, _read_values(config))


func _create_default_settings(settings_path: String) -> Dictionary:
	var ensure_error := _ensure_parent_directory(settings_path)
	if ensure_error != OK:
		return _io_result(ensure_error)

	var values: Dictionary = DEFAULT_SETTINGS.duplicate(true)
	var config := ConfigFile.new()
	_write_values(config, values)
	var save_error := config.save(settings_path)
	if save_error != OK:
		return _io_result(save_error)

	return _io_result(OK, values)


func _ensure_parent_directory(settings_path: String) -> Error:
	var parent_path := settings_path.get_base_dir()
	if DirAccess.dir_exists_absolute(parent_path):
		return OK
	return DirAccess.make_dir_recursive_absolute(parent_path)


func _read_values(config: ConfigFile) -> Dictionary:
	return {
		"master_volume": _read_volume(config, "master_volume", 1.0),
		"sfx_volume": _read_volume(config, "sfx_volume", 0.9),
		"reduce_motion": _read_bool(config, "reduce_motion", false),
		"reduce_flashes": _read_bool(config, "reduce_flashes", false),
		"controller_vibration": _read_bool(config, "controller_vibration", true),
		"tutorial_completed": _read_bool(config, "tutorial_completed", false),
	}


func _read_volume(config: ConfigFile, key: String, default_value: float) -> float:
	var value: Variant = config.get_value(SETTINGS_SECTION, key, default_value)
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return default_value
	return clampf(float(value), 0.0, 1.0)


func _read_bool(config: ConfigFile, key: String, default_value: bool) -> bool:
	var value: Variant = config.get_value(SETTINGS_SECTION, key, default_value)
	if typeof(value) != TYPE_BOOL:
		return default_value
	return value


func _write_values(config: ConfigFile, values: Dictionary) -> void:
	config.set_value(SETTINGS_SECTION, "master_volume", values["master_volume"])
	config.set_value(SETTINGS_SECTION, "sfx_volume", values["sfx_volume"])
	config.set_value(SETTINGS_SECTION, "reduce_motion", values["reduce_motion"])
	config.set_value(SETTINGS_SECTION, "reduce_flashes", values["reduce_flashes"])
	config.set_value(SETTINGS_SECTION, "controller_vibration", values["controller_vibration"])
	config.set_value(SETTINGS_SECTION, "tutorial_completed", values["tutorial_completed"])


func _apply_values(values: Dictionary) -> void:
	master_volume = values["master_volume"]
	sfx_volume = values["sfx_volume"]
	reduce_motion = values["reduce_motion"]
	reduce_flashes = values["reduce_flashes"]
	controller_vibration = values["controller_vibration"]
	tutorial_completed = values["tutorial_completed"]


func _resolve_game_settings_path(settings_path: String) -> String:
	return USER_SETTINGS_PATH if settings_path == USER_SETTINGS_PATH else ""


func _normalize_absolute_path(path: String) -> String:
	if path.is_empty():
		return ""
	var normalized := path.replace("\\", "/").simplify_path()
	if not normalized.is_absolute_path():
		return ""
	if normalized.get_file().to_lower() != "settings.cfg":
		return ""
	return normalized


func _is_path_within(path: String, root_path: String) -> bool:
	if root_path.is_empty():
		return false
	var lowercase_path := path.to_lower()
	var lowercase_root := root_path.to_lower().trim_suffix("/")
	return lowercase_path.begins_with(lowercase_root + "/")


func _io_result(error: Error, values: Dictionary = {}) -> Dictionary:
	return {"error": error, "values": values}
