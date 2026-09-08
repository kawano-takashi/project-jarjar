extends RefCounted


func test_origin_shift_preserves_hits_loot_and_vacuum_targets(a: Variant, _context: Dictionary) -> void:
	var catalog: DefinitionCatalog = BalanceTestFixtures.catalog()
	for sign_value: float in [-1.0, 1.0]:
		var sim := CombatSimulation.new()
		sim.initialize(RunStateFactory.create(8701, catalog), catalog)
		sim.state.weapons.clear()
		sim.state.stop_until_tick = 1000
		sim.state.current_hp = 10.0
		var start := Vector2.ONE * (1023.99 * sign_value)
		sim.player_position = start
		sim.view.reset(start)
		var enemy: EnemyEntity = sim.spawn_fixture_enemy(GameTypes.EnemyType.BULWARK, start + Vector2(2, 0), -1)
		var hp: float = enemy.hp
		for node: ArenaNodeState in sim.arena_object_system.nodes:
			node.deactivate()
		var node: ArenaNodeState = sim.arena_object_system.nodes[0]
		node.activate(900, start + Vector2(1, 0), 18.0)
		sim.arena_object_system._spawn_pickup(ArenaPickup.Kind.HEAL, start, 0)
		sim.arena_object_system._spawn_pickup(ArenaPickup.Kind.VACUUM, start, 1)
		var old_xp: XpPickupState = sim.xp_pickup_pool.acquire(start + Vector2(30, 0), 7, -1, start)
		sim.projectile_pool.acquire(ProjectileState.FACTION_ALLY, &"homing_core", -1,
			start + Vector2(0.2, 0), Vector2(120, 0), 0.1, 7.0, 10.0, 10.0, start + Vector2(10, 0), 0, 0)
		var arc_start: Vector2 = start + Vector2(0, 3)
		var arc_target: Vector2 = arc_start + Vector2(6, 0)
		var arc: ProjectileState = sim.projectile_pool.acquire(ProjectileState.FACTION_ALLY, &"arc_crystal", -1,
			arc_start, Vector2(12, 0), 0.1, 1.0, 6.0, 10.0, arc_target, 0, 0, &"arc_crystal", ProjectileState.MovementKind.ARC)
		var effect: VfxState = sim.add_fixture_vfx(start + Vector2(4, 4), 1.0, Color.WHITE, 10.0)
		a.expect_true(sim.advance_tick(Vector2.ONE * sign_value), "a combat tick crosses the origin threshold")
		var displacement := Vector2(sim.world_origin) * CombatSimulation.ORIGIN_STEP_METERS
		a.expect_equal(Vector2i.ONE * int(sign_value), sim.world_origin, "both origin axes move by one unit")
		a.expect_float(hp - 7.0, enemy.hp, "the swept projectile still hits the same enemy")
		a.expect_float(11.0, node.hp, "the swept projectile still hits the same destructible")
		a.expect_true(arc.active, "the flying arc survives the origin change")
		a.expect_true(arc.previous_position.distance_to(arc_start - displacement) < 0.001, "previous projectile position shifts with the current position")
		a.expect_true(arc.target_position.distance_to(arc_target - displacement) < 0.001, "the projectile target remains on its original trajectory")
		a.expect_true(effect.position.distance_to(start + Vector2(4, 4) - displacement) < 0.001, "existing effects stay attached to their world location")
		a.expect_float(10.0 + catalog.manifest().arena.node_heal_amount, sim.state.current_hp, "healing at the crossing point is collected")
		a.expect_true(old_xp.position.distance_to(sim.player_position) < 30.0, "vacuum starts pulling pre-existing offscreen XP")
		var new_position: Vector2 = sim.player_position + Vector2(40, 0)
		var new_xp: XpPickupState = sim.xp_pickup_pool.acquire(new_position, 11, sim.state.combat_tick, sim.player_position)
		var old_distance: float = old_xp.position.distance_to(sim.player_position)
		sim.xp_pickup_pool.advance_and_collect(sim.player_position, 0.5, sim.state.combat_tick + 1)
		a.expect_true(old_xp.position.distance_to(sim.player_position) < old_distance, "marked XP continues to travel after the shift")
		a.expect_equal(new_position, new_xp.position, "vacuum does not mark future drops")
		a.expect_equal(18, sim.xp_pickup_pool.total_value(), "moving distant gems preserves their total value")
		sim.player_position = Vector2(300, -250)
		sim.view.reset(sim.player_position)
		sim.state.combat_tick = catalog.boss_start_tick
		sim._begin_boss_transition_if_due(sim.state.combat_tick)
		a.expect_equal(sim.player_position, sim.build_snapshot().absorption_position, "boss absorption is anchored at the transition player's position")


func test_node_luck_is_capped_and_ignored_at_capacity(a: Variant, _context: Dictionary) -> void:
	var content: SurvivalContentManifest = BalanceTestFixtures.manifest()
	content.arena.node_initial_count = 0
	content.arena.node_capacity = 1
	content.arena.node_spawn_interval_ticks = 1
	content.arena.node_spawn_chance = 0.1
	content.arena.node_spawn_chance_max = 0.5
	var luck_id: StringName = &""
	for passive: PassiveDefinition in content.passives:
		if passive.stat_id == &"luck_pct":
			passive.amount_per_level = 1000.0
			luck_id = passive.passive_id
	var catalog := DefinitionCatalog.new()
	a.expect_true(catalog.validate_manifest(content), catalog.error_text)
	var state: RunState = RunStateFactory.create(8702, catalog)
	ProgressionService.apply_direct_upgrade(state, catalog, GameTypes.UpgradeKind.PASSIVE, luck_id)
	var objects := ArenaObjectSystem.new()
	objects.initialize(state, catalog)
	var rng: RandomNumberGenerator = state.rng_streams.node_spawn_rng
	rng.state = _rng_state_for_roll(0.55, 0.9)
	objects.advance(1)
	a.expect_equal(0, objects.active_node_count(), "large Luck cannot exceed the chance ceiling")
	rng.state = _rng_state_for_roll(0.2, 0.45)
	objects.advance(2)
	a.expect_equal(1, objects.active_node_count(), "Luck multiplies the base spawn chance below capacity")
	var id: int = objects.nodes[0].node_id
	rng.state = _rng_state_for_roll(0.2, 0.45)
	objects.advance(3)
	a.expect_equal(id, objects.nodes[0].node_id, "at capacity the same roll ignores Luck")
	var before: Dictionary = state.rng_streams.state_digest()
	state.phase = GameTypes.RunPhase.CHEST_REWARD
	objects.advance(4)
	a.expect_equal(before, state.rng_streams.state_digest(), "chest selection freezes spawn draws as well")


func test_chest_compass_tracks_nearest_hidden_chest_of_each_kind(a: Variant, _context: Dictionary) -> void:
	var catalog: DefinitionCatalog = BalanceTestFixtures.catalog()
	var sim := CombatSimulation.new()
	sim.initialize(RunStateFactory.create(8703, catalog), catalog)
	var normal_serial: int = catalog.elite_chest_kinds.find(GameTypes.ChestKind.NORMAL)
	var evolution_serial: int = catalog.elite_chest_kinds.find(GameTypes.ChestKind.EVOLUTION_CAPABLE)
	var near_chest: ArenaPickup = sim.arena_object_system.spawn_chest(Vector2(45, 0), normal_serial)
	var far_chest: ArenaPickup = sim.arena_object_system.spawn_chest(Vector2(0, 80), normal_serial)
	sim.arena_object_system.spawn_chest(Vector2(-60, 0), evolution_serial)
	var cues: Array[Dictionary] = sim.build_snapshot().chest_guidance
	a.expect_equal(2, cues.size(), "normal and evolution chests have separate cues")
	a.expect_equal(sim.view.edge_guidance(near_chest.position)["direction"], cues[0]["direction"], "normal cue chooses the nearest hidden chest")
	sim.arena_object_system.collect_at(near_chest.position)
	cues = sim.build_snapshot().chest_guidance
	a.expect_equal(sim.view.edge_guidance(far_chest.position)["direction"], cues[0]["direction"], "collecting the nearest chest reveals the next direction")
	far_chest.position = Vector2(2, 0)
	cues = sim.build_snapshot().chest_guidance
	a.expect_equal(1, cues.size(), "a chest inside the screen no longer needs a cue")
	sim.set_viewport_size(Vector2i(1024, 768))
	cues = sim.build_snapshot().chest_guidance
	for cue: Dictionary in cues:
		a.expect_true(Rect2(Vector2.ZERO, Vector2(1024, 768)).has_point(cue["screen_position"]), "guidance stays inside the resized viewport")


func _rng_state_for_roll(lower: float, upper: float) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = 8702
	for index: int in 1000:
		var state: int = rng.state
		var roll: float = rng.randf()
		if roll > lower and roll < upper:
			return state
	return rng.state
