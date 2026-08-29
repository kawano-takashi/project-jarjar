class_name DefinitionCatalog
extends RefCounted


const Types := preload("res://src/core/game_types.gd")

const WEAPON_PATHS: Array[String] = [
	"res://data/definitions/weapons/wood_stick.tres",
	"res://data/definitions/weapons/bow.tres",
	"res://data/definitions/weapons/staff.tres",
	"res://data/definitions/weapons/sword.tres",
]
const ENEMY_PATHS: Array[String] = [
	"res://data/definitions/enemies/tracker.tres",
	"res://data/definitions/enemies/fast.tres",
	"res://data/definitions/enemies/armored.tres",
	"res://data/definitions/enemies/ranged.tres",
	"res://data/definitions/enemies/elite.tres",
	"res://data/definitions/enemies/boss.tres",
]
const WAVE_PATHS: Array[String] = [
	"res://data/definitions/waves/wave_01.tres",
	"res://data/definitions/waves/wave_02.tres",
	"res://data/definitions/waves/wave_03.tres",
	"res://data/definitions/waves/wave_04.tres",
	"res://data/definitions/waves/wave_05.tres",
	"res://data/definitions/waves/wave_06.tres",
	"res://data/definitions/waves/wave_07.tres",
	"res://data/definitions/waves/wave_08.tres",
]
const RARITY_PATHS: Array[String] = [
	"res://data/definitions/rarities/common.tres",
	"res://data/definitions/rarities/rare.tres",
	"res://data/definitions/rarities/epic.tres",
	"res://data/definitions/rarities/legendary.tres",
]
const AFFIX_PATHS: Array[String] = [
	"res://data/definitions/affixes/damage_pct.tres",
	"res://data/definitions/affixes/attack_speed_pct.tres",
	"res://data/definitions/affixes/cooldown_reduction_pct.tres",
	"res://data/definitions/affixes/area_pct.tres",
	"res://data/definitions/affixes/pierce.tres",
	"res://data/definitions/affixes/max_hp.tres",
	"res://data/definitions/affixes/damage_reduction_pct.tres",
	"res://data/definitions/affixes/move_speed_pct.tres",
	"res://data/definitions/affixes/skill_power_pct.tres",
]
const SKILL_PATHS: Array[String] = [
	"res://data/definitions/skills/starfall.tres",
	"res://data/definitions/skills/thousand_blades.tres",
	"res://data/definitions/skills/soul_chain.tres",
	"res://data/definitions/skills/bell_of_retribution.tres",
]
const UNIQUE_PATHS: Array[String] = [
	"res://data/definitions/uniques/bloodied_dagger.tres",
	"res://data/definitions/uniques/broken_clock.tres",
	"res://data/definitions/uniques/coward_boots.tres",
	"res://data/definitions/uniques/immortal_breastplate.tres",
	"res://data/definitions/uniques/echo_gauntlet.tres",
	"res://data/definitions/uniques/hollow_crown.tres",
]
const SCORE_PATH := "res://data/definitions/score.tres"
const BALANCE_MANIFEST_PATH := "res://data/balance/balance_manifest.tres"
const WEIGHT_SUM_TOLERANCE := 0.000001

var weapons: Dictionary[StringName, WeaponDefinition] = {}
var enemies: Dictionary[StringName, EnemyDefinition] = {}
var waves: Dictionary[int, WaveDefinition] = {}
var rarities: Dictionary[int, RarityDefinition] = {}
var affixes: Dictionary[StringName, AffixDefinition] = {}
var skills: Dictionary[StringName, SkillDefinition] = {}
var uniques: Dictionary[StringName, UniqueDefinition] = {}
var is_valid: bool = false
var error_text: String = ""
var validation_errors: PackedStringArray = PackedStringArray()

var _score_definition: ScoreDefinition
var _balance_manifest: BalanceManifest


func load_and_validate() -> bool:
	_reset()
	_load_weapons()
	_load_enemies()
	_load_waves()
	_load_rarities()
	_load_affixes()
	_load_skills()
	_load_uniques()
	_load_score()
	_load_balance_manifest()
	_validate_catalog_shape()
	is_valid = validation_errors.is_empty()
	error_text = "\n".join(validation_errors)
	return is_valid


func weapon(weapon_id: StringName) -> WeaponDefinition:
	return weapons.get(weapon_id) as WeaponDefinition


func enemy(enemy_id: StringName) -> EnemyDefinition:
	return enemies.get(enemy_id) as EnemyDefinition


func wave(wave_number: int) -> WaveDefinition:
	return waves.get(wave_number) as WaveDefinition


func rarity(rarity_value: Types.Rarity) -> RarityDefinition:
	return rarities.get(rarity_value) as RarityDefinition


func affix(affix_id: StringName) -> AffixDefinition:
	return affixes.get(affix_id) as AffixDefinition


func skill(skill_id: StringName) -> SkillDefinition:
	return skills.get(skill_id) as SkillDefinition


func unique(unique_id: StringName) -> UniqueDefinition:
	return uniques.get(unique_id) as UniqueDefinition


func score_definition() -> ScoreDefinition:
	return _score_definition


func balance_manifest() -> BalanceManifest:
	return _balance_manifest


func affix_ids_for_slot(slot: Types.EquipmentSlot) -> Array[StringName]:
	var result: Array[StringName] = []
	for affix_id: StringName in affixes:
		var definition: AffixDefinition = affixes[affix_id]
		if definition.slot_pool.has(slot):
			result.append(affix_id)
	result.sort_custom(_string_name_ordinal_less)
	return result


func common_affix_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for affix_id: StringName in affixes:
		if affixes[affix_id].in_common_pool:
			result.append(affix_id)
	result.sort_custom(_string_name_ordinal_less)
	return result


func unique_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for unique_id: StringName in uniques:
		result.append(unique_id)
	result.sort_custom(_string_name_ordinal_less)
	return result


func _reset() -> void:
	weapons.clear()
	enemies.clear()
	waves.clear()
	rarities.clear()
	affixes.clear()
	skills.clear()
	uniques.clear()
	_score_definition = null
	_balance_manifest = null
	is_valid = false
	error_text = ""
	validation_errors.clear()


func _load_weapons() -> void:
	var seen_types: Dictionary[int, bool] = {}
	for path: String in WEAPON_PATHS:
		var loaded: Resource = ResourceLoader.load(path)
		if loaded == null:
			_add_error("Missing WeaponDefinition: %s" % path)
			continue
		if not (loaded is WeaponDefinition):
			_add_error("Wrong resource type for %s; expected WeaponDefinition" % path)
			continue
		var definition: WeaponDefinition = loaded as WeaponDefinition
		var expected_id := StringName(path.get_file().get_basename())
		_validate_id(definition.weapon_id, expected_id, path)
		if weapons.has(definition.weapon_id):
			_add_error("Duplicate weapon_id: %s" % definition.weapon_id)
		else:
			weapons[definition.weapon_id] = definition
		_validate_enum_value(
			definition.main_weapon_type,
			Types.MainWeaponType.size(),
			"main_weapon_type",
			path
		)
		if seen_types.has(definition.main_weapon_type):
			_add_error("Duplicate main_weapon_type in WeaponDefinition: %s" % path)
		seen_types[definition.main_weapon_type] = true
		_validate_positive_float(definition.base_damage, "base_damage", path)
		_validate_positive_float(definition.base_interval, "base_interval", path)
		_validate_positive_float(definition.range_m, "range_m", path)
		_validate_non_negative_float(definition.projectile_speed, "projectile_speed", path)
		_validate_non_negative_float(definition.projectile_radius, "projectile_radius", path)
		_validate_non_negative_float(definition.aoe_radius, "aoe_radius", path)
		_validate_non_negative_float(definition.arc_degrees, "arc_degrees", path)


func _load_enemies() -> void:
	for path: String in ENEMY_PATHS:
		var loaded: Resource = ResourceLoader.load(path)
		if loaded == null:
			_add_error("Missing EnemyDefinition: %s" % path)
			continue
		if not (loaded is EnemyDefinition):
			_add_error("Wrong resource type for %s; expected EnemyDefinition" % path)
			continue
		var definition: EnemyDefinition = loaded as EnemyDefinition
		var expected_id := StringName(path.get_file().get_basename())
		_validate_id(definition.enemy_id, expected_id, path)
		if enemies.has(definition.enemy_id):
			_add_error("Duplicate enemy_id: %s" % definition.enemy_id)
		else:
			enemies[definition.enemy_id] = definition
		_validate_positive_float(definition.base_hp, "base_hp", path)
		_validate_positive_float(definition.move_speed, "move_speed", path)
		_validate_positive_float(definition.body_radius, "body_radius", path)
		_validate_positive_float(definition.contact_interval, "contact_interval", path)
		_validate_non_negative_float(definition.contact_damage, "contact_damage", path)
		_validate_non_negative_float(
			definition.preferred_distance_min,
			"preferred_distance_min",
			path
		)
		_validate_non_negative_float(
			definition.preferred_distance_max,
			"preferred_distance_max",
			path
		)
		if definition.preferred_distance_min > definition.preferred_distance_max:
			_add_error("preferred distance range is reversed: %s" % path)
		_validate_non_negative_float(definition.special_interval, "special_interval", path)
		_validate_non_negative_float(definition.telegraph_seconds, "telegraph_seconds", path)
		_validate_non_negative_float(definition.area_radius, "area_radius", path)
		_validate_non_negative_float(definition.projectile_damage, "projectile_damage", path)
		_validate_non_negative_float(definition.projectile_speed, "projectile_speed", path)
		_validate_non_negative_float(definition.projectile_radius, "projectile_radius", path)
		_validate_non_negative_float(definition.projectile_lifetime, "projectile_lifetime", path)
		_validate_non_negative_int(definition.volley_count, "volley_count", path)
		_validate_non_negative_float(definition.summon_interval, "summon_interval", path)
		_validate_non_negative_int(definition.summon_count, "summon_count", path)


func _load_waves() -> void:
	for index: int in WAVE_PATHS.size():
		var path: String = WAVE_PATHS[index]
		var loaded: Resource = ResourceLoader.load(path)
		if loaded == null:
			_add_error("Missing WaveDefinition: %s" % path)
			continue
		if not (loaded is WaveDefinition):
			_add_error("Wrong resource type for %s; expected WaveDefinition" % path)
			continue
		var definition: WaveDefinition = loaded as WaveDefinition
		var expected_wave_number := index + 1
		if definition.wave_number != expected_wave_number:
			_add_error("wave_number does not match fixed path: %s" % path)
		if waves.has(definition.wave_number):
			_add_error("Duplicate wave_number: %d" % definition.wave_number)
		else:
			waves[definition.wave_number] = definition
		_validate_positive_float(definition.duration_seconds, "duration_seconds", path)
		_validate_non_negative_int(definition.kill_quota, "kill_quota", path)
		_validate_weights(
			definition.enemy_weights,
			[
				Types.EnemyType.TRACKER,
				Types.EnemyType.FAST,
				Types.EnemyType.ARMORED,
				Types.EnemyType.RANGED,
			],
			"enemy_weights",
			path
		)
		_validate_positive_float(definition.hp_multiplier, "hp_multiplier", path)
		_validate_positive_float(definition.damage_multiplier, "damage_multiplier", path)
		_validate_non_negative_float(definition.spawn_rate_start, "spawn_rate_start", path)
		_validate_non_negative_float(definition.spawn_rate_end, "spawn_rate_end", path)
		_validate_probability(definition.normal_chest_rate, "normal_chest_rate", path)
		_validate_weights(
			definition.rarity_weights,
			[
				Types.Rarity.COMMON,
				Types.Rarity.RARE,
				Types.Rarity.EPIC,
				Types.Rarity.LEGENDARY,
			],
			"rarity_weights",
			path
		)
		_validate_elite_elapsed(definition.elite_spawn_elapsed, path)


func _load_rarities() -> void:
	for index: int in RARITY_PATHS.size():
		var path: String = RARITY_PATHS[index]
		var loaded: Resource = ResourceLoader.load(path)
		if loaded == null:
			_add_error("Missing RarityDefinition: %s" % path)
			continue
		if not (loaded is RarityDefinition):
			_add_error("Wrong resource type for %s; expected RarityDefinition" % path)
			continue
		var definition: RarityDefinition = loaded as RarityDefinition
		_validate_enum_value(definition.rarity, Types.Rarity.size(), "rarity", path)
		if definition.rarity != index:
			_add_error("rarity does not match fixed path: %s" % path)
		if rarities.has(definition.rarity):
			_add_error("Duplicate rarity: %d" % definition.rarity)
		else:
			rarities[definition.rarity] = definition
		_validate_non_negative_int(definition.affix_count, "affix_count", path)


func _load_affixes() -> void:
	for path: String in AFFIX_PATHS:
		var loaded: Resource = ResourceLoader.load(path)
		if loaded == null:
			_add_error("Missing AffixDefinition: %s" % path)
			continue
		if not (loaded is AffixDefinition):
			_add_error("Wrong resource type for %s; expected AffixDefinition" % path)
			continue
		var definition: AffixDefinition = loaded as AffixDefinition
		var expected_id := StringName(path.get_file().get_basename())
		_validate_id(definition.affix_id, expected_id, path)
		if affixes.has(definition.affix_id):
			_add_error("Duplicate affix_id: %s" % definition.affix_id)
		else:
			affixes[definition.affix_id] = definition
		_validate_float_array(definition.values_by_rarity, RARITY_PATHS.size(), "values_by_rarity", path)
		if definition.slot_pool.is_empty():
			_add_error("slot_pool must not be empty: %s" % path)
		_validate_enum_array(
			definition.slot_pool,
			Types.EquipmentSlot.size(),
			"slot_pool",
			path,
			true
		)
		_validate_enum_array(
			definition.affinity_weapon_types,
			Types.MainWeaponType.size(),
			"affinity_weapon_types",
			path,
			false
		)


func _load_skills() -> void:
	var seen_trigger_types: Dictionary[int, bool] = {}
	for path: String in SKILL_PATHS:
		var loaded: Resource = ResourceLoader.load(path)
		if loaded == null:
			_add_error("Missing SkillDefinition: %s" % path)
			continue
		if not (loaded is SkillDefinition):
			_add_error("Wrong resource type for %s; expected SkillDefinition" % path)
			continue
		var definition: SkillDefinition = loaded as SkillDefinition
		var expected_id := StringName(path.get_file().get_basename())
		_validate_id(definition.skill_id, expected_id, path)
		if skills.has(definition.skill_id):
			_add_error("Duplicate skill_id: %s" % definition.skill_id)
		else:
			skills[definition.skill_id] = definition
		_validate_enum_value(definition.trigger_type, Types.TriggerType.size(), "trigger_type", path)
		if seen_trigger_types.has(definition.trigger_type):
			_add_error("Duplicate trigger_type in SkillDefinition: %s" % path)
		seen_trigger_types[definition.trigger_type] = true
		_validate_positive_float(definition.base_threshold, "base_threshold", path)
		_validate_float_array(definition.damage_by_level, 3, "damage_by_level", path)
		_validate_float_array(definition.radius_by_level, 3, "radius_by_level", path)
		_validate_int_array(definition.target_count_by_level, 3, "target_count_by_level", path)


func _load_uniques() -> void:
	for path: String in UNIQUE_PATHS:
		var loaded: Resource = ResourceLoader.load(path)
		if loaded == null:
			_add_error("Missing UniqueDefinition: %s" % path)
			continue
		if not (loaded is UniqueDefinition):
			_add_error("Wrong resource type for %s; expected UniqueDefinition" % path)
			continue
		var definition: UniqueDefinition = loaded as UniqueDefinition
		var expected_id := StringName(path.get_file().get_basename())
		_validate_id(definition.unique_id, expected_id, path)
		if uniques.has(definition.unique_id):
			_add_error("Duplicate unique_id: %s" % definition.unique_id)
		else:
			uniques[definition.unique_id] = definition
		if definition.display_name.is_empty():
			_add_error("display_name must not be empty: %s" % path)
		if definition.effect_description.strip_edges().is_empty():
			_add_error("effect_description must not be empty: %s" % path)
		_validate_enum_value(
			definition.equipment_slot,
			Types.EquipmentSlot.size(),
			"equipment_slot",
			path
		)


func _load_score() -> void:
	var loaded: Resource = ResourceLoader.load(SCORE_PATH)
	if loaded == null:
		_add_error("Missing ScoreDefinition: %s" % SCORE_PATH)
		return
	if not (loaded is ScoreDefinition):
		_add_error("Wrong resource type for %s; expected ScoreDefinition" % SCORE_PATH)
		return
	_score_definition = loaded as ScoreDefinition
	_validate_non_negative_int(_score_definition.normal_kill, "normal_kill", SCORE_PATH)
	_validate_non_negative_int(
		_score_definition.post_quota_bonus,
		"post_quota_bonus",
		SCORE_PATH
	)
	_validate_non_negative_int(_score_definition.elite_kill, "elite_kill", SCORE_PATH)
	_validate_non_negative_int(_score_definition.boss_kill, "boss_kill", SCORE_PATH)
	_validate_non_negative_int(_score_definition.wave_clear, "wave_clear", SCORE_PATH)
	_validate_non_negative_int(_score_definition.run_clear, "run_clear", SCORE_PATH)
	_validate_int_array(
		_score_definition.equipment_scores,
		RARITY_PATHS.size(),
		"equipment_scores",
		SCORE_PATH
	)
	_validate_non_negative_int(_score_definition.unique_tag, "unique_tag", SCORE_PATH)
	_validate_non_negative_int(_score_definition.skill_level, "skill_level", SCORE_PATH)
	_validate_non_negative_int(_score_definition.wild_material, "wild_material", SCORE_PATH)


func _load_balance_manifest() -> void:
	var loaded: Resource = ResourceLoader.load(BALANCE_MANIFEST_PATH)
	if loaded == null:
		_add_error("Missing BalanceManifest: %s" % BALANCE_MANIFEST_PATH)
		return
	if not (loaded is BalanceManifest):
		_add_error("Wrong resource type for %s; expected BalanceManifest" % BALANCE_MANIFEST_PATH)
		return
	_balance_manifest = loaded as BalanceManifest
	_validate_non_negative_int(
		_balance_manifest.balance_revision,
		"balance_revision",
		BALANCE_MANIFEST_PATH
	)


func _validate_catalog_shape() -> void:
	_validate_count(weapons.size(), WEAPON_PATHS.size(), "WeaponDefinition")
	_validate_count(enemies.size(), ENEMY_PATHS.size(), "EnemyDefinition")
	_validate_count(waves.size(), WAVE_PATHS.size(), "WaveDefinition")
	_validate_count(rarities.size(), RARITY_PATHS.size(), "RarityDefinition")
	_validate_count(affixes.size(), AFFIX_PATHS.size(), "AffixDefinition")
	_validate_count(skills.size(), SKILL_PATHS.size(), "SkillDefinition")
	_validate_count(uniques.size(), UNIQUE_PATHS.size(), "UniqueDefinition")
	var common_count := 0
	for definition: AffixDefinition in affixes.values():
		if definition.in_common_pool:
			common_count += 1
	if common_count != AFFIX_PATHS.size() - 1:
		_add_error("Common affix pool count does not match the fixed table")
	var elite_wave_count := 0
	var boss_wave_count := 0
	for definition: WaveDefinition in waves.values():
		if definition.elite_spawn_elapsed >= 0.0:
			elite_wave_count += 1
		if definition.boss_at_start:
			boss_wave_count += 1
	if elite_wave_count != 1:
		_add_error("Elite wave count does not match the fixed table")
	if boss_wave_count != 1:
		_add_error("Boss wave count does not match the fixed table")


func _validate_id(actual: StringName, expected: StringName, path: String) -> void:
	if actual.is_empty():
		_add_error("Definition ID must not be empty: %s" % path)
	elif actual != expected:
		_add_error("Definition ID does not match fixed path: %s" % path)


func _validate_count(actual: int, expected: int, resource_type: String) -> void:
	if actual != expected:
		_add_error("%s count mismatch: expected %d, got %d" % [resource_type, expected, actual])


func _validate_positive_float(value: float, field_name: String, path: String) -> void:
	if not is_finite(value) or value <= 0.0:
		_add_error("%s must be finite and positive: %s" % [field_name, path])


func _validate_non_negative_float(value: float, field_name: String, path: String) -> void:
	if not is_finite(value) or value < 0.0:
		_add_error("%s must be finite and non-negative: %s" % [field_name, path])


func _validate_non_negative_int(value: int, field_name: String, path: String) -> void:
	if value < 0:
		_add_error("%s must be non-negative: %s" % [field_name, path])


func _validate_probability(value: float, field_name: String, path: String) -> void:
	if not is_finite(value) or value < 0.0 or value > 1.0:
		_add_error("%s must be a finite probability: %s" % [field_name, path])


func _validate_elite_elapsed(value: float, path: String) -> void:
	if not is_finite(value) or (value < 0.0 and value != -1.0):
		_add_error("elite_spawn_elapsed must be -1 or non-negative: %s" % path)


func _validate_enum_value(value: int, enum_size: int, field_name: String, path: String) -> void:
	if value < 0 or value >= enum_size:
		_add_error("%s is outside its enum: %s" % [field_name, path])


func _validate_enum_array(
	values: Array,
	enum_size: int,
	field_name: String,
	path: String,
	allow_zero: bool
) -> void:
	var seen: Dictionary[int, bool] = {}
	for value: int in values:
		_validate_enum_value(value, enum_size, field_name, path)
		if not allow_zero and value == 0:
			_add_error("%s must not contain UNCLASSIFIED: %s" % [field_name, path])
		if seen.has(value):
			_add_error("%s contains a duplicate enum value: %s" % [field_name, path])
		seen[value] = true


func _validate_float_array(
	values: PackedFloat32Array,
	expected_size: int,
	field_name: String,
	path: String
) -> void:
	if values.size() != expected_size:
		_add_error("%s length mismatch: %s" % [field_name, path])
	for value: float in values:
		_validate_non_negative_float(value, field_name, path)


func _validate_int_array(
	values: PackedInt32Array,
	expected_size: int,
	field_name: String,
	path: String
) -> void:
	if values.size() != expected_size:
		_add_error("%s length mismatch: %s" % [field_name, path])
	for value: int in values:
		_validate_non_negative_int(value, field_name, path)


func _validate_weights(
	weights: Dictionary,
	expected_keys: Array[int],
	field_name: String,
	path: String
) -> void:
	if weights.size() != expected_keys.size():
		_add_error("%s key count mismatch: %s" % [field_name, path])
	var total := 0.0
	for key: int in expected_keys:
		if not weights.has(key):
			_add_error("%s is missing enum key %d: %s" % [field_name, key, path])
			continue
		var raw_value: Variant = weights[key]
		if typeof(raw_value) != TYPE_FLOAT and typeof(raw_value) != TYPE_INT:
			_add_error("%s contains a non-numeric weight: %s" % [field_name, path])
			continue
		var value := float(raw_value)
		_validate_non_negative_float(value, field_name, path)
		total += value
	if not is_finite(total) or absf(total - 1.0) > WEIGHT_SUM_TOLERANCE:
		_add_error("%s must sum to 1: %s" % [field_name, path])


func _add_error(message: String) -> void:
	validation_errors.append(message)


func _string_name_ordinal_less(left: StringName, right: StringName) -> bool:
	return String(left) < String(right)
