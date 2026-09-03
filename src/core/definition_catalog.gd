class_name DefinitionCatalog
extends RefCounted


const MANIFEST_PATH: String = "res://data/balance/survival_content_manifest.tres"
const EXPECTED_TARGETS: Array[int] = [
	16, 46, 32, 68, 49, 140, 92, 132, 97, 176,
]
const BASELINE_HP_MULTIPLIERS: Array[float] = [
	0.15, 0.215, 1.325, 0.24, 0.74, 0.35, 1.85, 0.78, 1.75, 1.40,
]
const BASELINE_DAMAGE_MULTIPLIERS: Array[float] = [
	0.18, 0.20, 0.22, 0.25, 0.29, 0.34, 0.42, 0.50, 0.64, 1.50,
]
const EXPECTED_SEGMENT_WEIGHTS: Array = [
	[0.70, 0.30, 0.0, 0.0, 0.0, 0.0],
	[0.25, 0.75, 0.0, 0.0, 0.0, 0.0],
	[1.00, 0.00, 0.0, 0.0, 0.0, 0.0],
	[0.40, 0.225, 0.225, 0.15, 0.0, 0.0],
	[0.45, 0.25, 0.25, 0.05, 0.0, 0.0],
	[0.16, 0.165, 0.15, 0.525, 0.0, 0.0],
	[0.20, 0.15, 0.65, 0.00, 0.0, 0.0],
	[0.15, 0.15, 0.50, 0.20, 0.0, 0.0],
	[0.15, 0.15, 0.45, 0.25, 0.0, 0.0],
	[0.25, 0.25, 0.25, 0.25, 0.0, 0.0],
]
const MAX_APPROVED_AREA_MULTIPLIER: float = 1.5
const EXPECTED_ELITE_TICKS: Array[int] = [
	7200, 14400, 21600, 28800,
]
const WEIGHT_TOLERANCE: float = 0.0001
const MIN_SEGMENT_TARGET_HP_RATIO: float = 0.10
const MIN_SEGMENT_DAMAGE_RATIO: float = 0.15
const MIN_BOSS_TUNING_RATIO: float = 0.20
const MIN_BOSS_HP_TUNING_RATIO: float = 0.15
const MIN_BOSS_DAMAGE_ACTION_TUNING_RATIO: float = 0.05

var weapons: Dictionary[StringName, WeaponDefinition] = {}
var passives: Dictionary[StringName, PassiveDefinition] = {}
var enemies: Dictionary[StringName, EnemyDefinition] = {}
var segments: Dictionary[int, EnemySegmentDefinition] = {}
var evolutions: Dictionary[StringName, EvolutionDefinition] = {}
var is_valid: bool = false
var error_text: String = ""
var validation_errors: PackedStringArray = PackedStringArray()

var _manifest: SurvivalContentManifest = null
var _enemies_by_type: Dictionary[int, EnemyDefinition] = {}
var _evolved_weapon_ids: Dictionary[StringName, bool] = {}


func load_and_validate() -> bool:
	var loaded: Resource = ResourceLoader.load(MANIFEST_PATH)
	if not loaded is SurvivalContentManifest:
		_reset()
		_add_error("Missing or invalid SurvivalContentManifest: %s" % MANIFEST_PATH)
		_finish_validation()
		return false
	return validate_manifest(loaded as SurvivalContentManifest)


func validate_manifest(content_manifest: SurvivalContentManifest) -> bool:
	_reset()
	if content_manifest == null:
		_add_error("SurvivalContentManifest must not be null")
		_finish_validation()
		return false
	_manifest = content_manifest
	_index_content()
	_validate_globals()
	_validate_weapons()
	_validate_passives()
	_validate_evolutions()
	_validate_enemies()
	_validate_segments()
	_finish_validation()
	return is_valid


func manifest() -> SurvivalContentManifest:
	return _manifest


func balance_manifest() -> BalanceManifest:
	return null if _manifest == null else _manifest.balance


func weapon(weapon_id: StringName) -> WeaponDefinition:
	return weapons.get(weapon_id) as WeaponDefinition


func passive(passive_id: StringName) -> PassiveDefinition:
	return passives.get(passive_id) as PassiveDefinition


func enemy(enemy_id: StringName) -> EnemyDefinition:
	return enemies.get(enemy_id) as EnemyDefinition


func enemy_for_type(enemy_type: GameTypes.EnemyType) -> EnemyDefinition:
	return _enemies_by_type.get(int(enemy_type)) as EnemyDefinition


func segment(segment_index: int) -> EnemySegmentDefinition:
	return segments.get(segment_index) as EnemySegmentDefinition


func segment_for_tick(combat_tick: int) -> EnemySegmentDefinition:
	if segments.is_empty():
		return null
	var index: int = clampi(
		int(floor(float(combat_tick) / 3600.0)),
		0,
		segments.size() - 1,
	)
	return segment(index)


func evolution_for_weapon(base_weapon_id: StringName) -> EvolutionDefinition:
	return evolutions.get(base_weapon_id) as EvolutionDefinition


func is_evolved_weapon(weapon_id: StringName) -> bool:
	return _evolved_weapon_ids.has(weapon_id)


func basic_weapon_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for definition: WeaponDefinition in weapons.values():
		if not definition.is_evolved:
			result.append(definition.weapon_id)
	result.sort_custom(_string_name_less)
	return result


func evolved_weapon_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for weapon_id: StringName in _evolved_weapon_ids:
		result.append(weapon_id)
	result.sort_custom(_string_name_less)
	return result


func passive_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for passive_id: StringName in passives:
		result.append(passive_id)
	result.sort_custom(_string_name_less)
	return result


func _reset() -> void:
	weapons.clear()
	passives.clear()
	enemies.clear()
	segments.clear()
	evolutions.clear()
	_enemies_by_type.clear()
	_evolved_weapon_ids.clear()
	_manifest = null
	is_valid = false
	error_text = ""
	validation_errors.clear()


func _index_content() -> void:
	for definition: WeaponDefinition in _manifest.weapons:
		if definition == null:
			_add_error("Manifest contains a null weapon")
			continue
		if weapons.has(definition.weapon_id):
			_add_error("Duplicate weapon_id: %s" % definition.weapon_id)
		else:
			weapons[definition.weapon_id] = definition
		if definition.is_evolved:
			_evolved_weapon_ids[definition.weapon_id] = true
	for definition: PassiveDefinition in _manifest.passives:
		if definition == null:
			_add_error("Manifest contains a null passive")
			continue
		if passives.has(definition.passive_id):
			_add_error("Duplicate passive_id: %s" % definition.passive_id)
		else:
			passives[definition.passive_id] = definition
	for definition: EvolutionDefinition in _manifest.evolutions:
		if definition == null:
			_add_error("Manifest contains a null evolution")
			continue
		if evolutions.has(definition.base_weapon_id):
			_add_error("Duplicate evolution base weapon: %s" % definition.base_weapon_id)
		else:
			evolutions[definition.base_weapon_id] = definition
	for definition: EnemyDefinition in _manifest.enemies:
		if definition == null:
			_add_error("Manifest contains a null enemy")
			continue
		if enemies.has(definition.enemy_id):
			_add_error("Duplicate enemy_id: %s" % definition.enemy_id)
		else:
			enemies[definition.enemy_id] = definition
		if _enemies_by_type.has(int(definition.enemy_type)):
			_add_error("Duplicate enemy_type: %s" % definition.enemy_id)
		else:
			_enemies_by_type[int(definition.enemy_type)] = definition
	for definition: EnemySegmentDefinition in _manifest.segments:
		if definition == null:
			_add_error("Manifest contains a null segment")
			continue
		if segments.has(definition.segment_index):
			_add_error("Duplicate segment_index: %d" % definition.segment_index)
		else:
			segments[definition.segment_index] = definition


func _validate_globals() -> void:
	if _manifest.balance == null or _manifest.balance.balance_revision != 7:
		_add_error("balance revision must be 7")
	if _manifest.ticks_per_second != 60:
		_add_error("ticks_per_second must be 60")
	if not _manifest.arena_size.is_equal_approx(Vector2(30.0, 30.0)):
		_add_error("arena_size must be 30x30")
	if _manifest.boss_start_tick != 36000:
		_add_error("boss_start_tick must be 36000")
	_validate_xp_contract()
	if _manifest.weapon_slot_count != 5 or _manifest.passive_slot_count != 5:
		_add_error("run slots must be five weapons and five passives")
	if _manifest.level_offer_count != 3:
		_add_error("level_offer_count must be 3")
	if (
		_manifest.owned_offer_attempt_count != 2
		or not is_equal_approx(_manifest.owned_offer_luck_coefficient, 0.3)
	):
		_add_error("owned offer must use two attempts and coefficient 0.3")
	if _manifest.elite_spawn_ticks != PackedInt32Array(EXPECTED_ELITE_TICKS):
		_add_error("elite spawn ticks do not match 2/4/6/8 minutes")
	if _manifest.node_site_count != 8 or _manifest.active_node_count != 4:
		_add_error("node site/active counts must be 8/4")
	if _manifest.node_respawn_ticks != 1800:
		_add_error("node respawn must be 1800 ticks")
	if not is_equal_approx(_manifest.node_heal_amount, 30.0):
		_add_error("node heal must be 30")
	if _manifest.node_stop_ticks != 300:
		_add_error("node stop must be 300 ticks")
	_validate_probability_weights(_manifest.node_drop_weights, "node_drop_weights")
	var expected_node_weights := PackedFloat32Array([0.55, 0.35, 0.07, 0.03])
	if not _float_arrays_equal(_manifest.node_drop_weights, expected_node_weights):
		_add_error("node drop weights differ from approved values")
	if _manifest.damage_invulnerability_ticks != 30:
		_add_error("damage invulnerability must be 30 ticks")
	if _manifest.modal_resume_invulnerability_ticks != 45:
		_add_error("modal resume invulnerability must be 45 ticks")
	_validate_tunable_multiplier(
		_manifest.normal_enemy_damage_scale,
		SurvivalContentManifest.DEFAULT_NORMAL_ENEMY_DAMAGE_SCALE,
		"normal enemy damage scale",
	)
	_validate_tunable_multiplier(
		_manifest.boss_hp_multiplier,
		SurvivalContentManifest.DEFAULT_BOSS_HP_MULTIPLIER,
		"boss HP multiplier",
		MIN_BOSS_HP_TUNING_RATIO,
	)
	_validate_tunable_multiplier(
		_manifest.boss_damage_multiplier,
		SurvivalContentManifest.DEFAULT_BOSS_DAMAGE_MULTIPLIER,
		"boss damage multiplier",
		MIN_BOSS_DAMAGE_ACTION_TUNING_RATIO,
	)
	_validate_tunable_multiplier(
		_manifest.boss_action_rate_multiplier,
		SurvivalContentManifest.DEFAULT_BOSS_ACTION_RATE_MULTIPLIER,
		"boss action rate multiplier",
		MIN_BOSS_DAMAGE_ACTION_TUNING_RATIO,
	)
	if _manifest.boss_enrage_interval_ticks != 1800:
		_add_error("boss enrage interval must be 1800 ticks")
	if _manifest.boss_enrage_max_stacks != 10:
		_add_error("boss enrage cap must be 10 stacks")
	if not is_equal_approx(_manifest.boss_attack_bonus_per_stack, 0.10):
		_add_error("boss attack bonus must be +10% per stack")
	if not is_equal_approx(_manifest.boss_interval_reduction_per_stack, 0.10):
		_add_error("boss interval reduction must be -10% per stack")
	if not weapons.has(_manifest.starter_weapon_id):
		_add_error("starter weapon is missing")
	elif _manifest.starter_weapon_id != &"homing_core":
		_add_error("starter weapon must be homing_core")


func _validate_xp_contract() -> void:
	if (
		_manifest.xp_early_max_level != SurvivalContentManifest.DEFAULT_XP_EARLY_MAX_LEVEL
		or _manifest.xp_early_coefficient != SurvivalContentManifest.DEFAULT_XP_EARLY_COEFFICIENT
		or _manifest.xp_early_offset != SurvivalContentManifest.DEFAULT_XP_EARLY_OFFSET
	):
		_add_error("early XP formula must be 10L-5 through level 19")
	if _manifest.xp_level_20_requirement != SurvivalContentManifest.DEFAULT_XP_LEVEL_20_REQUIREMENT:
		_add_error("level 20 XP requirement must be 795")
	if (
		_manifest.xp_middle_max_level != SurvivalContentManifest.DEFAULT_XP_MIDDLE_MAX_LEVEL
		or _manifest.xp_middle_coefficient != SurvivalContentManifest.DEFAULT_XP_MIDDLE_COEFFICIENT
		or _manifest.xp_middle_offset != SurvivalContentManifest.DEFAULT_XP_MIDDLE_OFFSET
	):
		_add_error("middle XP formula must be 13L-65 through level 39")
	if _manifest.xp_level_40_requirement != SurvivalContentManifest.DEFAULT_XP_LEVEL_40_REQUIREMENT:
		_add_error("level 40 XP requirement must be 2855")
	if (
		_manifest.xp_late_coefficient != SurvivalContentManifest.DEFAULT_XP_LATE_COEFFICIENT
		or _manifest.xp_late_offset != SurvivalContentManifest.DEFAULT_XP_LATE_OFFSET
	):
		_add_error("late XP formula must be 16L-185 from level 41")
	if (
		_manifest.xp_growth_compensation_levels
		!= PackedInt32Array(SurvivalContentManifest.DEFAULT_XP_GROWTH_COMPENSATION_LEVELS)
		or not is_equal_approx(
			_manifest.xp_growth_compensation_multiplier,
			SurvivalContentManifest.DEFAULT_XP_GROWTH_COMPENSATION_MULTIPLIER,
		)
	):
		_add_error("Growth compensation must be 2x at levels 20 and 40")
	if _manifest.xp_pool_capacity != SurvivalContentManifest.DEFAULT_XP_POOL_CAPACITY:
		_add_error("XP pickup capacity must be 2048")
	if not is_equal_approx(
		_manifest.xp_pickup_attract_radius,
		SurvivalContentManifest.DEFAULT_XP_PICKUP_ATTRACT_RADIUS,
	):
		_add_error("XP pickup attract radius must be 2.25")
	if not is_equal_approx(
		_manifest.xp_pickup_collect_radius,
		SurvivalContentManifest.DEFAULT_XP_PICKUP_COLLECT_RADIUS,
	):
		_add_error("XP pickup collect radius must be 0.7")
	if not is_equal_approx(
		_manifest.xp_pickup_speed,
		SurvivalContentManifest.DEFAULT_XP_PICKUP_SPEED,
	):
		_add_error("XP pickup speed must be 14")
	if (
		_manifest.xp_yield_percent < 50
		or _manifest.xp_yield_percent > 200
		or _manifest.xp_yield_percent % 5 != 0
	):
		_add_error("XP yield percent must be 50-200 in 5% steps")


func _validate_tunable_multiplier(
	value: float,
	baseline: float,
	label: String,
	minimum_ratio: float = MIN_BOSS_TUNING_RATIO,
) -> void:
	if not is_finite(value) or not is_finite(baseline) or baseline <= 0.0:
		_add_error("%s must be finite with a positive baseline" % label)
		return
	var ratio: float = value / baseline
	var five_percent_units: float = ratio * 20.0
	if (
		ratio < minimum_ratio - WEIGHT_TOLERANCE
		or ratio > 1.10 + WEIGHT_TOLERANCE
		or absf(five_percent_units - roundf(five_percent_units)) > WEIGHT_TOLERANCE
	):
		_add_error(
			"%s must be -%d%% to +10%% in 5%% steps"
			% [label, 100 - roundi(minimum_ratio * 100.0)]
		)


func _validate_weapons() -> void:
	if weapons.size() != 16:
		_add_error("weapon count must be 8 base + 8 evolved")
	var basic_count: int = 0
	var evolved_count: int = 0
	var seen_behaviors: Dictionary[int, bool] = {}
	for definition: WeaponDefinition in weapons.values():
		if definition.weapon_id == &"" or definition.display_name.is_empty():
			_add_error("weapon id/name must not be empty")
		if definition.lineage_id == &"":
			_add_error("weapon lineage must not be empty: %s" % definition.weapon_id)
		var expected_levels: int = 1 if definition.is_evolved else 8
		if definition.max_level != expected_levels:
			_add_error("weapon max level mismatch: %s" % definition.weapon_id)
		_validate_weapon_arrays(definition)
		if definition.is_evolved:
			evolved_count += 1
			if not is_zero_approx(definition.selection_weight):
				_add_error("evolved weapon must not enter offers: %s" % definition.weapon_id)
		else:
			basic_count += 1
			_validate_single_weapon_level_deltas(definition)
			if definition.selection_weight <= 0.0:
				_add_error("base weapon must have positive weight: %s" % definition.weapon_id)
			if not is_equal_approx(
				definition.selection_weight,
				_expected_weapon_weight(definition.weapon_id),
			):
				_add_error("base weapon weight differs from approved value: %s" % definition.weapon_id)
			if seen_behaviors.has(int(definition.behavior)):
				_add_error("duplicate base weapon behavior: %s" % definition.weapon_id)
			seen_behaviors[int(definition.behavior)] = true
	if basic_count != 8 or evolved_count != 8 or seen_behaviors.size() != 8:
		_add_error("weapon role count must be exactly eight base/evolved")


func _validate_weapon_arrays(definition: WeaponDefinition) -> void:
	var size: int = definition.max_level
	if definition.damage_by_level.size() != size:
		_add_error("damage_by_level length mismatch: %s" % definition.weapon_id)
	if definition.cooldown_ticks_by_level.size() != size:
		_add_error("cooldown_ticks_by_level length mismatch: %s" % definition.weapon_id)
	if definition.amount_by_level.size() != size:
		_add_error("amount_by_level length mismatch: %s" % definition.weapon_id)
	if definition.projectile_speed_by_level.size() != size:
		_add_error("projectile_speed_by_level length mismatch: %s" % definition.weapon_id)
	if definition.range_by_level.size() != size:
		_add_error("range_by_level length mismatch: %s" % definition.weapon_id)
	if definition.projectile_radius_by_level.size() != size:
		_add_error("projectile_radius_by_level length mismatch: %s" % definition.weapon_id)
	if definition.effect_radius_by_level.size() != size:
		_add_error("effect_radius_by_level length mismatch: %s" % definition.weapon_id)
	if definition.duration_ticks_by_level.size() != size:
		_add_error("duration_ticks_by_level length mismatch: %s" % definition.weapon_id)
	if definition.pierce_by_level.size() != size:
		_add_error("pierce_by_level length mismatch: %s" % definition.weapon_id)
	for value: float in definition.damage_by_level:
		if not is_finite(value) or value <= 0.0:
			_add_error("weapon damage must be positive: %s" % definition.weapon_id)
	for value: int in definition.cooldown_ticks_by_level:
		if value <= 0:
			_add_error("weapon cooldown must be positive: %s" % definition.weapon_id)
	for value: float in definition.range_by_level:
		if not is_finite(value) or value < 0.0:
			_add_error("weapon range must be finite and non-negative: %s" % definition.weapon_id)
	for value: float in definition.projectile_radius_by_level:
		if not is_finite(value) or value < 0.0:
			_add_error("weapon projectile radius must be finite and non-negative: %s" % definition.weapon_id)
	for value: float in definition.effect_radius_by_level:
		if not is_finite(value) or value < 0.0:
			_add_error("weapon effect radius must be finite and non-negative: %s" % definition.weapon_id)
	_validate_weapon_envelope(definition)


func _validate_single_weapon_level_deltas(definition: WeaponDefinition) -> void:
	for next_level: int in range(2, definition.max_level + 1):
		var deltas: Array[WeaponDefinition.WeaponLevelDelta] = definition.level_deltas(next_level)
		if deltas.size() != 1:
			_add_error(
				"base weapon level must change exactly one stat: %s level %d changed %d"
				% [definition.weapon_id, next_level, deltas.size()]
			)
			continue
		var delta: WeaponDefinition.WeaponLevelDelta = deltas[0]
		if (
			delta.stat_id == WeaponDefinition.STAT_AMOUNT
			and not is_equal_approx(delta.new_value - delta.previous_value, 1.0)
		):
			_add_error(
				"base weapon amount level delta must be +1: %s level %d changed %d to %d"
				% [
					definition.weapon_id,
					next_level,
					roundi(delta.previous_value),
					roundi(delta.new_value),
				]
			)


func _validate_weapon_envelope(definition: WeaponDefinition) -> void:
	for level: int in range(1, definition.max_level + 1):
		var range_m: float = definition.effective_range_at(
			level,
			MAX_APPROVED_AREA_MULTIPLIER,
		)
		var projectile_radius: float = definition.effective_projectile_radius_at(
			level,
			MAX_APPROVED_AREA_MULTIPLIER,
		)
		var effect_radius: float = definition.effective_effect_radius_at(
			level,
			MAX_APPROVED_AREA_MULTIPLIER,
		)
		var outer_edge: float = 0.0
		match definition.behavior:
			GameTypes.WeaponBehavior.MELEE_WAVE:
				outer_edge = range_m
			GameTypes.WeaponBehavior.ORBITAL:
				outer_edge = range_m + effect_radius
			GameTypes.WeaponBehavior.AURA:
				outer_edge = effect_radius
			_:
				outer_edge = range_m + maxf(projectile_radius, effect_radius)
		if outer_edge > CombatEnvelope.EFFECT_OUTER_RADIUS + WEIGHT_TOLERANCE:
			_add_error(
				"weapon outer edge exceeds combat envelope: %s level %d"
				% [definition.weapon_id, level]
			)


func _validate_passives() -> void:
	if passives.size() != 8:
		_add_error("passive count must be eight")
	for definition: PassiveDefinition in passives.values():
		if definition.passive_id == &"" or definition.display_name.is_empty():
			_add_error("passive id/name must not be empty")
		if definition.max_level != 5:
			_add_error("passive max level must be five: %s" % definition.passive_id)
		if definition.selection_weight <= 0.0:
			_add_error("passive weight must be positive: %s" % definition.passive_id)
		if definition.stat_id == &"" or not weapons.has(definition.paired_weapon_id):
			_add_error("passive effect/pair is invalid: %s" % definition.passive_id)
		var approved: Dictionary = _expected_passive_spec(definition.passive_id)
		if approved.is_empty():
			_add_error("unknown passive identity: %s" % definition.passive_id)
		elif (
			definition.stat_id != approved[&"stat_id"]
			or not is_equal_approx(definition.amount_per_level, float(approved[&"amount"]))
			or not is_equal_approx(definition.selection_weight, float(approved[&"weight"]))
		):
			_add_error("passive spec differs from approved value: %s" % definition.passive_id)


func _validate_evolutions() -> void:
	if evolutions.size() != 8:
		_add_error("evolution count must be eight")
	var evolved_targets: Dictionary[StringName, bool] = {}
	for definition: EvolutionDefinition in evolutions.values():
		var base: WeaponDefinition = weapon(definition.base_weapon_id)
		var evolved: WeaponDefinition = weapon(definition.evolved_weapon_id)
		var paired_passive: PassiveDefinition = passive(definition.passive_id)
		if base == null or base.is_evolved:
			_add_error("evolution base is invalid: %s" % definition.base_weapon_id)
		if evolved == null or not evolved.is_evolved:
			_add_error("evolution target is invalid: %s" % definition.evolved_weapon_id)
		if paired_passive == null:
			_add_error("evolution passive is invalid: %s" % definition.passive_id)
		if base != null and base.paired_passive_id != definition.passive_id:
			_add_error("weapon/passive evolution pair mismatch: %s" % definition.base_weapon_id)
		if evolved != null and evolved.lineage_id != definition.base_weapon_id:
			_add_error("evolution lineage mismatch: %s" % definition.evolved_weapon_id)
		if evolved_targets.has(definition.evolved_weapon_id):
			_add_error("duplicate evolution target: %s" % definition.evolved_weapon_id)
		evolved_targets[definition.evolved_weapon_id] = true


func _validate_enemies() -> void:
	if enemies.size() != GameTypes.EnemyType.size():
		_add_error("enemy count must match EnemyType")
	for definition: EnemyDefinition in enemies.values():
		if definition.enemy_id == &"" or definition.display_name.is_empty():
			_add_error("enemy id/name must not be empty")
		if definition.base_hp <= 0.0 or definition.move_speed <= 0.0:
			_add_error("enemy hp/speed must be positive: %s" % definition.enemy_id)
		if definition.contact_interval_ticks <= 0 or definition.contact_damage <= 0.0:
			_add_error("enemy contact values must be positive: %s" % definition.enemy_id)
		if definition.xp_value < 0:
			_add_error("enemy XP must not be negative: %s" % definition.enemy_id)
		if definition.enemy_type != GameTypes.EnemyType.BOSS and (
			not is_finite(definition.preferred_distance_min)
			or definition.preferred_distance_min != 0.0
			or not is_finite(definition.preferred_distance_max)
			or definition.preferred_distance_max != 0.0
			or definition.special_interval_ticks != 0
			or definition.telegraph_ticks != 0
			or not is_finite(definition.area_radius)
			or definition.area_radius != 0.0
			or not is_finite(definition.projectile_damage)
			or definition.projectile_damage != 0.0
			or not is_finite(definition.projectile_speed)
			or definition.projectile_speed != 0.0
			or not is_finite(definition.projectile_radius)
			or definition.projectile_radius != 0.0
			or definition.projectile_lifetime_ticks != 0
			or definition.volley_count != 0
		):
			_add_error("non-boss enemies must be contact-only: %s" % definition.enemy_id)
	var elite: EnemyDefinition = enemy_for_type(GameTypes.EnemyType.ELITE)
	var boss: EnemyDefinition = enemy_for_type(GameTypes.EnemyType.BOSS)
	if elite == null or not elite.drops_chest:
		_add_error("elite must drop a chest")
	elif not is_equal_approx(elite.base_hp, 650.0):
		_add_error("revision 7 elite HP must be 650")
	if boss == null or not boss.is_boss:
		_add_error("boss definition must be marked as boss")
	_validate_revision_seven_enemy_roles()


func _validate_revision_seven_enemy_roles() -> void:
	var expected_specs: Dictionary[StringName, Array] = {
		&"pursuer": [20.0, 2.4, 45, 8.0, 1],
		&"swarmer": [9.0, 4.2, 45, 4.0, 1],
		&"bulwark": [80.0, 1.35, 60, 14.0, 2],
		&"shooter": [34.0, 3.0, 42, 11.0, 2],
	}
	for enemy_id: StringName in expected_specs:
		var definition: EnemyDefinition = enemy(enemy_id)
		var expected: Array = expected_specs[enemy_id]
		if definition == null:
			continue
		if (
			not is_equal_approx(definition.base_hp, float(expected[0]))
			or not is_equal_approx(definition.move_speed, float(expected[1]))
			or definition.contact_interval_ticks != int(expected[2])
			or not is_equal_approx(definition.contact_damage, float(expected[3]))
			or definition.xp_value != int(expected[4])
		):
			_add_error("revision 7 enemy role differs from approved values: %s" % enemy_id)


func _validate_segments() -> void:
	if segments.size() != 10:
		_add_error("segment count must be ten")
	for index: int in range(10):
		var definition: EnemySegmentDefinition = segment(index)
		if definition == null:
			_add_error("missing segment %d" % index)
			continue
		if definition.start_tick != index * 3600 or definition.end_tick != (index + 1) * 3600:
			_add_error("segment tick bounds mismatch: %d" % index)
		if definition.target_active != EXPECTED_TARGETS[index]:
			_add_error("segment target differs from revision 7 value: %d" % index)
		if not is_equal_approx(definition.hp_multiplier, BASELINE_HP_MULTIPLIERS[index]):
			_add_error("segment HP differs from revision 7 value: %d" % index)
		if not is_equal_approx(
			definition.damage_multiplier,
			BASELINE_DAMAGE_MULTIPLIERS[index],
		):
			_add_error("segment damage differs from revision 7 value: %d" % index)
		_validate_probability_weights(definition.spawn_weights, "segment_%02d weights" % (index + 1))
		if not _float_arrays_equal(definition.spawn_weights, EXPECTED_SEGMENT_WEIGHTS[index]):
			_add_error("segment weights differ from revision 7 value: %d" % index)
		if definition.spawn_weights.size() != GameTypes.EnemyType.size():
			_add_error(
				"segment spawn weights must contain exactly one entry per EnemyType: %d"
				% index
			)
		else:
			if (
				not is_zero_approx(definition.spawn_weights[GameTypes.EnemyType.ELITE])
				or not is_zero_approx(definition.spawn_weights[GameTypes.EnemyType.BOSS])
			):
				_add_error("segments may only spawn normal enemy types: %d" % index)


func _validate_probability_weights(values: PackedFloat32Array, label: String) -> void:
	if values.is_empty():
		_add_error("%s must not be empty" % label)
		return
	var total: float = 0.0
	for value: float in values:
		if not is_finite(value) or value < 0.0:
			_add_error("%s contains an invalid value" % label)
		total += value
	if absf(total - 1.0) > WEIGHT_TOLERANCE:
		_add_error("%s must sum to one" % label)


func _validate_segment_target_tuning(
	definition: EnemySegmentDefinition,
	segment_index: int,
) -> void:
	var baseline: int = EXPECTED_TARGETS[segment_index]
	var maximum_step: int = 22 if segment_index >= 6 else 20
	for five_percent_step: int in range(
		roundi(MIN_SEGMENT_TARGET_HP_RATIO * 20.0),
		maximum_step + 1,
	):
		var allowed_target: int = roundi(
			float(baseline) * float(five_percent_step) / 20.0
		)
		if definition.target_active == allowed_target:
			return
	_add_error(
		"segment target must be -90%%..%s in 5%% steps: %d"
		% ["+10%" if segment_index >= 6 else "baseline", segment_index]
	)


func _validate_segment_multiplier_tuning(
	value: float,
	baseline: float,
	segment_index: int,
	label: String,
	minimum_ratio: float,
) -> void:
	if not is_finite(value) or not is_finite(baseline) or baseline <= 0.0:
		_add_error("segment %s multiplier must be finite with a positive baseline: %d" % [label, segment_index])
		return
	var ratio: float = value / baseline
	var maximum_ratio: float = 1.10 if segment_index >= 6 else 1.0
	var five_percent_units: float = ratio * 20.0
	if (
		ratio < minimum_ratio - WEIGHT_TOLERANCE
		or ratio > maximum_ratio + WEIGHT_TOLERANCE
		or absf(five_percent_units - roundf(five_percent_units)) > WEIGHT_TOLERANCE
	):
		_add_error(
			"segment %s must be -%d%%..%s in 5%% steps: %d"
			% [
				label,
				100 - roundi(minimum_ratio * 100.0),
				"+10%" if segment_index >= 6 else "baseline",
				segment_index,
			]
		)


func _float_arrays_equal(left: PackedFloat32Array, right: Array) -> bool:
	if left.size() != right.size():
		return false
	for index: int in range(left.size()):
		if not is_equal_approx(left[index], right[index]):
			return false
	return true


func _finish_validation() -> void:
	is_valid = validation_errors.is_empty()
	error_text = "\n".join(validation_errors)


func _add_error(message: String) -> void:
	validation_errors.append(message)


func _expected_weapon_weight(weapon_id: StringName) -> float:
	match weapon_id:
		&"resonance_wave", &"homing_core", &"directional_needle", &"arc_crystal":
			return 100.0
		&"returning_ring", &"orbital_array", &"mass_projectile":
			return 80.0
		&"zero_field":
			return 70.0
	return -1.0


func _expected_passive_spec(passive_id: StringName) -> Dictionary:
	match passive_id:
		&"life_lattice":
			return {&"stat_id": &"max_hp_pct", &"amount": 20.0, &"weight": 90.0}
		&"cycle_crystal":
			return {&"stat_id": &"cooldown_pct", &"amount": -8.0, &"weight": 50.0}
		&"speed_gate":
			return {&"stat_id": &"projectile_speed_pct", &"amount": 10.0, &"weight": 100.0}
		&"scale_lens":
			return {&"stat_id": &"area_pct", &"amount": 10.0, &"weight": 100.0}
		&"probability_core":
			return {&"stat_id": &"luck_pct", &"amount": 10.0, &"weight": 100.0}
		&"duration_ring":
			return {&"stat_id": &"duration_pct", &"amount": 10.0, &"weight": 100.0}
		&"amplifier_core":
			return {&"stat_id": &"might_pct", &"amount": 10.0, &"weight": 100.0}
		&"repair_core":
			return {&"stat_id": &"recovery_per_second", &"amount": 0.2, &"weight": 90.0}
	return {}


func _string_name_less(left: StringName, right: StringName) -> bool:
	return String(left) < String(right)
