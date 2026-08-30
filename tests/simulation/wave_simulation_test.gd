extends RefCounted


const DELTA: float = 1.0 / 60.0


func test_names() -> PackedStringArray:
	return PackedStringArray([
		"wood_stick_one_hit_and_w1_40_within_32_seconds",
		"death_timeout_same_tick_and_full_heal_flow",
		"w8_boss_299_gate_and_spawn_resume",
	])


func run_test(test_name: String, assertions: Variant, _context: Dictionary) -> void:
	match test_name:
		"wood_stick_one_hit_and_w1_40_within_32_seconds":
			_test_wood_stick_w1(assertions)
		"death_timeout_same_tick_and_full_heal_flow":
			_test_flow_priorities_and_heal(assertions)
		"w8_boss_299_gate_and_spawn_resume":
			_test_w8_gate(assertions)
		_:
			assertions.expect_true(false, "registered combat simulation test")


func _test_wood_stick_w1(assertions: Variant) -> void:
	var one_hit: CombatSimulation = _new_simulation(1)
	_freeze(one_hit)
	var tracker: EnemyEntity = one_hit.spawn_fixture_enemy(GameTypes.EnemyType.TRACKER, Vector2(1.0, 0.0))
	_set_weapon_ready(one_hit)
	one_hit.step(Vector2.ZERO, DELTA)
	assertions.expect_false(one_hit.enemy_system.enemy_store.has_entity(tracker.entity_id), "initial wood stick one-shots W1 TRACKER")
	assertions.expect_equal(1, one_hit.state.wave_kills, "one-hit increments W1 kill")

	var forty: CombatSimulation = _new_simulation(1)
	_freeze(forty)
	forty.spawn_fixture_enemy(GameTypes.EnemyType.TRACKER, Vector2(1.0, 0.0))
	_set_weapon_ready(forty)
	var ticks: int = 0
	while forty.state.wave_kills < 40 and ticks < 1921:
		var kills_before: int = forty.state.wave_kills
		forty.step(Vector2.ZERO, DELTA)
		ticks += 1
		if forty.state.wave_kills > kills_before and forty.state.wave_kills < 40:
			forty.spawn_fixture_enemy(GameTypes.EnemyType.TRACKER, Vector2(1.0, 0.0))
	assertions.expect_equal(40, forty.state.wave_kills, "continuous in-range wood stick defeats 40")
	assertions.expect_true(ticks <= 1920, "40 kills complete within 32.0 seconds")
	assertions.expect_true(forty.state.wave_cleared, "W1 quota latches")


func _test_flow_priorities_and_heal(assertions: Variant) -> void:
	var pre_death: CombatSimulation = _new_simulation(1)
	pre_death.freeze_normal_spawn = true
	pre_death.state.wave_kills = 39
	pre_death.state.current_hp = 1.0
	pre_death.weapon_system.attack_elapsed_by_slot[int(GameTypes.EquipmentSlot.WEAPON_1)] = 0.0
	var death_enemy: EnemyEntity = pre_death.spawn_fixture_enemy(GameTypes.EnemyType.TRACKER, Vector2.ZERO)
	death_enemy.contact_elapsed = death_enemy.definition.contact_interval
	pre_death.step(Vector2.ZERO, DELTA)
	assertions.expect_equal(GameTypes.RunPhase.FAILED, pre_death.state.phase, "death before quota fails")

	var timeout: CombatSimulation = _new_simulation(1)
	timeout.freeze_normal_spawn = true
	timeout.state.wave_kills = 39
	timeout.state.time_remaining = DELTA
	timeout.step(Vector2.ZERO, DELTA)
	assertions.expect_equal(GameTypes.RunPhase.FAILED, timeout.state.phase, "timeout before quota fails")

	var post_death: CombatSimulation = _new_simulation(1)
	post_death.freeze_normal_spawn = true
	post_death.state.wave_kills = 40
	post_death.state.wave_cleared = true
	post_death.state.current_hp = 1.0
	post_death.weapon_system.attack_elapsed_by_slot[int(GameTypes.EquipmentSlot.WEAPON_1)] = 0.0
	var post_enemy: EnemyEntity = post_death.spawn_fixture_enemy(GameTypes.EnemyType.TRACKER, Vector2.ZERO)
	post_enemy.contact_elapsed = post_enemy.definition.contact_interval
	post_death.step(Vector2.ZERO, DELTA)
	assertions.expect_equal(GameTypes.RunPhase.REWARD_REVEAL, post_death.state.phase, "death after quota succeeds")

	var kill_and_death: CombatSimulation = _new_simulation(1)
	kill_and_death.freeze_normal_spawn = true
	kill_and_death.state.wave_kills = 39
	kill_and_death.state.current_hp = 1.0
	var target: EnemyEntity = kill_and_death.spawn_fixture_enemy(GameTypes.EnemyType.TRACKER, Vector2(0.5, 0.0))
	var armored: EnemyEntity = kill_and_death.spawn_fixture_enemy(GameTypes.EnemyType.ARMORED, Vector2(1.0, 0.0))
	armored.contact_elapsed = armored.definition.contact_interval
	_set_weapon_ready(kill_and_death)
	kill_and_death.step(Vector2.ZERO, DELTA)
	assertions.expect_false(kill_and_death.enemy_system.enemy_store.has_entity(target.entity_id), "same tick target killed")
	assertions.expect_true(kill_and_death.state.wave_cleared, "same tick quota latched before death")
	assertions.expect_equal(GameTypes.RunPhase.REWARD_REVEAL, kill_and_death.state.phase, "same tick quota/death succeeds")

	var kill_and_timeout: CombatSimulation = _new_simulation(1)
	kill_and_timeout.freeze_normal_spawn = true
	kill_and_timeout.state.wave_kills = 39
	kill_and_timeout.state.time_remaining = DELTA
	kill_and_timeout.spawn_fixture_enemy(GameTypes.EnemyType.TRACKER, Vector2(1.0, 0.0))
	_set_weapon_ready(kill_and_timeout)
	kill_and_timeout.step(Vector2.ZERO, DELTA)
	assertions.expect_true(kill_and_timeout.state.wave_cleared, "same tick quota latched before timeout")
	assertions.expect_equal(GameTypes.RunPhase.REWARD_REVEAL, kill_and_timeout.state.phase, "same tick quota/timeout succeeds")

	var healing: CombatSimulation = _new_simulation(1)
	healing.state.current_hp = 1.0
	healing.state.recent_damage_samples.append(DamageSample.new())
	assertions.expect_true(healing.begin_wave(2), "next wave starts")
	assertions.expect_float(healing.state.max_hp, healing.state.current_hp, "wave start fully heals")
	assertions.expect_equal(0, healing.state.recent_damage_samples.size(), "wave start clears recent damage samples")


func _test_w8_gate(assertions: Variant) -> void:
	var simulation: CombatSimulation = _new_simulation(8)
	simulation.state.non_boss_spawned = 299
	simulation.state.wave_kills = 299
	simulation.state.spawn_credit = 1.0
	var count_before: int = simulation.enemy_system.enemy_store.active_count()
	var blocked: Array[EnemyEntity] = simulation.enemy_system.resolve_normal_spawns(Vector2.ZERO, 1)
	assertions.expect_equal(0, blocked.size(), "W8 normal spawn stops at 299 while boss alive")
	assertions.expect_equal(count_before, simulation.enemy_system.enemy_store.active_count(), "W8 blocked count unchanged")
	assertions.expect_float(1.0, simulation.state.spawn_credit, "W8 blocked spawn credit held")
	assertions.expect_false(RunStateMachine.quota_reached(simulation.state, simulation.wave), "W8 299 and live boss cannot clear")

	var boss: EnemyEntity = simulation.enemy_system.enemy_store.get_by_id(0)
	assertions.expect_true(boss != null, "W8 starts with boss")
	if boss != null:
		simulation.enemy_system.enemy_store.remove(boss.entity_id)
	simulation.state.boss_defeated = true
	var resumed: Array[EnemyEntity] = simulation.enemy_system.resolve_normal_spawns(Vector2.ZERO, 2)
	assertions.expect_equal(1, resumed.size(), "normal spawn resumes after boss defeat")
	assertions.expect_float(0.0, simulation.state.spawn_credit, "resumed spawn consumes held credit")
	simulation.state.wave_kills = 300
	assertions.expect_true(RunStateMachine.quota_reached(simulation.state, simulation.wave), "W8 300 clears after boss defeat")


func _new_simulation(wave_number: int) -> CombatSimulation:
	var catalog := DefinitionCatalog.new()
	catalog.load_and_validate()
	var state: RunState = RunStateFactory.create(20260827, catalog.wave(wave_number))
	state.wave_number = wave_number
	state.time_remaining = catalog.wave(wave_number).duration_seconds
	var simulation := CombatSimulation.new()
	simulation.initialize(state, catalog)
	return simulation


func _freeze(simulation: CombatSimulation) -> void:
	simulation.freeze_enemy_ai = true
	simulation.freeze_enemy_timers = true
	simulation.freeze_normal_spawn = true
	simulation.freeze_countdown = true


func _set_weapon_ready(simulation: CombatSimulation) -> void:
	var slot: GameTypes.EquipmentSlot = GameTypes.EquipmentSlot.WEAPON_1
	var item: ItemInstance = simulation.state.equipped.get(slot, null)
	if item == null:
		return
	simulation.weapon_system.attack_elapsed_by_slot[int(slot)] = (
		simulation.weapon_system.effective_interval(item)
	)
