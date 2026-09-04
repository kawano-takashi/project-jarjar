extends RefCounted


const UNIT_LABELS: PackedStringArray = [
	"player",
	"pursuer",
	"swarmer",
	"shooter",
	"bulwark",
	"elite",
	"boss",
]
const ENEMY_IDS: Array[StringName] = [
	&"pursuer",
	&"swarmer",
	&"shooter",
	&"bulwark",
	&"elite",
	&"boss",
]
const EXPECTED_SPEEDS: Array[float] = [
	4.05,
	1.944,
	5.184,
	2.43,
	1.0935,
	1.62,
	1.296,
]
const CONTACT_FIXTURE_MAX_TICKS: int = 600
const CONTACT_FIXTURE_SEED: int = 12_120
const CONTACT_FIXTURE_SEGMENT_INDEX: int = 1
const ESCAPE_DIRECTION_COUNT: int = 32


func test_names() -> PackedStringArray:
	return PackedStringArray([
		"movement_speeds_match_approved_values",
		"player_and_regular_enemies_travel_their_configured_sixty_tick_distance",
		"player_and_enemy_world_directions_keep_equal_speed",
		"all_level_one_weapons_kill_a_swarmer_before_contact",
	])


func run_test(test_name: String, assertions: Variant, _context: Dictionary) -> void:
	match test_name:
		"movement_speeds_match_approved_values":
			_test_speed_values(assertions)
		"player_and_regular_enemies_travel_their_configured_sixty_tick_distance":
			_test_sixty_tick_distances(assertions)
		"player_and_enemy_world_directions_keep_equal_speed":
			_test_world_direction_speed(assertions)
		"all_level_one_weapons_kill_a_swarmer_before_contact":
			_test_level_one_weapon_contact_fixture(assertions)
		_:
			assertions.expect_true(false, "registered movement-speed test")


func _test_speed_values(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	if catalog == null:
		return
	var current_speeds: Array[float] = [CombatSimulation.PLAYER_SPEED]
	for enemy_id: StringName in ENEMY_IDS:
		current_speeds.append(catalog.enemy(enemy_id).move_speed)
	for index: int in range(current_speeds.size()):
		assertions.expect_float(
			EXPECTED_SPEEDS[index],
			current_speeds[index],
			"%s speed matches its approved definition" % UNIT_LABELS[index],
		)


func _test_sixty_tick_distances(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	if catalog == null:
		return
	var player_simulation := CombatSimulation.new()
	for _tick: int in range(RunState.TICKS_PER_SECOND):
		player_simulation._move_player(Vector2.RIGHT)
	assertions.expect_float(
		CombatSimulation.PLAYER_SPEED,
		player_simulation.player_position.x,
		"player travels its configured distance in sixty ticks",
	)

	var state: RunState = RunStateFactory.create(11001, catalog)
	var system := EnemySystem.new()
	system.initialize(state, catalog)
	var enemies_by_id: Dictionary[StringName, EnemyEntity] = {}
	for enemy_id: StringName in ENEMY_IDS:
		var definition: EnemyDefinition = catalog.enemy(enemy_id)
		var enemy: EnemyEntity = system.enemy_store.try_spawn(
			state,
			definition.enemy_type,
			definition,
			Vector2(-5.0, 0.0),
			1.0,
			1.0,
			0,
		)
		assertions.expect_true(enemy != null, "%s distance fixture spawns" % enemy_id)
		if enemy != null:
			enemies_by_id[enemy_id] = enemy
	var ids: Array[int] = system.snapshot_ids()
	for tick: int in range(1, RunState.TICKS_PER_SECOND + 1):
		state.combat_tick = tick
		system.advance_snapshot(ids, Vector2(5.0, 0.0), tick)
	for enemy_id: StringName in ENEMY_IDS:
		var enemy: EnemyEntity = enemies_by_id.get(enemy_id) as EnemyEntity
		if enemy == null:
			continue
		assertions.expect_float(
			enemy.definition.move_speed,
			enemy.position.x + 5.0,
			"%s travels its configured distance in sixty ticks" % enemy_id,
		)


func _test_world_direction_speed(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	if catalog == null:
		return
	var directions: Array[Vector2] = [
		Vector2.RIGHT,
		Vector2.LEFT,
		Vector2.UP,
		Vector2.DOWN,
		Vector2.ONE,
	]
	var direction_labels: PackedStringArray = ["right", "left", "up", "down", "diagonal"]
	for index: int in range(directions.size()):
		var direction: Vector2 = directions[index]
		var player_simulation := CombatSimulation.new()
		for _tick: int in range(RunState.TICKS_PER_SECOND):
			player_simulation._move_player(direction)
		assertions.expect_float(
			CombatSimulation.PLAYER_SPEED,
			player_simulation.player_position.length(),
			"player %s movement has equal world-space speed" % direction_labels[index],
		)

		var state: RunState = RunStateFactory.create(11100 + index, catalog)
		var system := EnemySystem.new()
		system.initialize(state, catalog)
		var definition: EnemyDefinition = catalog.enemy(&"pursuer")
		var enemy: EnemyEntity = system.enemy_store.try_spawn(
			state,
			definition.enemy_type,
			definition,
			Vector2.ZERO,
			1.0,
			1.0,
			0,
		)
		var ids: Array[int] = [enemy.entity_id]
		var target_position: Vector2 = direction.normalized() * 10.0
		for tick: int in range(1, RunState.TICKS_PER_SECOND + 1):
			state.combat_tick = tick
			system.advance_snapshot(ids, target_position, tick)
		assertions.expect_float(
			definition.move_speed,
			enemy.position.length(),
			"enemy %s movement has equal world-space speed" % direction_labels[index],
		)
	var analog_simulation := CombatSimulation.new()
	for _tick: int in range(RunState.TICKS_PER_SECOND):
		analog_simulation._move_player(Vector2(0.3, 0.4))
	assertions.expect_float(
		CombatSimulation.PLAYER_SPEED * 0.5,
		analog_simulation.player_position.length(),
		"sub-unit analog input preserves magnitude without normalization",
	)


func _test_level_one_weapon_contact_fixture(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	if catalog == null:
		return
	var segment: EnemySegmentDefinition = catalog.segment(CONTACT_FIXTURE_SEGMENT_INDEX)
	var swarmer_definition: EnemyDefinition = catalog.enemy(&"swarmer")
	assertions.expect_true(segment != null, "the 1:00-2:00 segment exists")
	assertions.expect_true(swarmer_definition != null, "the normal swarmer definition exists")
	if segment == null or swarmer_definition == null:
		return
	var effective_hp: float = swarmer_definition.base_hp * segment.hp_multiplier
	assertions.expect_float(0.215, segment.hp_multiplier, "fixture uses the actual 1:00-2:00 HP multiplier")
	assertions.expect_float(1.935, effective_hp, "fixture swarmer has the actual 1:00-2:00 HP")
	assertions.expect_float(5.184, swarmer_definition.move_speed, "fixture swarmer uses speed")
	assertions.expect_float(0.26, swarmer_definition.body_radius, "fixture preserves the normal swarmer body radius")
	assertions.expect_float(4.0, swarmer_definition.contact_damage, "fixture preserves normal contact damage")
	assertions.expect_float(10.0, CombatEnvelope.SPAWN_INNER_HALF_EXTENT, "fixture starts at the minimum spawn distance")
	assertions.expect_equal(21, CombatEnvelope.NORMAL_ENTRY_TICKS, "fixture uses the standard normal-enemy entry wait")

	var weapon_ids: Array[StringName] = catalog.basic_weapon_ids()
	assertions.expect_equal(8, weapon_ids.size(), "fixture covers every basic weapon")
	for weapon_id: StringName in weapon_ids:
		var result: Dictionary = _run_level_one_contact_fixture(
			catalog,
			weapon_id,
			segment,
			swarmer_definition,
		)
		var label: String = str(weapon_id)
		assertions.expect_true(bool(result.get("spawned", false)), "%s fixture spawns exactly one normal swarmer" % label)
		if not bool(result.get("spawned", false)):
			continue
		assertions.expect_equal(1, int(result["weapon_count"]), "%s is the only equipped weapon" % label)
		assertions.expect_equal(0, int(result["passive_count"]), "%s fixture has no passive" % label)
		assertions.expect_equal(1, int(result["weapon_level"]), "%s remains level one" % label)
		assertions.expect_equal(
			int(result["base_cooldown_ticks"]),
			int(result["starting_cooldown_ticks"]),
			"%s starts with its full level-one base cooldown" % label,
		)
		assertions.expect_equal(21, int(result["entry_ticks"]), "%s swarmer waits the standard twenty-one ticks" % label)
		assertions.expect_float(10.0, float(result["spawn_distance"]), "%s swarmer starts ten metres away" % label)
		assertions.expect_float(effective_hp, float(result["effective_hp"]), "%s swarmer uses effective HP 1.935" % label)
		assertions.expect_float(5.184, float(result["move_speed"]), "%s swarmer keeps speed" % label)
		assertions.expect_equal(1, int(result["peak_enemy_count"]), "%s fixture never introduces another enemy" % label)
		assertions.expect_true(int(result["ticks_elapsed"]) <= CONTACT_FIXTURE_MAX_TICKS, "%s resolves within six hundred ticks" % label)
		assertions.expect_equal(1, int(result["weapon_kills"]), "%s records a weapon kill" % label)
		assertions.expect_true(float(result["weapon_damage"]) > 0.0, "%s deals weapon damage" % label)
		assertions.expect_false(bool(result["enemy_remaining"]), "%s kills the fixture swarmer" % label)
		assertions.expect_equal(0, int(result["geometric_contacts"]), "%s kills before geometric contact" % label)
		assertions.expect_equal(0, int(result["player_damage_ticks"]), "%s causes no player-damage tick" % label)
		assertions.expect_float(0.0, float(result["player_damage"]), "%s causes zero player damage" % label)


func _run_level_one_contact_fixture(
	catalog: DefinitionCatalog,
	weapon_id: StringName,
	segment: EnemySegmentDefinition,
	swarmer_definition: EnemyDefinition,
) -> Dictionary:
	var state: RunState = RunStateFactory.create(
		SeedService.derive(CONTACT_FIXTURE_SEED, weapon_id),
		catalog,
	)
	state.weapons.clear()
	state.passives.clear()
	state.combat_tick = RunState.BOSS_START_TICK
	state.boss_spawned = true
	state.boss_transition_started = true
	state.build_maxed = true
	var weapon_definition: WeaponDefinition = catalog.weapon(weapon_id)
	var runtime: RunWeapon = RunWeapon.create(
		weapon_definition.weapon_id,
		weapon_definition.lineage_id,
		false,
		state.rng_streams.create_weapon_rng(weapon_definition.lineage_id, 0),
	)
	runtime.level = 1
	runtime.ready_on_resume = false
	runtime.cooldown_remaining_ticks = weapon_definition.cooldown_ticks_at(1)
	state.weapons.append(runtime)

	var simulation := CombatSimulation.new()
	simulation.initialize(state, catalog)
	simulation.enemy_system._elite_spawned.fill(1)
	var enemy: EnemyEntity = simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.SWARMER,
		Vector2.RIGHT * CombatEnvelope.SPAWN_INNER_HALF_EXTENT,
		state.combat_tick,
		false,
		false,
	)
	if enemy == null:
		return {"spawned": false}
	var fixture_definition: EnemyDefinition = swarmer_definition.duplicate(true) as EnemyDefinition
	enemy.definition = fixture_definition
	enemy.max_hp = fixture_definition.base_hp * segment.hp_multiplier
	enemy.hp = enemy.max_hp
	enemy.damage_multiplier = (
		segment.damage_multiplier * catalog.manifest().normal_enemy_damage_scale
	)
	var enemy_id: int = enemy.entity_id
	var entry_ticks: int = enemy.activation_tick - enemy.spawn_tick
	var spawn_distance: float = simulation.player_position.distance_to(enemy.position)
	var starting_hp: float = state.current_hp
	var starting_tick: int = state.combat_tick
	var starting_cooldown_ticks: int = runtime.cooldown_remaining_ticks
	var geometric_contacts: int = 0
	var player_damage_ticks: int = 0
	var peak_enemy_count: int = simulation.enemy_system.enemy_store.entities.size()

	for _tick_index: int in range(CONTACT_FIXTURE_MAX_TICKS):
		var live_enemy: EnemyEntity = simulation.enemy_system.enemy_store.get_by_id(enemy_id)
		if live_enemy == null:
			break
		var move_input: Vector2 = _contact_fixture_move_input(
			simulation,
			live_enemy,
			runtime,
			weapon_definition,
		)
		var next_tick: int = state.combat_tick + 1
		var projected_player: Vector2 = _project_fixture_player(
			simulation.player_position,
			move_input,
		)
		var projected_enemy: Vector2 = _project_fixture_enemy(
			live_enemy,
			projected_player,
			next_tick,
		)
		var contact_radius: float = CombatEnvelope.PLAYER_BODY_RADIUS + live_enemy.body_radius()
		if projected_player.distance_squared_to(projected_enemy) <= contact_radius * contact_radius:
			geometric_contacts += 1
		simulation.advance_tick(move_input)
		if simulation._player_hit_this_tick:
			player_damage_ticks += 1
		peak_enemy_count = maxi(
			peak_enemy_count,
			simulation.enemy_system.enemy_store.entities.size(),
		)

	return {
		"spawned": true,
		"weapon_count": state.weapons.size(),
		"passive_count": state.passives.size(),
		"weapon_level": runtime.level,
		"base_cooldown_ticks": weapon_definition.cooldown_ticks_at(1),
		"starting_cooldown_ticks": starting_cooldown_ticks,
		"entry_ticks": entry_ticks,
		"spawn_distance": spawn_distance,
		"effective_hp": fixture_definition.base_hp * segment.hp_multiplier,
		"move_speed": fixture_definition.move_speed,
		"peak_enemy_count": peak_enemy_count,
		"ticks_elapsed": state.combat_tick - starting_tick,
		"weapon_kills": state.weapon_kill_count,
		"weapon_damage": float(state.weapon_damage_by_lineage.get(weapon_definition.lineage_id, 0.0)),
		"enemy_remaining": simulation.enemy_system.enemy_store.has_entity(enemy_id),
		"geometric_contacts": geometric_contacts,
		"player_damage_ticks": player_damage_ticks,
		"player_damage": starting_hp - state.current_hp,
	}


func _contact_fixture_move_input(
	simulation: CombatSimulation,
	enemy: EnemyEntity,
	runtime: RunWeapon,
	weapon_definition: WeaponDefinition,
) -> Vector2:
	var escape_direction: Vector2 = _wall_aware_escape_direction(simulation, enemy)
	if weapon_definition.behavior not in [
		GameTypes.WeaponBehavior.MELEE_WAVE,
		GameTypes.WeaponBehavior.DIRECTIONAL_PROJECTILE,
	]:
		return escape_direction
	if runtime.ready_on_resume or runtime.cooldown_remaining_ticks > 1:
		return escape_direction
	var next_tick: int = simulation.state.combat_tick + 1
	if not enemy.is_targetable(next_tick):
		return escape_direction
	var aim_direction: Vector2 = enemy.position - simulation.player_position
	if aim_direction == Vector2.ZERO:
		return escape_direction
	aim_direction = aim_direction.normalized()
	var aimed_player: Vector2 = _project_fixture_player(
		simulation.player_position,
		aim_direction,
	)
	var aimed_enemy: Vector2 = _project_fixture_enemy(enemy, aimed_player, next_tick)
	if weapon_definition.behavior == GameTypes.WeaponBehavior.MELEE_WAVE:
		return aim_direction
	if aimed_player.distance_squared_to(aimed_enemy) <= (
		CombatEnvelope.TARGET_CENTER_RADIUS * CombatEnvelope.TARGET_CENTER_RADIUS
	):
		return aim_direction
	return escape_direction


func _wall_aware_escape_direction(
	simulation: CombatSimulation,
	enemy: EnemyEntity,
) -> Vector2:
	var best_direction: Vector2 = Vector2.ZERO
	var best_distance_squared: float = -1.0
	var best_interior_clearance: float = -1.0
	var next_tick: int = simulation.state.combat_tick + 1
	for direction_index: int in range(ESCAPE_DIRECTION_COUNT):
		var direction: Vector2 = Vector2.from_angle(
			TAU * float(direction_index) / float(ESCAPE_DIRECTION_COUNT)
		)
		var next_player: Vector2 = _project_fixture_player(
			simulation.player_position,
			direction,
		)
		var intended_step: float = CombatSimulation.PLAYER_SPEED / float(RunState.TICKS_PER_SECOND)
		if not is_equal_approx(
			simulation.player_position.distance_to(next_player),
			intended_step,
		):
			continue
		var next_enemy: Vector2 = _project_fixture_enemy(enemy, next_player, next_tick)
		var distance_squared: float = next_player.distance_squared_to(next_enemy)
		var interior_clearance: float = minf(
			minf(
				next_player.x - CombatSimulation.ARENA_MIN.x,
				CombatSimulation.ARENA_MAX.x - next_player.x,
			),
			minf(
				next_player.y - CombatSimulation.ARENA_MIN.y,
				CombatSimulation.ARENA_MAX.y - next_player.y,
			),
		)
		if (
			distance_squared > best_distance_squared
			or (
				is_equal_approx(distance_squared, best_distance_squared)
				and interior_clearance > best_interior_clearance
			)
		):
			best_direction = direction
			best_distance_squared = distance_squared
			best_interior_clearance = interior_clearance
	if best_direction != Vector2.ZERO:
		return best_direction
	return (Vector2.ZERO - simulation.player_position).normalized()


func _project_fixture_player(position: Vector2, move_input: Vector2) -> Vector2:
	var normalized_input: Vector2 = move_input
	if normalized_input.length_squared() > 1.0:
		normalized_input = normalized_input.normalized()
	var next_position: Vector2 = (
		position
		+ normalized_input * CombatSimulation.PLAYER_SPEED / float(RunState.TICKS_PER_SECOND)
	)
	return Vector2(
		clampf(next_position.x, CombatSimulation.ARENA_MIN.x, CombatSimulation.ARENA_MAX.x),
		clampf(next_position.y, CombatSimulation.ARENA_MIN.y, CombatSimulation.ARENA_MAX.y),
	)


func _project_fixture_enemy(
	enemy: EnemyEntity,
	player_position: Vector2,
	next_tick: int,
) -> Vector2:
	if not enemy.is_targetable(next_tick):
		return enemy.position
	var offset: Vector2 = player_position - enemy.position
	var next_position: Vector2 = enemy.position
	if offset != Vector2.ZERO:
		next_position += (
			offset.normalized()
			* enemy.definition.move_speed
			/ float(RunState.TICKS_PER_SECOND)
		)
	var center_limit: float = CombatEnvelope.enemy_center_limit(enemy.body_radius())
	if absf(enemy.position.x) <= center_limit and absf(enemy.position.y) <= center_limit:
		next_position = Vector2(
			clampf(next_position.x, -center_limit, center_limit),
			clampf(next_position.y, -center_limit, center_limit),
		)
	return next_position


func _catalog(assertions: Variant) -> DefinitionCatalog:
	var catalog := DefinitionCatalog.new()
	assertions.expect_true(
		catalog.load_and_validate(),
		"movement catalog validates: %s" % catalog.error_text,
	)
	return catalog if catalog.is_valid else null
