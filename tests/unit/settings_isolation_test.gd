extends RefCounted


const SettingsScript = preload("res://src/core/settings_store.gd")


func test_names() -> PackedStringArray:
	return PackedStringArray([
		"runner_settings_are_isolated_and_removed",
		"runner_settings_are_removed_when_owner_is_freed",
	])


func run_test(test_name: String, assertions: Variant, _context: Dictionary) -> void:
	match test_name:
		"runner_settings_are_isolated_and_removed":
			_test_isolation(assertions)
		"runner_settings_are_removed_when_owner_is_freed":
			var settings := SettingsScript.new()
			assertions.expect_equal(OK, settings.initialize_for_runner(), "temporary settings initialized")
			var temporary_root := settings.active_settings_path.get_base_dir().get_base_dir()
			settings.free()
			assertions.expect_false(temporary_root.is_empty(), "temporary root was allocated")
			assertions.expect_false(DirAccess.dir_exists_absolute(temporary_root), "owner destruction removes settings even without explicit completion")
		_:
			assertions.expect_true(false, "registered settings isolation test")


func _test_isolation(assertions: Variant) -> void:
	var first := SettingsScript.new()
	var second := SettingsScript.new()
	var first_error := first.initialize_for_runner()
	var second_error := second.initialize_for_runner()
	assertions.expect_equal(OK, first_error, "first session initialized")
	assertions.expect_equal(OK, second_error, "second session initialized")
	if first_error != OK or second_error != OK:
		first.free()
		second.free()
		return
	var first_root := first.active_settings_path.get_base_dir().get_base_dir()
	var second_root := second.active_settings_path.get_base_dir().get_base_dir()
	var repository_root := ProjectSettings.globalize_path("res://").replace("\\", "/").to_lower()
	assertions.expect_not_equal(first_root, second_root, "concurrent sessions use distinct directories")
	assertions.expect_false(first_root.to_lower().begins_with(repository_root), "test settings are outside the repository")
	assertions.expect_equal(ERR_ALREADY_IN_USE, first.initialize_for_runner(), "active session cannot be replaced")
	assertions.expect_equal(ERR_INVALID_PARAMETER, first.use_test_path(second.active_settings_path), "another session's settings cannot be modified")
	assertions.expect_equal(ERR_INVALID_PARAMETER, first.use_test_path(ProjectSettings.globalize_path("user://settings.cfg")), "real user settings cannot be modified")
	assertions.expect_equal(ERR_INVALID_PARAMETER, first.use_test_path(first_root.path_join("../settings.cfg")), "parent traversal is rejected")
	var test_path := first_root.path_join("cases/nested/settings.cfg")
	assertions.expect_equal(OK, first.use_test_path(test_path), "nested case settings are created")
	first.master_volume = 0.25
	assertions.expect_equal(OK, first.save_settings(), "settings save remains available to tests")
	first.master_volume = 0.75
	assertions.expect_equal(OK, first.reload_settings(), "settings reload remains available to tests")
	assertions.expect_float(0.25, first.master_volume, "saved settings are reloaded")
	assertions.expect_equal(OK, first.restore_runner_bootstrap_path(), "runner settings are restored between cases")
	assertions.expect_float(1.0, first.master_volume, "restored settings use clean defaults")
	assertions.expect_equal(OK, first.finish_runner(), "first session cleanup succeeds")
	assertions.expect_false(DirAccess.dir_exists_absolute(first_root), "cleanup removes nested files and directories")
	assertions.expect_true(DirAccess.dir_exists_absolute(second_root), "cleanup preserves the other session")
	assertions.expect_equal(ERR_UNAUTHORIZED, first.use_test_path(test_path), "completed session cannot recreate files")
	assertions.expect_equal(OK, second.finish_runner(), "second session cleanup succeeds")
	assertions.expect_false(DirAccess.dir_exists_absolute(second_root), "second directory removed")
	first.free()
	second.free()
