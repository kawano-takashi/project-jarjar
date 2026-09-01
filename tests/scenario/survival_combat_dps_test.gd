extends RefCounted


enum FixtureKind { SINGLE, GROUP, BOSS }

const MEASURE_TICKS: int = 600
const GROUP_TARGET_COUNT: float = 12.0
const MIN_MEDIAN_GAIN_RATIO: float = 1.15
const ROLE_MEDIAN_TOLERANCE: float = 0.25
const ROLE_EVOLUTION_RATIO: float = 1.50
const ORBITAL_FIXTURE_MOVE_SPEED: float = 0.15
const SINGLE_ROLE_IDS: Array[StringName] = [
	&"homing_core",
	&"returning_ring",
	&"mass_projectile",
]
const GROUP_ROLE_IDS: Array[StringName] = [
	&"resonance_wave",
	&"directional_needle",
	&"arc_crystal",
	&"orbital_array",
	&"zero_field",
]

# Work-start scores were recorded with stationary targets. They remain useful
# only for like-for-like gain checks. Moving targets are measured separately
# for the role bands and evolution ratios used by the gameplay acceptance gate.
# GROUP values are total fixture DPS divided by twelve; SINGLE and BOSS values
# are total DPS.
const BASELINE_LV1_ROLE_SCORES: Dictionary = {
	&"arc_crystal": 1.0,
	&"directional_needle": 0.85,
	&"homing_core": 9.0,
	&"mass_projectile": 14.0,
	&"orbital_array": 5.0666667,
	&"resonance_wave": 8.0,
	&"returning_ring": 19.5,
	&"zero_field": 0.0,
}
const BASELINE_LV8_ROLE_SCORES: Dictionary = {
	&"arc_crystal": 12.0,
	&"directional_needle": 78.125,
	&"homing_core": 195.0,
	&"mass_projectile": 150.0,
	&"orbital_array": 56.0,
	&"resonance_wave": 62.5,
	&"returning_ring": 243.0,
	&"zero_field": 28.0,
}
const BASELINE_EVOLVED_ROLE_SCORES: Dictionary = {
	&"arc_crystal": 300.0,
	&"directional_needle": 222.25,
	&"homing_core": 2261.0,
	&"mass_projectile": 513.0,
	&"orbital_array": 144.0,
	&"resonance_wave": 177.5,
	&"returning_ring": 1353.6,
	&"zero_field": 61.2,
}


func test_names() -> PackedStringArray:
	return PackedStringArray([
		"survival_weapon_dps_matrix_evolutions_are_stronger",
	])


func run_test(test_name: String, assertions: Variant, _context: Dictionary) -> void:
	match test_name:
		"survival_weapon_dps_matrix_evolutions_are_stronger":
			_test_role_normalization(assertions)
		_:
			assertions.expect_true(false, "registered survival weapon DPS test")


func _test_role_normalization(assertions: Variant) -> void:
	var catalog := DefinitionCatalog.new()
	assertions.expect_true(catalog.load_and_validate(), "DPS fixture content validates")
	if not catalog.is_valid:
		return
	var stationary_level_one_scores: Dictionary[StringName, float] = {}
	var stationary_level_eight_scores: Dictionary[StringName, float] = {}
	var stationary_evolved_scores: Dictionary[StringName, float] = {}
	var moving_level_one_scores: Dictionary[StringName, float] = {}
	var moving_level_eight_scores: Dictionary[StringName, float] = {}
	var moving_evolved_scores: Dictionary[StringName, float] = {}
	for base_id: StringName in catalog.basic_weapon_ids():
		var evolution: EvolutionDefinition = catalog.evolution_for_weapon(base_id)
		var role_fixture: FixtureKind = _role_fixture(base_id)
		var stationary_level_one_score: float = _normalized_role_score(
			_measure_dps(catalog, base_id, role_fixture, 1, false),
			role_fixture,
		)
		var stationary_level_eight_score: float = _normalized_role_score(
			_measure_dps(catalog, base_id, role_fixture, 8, false),
			role_fixture,
		)
		var stationary_evolved_score: float = _normalized_role_score(
			_measure_dps(catalog, evolution.evolved_weapon_id, role_fixture, 1, false),
			role_fixture,
		)
		var moving_level_one_score: float = _normalized_role_score(
			_measure_dps(catalog, base_id, role_fixture, 1, true),
			role_fixture,
		)
		var moving_level_eight_score: float = _normalized_role_score(
			_measure_dps(catalog, base_id, role_fixture, 8, true),
			role_fixture,
		)
		var moving_evolved_score: float = _normalized_role_score(
			_measure_dps(catalog, evolution.evolved_weapon_id, role_fixture, 1, true),
			role_fixture,
		)
		stationary_level_one_scores[base_id] = stationary_level_one_score
		stationary_level_eight_scores[base_id] = stationary_level_eight_score
		stationary_evolved_scores[base_id] = stationary_evolved_score
		moving_level_one_scores[base_id] = moving_level_one_score
		moving_level_eight_scores[base_id] = moving_level_eight_score
		moving_evolved_scores[base_id] = moving_evolved_score
		print("WEAPON_ROLE_SCORE lineage=%s stationary=%.4f/%.4f/%.4f moving=%.4f/%.4f/%.4f" % [
			base_id,
			stationary_level_one_score,
			stationary_level_eight_score,
			stationary_evolved_score,
			moving_level_one_score,
			moving_level_eight_score,
			moving_evolved_score,
		])
		assertions.expect_true(
			moving_evolved_score >= moving_level_eight_score * ROLE_EVOLUTION_RATIO,
			"%s evolution reaches at least 1.5x its moving-target Lv8 role score (%.2f -> %.2f)" % [
				base_id,
				moving_level_eight_score,
				moving_evolved_score,
			],
		)
	_assert_baseline_gain(
		assertions,
		"single",
		SINGLE_ROLE_IDS,
		stationary_level_one_scores,
		stationary_level_eight_scores,
		stationary_evolved_scores,
	)
	_assert_baseline_gain(
		assertions,
		"group",
		GROUP_ROLE_IDS,
		stationary_level_one_scores,
		stationary_level_eight_scores,
		stationary_evolved_scores,
	)
	_assert_role_bands(
		assertions,
		"single",
		SINGLE_ROLE_IDS,
		moving_level_one_scores,
		moving_level_eight_scores,
		moving_evolved_scores,
	)
	_assert_role_bands(
		assertions,
		"group",
		GROUP_ROLE_IDS,
		moving_level_one_scores,
		moving_level_eight_scores,
		moving_evolved_scores,
	)
	assertions.expect_equal(
		1,
		catalog.weapon(&"infinite_homing").cooldown_ticks_at(1),
		"infinite homing retains its one-tick cadence",
	)


func _assert_baseline_gain(
	assertions: Variant,
	role_name: String,
	lineage_ids: Array[StringName],
	level_one_scores: Dictionary[StringName, float],
	level_eight_scores: Dictionary[StringName, float],
	evolved_scores: Dictionary[StringName, float],
) -> void:
	var role_level_one: Dictionary[StringName, float] = _select_scores(level_one_scores, lineage_ids)
	var role_level_eight: Dictionary[StringName, float] = _select_scores(level_eight_scores, lineage_ids)
	var role_evolved: Dictionary[StringName, float] = _select_scores(evolved_scores, lineage_ids)
	var baseline_level_one: Dictionary[StringName, float] = _select_scores(BASELINE_LV1_ROLE_SCORES, lineage_ids)
	var baseline_level_eight: Dictionary[StringName, float] = _select_scores(BASELINE_LV8_ROLE_SCORES, lineage_ids)
	var baseline_evolved: Dictionary[StringName, float] = _select_scores(BASELINE_EVOLVED_ROLE_SCORES, lineage_ids)
	var level_one_median: float = _median(_score_values(role_level_one))
	var level_eight_median: float = _median(_score_values(role_level_eight))
	var evolved_median: float = _median(_score_values(role_evolved))
	var baseline_level_one_median: float = _median(_score_values(baseline_level_one))
	var baseline_level_eight_median: float = _median(_score_values(baseline_level_eight))
	var baseline_evolved_median: float = _median(_score_values(baseline_evolved))
	print("WEAPON_ROLE_MEDIANS role=%s lv1=%.4f lv8=%.4f evolved=%.4f baseline_lv1=%.4f baseline_lv8=%.4f baseline_evolved=%.4f" % [
		role_name,
		level_one_median,
		level_eight_median,
		evolved_median,
		baseline_level_one_median,
		baseline_level_eight_median,
		baseline_evolved_median,
	])
	assertions.expect_true(
		level_one_median >= baseline_level_one_median * MIN_MEDIAN_GAIN_RATIO,
		"%s Lv1 role median improves by at least fifteen percent" % role_name,
	)
	assertions.expect_true(
		level_eight_median >= baseline_level_eight_median * MIN_MEDIAN_GAIN_RATIO,
		"%s Lv8 role median improves by at least fifteen percent" % role_name,
	)
	assertions.expect_true(
		evolved_median >= baseline_evolved_median,
		"%s evolved role median does not drop from the work-start baseline" % role_name,
	)


func _assert_role_bands(
	assertions: Variant,
	role_name: String,
	lineage_ids: Array[StringName],
	level_one_scores: Dictionary[StringName, float],
	level_eight_scores: Dictionary[StringName, float],
	evolved_scores: Dictionary[StringName, float],
) -> void:
	var role_level_one: Dictionary[StringName, float] = _select_scores(level_one_scores, lineage_ids)
	var role_level_eight: Dictionary[StringName, float] = _select_scores(level_eight_scores, lineage_ids)
	var role_evolved: Dictionary[StringName, float] = _select_scores(evolved_scores, lineage_ids)
	_assert_tier_band(
		assertions,
		"%s moving-target Lv1" % role_name,
		role_level_one,
		_median(_score_values(role_level_one)),
	)
	_assert_tier_band(
		assertions,
		"%s moving-target Lv8" % role_name,
		role_level_eight,
		_median(_score_values(role_level_eight)),
	)
	_assert_tier_band(
		assertions,
		"%s moving-target evolved" % role_name,
		role_evolved,
		_median(_score_values(role_evolved)),
	)


func _assert_tier_band(
	assertions: Variant,
	tier_name: String,
	scores: Dictionary[StringName, float],
	median_score: float,
) -> void:
	var minimum_score: float = median_score * (1.0 - ROLE_MEDIAN_TOLERANCE)
	var maximum_score: float = median_score * (1.0 + ROLE_MEDIAN_TOLERANCE)
	for lineage_id: StringName in scores:
		var score: float = scores[lineage_id]
		assertions.expect_true(
			score + 0.01 >= minimum_score and score - 0.01 <= maximum_score,
			"%s %s role score stays within its median plus or minus twenty-five percent (%.2f; %.2f..%.2f)" % [
				lineage_id,
				tier_name,
				score,
				minimum_score,
				maximum_score,
			],
		)


func _measure_dps(
	catalog: DefinitionCatalog,
	weapon_id: StringName,
	fixture_kind: FixtureKind,
	requested_level: int,
	moving_targets: bool,
) -> float:
	var state: RunState = RunStateFactory.create(
		SeedService.derive(9200 + int(fixture_kind), weapon_id),
		catalog,
	)
	state.weapons.clear()
	state.passives.clear()
	state.combat_tick = RunState.BOSS_START_TICK
	state.boss_spawned = true
	state.build_maxed = true
	state.damage_invulnerable_until_tick = RunState.BOSS_START_TICK + MEASURE_TICKS + 10
	var definition: WeaponDefinition = catalog.weapon(weapon_id)
	var runtime: RunWeapon = RunWeapon.create(
		definition.weapon_id,
		definition.lineage_id,
		definition.is_evolved,
		state.rng_streams.create_weapon_rng(definition.lineage_id, 0),
	)
	runtime.level = requested_level
	state.weapons.append(runtime)
	var simulation := CombatSimulation.new()
	simulation.initialize(state, catalog)
	simulation.enemy_system._elite_spawned.fill(1)
	for position: Vector2 in _fixture_positions(definition, requested_level, fixture_kind):
		var enemy_type: GameTypes.EnemyType = (
			GameTypes.EnemyType.BOSS
			if fixture_kind == FixtureKind.BOSS
			else GameTypes.EnemyType.BULWARK
		)
		var enemy: EnemyEntity = simulation.spawn_fixture_enemy(
			enemy_type,
			position,
			state.combat_tick - 1,
		)
		var fixture_definition: EnemyDefinition = enemy.definition.duplicate()
		fixture_definition.contact_damage = 0.0
		fixture_definition.special_interval_ticks = 0
		fixture_definition.summon_interval_ticks = 0
		if not moving_targets:
			fixture_definition.move_speed = 0.0
		elif definition.lineage_id == &"orbital_array":
			# The orbit role is measured against a slow stream crossing the orbit,
			# rather than enemies that reach the player's center and stay there.
			fixture_definition.move_speed = ORBITAL_FIXTURE_MOVE_SPEED
		enemy.definition = fixture_definition
		enemy.max_hp = 1_000_000_000.0
		enemy.hp = enemy.max_hp
		if enemy_type == GameTypes.EnemyType.BOSS:
			state.boss_hp = enemy.hp
			state.boss_max_hp = enemy.max_hp
	simulation.weapon_system.update_move_direction(Vector2.RIGHT)
	for _tick_index: int in range(MEASURE_TICKS):
		simulation.step(Vector2.ZERO)
	return (
		float(state.weapon_damage_by_lineage.get(definition.lineage_id, 0.0))
		/ (float(MEASURE_TICKS) / float(RunState.TICKS_PER_SECOND))
	)


func _fixture_positions(
	definition: WeaponDefinition,
	level: int,
	fixture_kind: FixtureKind,
) -> Array[Vector2]:
	if fixture_kind == FixtureKind.SINGLE:
		return [Vector2(2.0, 0.0)]
	if fixture_kind == FixtureKind.BOSS:
		return [Vector2(2.5, 0.0)]
	var result: Array[Vector2] = []
	match definition.lineage_id:
		&"resonance_wave":
			var wave_range: float = definition.area_at(level)
			for index: int in range(12):
				var side: float = -1.0 if index % 2 == 0 else 1.0
				var row_index: int = floori(float(index) / 2.0)
				result.append(Vector2(
					side * wave_range * (0.45 + 0.07 * float(row_index)),
					wave_range * 0.05 * float(index % 3 - 1),
				))
		&"directional_needle":
			for index: int in range(12):
				result.append(Vector2(
					1.5 + 0.55 * float(index),
					0.12 * float(index % 3 - 1),
				))
		&"arc_crystal":
			for index: int in range(12):
				result.append(Vector2.from_angle(TAU * float(index) / 12.0) * 3.0)
		&"orbital_array":
			var orbit_radius: float = maxf(1.0, definition.area_at(level))
			for index: int in range(12):
				result.append(
					Vector2.from_angle(TAU * float(index) / 12.0) * orbit_radius
				)
		&"zero_field":
			var aura_radius: float = definition.area_at(level) * 0.65
			for index: int in range(12):
				result.append(
					Vector2.from_angle(TAU * float(index) / 12.0) * aura_radius
				)
		_:
			for index: int in range(12):
				result.append(Vector2.from_angle(TAU * float(index) / 12.0) * 3.5)
	return result


func _normalized_role_score(raw_dps: float, fixture_kind: FixtureKind) -> float:
	return raw_dps / GROUP_TARGET_COUNT if fixture_kind == FixtureKind.GROUP else raw_dps


func _score_values(scores: Dictionary) -> Array[float]:
	var result: Array[float] = []
	for score: Variant in scores.values():
		result.append(float(score))
	return result


func _select_scores(
	scores: Dictionary,
	lineage_ids: Array[StringName],
) -> Dictionary[StringName, float]:
	var result: Dictionary[StringName, float] = {}
	for lineage_id: StringName in lineage_ids:
		result[lineage_id] = float(scores[lineage_id])
	return result


func _median(values: Array[float]) -> float:
	var sorted_values: Array[float] = values.duplicate()
	sorted_values.sort()
	var middle_index: int = floori(float(sorted_values.size()) / 2.0)
	if sorted_values.size() % 2 == 1:
		return sorted_values[middle_index]
	return (sorted_values[middle_index - 1] + sorted_values[middle_index]) * 0.5


func _role_fixture(lineage_id: StringName) -> FixtureKind:
	match lineage_id:
		&"homing_core":
			return FixtureKind.SINGLE
		&"returning_ring", &"mass_projectile":
			return FixtureKind.BOSS
	return FixtureKind.GROUP
