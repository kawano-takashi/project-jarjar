extends RefCounted

const BotObservation = preload("res://dev/bot/bot_observation.gd")
const BotKnowledge = preload("res://dev/bot/bot_knowledge.gd")
const BotController = preload("res://dev/bot/bot_controller.gd")
const BotSession = preload("res://dev/bot/bot_session.gd")


func test_bot_observes_mixed_ring_members_and_only_visible_boundary_lines(a: Variant, _context: Dictionary) -> void:
	var session: BotSession = _session()
	var sim: CombatSimulation = session.simulation
	sim.state.combat_tick = sim.catalog.elite_spawn_ticks[0]
	sim.enemy_system.resolve_scheduled_spawns(Vector2.ZERO, sim.state.combat_tick)
	var member: EnemyEntity = _member(sim)
	member.position = Vector2(0.0, 2.0)
	sim.spawn_fixture_enemy(GameTypes.EnemyType.PURSUER, Vector2(2.0, 0.0))
	var observed: BotObservation = session.observer.capture(sim, session.view)
	var kinds: PackedInt32Array = observed.enemy_values()["kinds"]
	a.expect_true(kinds.has(CombatSnapshot.EnemyVisualKind.ENCIRCLER), "ring has its own visible mesh kind")
	a.expect_true(kinds.has(CombatSnapshot.EnemyVisualKind.PURSUER), "new visual does not erase other enemy observations")
	var encounter: EncounterSystem = sim.enemy_system.encounters
	encounter.begin_boss(Vector2(1000, 1000), sim.state.combat_tick)
	var hidden: BotObservation = session.observer.capture(sim, session.view)
	a.expect_true(hidden.boundary_segments.is_empty(), "a wholly offscreen enclosure reveals no boundary")
	encounter.boss_center = Vector2(2000, 1000)
	encounter._boss_activation_tick += 600
	var hidden_changed: BotObservation = session.observer.capture(sim, session.view)
	a.expect_equal(hidden.boundary_segments, hidden_changed.boundary_segments, "unseen geometry and future timing do not leak")
	var first := BotController.new(BotKnowledge.new(sim.catalog))
	var second := BotController.new(BotKnowledge.new(sim.catalog))
	a.expect_equal(first.decide(hidden).move_input, second.decide(hidden_changed).move_input, "identical visible information gives the same move")
	encounter.boss_center = Vector2.ZERO
	observed = session.observer.capture(sim, session.view)
	a.expect_true(not observed.boundary_segments.is_empty(), "visible perimeter produces line observations")
	for index: int in observed.boundary_segments.size():
		var line: Vector4 = observed.boundary_segments[index]
		var normal: Vector2 = observed.boundary_normals[index]
		for point: Vector2 in [Vector2(line.x, line.y), Vector2(line.z, line.w)]:
			var pixel: Vector2 = session.view.project_position(Vector3(point.x, EncounterGeometry.BOUNDARY_HEIGHT, point.y))
			a.expect_true(Rect2(Vector2.ZERO, Vector2(session.view.viewport_size)).grow(0.1).has_point(pixel), "line endpoints are clipped to the actual camera")
			a.expect_true((-point).dot(normal) > 0.0, "normal points into the visible enclosed side")
	observed.boundary_segments[0] = Vector4.ZERO
	a.expect_not_equal(observed.boundary_segments, session.observer.capture(sim, session.view).boundary_segments, "boundary values are detached from game state")


func test_bot_wall_routes_keep_reachable_loot_and_bound_memory(a: Variant, _context: Dictionary) -> void:
	var session: BotSession = _session()
	var controller: BotController = session.controller
	var nav: RefCounted = controller._navigation
	var segments := PackedVector4Array([Vector4(4, -10, 4, 10)])
	var normals := PackedVector2Array([Vector2.LEFT])
	nav.observe_boundaries(segments, normals, 10)
	var route: Vector2 = nav.route_tracked(Vector2(3.6, 0), Vector2(20, 0), 0.45)
	a.expect_true(route.x <= 3.55, "rounded wall-side start connects to an inside route")
	a.expect_true(route.distance_to(Vector2(3.6, 0)) > 0.001, "rounding does not leave the bot stuck on its current cell")
	var view: ArenaView = session.view
	nav.remember_loot(PackedVector4Array([Vector4(1, 10, 0, 1)]), view.camera_transform.affine_inverse(), view.viewport_size, 10, view.projection, 0)
	var frame: Dictionary = {"player": Vector2.ZERO, "last_move": Vector2.RIGHT, "maxed": false, "evolution_ready": false, "hp": 100.0, "max_hp": 100.0, "pickup_radius": 2.0, "object_collect_radius": 1.0, "player_radius": 0.45, "loot_kinds": PackedInt32Array([0, 1, 2, 3, 4])}
	a.expect_equal(0.0, nav.choose_loot_goal(frame).z, "inaccessible outer chest is excluded")
	nav.remember_loot(PackedVector4Array([Vector4(1, 4.2, 0, 1)]), view.camera_transform.affine_inverse(), view.viewport_size, 10, view.projection, 0)
	var goal: Vector3 = nav.choose_loot_goal(frame)
	a.expect_equal(1.0, goal.z, "outer chest within collection reach remains eligible")
	a.expect_true(goal.x <= 3.55, "collection approach stays inside")
	nav.shift_origin(Vector2(1024, 0))
	var shifted: Vector2 = nav.route_tracked(Vector2(3.6 - 1024, 0), Vector2(20 - 1024, 0), 0.45)
	a.expect_true((shifted + Vector2(1024, 0)).distance_to(route) < 0.001, "origin changes shift remembered planes and routes together")
	nav.observe_boundaries(PackedVector4Array(), PackedVector2Array(), 131)
	var expired: Vector2 = nav.route_tracked(Vector2(3.6 - 1024, 0), Vector2(20 - 1024, 0), 0.45)
	a.expect_true(expired.x > 3.55 - 1024, "unseen boundary memory expires after the existing 120-tick limit")
	# A public boss transition discards old battle memories while preserving loot.
	controller._swarm_warnings.append({"position": Vector2.ZERO, "direction": Vector2.RIGHT})
	controller._goal = Vector2(900, 900)
	var observation: BotObservation = session.observer.capture(session.simulation, view)
	observation.boss_active = true
	observation.tick = 132
	observation.world_origin = Vector2i(1, 0)
	observation.player_position = Vector2(-1024, 0)
	observation.camera_transform.origin += Vector3(5000, 0, 0)
	# Synchronize the test's explicit native origin move with the controller.
	controller._world_origin = Vector2i(1, 0)
	controller.decide(observation)
	a.expect_true(controller._swarm_warnings.is_empty(), "boss transition clears retired swarm warnings")
	a.expect_true(controller._goal.distance_to(Vector2(900, 900)) > 1.0, "boss transition drops the old goal")
	frame["player"] = Vector2(-1024, 0)
	a.expect_equal(1.0, nav.choose_loot_goal(frame).z, "transition retains unseen loot memory")
	nav.configure(Vector2(-32, -32), Vector2i(65, 65), 1.0)
	nav.observe_boundaries(segments, normals, 200)
	nav.observe_boundaries(PackedVector4Array([Vector4(3.9, -10, 3.9, 10)]), normals, 206)
	var shrinking: Vector2 = nav.route_tracked(Vector2(3, 0), Vector2(20, 0), 0.45)
	nav.observe_boundaries(PackedVector4Array([Vector4(3.9, -10, 3.9, 10)]), normals, 212)
	var stopped: Vector2 = nav.route_tracked(Vector2(3, 0), Vector2(20, 0), 0.45)
	a.expect_true(shrinking.x < stopped.x - 0.1, "visible wall motion predicts shrink, and stationary history stops that prediction")


func test_bot_normal_escape_and_needle_moves_follow_shrinking_combat_boundary(a: Variant, _context: Dictionary) -> void:
	for mode: String in ["normal", "escape", "needles"]:
		var session: BotSession = _session()
		var sim: CombatSimulation = session.simulation
		sim.state.combat_tick = sim.catalog.boss_start_tick - 1
		sim.advance_tick(Vector2.ZERO)
		var boss: EnemyEntity = sim.enemy_system.boss_entity()
		sim.state.combat_tick = boss.activation_tick + 1
		boss.position = Vector2(-4, 0)
		var radius: float = sim.catalog.manifest().player.body_radius
		var encounter: EncounterSystem = sim.enemy_system.encounters
		sim.player_position = encounter.constrain_body(Vector2(encounter.boss_radius, 0), radius)
		sim.view.reset(sim.player_position)
		sim.state.weapons.clear()
		if mode == "needles":
			sim.state.weapons.append(RunWeapon.create(&"directional_needle", &"directional_needle", false, sim.state.rng_streams.create_weapon_rng(&"directional_needle", 0)))
			sim.spawn_fixture_enemy(GameTypes.EnemyType.PURSUER, sim.player_position + Vector2(4, 0), -1, true, true)
		session.controller.decide(session.observer.capture(sim, sim.view))
		session.controller._goal = sim.player_position + Vector2(10, 0)
		session.controller._next_goal_tick = sim.state.combat_tick + 100
		if mode == "escape":
			sim.spawn_fixture_enemy(GameTypes.EnemyType.PURSUER, sim.player_position - Vector2(0.8, 0), -1, true, true)
			sim.advance_tick(Vector2.ZERO)
		if mode == "needles":
			session.controller._needle_next_tick = sim.state.combat_tick + 1
		var before: Vector2 = sim.player_position
		for step: int in 30:
			a.expect_true(session.advance(), "%s wall scenario accepts its bot action" % mode)
			var intended_move: Vector2 = sim.view.screen_to_world_input(session.last_action.move_input)
			if intended_move.length_squared() > 0.001:
				# Tangent motion may slide. Pushing straight out must not be mistaken for escape.
				a.expect_true(sim.last_player_displacement.dot(intended_move) > 0.0, "%s makes actual progress along its chosen movement" % mode)
			a.expect_true(sim.player_position.distance_to(encounter.boss_center) + radius <= encounter.boss_radius + 0.001, "%s movement respects the actual shrinking boundary" % mode)
		a.expect_true(sim.player_position.distance_to(before) > 0.2, "%s does not keep pushing into the wall" % mode)
		if mode == "escape":
			a.expect_true(session.controller._escape_until_tick >= sim.state.combat_tick, "real contact damage exercised post-hit escape")
		sim.state.phase = GameTypes.RunPhase.LEVEL_UP
		var radius_before: float = encounter.boss_radius
		var tick_before: int = sim.state.combat_tick
		a.expect_false(sim.advance_tick(Vector2.RIGHT), "pause stops combat and boundary clocks")
		a.expect_equal(tick_before, sim.state.combat_tick, "paused tick is unchanged")
		a.expect_float(radius_before, encounter.boss_radius, "paused boundary is unchanged")


func test_bot_can_break_through_soft_ring_away_from_elite_contact(a: Variant, _context: Dictionary) -> void:
	var session: BotSession = _session()
	var sim: CombatSimulation = session.simulation
	sim.state.weapons.clear()
	sim.state.combat_tick = sim.catalog.elite_spawn_ticks[0]
	var elite: EnemyEntity = sim.enemy_system.resolve_scheduled_spawns(Vector2.ZERO, sim.state.combat_tick)[0]
	var members: Array[EnemyEntity] = []
	for enemy: EnemyEntity in sim.enemy_system.enemy_store.entities:
		if enemy.encounter_owner_id >= 0:
			members.append(enemy)
	for index: int in members.size():
		members[index].position = Vector2.from_angle(TAU * float(index) / members.size()) * 1.6
	elite.position = Vector2(-1.2, 0)
	sim.state.combat_tick = elite.activation_tick
	session.controller.decide(session.observer.capture(sim, sim.view))
	session.controller._goal = Vector2(10, 0)
	session.controller._next_goal_tick = sim.state.combat_tick + 100
	for step: int in 75:
		if not session.advance():
			break
	a.expect_true(sim.player_position.x > 2.7, "bot crosses living low-damage members to leave prolonged elite contact")
	a.expect_equal(0, sim.state.total_kills, "escape does not require a kill or hidden enemy HP")
	a.expect_false(sim.enemy_system.encounters.boss_active, "soft ring never creates a navigation boundary")


func _session() -> BotSession:
	var session := BotSession.new()
	session.initialize(BalanceTestFixtures.catalog(), 9183, Vector2i(1920, 1080))
	return session


func _member(sim: CombatSimulation) -> EnemyEntity:
	for enemy: EnemyEntity in sim.enemy_system.enemy_store.entities:
		if enemy.encounter_owner_id >= 0:
			return enemy
	return null
