extends RefCounted


enum FixtureKind { SINGLE, GROUP, BOSS }

const MEASURE_TICKS: int = 600
const GROUP_TARGET_COUNT: float = 12.0
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

func test_names() -> PackedStringArray:
	return PackedStringArray([
		"survival_weapon_dps_matrix_revision_five_contract",
	])


func run_test(test_name: String, assertions: Variant, _context: Dictionary) -> void:
	match test_name:
		"survival_weapon_dps_matrix_revision_five_contract":
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
			stationary_level_one_score > 0.0,
			"%s Lv1 resolves positive stationary-target damage" % base_id,
		)
		assertions.expect_true(
			stationary_level_eight_score >= stationary_level_one_score,
			"%s Lv8 stationary-target damage does not regress" % base_id,
		)
		assertions.expect_true(
			moving_level_one_score > 0.0 and moving_level_eight_score > 0.0,
			"%s base levels resolve positive moving-target damage" % base_id,
		)
		assertions.expect_true(
			moving_evolved_score >= moving_level_eight_score * ROLE_EVOLUTION_RATIO,
			"%s evolution reaches at least 1.5x its moving-target Lv8 role score (%.2f -> %.2f)" % [
				base_id,
				moving_level_eight_score,
				moving_evolved_score,
			],
		)
	assertions.expect_equal(
		1,
		catalog.weapon(&"infinite_homing").cooldown_ticks_at(1),
		"infinite homing retains its one-tick cadence",
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
	state.boss_transition_started = true
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
			var wave_range: float = definition.range_at(level)
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
			var orbit_radius: float = maxf(1.0, definition.range_at(level))
			for index: int in range(12):
				result.append(
					Vector2.from_angle(TAU * float(index) / 12.0) * orbit_radius
				)
		&"zero_field":
			var aura_radius: float = definition.effect_radius_at(level) * 0.65
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
