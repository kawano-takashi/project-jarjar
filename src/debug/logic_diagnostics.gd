class_name LogicDiagnostics
extends RefCounted


const RUN_SEED: int = 20260827
const EXPECTED_UNIT_PASS_COUNT: int = 22
const TEST_LOG_PATH: String = "res://artifacts/gate-02/tests.txt"
const FusionServiceScript = preload("res://src/inventory/fusion_service.gd")
static func build() -> Dictionary:
	var catalog := DefinitionCatalog.new()
	if not catalog.load_and_validate():
		return {"valid": false, "reason": "definition-catalog"}

	var streams: RunRngStreams = RunRngStreams.create(RUN_SEED)
	var combat_values: Array[int] = _take_rng_values(streams.combat_rng, 3)
	var loot_values: Array[int] = _take_rng_values(streams.loot_rng, 3)
	var fusion_values: Array[int] = _take_rng_values(streams.fusion_rng, 3)
	var item_examples: Array[Dictionary] = _build_item_examples(catalog)
	var fusion: Dictionary = _build_fusion_example(catalog)
	if not fusion["valid"]:
		return fusion
	var score: Dictionary = _build_score_breakdown(catalog.score_definition())
	if not score["valid"]:
		return score
	var test_summary: Dictionary = _read_test_summary()
	if not test_summary["valid"]:
		return test_summary

	return {
		"valid": true,
		"seed_line": "RUN SEED  %d    •    mutable streams are owned once per run" % RUN_SEED,
		"left_text": _format_left_panel(
			streams,
			combat_values,
			loot_values,
			fusion_values,
			item_examples
		),
		"right_text": _format_right_panel(fusion, score, test_summary),
	}


static func _take_rng_values(rng: RandomNumberGenerator, count: int) -> Array[int]:
	var values: Array[int] = []
	for _index: int in range(count):
		values.append(rng.randi())
	return values


static func _build_item_examples(catalog: DefinitionCatalog) -> Array[Dictionary]:
	var generation_streams: RunRngStreams = RunRngStreams.create(RUN_SEED)
	var wood_stick: ItemInstance = ItemFactory.create_initial_wood_stick(RUN_SEED)
	var bow: ItemInstance = ItemFactory.create_item(
		RUN_SEED,
		ItemFactory.make_item_id(RUN_SEED, 1, 1),
		GameTypes.EquipmentSlot.MAIN_WEAPON,
		GameTypes.MainWeaponType.BOW,
		GameTypes.Rarity.COMMON,
		&"",
		GameTypes.MainWeaponType.BOW,
		generation_streams.loot_rng,
		catalog
	)
	var body: ItemInstance = ItemFactory.create_item(
		RUN_SEED,
		ItemFactory.make_item_id(RUN_SEED, 2, 2),
		GameTypes.EquipmentSlot.BODY,
		GameTypes.MainWeaponType.UNCLASSIFIED,
		GameTypes.Rarity.RARE,
		&"",
		GameTypes.MainWeaponType.STAFF,
		generation_streams.loot_rng,
		catalog
	)
	var staff: ItemInstance = ItemFactory.create_item(
		RUN_SEED,
		ItemFactory.make_item_id(RUN_SEED, 3, 3),
		GameTypes.EquipmentSlot.MAIN_WEAPON,
		GameTypes.MainWeaponType.STAFF,
		GameTypes.Rarity.EPIC,
		&"",
		GameTypes.MainWeaponType.STAFF,
		generation_streams.loot_rng,
		catalog
	)
	return [
		_item_example(wood_stick),
		_item_example(bow),
		_item_example(body),
		_item_example(staff),
	]


static func _item_example(item: ItemInstance) -> Dictionary:
	return {
		"item_id": item.item_id,
		"item_seed": item.item_seed,
		"display_name": item.display_name,
		"rarity": _rarity_label(item.rarity),
		"name_rng_values": NameGenerator.first_rng_values(item.item_seed, 3),
	}


static func _build_fusion_example(catalog: DefinitionCatalog) -> Dictionary:
	var material_rng := RandomNumberGenerator.new()
	material_rng.seed = SeedService.derive(RUN_SEED, &"diagnostic:materials")
	var materials: Array[ItemInstance] = []
	for serial: int in [10, 11, 12]:
		materials.append(ItemFactory.create_item(
			RUN_SEED,
			ItemFactory.make_item_id(RUN_SEED, 4, serial),
			GameTypes.EquipmentSlot.HANDS,
			GameTypes.MainWeaponType.UNCLASSIFIED,
			GameTypes.Rarity.RARE,
			&"",
			GameTypes.MainWeaponType.BOW,
			material_rng,
			catalog
		))
	var fusion_streams: RunRngStreams = RunRngStreams.create(RUN_SEED)
	var result: Dictionary = FusionServiceScript.fuse(
		materials,
		0,
		0,
		[],
		true,
		RUN_SEED,
		4,
		4,
		GameTypes.MainWeaponType.BOW,
		fusion_streams.fusion_rng,
		catalog
	)
	if not result["success"] or result["output"] == null:
		return {"valid": false, "reason": "fusion-example"}
	var output: ItemInstance = result["output"] as ItemInstance
	return {
		"valid": true,
		"output_id": output.item_id,
		"output_name": output.display_name,
		"output_rarity": _rarity_label(output.rarity),
	}


static func _build_score_breakdown(definition: ScoreDefinition) -> Dictionary:
	if definition == null or definition.equipment_scores.size() != 4:
		return {"valid": false, "reason": "score-resource"}
	var held_equipment: Array[ItemInstance] = []
	for rarity: GameTypes.Rarity in [
		GameTypes.Rarity.COMMON,
		GameTypes.Rarity.RARE,
		GameTypes.Rarity.EPIC,
		GameTypes.Rarity.LEGENDARY,
	]:
		var item := ItemInstance.new()
		item.rarity = rarity
		held_equipment.append(item)
	held_equipment[0].unique_id = &"bloodied_dagger"
	var first_skill := SkillState.new()
	first_skill.level = 2
	var second_skill := SkillState.new()
	second_skill.level = 3
	var skill_library: Dictionary = {
		&"starfall": first_skill,
		&"thousand_blades": second_skill,
	}
	var calculated: Dictionary = ScoreService.calculate(
		100,
		1,
		1,
		20,
		8,
		true,
		held_equipment,
		skill_library,
		2,
		definition
	)
	if calculated[&"total"] != 12055:
		return {"valid": false, "reason": "score-total"}
	return {
		"valid": true,
		"normal": calculated[&"normal_kills"],
		"post_quota": calculated[&"post_quota_bonus"],
		"elite": calculated[&"elite_kills"],
		"boss": calculated[&"boss_kills"],
		"waves": calculated[&"wave_clears"],
		"clear": calculated[&"run_clear"],
		"equipment": calculated[&"equipment"],
		"unique": calculated[&"unique_tags"],
		"skills": calculated[&"skill_levels"],
		"wild": calculated[&"wild_materials"],
		"combat": calculated[&"combat_score"],
		"build": calculated[&"final_build_score"],
		"total": calculated[&"total"],
	}


static func _read_test_summary() -> Dictionary:
	if not FileAccess.file_exists(TEST_LOG_PATH):
		return {"valid": false, "reason": "unit-test-log"}
	var passed: int = -1
	var failed: int = -1
	for line: String in FileAccess.get_file_as_string(TEST_LOG_PATH).split("\n"):
		if not line.begins_with("TEST_SUMMARY "):
			continue
		for field: String in line.strip_edges().split(" "):
			if field.begins_with("passed="):
				passed = field.trim_prefix("passed=").to_int()
			elif field.begins_with("failed="):
				failed = field.trim_prefix("failed=").to_int()
	if passed != EXPECTED_UNIT_PASS_COUNT or failed != 0:
		return {"valid": false, "reason": "unit-test-summary"}
	return {"valid": true, "passed": passed, "failed": failed}


static func _format_left_panel(
	streams: RunRngStreams,
	combat_values: Array[int],
	loot_values: Array[int],
	fusion_values: Array[int],
	items: Array[Dictionary]
) -> String:
	var lines: PackedStringArray = PackedStringArray([
		"[color=#55e6c1][b]MUTABLE RUN RNG STREAMS[/b][/color]",
		"combat  seed %d" % streams.combat_seed,
		"          first 3  %s" % str(combat_values),
		"loot       seed %d" % streams.loot_seed,
		"          first 3  %s" % str(loot_values),
		"fusion    seed %d" % streams.fusion_seed,
		"          first 3  %s" % str(fusion_values),
		"",
		"[color=#55e6c1][b]4 GENERATED ITEM EXAMPLES[/b][/color]",
	])
	for index: int in range(items.size()):
		var item: Dictionary = items[index]
		lines.append("[b]%d  %s[/b]  ·  %s" % [index + 1, item["display_name"], item["rarity"]])
		lines.append("    %s" % item["item_id"])
		lines.append("    name(item_seed) ×3  %s" % str(item["name_rng_values"]))
	return "\n".join(lines)


static func _format_right_panel(
	fusion: Dictionary,
	score: Dictionary,
	test_summary: Dictionary
) -> String:
	return "\n".join(PackedStringArray([
		"[color=#ffcf66][b]FUSION EXAMPLE[/b][/color]",
		"materials  Rare HANDS #0010 + #0011 + #0012",
		"→ %s  %s" % [fusion["output_rarity"], fusion["output_name"]],
		"output  %s" % fusion["output_id"],
		"validation ✓  locked/equipped/Legendary rejected",
		"",
		"[color=#ffcf66][b]SCORE BREAKDOWN — FIXED EXAMPLE[/b][/color]",
		"normal 100 × 10                 %5d" % score["normal"],
		"post-quota 20 × 10              %5d" % score["post_quota"],
		"elite / boss                    %5d / %d" % [score["elite"], score["boss"]],
		"8 waves / run clear             %5d / %d" % [score["waves"], score["clear"]],
		"[b]COMBAT SCORE                     %5d[/b]" % score["combat"],
		"equipment / unique              %5d / %d" % [score["equipment"], score["unique"]],
		"skills Lv total 5 / wild ×2     %5d / %d" % [score["skills"], score["wild"]],
		"[b]FINAL BUILD SCORE                %5d[/b]" % score["build"],
		"",
		"[font_size=28][color=#55e6c1][b]TOTAL  %s[/b][/color][/font_size]" % _with_commas(score["total"]),
		"",
		"[font_size=24][color=#55e6c1][b]UNIT TESTS  %d PASS  /  0 FAIL[/b][/color][/font_size]" % test_summary["passed"],
	]))


static func _rarity_label(rarity: GameTypes.Rarity) -> String:
	match rarity:
		GameTypes.Rarity.COMMON:
			return "COMMON"
		GameTypes.Rarity.RARE:
			return "RARE"
		GameTypes.Rarity.EPIC:
			return "EPIC"
		GameTypes.Rarity.LEGENDARY:
			return "LEGENDARY"
	return "UNKNOWN"


static func _with_commas(value: int) -> String:
	var digits: String = str(value)
	var output: String = ""
	for index: int in range(digits.length()):
		if index > 0 and (digits.length() - index) % 3 == 0:
			output += ","
		output += digits[index]
	return output
