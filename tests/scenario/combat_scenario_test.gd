extends RefCounted


const DELTA: float = 1.0 / 60.0
const NameGeneratorScript := preload("res://src/loot/name_generator.gd")
const QaItemBuilderScript := preload("res://src/debug/qa_item_builder.gd")


class TraceRng:
	extends RefCounted

	var float_values: Array[float] = []
	var int_values: Array[int] = []
	var range_values: Array[float] = []
	var calls: Array[String] = []

	func randf() -> float:
		calls.append("randf")
		return float_values.pop_front() if not float_values.is_empty() else 0.5

	func randi_range(_minimum: int, _maximum: int) -> int:
		calls.append("randi_range")
		return int_values.pop_front() if not int_values.is_empty() else 0

	func randf_range(minimum: float, maximum: float) -> float:
		calls.append("randf_range")
		var unit_value: float = range_values.pop_front() if not range_values.is_empty() else 0.0
		return lerpf(minimum, maximum, unit_value)


func test_names() -> PackedStringArray:
	return PackedStringArray([
		"camera_arena_and_input_contract",
		"four_weapon_target_shape_interval_contract",
		"ally_projectile_immediate_resolution_contract",
		"strict_distance_and_intersection_order_contract",
		"four_normal_enemy_behavior_contract",
		"enemy_special_fixed_tick_contract",
		"wave_resource_contract",
		"spawn_rng_order_reject_and_block_contract",
		"boss_summon_priority_and_born_tick_contract",
		"w4_normal_before_elite_entity_id_contract",
		"deterministic_replay_and_dense_500_contract",
		"hud_fixed_text_contract",
		"qa_item_builder_validation_contract",
		"qa_scenario_contract",
	])


func run_test(test_name: String, assertions: Variant, context: Dictionary) -> void:
	match test_name:
		"camera_arena_and_input_contract":
			_test_camera_arena_and_input(assertions)
		"four_weapon_target_shape_interval_contract":
			_test_four_weapons(assertions)
		"ally_projectile_immediate_resolution_contract":
			_test_ally_projectile_immediate_resolution(assertions)
		"strict_distance_and_intersection_order_contract":
			_test_strict_distance_and_intersection_order(assertions)
		"four_normal_enemy_behavior_contract":
			_test_four_normal_behaviors(assertions)
		"enemy_special_fixed_tick_contract":
			_test_enemy_special_timing(assertions)
		"wave_resource_contract":
			_test_wave_resources(assertions)
		"spawn_rng_order_reject_and_block_contract":
			_test_spawn_rng(assertions)
		"boss_summon_priority_and_born_tick_contract":
			_test_boss_priority_and_born_tick(assertions)
		"w4_normal_before_elite_entity_id_contract":
			_test_w4_order(assertions)
		"deterministic_replay_and_dense_500_contract":
			_test_deterministic_replay_and_dense_500(assertions)
		"hud_fixed_text_contract":
			await _test_hud_fixed_text(assertions, context)
		"qa_item_builder_validation_contract":
			_test_qa_item_builder_validation(assertions)
		"qa_scenario_contract":
			_test_qa_scenarios(assertions)
		_:
			assertions.expect_true(false, "registered combat scenario test")


func _test_camera_arena_and_input(assertions: Variant) -> void:
	var packed := ResourceLoader.load("res://scenes/gameplay/arena_combat.tscn") as PackedScene
	assertions.expect_true(packed != null, "arena scene loads")
	if packed == null:
		return
	var arena: Node = packed.instantiate()
	var camera := arena.get_node("ArenaCamera") as Camera3D
	assertions.expect_equal(Camera3D.PROJECTION_ORTHOGONAL, camera.projection, "camera orthographic")
	assertions.expect_float(13.0, camera.size, "camera size 13")
	assertions.expect_float(0.1, camera.near, "camera near")
	assertions.expect_float(100.0, camera.far, "camera far")
	var horizontal: float = Vector2(ArenaPresenter.CAMERA_OFFSET.x, ArenaPresenter.CAMERA_OFFSET.z).length()
	var azimuth: float = rad_to_deg(atan2(ArenaPresenter.CAMERA_OFFSET.x, ArenaPresenter.CAMERA_OFFSET.z))
	var elevation: float = rad_to_deg(atan2(ArenaPresenter.CAMERA_OFFSET.y, horizontal))
	assertions.expect_true(is_equal_approx(45.0, azimuth), "camera azimuth 45 degrees")
	assertions.expect_true(absf(elevation - 55.0) < 0.0001, "camera elevation 55 degrees")
	var floor_mesh := (arena.get_node("Floor") as MeshInstance3D).mesh as BoxMesh
	assertions.expect_equal(Vector3(30.0, 0.1, 18.0), floor_mesh.size, "arena is 30m by 18m")
	var enemy_multimesh := (arena.get_node("EnemyInstances") as MultiMeshInstance3D).multimesh
	var projectile_multimesh := (arena.get_node("ProjectileInstances") as MultiMeshInstance3D).multimesh
	var vfx_multimesh := (arena.get_node("VfxInstances") as MultiMeshInstance3D).multimesh
	var chest_multimesh := (arena.get_node("ChestInstances") as MultiMeshInstance3D).multimesh
	assertions.expect_equal(768, enemy_multimesh.instance_count, "enemy MultiMesh capacity")
	assertions.expect_equal(4096, projectile_multimesh.instance_count, "projectile MultiMesh capacity")
	assertions.expect_equal(4096, vfx_multimesh.instance_count, "VFX MultiMesh capacity")
	assertions.expect_equal(128, chest_multimesh.instance_count, "chest MultiMesh capacity")
	for forbidden_action: String in ["attack", "aim", "skill", "dash"]:
		assertions.expect_false(InputMap.has_action(forbidden_action), "no %s input action" % forbidden_action)
	arena.free()

	var simulation: CombatSimulation = _new_simulation(1)
	simulation.freeze_enemy_ai = true
	simulation.freeze_enemy_timers = true
	simulation.freeze_normal_spawn = true
	simulation.freeze_countdown = true
	for _tick: int in range(180):
		simulation.step(Vector2.RIGHT, DELTA)
	assertions.expect_true(absf(simulation.player_position.x - 15.0) <= 0.0001, "player reaches X boundary in 3 seconds")
	simulation.step(Vector2.RIGHT, DELTA)
	assertions.expect_true(absf(simulation.player_position.x - 15.0) <= 0.0001, "player clamps at arena boundary")


func _test_four_weapons(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog()
	var expected: Dictionary = {
		&"wood_stick": [10.0, 0.8, 1.8, 0.0, 0.0],
		&"bow": [12.0, 0.75, 14.0, 24.0, 0.2],
		&"staff": [18.0, 1.5, 13.0, 16.0, 0.25],
		&"sword": [14.0, 0.9, 2.4, 0.0, 0.0],
	}
	for weapon_id: StringName in expected:
		var definition: WeaponDefinition = catalog.weapon(weapon_id)
		var values: Array = expected[weapon_id]
		assertions.expect_float(float(values[0]), definition.base_damage, "%s damage" % weapon_id)
		assertions.expect_float(float(values[1]), definition.base_interval, "%s interval" % weapon_id)
		assertions.expect_float(float(values[2]), definition.range_m, "%s range" % weapon_id)
		assertions.expect_float(float(values[3]), definition.projectile_speed, "%s projectile speed" % weapon_id)
		assertions.expect_float(float(values[4]), definition.projectile_radius, "%s projectile radius" % weapon_id)
	assertions.expect_float(2.25, catalog.weapon(&"staff").aoe_radius, "staff area radius")
	assertions.expect_float(120.0, catalog.weapon(&"sword").arc_degrees, "sword fan angle")

	var wood: CombatSimulation = _new_simulation(1)
	_freeze_fixture(wood)
	var low_id: EnemyEntity = wood.spawn_fixture_enemy(GameTypes.EnemyType.TRACKER, Vector2(1.0, 0.2))
	var high_id: EnemyEntity = wood.spawn_fixture_enemy(GameTypes.EnemyType.TRACKER, Vector2(1.0, -0.2))
	wood.step(Vector2.ZERO, DELTA)
	assertions.expect_false(wood.enemy_system.enemy_store.has_entity(low_id.entity_id), "wood stick equal-distance tie uses lower entity_id")
	assertions.expect_true(wood.enemy_system.enemy_store.has_entity(high_id.entity_id), "wood stick hits one target")

	var bow: CombatSimulation = _new_weapon_simulation(GameTypes.MainWeaponType.BOW)
	_freeze_fixture(bow)
	var bow_target: EnemyEntity = bow.spawn_fixture_enemy(GameTypes.EnemyType.TRACKER, Vector2(10.0, 0.0))
	bow.step(Vector2.ZERO, DELTA)
	var bow_projectile: ProjectileState = _first_active_projectile(bow.projectile_pool)
	assertions.expect_true(bow_projectile != null, "bow generates projectile")
	if bow_projectile != null:
		assertions.expect_float(24.0, bow_projectile.velocity.length(), "bow runtime speed")
		assertions.expect_equal(bow_target.position, bow_projectile.target_position, "bow auto-aim target")
		assertions.expect_equal(1, bow_projectile.pierce_remaining, "bow base hit count one")

	var staff: CombatSimulation = _new_weapon_simulation(GameTypes.MainWeaponType.STAFF)
	_freeze_fixture(staff)
	staff.spawn_fixture_enemy(GameTypes.EnemyType.TRACKER, Vector2(10.0, 0.0))
	staff.step(Vector2.ZERO, DELTA)
	var staff_projectile: ProjectileState = _first_active_projectile(staff.projectile_pool)
	assertions.expect_true(staff_projectile != null, "staff generates projectile")
	if staff_projectile != null:
		assertions.expect_float(16.0, staff_projectile.velocity.length(), "staff runtime speed")

	var sword: CombatSimulation = _new_weapon_simulation(GameTypes.MainWeaponType.SWORD)
	_freeze_fixture(sword)
	var inside_left: EnemyEntity = sword.spawn_fixture_enemy(GameTypes.EnemyType.TRACKER, Vector2(1.8, 0.8))
	var inside_right: EnemyEntity = sword.spawn_fixture_enemy(GameTypes.EnemyType.TRACKER, Vector2(1.8, -0.8))
	var outside: EnemyEntity = sword.spawn_fixture_enemy(GameTypes.EnemyType.TRACKER, Vector2(-2.3, 0.0))
	sword.step(Vector2.ZERO, DELTA)
	assertions.expect_false(sword.enemy_system.enemy_store.has_entity(inside_left.entity_id), "sword hits fan left")
	assertions.expect_false(sword.enemy_system.enemy_store.has_entity(inside_right.entity_id), "sword hits fan right")
	assertions.expect_true(sword.enemy_system.enemy_store.has_entity(outside.entity_id), "sword excludes behind fan")


func _test_ally_projectile_immediate_resolution(assertions: Variant) -> void:
	var simulation: CombatSimulation = _new_simulation(1)
	_freeze_fixture(simulation)
	simulation.weapon_system.attack_elapsed = 0.0
	var front: EnemyEntity = simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.TRACKER,
		Vector2(0.8, 0.0),
	)
	var rear: EnemyEntity = simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.TRACKER,
		Vector2(1.8, 0.0),
	)
	for _index: int in range(2):
		var projectile: ProjectileState = simulation.projectile_pool.acquire(
			ProjectileState.FACTION_ALLY,
			&"bow",
			-1,
			Vector2.ZERO,
			Vector2(120.0, 0.0),
			0.2,
			10.0,
			14.0,
			1.0,
			Vector2(14.0, 0.0),
			1,
			simulation.state.physics_tick,
		)
		assertions.expect_true(projectile != null, "sequential ally projectile acquired")
	simulation.step(Vector2.ZERO, DELTA)
	assertions.expect_false(
		simulation.enemy_system.enemy_store.has_entity(front.entity_id),
		"first ally projectile kills front enemy immediately",
	)
	assertions.expect_false(
		simulation.enemy_system.enemy_store.has_entity(rear.entity_id),
		"second ally projectile observes removal and hits rear enemy",
	)
	assertions.expect_equal(2, simulation.state.wave_kills, "both sequential projectile kills counted")


func _test_strict_distance_and_intersection_order(assertions: Variant) -> void:
	var nearest: CombatSimulation = _new_simulation(1)
	_freeze_fixture(nearest)
	var farther_low_id: EnemyEntity = nearest.spawn_fixture_enemy(
		GameTypes.EnemyType.TRACKER,
		Vector2(1.000001, 0.0),
	)
	var nearer_high_id: EnemyEntity = nearest.spawn_fixture_enemy(
		GameTypes.EnemyType.TRACKER,
		Vector2(0.999999, 0.0),
	)
	nearest.step(Vector2.ZERO, DELTA)
	assertions.expect_true(
		nearest.enemy_system.enemy_store.has_entity(farther_low_id.entity_id),
		"near-equal farther low id is not treated as distance tie",
	)
	assertions.expect_false(
		nearest.enemy_system.enemy_store.has_entity(nearer_high_id.entity_id),
		"strictly nearer high id wins auto-aim",
	)

	var bow: CombatSimulation = _new_weapon_simulation(GameTypes.MainWeaponType.BOW)
	_freeze_fixture(bow)
	bow.weapon_system.attack_elapsed = 0.0
	var later_low_id: EnemyEntity = bow.spawn_fixture_enemy(
		GameTypes.EnemyType.TRACKER,
		Vector2(1.000002, 0.0),
	)
	var earlier_high_id: EnemyEntity = bow.spawn_fixture_enemy(
		GameTypes.EnemyType.TRACKER,
		Vector2(1.0, 0.0),
	)
	bow.projectile_pool.acquire(
		ProjectileState.FACTION_ALLY,
		&"bow",
		-1,
		Vector2.ZERO,
		Vector2(120.0, 0.0),
		0.2,
		12.0,
		14.0,
		1.0,
		Vector2(14.0, 0.0),
		1,
		bow.state.physics_tick,
	)
	bow.step(Vector2.ZERO, DELTA)
	assertions.expect_true(
		bow.enemy_system.enemy_store.has_entity(later_low_id.entity_id),
		"near-equal later intersection is not treated as t tie",
	)
	assertions.expect_false(
		bow.enemy_system.enemy_store.has_entity(earlier_high_id.entity_id),
		"strictly earlier intersection wins before entity id",
	)

	var staff: CombatSimulation = _new_weapon_simulation(GameTypes.MainWeaponType.STAFF)
	_freeze_fixture(staff)
	var staff_later_low_id: EnemyEntity = staff.spawn_fixture_enemy(
		GameTypes.EnemyType.TRACKER,
		Vector2(1.000001, 0.0),
	)
	var staff_earlier_high_id: EnemyEntity = staff.spawn_fixture_enemy(
		GameTypes.EnemyType.TRACKER,
		Vector2(0.999999, 0.0),
	)
	var staff_projectile: ProjectileState = staff.projectile_pool.acquire(
		ProjectileState.FACTION_ALLY,
		&"staff",
		-1,
		Vector2.ZERO,
		Vector2(120.0, 0.0),
		0.25,
		18.0,
		13.0,
		1.0,
		Vector2(13.0, 0.0),
		1,
		staff.state.physics_tick,
	)
	var staff_snapshot: Array[Vector2i] = staff.projectile_pool.snapshot_active()
	staff.weapon_system.move_snapshot_projectiles(staff_snapshot, DELTA, 1)
	var staff_hits: Array[Dictionary] = staff.weapon_system.resolve_ally_projectile(
		staff_snapshot[0],
		staff.enemy_system.enemy_store,
		staff.enemy_system.uniform_grid,
		1,
	)
	assertions.expect_true(staff_projectile != null, "strict staff projectile acquired")
	assertions.expect_true(not staff_hits.is_empty(), "strict staff explosion produces hit records")
	if not staff_hits.is_empty():
		var event: CombatEvent = staff_hits[0].get("event") as CombatEvent
		var expected_t: float = CombatGeometry.segment_circle_first_t(
			Vector2.ZERO,
			Vector2(2.0, 0.0),
			staff_earlier_high_id.position,
			0.25 + staff_earlier_high_id.body_radius(),
		)
		var expected_center: Vector2 = Vector2.ZERO.lerp(Vector2(2.0, 0.0), expected_t)
		assertions.expect_equal(expected_center, event.position, "staff uses strictly earliest impact center")
	assertions.expect_true(
		staff_later_low_id.entity_id < staff_earlier_high_id.entity_id,
		"staff fixture gives later intersection the lower entity id",
	)


func _test_four_normal_behaviors(assertions: Variant) -> void:
	var expected_speeds: Dictionary = {
		GameTypes.EnemyType.TRACKER: 2.2,
		GameTypes.EnemyType.FAST: 3.8,
		GameTypes.EnemyType.ARMORED: 1.35,
	}
	for enemy_type: GameTypes.EnemyType in expected_speeds:
		var simulation: CombatSimulation = _new_simulation(1)
		var enemy: EnemyEntity = simulation.spawn_fixture_enemy(enemy_type, Vector2(5.0, 0.0))
		var ids: Array[int] = simulation.enemy_system.snapshot_ids()
		simulation.enemy_system.advance_snapshot(ids, Vector2.ZERO, DELTA, 1)
		var traveled: float = 5.0 - enemy.position.x
		assertions.expect_true(absf(traveled - float(expected_speeds[enemy_type]) * DELTA) < 0.00001, "%s chases at fixed speed" % enemy_type)
	var ranged_sim: CombatSimulation = _new_simulation(1)
	var ranged_far: EnemyEntity = ranged_sim.spawn_fixture_enemy(GameTypes.EnemyType.RANGED, Vector2(8.0, 0.0))
	ranged_sim.enemy_system.advance_snapshot([ranged_far.entity_id], Vector2.ZERO, DELTA, 1)
	assertions.expect_true(ranged_far.position.x < 8.0, "RANGED approaches beyond 7.25m")
	var ranged_near: EnemyEntity = ranged_sim.spawn_fixture_enemy(GameTypes.EnemyType.RANGED, Vector2(6.0, 0.0))
	ranged_sim.enemy_system.advance_snapshot([ranged_near.entity_id], Vector2.ZERO, DELTA, 2)
	assertions.expect_true(ranged_near.position.x > 6.0, "RANGED retreats inside 6.75m")

	var contact_ticks: Dictionary = {
		GameTypes.EnemyType.TRACKER: 45,
		GameTypes.EnemyType.FAST: 36,
		GameTypes.EnemyType.ARMORED: 60,
		GameTypes.EnemyType.RANGED: 45,
	}
	for enemy_type: GameTypes.EnemyType in contact_ticks:
		var contact_sim: CombatSimulation = _new_simulation(1)
		var contact_enemy: EnemyEntity = contact_sim.spawn_fixture_enemy(enemy_type, Vector2.ZERO, 0)
		var ids: Array[int] = [contact_enemy.entity_id]
		var expected_tick: int = int(contact_ticks[enemy_type])
		var early_damage_count: int = 0
		for tick: int in range(1, expected_tick):
			contact_sim.enemy_system.advance_snapshot(ids, Vector2.ZERO, DELTA, tick)
			early_damage_count += contact_sim.enemy_system.resolve_ready_enemy_damage_actions(ids, Vector2.ZERO, tick).size()
		assertions.expect_equal(0, early_damage_count, "%s contact not early" % enemy_type)
		contact_sim.enemy_system.advance_snapshot(ids, Vector2.ZERO, DELTA, expected_tick)
		var on_tick: Array[Dictionary] = contact_sim.enemy_system.resolve_ready_enemy_damage_actions(ids, Vector2.ZERO, expected_tick)
		assertions.expect_equal(1, on_tick.size(), "%s first contact at interval tick" % enemy_type)


func _test_enemy_special_timing(assertions: Variant) -> void:
	var ranged_sim: CombatSimulation = _new_simulation(1)
	var ranged: EnemyEntity = ranged_sim.spawn_fixture_enemy(GameTypes.EnemyType.RANGED, Vector2(7.0, 0.0), 0)
	var ranged_ids: Array[int] = [ranged.entity_id]
	for tick: int in range(1, 108):
		ranged_sim.enemy_system.advance_snapshot(ranged_ids, Vector2.ZERO, DELTA, tick)
		ranged_sim.enemy_system.resolve_ready_enemy_special_actions(ranged_ids, Vector2.ZERO, tick, ranged_sim.projectile_pool)
	assertions.expect_equal(0, ranged_sim.projectile_pool.active_count(), "RANGED has no early projectile")
	ranged_sim.enemy_system.advance_snapshot(ranged_ids, Vector2.ZERO, DELTA, 108)
	ranged_sim.enemy_system.resolve_ready_enemy_special_actions(ranged_ids, Vector2.ZERO, 108, ranged_sim.projectile_pool)
	assertions.expect_equal(1, ranged_sim.projectile_pool.active_count(), "RANGED first projectile at tick 108")

	var elite_sim: CombatSimulation = _new_simulation(1)
	var elite: EnemyEntity = elite_sim.spawn_fixture_enemy(GameTypes.EnemyType.ELITE, Vector2.ZERO, 0)
	var elite_ids: Array[int] = [elite.entity_id]
	for tick: int in range(1, 240):
		elite_sim.enemy_system.advance_snapshot(elite_ids, Vector2.ZERO, DELTA, tick)
		elite_sim.enemy_system.resolve_ready_enemy_special_actions(elite_ids, Vector2.ZERO, tick, elite_sim.projectile_pool)
	assertions.expect_false(elite.telegraph_active, "ELITE telegraph not early")
	elite_sim.enemy_system.advance_snapshot(elite_ids, Vector2.ZERO, DELTA, 240)
	elite_sim.enemy_system.resolve_ready_enemy_special_actions(elite_ids, Vector2.ZERO, 240, elite_sim.projectile_pool)
	assertions.expect_true(elite.telegraph_active, "ELITE first telegraph tick 240")
	var elite_area_hits: int = 0
	for tick: int in range(241, 313):
		elite_sim.enemy_system.advance_snapshot(elite_ids, Vector2.ZERO, DELTA, tick)
		var records: Array[Dictionary] = elite_sim.enemy_system.resolve_ready_enemy_damage_actions(elite_ids, Vector2.ZERO, tick)
		for record: Dictionary in records:
			if record.get("source_effect_id", &"") == EnemySystem.DAMAGE_SOURCE_ELITE_AREA:
				elite_area_hits += 1
	assertions.expect_equal(1, elite_area_hits, "ELITE resolves 72 ticks after telegraph")

	var boss_sim: CombatSimulation = _new_simulation(8)
	var boss_ids: Array[int] = boss_sim.enemy_system.snapshot_ids()
	assertions.expect_equal(1, boss_ids.size(), "W8 starts with exactly one BOSS")
	for tick: int in range(1, 180):
		boss_sim.enemy_system.advance_snapshot(boss_ids, Vector2.ZERO, DELTA, tick)
		boss_sim.enemy_system.resolve_ready_enemy_special_actions(boss_ids, Vector2.ZERO, tick, boss_sim.projectile_pool)
	assertions.expect_equal(0, boss_sim.projectile_pool.active_count(), "BOSS barrage not early")
	boss_sim.enemy_system.advance_snapshot(boss_ids, Vector2.ZERO, DELTA, 180)
	boss_sim.enemy_system.resolve_ready_enemy_special_actions(boss_ids, Vector2.ZERO, 180, boss_sim.projectile_pool)
	assertions.expect_equal(12, boss_sim.projectile_pool.active_count(), "BOSS first 12-shot barrage tick 180")
	var summon_sim: CombatSimulation = _new_simulation(8)
	var summon_ids: Array[int] = summon_sim.enemy_system.snapshot_ids()
	for tick: int in range(1, 360):
		summon_sim.enemy_system.advance_snapshot(summon_ids, Vector2.ZERO, DELTA, tick)
		summon_sim.enemy_system.resolve_ready_boss_summons(summon_ids, Vector2.ZERO, tick)
	assertions.expect_equal(1, summon_sim.enemy_system.enemy_store.active_count(), "BOSS summon not early")
	summon_sim.enemy_system.advance_snapshot(summon_ids, Vector2.ZERO, DELTA, 360)
	var summoned: Array[EnemyEntity] = summon_sim.enemy_system.resolve_ready_boss_summons(summon_ids, Vector2.ZERO, 360)
	assertions.expect_equal(8, summoned.size(), "BOSS first summon tick 360")


func _test_wave_resources(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog()
	var quotas: Array[int] = [40, 60, 85, 115, 150, 190, 240, 300]
	for index: int in range(8):
		var wave: WaveDefinition = catalog.wave(index + 1)
		assertions.expect_equal(index + 1, wave.wave_number, "W%d number" % (index + 1))
		assertions.expect_float(60.0, wave.duration_seconds, "W%d duration" % (index + 1))
		assertions.expect_equal(quotas[index], wave.kill_quota, "W%d quota" % (index + 1))
	assertions.expect_float(30.0, catalog.wave(4).elite_spawn_elapsed, "W4 elite at elapsed 30")
	assertions.expect_true(catalog.wave(8).boss_at_start, "W8 boss at start")


func _test_spawn_rng(assertions: Variant) -> void:
	var accept_rng := TraceRng.new()
	accept_rng.float_values = [0.1, 0.5]
	accept_rng.int_values = [0]
	var accept_sim: CombatSimulation = _new_simulation(1, accept_rng)
	accept_sim.state.spawn_credit = 1.0
	var accepted: Array[EnemyEntity] = accept_sim.enemy_system.resolve_normal_spawns(Vector2.ZERO, 1)
	assertions.expect_equal(1, accepted.size(), "normal spawn accepted")
	assertions.expect_equal(["randf", "randi_range", "randf"], accept_rng.calls, "type then edge then coordinate RNG order")
	assertions.expect_equal(Vector2(-14.25, 0.0), accepted[0].position, "accepted edge coordinate")

	var ordinal_rng := TraceRng.new()
	ordinal_rng.float_values = [0.0, 0.5]
	ordinal_rng.int_values = [0]
	var ordinal_sim: CombatSimulation = _new_simulation(8, ordinal_rng)
	ordinal_sim.state.spawn_credit = 1.0
	var ordinal_spawn: Array[EnemyEntity] = ordinal_sim.enemy_system.resolve_normal_spawns(Vector2.ZERO, 1)
	assertions.expect_equal(1, ordinal_spawn.size(), "ordinal selector fixture spawns once")
	assertions.expect_equal(
		GameTypes.EnemyType.ARMORED,
		ordinal_spawn[0].enemy_type,
		"W8 randf 0 selects first positive fixed-ID candidate armored",
	)

	var reject_rng := TraceRng.new()
	reject_rng.float_values.append(0.1)
	for _index: int in range(16):
		reject_rng.float_values.append(0.5)
		reject_rng.int_values.append(0)
	var reject_sim: CombatSimulation = _new_simulation(1, reject_rng)
	reject_sim.state.spawn_credit = 1.0
	var rejected_then_fallback: Array[EnemyEntity] = reject_sim.enemy_system.resolve_normal_spawns(Vector2(-14.25, 0.0), 1)
	assertions.expect_equal(1 + 16 * 2, reject_rng.calls.size(), "16 rejects consume no fallback RNG")
	assertions.expect_equal(Vector2(14.25, 8.25), rejected_then_fallback[0].position, "16 rejects use first farthest fixed corner")

	var blocked_rng := TraceRng.new()
	var blocked_sim: CombatSimulation = _new_simulation(8, blocked_rng)
	blocked_sim.state.non_boss_spawned = 299
	blocked_sim.state.spawn_credit = 1.0
	var blocked: Array[EnemyEntity] = blocked_sim.enemy_system.resolve_normal_spawns(Vector2.ZERO, 1)
	assertions.expect_equal(0, blocked.size(), "W8 blocked normal spawn creates none")
	assertions.expect_equal(0, blocked_rng.calls.size(), "blocked normal spawn consumes zero RNG")
	assertions.expect_float(1.0, blocked_sim.state.spawn_credit, "blocked normal spawn retains credit")


func _test_boss_priority_and_born_tick(assertions: Variant) -> void:
	var rng := TraceRng.new()
	rng.range_values = [0.0]
	rng.float_values = [0.1, 0.2, 0.3]
	var simulation: CombatSimulation = _new_simulation(8, rng)
	var boss: EnemyEntity = simulation.enemy_system.enemy_store.get_by_id(0)
	for index: int in range(EnemyStore.CAPACITY - 4):
		simulation.enemy_system.enemy_store.try_spawn(
			simulation.state,
			GameTypes.EnemyType.TRACKER,
			simulation.catalog.enemy(&"tracker"),
			Vector2(float(index % 15) - 7.0, float(index % 9) - 4.0),
			1.0,
			1.0,
			0,
		)
	assertions.expect_equal(3, simulation.enemy_system.enemy_store.free_count(), "boss priority fixture has three enemy slots")
	simulation.state.non_boss_spawned = 296
	simulation.state.spawn_credit = 1.0
	simulation.state.physics_tick = 360
	boss.summon_elapsed = boss.definition.summon_interval
	var ids: Array[int] = simulation.enemy_system.snapshot_ids()
	var summoned: Array[EnemyEntity] = simulation.enemy_system.resolve_ready_boss_summons(ids, Vector2.ZERO, 360)
	var credit_before: float = simulation.state.spawn_credit
	var normal: Array[EnemyEntity] = simulation.enemy_system.resolve_normal_spawns(Vector2.ZERO, 360)
	assertions.expect_equal(3, summoned.size(), "boss summon consumes all three remaining slots")
	assertions.expect_equal(0, normal.size(), "normal spawn gets zero slots after summon")
	assertions.expect_float(credit_before, simulation.state.spawn_credit, "normal spawn credit retained after summon priority")
	assertions.expect_equal(["randf_range", "randf", "randf", "randf"], rng.calls, "boss consumes angle and three type rolls first")
	assertions.expect_equal(summoned[0].entity_id + 1, summoned[1].entity_id, "summon entity ids consecutive first")
	assertions.expect_equal(summoned[1].entity_id + 1, summoned[2].entity_id, "summon entity ids consecutive second")
	for enemy: EnemyEntity in summoned:
		assertions.expect_false(enemy.is_targetable(360), "summoned enemy excluded on born tick")
		assertions.expect_true(enemy.is_targetable(361), "summoned enemy eligible next tick")

	var projectile_sim: CombatSimulation = _new_simulation(1)
	_freeze_fixture(projectile_sim)
	var ranged: EnemyEntity = projectile_sim.spawn_fixture_enemy(GameTypes.EnemyType.RANGED, Vector2(7.0, 0.0))
	ranged.special_elapsed = ranged.definition.special_interval
	var old_snapshot: Array[Vector2i] = projectile_sim.projectile_pool.snapshot_active()
	projectile_sim.enemy_system.resolve_ready_enemy_special_actions([ranged.entity_id], Vector2.ZERO, 10, projectile_sim.projectile_pool)
	assertions.expect_equal(0, old_snapshot.size(), "enemy projectile absent from tick-start snapshot")
	var enemy_bullet: ProjectileState = _first_active_projectile(projectile_sim.projectile_pool)
	assertions.expect_equal(10, enemy_bullet.born_physics_tick, "enemy bullet born tick recorded")
	var bullet_position: Vector2 = enemy_bullet.position
	projectile_sim.weapon_system.move_snapshot_projectiles(old_snapshot, DELTA, 10)
	assertions.expect_equal(bullet_position, enemy_bullet.position, "enemy bullet does not move on born tick")

	var bow_sim: CombatSimulation = _new_weapon_simulation(GameTypes.MainWeaponType.BOW)
	_freeze_fixture(bow_sim)
	bow_sim.spawn_fixture_enemy(GameTypes.EnemyType.TRACKER, Vector2(10.0, 0.0))
	var ally_old_snapshot: Array[Vector2i] = bow_sim.projectile_pool.snapshot_active()
	bow_sim.state.physics_tick = 20
	bow_sim.weapon_system.try_primary_attack(Vector2.ZERO, bow_sim.enemy_system.enemy_store, bow_sim.enemy_system.uniform_grid, 20)
	var ally_bullet: ProjectileState = _first_active_projectile(bow_sim.projectile_pool)
	assertions.expect_equal(0, ally_old_snapshot.size(), "ally projectile absent from tick-start snapshot")
	assertions.expect_equal(20, ally_bullet.born_physics_tick, "ally projectile born tick recorded")


func _test_w4_order(assertions: Variant) -> void:
	var rng := TraceRng.new()
	rng.float_values = [0.1, 0.5]
	rng.int_values = [0]
	var simulation: CombatSimulation = _new_simulation(4, rng)
	simulation.state.time_remaining = 30.0 + DELTA
	simulation.state.spawn_credit = 1.0
	simulation.step(Vector2.ZERO, DELTA)
	var ids: Array[int] = simulation.enemy_system.snapshot_ids()
	assertions.expect_true(ids.size() >= 2, "W4 overlap creates normal and elite")
	var normal: EnemyEntity = simulation.enemy_system.enemy_store.get_by_id(ids[0])
	var elite: EnemyEntity = simulation.enemy_system.enemy_store.get_by_id(ids[1])
	assertions.expect_true(normal.enemy_type != GameTypes.EnemyType.ELITE, "W4 normal gets smaller entity_id")
	assertions.expect_equal(GameTypes.EnemyType.ELITE, elite.enemy_type, "W4 elite gets following entity_id")
	simulation.enemy_system.resolve_w4_elite_after_countdown(Vector2.ZERO, simulation.state.physics_tick + 1)
	var elite_count: int = 0
	for entity: EnemyEntity in simulation.enemy_system.enemy_store.entities:
		if entity.enemy_type == GameTypes.EnemyType.ELITE:
			elite_count += 1
	assertions.expect_equal(1, elite_count, "W4 creates exactly one ELITE")


func _test_deterministic_replay_and_dense_500(assertions: Variant) -> void:
	var first: CombatSimulation = _new_simulation(3)
	var second: CombatSimulation = _new_simulation(3)
	first.freeze_enemy_ai = true
	first.freeze_enemy_timers = true
	first.freeze_countdown = true
	second.freeze_enemy_ai = true
	second.freeze_enemy_timers = true
	second.freeze_countdown = true
	for _tick: int in range(240):
		first.step(Vector2(0.6, -0.2), DELTA)
		second.step(Vector2(0.6, -0.2), DELTA)
	var first_ids: Array[int] = first.enemy_system.snapshot_ids()
	var second_ids: Array[int] = second.enemy_system.snapshot_ids()
	assertions.expect_equal(first_ids, second_ids, "same seed and input reproduce entity ids")
	for index: int in range(first_ids.size()):
		var first_enemy: EnemyEntity = first.enemy_system.enemy_store.get_by_id(first_ids[index])
		var second_enemy: EnemyEntity = second.enemy_system.enemy_store.get_by_id(second_ids[index])
		assertions.expect_equal(first_enemy.enemy_type, second_enemy.enemy_type, "replay enemy type %d" % index)
		assertions.expect_equal(first_enemy.position, second_enemy.position, "replay spawn position %d" % index)

	var dense: CombatSimulation = _new_simulation(1)
	dense.freeze_normal_spawn = true
	for index: int in range(500):
		dense.spawn_fixture_enemy(
			GameTypes.EnemyType.TRACKER,
			Vector2(float(index % 30) - 14.5, float(index % 18) - 8.5),
		)
	assertions.expect_equal(500, dense.enemy_system.enemy_store.active_count(), "dense enemy array holds 500")
	assertions.expect_equal(0, dense.enemy_system.enemy_store.overflow_count, "500 enemies do not overflow capacity 768")
	for index: int in range(500, EnemyStore.CAPACITY):
		dense.spawn_fixture_enemy(
			GameTypes.EnemyType.TRACKER,
			Vector2(float(index % 30) - 14.5, float(index % 18) - 8.5),
		)
	var next_entity_id_before_overflow: int = dense.state.next_entity_id
	dense.state.spawn_credit = 1.0
	var denied_spawns: Array[EnemyEntity] = dense.enemy_system.resolve_normal_spawns(Vector2.ZERO, 1)
	assertions.expect_equal(0, denied_spawns.size(), "full enemy pool denies normal spawn")
	assertions.expect_equal(1, dense.enemy_system.enemy_store.overflow_count, "full enemy pool records one denied acquisition")
	assertions.expect_equal(next_entity_id_before_overflow, dense.state.next_entity_id, "denied spawn consumes no entity id")
	assertions.expect_float(1.0, dense.state.spawn_credit, "denied spawn retains credit")
	var arena := (ResourceLoader.load("res://scenes/gameplay/arena_combat.tscn") as PackedScene).instantiate()
	var enemy_named_nodes: int = 0
	for child: Node in arena.find_children("EnemyEntity*", "Node", true, false):
		if not child is MultiMeshInstance3D:
			enemy_named_nodes += 1
	assertions.expect_equal(0, enemy_named_nodes, "no per-enemy Node exists")
	arena.free()


func _test_hud_fixed_text(assertions: Variant, context: Dictionary) -> void:
	var packed := ResourceLoader.load("res://scenes/ui/combat_hud.tscn") as PackedScene
	var hud := packed.instantiate() as CombatHud
	context["tree"].root.add_child(hud)
	await context["tree"].process_frame
	var values: Dictionary = {
		"wave_number": 8,
		"time_remaining": 29.01,
		"wave_kills": 299,
		"kill_quota": 300,
		"current_hp": 100.0,
		"max_hp": 100.0,
		"weapon_name": "木の棒",
		"wave_chests": 0,
		"wave_cleared": false,
		"boss_defeated": false,
		"non_boss_spawned": 299,
		"active_enemy": 1,
		"active_projectile": 2,
		"active_vfx": 3,
		"enemy_pool_overflow": 4,
		"projectile_pool_overflow": 5,
		"vfx_pool_overflow": 6,
	}
	hud.update_from_snapshot(CombatSnapshot.new(Vector2.ZERO, [], [], [], values))
	var time_label := hud.get_node("CombatPanel/Content/WaveRow/TimeValue") as Label
	var skill_zero := hud.get_node("SkillPanel/Content/SkillSlot0/SkillSlot0Value") as Label
	var skill_one := hud.get_node("SkillPanel/Content/SkillSlot1/SkillSlot1Value") as Label
	var requirement := hud.get_node("BossGate/BossRequirement") as Label
	var stopped := hud.get_node("BossGate/BossSpawnStatus") as Label
	assertions.expect_equal("残り 30 秒", time_label.text, "HUD remaining seconds rounds upward")
	assertions.expect_equal("未装着", skill_zero.text, "HUD skill slot zero reserved and unmounted")
	assertions.expect_equal("未装着", skill_one.text, "HUD skill slot one reserved and unmounted")
	assertions.expect_equal("300到達にはボス撃破が必要", requirement.text, "HUD boss requirement exact")
	assertions.expect_equal("通常敵スポーン停止中", stopped.text, "HUD 299 stop exact")
	assertions.expect_true(stopped.visible, "HUD 299 stop visible")
	values["boss_defeated"] = true
	hud.update_from_snapshot(CombatSnapshot.new(Vector2.ZERO, [], [], [], values))
	assertions.expect_equal("ボス撃破済み／通常敵スポーン中", requirement.text, "HUD boss defeated replacement exact")
	assertions.expect_false(stopped.visible, "HUD stop hidden after boss defeat")
	values["wave_cleared"] = true
	hud.update_from_snapshot(CombatSnapshot.new(Vector2.ZERO, [], [], [], values))
	assertions.expect_true((hud.get_node("BonusTime") as Label).visible, "HUD BONUS TIME visible after clear")
	if OS.is_debug_build():
		var debug_overlay := hud.get_node("DebugOverlay") as PanelContainer
		var debug_overflow := hud.get_node("DebugOverlay/Content/DebugOverflow") as Label
		assertions.expect_true(debug_overlay.visible, "debug HUD overlay visible only in debug build")
		assertions.expect_true("ENEMY 4" in debug_overflow.text, "debug HUD enemy overflow")
		assertions.expect_true("PROJECTILE 5" in debug_overflow.text, "debug HUD projectile overflow")
		assertions.expect_true("VFX 6" in debug_overflow.text, "debug HUD VFX overflow")
	context["tree"].root.remove_child(hud)
	hud.free()


func _test_qa_item_builder_validation(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog()
	var normal_affixes: Array[AffixRoll] = [_qa_affix(&"max_hp", 10.0)]
	var normal: ItemInstance = QaItemBuilderScript.build(
		catalog,
		"qa-builder-normal",
		GameTypes.EquipmentSlot.MAIN_WEAPON,
		GameTypes.Rarity.COMMON,
		GameTypes.MainWeaponType.BOW,
		normal_affixes,
		&"",
		false,
	)
	assertions.expect_true(normal != null, "QA builder accepts valid common weapon")
	if normal != null:
		var expected_seed: int = SeedService.derive(20260827, &"qa-item:qa-builder-normal")
		assertions.expect_equal(expected_seed, normal.item_seed, "QA builder uses fixed item-seed domain")
		assertions.expect_equal(
			NameGeneratorScript.generate(
				expected_seed,
				GameTypes.EquipmentSlot.MAIN_WEAPON,
				GameTypes.MainWeaponType.BOW,
				normal.affixes,
			),
			normal.display_name,
			"QA builder derives normal display name from item seed",
		)
		assertions.expect_equal(1, normal.affixes.size(), "common normal item has one affix")
		assertions.expect_false(normal.affixes[0] == normal_affixes[0], "QA builder copies fixed affix values")

	var unique_affixes: Array[AffixRoll] = [_qa_affix(&"damage_pct", 14.0)]
	var unique: ItemInstance = QaItemBuilderScript.build(
		catalog,
		"qa-builder-unique",
		GameTypes.EquipmentSlot.SUB_WEAPON,
		GameTypes.Rarity.RARE,
		GameTypes.MainWeaponType.UNCLASSIFIED,
		unique_affixes,
		&"bloodied_dagger",
		false,
	)
	assertions.expect_true(unique != null, "QA builder accepts valid unique with halved affix count")
	if unique != null:
		assertions.expect_equal(1, unique.affixes.size(), "Rare unique uses floor(2 / 2) affixes")
		assertions.expect_equal(
			catalog.unique(&"bloodied_dagger").display_name,
			unique.display_name,
			"QA builder uses UniqueDefinition display name",
		)

	var no_affixes: Array[AffixRoll] = []
	assertions.expect_equal(
		null,
		QaItemBuilderScript.build(
			catalog,
			"qa-builder-wrong-count",
			GameTypes.EquipmentSlot.MAIN_WEAPON,
			GameTypes.Rarity.COMMON,
			GameTypes.MainWeaponType.BOW,
			no_affixes,
		),
		"QA builder rejects rarity affix-count mismatch",
	)
	var wrong_value: Array[AffixRoll] = [_qa_affix(&"max_hp", 10.000001)]
	assertions.expect_equal(
		null,
		QaItemBuilderScript.build(
			catalog,
			"qa-builder-wrong-value",
			GameTypes.EquipmentSlot.MAIN_WEAPON,
			GameTypes.Rarity.COMMON,
			GameTypes.MainWeaponType.BOW,
			wrong_value,
		),
		"QA builder rejects even a near non-table affix value",
	)
	var wrong_pool: Array[AffixRoll] = [_qa_affix(&"pierce", 1.0)]
	assertions.expect_equal(
		null,
		QaItemBuilderScript.build(
			catalog,
			"qa-builder-wrong-pool",
			GameTypes.EquipmentSlot.HEAD,
			GameTypes.Rarity.COMMON,
			GameTypes.MainWeaponType.UNCLASSIFIED,
			wrong_pool,
		),
		"QA builder rejects affix outside common and slot pools",
	)
	var unique_wrong_slot: Array[AffixRoll] = [_qa_affix(&"skill_power_pct", 18.0)]
	assertions.expect_equal(
		null,
		QaItemBuilderScript.build(
			catalog,
			"qa-builder-wrong-unique-slot",
			GameTypes.EquipmentSlot.HEAD,
			GameTypes.Rarity.RARE,
			GameTypes.MainWeaponType.UNCLASSIFIED,
			unique_wrong_slot,
			&"bloodied_dagger",
		),
		"QA builder rejects UniqueDefinition slot mismatch",
	)
	var unique_wrong_count: Array[AffixRoll] = [
		_qa_affix(&"damage_pct", 14.0),
		_qa_affix(&"max_hp", 18.0),
	]
	assertions.expect_equal(
		null,
		QaItemBuilderScript.build(
			catalog,
			"qa-builder-wrong-unique-count",
			GameTypes.EquipmentSlot.SUB_WEAPON,
			GameTypes.Rarity.RARE,
			GameTypes.MainWeaponType.UNCLASSIFIED,
			unique_wrong_count,
			&"bloodied_dagger",
		),
		"QA builder rejects unique affix count before halving",
	)
	assertions.expect_equal(
		null,
		QaItemBuilderScript.build(
			DefinitionCatalog.new(),
			"qa-builder-invalid-catalog",
			GameTypes.EquipmentSlot.MAIN_WEAPON,
			GameTypes.Rarity.COMMON,
			GameTypes.MainWeaponType.BOW,
			normal_affixes,
		),
		"QA builder rejects unvalidated catalog",
	)


func _test_qa_scenarios(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog()
	for scenario_id: String in QaScenarioFactory.VALID_IDS:
		var result: Dictionary = QaScenarioFactory.build(scenario_id, catalog)
		assertions.expect_true(result.get("valid", false), "%s QA fixture valid" % scenario_id)
		assertions.expect_false(bool(result.get("tutorial_active", true)), "%s tutorial inactive" % scenario_id)
		assertions.expect_true(bool(result.get("rng_unchanged", false)), "%s mutable RNG unchanged" % scenario_id)
		var state: RunState = result["state"] as RunState
		match scenario_id:
			"reward_controls":
				assertions.expect_equal(GameTypes.RunPhase.REWARD_REVEAL, state.phase, "reward_controls starts REWARD_REVEAL")
				assertions.expect_equal(3, state.wave_number, "reward_controls starts W3")
			"inventory_controller":
				assertions.expect_equal(GameTypes.RunPhase.INVENTORY, state.phase, "inventory_controller starts INVENTORY")
				assertions.expect_equal(7, state.wave_number, "inventory_controller starts after W7")
			"result_controller":
				assertions.expect_equal(GameTypes.RunPhase.RESULT, state.phase, "result_controller starts RESULT")
				assertions.expect_equal(8, state.wave_number, "result_controller represents W8 clear")
			"immortal_100":
				assertions.expect_equal(GameTypes.RunPhase.COMBAT, state.phase, "immortal_100 starts COMBAT")
				assertions.expect_equal(5, state.wave_number, "immortal_100 starts W5")
			"boss_299":
				assertions.expect_equal(GameTypes.RunPhase.COMBAT, state.phase, "boss_299 starts COMBAT")
				assertions.expect_equal(8, state.wave_number, "boss_299 starts W8")
			_:
				assertions.expect_equal(GameTypes.RunPhase.COMBAT, state.phase, "%s starts COMBAT" % scenario_id)
				assertions.expect_equal(1, state.wave_number, "%s starts W1" % scenario_id)
	assertions.expect_false(QaScenarioFactory.build("unknown", catalog).get("valid", true), "unknown QA ID rejected")
	for weapon_id: String in ["weapon_bow", "weapon_staff", "weapon_sword"]:
		var weapon_result: Dictionary = QaScenarioFactory.build(weapon_id, catalog)
		var weapon_state: RunState = weapon_result["state"] as RunState
		assertions.expect_true(weapon_state.inventory[0] != null, "%s keeps wood stick at inventory index 0" % weapon_id)
		var equipped_weapon: ItemInstance = weapon_state.equipped[GameTypes.EquipmentSlot.MAIN_WEAPON]
		assertions.expect_equal(
			SeedService.derive(QaScenarioFactory.FIXED_SEED, StringName("qa-item:" + equipped_weapon.item_id)),
			equipped_weapon.item_seed,
			"%s uses fixed QA item-seed domain" % weapon_id,
		)
		assertions.expect_equal(
			NameGeneratorScript.generate(
				equipped_weapon.item_seed,
				equipped_weapon.slot,
				equipped_weapon.main_weapon_type,
				equipped_weapon.affixes,
			),
			equipped_weapon.display_name,
			"%s uses seeded normal display name" % weapon_id,
		)
		assertions.expect_equal(20, (weapon_result["simulation"] as CombatSimulation).enemy_system.enemy_store.active_count(), "%s has 20 trackers" % weapon_id)
	var pre_death: Dictionary = QaScenarioFactory.build("pre_quota_death", catalog)
	var pre_death_reward: RewardRoll = (pre_death["state"] as RunState).unopened_rewards[0]
	assertions.expect_equal(
		SeedService.derive(QaScenarioFactory.FIXED_SEED, &"qa-item:qa-item-death"),
		pre_death_reward.equipment.item_seed,
		"death fixture uses fixed QA item-seed domain",
	)
	(pre_death["simulation"] as CombatSimulation).step(Vector2.ZERO, DELTA)
	assertions.expect_equal(GameTypes.RunPhase.FAILED, (pre_death["state"] as RunState).phase, "pre-quota death fails")
	assertions.expect_equal(0, (pre_death["state"] as RunState).unopened_rewards.size(), "pre-quota death discards reward")
	var timeout: Dictionary = QaScenarioFactory.build("pre_quota_timeout", catalog)
	(timeout["simulation"] as CombatSimulation).step(Vector2.ZERO, DELTA)
	assertions.expect_equal(GameTypes.RunPhase.FAILED, (timeout["state"] as RunState).phase, "pre-quota timeout fails")
	var post_death: Dictionary = QaScenarioFactory.build("post_quota_death", catalog)
	(post_death["simulation"] as CombatSimulation).step(Vector2.ZERO, DELTA)
	assertions.expect_equal(GameTypes.RunPhase.REWARD_REVEAL, (post_death["state"] as RunState).phase, "post-quota death succeeds")
	assertions.expect_equal(1, (post_death["state"] as RunState).unopened_rewards.size(), "post-quota reward retained")


func _qa_affix(affix_id: StringName, value: float) -> AffixRoll:
	var affix := AffixRoll.new()
	affix.affix_id = affix_id
	affix.value = value
	return affix


func _catalog() -> DefinitionCatalog:
	var catalog := DefinitionCatalog.new()
	catalog.load_and_validate()
	return catalog


func _new_simulation(wave_number: int, rng_source: Variant = null) -> CombatSimulation:
	var catalog: DefinitionCatalog = _catalog()
	var state: RunState = RunStateFactory.create(20260827, catalog.wave(wave_number))
	state.wave_number = wave_number
	state.time_remaining = catalog.wave(wave_number).duration_seconds
	var simulation := CombatSimulation.new()
	simulation.initialize(state, catalog, rng_source)
	return simulation


func _new_weapon_simulation(weapon_type: GameTypes.MainWeaponType) -> CombatSimulation:
	var catalog: DefinitionCatalog = _catalog()
	var state: RunState = RunStateFactory.create(20260827, catalog.wave(1))
	var weapon := ItemInstance.new()
	weapon.item_id = "scenario-weapon"
	weapon.slot = GameTypes.EquipmentSlot.MAIN_WEAPON
	weapon.main_weapon_type = weapon_type
	weapon.rarity = GameTypes.Rarity.COMMON
	weapon.display_name = String(GameTypes.main_weapon_type_to_key(weapon_type))
	state.equipped[GameTypes.EquipmentSlot.MAIN_WEAPON] = weapon
	var simulation := CombatSimulation.new()
	simulation.initialize(state, catalog)
	return simulation


func _freeze_fixture(simulation: CombatSimulation) -> void:
	simulation.freeze_enemy_ai = true
	simulation.freeze_enemy_timers = true
	simulation.freeze_normal_spawn = true
	simulation.freeze_countdown = true


func _first_active_projectile(pool: ProjectilePool) -> ProjectileState:
	for projectile: ProjectileState in pool.slots:
		if projectile.active:
			return projectile
	return null
