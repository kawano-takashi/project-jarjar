extends RefCounted


func test_names() -> PackedStringArray:
	return PackedStringArray([
		"weapon_intervals_are_bounded_and_centered",
		"weapon_cooldowns_are_reproducible_and_rng_free",
		"recontact_attacks_follow_due_order_and_global_gap",
		"sword_staff_bow_use_only_applicable_charm_effects",
	])


func run_test(test_name: String, assertions: Variant, _context: Dictionary) -> void:
	match test_name:
		"weapon_intervals_are_bounded_and_centered":
			_test_interval_distribution(assertions)
		"weapon_cooldowns_are_reproducible_and_rng_free":
			_test_cooldown_reproducibility(assertions)
		"recontact_attacks_follow_due_order_and_global_gap":
			_test_recontact_stagger(assertions)
		"sword_staff_bow_use_only_applicable_charm_effects":
			_test_geometry(assertions)
		_:
			assertions.expect_true(false, "registered three-weapon combat test")


func _test_interval_distribution(assertions: Variant) -> void:
	const SAMPLE_COUNT: int = 20_000
	const NOMINAL_INTERVAL: float = 0.8
	for weapon_count: int in range(1, 4):
		var expected_delta: float = minf(
			float(weapon_count) * NOMINAL_INTERVAL / 5.0,
			float(weapon_count) * 5.0 / 60.0,
		)
		var bounds: Vector2 = WeaponSystem.interval_bounds(NOMINAL_INTERVAL, weapon_count)
		assertions.expect_float(
			maxf(WeaponSystem.MIN_ATTACK_GAP_SECONDS, NOMINAL_INTERVAL - expected_delta),
			bounds.x,
			"%d weapon lower interval bound follows Brotato formula" % weapon_count,
		)
		assertions.expect_float(
			NOMINAL_INTERVAL + expected_delta,
			bounds.y,
			"%d weapon upper interval bound follows Brotato formula" % weapon_count,
		)
		var rng := RandomNumberGenerator.new()
		rng.seed = 7300 + weapon_count
		var total: float = 0.0
		var samples_in_bounds: bool = true
		for _sample_index: int in range(SAMPLE_COUNT):
			var sampled: float = WeaponSystem.sample_interval(
				NOMINAL_INTERVAL,
				weapon_count,
				rng,
			)
			total += sampled
			if sampled < bounds.x or sampled > bounds.y:
				samples_in_bounds = false
		assertions.expect_true(samples_in_bounds, "%d weapon samples stay inside inclusive bounds" % weapon_count)
		var mean: float = total / float(SAMPLE_COUNT)
		assertions.expect_true(
			absf(mean - NOMINAL_INTERVAL) <= 0.01,
			"%d weapon sample mean stays within 0.01 seconds of nominal: %.6f" % [weapon_count, mean],
		)
	var floor_bounds: Vector2 = WeaponSystem.interval_bounds(0.05, 3)
	assertions.expect_float(0.05, floor_bounds.x, "lower interval keeps the 0.05 second floor")


func _test_cooldown_reproducibility(assertions: Variant) -> void:
	var catalog := DefinitionCatalog.new()
	assertions.expect_true(catalog.load_and_validate(), "cooldown catalog valid")
	if not catalog.is_valid:
		return
	var first: RunState = _three_weapon_state(catalog, 8899, 3)
	var rng_before: Dictionary = _rng_snapshot(first)
	var first_system := WeaponSystem.new()
	first_system.initialize(first, catalog, ProjectilePool.new(), CombatEventRouter.new())
	var first_phases: Dictionary = first_system.attack_elapsed_by_slot.duplicate(true)
	var first_intervals: Dictionary = first_system.attack_interval_by_slot.duplicate(true)
	for slot: GameTypes.EquipmentSlot in GameTypes.weapon_slots():
		var item: ItemInstance = first.equipped[slot]
		var phase_rng := RandomNumberGenerator.new()
		phase_rng.seed = SeedService.derive(
			first.run_seed,
			StringName("weapon_phase:%d:%s" % [first.wave_number, item.item_id]),
		)
		assertions.expect_float(
			phase_rng.randf() * float(first_intervals[int(slot)]),
			float(first_phases[int(slot)]),
			"initial phase scales the first sampled interval for slot %d" % int(slot),
		)
	assertions.expect_equal(rng_before, _rng_snapshot(first), "initial cooldowns consume no gameplay RNG")
	var second: RunState = _three_weapon_state(catalog, 8899, 3)
	var second_system := WeaponSystem.new()
	second_system.initialize(second, catalog, ProjectilePool.new(), CombatEventRouter.new())
	assertions.expect_equal(first_phases, second_system.attack_elapsed_by_slot, "seed wave and item IDs reproduce all phases")
	assertions.expect_equal(first_intervals, second_system.attack_interval_by_slot, "seed wave and item IDs reproduce first intervals")
	var first_sequence: Array = _interval_sequence(first_system, 100)
	var second_sequence: Array = _interval_sequence(second_system, 100)
	assertions.expect_equal(first_sequence, second_sequence, "seed wave and item IDs reproduce 100 cooldown rolls per weapon")
	assertions.expect_equal(rng_before, _rng_snapshot(first), "dedicated cooldown rolls leave combat loot and fusion RNG unchanged")
	var next_wave: RunState = _three_weapon_state(catalog, 8899, 4)
	var next_system := WeaponSystem.new()
	next_system.initialize(next_wave, catalog, ProjectilePool.new(), CombatEventRouter.new())
	assertions.expect_not_equal(first_phases, next_system.attack_elapsed_by_slot, "wave number changes deterministic phases")
	assertions.expect_not_equal(first_sequence, _interval_sequence(next_system, 100), "wave number changes cooldown sequences")
	var changed_item: RunState = _three_weapon_state(catalog, 8899, 3)
	changed_item.equipped[GameTypes.EquipmentSlot.WEAPON_1] = ItemFactory.create_weapon(
		changed_item.run_seed,
		"phase-item-changed",
		GameTypes.WeaponType.BOW,
		GameTypes.Rarity.COMMON,
		catalog,
	)
	var changed_item_system := WeaponSystem.new()
	changed_item_system.initialize(changed_item, catalog, ProjectilePool.new(), CombatEventRouter.new())
	assertions.expect_not_equal(first_sequence, _interval_sequence(changed_item_system, 100), "item ID changes cooldown sequences")


func _test_recontact_stagger(assertions: Variant) -> void:
	var setup: Dictionary = _simulation_with_weapon(assertions, GameTypes.WeaponType.BOW)
	var simulation: CombatSimulation = setup["simulation"]
	var catalog: DefinitionCatalog = setup["catalog"]
	if not catalog.is_valid:
		return
	var item_ids: Array[String] = ["stagger-b", "stagger-c", "stagger-a"]
	for index: int in range(3):
		simulation.state.equipped[GameTypes.weapon_slots()[index]] = QaItemBuilder.weapon(
			catalog,
			item_ids[index],
			GameTypes.WeaponType.BOW,
		)
	simulation.weapon_system.initialize(simulation.state, catalog, simulation.projectile_pool, simulation.event_router)
	var elapsed_values: Array[float] = [1.3, 1.1, 1.3]
	for index: int in range(3):
		var slot: GameTypes.EquipmentSlot = GameTypes.weapon_slots()[index]
		simulation.weapon_system.attack_interval_by_slot[int(slot)] = 1.0
		simulation.weapon_system.attack_elapsed_by_slot[int(slot)] = elapsed_values[index]
	var elapsed_before_wait: Dictionary = simulation.weapon_system.attack_elapsed_by_slot.duplicate(true)
	var intervals_before_wait: Dictionary = simulation.weapon_system.attack_interval_by_slot.duplicate(true)
	assertions.expect_equal(
		0,
		simulation.weapon_system.try_attacks_detailed(
			Vector2.ZERO,
			simulation.enemy_system.enemy_store,
			simulation.enemy_system.uniform_grid,
			1,
		).size(),
		"ready weapons do not attack without a target",
	)
	assertions.expect_equal(elapsed_before_wait, simulation.weapon_system.attack_elapsed_by_slot, "no-target wait preserves due order")
	assertions.expect_equal(intervals_before_wait, simulation.weapon_system.attack_interval_by_slot, "no-target wait consumes no cooldown roll")
	var target: EnemyEntity = simulation.spawn_fixture_enemy(GameTypes.EnemyType.ARMORED, Vector2(3.0, 0.0))
	var first_results: Array[Dictionary] = _try_simulation_attacks(simulation, 1)
	assertions.expect_equal(1, first_results.size(), "recontact commits at most one immediate attack")
	assertions.expect_equal("stagger-a", _result_item_id(first_results), "equal due times use item ID before slot order")
	assertions.expect_equal(target.entity_id, _result_target_id(first_results), "recontact attack still chooses the nearest target")
	assertions.expect_equal(1, simulation.projectile_pool.active_count(), "first recontact bow creates one projectile")
	assertions.expect_equal(0, _try_simulation_attacks(simulation, 1).size(), "same physics step cannot commit a second attack")
	simulation.weapon_system.advance_attack_timers(0.049)
	assertions.expect_equal(0, _try_simulation_attacks(simulation, 2).size(), "next weapon stays blocked immediately before 0.05 seconds")
	simulation.weapon_system.advance_attack_timers(0.001)
	var second_results: Array[Dictionary] = _try_simulation_attacks(simulation, 3)
	assertions.expect_equal(1, second_results.size(), "next weapon fires at the 0.05 second boundary")
	assertions.expect_equal("stagger-b", _result_item_id(second_results), "remaining weapons preserve independent due order")
	assertions.expect_equal(2, simulation.projectile_pool.active_count(), "second staggered bow creates one more projectile")
	simulation.enemy_system.enemy_store.clear()
	simulation.enemy_system.uniform_grid.clear()
	simulation.weapon_system.advance_attack_timers(WeaponSystem.MIN_ATTACK_GAP_SECONDS)
	var elapsed_before_missing_target: Dictionary = simulation.weapon_system.attack_elapsed_by_slot.duplicate(true)
	var intervals_before_missing_target: Dictionary = simulation.weapon_system.attack_interval_by_slot.duplicate(true)
	assertions.expect_equal(0, _try_simulation_attacks(simulation, 4).size(), "vanished target causes no empty attack")
	assertions.expect_equal(elapsed_before_missing_target, simulation.weapon_system.attack_elapsed_by_slot, "vanished target does not consume ready cooldown")
	assertions.expect_equal(intervals_before_missing_target, simulation.weapon_system.attack_interval_by_slot, "vanished target does not draw another interval")
	target = simulation.spawn_fixture_enemy(GameTypes.EnemyType.ARMORED, Vector2(3.0, 0.0))
	var third_results: Array[Dictionary] = _try_simulation_attacks(simulation, 5)
	assertions.expect_equal(1, third_results.size(), "ready weapon fires immediately after target returns")
	assertions.expect_equal("stagger-c", _result_item_id(third_results), "target return preserves the last weapon's due position")
	assertions.expect_equal(target.entity_id, _result_target_id(third_results), "returned target is acquired without a miss")

	setup = _simulation_with_weapon(assertions, GameTypes.WeaponType.SWORD)
	simulation = setup["simulation"]
	catalog = setup["catalog"]
	simulation.state.equipped[GameTypes.EquipmentSlot.WEAPON_1] = QaItemBuilder.weapon(
		catalog,
		"range-first-sword",
		GameTypes.WeaponType.SWORD,
	)
	simulation.state.equipped[GameTypes.EquipmentSlot.WEAPON_2] = QaItemBuilder.weapon(
		catalog,
		"range-second-bow",
		GameTypes.WeaponType.BOW,
	)
	simulation.weapon_system.initialize(simulation.state, catalog, simulation.projectile_pool, simulation.event_router)
	var sword_slot := GameTypes.EquipmentSlot.WEAPON_1
	var bow_slot := GameTypes.EquipmentSlot.WEAPON_2
	simulation.weapon_system.attack_interval_by_slot[int(sword_slot)] = 1.0
	simulation.weapon_system.attack_interval_by_slot[int(bow_slot)] = 1.0
	simulation.weapon_system.attack_elapsed_by_slot[int(sword_slot)] = 1.3
	simulation.weapon_system.attack_elapsed_by_slot[int(bow_slot)] = 1.2
	simulation.spawn_fixture_enemy(GameTypes.EnemyType.ARMORED, Vector2(8.0, 0.0))
	var sword_elapsed_before: float = simulation.weapon_system.attack_elapsed_by_slot[int(sword_slot)]
	var ranged_result: Array[Dictionary] = _try_simulation_attacks(simulation, 1)
	assertions.expect_equal("range-second-bow", _result_item_id(ranged_result), "out-of-range earlier weapon yields to the next valid weapon")
	assertions.expect_float(sword_elapsed_before, simulation.weapon_system.attack_elapsed_by_slot[int(sword_slot)], "skipped out-of-range weapon keeps its cooldown")

	setup = _simulation_with_weapon(assertions, GameTypes.WeaponType.BOW)
	simulation = setup["simulation"]
	catalog = setup["catalog"]
	for index: int in range(2):
		simulation.state.equipped[GameTypes.weapon_slots()[index]] = QaItemBuilder.weapon(
			catalog,
			"same-item-id",
			GameTypes.WeaponType.BOW,
		)
	simulation.weapon_system.initialize(simulation.state, catalog, simulation.projectile_pool, simulation.event_router)
	for slot: GameTypes.EquipmentSlot in [GameTypes.EquipmentSlot.WEAPON_1, GameTypes.EquipmentSlot.WEAPON_2]:
		simulation.weapon_system.attack_interval_by_slot[int(slot)] = 1.0
		simulation.weapon_system.attack_elapsed_by_slot[int(slot)] = 1.0
	simulation.spawn_fixture_enemy(GameTypes.EnemyType.ARMORED, Vector2(3.0, 0.0))
	var slot_tie_result: Array[Dictionary] = _try_simulation_attacks(simulation, 1)
	assertions.expect_equal(int(GameTypes.EquipmentSlot.WEAPON_1), _result_slot(slot_tie_result), "equal due time and item ID use slot order")


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
			system.attack_elapsed_by_slot[int(slot)] = float(
				system.attack_interval_by_slot[int(slot)],
			)


func _interval_sequence(system: WeaponSystem, sample_count: int) -> Array:
	var sequences: Array = []
	for slot: GameTypes.EquipmentSlot in GameTypes.weapon_slots():
		var sequence: Array[float] = []
		for _sample_index: int in range(sample_count):
			sequence.append(system.roll_next_interval(slot))
		sequences.append(sequence)
	return sequences


func _try_simulation_attacks(simulation: CombatSimulation, current_tick: int) -> Array[Dictionary]:
	return simulation.weapon_system.try_attacks_detailed(
		Vector2.ZERO,
		simulation.enemy_system.enemy_store,
		simulation.enemy_system.uniform_grid,
		current_tick,
	)


func _result_item_id(results: Array[Dictionary]) -> String:
	return String(results[0].get("item_id", "")) if not results.is_empty() else ""


func _result_target_id(results: Array[Dictionary]) -> int:
	return int(results[0].get("target_entity_id", -1)) if not results.is_empty() else -1


func _result_slot(results: Array[Dictionary]) -> int:
	return int(results[0].get("slot", -1)) if not results.is_empty() else -1


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
