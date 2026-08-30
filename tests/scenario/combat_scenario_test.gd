extends RefCounted


func test_names() -> PackedStringArray:
	return PackedStringArray([
		"three_duplicate_weapons_attack_independently",
		"weapon_phase_is_reproducible_rng_free_and_waits_ready",
		"sword_staff_bow_use_only_applicable_charm_effects",
	])


func run_test(test_name: String, assertions: Variant, _context: Dictionary) -> void:
	match test_name:
		"three_duplicate_weapons_attack_independently":
			_test_three_duplicates(assertions)
		"weapon_phase_is_reproducible_rng_free_and_waits_ready":
			_test_phase_and_wait(assertions)
		"sword_staff_bow_use_only_applicable_charm_effects":
			_test_geometry(assertions)
		_:
			assertions.expect_true(false, "registered three-weapon combat test")


func _test_three_duplicates(assertions: Variant) -> void:
	var setup: Dictionary = _simulation_with_weapon(assertions, GameTypes.WeaponType.BOW)
	var simulation: CombatSimulation = setup["simulation"]
	var catalog: DefinitionCatalog = setup["catalog"]
	if not catalog.is_valid:
		return
	for index: int in range(3):
		simulation.state.equipped[GameTypes.weapon_slots()[index]] = QaItemBuilder.weapon(
			catalog,
			"duplicate-bow-%d" % index,
			GameTypes.WeaponType.BOW,
		)
	simulation.weapon_system.initialize(simulation.state, catalog, simulation.projectile_pool, simulation.event_router)
	simulation.spawn_fixture_enemy(GameTypes.EnemyType.ARMORED, Vector2(4.0, 0.0))
	var target: EnemyEntity = simulation.spawn_fixture_enemy(GameTypes.EnemyType.ARMORED, Vector2(2.0, 0.0))
	_make_all_ready(simulation.weapon_system, simulation.state)
	var results: Array[Dictionary] = simulation.weapon_system.try_attacks_detailed(
		Vector2.ZERO,
		simulation.enemy_system.enemy_store,
		simulation.enemy_system.uniform_grid,
		1,
	)
	assertions.expect_equal(3, results.size(), "three duplicate weapons all generate attacks")
	assertions.expect_equal(3, simulation.projectile_pool.active_count(), "duplicate weapons keep separate projectiles")
	var sources: Dictionary[StringName, bool] = {}
	for result: Dictionary in results:
		assertions.expect_equal(target.entity_id, int(result["target_entity_id"]), "all weapons independently choose the same nearest target")
		sources[StringName(result["source_effect_id"])] = true
	assertions.expect_equal(3, sources.size(), "each duplicate weapon has its own attack source id")
	for slot: GameTypes.EquipmentSlot in GameTypes.weapon_slots():
		assertions.expect_float(0.0, float(simulation.weapon_system.attack_elapsed_by_slot[int(slot)]), "each duplicate timer resets independently")


func _test_phase_and_wait(assertions: Variant) -> void:
	var catalog := DefinitionCatalog.new()
	assertions.expect_true(catalog.load_and_validate(), "phase catalog valid")
	if not catalog.is_valid:
		return
	var first: RunState = _three_weapon_state(catalog, 8899, 3)
	var rng_before: Dictionary = _rng_snapshot(first)
	var first_system := WeaponSystem.new()
	first_system.initialize(first, catalog, ProjectilePool.new(), CombatEventRouter.new())
	var first_phases: Dictionary = first_system.attack_elapsed_by_slot.duplicate(true)
	assertions.expect_equal(rng_before, _rng_snapshot(first), "initial phases consume no gameplay RNG")
	var second: RunState = _three_weapon_state(catalog, 8899, 3)
	var second_system := WeaponSystem.new()
	second_system.initialize(second, catalog, ProjectilePool.new(), CombatEventRouter.new())
	assertions.expect_equal(first_phases, second_system.attack_elapsed_by_slot, "seed wave and item IDs reproduce all phases")
	var next_wave: RunState = _three_weapon_state(catalog, 8899, 4)
	var next_system := WeaponSystem.new()
	next_system.initialize(next_wave, catalog, ProjectilePool.new(), CombatEventRouter.new())
	assertions.expect_not_equal(first_phases, next_system.attack_elapsed_by_slot, "wave number changes deterministic phases")

	var wait_state: RunState = _three_weapon_state(catalog, 9911, 1)
	wait_state.equipped[GameTypes.EquipmentSlot.WEAPON_2] = null
	wait_state.equipped[GameTypes.EquipmentSlot.WEAPON_3] = null
	var pool := ProjectilePool.new()
	var wait_system := WeaponSystem.new()
	wait_system.initialize(wait_state, catalog, pool, CombatEventRouter.new())
	var slot := GameTypes.EquipmentSlot.WEAPON_1
	wait_system.attack_elapsed_by_slot[int(slot)] = wait_system.effective_interval(wait_state.equipped[slot])
	var store := EnemyStore.new()
	var grid := UniformGrid.new()
	assertions.expect_equal(0, wait_system.try_attacks_detailed(Vector2.ZERO, store, grid, 1).size(), "ready weapon does not fire without a target")
	assertions.expect_true(wait_system.is_attack_ready(slot), "no-target weapon remains ready")
	var enemy: EnemyEntity = store.try_spawn(wait_state, GameTypes.EnemyType.TRACKER, catalog.enemy(&"tracker"), Vector2(3.0, 0.0), 1.0, 1.0, 0)
	grid.insert(enemy.entity_id, enemy.position)
	assertions.expect_equal(1, wait_system.try_attacks_detailed(Vector2.ZERO, store, grid, 1).size(), "ready weapon fires immediately on contact")


func _test_geometry(assertions: Variant) -> void:
	var setup: Dictionary = _simulation_with_weapon(assertions, GameTypes.WeaponType.SWORD)
	var simulation: CombatSimulation = setup["simulation"]
	var catalog: DefinitionCatalog = setup["catalog"]
	if not catalog.is_valid:
		return
	var charm: ItemInstance = QaItemBuilder.charm(
		catalog,
		"geometry-charm",
		GameTypes.Rarity.EPIC,
		[&"area_pct", &"pierce", &"damage_pct"],
	)
	simulation.state.equipped[GameTypes.EquipmentSlot.CHARM_1] = charm
	simulation.weapon_system.initialize(simulation.state, catalog, simulation.projectile_pool, simulation.event_router)
	var sword: ItemInstance = simulation.state.equipped[GameTypes.EquipmentSlot.WEAPON_1]
	assertions.expect_float(2.4 * 1.30, simulation.weapon_system.effective_range(sword), "area increases sword range only")
	assertions.expect_float(14.0 * 1.24, simulation.weapon_system.effective_damage(sword), "damage charm applies to every weapon")
	var sword_near: EnemyEntity = simulation.spawn_fixture_enemy(GameTypes.EnemyType.ARMORED, Vector2(1.0, 0.0))
	var sword_inside: EnemyEntity = simulation.spawn_fixture_enemy(GameTypes.EnemyType.ARMORED, Vector2(3.0, 0.0))
	var sword_outside: EnemyEntity = simulation.spawn_fixture_enemy(GameTypes.EnemyType.ARMORED, Vector2(0.0, 2.0))
	_make_all_ready(simulation.weapon_system, simulation.state)
	var sword_results: Array[Dictionary] = simulation.weapon_system.try_attacks_detailed(Vector2.ZERO, simulation.enemy_system.enemy_store, simulation.enemy_system.uniform_grid, 1)
	var sword_hit_ids: Array[int] = _hit_ids(sword_results[0])
	assertions.expect_true(sword_near.entity_id in sword_hit_ids, "sword hits nearest in fixed 120-degree fan")
	assertions.expect_true(sword_inside.entity_id in sword_hit_ids, "area-expanded sword reaches forward target")
	assertions.expect_false(sword_outside.entity_id in sword_hit_ids, "sword fan angle stays 120 degrees")

	setup = _simulation_with_weapon(assertions, GameTypes.WeaponType.STAFF, charm)
	simulation = setup["simulation"]
	var staff_target: EnemyEntity = simulation.spawn_fixture_enemy(GameTypes.EnemyType.ARMORED, Vector2(5.0, 0.0))
	var staff_near: EnemyEntity = simulation.spawn_fixture_enemy(GameTypes.EnemyType.ARMORED, Vector2(5.0, 2.8))
	var staff_far: EnemyEntity = simulation.spawn_fixture_enemy(GameTypes.EnemyType.ARMORED, Vector2(5.0, 4.0))
	_make_all_ready(simulation.weapon_system, simulation.state)
	simulation.weapon_system.try_attacks_detailed(Vector2.ZERO, simulation.enemy_system.enemy_store, simulation.enemy_system.uniform_grid, 1)
	var staff_projectiles: Array[Vector2i] = simulation.projectile_pool.snapshot_active()
	var staff_state: ProjectileState = simulation.projectile_pool.resolve_snapshot_entry(staff_projectiles[0])
	assertions.expect_equal(1, staff_state.pierce_remaining, "pierce charm does not affect staff")
	simulation.weapon_system.move_snapshot_projectiles(staff_projectiles, 0.4, 2)
	var staff_hits: Array[Dictionary] = simulation.weapon_system.resolve_ally_projectile(staff_projectiles[0], simulation.enemy_system.enemy_store, simulation.enemy_system.uniform_grid, 2)
	var staff_ids: Array[int] = _record_ids(staff_hits)
	assertions.expect_true(staff_target.entity_id in staff_ids, "staff explosion hits impact target")
	assertions.expect_true(staff_near.entity_id in staff_ids, "area charm expands staff explosion")
	assertions.expect_false(staff_far.entity_id in staff_ids, "staff explosion still respects expanded radius")

	setup = _simulation_with_weapon(assertions, GameTypes.WeaponType.BOW, charm)
	simulation = setup["simulation"]
	var bow: ItemInstance = simulation.state.equipped[GameTypes.EquipmentSlot.WEAPON_1]
	assertions.expect_float(14.0, simulation.weapon_system.effective_range(bow), "area charm does not affect bow range")
	for x: float in [3.0, 5.0, 7.0, 9.0]:
		simulation.spawn_fixture_enemy(GameTypes.EnemyType.ARMORED, Vector2(x, 0.0))
	_make_all_ready(simulation.weapon_system, simulation.state)
	simulation.weapon_system.try_attacks_detailed(Vector2.ZERO, simulation.enemy_system.enemy_store, simulation.enemy_system.uniform_grid, 1)
	var bow_projectiles: Array[Vector2i] = simulation.projectile_pool.snapshot_active()
	var bow_state: ProjectileState = simulation.projectile_pool.resolve_snapshot_entry(bow_projectiles[0])
	assertions.expect_equal(3, bow_state.pierce_remaining, "Epic pierce two adds two extra bow hits")
	simulation.weapon_system.move_snapshot_projectiles(bow_projectiles, 0.5, 2)
	var bow_hits: Array[Dictionary] = simulation.weapon_system.resolve_ally_projectile(bow_projectiles[0], simulation.enemy_system.enemy_store, simulation.enemy_system.uniform_grid, 2)
	assertions.expect_equal(3, bow_hits.size(), "bow pierces exactly the configured extra targets")


func _simulation_with_weapon(
	assertions: Variant,
	weapon_type: GameTypes.WeaponType,
	charm: ItemInstance = null,
) -> Dictionary:
	var catalog := DefinitionCatalog.new()
	assertions.expect_true(catalog.load_and_validate(), "combat catalog valid: %s" % catalog.error_text)
	var state: RunState = RunStateFactory.create(20260827, catalog.wave(1))
	state.equipped[GameTypes.EquipmentSlot.WEAPON_1] = QaItemBuilder.weapon(catalog, "combat-weapon-%d" % weapon_type, weapon_type)
	state.equipped[GameTypes.EquipmentSlot.WEAPON_2] = null
	state.equipped[GameTypes.EquipmentSlot.WEAPON_3] = null
	state.equipped[GameTypes.EquipmentSlot.CHARM_1] = charm
	var simulation := CombatSimulation.new()
	simulation.initialize(state, catalog)
	simulation.enemy_system.enemy_store.clear()
	simulation.enemy_system.uniform_grid.clear()
	simulation.freeze_normal_spawn = true
	simulation.freeze_enemy_ai = true
	simulation.freeze_enemy_timers = true
	simulation.freeze_countdown = true
	return {"catalog": catalog, "simulation": simulation}


func _three_weapon_state(catalog: DefinitionCatalog, run_seed: int, wave_number: int) -> RunState:
	var state: RunState = RunStateFactory.create(run_seed, catalog.wave(wave_number))
	state.wave_number = wave_number
	var types: Array[GameTypes.WeaponType] = [GameTypes.WeaponType.BOW, GameTypes.WeaponType.STAFF, GameTypes.WeaponType.SWORD]
	for index: int in range(3):
		state.equipped[GameTypes.weapon_slots()[index]] = ItemFactory.create_weapon(run_seed, "phase-item-%d" % index, types[index], GameTypes.Rarity.COMMON, catalog)
	return state


func _make_all_ready(system: WeaponSystem, state: RunState) -> void:
	for slot: GameTypes.EquipmentSlot in GameTypes.weapon_slots():
		var item: ItemInstance = state.equipped.get(slot) as ItemInstance
		if item != null:
			system.attack_elapsed_by_slot[int(slot)] = system.effective_interval(item)


func _hit_ids(result: Dictionary) -> Array[int]:
	var ids: Array[int] = []
	for record: Dictionary in result.get("hits", []):
		ids.append(int(record["entity_id"]))
	return ids


func _record_ids(records: Array[Dictionary]) -> Array[int]:
	var ids: Array[int] = []
	for record: Dictionary in records:
		ids.append(int(record["entity_id"]))
	return ids


func _rng_snapshot(state: RunState) -> Dictionary:
	return {
		"combat": state.rng_streams.combat_rng.state,
		"loot": state.rng_streams.loot_rng.state,
		"fusion": state.rng_streams.fusion_rng.state,
	}
