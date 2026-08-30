extends RefCounted


const LEGACY_TOKENS: PackedStringArray = [
	"CombatSkillSystem",
	"SkillEquipService",
	"skill_library",
	"wild_material_count",
	"unique_id",
	"Rarity.UNIQUE",
	"MainWeaponType",
	"RewardKind",
	"FusionWildToggle",
	"SkillPanel",
]


func test_names() -> PackedStringArray:
	return PackedStringArray([
		"production_has_no_skill_unique_wild_or_armor_paths",
		"definition_file_shape_matches_unified_item_system",
		"launch_and_balance_contracts_are_current",
	])


func run_test(test_name: String, assertions: Variant, _context: Dictionary) -> void:
	match test_name:
		"production_has_no_skill_unique_wild_or_armor_paths":
			_test_no_legacy_references(assertions)
		"definition_file_shape_matches_unified_item_system":
			_test_definition_shape(assertions)
		"launch_and_balance_contracts_are_current":
			_test_launch_balance(assertions)
		_:
			assertions.expect_true(false, "registered project contract test")


func _test_no_legacy_references(assertions: Variant) -> void:
	var files: PackedStringArray = PackedStringArray()
	_collect_text_files("res://src", files)
	_collect_text_files("res://scenes", files)
	_collect_text_files("res://data", files)
	var hits := PackedStringArray()
	for path: String in files:
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var text: String = file.get_as_text()
		for token: String in LEGACY_TOKENS:
			if text.contains(token):
				hits.append("%s:%s" % [path, token])
	assertions.expect_equal(PackedStringArray(), hits, "production references to removed systems are zero")
	for removed_path: String in [
		"res://src/combat/combat_skill_system.gd",
		"res://src/skills/skill_equip_service.gd",
		"res://src/definitions/skill_definition.gd",
		"res://src/definitions/unique_definition.gd",
		"res://data/definitions/rarities/unique.tres",
		"res://data/definitions/affixes/cooldown_reduction_pct.tres",
		"res://data/definitions/affixes/skill_power_pct.tres",
	]:
		assertions.expect_false(FileAccess.file_exists(removed_path), "removed file absent: %s" % removed_path)


func _test_definition_shape(assertions: Variant) -> void:
	assertions.expect_equal(4, _files_with_extension("res://data/definitions/weapons", "tres").size(), "four weapon definitions including starter")
	assertions.expect_equal(7, _files_with_extension("res://data/definitions/affixes", "tres").size(), "seven charm effect definitions")
	assertions.expect_equal(4, _files_with_extension("res://data/definitions/rarities", "tres").size(), "unique rarity definition removed")
	assertions.expect_equal(0, _files_with_extension("res://data/definitions/skills", "tres").size(), "skill resources removed")
	assertions.expect_equal(0, _files_with_extension("res://data/definitions/uniques", "tres").size(), "unique resources removed")
	for removed_image: String in ["slot_head.png", "slot_body.png", "slot_hands.png", "slot_feet.png"]:
		assertions.expect_false(FileAccess.file_exists("res://assets/ui/inventory_icons/" + removed_image), "unused armor image removed: %s" % removed_image)


func _test_launch_balance(assertions: Variant) -> void:
	var expected: Array[String] = [
		"weapon_wood_stick", "weapon_bow", "weapon_staff", "weapon_sword",
		"pre_quota_death", "pre_quota_timeout", "post_quota_death",
		"reward_controls", "inventory_controller", "result_controller", "boss_299",
	]
	assertions.expect_equal(expected, LaunchArguments.QA_SCENARIOS, "QA scenarios contain no removed immortal unique fixture")
	var catalog := DefinitionCatalog.new()
	assertions.expect_true(catalog.load_and_validate(), "project contract catalog valid")
	assertions.expect_equal(2, catalog.balance_manifest().balance_revision, "balance revision is two")
	assertions.expect_equal("4.7", str(ProjectSettings.get_setting("application/config/features", PackedStringArray())[0]).left(3), "project targets Godot 4.7")


func _collect_text_files(directory_path: String, output: PackedStringArray) -> void:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry: String = directory.get_next()
	while not entry.is_empty():
		var path: String = directory_path.path_join(entry)
		if directory.current_is_dir():
			_collect_text_files(path, output)
		elif entry.get_extension().to_lower() in ["gd", "tscn", "tres"]:
			output.append(path)
		entry = directory.get_next()
	directory.list_dir_end()


func _files_with_extension(directory_path: String, extension: String) -> PackedStringArray:
	var result := PackedStringArray()
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return result
	directory.list_dir_begin()
	var entry: String = directory.get_next()
	while not entry.is_empty():
		if not directory.current_is_dir() and entry.get_extension().to_lower() == extension:
			result.append(entry)
		entry = directory.get_next()
	directory.list_dir_end()
	result.sort()
	return result
