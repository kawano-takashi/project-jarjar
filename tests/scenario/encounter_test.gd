extends RefCounted


func test_elite_encounter_reserves_capacity_once_and_expires_during_stop(a: Variant, _context: Dictionary) -> void:
	var sim: CombatSimulation = _simulation()
	var system: EnemySystem = sim.enemy_system
	var definition: EncounterBalanceDefinition = sim.catalog.manifest().encounters
	var tick: int = sim.catalog.elite_spawn_ticks[0]
	sim.state.combat_tick = tick
	sim.state.level = 3
	var near_enemy: EnemyEntity = sim.spawn_fixture_enemy(GameTypes.EnemyType.PURSUER, Vector2.ONE)
	var near_id: int = near_enemy.entity_id
	for index: int in range(system.enemy_store.capacity - 1):
		sim.spawn_fixture_enemy(GameTypes.EnemyType.PURSUER, Vector2(100.0 + index, 0.0))
	var scheduled: Array[EnemyEntity] = system.resolve_scheduled_spawns(sim.player_position, tick)
	a.expect_equal(1, scheduled.size(), "a full pool reserves the entire encounter atomically")
	if scheduled.is_empty():
		return
	var elite: EnemyEntity = scheduled[0]
	var members: Array[EnemyEntity] = _members(sim)
	a.expect_equal(definition.member_count, members.size(), "all ring members spawn together")
	a.expect_true(system.enemy_store.has_entity(near_id), "capacity retires distant ordinary enemies first")
	a.expect_equal(system.enemy_store.capacity - definition.member_count - 1, system._normal_enemy_count(), "ring members do not consume the normal target")
	a.expect_equal(0, sim.state.total_kills, "capacity retirement has no kill rewards")
	a.expect_equal(0, sim.xp_pickup_pool.total_value(), "capacity retirement drops no XP")
	a.expect_float(definition.opponent_distance, elite.position.distance_to(sim.player_position), "opponent starts safely inside the ring")
	for member: EnemyEntity in members:
		a.expect_float(definition.unit_definition.base_hp * sim.state.level, member.hp, "ring HP uses spawn level without segment HP scaling")
		a.expect_equal(elite.activation_tick, member.activation_tick, "owner and ring share entry protection")
		a.expect_false(member.is_targetable(tick), "materializing ring is harmless and untargetable")
	var expiry: int = elite.activation_tick + definition.elite_lifetime_ticks
	elite.position = Vector2(1000.0, 0.0)
	system.advance_snapshot([elite.entity_id], sim.player_position, tick + 1)
	a.expect_equal(0, system.resolve_scheduled_spawns(sim.player_position, tick + 1).size(), "repositioning an elite does not recreate its encounter")
	a.expect_equal(definition.member_count, _members(sim).size(), "no replacement members are added")
	sim.state.combat_tick = expiry - 2
	sim.state.stop_until_tick = expiry + 100
	# Isolate self-propelled pursuit: stopped bodies can still be pushed.
	members[0].position = Vector2(0.0, 4.0)
	var member_position: Vector2 = members[0].position
	sim.advance_tick(Vector2.ZERO)
	a.expect_equal(member_position, members[0].position, "STOP freezes ring pursuit")
	a.expect_equal(definition.member_count, _members(sim).size(), "ring survives its final lifetime tick")
	sim.state.phase = GameTypes.RunPhase.LEVEL_UP
	a.expect_false(sim.advance_tick(Vector2.ZERO), "modal pauses encounter clock")
	sim.state.phase = GameTypes.RunPhase.COMBAT
	sim.advance_tick(Vector2.ZERO)
	a.expect_equal(0, _members(sim).size(), "lifetime expires during STOP without a reward")
	a.expect_equal(0, sim.state.total_kills, "expiry is not a kill")


func test_encirclers_allow_crossing_and_only_killed_members_drop_xp(a: Variant, _context: Dictionary) -> void:
	var sim: CombatSimulation = _simulation()
	var tick: int = sim.catalog.elite_spawn_ticks[0]
	sim.state.combat_tick = tick
	var elite: EnemyEntity = sim.enemy_system.resolve_scheduled_spawns(Vector2.ZERO, tick)[0]
	var members: Array[EnemyEntity] = _members(sim)
	var crossed: EnemyEntity = members[0]
	crossed.position = Vector2.ZERO
	sim.player_position = Vector2(-1.4, 0.0)
	sim.state.combat_tick = elite.activation_tick
	var hp_before: float = sim.state.current_hp
	for index: int in 50:
		sim.advance_tick(Vector2.RIGHT)
	a.expect_true(sim.player_position.x > crossed.position.x + crossed.body_radius(), "walking crosses an intact ring member")
	a.expect_true(sim.state.current_hp < hp_before, "crossing uses normal contact damage")
	a.expect_equal(0, sim.state.total_kills, "crossing alone grants no kill")
	var member_xp: int = crossed.definition.xp_value
	var elite_xp: int = elite.definition.xp_value
	# Simultaneous deaths must resolve before surviving members are retired.
	crossed.hp = 0.0
	elite.hp = 0.0
	sim._record_enemy_death(elite, &"homing_core")
	sim._record_enemy_death(crossed, &"homing_core")
	sim._process_pending_deaths(sim.state.combat_tick)
	sim.enemy_system.encounters.retire_finished_groups(sim.state.combat_tick, sim.enemy_system.enemy_store)
	a.expect_equal(2, sim.state.total_kills, "only the two actual deaths count")
	a.expect_equal(0, sim.state.normal_kills, "encircler kills are outside ordinary enemy statistics")
	a.expect_equal(elite_xp + member_xp, sim.xp_pickup_pool.total_value(), "simultaneous member kill retains its XP")
	a.expect_equal(0, _members(sim).size(), "owner death retires all survivors")
	a.expect_equal(1, sim.arena_object_system.pickups.size(), "only the elite creates a chest")


func test_boss_boundary_constrains_bodies_slides_and_stops_shrinking(a: Variant, _context: Dictionary) -> void:
	var sim: CombatSimulation = _simulation()
	sim.state.combat_tick = sim.catalog.boss_start_tick - 1
	sim.player_position = Vector2(1023.99, 0.0)
	sim.view.reset(sim.player_position)
	sim.advance_tick(Vector2.ZERO)
	var encounter: EncounterSystem = sim.enemy_system.encounters
	var boss: EnemyEntity = sim.enemy_system.boss_entity()
	var center: Vector2 = encounter.boss_center
	var player_radius: float = sim.catalog.manifest().player.body_radius
	var started_radius: float = encounter.boss_radius
	sim.state.combat_tick = boss.activation_tick
	sim.player_position = encounter.constrain_body(center + Vector2.RIGHT * started_radius, player_radius)
	boss.position = center + Vector2(100.0, 0.0)
	var before: Vector2 = sim.player_position
	sim.advance_tick(Vector2(1.0, 1.0).normalized())
	var displacement := Vector2(sim.world_origin) * CombatSimulation.ORIGIN_STEP_METERS
	a.expect_equal(Vector2i(1, 0), sim.world_origin, "boundary follows an origin shift")
	a.expect_true((encounter.boss_center + displacement).is_equal_approx(center), "origin shift preserves boundary world position")
	a.expect_true(sim.player_position.y > before.y, "an outward diagonal slides along the wall")
	a.expect_true(sim.player_position.distance_to(encounter.boss_center) + player_radius <= encounter.boss_radius + 0.001, "player body stays inside")
	a.expect_true(boss.position.distance_to(encounter.boss_center) + boss.body_radius() <= encounter.boss_radius + 0.001, "boss is constrained instead of repositioned offscreen")
	sim.state.stop_until_tick = sim.state.combat_tick + 10000
	sim.state.combat_tick = boss.activation_tick + sim.catalog.manifest().encounters.boss_shrink_ticks - 1
	sim.advance_tick(Vector2.ZERO)
	var final_radius: float = encounter.boss_radius
	a.expect_float(sim.catalog.manifest().encounters.boss_final_radius, final_radius, "shrink reaches configured final radius despite STOP")
	sim.advance_tick(Vector2.ZERO)
	a.expect_float(final_radius, encounter.boss_radius, "boundary remains at final radius")
	sim.state.current_hp = 0.0
	sim.advance_tick(Vector2.ZERO)
	a.expect_false(encounter.boss_active, "defeat clears the boundary")
	sim.initialize(RunStateFactory.create(9182, sim.catalog), sim.catalog)
	a.expect_false(sim.enemy_system.encounters.boss_active, "restart returns to the infinite field")
	sim.state.combat_tick = sim.catalog.boss_start_tick - 1
	sim.advance_tick(Vector2.ZERO)
	boss = sim.enemy_system.boss_entity()
	boss.hp = 0.0
	sim._record_enemy_death(boss, &"homing_core")
	sim._process_pending_deaths(sim.state.combat_tick)
	sim.advance_tick(Vector2.ZERO)
	a.expect_equal(GameTypes.RunPhase.RESULT, sim.state.phase, "boss death reaches victory")
	a.expect_false(sim.enemy_system.encounters.boss_active, "victory clears the boundary")


func _simulation() -> CombatSimulation:
	var catalog: DefinitionCatalog = BalanceTestFixtures.catalog()
	var sim := CombatSimulation.new()
	sim.initialize(RunStateFactory.create(9182, catalog), catalog)
	sim.state.weapons.clear()
	return sim


func _members(sim: CombatSimulation) -> Array[EnemyEntity]:
	var result: Array[EnemyEntity] = []
	for enemy: EnemyEntity in sim.enemy_system.enemy_store.entities:
		if enemy.encounter_owner_id >= 0:
			result.append(enemy)
	return result
