extends RefCounted


func test_enemy_bodies_share_equal_separation_across_types_and_sizes(a: Variant, _context: Dictionary) -> void:
	var sim: CombatSimulation = _simulation()
	var content: SurvivalContentManifest = sim.catalog.manifest()
	var small: EnemyDefinition = sim.catalog.enemy(&"pursuer").duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as EnemyDefinition
	small.body_radius = 0.5
	var definitions: Array[EnemyDefinition] = content.enemies.duplicate()
	definitions.append(content.encounters.unit_definition)
	definitions.append(content.swarm_event.unit_definition)
	for definition: EnemyDefinition in definitions:
		for radius: float in [0.5, 1.0]:
			sim.enemy_system.enemy_store.clear()
			definition.body_radius = radius
			var first: EnemyEntity = _spawn(sim, small, Vector2(-2.25, 3.0))
			var second_start := Vector2(-2.25 + radius, 3.0)
			var second: EnemyEntity = _spawn(sim, definition, second_start)
			if definition == content.encounters.unit_definition:
				second.encounter_owner_id = 999
			elif definition == content.swarm_event.unit_definition:
				second.configure_swarm_event(1, Vector2.RIGHT, 10.0, false)
			sim.state.combat_tick = 1
			sim.enemy_system.advance_snapshot(sim.enemy_system.snapshot_ids(), Vector2.ZERO, 1)
			# Each pair starts with half a metre of overlap, across a negative grid boundary.
			a.expect_true(first.position.is_equal_approx(Vector2(-2.5, 3.0)), "%s gives half the overlap to the small body" % definition.enemy_id)
			a.expect_true(second.position.is_equal_approx(second_start + Vector2(0.25, 0.0)), "%s receives the same correction regardless of size or role" % definition.enemy_id)


func test_coincident_stopped_crowds_separate_deterministically_without_actions(a: Variant, _context: Dictionary) -> void:
	var first: CombatSimulation = _simulation()
	var replay: CombatSimulation = _simulation()
	for sim: CombatSimulation in [first, replay]:
		var definition: EnemyDefinition = sim.catalog.enemy(&"pursuer")
		definition.move_speed = 3.0
		sim.state.stop_until_tick = 100
		for _index: int in 12:
			_spawn(sim, definition, Vector2(0.0, 4.0))
	var first_ids: Array[int] = first.enemy_system.snapshot_ids()
	var reversed_ids: Array[int] = replay.enemy_system.snapshot_ids()
	reversed_ids.reverse()
	var rng_before: Dictionary = first.state.rng_streams.state_digest()
	for tick: int in range(1, 9):
		first.state.combat_tick = tick
		replay.state.combat_tick = tick
		first.enemy_system.advance_snapshot(first_ids, Vector2.ZERO, tick)
		replay.enemy_system.advance_snapshot(reversed_ids, Vector2.ZERO, tick)
	var moved: bool = false
	for entity_id: int in first_ids:
		var enemy: EnemyEntity = first.enemy_system.enemy_store.get_by_id(entity_id)
		var repeated: EnemyEntity = replay.enemy_system.enemy_store.get_by_id(entity_id)
		a.expect_equal(enemy.position, repeated.position, "input iteration order does not change separation")
		a.expect_true(is_finite(enemy.position.x) and is_finite(enemy.position.y), "coincident bodies remain finite")
		moved = moved or enemy.position != Vector2(0.0, 4.0)
	a.expect_true(moved, "STOP preserves passive crowd separation")
	a.expect_equal(rng_before, first.state.rng_streams.state_digest(), "separation consumes no gameplay randomness")
	var contact_position: Vector2 = first.enemy_system.enemy_store.get_by_id(first_ids[0]).position
	a.expect_true(first.enemy_system.resolve_contact_damage_candidates(first_ids, contact_position, 8).is_empty(), "pushed stopped enemies still cannot deal contact damage")


func test_collision_snapshot_excludes_entry_and_retired_ids_before_slot_reuse(a: Variant, _context: Dictionary) -> void:
	var sim: CombatSimulation = _simulation()
	var system: EnemySystem = sim.enemy_system
	var definition: EnemyDefinition = sim.catalog.enemy(&"pursuer")
	var active: EnemyEntity = _spawn(sim, definition, Vector2(-2.0, 3.0))
	var entering: EnemyEntity = _spawn(sim, definition, Vector2(-1.5, 3.0))
	entering.activation_tick = 3
	var retired: EnemyEntity = _spawn(sim, definition, Vector2(-2.0, 3.0))
	var retired_id: int = retired.entity_id
	var retired_slot: int = retired.pool_index
	var ids: Array[int] = system.snapshot_ids()
	system.enemy_store.remove(retired_id)
	var replacement: EnemyEntity = _spawn(sim, definition, Vector2(-2.0, 3.0))
	a.expect_equal(retired_slot, replacement.pool_index, "fixture reuses the retired body slot")
	sim.state.combat_tick = 1
	system.advance_snapshot(ids, Vector2.ZERO, 1)
	a.expect_equal(Vector2(-2.0, 3.0), active.position, "entering and post-snapshot bodies do not push")
	a.expect_equal(Vector2(-1.5, 3.0), entering.position, "entry protection also prevents passive displacement")
	sim.state.combat_tick = 2
	system.advance_snapshot(system.snapshot_ids(), Vector2.ZERO, 2)
	a.expect_float(2.0, active.position.distance_to(replacement.position), "the new identity participates in the next snapshot")
	sim.state.combat_tick = 3
	system.advance_snapshot(system.snapshot_ids(), Vector2.ZERO, 3)
	a.expect_not_equal(Vector2(-1.5, 3.0), entering.position, "the entering body participates on its activation tick")
	a.expect_false(system.uniform_grid.query_circle_candidates(Vector2.ZERO, 10.0, 0.0).has(retired_id), "the rebuilt grid retains no retired identity")


func test_rebased_collision_positions_feed_rendering_contact_and_weapons(a: Variant, _context: Dictionary) -> void:
	var sim: CombatSimulation = _simulation()
	var small: EnemyDefinition = sim.catalog.enemy(&"pursuer")
	small.body_radius = 0.5
	sim.player_position = Vector2(1024.0, 1024.0)
	sim.view.reset(sim.player_position)
	var first: EnemyEntity = _spawn(sim, small, Vector2(1024.125, 1027.0))
	_spawn(sim, sim.catalog.enemy(&"bulwark"), Vector2(1024.625, 1027.0))
	sim.advance_tick(Vector2.ZERO)
	a.expect_equal(Vector2i(1, 1), sim.world_origin, "collision participates in the normal origin-shift path")
	a.expect_equal(Vector2(-0.375, 3.0), first.position, "separation remains correct after rebasing")
	a.expect_equal([first.entity_id], sim.enemy_system.uniform_grid.query_circle_candidates(first.position, 0.0, 0.0), "the moved body is indexed in its new cell")
	var snapshot: CombatSnapshot = sim.build_snapshot()
	var rendered: Vector3 = snapshot.enemy_transforms[0].origin
	a.expect_equal(first.position, Vector2(rendered.x, rendered.z), "rendering consumes the corrected position")
	var contact_position := Vector2(-1.1, 3.0)
	var ids: Array[int] = sim.enemy_system.uniform_grid.query_circle_candidates(contact_position, sim.envelope.player_body_radius, sim.catalog.maximum_enemy_body_radius)
	var contacts: Array[Dictionary] = sim.enemy_system.resolve_contact_damage_candidates(ids, contact_position, sim.state.combat_tick)
	a.expect_equal(1, contacts.size(), "contact damage sees the body pushed into contact range")
	if not contacts.is_empty():
		a.expect_equal(first.entity_id, contacts[0]["source_entity_id"], "the displaced body supplies the contact")
	var impact := Vector2(-0.825, 3.0)
	var projectile: ProjectileState = sim.projectile_pool.acquire(
		ProjectileState.FACTION_ALLY, &"directional_needle", -1,
		impact, Vector2.ZERO, 0.05, 1.0, 1.0, 1.0, impact, 1, 0,
	)
	var hits: Array[Dictionary] = sim.weapon_system.resolve_ally_projectile(
		PackedInt64Array([projectile.pool_index, projectile.generation]), sim.enemy_system.enemy_store,
		sim.enemy_system.uniform_grid, sim.player_position, sim.state.combat_tick,
	)
	a.expect_equal(1, hits.size(), "a weapon hits the corrected body beyond its old collision circle")
	if not hits.is_empty():
		a.expect_equal(first.entity_id, hits[0]["entity_id"], "the displaced body receives the weapon hit")


func _simulation() -> CombatSimulation:
	var content: SurvivalContentManifest = BalanceTestFixtures.manifest()
	var definitions: Array[EnemyDefinition] = content.enemies.duplicate()
	definitions.append(content.encounters.unit_definition)
	definitions.append(content.swarm_event.unit_definition)
	for definition: EnemyDefinition in definitions:
		definition.move_speed = 0.0
		definition.body_radius = 1.0
	var catalog := DefinitionCatalog.new()
	assert(catalog.validate_manifest(content), catalog.error_text)
	var sim := CombatSimulation.new()
	sim.initialize(RunStateFactory.create(15001, catalog), catalog)
	sim.state.weapons.clear()
	return sim


func _spawn(sim: CombatSimulation, definition: EnemyDefinition, position: Vector2) -> EnemyEntity:
	return sim.enemy_system.enemy_store.try_spawn(sim.state, definition.enemy_type, definition, position, 1.0, 1.0, 0)
