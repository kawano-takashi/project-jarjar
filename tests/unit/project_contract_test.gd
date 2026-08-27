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
		"gate_script_argument_validation",
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
			_test_launch_argument_contract(assertions, context)
		"qa_runtime_settings_are_ephemeral":
			_test_qa_runtime_settings_are_ephemeral(assertions, context)
		"gate_script_argument_validation":
			_test_gate_script_argument_validation(assertions)
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
	var current_gate_name: String = context["test_user_root"].get_base_dir().get_file()
	var other_gate_name := "gate-02" if current_gate_name == "gate-01" else "gate-01"
	var cross_gate_path := ProjectSettings.globalize_path(
		"res://artifacts/%s/test-user/cross_gate_rejected_from_%s/settings.cfg"
		% [other_gate_name, current_gate_name]
	)
	assertions.expect_false(FileAccess.file_exists(cross_gate_path), "cross-Gate target absent before rejection")
	assertions.expect_equal(ERR_INVALID_PARAMETER, store.use_test_path(cross_gate_path), "cross-Gate test path rejected")
	assertions.expect_equal(context["test_path"], store.active_settings_path, "cross-Gate rejection preserves active path")
	assertions.expect_false(FileAccess.file_exists(cross_gate_path), "cross-Gate rejection performs no target file I/O")
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
	var exit_button: Control = title.exit_focus_control()
	assertions.expect_equal(PackedStringArray(["title_start", "title_exit"]), title.focus_order(), "title focus order")
	assertions.expect_equal("title_start", str(start.get_meta("focus_id", "")), "start focus id")
	assertions.expect_equal("title_exit", str(exit_button.get_meta("focus_id", "")), "exit focus id")
	assertions.expect_equal(start, title.get_viewport().gui_get_focus_owner(), "deferred initial focus")
	assertions.expect_equal(start.get_path_to(exit_button), start.focus_neighbor_top, "start up wraps exit")
	assertions.expect_equal(start.get_path_to(exit_button), start.focus_neighbor_bottom, "start down reaches exit")
	assertions.expect_equal(start.get_path_to(start), start.focus_neighbor_left, "start left self")
	assertions.expect_equal(start.get_path_to(start), start.focus_neighbor_right, "start right self")
	assertions.expect_equal(exit_button.get_path_to(start), exit_button.focus_neighbor_top, "exit up reaches start")
	assertions.expect_equal(exit_button.get_path_to(start), exit_button.focus_neighbor_bottom, "exit down wraps start")
	assertions.expect_equal(exit_button.get_path_to(exit_button), exit_button.focus_neighbor_left, "exit left self")
	assertions.expect_equal(exit_button.get_path_to(exit_button), exit_button.focus_neighbor_right, "exit right self")
	context["tree"].root.remove_child(title)
	title.free()


func _test_project_settings_contract(assertions: Variant) -> void:
	assertions.expect_equal("4.7.2-stable", FileAccess.get_file_as_string("res://.godot-version").strip_edges(), "Godot version file")
	var gitignore := FileAccess.get_file_as_string("res://.gitignore")
	for ignored_entry in [".godot/", "tools/", "build/", "artifacts/", "work/", "*.log", ".godot/export_credentials.cfg"]:
		assertions.expect_true(ignored_entry in gitignore.split("\n"), "gitignore contains %s" % ignored_entry)
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
		"res://tools/export_templates/4.7.2.stable/windows_debug_x86_64.exe",
		export_config.get_value("preset.0.options", "custom_template/debug", ""),
		"fixed debug export template",
	)
	assertions.expect_equal(
		"res://tools/export_templates/4.7.2.stable/windows_release_x86_64.exe",
		export_config.get_value("preset.0.options", "custom_template/release", ""),
		"fixed release export template",
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


func _test_gate_script_argument_validation(assertions: Variant) -> void:
	var script_path := ProjectSettings.globalize_path("res://tests/run_gate_checks.ps1")
	var invalid_gate_output: Array[String] = []
	var invalid_gate_exit := OS.execute(
		"powershell.exe",
		PackedStringArray([
			"-NoProfile",
			"-ExecutionPolicy",
			"Bypass",
			"-File",
			script_path,
			"-GateNumber",
			"0",
			"-Suite",
			"all",
		]),
		invalid_gate_output,
		true,
	)
	assertions.expect_equal(2, invalid_gate_exit, "invalid GateNumber rejected")
	var invalid_suite_output: Array[String] = []
	var invalid_suite_exit := OS.execute(
		"powershell.exe",
		PackedStringArray([
			"-NoProfile",
			"-ExecutionPolicy",
			"Bypass",
			"-File",
			script_path,
			"-GateNumber",
			"1",
			"-Suite",
			"invalid",
		]),
		invalid_suite_output,
		true,
	)
	assertions.expect_equal(2, invalid_suite_exit, "invalid Suite rejected")


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
		"settings_path": qa_settings_path,
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


func _test_launch_argument_contract(assertions: Variant, context: Dictionary) -> void:
	var parser := load("res://src/app/launch_arguments.gd")
	var valid_smoke: Dictionary = parser.parse_debug(PackedStringArray([
		"--smoke-quit=120",
		"--settings-path=" + context["test_path"],
	]))
	assertions.expect_true(valid_smoke["valid"], "valid smoke accepted")
	assertions.expect_equal(&"smoke_quit", valid_smoke["mode"], "smoke mode")
	assertions.expect_equal(120, valid_smoke["smoke_frames"], "smoke physics frames")

	for invalid_value in ["", "abc", "0", "-1", "1.5"]:
		var invalid_smoke: Dictionary = parser.parse_debug(PackedStringArray([
			"--smoke-quit=" + invalid_value,
			"--settings-path=" + context["test_path"],
		]))
		assertions.expect_false(invalid_smoke["valid"], "invalid smoke value rejected: %s" % invalid_value)
		assertions.expect_equal("--smoke-quit", invalid_smoke["rejected_name"], "invalid smoke marker: %s" % invalid_value)

	var missing_smoke: Dictionary = parser.parse_debug(PackedStringArray([
		"--smoke-quit",
		"--settings-path=" + context["test_path"],
	]))
	assertions.expect_false(missing_smoke["valid"], "missing smoke value rejected")
	assertions.expect_equal("--smoke-quit", missing_smoke["rejected_name"], "missing smoke marker")
	var settings_only: Dictionary = parser.parse_debug(PackedStringArray(["--settings-path=" + context["test_path"]]))
	assertions.expect_false(settings_only["valid"], "settings-only rejected")
	assertions.expect_equal("--settings-path", settings_only["rejected_name"], "settings-only marker")
	var future_gate_path := ProjectSettings.globalize_path("res://artifacts/gate-02/test-user/future/settings.cfg")
	var future_gate_smoke: Dictionary = parser.parse_debug(PackedStringArray([
		"--smoke-quit=1",
		"--settings-path=" + future_gate_path,
	]))
	assertions.expect_true(future_gate_smoke["valid"], "future Gate settings path accepted")
	assertions.expect_equal(future_gate_path.replace("\\", "/").simplify_path(), future_gate_smoke["settings_path"], "future Gate settings path normalized")
	for rejected_path in [
		ProjectSettings.globalize_path("res://artifacts/gate-00/test-user/rejected/settings.cfg"),
		ProjectSettings.globalize_path("res://artifacts/gate-07/test-user/rejected/settings.cfg"),
		ProjectSettings.globalize_path("res://artifacts/gate-01/test-users/rejected/settings.cfg"),
		ProjectSettings.globalize_path("res://artifacts/gate-01/test-user/rejected/not-settings.cfg"),
	]:
		var rejected_smoke: Dictionary = parser.parse_debug(PackedStringArray([
			"--smoke-quit=1",
			"--settings-path=" + rejected_path,
		]))
		assertions.expect_false(rejected_smoke["valid"], "malformed or out-of-range Gate path rejected: %s" % rejected_path)
		assertions.expect_equal("--settings-path", rejected_smoke["rejected_name"], "rejected Gate path marker: %s" % rejected_path)
