extends RefCounted


func test_release_launch_accepts_only_normal_game(assertions: Variant, _context: Dictionary) -> void:
	var launch := LaunchArguments.parse_release(PackedStringArray())
	assertions.expect_true(launch["valid"], "release starts normally without custom arguments")
	assertions.expect_equal(LaunchArguments.MODE_NORMAL, launch.get("mode"), "release starts the game")
	assertions.expect_equal("user://settings.cfg", launch.get("settings_path"), "normal launch uses player settings")
	for arguments: PackedStringArray in [
		PackedStringArray(["--smoke-run"]),
		PackedStringArray(["--release-pack-audit"]),
		PackedStringArray(["--qa-scenario=result"]),
		PackedStringArray(["--smoke-quit=1"]),
		PackedStringArray(["--performance=full_hd_500_2000", "--run-seed=5002000"]),
		PackedStringArray(["--run-seed=1"]),
		PackedStringArray(["--unknown"]),
	]:
		assertions.expect_false(
			LaunchArguments.parse_release(arguments)["valid"],
			"release rejects test, debug, and unknown arguments: %s" % str(arguments),
		)
