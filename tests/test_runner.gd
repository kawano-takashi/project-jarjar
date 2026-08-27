extends SceneTree


const VALID_SUITES: Array[String] = ["unit", "scenario", "simulation", "all"]
const TEST_TIMEOUT_MS: int = 600000

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
	var invocation := _validate_invocation()
	if not invocation["valid"]:
		_reject(invocation["rejected_name"])
		return

	var settings_store: Variant = root.get_node_or_null("SettingsStore")
	if settings_store == null:
		print("RUNNER_BOOTSTRAP_FAILED reason=autoload")
		quit(2)
		return
	var initialize_error: Error = settings_store.initialize_for_runner(invocation["settings_path"])
	if initialize_error != OK:
		print("RUNNER_BOOTSTRAP_FAILED reason=initialize code=%d" % initialize_error)
		quit(2)
		return
	if (
		not settings_store.initialized
		or not settings_store.runner_safe_mode
		or settings_store.active_settings_path != invocation["settings_path"]
	):
		print("RUNNER_BOOTSTRAP_FAILED reason=state")
		quit(2)
		return

	var assertion_script := load("res://tests/assertions.gd")
	if assertion_script == null:
		print("RUNNER_BOOTSTRAP_FAILED reason=assertions")
		quit(2)
		return
	var registry := _load_registry(invocation["suite"])
	if not registry["valid"] or registry["tests"].is_empty():
		print("RUNNER_BOOTSTRAP_FAILED reason=empty-suite")
		quit(2)
		return

	var bootstrap_path: String = invocation["settings_path"]
	var test_user_root := bootstrap_path.get_base_dir().get_base_dir()
	var passed := 0
	var failed := 0
	var suite_started_ms := Time.get_ticks_msec()
	for test_case in registry["tests"]:
		_deadline_ms = Time.get_ticks_msec() + TEST_TIMEOUT_MS
		var test_name: String = test_case["name"]
		var test_path := test_user_root.path_join(test_name).path_join("settings.cfg")
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
			await test_case["instance"].run_test(test_name, assertions, context)

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


func _validate_invocation() -> Dictionary:
	var engine_arguments := OS.get_cmdline_args()
	var script_index := engine_arguments.find("--script")
	if (
		script_index < 0
		or script_index + 1 >= engine_arguments.size()
		or engine_arguments[script_index + 1] != "res://tests/test_runner.gd"
	):
		return _invalid("--script")

	var user_arguments := OS.get_cmdline_user_args()
	var suite := ""
	var settings_path := ""
	var index := 0
	while index < user_arguments.size():
		var argument := user_arguments[index]
		if argument == "--suite":
			if not suite.is_empty():
				return _invalid("--suite")
			if index + 1 >= user_arguments.size() or user_arguments[index + 1].begins_with("--"):
				return _invalid("missing")
			suite = user_arguments[index + 1]
			index += 2
			continue
		if argument.begins_with("--settings-path="):
			if not settings_path.is_empty():
				return _invalid("--settings-path")
			settings_path = _normalize_settings_path(argument.trim_prefix("--settings-path="))
			if settings_path.is_empty():
				return _invalid("--settings-path")
			index += 1
			continue
		return _invalid(_option_name(argument))

	if suite.is_empty() or settings_path.is_empty():
		return _invalid("missing")
	if not suite in VALID_SUITES:
		return _invalid("--suite")
	return {"valid": true, "suite": suite, "settings_path": settings_path}


func _load_registry(suite: String) -> Dictionary:
	var requested_suites: Array[String] = []
	if suite == "all":
		requested_suites.assign(["unit", "scenario", "simulation"])
	else:
		requested_suites.append(suite)
	var test_cases: Array[Dictionary] = []
	for suite_name in requested_suites:
		var script_paths: Array[String] = []
		if suite_name == "unit":
			script_paths.append("res://tests/unit/smoke_bootstrap_test.gd")
		for script_path in script_paths:
			var test_script := load(script_path)
			if test_script == null:
				return {"valid": false, "tests": []}
			var instance: Variant = test_script.new()
			for test_name in instance.test_names():
				test_cases.append({"name": str(test_name), "instance": instance})
	return {"valid": true, "tests": test_cases}


func _normalize_settings_path(path: String) -> String:
	var normalized := path.replace("\\", "/").simplify_path()
	if not normalized.is_absolute_path() or normalized.get_file().to_lower() != "settings.cfg":
		return ""
	for gate_number in range(1, 7):
		var allowed := ProjectSettings.globalize_path(
			"res://artifacts/gate-%02d/test-user/runner/settings.cfg" % gate_number
		).replace("\\", "/").simplify_path()
		if normalized.to_lower() == allowed.to_lower():
			return normalized
	return ""


func _reject(argument_name: String) -> void:
	print("RUNNER_ARGUMENT_REJECTED name=%s" % argument_name)
	quit(2)


func _invalid(argument_name: String) -> Dictionary:
	return {"valid": false, "rejected_name": argument_name}


func _option_name(argument: String) -> String:
	if argument.is_empty():
		return "missing"
	var equals_index := argument.find("=")
	return argument if equals_index < 0 else argument.substr(0, equals_index)
