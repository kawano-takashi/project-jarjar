extends SceneTree


const SOURCE_EXTENSIONS: Array[String] = ["gd", "gdshader", "tscn", "tres"]
const IGNORED_ROOTS: Array[String] = [".codex", ".git", ".godot", "artifacts", "build", "work"]
const TEST_TIMEOUT_MS: int = 600_000

var _errors := ErrorCounter.new()
var _discovery_error: String = ""
var _deadline_ms: int = 0
var _finished: bool = false


# GDScript runtime errors can abort a test method without stopping the runner.
class ErrorCounter extends Logger:


	var _count: int = 0
	var _mutex := Mutex.new()


	func _log_error(
		_function: String, _file: String, _line: int, _code: String,
		_rationale: String, _editor_notify: bool, error_type: int,
		_script_backtraces: Array[ScriptBacktrace],
	) -> void:
		if error_type != Logger.ERROR_TYPE_WARNING:
			_mutex.lock()
			_count += 1
			_mutex.unlock()


	func count() -> int:
		_mutex.lock()
		var result := _count
		_mutex.unlock()
		return result


func _initialize() -> void:
	OS.add_logger(_errors)
	_deadline_ms = Time.get_ticks_msec() + TEST_TIMEOUT_MS
	_run.call_deferred()


func _process(_delta: float) -> bool:
	if not _finished and Time.get_ticks_msec() >= _deadline_ms:
		_abort("timeout")
	return false


func _run() -> void:
	var started_ms := Time.get_ticks_msec()
	var verbose_value := OS.get_environment("JARJAR_TEST_VERBOSE")
	if not OS.get_cmdline_user_args().is_empty() or verbose_value not in ["", "0", "1"]:
		_abort("use JARJAR_TEST_FILTER and JARJAR_TEST_VERBOSE=0 or 1")
		return
	var verbose := verbose_value == "1"
	var test_filter := OS.get_environment("JARJAR_TEST_FILTER")
	var settings: Variant = root.get_node_or_null("SettingsStore")
	if settings == null or settings.initialize_for_runner() != OK:
		_abort("temporary settings initialization failed")
		return
	var temporary_root: String = settings.active_settings_path.get_base_dir().get_base_dir()

	var paths: Array[String] = []
	_collect_paths("res://", paths)
	paths.sort()
	var cases := _load_and_discover(paths)
	if not _discovery_error.is_empty() or _errors.count() > 0:
		_abort("source discovery: %s" % _discovery_error)
		return
	if not test_filter.is_empty():
		cases = cases.filter(func(test: Dictionary) -> bool: return test["name"] == test_filter)
	if cases.is_empty():
		_abort("no tests matched: %s" % test_filter)
		return

	var passed := 0
	var failed := 0
	for index in cases.size():
		_deadline_ms = Time.get_ticks_msec() + TEST_TIMEOUT_MS
		var test: Dictionary = cases[index]
		var assertions := JarjarAssertions.new()
		assertions.test_name = test["name"]
		assertions.verbose = verbose
		var errors_before := _errors.count()
		var test_started_ms := Time.get_ticks_msec()
		var test_path := temporary_root.path_join("cases/%04d/settings.cfg" % index)
		var setup_error: Error = settings.use_test_path(test_path)
		if setup_error == OK:
			var context := {"tree": self, "settings_store": settings, "test_path": test_path}
			var instance: RefCounted = test["script"].new()
			await instance.call(test["method"], assertions, context)
			assertions.expect_true(assertions.check_count > 0, "test executed assertions")
		else:
			assertions.expect_equal(OK, setup_error, "temporary settings setup")
		assertions.expect_equal(OK, settings.restore_runner_bootstrap_path(), "temporary settings reset")
		assertions.expect_equal(errors_before, _errors.count(), "no engine or script errors")
		if assertions.failures > 0:
			failed += 1
		else:
			passed += 1
		if verbose or assertions.failures > 0:
			print("TEST name=%s result=%s elapsed_ms=%d" % [
				test["name"], "FAIL" if assertions.failures > 0 else "PASS",
				Time.get_ticks_msec() - test_started_ms,
			])
	var exit_code := _finish(0 if failed == 0 else 1)
	print("TEST_SUMMARY passed=%d failed=%d resources=%d elapsed_ms=%d exit_code=%d" % [
		passed, failed, paths.size(), Time.get_ticks_msec() - started_ms, exit_code,
	])


func _collect_paths(directory_path: String, paths: Array[String]) -> void:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		_discovery_error = "cannot open %s" % directory_path
		return
	for child in directory.get_directories():
		if directory_path == "res://" and child in IGNORED_ROOTS:
			continue
		_collect_paths(directory_path.path_join(child), paths)
	for file in directory.get_files():
		if file.get_extension().to_lower() in SOURCE_EXTENSIONS:
			paths.append(directory_path.path_join(file))


func _load_and_discover(paths: Array[String]) -> Array[Dictionary]:
	var cases: Array[Dictionary] = []
	var names: Dictionary[String, bool] = {}
	for path in paths:
		var resource := ResourceLoader.load(path)
		if resource == null or (resource is Script and not resource.can_instantiate()):
			_discovery_error = "cannot load %s" % path
			return []
		if not path.begins_with("res://tests/") or not path.ends_with("_test.gd"):
			continue
		var script := resource as Script
		if script.get_instance_base_type() != &"RefCounted":
			_discovery_error = "test must extend RefCounted: %s" % path
			return []
		var case_count := cases.size()
		for method in script.get_script_method_list():
			var method_name := String(method["name"])
			if not method_name.begins_with("test_"):
				continue
			var test_name := method_name.trim_prefix("test_")
			if test_name.is_empty() or names.has(test_name) or method["args"].size() != 2:
				_discovery_error = "invalid or duplicate test: %s in %s" % [method_name, path]
				return []
			names[test_name] = true
			cases.append({"name": test_name, "method": method_name, "script": script})
		if cases.size() == case_count:
			_discovery_error = "no test_ functions in %s" % path
			return []
	return cases


func _abort(reason: String) -> void:
	print("RUNNER_FAILED reason=%s" % reason)
	_finish(2)


func _finish(exit_code: int) -> int:
	_finished = true
	var settings: Variant = root.get_node_or_null("SettingsStore")
	if settings != null and settings.runner_safe_mode and settings.finish_runner() != OK:
		print("RUNNER_FAILED reason=temporary settings cleanup")
		exit_code = 2
	if _errors.count() > 0 and exit_code == 0:
		exit_code = 1
	OS.remove_logger(_errors)
	quit(exit_code)
	return exit_code
