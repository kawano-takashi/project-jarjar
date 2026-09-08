extends RefCounted

const EXTENSION_PATH: String = "res://build/bot-native/jarjar_bot.gdextension"
const KERNEL_CLASS: StringName = &"JarjarBotKernel"
const API_VERSION: int = 6
static var error_message: String = ""
static var _attempted: bool = false
static var _loaded: bool = false

static func ensure_loaded() -> bool:
	if _attempted:
		return _loaded
	_attempted = true
	if not ClassDB.class_exists(KERNEL_CLASS):
		var config := ConfigFile.new()
		if config.load(EXTENSION_PATH) != OK:
			error_message = "native_build_required: run dev/bot/native/build.ps1"
			return false
		var library: String = config.get_value("libraries", "windows.x86_64", "")
		if library.is_empty() or not FileAccess.file_exists(EXTENSION_PATH.get_base_dir().path_join(library)):
			error_message = "native_library_missing: run dev/bot/native/build.ps1"
			return false
		var status: GDExtensionManager.LoadStatus = GDExtensionManager.load_extension(ProjectSettings.globalize_path(EXTENSION_PATH))
		if status not in [GDExtensionManager.LOAD_STATUS_OK, GDExtensionManager.LOAD_STATUS_ALREADY_LOADED] or not ClassDB.class_exists(KERNEL_CLASS):
			error_message = "native_load_failed status=%d: rebuild dev/bot/native/build.ps1" % status
			return false
	var kernel := ClassDB.instantiate(KERNEL_CLASS) as RefCounted
	if kernel == null or not kernel.has_method(&"api_version") or int(kernel.call(&"api_version")) != API_VERSION:
		error_message = "native_api_mismatch: rebuild dev/bot/native/build.ps1"
		return false
	_loaded = true
	return true

static func create_kernel() -> RefCounted:
	if not ensure_loaded():
		return null
	return ClassDB.instantiate(KERNEL_CLASS) as RefCounted
