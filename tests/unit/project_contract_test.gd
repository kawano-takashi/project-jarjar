extends RefCounted


const REMOVED_PRODUCTION_TOKENS: PackedStringArray = [
	"inventory",
	"fusion",
	"loot",
	"rarity",
	"affix",
	"equipment",
	"score",
	"iteminstance",
	"item_instance",
	"rewardroll",
	"reward_roll",
	"affixroll",
	"affix_roll",
	"inventoryservice",
	"inventory_service",
	"fusionservice",
	"fusion_service",
	"fusioncommitservice",
	"fusion_commit_service",
	"rewardapplicationservice",
	"reward_application_service",
	"lootservice",
	"loot_service",
	"itemfactory",
	"item_factory",
	"namegenerator",
	"name_generator",
	"scoreservice",
	"score_service",
	"raritydefinition",
	"rarity_definition",
	"affixdefinition",
	"affix_definition",
	"wavedefinition",
	"wave_definition",
	"scoredefinition",
	"score_definition",
	"equipmentslot",
	"equipment_slot",
	"itemcategory",
	"item_category",
	"wood_stick",
	"sword_trail",
]

const REMOVED_PATH_PREFIXES: PackedStringArray = [
	"res://assets/ui/inventory_icons/",
	"res://data/definitions/affixes/",
	"res://data/definitions/rarities/",
	"res://data/definitions/waves/",
	"res://src/inventory/",
	"res://src/loot/",
	"res://src/ui/inventory_",
	"res://src/ui/fusion_",
	"res://src/ui/reward_reveal_",
	"res://scenes/ui/inventory_",
	"res://scenes/ui/fusion_",
	"res://scenes/ui/reward_reveal_",
]

const REMOVED_ICON_PATHS: PackedStringArray = [
	"res://assets/ui/inventory_icons/slot_sub_weapon.png",
	"res://assets/ui/inventory_icons/weapon_bow.png",
	"res://assets/ui/inventory_icons/weapon_staff.png",
	"res://assets/ui/inventory_icons/weapon_stick.png",
	"res://assets/ui/inventory_icons/weapon_sword.png",
]

const REMOVED_TOKEN_POLICY_ALLOWLIST: PackedStringArray = [
	"res://src/release/release_pack_auditor.gd",
]

const REMOVED_MUSIC_TOKENS: PackedStringArray = [
	"music_volume",
	"bgm",
	"music",
]

const REMOVED_PATHS: PackedStringArray = [
	"res://src/inventory",
	"res://src/loot",
	"res://src/core/models/item_instance.gd",
	"res://src/core/models/reward_roll.gd",
	"res://src/core/models/affix_roll.gd",
	"res://src/core/score_service.gd",
	"res://src/definitions/rarity_definition.gd",
	"res://src/definitions/affix_definition.gd",
	"res://src/definitions/wave_definition.gd",
	"res://src/definitions/score_definition.gd",
	"res://data/definitions/affixes",
	"res://data/definitions/rarities",
	"res://data/definitions/waves",
	"res://data/definitions/score.tres",
	"res://data/definitions/weapons/wood_stick.tres",
	"res://data/definitions/weapons/bow.tres",
	"res://data/definitions/weapons/staff.tres",
	"res://data/definitions/weapons/sword.tres",
	"res://scenes/ui/inventory_screen.tscn",
	"res://scenes/ui/fusion_dialog.tscn",
	"res://scenes/ui/reward_reveal_screen.tscn",
]


func test_names() -> PackedStringArray:
	return PackedStringArray([
		"production_has_no_removed_equipment_loot_or_score_system",
		"production_and_project_settings_have_no_music_or_bgm",
		"survival_definition_file_shape_is_exact",
		"launch_balance_and_engine_contracts_are_revision_nine",
	])


func run_test(test_name: String, assertions: Variant, _context: Dictionary) -> void:
	match test_name:
		"production_has_no_removed_equipment_loot_or_score_system":
			_test_no_removed_references(assertions)
		"production_and_project_settings_have_no_music_or_bgm":
			_test_no_music_or_bgm(assertions)
		"survival_definition_file_shape_is_exact":
			_test_definition_shape(assertions)
		"launch_balance_and_engine_contracts_are_revision_nine":
			_test_launch_balance(assertions)
		_:
			assertions.expect_true(false, "registered project contract test")


func _test_no_removed_references(assertions: Variant) -> void:
	var files := PackedStringArray()
	_collect_text_files("res://src", files)
	_collect_text_files("res://scenes", files)
	_collect_text_files("res://data", files)
	var hits := PackedStringArray()
	for path: String in files:
		if path in REMOVED_TOKEN_POLICY_ALLOWLIST:
			continue
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var text: String = file.get_as_text().to_lower()
		for token: String in REMOVED_PRODUCTION_TOKENS:
			if text.contains(token):
				hits.append("%s:%s" % [path, token])
	assertions.expect_equal(PackedStringArray(), hits, "removed production concepts have zero references")
	var production_paths := PackedStringArray()
	_collect_all_paths("res://src", production_paths)
	_collect_all_paths("res://scenes", production_paths)
	_collect_all_paths("res://data", production_paths)
	_collect_all_paths("res://assets", production_paths)
	var removed_prefix_hits := PackedStringArray()
	for path: String in production_paths:
		var lowercase_path: String = path.to_lower()
		for prefix: String in REMOVED_PATH_PREFIXES:
			if lowercase_path.begins_with(prefix):
				removed_prefix_hits.append(path)
				break
	assertions.expect_equal(PackedStringArray(), removed_prefix_hits, "removed production path prefixes are absent")
	for removed_path: String in REMOVED_PATHS:
		assertions.expect_false(
			FileAccess.file_exists(removed_path) or _directory_contains_files(removed_path),
			"removed path absent: %s" % removed_path,
		)
	for icon_path: String in REMOVED_ICON_PATHS:
		assertions.expect_false(FileAccess.file_exists(icon_path), "removed inventory icon absent: %s" % icon_path)
	var audited_prefixes: Array[String] = [
		"res://tools/",
		"res://build/",
		"res://artifacts/",
		"res://work/",
		"res://.codex/",
		"res://assets/ui/inventory_icons/",
		"res://data/definitions/affixes/",
		"res://data/definitions/rarities/",
		"res://data/definitions/waves/",
		"res://src/inventory/",
		"res://src/loot/",
		"res://src/definitions/rarity_definition.",
		"res://src/definitions/affix_definition.",
		"res://src/definitions/wave_definition.",
		"res://src/definitions/score_definition.",
		"res://data/definitions/weapons/wood_stick.tres",
		"res://data/definitions/weapons/bow.tres",
		"res://data/definitions/weapons/staff.tres",
		"res://data/definitions/weapons/sword.tres",
		"res://src/ui/inventory_",
		"res://scenes/ui/reward_reveal_",
	]
	for prefix: String in audited_prefixes:
		assertions.expect_true(
			ReleasePackAuditor.FORBIDDEN_PREFIXES.has(prefix),
			"release pack auditor also forbids: %s" % prefix,
		)


func _test_no_music_or_bgm(assertions: Variant) -> void:
	var files := PackedStringArray(["res://project.godot"])
	_collect_text_files("res://src", files)
	_collect_text_files("res://scenes", files)
	_collect_text_files("res://data", files)
	var hits := PackedStringArray()
	for path: String in files:
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			hits.append("%s:unreadable" % path)
			continue
		var text: String = file.get_as_text().to_lower()
		for token: String in REMOVED_MUSIC_TOKENS:
			if text.contains(token):
				hits.append("%s:%s" % [path, token])
	assertions.expect_equal(
		PackedStringArray(),
		hits,
		"project.godot and production resources have no music/BGM setting or reference",
	)


func _test_definition_shape(assertions: Variant) -> void:
	assertions.expect_equal(16, _files_with_extension("res://data/definitions/weapons", "tres").size(), "eight base and eight evolved weapons")
	assertions.expect_equal(8, _files_with_extension("res://data/definitions/passives", "tres").size(), "eight passive definitions")
	assertions.expect_equal(8, _files_with_extension("res://data/definitions/evolutions", "tres").size(), "eight evolution mappings")
	assertions.expect_equal(7, _files_with_extension("res://data/definitions/enemies", "tres").size(), "six normal roles plus one separate swarm unit")
	assertions.expect_equal(8, _files_with_extension("res://data/definitions/swarm_events", "tres").size(), "one swarm event and seven schedule definitions")
	assertions.expect_equal(10, _files_with_extension("res://data/definitions/segments", "tres").size(), "ten timed enemy segments")
	assertions.expect_true(FileAccess.file_exists("res://data/balance/survival_content_manifest.tres"), "survival manifest exists")
	assertions.expect_true(FileAccess.file_exists("res://data/balance/balance_manifest.tres"), "release identity manifest exists")


func _test_launch_balance(assertions: Variant) -> void:
	var expected: Array[String] = [
		"weapon_resonance_wave",
		"weapon_homing_core",
		"weapon_direction_needle",
		"weapon_arc_crystal",
		"weapon_return_ring",
		"weapon_orbit_array",
		"weapon_mass_shot",
		"weapon_zero_field",
		"level_up_modal",
		"chest_reward",
		"boss_phase_three",
		"result",
	]
	assertions.expect_equal(expected, LaunchArguments.QA_SCENARIOS, "QA scenarios expose only survival fixtures")
	var catalog := DefinitionCatalog.new()
	assertions.expect_true(catalog.load_and_validate(), "project contract catalog valid: %s" % catalog.error_text)
	if catalog.is_valid:
		assertions.expect_equal(9, catalog.balance_manifest().balance_revision, "balance revision is nine")
	assertions.expect_equal(60, int(ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 60)), "gameplay physics is fixed at 60Hz")
	assertions.expect_equal("4.7", str(ProjectSettings.get_setting("application/config/features", PackedStringArray())[0]).left(3), "project targets Godot 4.7")
	assertions.expect_false(InputMap.has_action(&"item_lock"), "old item lock input removed")
	assertions.expect_false(InputMap.has_action(&"reward_open_all"), "old reward input removed")


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


func _collect_all_paths(directory_path: String, output: PackedStringArray) -> void:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry: String = directory.get_next()
	while not entry.is_empty():
		var path: String = directory_path.path_join(entry)
		if directory.current_is_dir():
			_collect_all_paths(path, output)
		else:
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


func _directory_contains_files(directory_path: String) -> bool:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return false
	directory.list_dir_begin()
	var entry: String = directory.get_next()
	while not entry.is_empty():
		var child_path := directory_path.path_join(entry)
		if directory.current_is_dir():
			if _directory_contains_files(child_path):
				directory.list_dir_end()
				return true
		else:
			directory.list_dir_end()
			return true
		entry = directory.get_next()
	directory.list_dir_end()
	return false
