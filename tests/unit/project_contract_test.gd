extends RefCounted


const GameAppScript = preload("res://src/app/game_app.gd")
const LaunchArgumentsScript = preload("res://src/app/launch_arguments.gd")
const SettingsStoreScript = preload("res://src/core/settings_store.gd")


const EXPECTED_ACTIONS: Array[String] = [
	"item_lock",
	"move_down",
	"move_left",
	"move_right",
	"move_up",
	"reward_open_all",
	"ui_accept",
	"ui_cancel",
	"ui_down",
	"ui_left",
	"ui_right",
	"ui_up",
]


func test_names() -> PackedStringArray:
	return PackedStringArray([
		"settings_defaults_and_persistence",
		"runner_autoload_and_safe_mode",
		"runner_test_path_isolation",
		"title_starts_new_seed_w1_combat",
		"title_focus_contract",
		"project_settings_contract",
		"input_map_contract",
		"launch_argument_contract",
		"qa_runtime_settings_are_ephemeral",
	])


func run_test(test_name: String, assertions: Variant, context: Dictionary) -> void:
	match test_name:
		"settings_defaults_and_persistence":
			_test_settings_defaults_and_persistence(assertions, context)
		"runner_autoload_and_safe_mode":
			_test_runner_autoload_and_safe_mode(assertions, context)
		"runner_test_path_isolation":
			_test_runner_test_path_isolation(assertions, context)
		"title_starts_new_seed_w1_combat":
			await _test_title_starts_new_seed_w1_combat(assertions, context)
		"title_focus_contract":
			await _test_title_focus_contract(assertions, context)
		"project_settings_contract":
			_test_project_settings_contract(assertions)
		"input_map_contract":
			_test_input_map_contract(assertions)
		"launch_argument_contract":
			_test_launch_argument_contract(assertions)
		"qa_runtime_settings_are_ephemeral":
			_test_qa_runtime_settings_are_ephemeral(assertions, context)
		_:
			assertions.expect_true(false, "registered test name")


func _test_settings_defaults_and_persistence(assertions: Variant, context: Dictionary) -> void:
	var store: Variant = context["settings_store"]
	assertions.expect_float(1.0, store.master_volume, "default master_volume")
	assertions.expect_float(0.8, store.music_volume, "default music_volume")
	assertions.expect_float(0.9, store.sfx_volume, "default sfx_volume")
	assertions.expect_false(store.reduce_motion, "default reduce_motion")
	assertions.expect_false(store.reduce_flashes, "default reduce_flashes")
	assertions.expect_true(store.controller_vibration, "default controller_vibration")
	assertions.expect_false(store.tutorial_seen, "default tutorial_seen")
	assertions.expect_true(FileAccess.file_exists(context["test_path"]), "missing settings file created")

	var config := ConfigFile.new()
	assertions.expect_equal(OK, config.load(context["test_path"]), "default settings readable")
	var keys := Array(config.get_section_keys("settings"))
	keys.sort()
	assertions.expect_equal(
		[
			"controller_vibration",
			"master_volume",
			"music_volume",
			"reduce_flashes",
			"reduce_motion",
			"sfx_volume",
			"tutorial_seen",
		],
		keys,
		"settings keys only",
	)
	assertions.expect_false(config.has_section("run"), "run is not saved")
	assertions.expect_false(config.has_section("score"), "score is not saved")

	store.master_volume = 0.42
	store.tutorial_seen = true
	assertions.expect_equal(OK, store.save_settings(), "settings save")
	store.master_volume = 0.0
	store.tutorial_seen = false
	assertions.expect_equal(OK, store.reload_settings(), "settings reload")
	assertions.expect_float(0.42, store.master_volume, "saved master_volume")
	assertions.expect_true(store.tutorial_seen, "saved tutorial_seen")


func _test_runner_autoload_and_safe_mode(assertions: Variant, context: Dictionary) -> void:
	var store: Variant = context["settings_store"]
	assertions.expect_true(context["runner_preflight_verified"], "runner preflight verified")
	assertions.expect_true(store != null, "SettingsStore autoload exists")
	assertions.expect_true(store.initialized, "runner initialized")
	assertions.expect_true(store.runner_safe_mode, "runner safe mode")
	assertions.expect_equal(context["test_path"], store.active_settings_path, "active test settings path")
	assertions.expect_true(store.active_settings_path.begins_with(context["test_user_root"] + "/"), "active path isolated")
	var active_path_before: String = store.active_settings_path
	var settings_text_before := FileAccess.get_file_as_string(active_path_before)
	assertions.expect_equal(ERR_ALREADY_IN_USE, store.initialize_for_game("user://settings.cfg"), "second game initialization rejected")
	assertions.expect_equal(ERR_ALREADY_IN_USE, store.initialize_ephemeral(), "second ephemeral initialization rejected")
	assertions.expect_equal(active_path_before, store.active_settings_path, "reinitialization preserves active path")
	assertions.expect_equal(settings_text_before, FileAccess.get_file_as_string(active_path_before), "reinitialization performs no active file I/O")


func _test_runner_test_path_isolation(assertions: Variant, context: Dictionary) -> void:
	var store: Variant = context["settings_store"]
	assertions.expect_not_equal(context["bootstrap_path"], context["test_path"], "test path differs from bootstrap")
	assertions.expect_equal(context["test_path"], store.active_settings_path, "test path selected")
	var outside_root_path := ProjectSettings.globalize_path(
		"res://artifacts/release-tests/rejected-settings/settings.cfg"
	)
	var outside_existed := FileAccess.file_exists(outside_root_path)
	var outside_contents := (
		FileAccess.get_file_as_string(outside_root_path)
		if outside_existed
		else ""
	)
	assertions.expect_equal(
		ERR_INVALID_PARAMETER,
		store.use_test_path(outside_root_path),
		"path outside GDScript test settings root rejected",
	)
	assertions.expect_equal(context["test_path"], store.active_settings_path, "rejection preserves active path")
	assertions.expect_equal(
		outside_existed,
		FileAccess.file_exists(outside_root_path),
		"rejection preserves outside path existence",
	)
	if outside_existed:
		assertions.expect_equal(
			outside_contents,
			FileAccess.get_file_as_string(outside_root_path),
			"rejection preserves outside path contents",
		)
	var bootstrap_config := ConfigFile.new()
	assertions.expect_equal(OK, bootstrap_config.load(context["bootstrap_path"]), "bootstrap settings remain readable")
	assertions.expect_float(
		1.0,
		float(bootstrap_config.get_value("settings", "master_volume", -1.0)),
		"bootstrap remains default during test",
	)
	store.master_volume = 0.25
	assertions.expect_equal(OK, store.save_settings(), "isolated test settings save")
	var bootstrap_reloaded := ConfigFile.new()
	assertions.expect_equal(OK, bootstrap_reloaded.load(context["bootstrap_path"]), "bootstrap settings reloaded")
	assertions.expect_float(1.0, float(bootstrap_reloaded.get_value("settings", "master_volume", -1.0)), "bootstrap unchanged on disk")
	var test_config := ConfigFile.new()
	assertions.expect_equal(OK, test_config.load(context["test_path"]), "test settings reloaded")
	assertions.expect_float(0.25, float(test_config.get_value("settings", "master_volume", -1.0)), "test settings written only to test path")


func _test_title_starts_new_seed_w1_combat(assertions: Variant, context: Dictionary) -> void:
	var game_app_script := load("res://src/app/game_app.gd")
	var app: Node = game_app_script.new()
	app.call("_show_title")
	assertions.expect_equal(GameTypes.RunPhase.TITLE, app.current_run_phase(), "TITLE is active before start")
	var title: Control = app.get_child(0) as Control
	assertions.expect_true(title != null, "TITLE screen exists")
	if title != null:
		title.emit_signal("start_requested")
	await context["tree"].process_frame
	assertions.expect_true(app.run_state != null, "TITLE start owns RunState")
	if app.run_state == null:
		app.free()
		return
	assertions.expect_true(app.run_state.run_seed > 0, "TITLE start creates a new positive seed")
	assertions.expect_equal(GameTypes.RunPhase.COMBAT, app.run_state.phase, "TITLE enters COMBAT")
	assertions.expect_equal(1, app.run_state.wave_number, "TITLE enters W1")
	assertions.expect_equal(1, app.run_state.drop_serial, "initial wood stick consumes serial 0000")
	var main_weapon: ItemInstance = app.run_state.equipped.get(
		GameTypes.EquipmentSlot.MAIN_WEAPON,
		null,
	) as ItemInstance
	assertions.expect_true(main_weapon != null, "initial main weapon exists")
	if main_weapon != null:
		assertions.expect_equal("木の棒", main_weapon.display_name, "initial main weapon is wood stick")
	app.free()


func _test_title_focus_contract(assertions: Variant, context: Dictionary) -> void:
	var packed := ResourceLoader.load("res://scenes/ui/title_screen.tscn") as PackedScene
	assertions.expect_true(packed != null, "title scene loads")
	if packed == null:
		return
	var title := packed.instantiate() as Control
	context["tree"].root.add_child(title)
	await context["tree"].process_frame
	await context["tree"].process_frame
	var start: Control = title.initial_focus_control()
	var settings: Control = title.settings_focus_control()
	var exit_button: Control = title.exit_focus_control()
	assertions.expect_equal(
		PackedStringArray(["title_start", "title_settings", "title_exit"]),
		title.focus_order(),
		"title focus order",
	)
	assertions.expect_equal("title_start", str(start.get_meta("focus_id", "")), "start focus id")
	assertions.expect_equal("title_settings", str(settings.get_meta("focus_id", "")), "settings focus id")
	assertions.expect_equal("title_exit", str(exit_button.get_meta("focus_id", "")), "exit focus id")
	assertions.expect_equal(start, title.get_viewport().gui_get_focus_owner(), "deferred initial focus")
	assertions.expect_equal(start.get_path_to(exit_button), start.focus_neighbor_top, "start up wraps exit")
	assertions.expect_equal(start.get_path_to(settings), start.focus_neighbor_bottom, "start down reaches settings")
	assertions.expect_equal(start.get_path_to(start), start.focus_neighbor_left, "start left self")
	assertions.expect_equal(start.get_path_to(start), start.focus_neighbor_right, "start right self")
	assertions.expect_equal(settings.get_path_to(start), settings.focus_neighbor_top, "settings up reaches start")
	assertions.expect_equal(settings.get_path_to(exit_button), settings.focus_neighbor_bottom, "settings down reaches exit")
	assertions.expect_equal(settings.get_path_to(settings), settings.focus_neighbor_left, "settings left self")
	assertions.expect_equal(settings.get_path_to(settings), settings.focus_neighbor_right, "settings right self")
	assertions.expect_equal(exit_button.get_path_to(settings), exit_button.focus_neighbor_top, "exit up reaches settings")
	assertions.expect_equal(exit_button.get_path_to(start), exit_button.focus_neighbor_bottom, "exit down wraps start")
	assertions.expect_equal(exit_button.get_path_to(exit_button), exit_button.focus_neighbor_left, "exit left self")
	assertions.expect_equal(exit_button.get_path_to(exit_button), exit_button.focus_neighbor_right, "exit right self")
	context["tree"].root.remove_child(title)
	title.free()


func _test_project_settings_contract(assertions: Variant) -> void:
	assertions.expect_equal("4.7.2-stable", FileAccess.get_file_as_string("res://.godot-version").strip_edges(), "Godot version file")
	var gitignore := FileAccess.get_file_as_string("res://.gitignore")
	for ignored_entry in [".godot/", "build/", "artifacts/", "work/", "*.log", ".godot/export_credentials.cfg"]:
		assertions.expect_true(ignored_entry in gitignore.split("\n"), "gitignore contains %s" % ignored_entry)
	assertions.expect_false("tools/" in gitignore.split("\n"), "repo-local export templates are not ignored")
	assertions.expect_equal("gl_compatibility", ProjectSettings.get_setting("rendering/renderer/rendering_method"), "desktop renderer")
	assertions.expect_equal("gl_compatibility", ProjectSettings.get_setting("rendering/renderer/rendering_method.mobile"), "mobile renderer")
	assertions.expect_equal(60, ProjectSettings.get_setting("physics/common/physics_ticks_per_second"), "physics 60Hz")
	assertions.expect_equal(1920, ProjectSettings.get_setting("display/window/size/viewport_width"), "logical width")
	assertions.expect_equal(1080, ProjectSettings.get_setting("display/window/size/viewport_height"), "logical height")
	assertions.expect_equal(1280, ProjectSettings.get_setting("display/window/size/window_width_override"), "initial window width")
	assertions.expect_equal(720, ProjectSettings.get_setting("display/window/size/window_height_override"), "initial window height")
	assertions.expect_equal("canvas_items", ProjectSettings.get_setting("display/window/stretch/mode"), "canvas stretch")
	assertions.expect_true(ProjectSettings.get_setting("application/config/use_custom_user_dir"), "custom user dir enabled")
	assertions.expect_equal("ProjectJARJAR", ProjectSettings.get_setting("application/config/custom_user_dir_name"), "custom user dir name")
	assertions.expect_false(ProjectSettings.get_setting("debug/file_logging/enable_file_logging"), "file logging disabled")
	assertions.expect_false(ProjectSettings.get_setting("debug/file_logging/enable_file_logging.pc"), "PC file logging disabled")
	assertions.expect_false(ProjectSettings.get_setting("rendering/shader_compiler/shader_cache/enabled"), "shader cache disabled")

	var config := ConfigFile.new()
	assertions.expect_equal(OK, config.load("res://project.godot"), "project.godot readable")
	assertions.expect_equal(false, config.get_value("debug", "file_logging/enable_file_logging", null), "file logging explicitly disabled")
	assertions.expect_equal(false, config.get_value("debug", "file_logging/enable_file_logging.pc", null), "PC file logging explicitly disabled")
	assertions.expect_equal(60, config.get_value("physics", "common/physics_ticks_per_second", null), "physics 60Hz explicitly configured")
	assertions.expect_equal(PackedStringArray(["SettingsStore"]), config.get_section_keys("autoload"), "sole autoload")
	var main_scene := ResourceLoader.load("res://scenes/main.tscn") as PackedScene
	assertions.expect_true(main_scene != null, "main scene loads")
	if main_scene != null:
		assertions.expect_equal(1, main_scene.get_state().get_node_count(), "main scene root only")
		assertions.expect_equal("GameApp", str(main_scene.get_state().get_node_name(0)), "main scene root name")
	var export_config := ConfigFile.new()
	assertions.expect_equal(OK, export_config.load("res://export_presets.cfg"), "export preset readable")
	assertions.expect_equal("Windows Desktop", export_config.get_value("preset.0", "name", ""), "export preset name")
	assertions.expect_equal("build/windows/ProjectJARJAR.exe", export_config.get_value("preset.0", "export_path", ""), "export path")
	assertions.expect_equal("x86_64", export_config.get_value("preset.0.options", "binary_format/architecture", ""), "export architecture")
	assertions.expect_false(export_config.get_value("preset.0.options", "binary_format/embed_pck", true), "PCK separated")
	assertions.expect_equal(2, export_config.get_value("preset.0.options", "debug/export_console_wrapper", -1), "console wrapper debug and release")
	assertions.expect_equal(
		"",
		export_config.get_value("preset.0.options", "custom_template/debug", ""),
		"default debug export template",
	)
	assertions.expect_equal(
		"",
		export_config.get_value("preset.0.options", "custom_template/release", ""),
		"default release export template",
	)
	var exclude_filter: String = export_config.get_value("preset.0", "exclude_filter", "")
	for required_filter in ["tests/*", "src/debug/*", "scenes/debug/*", "outputs/*", "docs/*"]:
		assertions.expect_true(required_filter in exclude_filter.split(","), "release excludes %s" % required_filter)


func _test_input_map_contract(assertions: Variant) -> void:
	var config := ConfigFile.new()
	assertions.expect_equal(OK, config.load("res://project.godot"), "InputMap source readable")
	var configured_actions := Array(config.get_section_keys("input"))
	configured_actions.sort()
	assertions.expect_equal(EXPECTED_ACTIONS, configured_actions, "no additional configured actions")
	_assert_action(assertions, "move_up", [87, 4194320], [], [[1, -1.0]])
	_assert_action(assertions, "move_down", [83, 4194322], [], [[1, 1.0]])
	_assert_action(assertions, "move_left", [65, 4194319], [], [[0, -1.0]])
	_assert_action(assertions, "move_right", [68, 4194321], [], [[0, 1.0]])
	_assert_action(assertions, "ui_up", [4194320], [11], [[1, -1.0]])
	_assert_action(assertions, "ui_down", [4194322], [12], [[1, 1.0]])
	_assert_action(assertions, "ui_left", [4194319], [13], [[0, -1.0]])
	_assert_action(assertions, "ui_right", [4194321], [14], [[0, 1.0]])
	_assert_action(assertions, "ui_accept", [4194309], [0], [])
	_assert_action(assertions, "ui_cancel", [4194305], [1], [])
	_assert_action(assertions, "item_lock", [76], [2], [])
	_assert_action(assertions, "reward_open_all", [70], [3], [])


func _assert_action(assertions: Variant, action: StringName, keys: Array, buttons: Array, axes: Array) -> void:
	assertions.expect_true(InputMap.has_action(action), "%s registered" % action)
	var events := InputMap.action_get_events(action)
	assertions.expect_equal(keys.size() + buttons.size() + axes.size(), events.size(), "%s event count" % action)
	for physical_keycode in keys:
		var found := false
		for event in events:
			if event is InputEventKey and event.physical_keycode == physical_keycode:
				found = true
				break
		assertions.expect_true(found, "%s physical key %s" % [action, physical_keycode])
	for button_index in buttons:
		var found := false
		for event in events:
			if event is InputEventJoypadButton and event.button_index == button_index:
				found = true
				break
		assertions.expect_true(found, "%s joy button %s" % [action, button_index])
	for axis_spec in axes:
		var found := false
		for event in events:
			if (
				event is InputEventJoypadMotion
				and event.axis == axis_spec[0]
				and is_equal_approx(event.axis_value, axis_spec[1])
			):
				found = true
				break
		assertions.expect_true(found, "%s joy axis %s:%s" % [action, axis_spec[0], axis_spec[1]])


func _test_qa_runtime_settings_are_ephemeral(assertions: Variant, context: Dictionary) -> void:
	var qa_settings_path: String = String(context["test_user_root"]).path_join(
		"qa-runtime-policy/settings.cfg"
	)
	if FileAccess.file_exists(qa_settings_path):
		assertions.expect_equal(
			OK,
			DirAccess.remove_absolute(qa_settings_path),
			"QA policy fixture removes its prior isolated file",
		)
	var settings_store: Variant = SettingsStoreScript.new()
	var game_app: Variant = GameAppScript.new()
	game_app.set("_launch", {
		"mode": LaunchArgumentsScript.MODE_QA_SCENARIO,
	})
	var initialize_error: Variant = game_app.call(
		"_initialize_settings_for_launch",
		settings_store,
	)
	assertions.expect_equal(OK, initialize_error, "QA settings policy initializes")
	assertions.expect_true(settings_store.initialized, "QA settings policy initializes runtime defaults")
	assertions.expect_false(settings_store.runner_safe_mode, "QA settings policy is not runner mode")
	assertions.expect_equal("", settings_store.active_settings_path, "QA settings path stays ephemeral")
	assertions.expect_true(settings_store.tutorial_seen, "QA tutorial_seen is runtime true")
	assertions.expect_false(FileAccess.file_exists(qa_settings_path), "QA settings policy writes no file")
	game_app.free()
	settings_store.free()


func _test_launch_argument_contract(assertions: Variant) -> void:
	var parser := load("res://src/app/launch_arguments.gd")
	var debug_normal: Dictionary = parser.parse_debug(PackedStringArray())
	assertions.expect_true(debug_normal["valid"], "debug no-argument normal launch accepted")
	assertions.expect_equal(&"normal", debug_normal["mode"], "debug normal mode selected")
	assertions.expect_equal(
		"user://settings.cfg",
		debug_normal["settings_path"],
		"normal launch uses user settings",
	)

	var valid_smoke: Dictionary = parser.parse_debug(PackedStringArray(["--smoke-quit=120"]))
	assertions.expect_true(valid_smoke["valid"], "valid smoke accepted")
	assertions.expect_equal(&"smoke_quit", valid_smoke["mode"], "smoke mode")
	assertions.expect_equal(120, valid_smoke["smoke_frames"], "smoke physics frames")
	assertions.expect_equal("", valid_smoke["settings_path"], "smoke settings are ephemeral")
	for invalid_value in ["", "abc", "0", "-1", "1.5"]:
		var invalid_smoke: Dictionary = parser.parse_debug(PackedStringArray([
			"--smoke-quit=" + invalid_value,
		]))
		assertions.expect_false(invalid_smoke["valid"], "invalid smoke value rejected: %s" % invalid_value)
		assertions.expect_equal("--smoke-quit", invalid_smoke["rejected_name"], "invalid smoke marker: %s" % invalid_value)
	for invalid_smoke_arguments: PackedStringArray in [
		PackedStringArray(["--smoke-quit"]),
		PackedStringArray(["--smoke-quit=1", "--smoke-quit=2"]),
		PackedStringArray(["--smoke-quit=1", "--qa-scenario=weapon_bow"]),
	]:
		assertions.expect_false(
			parser.parse_debug(invalid_smoke_arguments)["valid"],
			"invalid smoke argument shape rejected",
		)

	for scenario_id: String in parser.QA_SCENARIOS:
		var valid_qa: Dictionary = parser.parse_debug(PackedStringArray([
			"--qa-scenario=" + scenario_id,
		]))
		assertions.expect_true(valid_qa["valid"], "QA scenario accepted: %s" % scenario_id)
		assertions.expect_equal(&"qa_scenario", valid_qa["mode"], "QA mode selected")
		assertions.expect_equal("", valid_qa["settings_path"], "QA settings are ephemeral")
	for invalid_qa_arguments: PackedStringArray in [
		PackedStringArray(["--qa-scenario=unknown"]),
		PackedStringArray(["--qa-scenario"]),
		PackedStringArray(["--qa-scenario=weapon_bow", "--qa-scenario=weapon_staff"]),
	]:
		assertions.expect_false(
			parser.parse_debug(invalid_qa_arguments)["valid"],
			"invalid QA argument shape rejected",
		)

	for valid_performance_arguments: PackedStringArray in [
		PackedStringArray([
			"--performance=full_hd_500_2000",
			"--run-seed=5002000",
		]),
		PackedStringArray([
			"--run-seed=5002000",
			"--performance=full_hd_500_2000",
		]),
	]:
		var valid_performance: Dictionary = parser.parse_debug(valid_performance_arguments)
		assertions.expect_true(valid_performance["valid"], "exact performance arguments accepted")
		assertions.expect_equal(&"performance", valid_performance["mode"], "performance mode selected")
		assertions.expect_equal(5_002_000, valid_performance["run_seed"], "performance seed fixed")
		assertions.expect_equal("", valid_performance["settings_path"], "performance settings are ephemeral")
	for invalid_performance: PackedStringArray in [
		PackedStringArray(["--performance=full_hd_500_2000", "--run-seed=1"]),
		PackedStringArray(["--performance=reduced_load", "--run-seed=5002000"]),
		PackedStringArray(["--performance=full_hd_500_2000"]),
		PackedStringArray(["--run-seed=5002000"]),
		PackedStringArray([
			"--performance=full_hd_500_2000",
			"--run-seed=5002000",
			"--run-seed=5002000",
		]),
	]:
		assertions.expect_false(
			parser.parse_debug(invalid_performance)["valid"],
			"altered performance contract rejected",
		)

	for removed_or_unknown_debug: PackedStringArray in [
		PackedStringArray(["--settings-path=C:/tmp/settings.cfg"]),
		PackedStringArray(["--suite=unit"]),
		PackedStringArray(["--unknown=value"]),
	]:
		assertions.expect_false(
			parser.parse_debug(removed_or_unknown_debug)["valid"],
			"removed or unknown debug option rejected",
		)

	var release_normal: Dictionary = parser.parse_release(PackedStringArray())
	assertions.expect_true(release_normal["valid"], "Release no-argument normal launch accepted")
	assertions.expect_equal(&"normal", release_normal["mode"], "Release normal mode selected")
	var release_smoke: Dictionary = parser.parse_release(PackedStringArray(["--smoke-run"]))
	assertions.expect_true(release_smoke["valid"], "Release smoke driver accepted alone")
	assertions.expect_equal(&"release_smoke", release_smoke["mode"], "Release smoke mode selected")
	var manifest_path := ProjectSettings.globalize_path(
		"res://artifacts/release-tests/pack-manifest.txt"
	)
	var release_audit: Dictionary = parser.parse_release(PackedStringArray([
		"--release-pack-audit=" + manifest_path,
	]))
	assertions.expect_true(release_audit["valid"], "Release absolute pack audit accepted alone")
	assertions.expect_equal(&"release_pack_audit", release_audit["mode"], "Release audit mode selected")
	assertions.expect_equal(
		manifest_path.replace("\\", "/").simplify_path(),
		release_audit["manifest_path"],
		"Release audit path normalized",
	)

	var rejected_release_cases: Array[PackedStringArray] = [
		PackedStringArray(["--qa-scenario=weapon_bow"]),
		PackedStringArray(["--settings-path=C:/tmp/settings.cfg"]),
		PackedStringArray(["--smoke-quit=1"]),
		PackedStringArray(["--performance=full_hd_500_2000"]),
		PackedStringArray(["--run-seed=5002000"]),
		PackedStringArray(["--suite=unit"]),
		PackedStringArray(["--unknown-qa-option"]),
		PackedStringArray(["--smoke-run", "--smoke-run"]),
		PackedStringArray(["--smoke-run", "--release-pack-audit=" + manifest_path]),
		PackedStringArray(["--release-pack-audit=relative.txt"]),
		PackedStringArray([
			"--release-pack-audit=" + manifest_path,
			"--release-pack-audit=" + manifest_path,
		]),
	]
	for release_arguments: PackedStringArray in rejected_release_cases:
		var rejected_release: Dictionary = parser.parse_release(release_arguments)
		assertions.expect_false(rejected_release["valid"], "Release rejects non-whitelisted arguments")
