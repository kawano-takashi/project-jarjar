extends RefCounted


const ENEMY_IDS: Array[StringName] = [
	&"pursuer",
	&"swarmer",
	&"shooter",
	&"bulwark",
	&"elite",
	&"boss",
]


func test_player_and_regular_enemies_travel_their_configured_sixty_tick_distance(assertions: Variant, _context: Dictionary) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	if catalog == null:
		return
	var player_simulation := CombatSimulation.new()
	player_simulation.initialize(RunStateFactory.create(11001, catalog), catalog)
	for _tick: int in range(RunState.TICKS_PER_SECOND):
		player_simulation._move_player(Vector2.RIGHT)
	assertions.expect_float(
		catalog.manifest().player.move_speed,
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


func test_player_and_enemy_world_directions_keep_equal_speed(assertions: Variant, _context: Dictionary) -> void:
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
		player_simulation.initialize(RunStateFactory.create(11001, catalog), catalog)
		for _tick: int in range(RunState.TICKS_PER_SECOND):
			player_simulation._move_player(direction)
		assertions.expect_float(
			catalog.manifest().player.move_speed,
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
	analog_simulation.initialize(RunStateFactory.create(11001, catalog), catalog)
	for _tick: int in range(RunState.TICKS_PER_SECOND):
		analog_simulation._move_player(Vector2(0.3, 0.4))
	assertions.expect_float(
		catalog.manifest().player.move_speed * 0.5,
		analog_simulation.player_position.length(),
		"sub-unit analog input preserves magnitude without normalization",
	)


func _catalog(assertions: Variant) -> DefinitionCatalog:
	var catalog := DefinitionCatalog.new()
	assertions.expect_true(
		catalog.validate_manifest(BalanceTestFixtures.manifest()),
		"movement catalog validates: %s" % catalog.error_text,
	)
	return catalog if catalog.is_valid else null
