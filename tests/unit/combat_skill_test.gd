extends RefCounted


const DELTA: float = 1.0 / 60.0
const UNIQUE_IDS: Array[StringName] = [
	&"bloodied_dagger",
	&"broken_clock",
	&"coward_boots",
	&"immortal_breastplate",
	&"echo_gauntlet",
	&"hollow_crown",
]
const WEAPON_TYPES: Array[int] = [
	GameTypes.MainWeaponType.UNCLASSIFIED,
	GameTypes.MainWeaponType.BOW,
	GameTypes.MainWeaponType.STAFF,
	GameTypes.MainWeaponType.SWORD,
]


func test_names() -> PackedStringArray:
	return PackedStringArray([
		"skill_threshold_pending_fifo_contract",
		"echo_and_coward_replay_contract",
		"effect_chain_and_crown_empty_contract",
		"bloodied_kill_bonus_wave_reset_contract",
		"crown_all_skill_schedule_contract",
		"unique_skill_weapon_parameter_matrix",
	])


func run_test(test_name: String, assertions: Variant, _context: Dictionary) -> void:
	match test_name:
		"skill_threshold_pending_fifo_contract":
			_test_skill_threshold_pending_fifo(assertions)
		"echo_and_coward_replay_contract":
			_test_echo_and_coward_replay(assertions)
		"effect_chain_and_crown_empty_contract":
			_test_effect_chain_and_crown_empty(assertions)
		"bloodied_kill_bonus_wave_reset_contract":
			_test_bloodied_kill_bonus_wave_reset(assertions)
		"crown_all_skill_schedule_contract":
			_test_crown_all_skill_schedule(assertions)
		"unique_skill_weapon_parameter_matrix":
			_test_unique_skill_weapon_parameter_matrix(assertions)
		_:
			assertions.expect_true(false, "registered inventory combat skill unit test")


func _test_skill_threshold_pending_fifo(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	if catalog == null:
		return
	var state: RunState = RunStateFactory.create(20260827, catalog.wave(1))
	var soul: SkillState = _skill(&"soul_chain", 1, 0, 44.25)
	state.skill_library[soul.skill_id] = soul
	var router := CombatEventRouter.new()
	var system := CombatSkillSystem.new()
	system.initialize(state, catalog, router)

	var primary: CombatEvent = router.create_primary(
		state,
		&"damage",
		7,
		&"weapon:wood_stick",
		10.0,
	)
	var origin: CombatEvent = router.create_secondary(
		state,
		primary,
		&"damage",
		7,
		&"weapon:wood_stick",
		CombatSkillSystem.ECHO_PROC_ID,
		10.0,
	)
	system.register_kill(origin)
	assertions.expect_float(0.25, soul.trigger_progress, "three-threshold input keeps exact remainder")
	assertions.expect_equal(3, soul.pending_queue.size(), "one event queues three FIFO activations")
	for index: int in range(soul.pending_queue.size()):
		var pending: PendingSkillActivation = soul.pending_queue[index]
		assertions.expect_equal(index, pending.activation_serial, "pending serial is consecutive %d" % index)
		assertions.expect_equal(origin.event_serial, pending.origin_event_serial, "pending origin event copied %d" % index)
		assertions.expect_equal(
			PackedStringArray([String(CombatSkillSystem.ECHO_PROC_ID)]),
			pending.inherited_effect_chain,
			"pending lineage copied %d" % index,
		)
	origin.effect_chain.append("mutated:origin")
	soul.pending_queue[0].inherited_effect_chain.append("mutated:first")
	assertions.expect_equal(
		PackedStringArray([String(CombatSkillSystem.ECHO_PROC_ID)]),
		soul.pending_queue[1].inherited_effect_chain,
		"pending entries own value copies",
	)
	var self_chain_event: CombatEvent = router.create_secondary(
		state,
		primary,
		&"damage",
		7,
		&"skill:soul_chain",
		&"skill:soul_chain",
		24.0,
	)
	var progress_before_self_kill: float = soul.trigger_progress
	system.register_kill(self_chain_event)
	assertions.expect_float(
		progress_before_self_kill,
		soul.trigger_progress,
		"derived skill kill does not advance its own trigger",
	)
	system.register_kill(primary)
	assertions.expect_float(
		progress_before_self_kill + 1.0,
		soul.trigger_progress,
		"unvisited primary kill still advances the skill trigger",
	)

	var clock := _unique_item(
		catalog,
		&"broken_clock",
		"clock-threshold-fixture",
	)
	state.equipped[GameTypes.EquipmentSlot.SUB_WEAPON] = clock
	var expected_thresholds: Dictionary = {
		&"starfall": 3.0,
		&"thousand_blades": 4.0,
		&"soul_chain": 8.0,
		&"bell_of_retribution": 3.0,
	}
	var stats: Dictionary = StatCalculator.aggregate_affixes(state.equipped)
	var unique_ids: Array[StringName] = StatCalculator.equipped_unique_ids(state.equipped)
	for skill_id: StringName in CombatSkillSystem.SKILL_ORDER:
		assertions.expect_float(
			float(expected_thresholds[skill_id]),
			StatCalculator.effective_skill_threshold(
				catalog.skill(skill_id),
				stats,
				unique_ids,
			),
			"broken clock threshold %s" % skill_id,
		)

	var starfall: SkillState = _skill(&"starfall", 1, 0, 9.25)
	state.skill_library.clear()
	state.skill_library[starfall.skill_id] = starfall
	system.initialize(state, catalog, router)
	system.prepare_for_combat()
	assertions.expect_equal(3, starfall.pending_queue.size(), "clock attachment normalizes progress before combat")
	assertions.expect_float(0.25, starfall.trigger_progress, "clock normalization retains time remainder")
	for pending: PendingSkillActivation in starfall.pending_queue:
		assertions.expect_equal(-1, pending.origin_event_serial, "normalization uses empty origin")
		assertions.expect_equal(PackedStringArray(), pending.inherited_effect_chain, "normalization uses empty chain")
	starfall.equipped_slot = -1
	var unequipped_progress: float = starfall.trigger_progress
	system.advance_time_progress(1.0)
	assertions.expect_float(unequipped_progress, starfall.trigger_progress, "unequipped skill gains no progress")
	starfall.equipped_slot = 0
	system.advance_time_progress(1.0)
	assertions.expect_float(unequipped_progress + 1.0, starfall.trigger_progress, "re-equipped skill continues existing progress")
	state.wave_cleared = true
	assertions.expect_true(
		RunStateMachine.transition(state, GameTypes.RunPhase.REWARD_REVEAL),
		"pending fixture enters reward reveal",
	)
	assertions.expect_equal(3, starfall.pending_queue.size(), "pending survives reward reveal")
	assertions.expect_true(
		RunStateMachine.transition(state, GameTypes.RunPhase.INVENTORY),
		"pending fixture enters inventory",
	)
	assertions.expect_equal(3, starfall.pending_queue.size(), "pending survives inventory")
	assertions.expect_true(
		RunStateMachine.transition(state, GameTypes.RunPhase.COMBAT),
		"pending fixture returns to combat",
	)
	var lifecycle_simulation := CombatSimulation.new()
	lifecycle_simulation.initialize(state, catalog)
	assertions.expect_true(lifecycle_simulation.begin_wave(2), "pending fixture begins next wave")
	assertions.expect_equal(3, starfall.pending_queue.size(), "pending survives into next wave")
	var retry_state: RunState = RunStateFactory.create(20260827, catalog.wave(1))
	assertions.expect_equal(0, retry_state.skill_library.size(), "fresh retry state has no pending skill state")


func _test_echo_and_coward_replay(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	if catalog == null:
		return
	var state: RunState = RunStateFactory.create(20260827, catalog.wave(1))
	var echo: ItemInstance = _unique_item(catalog, &"echo_gauntlet", "echo-item-a")
	var router := CombatEventRouter.new()
	var system := CombatSkillSystem.new()
	system.initialize(state, catalog, router)
	var payload: Dictionary = {
		"generated": true,
		"source_effect_id": &"weapon:staff",
		"damage_snapshot": 37.5,
		"direction": Vector2(0.6, 0.8),
		"aim_distance": 9.25,
		"target_entity_id": 42,
	}
	for _attack: int in range(3):
		system.register_primary_attack(payload, 99)
	assertions.expect_equal(0, state.echo_primary_attack_progress, "attacks before echo equip are not counted")
	assertions.expect_equal(0, state.scheduled_proc_replays.size(), "attacks before echo equip schedule nothing")
	state.equipped[GameTypes.EquipmentSlot.HANDS] = echo
	system.synchronize_unique_state()
	system.register_primary_attack(payload, 100)
	system.register_primary_attack(payload, 100)
	assertions.expect_equal(2, state.echo_primary_attack_progress, "echo primary count reaches two")
	assertions.expect_equal(0, state.scheduled_proc_replays.size(), "echo has no early replay")
	system.register_primary_attack(payload, 100)
	assertions.expect_equal(0, state.echo_primary_attack_progress, "echo subtracts three attacks")
	assertions.expect_equal(1, state.scheduled_proc_replays.size(), "third generated primary schedules one replay")
	var replay: ScheduledProcReplay = state.scheduled_proc_replays[0]
	assertions.expect_equal(109, replay.due_physics_tick, "echo delay is nine physics ticks")
	assertions.expect_equal(&"weapon:staff", replay.source_effect_id, "echo source payload preserved")
	assertions.expect_equal(CombatSkillSystem.ECHO_PROC_ID, replay.proc_effect_id, "echo proc ID preserved")
	assertions.expect_equal(
		PackedStringArray([String(CombatSkillSystem.ECHO_PROC_ID)]),
		replay.inherited_effect_chain,
		"echo reserves proc in lineage at schedule time",
	)
	assertions.expect_float(37.5, replay.damage_snapshot, "echo damage snapshot preserved")
	assertions.expect_equal(Vector2(0.6, 0.8), replay.direction, "echo direction preserved")
	assertions.expect_float(9.25, replay.aim_distance, "echo staff aim distance preserved")
	assertions.expect_equal(42, replay.target_entity_id, "echo target ID preserved")
	assertions.expect_equal(0, system.take_due_replays(108).size(), "echo remains queued before due tick")

	var boots: ItemInstance = _unique_item(catalog, &"coward_boots", "coward-item")
	state.equipped[GameTypes.EquipmentSlot.FEET] = boots
	for _tick: int in range(14):
		system.update_coward_motion(Vector2.ZERO, Vector2.ZERO, DELTA)
	assertions.expect_true(system.combat_progress_paused(), "coward pauses through tick fourteen")
	assertions.expect_equal(0, system.take_due_replays(109).size(), "due replay stays queued during coward pause")
	assertions.expect_equal(1, state.scheduled_proc_replays.size(), "coward pause retains due replay")
	system.update_coward_motion(Vector2.ZERO, Vector2.ZERO, DELTA)
	assertions.expect_false(system.combat_progress_paused(), "coward resumes exactly at tick fifteen")
	assertions.expect_true(system.coward_stationary_active(), "coward stationary multiplier activates")
	assertions.expect_equal(1, system.take_due_replays(109).size(), "retained replay releases after pause")
	assertions.expect_equal(0, state.scheduled_proc_replays.size(), "released replay leaves queue")
	system.update_coward_motion(Vector2.ZERO, Vector2(0.001, 0.0), DELTA)
	assertions.expect_true(system.combat_progress_paused(), "actual speed above 0.05 resets coward wait")
	for _tick: int in range(15):
		system.update_coward_motion(Vector2(15.0, 0.0), Vector2(15.0, 0.0), DELTA)
	assertions.expect_true(system.coward_stationary_active(), "zero clamped boundary movement counts as stopped")

	state.equipped[GameTypes.EquipmentSlot.FEET] = null
	state.echo_primary_attack_progress = 2
	system.initialize(state, catalog, router)
	assertions.expect_equal(2, state.echo_primary_attack_progress, "same echo item keeps progress across initialize")
	var wave_simulation := CombatSimulation.new()
	wave_simulation.initialize(state, catalog)
	assertions.expect_true(wave_simulation.begin_wave(2), "echo fixture begins another wave")
	system = wave_simulation.skill_system
	assertions.expect_equal(2, state.echo_primary_attack_progress, "same echo item keeps two attacks across waves")
	state.equipped[GameTypes.EquipmentSlot.HANDS] = null
	system.synchronize_unique_state()
	assertions.expect_equal("", state.echo_progress_item_id, "removing echo clears tracked item")
	assertions.expect_equal(0, state.echo_primary_attack_progress, "removing echo resets progress")
	state.equipped[GameTypes.EquipmentSlot.HANDS] = echo
	system.synchronize_unique_state()
	assertions.expect_equal("echo-item-a", state.echo_progress_item_id, "re-equipped item starts a new tracking session")
	assertions.expect_equal(0, state.echo_primary_attack_progress, "same item re-equipped later restarts at zero")
	state.echo_primary_attack_progress = 2
	var replacement_echo: ItemInstance = _unique_item(catalog, &"echo_gauntlet", "echo-item-b")
	state.equipped[GameTypes.EquipmentSlot.HANDS] = replacement_echo
	system.synchronize_unique_state()
	assertions.expect_equal("echo-item-b", state.echo_progress_item_id, "different echo item replaces tracked ID")
	assertions.expect_equal(0, state.echo_primary_attack_progress, "different echo item resets progress")
	var retry_state: RunState = RunStateFactory.create(20260827, catalog.wave(1))
	assertions.expect_equal("", retry_state.echo_progress_item_id, "retry starts with empty echo tracked ID")
	assertions.expect_equal(0, retry_state.echo_primary_attack_progress, "retry starts with zero echo progress")

	var later := ScheduledProcReplay.new()
	later.due_physics_tick = 200
	later.schedule_serial = 8
	var earlier := ScheduledProcReplay.new()
	earlier.due_physics_tick = 200
	earlier.schedule_serial = 7
	state.scheduled_proc_replays = [later, earlier]
	var ordered_due: Array[ScheduledProcReplay] = system.take_due_replays(200)
	assertions.expect_equal(7, ordered_due[0].schedule_serial, "due replay order uses schedule serial first")
	assertions.expect_equal(8, ordered_due[1].schedule_serial, "due replay order uses schedule serial second")
	state.scheduled_proc_replays = [later]
	state.wave_cleared = false
	assertions.expect_true(
		RunStateMachine.transition(state, GameTypes.RunPhase.FAILED),
		"echo fixture exits combat",
	)
	assertions.expect_equal(0, state.scheduled_proc_replays.size(), "combat exit discards scheduled replays")


func _test_effect_chain_and_crown_empty(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	if catalog == null:
		return
	var state: RunState = RunStateFactory.create(20260827, catalog.wave(1))
	var router := CombatEventRouter.new()
	var primary: CombatEvent = router.create_primary(
		state,
		&"damage",
		1,
		&"weapon:sword",
		14.0,
	)
	var effect_a: CombatEvent = router.create_secondary(
		state,
		primary,
		&"damage",
		1,
		&"weapon:sword",
		&"proc:a",
		14.0,
	)
	var effect_b: CombatEvent = router.create_secondary(
		state,
		effect_a,
		&"damage",
		1,
		&"skill:soul_chain",
		&"proc:b",
		24.0,
	)
	assertions.expect_true(effect_b != null, "different proc A to B is allowed")
	var rejected_a: CombatEvent = router.create_secondary(
		state,
		effect_b,
		&"damage",
		1,
		&"weapon:sword",
		&"proc:a",
		14.0,
	)
	assertions.expect_equal(null, rejected_a, "A to B to A re-entry is rejected")
	assertions.expect_equal(1, router.duplicate_proc_rejection_count, "duplicate proc rejection counter increments")

	var cursor: CombatEvent = effect_b
	for depth: int in range(3, CombatEventRouter.MAX_CHAIN_DEPTH + 1):
		cursor = router.create_secondary(
			state,
			cursor,
			&"damage",
			depth,
			StringName("payload:%d" % depth),
			StringName("proc:%d" % depth),
			1.0,
		)
	assertions.expect_equal(CombatEventRouter.MAX_CHAIN_DEPTH, cursor.chain_depth, "chain reaches technical depth sixteen")
	assertions.expect_equal(
		null,
		router.create_secondary(
			state,
			cursor,
			&"damage",
			99,
			&"payload:overflow",
			&"proc:overflow",
			1.0,
		),
		"depth sixteen refuses another derived event",
	)
	assertions.expect_equal(1, router.chain_depth_overflow_count, "depth overflow counter increments")

	var crown: ItemInstance = _unique_item(catalog, &"hollow_crown", "crown-item")
	state.equipped[GameTypes.EquipmentSlot.HEAD] = crown
	var system := CombatSkillSystem.new()
	var empty_store := EnemyStore.new()
	var empty_grid := UniformGrid.new()
	for skill_id: StringName in CombatSkillSystem.SKILL_ORDER:
		state.skill_library.clear()
		state.skill_library[skill_id] = _skill(skill_id, 1, 0, 0.0)
		system.initialize(state, catalog, router)
		var replay := ScheduledProcReplay.new()
		replay.due_physics_tick = 9
		replay.schedule_serial = state.next_activation_serial
		state.next_activation_serial += 1
		replay.source_effect_id = StringName("skill:%s" % skill_id)
		replay.proc_effect_id = CombatSkillSystem.CROWN_PROC_ID
		replay.inherited_effect_chain = PackedStringArray([
			String(CombatSkillSystem.CROWN_PROC_ID),
		])
		replay.damage_snapshot = 123.0
		state.scheduled_proc_replays = [replay]
		var due: Array[ScheduledProcReplay] = system.take_due_replays(9)
		assertions.expect_equal(1, due.size(), "%s crown replay consumed once" % skill_id)
		assertions.expect_equal(0, state.scheduled_proc_replays.size(), "%s crown queue is empty after due" % skill_id)
		var result: Dictionary = system.resolve_scheduled_skill(
			due[0],
			[],
			empty_store,
			empty_grid,
			Vector2.ZERO,
			9,
		)
		var area_skill: bool = skill_id in [&"thousand_blades", &"bell_of_retribution"]
		assertions.expect_equal(area_skill, bool(result.get("success", false)), "%s empty-target crown rule" % skill_id)
		assertions.expect_equal(0, (result.get("hits", []) as Array).size(), "%s empty replay has zero hits" % skill_id)
		var event: CombatEvent = result.get("event") as CombatEvent
		assertions.expect_equal(area_skill, event != null, "%s empty area event creation rule" % skill_id)
		if event != null:
			assertions.expect_float(123.0, event.damage_snapshot, "%s crown reuses damage snapshot" % skill_id)
			assertions.expect_equal(
				PackedStringArray([String(CombatSkillSystem.CROWN_PROC_ID)]),
				event.effect_chain,
				"%s crown reuses scheduled chain" % skill_id,
			)


func _test_bloodied_kill_bonus_wave_reset(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	if catalog == null:
		return
	var state: RunState = RunStateFactory.create(20260827, catalog.wave(1))
	state.equipped[GameTypes.EquipmentSlot.SUB_WEAPON] = _unique_item(
		catalog,
		&"bloodied_dagger",
		"bloodied-reset-fixture",
	)
	var simulation := CombatSimulation.new()
	simulation.initialize(state, catalog)
	var interval_before_kill: float = simulation.weapon_system.effective_interval()
	var target: EnemyEntity = simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.TRACKER,
		Vector2(1.0, 0.0),
	)
	assertions.expect_true(target != null, "bloodied fixture target created")
	if target == null:
		return
	simulation.main_weapon_damage_override = target.max_hp + 1.0
	simulation.weapon_system.attack_elapsed = 999.0
	simulation.step(Vector2.ZERO, DELTA)
	assertions.expect_equal(1, state.wave_kills, "bloodied kill increments the wave-local bonus source")
	var interval_after_kill: float = simulation.weapon_system.effective_interval()
	assertions.expect_float(
		interval_before_kill / 1.01,
		interval_after_kill,
		"bloodied dagger adds one attack-speed percent per wave kill",
	)
	assertions.expect_true(
		interval_after_kill < interval_before_kill,
		"bloodied kill strictly accelerates the main weapon",
	)
	assertions.expect_true(simulation.begin_wave(2), "bloodied fixture begins the next wave")
	assertions.expect_equal(0, state.wave_kills, "begin_wave resets bloodied wave kill progress")
	assertions.expect_float(
		interval_before_kill,
		simulation.weapon_system.effective_interval(),
		"next wave removes the prior bloodied attack-speed bonus",
	)


func _test_crown_all_skill_schedule(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	if catalog == null:
		return
	const ACTIVATION_TICK: int = 40
	for skill_id: StringName in CombatSkillSystem.SKILL_ORDER:
		var state: RunState = RunStateFactory.create(20260827, catalog.wave(1))
		state.equipped[GameTypes.EquipmentSlot.HEAD] = _unique_item(
			catalog,
			&"hollow_crown",
			"crown-schedule-%s" % skill_id,
		)
		var skill_state: SkillState = _skill(skill_id, 1, 0, 0.0)
		var pending := PendingSkillActivation.new()
		pending.activation_serial = state.next_activation_serial
		state.next_activation_serial += 1
		skill_state.pending_queue.append(pending)
		state.skill_library[skill_id] = skill_state

		var router := CombatEventRouter.new()
		var system := CombatSkillSystem.new()
		system.initialize(state, catalog, router)
		var store := EnemyStore.new()
		var target: EnemyEntity = store.try_spawn(
			state,
			GameTypes.EnemyType.TRACKER,
			catalog.enemy(&"tracker"),
			Vector2(1.0, 0.0),
			1.0,
			1.0,
			0,
		)
		var grid := UniformGrid.new()
		if target != null:
			grid.insert(target.entity_id, target.position)
		assertions.expect_true(target != null, "%s crown activation target created" % skill_id)
		if target == null:
			continue

		var candidates: Array[Dictionary] = system.pending_activation_snapshot()
		assertions.expect_equal(1, candidates.size(), "%s has one activation candidate" % skill_id)
		if candidates.is_empty():
			continue
		var activation: Dictionary = system.resolve_pending_candidate(
			candidates[0],
			[target.entity_id],
			store,
			grid,
			Vector2.ZERO,
			ACTIVATION_TICK,
		)
		assertions.expect_true(
			bool(activation.get("success", false)),
			"%s primary skill activation succeeds" % skill_id,
		)
		assertions.expect_equal(0, skill_state.pending_queue.size(), "%s consumes its pending activation" % skill_id)
		assertions.expect_equal(1, state.scheduled_proc_replays.size(), "%s schedules exactly one crown replay" % skill_id)
		if state.scheduled_proc_replays.size() != 1:
			continue
		var event: CombatEvent = activation.get("event") as CombatEvent
		var replay: ScheduledProcReplay = state.scheduled_proc_replays[0]
		assertions.expect_equal(
			ACTIVATION_TICK + CombatSkillSystem.REPLAY_DELAY_TICKS,
			replay.due_physics_tick,
			"%s crown replay is due exactly nine ticks later" % skill_id,
		)
		assertions.expect_equal(
			pending.activation_serial + 1,
			replay.schedule_serial,
			"%s crown replay reserves the next activation serial" % skill_id,
		)
		assertions.expect_equal(
			StringName("skill:%s" % skill_id),
			replay.source_effect_id,
			"%s crown replay preserves the skill payload ID" % skill_id,
		)
		assertions.expect_equal(
			CombatSkillSystem.CROWN_PROC_ID,
			replay.proc_effect_id,
			"%s crown replay records the crown proc" % skill_id,
		)
		assertions.expect_equal(
			PackedStringArray([
				"skill:%s" % skill_id,
				String(CombatSkillSystem.CROWN_PROC_ID),
			]),
			replay.inherited_effect_chain,
			"%s crown replay preserves the activated lineage" % skill_id,
		)
		if event != null:
			assertions.expect_float(
				event.damage_snapshot,
				replay.damage_snapshot,
				"%s crown replay snapshots the activated damage" % skill_id,
			)
		assertions.expect_equal(
			0,
			system.take_due_replays(ACTIVATION_TICK + CombatSkillSystem.REPLAY_DELAY_TICKS - 1).size(),
			"%s crown replay remains queued before tick nine" % skill_id,
		)
		assertions.expect_equal(
			1,
			system.take_due_replays(ACTIVATION_TICK + CombatSkillSystem.REPLAY_DELAY_TICKS).size(),
			"%s crown replay becomes due on tick nine" % skill_id,
		)


func _test_unique_skill_weapon_parameter_matrix(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	if catalog == null:
		return
	var case_count: int = 0
	for unique_id: StringName in UNIQUE_IDS:
		for skill_id: StringName in CombatSkillSystem.SKILL_ORDER:
			for weapon_type_value: int in WEAPON_TYPES:
				var weapon_type: GameTypes.MainWeaponType = weapon_type_value as GameTypes.MainWeaponType
				var state: RunState = RunStateFactory.create(20260827 + case_count, catalog.wave(1))
				state.equipped[GameTypes.EquipmentSlot.MAIN_WEAPON] = _weapon_item(
					weapon_type,
					"matrix-weapon-%03d" % case_count,
				)
				var unique_item: ItemInstance = _unique_item(
					catalog,
					unique_id,
					"matrix-unique-%03d" % case_count,
				)
				state.equipped[unique_item.slot] = unique_item
				state.skill_library[skill_id] = _skill(skill_id, 1, 0, 0.0)
				if unique_id == &"coward_boots":
					state.coward_stationary_elapsed = CombatSkillSystem.COWARD_WAIT_SECONDS
				var router := CombatEventRouter.new()
				var projectile_pool := ProjectilePool.new()
				var weapon_system := WeaponSystem.new()
				weapon_system.initialize(state, catalog, projectile_pool, router)
				var skill_system := CombatSkillSystem.new()
				skill_system.initialize(state, catalog, router)

				var store := EnemyStore.new()
				var target: EnemyEntity = store.try_spawn(
					state,
					GameTypes.EnemyType.TRACKER,
					catalog.enemy(&"tracker"),
					Vector2(1.0, 0.0),
					1000.0,
					1.0,
					0,
				)
				var grid := UniformGrid.new()
				grid.insert(target.entity_id, target.position)
				var coward_active: bool = unique_id == &"coward_boots"
				var primary: Dictionary = weapon_system.try_primary_attack_detailed(
					Vector2.ZERO,
					store,
					grid,
					1,
					coward_active,
				)
				skill_system.register_primary_attack(primary, 1)
				var pending := PendingSkillActivation.new()
				pending.activation_serial = state.next_activation_serial
				state.next_activation_serial += 1
				(state.skill_library[skill_id] as SkillState).pending_queue.append(pending)
				var candidates: Array[Dictionary] = skill_system.pending_activation_snapshot()
				var skill_result: Dictionary = skill_system.resolve_pending_candidate(
					candidates[0] if not candidates.is_empty() else {},
					[target.entity_id],
					store,
					grid,
					Vector2.ZERO,
					1,
				)
				var skill_event: CombatEvent = skill_result.get("event") as CombatEvent
				var stats: Dictionary = StatCalculator.aggregate_affixes(state.equipped)
				var equipped_uniques: Array[StringName] = StatCalculator.equipped_unique_ids(state.equipped)
				var threshold: float = StatCalculator.effective_skill_threshold(
					catalog.skill(skill_id),
					stats,
					equipped_uniques,
				)
				var expected_weapon_damage: float = weapon_system.current_definition().base_damage * _unique_damage_multiplier(
					unique_id,
					false,
					coward_active,
				)
				var skill_definition: SkillDefinition = catalog.skill(skill_id)
				var expected_skill_damage: float = skill_definition.damage_by_level[0] * _unique_damage_multiplier(
					unique_id,
					true,
					coward_active,
				)
				var case_valid: bool = (
					bool(primary.get("generated", false))
					and bool(skill_result.get("success", false))
					and skill_event != null
					and is_finite(threshold)
					and threshold > 0.0
					and is_equal_approx(weapon_system.effective_damage(coward_active), expected_weapon_damage)
					and is_equal_approx(skill_event.damage_snapshot, expected_skill_damage)
					and skill_event.source_effect_id == StringName("skill:%s" % skill_id)
					and skill_event.proc_effect_id == StringName("skill:%s" % skill_id)
					and skill_event.effect_chain == PackedStringArray(["skill:%s" % skill_id])
				)
				assertions.expect_true(
					case_valid,
					"matrix %s x %s x %s" % [
						unique_id,
						skill_id,
						weapon_system.current_weapon_id(),
					],
				)
				case_count += 1
	assertions.expect_equal(96, case_count, "parameter matrix covers 6 unique x 4 skill x 4 weapon")


func _catalog(assertions: Variant) -> DefinitionCatalog:
	var catalog := DefinitionCatalog.new()
	assertions.expect_true(catalog.load_and_validate(), "inventory combat DefinitionCatalog valid")
	return catalog if catalog.is_valid else null


func _skill(
	skill_id: StringName,
	level: int,
	equipped_slot: int,
	progress: float,
) -> SkillState:
	var result := SkillState.new()
	result.skill_id = skill_id
	result.level = level
	result.equipped_slot = equipped_slot
	result.trigger_progress = progress
	return result


func _unique_item(
	catalog: DefinitionCatalog,
	unique_id: StringName,
	item_id: String,
) -> ItemInstance:
	var definition: UniqueDefinition = catalog.unique(unique_id)
	var item := ItemInstance.new()
	item.item_id = item_id
	item.slot = definition.equipment_slot
	item.unique_id = unique_id
	item.display_name = definition.display_name
	return item


func _weapon_item(
	weapon_type: GameTypes.MainWeaponType,
	item_id: String,
) -> ItemInstance:
	var item := ItemInstance.new()
	item.item_id = item_id
	item.slot = GameTypes.EquipmentSlot.MAIN_WEAPON
	item.main_weapon_type = weapon_type
	item.display_name = String(GameTypes.main_weapon_type_to_key(weapon_type))
	return item


func _unique_damage_multiplier(
	unique_id: StringName,
	is_skill: bool,
	coward_active: bool,
) -> float:
	match unique_id:
		&"bloodied_dagger", &"immortal_breastplate":
			return 0.5
		&"broken_clock":
			return 0.5 if is_skill else 1.0
		&"coward_boots":
			return 3.0 if coward_active else 1.0
	return 1.0
