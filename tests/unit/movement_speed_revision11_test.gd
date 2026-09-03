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
const REVISION_TEN_SPEEDS: Array[float] = [
	5.0,
	2.4,
	6.4,
	3.0,
	1.35,
	2.0,
	1.6,
]


func test_names() -> PackedStringArray:
	return PackedStringArray([
		"revision_eleven_speeds_are_ten_percent_lower_with_ratios_preserved",
		"player_and_regular_enemies_travel_their_configured_sixty_tick_distance",
		"player_and_enemy_world_directions_keep_equal_speed",
	])


func run_test(test_name: String, assertions: Variant, _context: Dictionary) -> void:
	match test_name:
		"revision_eleven_speeds_are_ten_percent_lower_with_ratios_preserved":
			_test_speed_values_and_ratios(assertions)
		"player_and_regular_enemies_travel_their_configured_sixty_tick_distance":
			_test_sixty_tick_distances(assertions)
		"player_and_enemy_world_directions_keep_equal_speed":
			_test_world_direction_speed(assertions)
		_:
			assertions.expect_true(false, "registered revision eleven movement-speed test")


func _test_speed_values_and_ratios(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	if catalog == null:
		return
	assertions.expect_equal(11, catalog.balance_manifest().balance_revision, "movement tuning ships as balance revision eleven")
	var current_speeds: Array[float] = [CombatSimulation.PLAYER_SPEED]
	for enemy_id: StringName in ENEMY_IDS:
		current_speeds.append(catalog.enemy(enemy_id).move_speed)
	for index: int in range(current_speeds.size()):
		assertions.expect_float(
			REVISION_TEN_SPEEDS[index] * 0.9,
			current_speeds[index],
			"%s speed is exactly ten percent below revision ten" % UNIT_LABELS[index],
		)
	for first_index: int in range(current_speeds.size()):
		for second_index: int in range(first_index + 1, current_speeds.size()):
			assertions.expect_float(
				REVISION_TEN_SPEEDS[first_index] / REVISION_TEN_SPEEDS[second_index],
				current_speeds[first_index] / current_speeds[second_index],
				"%s/%s relative speed is unchanged"
				% [UNIT_LABELS[first_index], UNIT_LABELS[second_index]],
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


func _catalog(assertions: Variant) -> DefinitionCatalog:
	var catalog := DefinitionCatalog.new()
	assertions.expect_true(
		catalog.load_and_validate(),
		"revision eleven movement catalog validates: %s" % catalog.error_text,
	)
	return catalog if catalog.is_valid else null
