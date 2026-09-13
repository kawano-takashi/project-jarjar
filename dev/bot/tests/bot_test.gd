extends RefCounted

const BotAction = preload("res://dev/bot/bot_action.gd")
const BotObservation = preload("res://dev/bot/bot_observation.gd")
const BotKnowledge = preload("res://dev/bot/bot_knowledge.gd")
const BotController = preload("res://dev/bot/bot_controller.gd")
const BotObserver = preload("res://dev/bot/bot_observer.gd")
const BotSession = preload("res://dev/bot/bot_session.gd")
const BotArguments = preload("res://dev/bot/launch_arguments.gd")


class InvalidController extends BotController:
	func decide(_observation: BotObservation) -> BotAction:
		var action := BotAction.new()
		action.move_input = Vector2(2.0, 0.0)
		return action


func test_bot_cli_validates_execution_modes_and_reproducible_view(a: Variant, _context: Dictionary) -> void:
	var defaults: Dictionary = BotArguments.parse(PackedStringArray(["--bot=fast"]))
	a.expect_true(defaults["valid"], "fast mode accepts default settings")
	a.expect_equal(Vector2i(1920, 1080), defaults["bot_view"], "default view matches the normal project")
	var watch: Dictionary = BotArguments.parse(PackedStringArray(["--bot=watch", "--run-seed=-123", "--bot-speed=16", "--bot-view=1024x768"]))
	a.expect_true(watch["valid"], "watch accepts a seed, speed and observation viewport")
	var delayed: Dictionary = BotArguments.parse(PackedStringArray(["--bot=fast", "--bot-evolution-after-tick=28800"]))
	a.expect_equal(28800, delayed.bot_evolution_after_tick, "comparison launch carries an integer combat tick")
	for arguments: PackedStringArray in [
		PackedStringArray(),
		PackedStringArray(["--bot=fast", "--bot=watch"]),
		PackedStringArray(["--bot=watch", "--runs=2"]),
		PackedStringArray(["--bot=fast", "--runs=0"]),
		PackedStringArray(["--bot=fast", "--bot-speed=4"]),
		PackedStringArray(["--bot=watch", "--bot-speed=3"]),
		PackedStringArray(["--bot=fast", "--bot-view=0x1080"]),
		PackedStringArray(["--bot=fast", "--run-seed=9223372036854775807", "--runs=2"]),
		PackedStringArray(["--bot=fast", "--qa-scenario=result"]),
		PackedStringArray(["--bot=fast", "--bot-evolution-after-tick=-1"]),
	]:
		a.expect_false(BotArguments.parse(arguments)["valid"], "invalid or conflicting bot arguments are rejected")


func test_bot_observation_excludes_hidden_state_and_detaches_values(a: Variant, _context: Dictionary) -> void:
	var catalog: DefinitionCatalog = BalanceTestFixtures.catalog()
	var session := BotSession.new()
	a.expect_true(session.initialize(catalog, 771, Vector2i(1920, 1080)), "session initializes")
	var sim: CombatSimulation = session.simulation
	var visible: EnemyEntity = sim.spawn_fixture_enemy(GameTypes.EnemyType.PURSUER, Vector2(2.0, 0.0), -1)
	var hidden: EnemyEntity = sim.spawn_fixture_enemy(GameTypes.EnemyType.PURSUER, Vector2(60.0, 60.0), -1)
	var first: BotObservation = session.observer.capture(sim, session.view)
	var first_brain := BotController.new(BotKnowledge.new(catalog))
	var first_action: BotAction = first_brain.decide(first)
	visible.hp *= 0.01
	visible.special_elapsed_ticks = 123456.0
	hidden.position = Vector2(-60.0, -60.0)
	sim.state.spawn_credit = 8765.0
	sim.state.weapons[0].cooldown_remaining_ticks = 9999
	sim.state.rng_streams.upgrade_rng.state = 123456
	var second: BotObservation = session.observer.capture(sim, session.view)
	var second_brain := BotController.new(BotKnowledge.new(catalog))
	var second_action: BotAction = second_brain.decide(second)
	a.expect_equal(1, first.enemies.size(), "only the visible enemy is exposed")
	a.expect_equal(_body_values(first.enemies), _body_values(second.enemies), "hidden HP, timers, enemies and RNG do not affect observation")
	a.expect_equal(first_action.move_input, second_action.move_input, "identical visible history produces identical decisions")
	second.enemies[0].position = Vector2(500, 500)
	second.weapons[0]["level"] = 999
	a.expect_equal(Vector2(2, 0), visible.position, "observation does not retain mutable entity references")
	a.expect_equal(1, sim.state.weapons[0].level, "inventory observation is detached")
	# All three powerups currently use the same mesh, scale and material.
	sim.arena_object_system.pickups.clear()
	sim.arena_object_system.pickups.append(ArenaPickup.new(1, ArenaPickup.Kind.HEAL, Vector2.ONE))
	var heal: BotObservation = session.observer.capture(sim, session.view)
	sim.arena_object_system.pickups[0].kind = ArenaPickup.Kind.STOP
	var stop: BotObservation = session.observer.capture(sim, session.view)
	a.expect_equal(heal.loot, stop.loot, "indistinguishable powerups do not reveal their effects")
	# HP-driven escape planning must obey the same observation boundary.
	sim.state.combat_tick = 1
	sim.state.current_hp -= 1.0
	visible.position = Vector2(0.9, 0.0)
	var hurt_before: BotObservation = session.observer.capture(sim, session.view)
	hidden.position = Vector2(70.0, -70.0)
	visible.hp *= 0.1
	var hurt_after: BotObservation = session.observer.capture(sim, session.view)
	a.expect_equal(first_brain.decide(hurt_before).move_input, second_brain.decide(hurt_after).move_input, "escape planning uses the visible HP change without reading hidden enemy state")
	# Both brains retain the same visible history while the former target is
	# offscreen. Moving or removing it cannot refresh either brain's memory.
	session.view.reset(Vector2(40.0, 0.0))
	for tick: int in range(2, 6):
		sim.state.combat_tick = tick
		var before_hidden_change: BotObservation = session.observer.capture(sim, session.view)
		visible.position = Vector2(-50.0 - tick, -50.0)
		visible.alive = tick < 3
		var after_hidden_change: BotObservation = session.observer.capture(sim, session.view)
		a.expect_equal(_body_values(before_hidden_change.enemies), _body_values(after_hidden_change.enemies), "unseen movement and disappearance remain unobservable across ticks")
		a.expect_equal(first_brain.decide(before_hidden_change).move_input, second_brain.decide(after_hidden_change).move_input, "offscreen changes cannot alter decisions through observation memory")
	session.view.reset(Vector2.ZERO)
	var xp: XpPickupState = sim.xp_pickup_pool.acquire(Vector2.ONE, 1, 0, Vector2.ZERO)
	var old_loot: BotObservation = session.observer.capture(sim, session.view)
	var retained: PackedVector4Array = old_loot.loot.duplicate()
	xp.position = Vector2(2.0, 2.0)
	xp.value = 16
	var moved_loot: BotObservation = session.observer.capture(sim, session.view)
	a.expect_equal(Vector2(2.0, 2.0), Vector2(moved_loot.loot[0].y, moved_loot.loot[0].z), "batch culling uses the pickup's current position")
	a.expect_true(moved_loot.loot[0].w > old_loot.loot[0].w, "absorbed XP updates the observed visual scale")
	a.expect_equal(retained, old_loot.loot, "updating the shared visual buffer cannot rewrite an earlier observation")
	sim.xp_pickup_pool.release(xp.pool_index, xp.generation)
	sim.xp_pickup_pool.acquire(Vector2(-1.0, -1.0), 1, 0, Vector2.ZERO)
	var recycled_loot: BotObservation = session.observer.capture(sim, session.view)
	a.expect_equal(Vector4(BotObservation.LootKind.XP, -1.0, -1.0, 1.0), recycled_loot.loot[0], "reused slots expose the new pickup's position and scale")
	sim.enemy_system.enemy_store.clear()
	var arriving: EnemyEntity = sim.spawn_fixture_enemy(GameTypes.EnemyType.PURSUER, Vector2.ONE, -1)
	var active: EnemyEntity = sim.spawn_fixture_enemy(GameTypes.EnemyType.PURSUER, Vector2.ONE, -1)
	arriving.activation_tick = sim.state.combat_tick + 10
	active.activation_tick = 0
	var coincident: BotObservation = session.observer.capture(sim, session.view)
	a.expect_false(coincident.enemies[0].materializing, "coincident bodies sort by visible attributes before spawn order")
	a.expect_true(coincident.enemies[1].materializing, "the materializing body follows an otherwise identical active body")
	var deferred_bodies: BotObservation = session.observer.capture(sim, session.view)
	active.position = Vector2(3.0, 0.0)
	session.observer.capture(sim, session.view)
	a.expect_equal(Vector2.ONE, deferred_bodies.enemies[0].position, "an unread packed observation retains its values across later captures")


func test_bot_observes_partial_telegraphs_and_escapes_swarm_lane(a: Variant, _context: Dictionary) -> void:
	var session := BotSession.new()
	session.initialize(BalanceTestFixtures.catalog(), 774, Vector2i(1920, 1080))
	var right: Vector3 = session.view.camera_transform.basis.x
	var focus_depth: float = session.view.camera_transform.origin.length()
	var edge_distance: float = focus_depth / session.view.projection.x.x + 0.5
	var edge_position := Vector2(right.x, right.z) * edge_distance
	var boss: EnemyEntity = session.simulation.spawn_fixture_enemy(GameTypes.EnemyType.BOSS, edge_position, -1)
	boss.boss_charge_active = true
	boss.boss_charge_spoke_count = 8
	var partial: BotObservation = session.observer.capture(session.simulation, session.view)
	a.expect_false(Rect2(Vector2.ZERO, Vector2(partial.viewport_size)).has_point(session.view.project_position(Vector3(edge_position.x, 0.055, edge_position.y))), "telegraph center is beyond the screen edge")
	a.expect_true(not partial.warnings.is_empty(), "the visible part of a boss telegraph is still observed")
	boss.position *= 4.0
	var hidden: BotObservation = session.observer.capture(session.simulation, session.view)
	a.expect_true(hidden.warnings.is_empty(), "an entirely offscreen warning does not reveal its position")
	var warning := SwarmWarningState.new()
	warning.direction = Vector2.LEFT
	warning.spawn_distance = 11.0
	warning.spawn_tick = 90
	warning.hp_multiplier = 1.0
	warning.damage_multiplier = 1.0
	session.simulation.enemy_system.stage_events.swarm_warning = warning
	var arrows: BotObservation = session.observer.capture(session.simulation, session.view)
	a.expect_equal(Vector2.LEFT, arrows.warnings[0]["travel_direction"], "visible arrowheads reveal the swarm's travel direction")
	var screen_right := Vector2(right.x, right.z)
	warning.anchor = screen_right * 28.0
	warning.direction = -screen_right
	var band_only: BotObservation = session.observer.capture(session.simulation, session.view)
	a.expect_equal(1, band_only.warnings.size(), "the edge of the band is visible while all arrows are offscreen")
	a.expect_equal(Vector2.ZERO, band_only.warnings[0]["travel_direction"], "an offscreen arrowhead cannot reveal travel direction")
	warning.direction = screen_right
	var reversed: BotObservation = session.observer.capture(session.simulation, session.view)
	a.expect_equal(band_only.warnings, reversed.warnings, "changing an unseen arrow direction preserves the visible band observation")
	# Exercise the real warning, spawn, movement and contact rules. XP ahead
	# tempts the bot toward the approaching group after its warning fades.
	var escape := BotSession.new()
	escape.initialize(BalanceTestFixtures.catalog(), 774, Vector2i(1920, 1080))
	warning.anchor = Vector2.ZERO
	warning.direction = Vector2.LEFT
	# Keep the fixture in the real offscreen spawn band used by warning prediction.
	warning.spawn_distance = escape.simulation.enemy_system._sample_spawn_distance(
		escape.simulation.state.rng_streams.swarm_event_rng, warning.anchor, -warning.direction,
	)
	escape.simulation.enemy_system.stage_events.swarm_warning = warning
	escape.simulation.xp_pickup_pool.acquire(Vector2(8.0, 0.0), 1, 0, Vector2.ZERO)
	for _tick: int in 360:
		if not escape.advance():
			break
	a.expect_float(0.0, escape.summary()["damage_taken"], "the bot avoids contact with the real incoming swarm while collecting")


func test_bot_reports_accepted_damage_without_changing_combat(a: Variant, _context: Dictionary) -> void:
	var catalog: DefinitionCatalog = BalanceTestFixtures.catalog()
	var session := BotSession.new()
	a.expect_true(session.initialize(catalog, 775, Vector2i(1920, 1080)), "recorded run initializes")
	var ordinary := CombatSimulation.new()
	ordinary.initialize(RunStateFactory.create(775, catalog), catalog)
	for sim: CombatSimulation in [ordinary, session.simulation]:
		sim.state.current_hp = 10.0
		sim._apply_player_damage_candidates([{"raw_damage": 3.0}])
		sim.state.current_hp += 2.0
		sim._apply_player_damage_candidates([{"raw_damage": 4.0}])
		sim.state.level_up_invulnerable_until_tick = 1
		sim._apply_player_damage_candidates([{"raw_damage": 4.0}])
	a.expect_float(5.0, session.simulation.state.current_hp, "recovery and invulnerability still use ordinary combat rules")
	a.expect_float(ordinary.state.current_hp, session.simulation.state.current_hp, "recording leaves combat HP unchanged")
	a.expect_float(7.0, session.summary()["damage_taken"], "report includes damage before recovery and excludes blocked hits")
	for sim: CombatSimulation in [ordinary, session.simulation]:
		sim.state.level_up_invulnerable_until_tick = 0
		var enemy: EnemyEntity = sim.spawn_fixture_enemy(GameTypes.EnemyType.BULWARK, Vector2.ONE, -1)
		sim._apply_player_damage_candidates([{"raw_damage": 20.0, "source_entity_id": enemy.entity_id}])
	a.expect_float(0.0, session.simulation.state.current_hp, "a lethal hit still removes the remaining HP")
	a.expect_float(ordinary.state.current_hp, session.simulation.state.current_hp, "recording preserves the lethal outcome")
	a.expect_float(12.0, session.summary()["damage_taken"], "report counts only the remaining HP on a lethal hit")
	a.expect_equal(&"bulwark", session.summary().fatal_hit.source, "the fatal hit is attributed to the actual source enemy")
	a.expect_float(7.0, session.summary().damage_by_source[&"unknown"], "unattributed and blocked hits are kept separate from the fatal source")


func test_bot_mesh_visibility_excludes_empty_corners_and_ring_holes(a: Variant, _context: Dictionary) -> void:
	var view := ArenaView.new()
	view.camera_transform = Transform3D.IDENTITY
	# A simple test frustum keeps the geometry cases independent of camera tuning.
	view.projection = Projection.create_perspective(90.0, 1.0, 1.0, 100.0)
	var culler := BotObserver.Culler.new(view)
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	var sphere_visual := BotObserver.Visual.new(sphere)
	for depth: float in [5.0, 20.0, 70.0]:
		var empty_corner := Transform3D(Basis.IDENTITY, Vector3(depth + 1.6, depth + 1.6, -depth))
		a.expect_true(culler.contains_visual(empty_corner, sphere.get_aabb()), "the broad bounds overlap the viewport corner")
		a.expect_false(sphere_visual.is_visible(culler, empty_corner), "an empty corner of a sphere's box does not reveal the sphere")
		var partial := Transform3D(Basis.IDENTITY, Vector3(depth + 0.8, depth + 0.8, -depth))
		a.expect_true(sphere_visual.is_visible(culler, partial), "a real part of the sphere at the corner is observed at each depth")
	var ring := TorusMesh.new()
	ring.inner_radius = 2.0
	ring.outer_radius = 3.0
	var ring_visual := BotObserver.Visual.new(ring)
	var facing := Transform3D(Basis(Vector3.RIGHT, PI * 0.5).scaled(Vector3.ONE * 10.0), Vector3(0.0, 0.0, -10.0))
	a.expect_false(ring_visual.is_visible(culler, facing), "a viewport entirely inside a ring's hole sees no ring")
	facing.origin.x = 22.0
	a.expect_true(ring_visual.is_visible(culler, facing), "translating the same ring exposes its surface")
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 0.4
	var box_visual := BotObserver.Visual.new(box)
	for depth: float in [-1.0, 0.5, 100.5]:
		a.expect_false(box_visual.is_visible(culler, Transform3D(Basis.IDENTITY, Vector3(0, 0, -depth))), "fully behind, near-clipped and far-clipped meshes remain hidden")
	for depth: float in [0.9, 50.0, 99.9]:
		a.expect_true(box_visual.is_visible(culler, Transform3D(Basis.IDENTITY, Vector3(0, 0, -depth))), "a mesh inside or crossing a depth clip plane remains visible")


func test_bot_memory_uses_perspective_visibility_and_clip_planes(a: Variant, _context: Dictionary) -> void:
	var projection := Projection.create_perspective(90.0, 1.0, 1.0, 100.0)
	var viewport := Vector2i(200, 200)
	var boss_kind: int = CombatSnapshot.EnemyVisualKind.BOSS
	var body := BotObservation.Body.new()
	body.position = Vector2(0, -10)
	body.kind = boss_kind
	body.radius = 0.4
	var visible: Dictionary = BotObservation.pack_bodies([body])
	var empty: Dictionary = BotObservation.pack_bodies([])
	var goal_frame: Dictionary = {
		"player": Vector2.ZERO, "last_move": Vector2.DOWN,
		"maxed": false, "evolution_ready": false, "hp": 100.0, "max_hp": 100.0,
		"pickup_radius": 1.0, "loot_kinds": PackedInt32Array([0, 1, 2, 3, 4]),
	}
	# Camera translations put the remembered point at a known screen location.
	# True means absence is unobservable, so the memory must survive.
	for sample: Array in [
		[Vector3(0, 0.35, 0), false, "center"],
		[Vector3(30, 0.35, 0), true, "offscreen"],
		[Vector3(8, 0.35, 0), true, "20px from left edge"],
		[Vector3(7, 0.35, 0), false, "30px from left edge"],
		[Vector3(8, 0.35, 10), false, "same lateral offset at greater depth"],
		[Vector3(0, 0.35, -20), true, "behind camera"],
		[Vector3(0, 0.35, -9.5), true, "before near plane"],
		[Vector3(0, 0.35, 100), true, "beyond far plane"],
	]:
		for loot_only: bool in [false, true]:
			var navigation: RefCounted = preload("res://dev/bot/native_loader.gd").create_kernel()
			navigation.configure_tracking({
				"enemy_speeds": {boss_kind: 0.0}, "track_cell": 0.75, "memory_ticks": 120,
				"swarm_speed": 0.0, "swarmer_kind": -1, "red_kind": -1, "boss_kind": boss_kind,
			})
			var inverse := Transform3D(Basis.IDENTITY, Vector3(0, 0.35, 0)).affine_inverse()
			var frame: Dictionary = {
				"enemies": empty if loot_only else visible, "bullets": empty,
				"player": Vector2.ZERO, "tick": 0, "elapsed": 1.0 / 60.0,
				"inverse": inverse, "projection": projection, "viewport": viewport,
			}
			navigation.observe_tracks(frame)
			if loot_only:
				navigation.remember_loot(PackedVector4Array([Vector4(BotObservation.LootKind.XP, 0, -10, 1)]), inverse, viewport, 0, projection, BotObservation.LootKind.XP)
			frame["enemies"] = empty
			frame["tick"] = 1
			frame["inverse"] = Transform3D(Basis.IDENTITY, sample[0]).affine_inverse()
			navigation.observe_tracks(frame)
			navigation.remember_loot(PackedVector4Array(), frame["inverse"], viewport, 1, projection, BotObservation.LootKind.XP)
			var target: Vector3 = navigation.choose_loot_goal(goal_frame) if loot_only else navigation.first_boss_position()
			a.expect_equal(sample[1], target.z != 0.0, "%s memory respects %s" % ["loot" if loot_only else "enemy", sample[2]])
			if sample[1]:
				frame["tick"] = 301 if loot_only else 121
				navigation.observe_tracks(frame)
				navigation.remember_loot(PackedVector4Array(), frame["inverse"], viewport, frame["tick"], projection, BotObservation.LootKind.XP)
				target = navigation.choose_loot_goal(goal_frame) if loot_only else navigation.first_boss_position()
				a.expect_equal(0.0, target.z, "unseen targets still expire without being refreshed by hidden state")


func test_bot_handles_modal_chain_and_terminal_limits(a: Variant, _context: Dictionary) -> void:
	var catalog: DefinitionCatalog = BalanceTestFixtures.catalog()
	var session := BotSession.new()
	session.initialize(catalog, 772, Vector2i(1920, 1080))
	var state: RunState = session.simulation.state
	state.pending_level_ups = 1
	state.pending_chest_sources.append(0)
	session.simulation._resolve_modal_priority()
	a.expect_equal(GameTypes.RunPhase.LEVEL_UP, state.phase, "a queued upgrade precedes the chest")
	a.expect_true(session.advance(), "bot chooses an offered upgrade")
	a.expect_equal(0, state.combat_tick, "upgrade choice does not advance combat")
	a.expect_equal(GameTypes.RunPhase.CHEST_REWARD, state.phase, "chest remains in the modal chain")
	a.expect_true(session.advance(), "bot continues the chest")
	a.expect_equal(0, state.combat_tick, "chest continuation does not advance combat")
	a.expect_equal(1, state.opened_chests, "chest applies exactly once")
	state.current_hp = 0.0
	session.advance()
	a.expect_equal(&"lost", session.result, "death ends the run without a retry")
	var timed_out := BotSession.new()
	timed_out.initialize(catalog, 773, Vector2i(1920, 1080))
	timed_out.simulation.state.combat_tick = BotSession.MAX_COMBAT_TICKS
	a.expect_false(timed_out.advance(), "time limit stops further ticks")
	a.expect_equal(&"timeout", timed_out.result, "time limit is not counted as a victory")
	var invalid := BotSession.new()
	invalid.initialize(catalog, 774, Vector2i(1920, 1080))
	invalid.controller = InvalidController.new(BotKnowledge.new(catalog))
	a.expect_false(invalid.advance(), "an illegal bot input stops execution")
	a.expect_equal(&"error", invalid.result, "illegal input is an execution error")
	a.expect_equal(0, invalid.simulation.state.combat_tick, "illegal input does not reach combat")


func test_bot_reacts_to_observed_projectile_motion_and_keeps_legal_input(a: Variant, _context: Dictionary) -> void:
	var knowledge := BotKnowledge.new(BalanceTestFixtures.catalog())
	var controller := BotController.new(knowledge)
	var observation := BotObservation.new()
	observation.hp = 100.0
	observation.max_hp = 100.0
	var view := ArenaView.new()
	observation.camera_transform = view.camera_transform
	observation.camera_projection = view.projection
	var bullet := BotObservation.Body.new()
	bullet.position = Vector2(1.0, 0.0)
	bullet.radius = 0.18
	observation.bullets.append(bullet)
	controller.decide(observation)
	observation.tick = 1
	bullet.position = Vector2(0.8, 0.0)
	var action: BotAction = controller.decide(observation)
	a.expect_true(action.is_valid_for(observation), "movement stays within the normal analog input range")
	var movement: Vector2 = view.screen_to_world_input(action.move_input)
	a.expect_true(movement.x < 0.1, "an approaching projectile does not cause a move directly into it")
	observation.tick = 2
	observation.bullets.clear()
	observation.player_position = Vector2(500, -400)
	view.reset(observation.player_position)
	observation.camera_transform = view.camera_transform
	var wall_action: BotAction = controller.decide(observation)
	var next_position: Vector2 = observation.player_position + view.screen_to_world_input(wall_action.move_input) * knowledge.move_speed / 60.0
	a.expect_true(next_position.distance_to(observation.player_position) > 0.0, "the bot moves freely far from the starting point")
	var aiming := BotController.new(knowledge)
	var firing := BotObservation.new()
	firing.hp = 100.0
	firing.max_hp = 100.0
	view.reset(firing.player_position)
	firing.camera_transform = view.camera_transform
	firing.camera_projection = view.projection
	firing.weapons.append({"id": &"directional_needle", "level": 1, "evolved": false})
	firing.needles.append(Vector2(0.1, 0.0))
	var behind := BotObservation.Body.new()
	behind.position = Vector2(-5.5, 0.0)
	behind.radius = 0.38
	firing.enemies.append(behind)
	aiming.decide(firing)
	firing.tick = int(knowledge.weapons[&"directional_needle"]["cooldown"][0]) - 1
	firing.needles[0] = Vector2(7.0, 0.0)
	var aimed: BotAction = aiming.decide(firing)
	a.expect_true(aimed.is_valid_for(firing), "aiming uses the ordinary analog movement range")
	a.expect_true(view.screen_to_world_input(aimed.move_input).x < 0.0, "a visible volley and the known firing cadence allow aiming at the pursuing enemy")
	var defending := BotController.new(knowledge)
	firing.tick = 0
	firing.needles[0] = Vector2(0.1, 0.0)
	defending.decide(firing)
	firing.tick = int(knowledge.weapons[&"directional_needle"]["cooldown"][0]) - 2
	firing.needles[0] = Vector2(7.0, 0.0)
	bullet.position = Vector2(1.0, 0.0)
	firing.bullets.append(bullet)
	defending.decide(firing)
	firing.tick += 1
	bullet.position = Vector2(0.8, 0.0)
	var dodging: BotAction = defending.decide(firing)
	a.expect_true(dodging.move_input.length() > 0.25, "an imminent projectile takes priority over the small aiming step")


func test_bot_aims_at_later_shots_and_restarts_only_its_own_weapon(a: Variant, _context: Dictionary) -> void:
	var catalog := DefinitionCatalog.new()
	a.expect_true(catalog.validate_manifest(BalanceTestFixtures.manifest()), "detached aiming fixture loads")
	var needle: WeaponDefinition = catalog.weapon(&"directional_needle")
	needle.amount_by_level[1] = 3
	needle.shot_interval_ticks_by_level[1] = 6
	needle.cooldown_ticks_by_level[1] = 30
	var controller := BotController.new(BotKnowledge.new(catalog))
	var observation := BotObservation.new()
	var view := ArenaView.new()
	observation.hp = 100.0
	observation.max_hp = 100.0
	observation.camera_transform = view.camera_transform
	observation.camera_projection = view.projection
	observation.weapons.append({"id": &"directional_needle", "level": 2, "evolved": false})
	var target := BotObservation.Body.new()
	target.position = Vector2(-5.5, 0.0)
	target.radius = 0.38
	observation.enemies.append(target)
	observation.needles.append(Vector2.ZERO)
	controller.decide(observation)
	for tick: int in [5, 11, 29]:
		observation.tick = tick
		observation.needles[0] = Vector2(2, 0)
		if tick == 11:
			observation.passives.append({"id": &"cycle_crystal", "level": 1})
		var aimed: BotAction = controller.decide(observation)
		a.expect_true(view.screen_to_world_input(aimed.move_input).x < 0.0, "later shots and the started cooldown retain their schedule across a passive upgrade")
	observation.tick = 30
	observation.weapons[0]["level"] = 3
	var upgraded: BotAction = controller.decide(observation)
	a.expect_true(view.screen_to_world_input(upgraded.move_input).x < 0.0, "its own upgrade immediately prepares a new aimed sequence")


func test_bot_concentrates_growth_and_secures_the_starter_evolution(a: Variant, _context: Dictionary) -> void:
	var controller := BotController.new(BotKnowledge.new(BalanceTestFixtures.catalog()))
	var observation := BotObservation.new()
	observation.phase = GameTypes.RunPhase.LEVEL_UP
	observation.hp = 100.0
	observation.max_hp = 100.0
	observation.weapons.assign([
		{"id": &"homing_core", "level": 4, "evolved": false},
		{"id": &"zero_field", "level": 3, "evolved": false},
		{"id": &"arc_crystal", "level": 1, "evolved": false}])
	observation.options.assign([
		{"id": &"homing_core", "kind": GameTypes.UpgradeKind.WEAPON, "level": 4, "next": 5},
		{"id": &"zero_field", "kind": GameTypes.UpgradeKind.WEAPON, "level": 3, "next": 4},
		{"id": &"mass_projectile", "kind": GameTypes.UpgradeKind.WEAPON, "level": 0, "next": 1}])
	a.expect_equal(0, controller.decide(observation).choice_index, "three weapons are enough to prioritize the main weapon over a fourth slot")
	observation.weapons[0]["level"] = 7
	observation.options[0]["level"] = 7
	observation.options[0]["next"] = 8
	observation.options[1] = {"id": &"cycle_crystal", "kind": GameTypes.UpgradeKind.PASSIVE, "level": 0, "next": 1}
	a.expect_equal(1, controller.decide(observation).choice_index, "the missing evolution partner is secured before the main weapon finishes")


func test_bot_delays_then_collects_an_evolution_chest_without_changing_combat(a: Variant, _context: Dictionary) -> void:
	var catalog: DefinitionCatalog = BalanceTestFixtures.catalog()
	var session := BotSession.new()
	a.expect_true(session.initialize(catalog, 9201, Vector2i(1920, 1080), false, 180), "delayed comparison starts")
	var sim: CombatSimulation = session.simulation
	sim.state.weapons[0].level = 8
	sim.state.passives.append(RunPassive.create(&"cycle_crystal"))
	for node: ArenaNodeState in sim.arena_object_system.nodes:
		node.deactivate()
	var serial: int = catalog.elite_chest_kinds.find(GameTypes.ChestKind.EVOLUTION_CAPABLE)
	sim.arena_object_system.spawn_chest(Vector2(2, 0), serial)
	while sim.state.combat_tick < 180 and session.result.is_empty():
		session.advance()
	a.expect_equal(0, sim.state.evolution_count, "the visible chest remains uncollected before the chosen tick")
	while sim.state.combat_tick < 1200 and sim.state.evolution_count == 0 and session.result.is_empty():
		session.advance()
	a.expect_equal(1, sim.state.evolution_count, "normal movement collects the chest after the delay")
	a.expect_true(session.first_evolution_tick >= 180, "the report records the real evolution time")
	a.expect_true(session.chest_collection_ticks[serial] >= 180, "collection time comes from the actual chest queue")


func _body_values(bodies: Array[BotObservation.Body]) -> Array:
	var result: Array = []
	for body: BotObservation.Body in bodies:
		result.append([body.position, body.kind, body.radius, body.materializing])
	return result


func test_bot_keeps_memory_across_local_grid_and_origin_changes(a: Variant, _context: Dictionary) -> void:
	var knowledge := BotKnowledge.new(BalanceTestFixtures.catalog())
	var controller := BotController.new(knowledge)
	var observation := BotObservation.new()
	observation.hp = 100.0
	observation.max_hp = 100.0
	observation.player_position = Vector2(1000, 0)
	var view := ArenaView.new()
	view.reset(observation.player_position)
	observation.camera_transform = view.camera_transform
	observation.camera_projection = view.projection
	var boss := BotObservation.Body.new()
	boss.kind = CombatSnapshot.EnemyVisualKind.BOSS
	boss.radius = 1.0
	boss.position = Vector2(1003, 0)
	observation.enemies.append(boss)
	observation.loot.append(Vector4(BotObservation.LootKind.CHEST, 1000, 3, 1))
	controller.decide(observation)
	var remembered: Vector3 = controller._navigation.first_boss_position()
	controller._navigation.recenter(Vector2(1010, -32))
	a.expect_equal(remembered, controller._navigation.first_boss_position(), "moving the local grid retains observed enemies")
	controller._shift_observed_origin(Vector2i(1, 0))
	var shifted: Vector3 = controller._navigation.first_boss_position()
	a.expect_true(Vector2(shifted.x, shifted.y).distance_to(Vector2(remembered.x - 1024, remembered.y)) < 0.001, "origin changes translate remembered enemies")
	var loot: Vector3 = controller._navigation.choose_loot_goal({
		"player": Vector2(-24, 0), "last_move": Vector2.DOWN,
		"maxed": false, "evolution_ready": false, "hp": 100.0, "max_hp": 100.0,
		"pickup_radius": 1.0, "loot_kinds": PackedInt32Array([0, 1, 2, 3, 4]),
	})
	a.expect_equal(Vector3(-24, 3, 1), loot, "origin changes retain the original observed chest")


func test_bot_observes_only_public_chest_directions(a: Variant, _context: Dictionary) -> void:
	var catalog: DefinitionCatalog = BalanceTestFixtures.catalog()
	var serial: int = catalog.elite_chest_kinds.find(GameTypes.ChestKind.NORMAL)
	for chest_position: Vector2 in [Vector2(100, 0), Vector2(0, 200)]:
		var sim := CombatSimulation.new()
		sim.initialize(RunStateFactory.create(8801, catalog), catalog)
		for node: ArenaNodeState in sim.arena_object_system.nodes:
			node.deactivate()
		sim.arena_object_system.spawn_chest(chest_position, serial)
		var observation: BotObservation = BotObserver.new().capture(sim, sim.view)
		a.expect_true(observation.loot.is_empty(), "the hidden chest's precise position is absent from visible loot")
		a.expect_equal(sim.build_snapshot().chest_guidance, observation.chest_guidance, "the bot sees the same chest direction as the player")
		a.expect_equal(3, observation.chest_guidance[0].size(), "the cue contains only kind, direction and screen-edge position")
		var controller := BotController.new(BotKnowledge.new(catalog))
		var action: BotAction = controller.decide(observation)
		a.expect_equal(&"chest_direction", action.reason, "the bot explores toward a public chest cue")
		a.expect_true(action.is_valid_for(observation), "chest guidance produces a valid move input")
		a.expect_true(sim.view.screen_to_world_input(action.move_input).dot(chest_position - sim.player_position) > 0.0, "the cue leads toward the unseen chest")
		observation.weapons.assign([{"id": &"homing_core", "level": 8, "evolved": false}])
		observation.passives.assign([{"id": &"cycle_crystal", "level": 1}])
		observation.chest_guidance[0]["kind"] = GameTypes.ChestKind.EVOLUTION_CAPABLE
		observation.loot.append(Vector4(BotObservation.LootKind.XP, -3, -3, 3))
		var ready_controller := BotController.new(BotKnowledge.new(catalog))
		a.expect_equal(&"chest_direction", ready_controller.decide(observation).reason, "nearby XP cannot indefinitely postpone a ready evolution")
