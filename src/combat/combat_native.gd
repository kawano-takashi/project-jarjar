class_name CombatNative
extends RefCounted

## Required runtime for the numerical combat kernels. Build instructions are
## available in native/combat/README.md; no gameplay fallback is installed.
const EXTENSION_PATH: String = "res://native/combat/runtime/jarjar_combat.gdextension"
const KERNEL_CLASS: StringName = &"JarjarCombatKernel"
const WORLD_CLASS: StringName = &"JarjarCombatWorld"
const API_VERSION: int = 4
static var error_message: String = ""
static var _loaded: bool = false


static func ensure_loaded() -> bool:
	if _loaded:
		return true
	if not ClassDB.class_exists(KERNEL_CLASS):
		var config := ConfigFile.new()
		if config.load(EXTENSION_PATH) != OK:
			error_message = "combat_native_build_required: run native/combat/build.ps1"
			return false
		var library: String = config.get_value("libraries", "windows.x86_64", "")
		var library_path: String = library if library.begins_with("res://") else EXTENSION_PATH.get_base_dir().path_join(library)
		if library.is_empty() or not FileAccess.file_exists(library_path):
			error_message = "combat_native_library_missing: run native/combat/build.ps1"
			return false
		var status: GDExtensionManager.LoadStatus = GDExtensionManager.load_extension(EXTENSION_PATH)
		if status not in [GDExtensionManager.LOAD_STATUS_OK, GDExtensionManager.LOAD_STATUS_ALREADY_LOADED] or not ClassDB.class_exists(KERNEL_CLASS):
			error_message = "combat_native_load_failed status=%d: rebuild native/combat/build.ps1" % status
			return false
	var kernel := ClassDB.instantiate(KERNEL_CLASS) as RefCounted
	if not ClassDB.class_exists(WORLD_CLASS) or kernel == null or not kernel.has_method(&"api_version") or int(kernel.call(&"api_version")) != API_VERSION:
		error_message = "combat_native_api_mismatch: rebuild native/combat/build.ps1"
		return false
	var world := ClassDB.instantiate(WORLD_CLASS) as RefCounted
	if world == null or not world.has_method(&"api_version") or int(world.call(&"api_version")) != API_VERSION:
		error_message = "combat_native_api_mismatch: rebuild native/combat/build.ps1"
		return false
	_loaded = true
	error_message = ""
	return true


static func create_kernel() -> RefCounted:
	if not ensure_loaded():
		push_error(error_message)
		return null
	return ClassDB.instantiate(KERNEL_CLASS) as RefCounted


static func create_world() -> RefCounted:
	if not ensure_loaded():
		push_error(error_message)
		return null
	return ClassDB.instantiate(WORLD_CLASS) as RefCounted


static func context(catalog: DefinitionCatalog, state: RunState, player: Vector2, tick: int) -> Dictionary:
	return {
		"tick": tick, "player": player, "player_radius": catalog.envelope.player_body_radius,
		"target_radius": catalog.envelope.target_center_radius, "damage_radius": catalog.envelope.damage_center_radius,
		"effect_radius": catalog.envelope.effect_outer_radius, "node_radius": catalog.manifest().arena.node_body_radius,
		"stopped": state.is_stop_active(), "hit_glow_ticks": CombatSimulation.HIT_GLOW_TICKS,
	}
