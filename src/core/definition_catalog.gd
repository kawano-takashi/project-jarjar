class_name DefinitionCatalog
extends RefCounted


const Types := preload("res://src/core/game_types.gd")

const WEAPON_PATHS: PackedStringArray = [
	"res://data/definitions/weapons/wood_stick.tres",
	"res://data/definitions/weapons/bow.tres",
	"res://data/definitions/weapons/staff.tres",
	"res://data/definitions/weapons/sword.tres",
]
const ENEMY_PATHS: PackedStringArray = [
	"res://data/definitions/enemies/tracker.tres",
	"res://data/definitions/enemies/fast.tres",
	"res://data/definitions/enemies/armored.tres",
	"res://data/definitions/enemies/ranged.tres",
	"res://data/definitions/enemies/elite.tres",
	"res://data/definitions/enemies/boss.tres",
]
const WAVE_PATHS: PackedStringArray = [
	"res://data/definitions/waves/wave_01.tres",
	"res://data/definitions/waves/wave_02.tres",
	"res://data/definitions/waves/wave_03.tres",
	"res://data/definitions/waves/wave_04.tres",
	"res://data/definitions/waves/wave_05.tres",
	"res://data/definitions/waves/wave_06.tres",
	"res://data/definitions/waves/wave_07.tres",
	"res://data/definitions/waves/wave_08.tres",
]
const RARITY_PATHS: PackedStringArray = [
	"res://data/definitions/rarities/common.tres",
	"res://data/definitions/rarities/rare.tres",
	"res://data/definitions/rarities/epic.tres",
	"res://data/definitions/rarities/legendary.tres",
]
const AFFIX_PATHS: PackedStringArray = [
	"res://data/definitions/affixes/damage_pct.tres",
	"res://data/definitions/affixes/attack_speed_pct.tres",
	"res://data/definitions/affixes/area_pct.tres",
	"res://data/definitions/affixes/pierce.tres",
	"res://data/definitions/affixes/max_hp.tres",
	"res://data/definitions/affixes/damage_reduction_pct.tres",
	"res://data/definitions/affixes/move_speed_pct.tres",
]
const SCORE_PATH: String = "res://data/definitions/score.tres"
const BALANCE_MANIFEST_PATH: String = "res://data/balance/balance_manifest.tres"
const NORMAL_RARITY_COUNT: int = 4
const WEIGHT_SUM_TOLERANCE: float = 0.000001

var weapons: Dictionary[StringName, WeaponDefinition] = {}
var enemies: Dictionary[StringName, EnemyDefinition] = {}
var waves: Dictionary[int, WaveDefinition] = {}
var rarities: Dictionary[int, RarityDefinition] = {}
var affixes: Dictionary[StringName, AffixDefinition] = {}
var is_valid: bool = false
var error_text: String = ""
var validation_errors: PackedStringArray = PackedStringArray()

var _weapons_by_type: Dictionary[int, WeaponDefinition] = {}
var _score_definition: ScoreDefinition = null
var _balance_manifest: BalanceManifest = null


func load_and_validate() -> bool:
	_reset()
	_load_weapons()
	_load_enemies()
	_load_waves()
	_load_rarities()
	_load_affixes()
	_load_score()
	_load_balance_manifest()
	_validate_catalog_shape()
	is_valid = validation_errors.is_empty()
	error_text = "\n".join(validation_errors)
	return is_valid


func weapon(weapon_id: StringName) -> WeaponDefinition:
	return weapons.get(weapon_id) as WeaponDefinition


func weapon_for_type(weapon_type: Types.WeaponType) -> WeaponDefinition:
	return _weapons_by_type.get(int(weapon_type)) as WeaponDefinition


func enemy(enemy_id: StringName) -> EnemyDefinition:
	return enemies.get(enemy_id) as EnemyDefinition


func wave(wave_number: int) -> WaveDefinition:
	return waves.get(wave_number) as WaveDefinition


func rarity(rarity_value: Types.Rarity) -> RarityDefinition:
	return rarities.get(int(rarity_value)) as RarityDefinition


func affix(affix_id: StringName) -> AffixDefinition:
	return affixes.get(affix_id) as AffixDefinition


func affix_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for affix_id: StringName in affixes:
		result.append(affix_id)
	result.sort_custom(_string_name_ordinal_less)
	return result


func score_definition() -> ScoreDefinition:
	return _score_definition


func balance_manifest() -> BalanceManifest:
	return _balance_manifest


func _reset() -> void:
	weapons.clear()
	_weapons_by_type.clear()
	enemies.clear()
	waves.clear()
	rarities.clear()
	affixes.clear()
	_score_definition = null
	_balance_manifest = null
	is_valid = false
	error_text = ""
	validation_errors.clear()


func _load_weapons() -> void:
	for path: String in WEAPON_PATHS:
		var loaded: Resource = ResourceLoader.load(path)
		if not loaded is WeaponDefinition:
			_add_error("Missing or invalid WeaponDefinition: %s" % path)
			continue
		var definition := loaded as WeaponDefinition
		_validate_id(definition.weapon_id, StringName(path.get_file().get_basename()), path)
		if weapons.has(definition.weapon_id):
			_add_error("Duplicate weapon_id: %s" % definition.weapon_id)
		else:
			weapons[definition.weapon_id] = definition
		if definition.weapon_type <= Types.WeaponType.NONE or definition.weapon_type >= Types.WeaponType.size():
			_add_error("Invalid weapon_type: %s" % path)
		elif _weapons_by_type.has(int(definition.weapon_type)):
			_add_error("Duplicate weapon_type: %s" % path)
		else:
			_weapons_by_type[int(definition.weapon_type)] = definition
		_validate_float_array(definition.damage_by_rarity, NORMAL_RARITY_COUNT, "damage_by_rarity", path, true)
		_validate_positive_float(definition.base_interval, "base_interval", path)
		_validate_positive_float(definition.range_m, "range_m", path)
		_validate_non_negative_float(definition.projectile_speed, "projectile_speed", path)
		_validate_non_negative_float(definition.projectile_radius, "projectile_radius", path)
		_validate_non_negative_float(definition.aoe_radius, "aoe_radius", path)
		_validate_non_negative_float(definition.arc_degrees, "arc_degrees", path)
		if definition.weapon_type == Types.WeaponType.WOOD_STICK and definition.lootable:
			_add_error("Wood stick must be starter-only: %s" % path)
		if definition.weapon_type != Types.WeaponType.WOOD_STICK and not definition.lootable:
			_add_error("Regular weapon must be lootable: %s" % path)


func _load_enemies() -> void:
	for path: String in ENEMY_PATHS:
		var loaded: Resource = ResourceLoader.load(path)
		if not loaded is EnemyDefinition:
			_add_error("Missing or invalid EnemyDefinition: %s" % path)
			continue
		var definition := loaded as EnemyDefinition
		_validate_id(definition.enemy_id, StringName(path.get_file().get_basename()), path)
		if enemies.has(definition.enemy_id):
			_add_error("Duplicate enemy_id: %s" % definition.enemy_id)
		else:
			enemies[definition.enemy_id] = definition
		_validate_positive_float(definition.base_hp, "base_hp", path)
		_validate_positive_float(definition.move_speed, "move_speed", path)
		_validate_positive_float(definition.body_radius, "body_radius", path)
		_validate_positive_float(definition.contact_interval, "contact_interval", path)
		_validate_non_negative_float(definition.contact_damage, "contact_damage", path)
		_validate_non_negative_float(definition.preferred_distance_min, "preferred_distance_min", path)
		_validate_non_negative_float(definition.preferred_distance_max, "preferred_distance_max", path)
		if definition.preferred_distance_min > definition.preferred_distance_max:
			_add_error("Preferred distance range is reversed: %s" % path)
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
	for index: int in range(WAVE_PATHS.size()):
		var path: String = WAVE_PATHS[index]
		var loaded: Resource = ResourceLoader.load(path)
		if not loaded is WaveDefinition:
			_add_error("Missing or invalid WaveDefinition: %s" % path)
			continue
		var definition := loaded as WaveDefinition
		if definition.wave_number != index + 1:
			_add_error("wave_number does not match fixed path: %s" % path)
		elif waves.has(definition.wave_number):
			_add_error("Duplicate wave_number: %d" % definition.wave_number)
		else:
			waves[definition.wave_number] = definition
		_validate_positive_float(definition.duration_seconds, "duration_seconds", path)
		_validate_non_negative_int(definition.kill_quota, "kill_quota", path)
		_validate_weights(definition.enemy_weights, [
			Types.EnemyType.TRACKER,
			Types.EnemyType.FAST,
			Types.EnemyType.ARMORED,
			Types.EnemyType.RANGED,
		], "enemy_weights", path)
		_validate_positive_float(definition.hp_multiplier, "hp_multiplier", path)
		_validate_positive_float(definition.damage_multiplier, "damage_multiplier", path)
		_validate_non_negative_float(definition.spawn_rate_start, "spawn_rate_start", path)
		_validate_non_negative_float(definition.spawn_rate_end, "spawn_rate_end", path)
		_validate_probability(definition.normal_chest_rate, "normal_chest_rate", path)
		_validate_weights(definition.rarity_weights, [
			Types.Rarity.COMMON,
			Types.Rarity.RARE,
			Types.Rarity.EPIC,
			Types.Rarity.LEGENDARY,
		], "rarity_weights", path)
		if not is_finite(definition.elite_spawn_elapsed) or (
			definition.elite_spawn_elapsed < 0.0 and definition.elite_spawn_elapsed != -1.0
		):
			_add_error("elite_spawn_elapsed must be -1 or non-negative: %s" % path)


func _load_rarities() -> void:
	for index: int in range(RARITY_PATHS.size()):
		var path: String = RARITY_PATHS[index]
		var loaded: Resource = ResourceLoader.load(path)
		if not loaded is RarityDefinition:
			_add_error("Missing or invalid RarityDefinition: %s" % path)
			continue
		var definition := loaded as RarityDefinition
		if int(definition.rarity) != index:
			_add_error("rarity does not match fixed path: %s" % path)
		elif rarities.has(index):
			_add_error("Duplicate rarity: %d" % index)
		else:
			rarities[index] = definition
		if definition.affix_count != index + 1:
			_add_error("affix_count must be rarity index + 1: %s" % path)


func _load_affixes() -> void:
	for path: String in AFFIX_PATHS:
		var loaded: Resource = ResourceLoader.load(path)
		if not loaded is AffixDefinition:
			_add_error("Missing or invalid AffixDefinition: %s" % path)
			continue
		var definition := loaded as AffixDefinition
		_validate_id(definition.affix_id, StringName(path.get_file().get_basename()), path)
		if affixes.has(definition.affix_id):
			_add_error("Duplicate affix_id: %s" % definition.affix_id)
		else:
			affixes[definition.affix_id] = definition
		_validate_float_array(definition.values_by_rarity, NORMAL_RARITY_COUNT, "values_by_rarity", path, false)


func _load_score() -> void:
	var loaded: Resource = ResourceLoader.load(SCORE_PATH)
	if not loaded is ScoreDefinition:
		_add_error("Missing or invalid ScoreDefinition: %s" % SCORE_PATH)
		return
	_score_definition = loaded as ScoreDefinition
	_validate_non_negative_int(_score_definition.normal_kill, "normal_kill", SCORE_PATH)
	_validate_non_negative_int(_score_definition.post_quota_bonus, "post_quota_bonus", SCORE_PATH)
	_validate_non_negative_int(_score_definition.elite_kill, "elite_kill", SCORE_PATH)
	_validate_non_negative_int(_score_definition.boss_kill, "boss_kill", SCORE_PATH)
	_validate_non_negative_int(_score_definition.wave_clear, "wave_clear", SCORE_PATH)
	_validate_non_negative_int(_score_definition.run_clear, "run_clear", SCORE_PATH)
	if _score_definition.equipment_scores.size() != NORMAL_RARITY_COUNT:
		_add_error("equipment_scores length mismatch: %s" % SCORE_PATH)
	for value: int in _score_definition.equipment_scores:
		_validate_non_negative_int(value, "equipment_scores", SCORE_PATH)


func _load_balance_manifest() -> void:
	var loaded: Resource = ResourceLoader.load(BALANCE_MANIFEST_PATH)
	if not loaded is BalanceManifest:
		_add_error("Missing or invalid BalanceManifest: %s" % BALANCE_MANIFEST_PATH)
		return
	_balance_manifest = loaded as BalanceManifest
	_validate_non_negative_int(_balance_manifest.balance_revision, "balance_revision", BALANCE_MANIFEST_PATH)


func _validate_catalog_shape() -> void:
	_validate_count(weapons.size(), WEAPON_PATHS.size(), "WeaponDefinition")
	_validate_count(_weapons_by_type.size(), WEAPON_PATHS.size(), "WeaponType")
	_validate_count(enemies.size(), ENEMY_PATHS.size(), "EnemyDefinition")
	_validate_count(waves.size(), WAVE_PATHS.size(), "WaveDefinition")
	_validate_count(rarities.size(), RARITY_PATHS.size(), "RarityDefinition")
	_validate_count(affixes.size(), AFFIX_PATHS.size(), "AffixDefinition")
	var elite_wave_count: int = 0
	var boss_wave_count: int = 0
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
	if actual.is_empty() or actual != expected:
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


func _validate_float_array(
	values: PackedFloat32Array,
	expected_size: int,
	field_name: String,
	path: String,
	require_positive: bool,
) -> void:
	if values.size() != expected_size:
		_add_error("%s length mismatch: %s" % [field_name, path])
	for value: float in values:
		if require_positive:
			_validate_positive_float(value, field_name, path)
		else:
			_validate_non_negative_float(value, field_name, path)


func _validate_weights(
	weights: Dictionary,
	expected_keys: Array[int],
	field_name: String,
	path: String,
) -> void:
	if weights.size() != expected_keys.size():
		_add_error("%s key count mismatch: %s" % [field_name, path])
	var total: float = 0.0
	for key: int in expected_keys:
		if not weights.has(key):
			_add_error("%s is missing enum key %d: %s" % [field_name, key, path])
			continue
		var raw_value: Variant = weights[key]
		if typeof(raw_value) != TYPE_FLOAT and typeof(raw_value) != TYPE_INT:
			_add_error("%s contains a non-numeric weight: %s" % [field_name, path])
			continue
		var value: float = float(raw_value)
		_validate_non_negative_float(value, field_name, path)
		total += value
	if not is_finite(total) or absf(total - 1.0) > WEIGHT_SUM_TOLERANCE:
		_add_error("%s must sum to 1: %s" % [field_name, path])


func _add_error(message: String) -> void:
	validation_errors.append(message)


func _string_name_ordinal_less(left: StringName, right: StringName) -> bool:
	return String(left) < String(right)
