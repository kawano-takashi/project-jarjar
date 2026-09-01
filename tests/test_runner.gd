extends SceneTree


const TEST_TIMEOUT_MS: int = 600000
const TEST_SETTINGS_ROOT: String = "res://artifacts/gdscript-tests/settings"
const PREFLIGHT_EXTENSIONS: Array[String] = ["gd", "gdshader", "tscn", "tres"]
const IGNORED_ROOT_DIRECTORIES: Array[String] = [
	".codex",
	".git",
	".godot",
	"artifacts",
	"build",
	"work",
]

var _started: bool = false
var _finished: bool = false
var _deadline_ms: int = 0


func _initialize() -> void:
	_started = true
	_deadline_ms = Time.get_ticks_msec() + TEST_TIMEOUT_MS
	_run()


func _process(_delta: float) -> bool:
	if _started and not _finished and Time.get_ticks_msec() >= _deadline_ms:
		print("RUNNER_TIMEOUT")
		_finished = true
		quit(2)
		return false
	if _started:
		return false
	_started = true
	_run.call_deferred()
	return false


func _run() -> void:
	var user_arguments := OS.get_cmdline_user_args()
	if not user_arguments.is_empty():
		_reject(_option_name(user_arguments[0]))
		return

	var settings_store: Variant = root.get_node_or_null("SettingsStore")
	if settings_store == null:
		_bootstrap_failed("autoload")
		return

	var test_user_root := ProjectSettings.globalize_path(TEST_SETTINGS_ROOT).replace("\\", "/").simplify_path()
	var bootstrap_path := test_user_root.path_join("runner/settings.cfg")
	var initialize_error: Error = settings_store.initialize_for_runner(bootstrap_path)
	if initialize_error != OK:
		_bootstrap_failed("initialize code=%d" % initialize_error)
		return
	if (
		not settings_store.initialized
		or not settings_store.runner_safe_mode
		or settings_store.active_settings_path != bootstrap_path
	):
		_bootstrap_failed("state")
		return

	var assertion_script := load("res://tests/assertions.gd")
	if assertion_script == null:
		_bootstrap_failed("assertions")
		return

	var resource_paths: Array[String] = []
	var test_script_paths: Array[String] = []
	if not _collect_project_paths("res://", resource_paths, test_script_paths):
		_bootstrap_failed("discovery")
		return
	if not _preflight_resources(resource_paths):
		_bootstrap_failed("source-preflight")
		return
	print("SOURCE_PREFLIGHT_OK resources=%d" % resource_paths.size())

	var discovery := _discover_tests(test_script_paths)
	if not discovery["valid"]:
		_bootstrap_failed(str(discovery["reason"]))
		return
	var test_cases: Array = discovery["tests"]
	if test_cases.is_empty():
		_bootstrap_failed("empty-test-set")
		return

	var passed := 0
	var failed := 0
	var suite_started_ms := Time.get_ticks_msec()
	for test_index in test_cases.size():
		_deadline_ms = Time.get_ticks_msec() + TEST_TIMEOUT_MS
		var test_case: Dictionary = test_cases[test_index]
		var test_name: String = test_case["name"]
		var test_path := (
			test_user_root
			.path_join("cases")
			.path_join("case-%04d" % test_index)
			.path_join("settings.cfg")
		)
		var assertions: Variant = assertion_script.new()
		var test_started_ms := Time.get_ticks_msec()
		var switch_error: Error = settings_store.use_test_path(test_path)
		assertions.expect_equal(OK, switch_error, "runner use_test_path")
		if switch_error == OK:
			var context := {
				"tree": self,
				"settings_store": settings_store,
				"bootstrap_path": bootstrap_path,
				"test_path": test_path,
				"test_user_root": test_user_root,
				"runner_preflight_verified": true,
			}
			var test_instance: Variant = test_case["script"].new()
			await test_instance.run_test(test_name, assertions, context)

		var restore_error: Error = settings_store.restore_runner_bootstrap_path()
		assertions.expect_equal(OK, restore_error, "runner restore bootstrap")
		assertions.expect_equal(bootstrap_path, settings_store.active_settings_path, "runner bootstrap path restored")
		assertions.expect_true(settings_store.runner_safe_mode, "runner safe mode preserved")
		assertions.expect_float(1.0, settings_store.master_volume, "runner bootstrap defaults restored")

		for record in assertions.records:
			print(
				"ASSERT test=%s label=%s expected=%s actual=%s result=%s"
				% [
					test_name,
					record["label"],
					record["expected"],
					record["actual"],
					"PASS" if record["passed"] else "FAIL",
				]
			)
		var elapsed_ms := Time.get_ticks_msec() - test_started_ms
		if assertions.has_failures():
			failed += 1
			print("TEST name=%s expected=PASS actual=FAIL elapsed_ms=%d" % [test_name, elapsed_ms])
		else:
			passed += 1
			print("TEST name=%s expected=PASS actual=PASS elapsed_ms=%d" % [test_name, elapsed_ms])

	var total_elapsed_ms := Time.get_ticks_msec() - suite_started_ms
	print("TEST_SUMMARY passed=%d failed=%d elapsed_ms=%d" % [passed, failed, total_elapsed_ms])
	_finished = true
	quit(0 if failed == 0 else 1)


func _collect_project_paths(
	directory_path: String,
	resource_paths: Array[String],
	test_script_paths: Array[String],
) -> bool:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return false
	directory.list_dir_begin()
	var entry_name := directory.get_next()
	while not entry_name.is_empty():
		var child_path := directory_path.path_join(entry_name)
		if directory.current_is_dir():
			if directory_path == "res://" and entry_name in IGNORED_ROOT_DIRECTORIES:
				entry_name = directory.get_next()
				continue
			if not _collect_project_paths(child_path, resource_paths, test_script_paths):
				directory.list_dir_end()
				return false
		else:
			var extension := entry_name.get_extension().to_lower()
			if extension in PREFLIGHT_EXTENSIONS:
				resource_paths.append(child_path)
			if child_path.begins_with("res://tests/") and entry_name.ends_with("_test.gd"):
				test_script_paths.append(child_path)
		entry_name = directory.get_next()
	directory.list_dir_end()
	return true


func _preflight_resources(resource_paths: Array[String]) -> bool:
	for resource_path in resource_paths:
		var resource: Resource = ResourceLoader.load(resource_path)
		if resource == null:
			print("SOURCE_PREFLIGHT_FAILED path=%s" % resource_path)
			return false
		if resource is Script and not (resource as Script).can_instantiate():
			print("SOURCE_PREFLIGHT_FAILED path=%s reason=script_cannot_instantiate" % resource_path)
			return false
	return true


func _discover_tests(test_script_paths: Array[String]) -> Dictionary:
	var test_cases: Array[Dictionary] = []
	for script_path in test_script_paths:
		var test_script := ResourceLoader.load(script_path)
		if test_script == null:
			return {"valid": false, "reason": "test-load path=%s" % script_path, "tests": []}
		if test_script is Script and not (test_script as Script).can_instantiate():
			return {"valid": false, "reason": "test-parse path=%s" % script_path, "tests": []}
		var test_instance: Variant = test_script.new()
		if not test_instance.has_method("test_names") or not test_instance.has_method("run_test"):
			return {"valid": false, "reason": "test-contract path=%s" % script_path, "tests": []}
		var names: Variant = test_instance.test_names()
		if typeof(names) not in [TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY] or names.is_empty():
			return {"valid": false, "reason": "test-names path=%s" % script_path, "tests": []}
		var names_in_script: Dictionary = {}
		for test_name_value in names:
			var test_name := str(test_name_value)
			if test_name.is_empty() or names_in_script.has(test_name):
				return {"valid": false, "reason": "test-name path=%s" % script_path, "tests": []}
			names_in_script[test_name] = true
			test_cases.append({"name": test_name, "script": test_script, "path": script_path})
	return {"valid": true, "reason": "", "tests": test_cases}


func _bootstrap_failed(reason: String) -> void:
	print("RUNNER_BOOTSTRAP_FAILED reason=%s" % reason)
	_finished = true
	quit(2)


func _reject(argument_name: String) -> void:
	print("RUNNER_ARGUMENT_REJECTED name=%s" % argument_name)
	_finished = true
	quit(2)


func _option_name(argument: String) -> String:
	if argument.is_empty():
		return "missing"
	var equals_index := argument.find("=")
	return argument if equals_index < 0 else argument.substr(0, equals_index)
