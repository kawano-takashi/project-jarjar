extends RefCounted


const DELTA: float = 1.0 / 60.0
const WEAPON_TYPES: Array[int] = [
	GameTypes.MainWeaponType.UNCLASSIFIED,
	GameTypes.MainWeaponType.BOW,
	GameTypes.MainWeaponType.STAFF,
	GameTypes.MainWeaponType.SWORD,
]


func test_names() -> PackedStringArray:
	return PackedStringArray([
		"gate05_pending_target_snapshot_and_one_per_tick",
		"gate05_skill_target_selection_contract",
		"gate05_echo_and_crown_replay_execution_contract",
		"gate05_immortal_hit_and_dps_window_contract",
		"gate05_skill_hud_presentation_contract",
	])


func run_test(test_name: String, assertions: Variant, context: Dictionary) -> void:
	match test_name:
		"gate05_pending_target_snapshot_and_one_per_tick":
			_test_pending_target_snapshot_and_one_per_tick(assertions)
		"gate05_skill_target_selection_contract":
			_test_skill_target_selection(assertions)
		"gate05_echo_and_crown_replay_execution_contract":
			_test_echo_and_crown_replay_execution(assertions)
		"gate05_immortal_hit_and_dps_window_contract":
			_test_immortal_hit_and_dps_window(assertions)
		"gate05_skill_hud_presentation_contract":
			await _test_skill_hud_presentation(assertions, context)
		_:
			assertions.expect_true(false, "registered Gate 5 skill combat scenario test")


func _test_pending_target_snapshot_and_one_per_tick(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	if catalog == null:
		return
	for skill_id: StringName in CombatSkillSystem.SKILL_ORDER:
		var simulation: CombatSimulation = _new_simulation(catalog)
		_freeze_fixture(simulation)
		simulation.weapon_system.attack_elapsed = 0.0
		var skill: SkillState = _skill(skill_id, 1, 0, 0.0)
		simulation.state.skill_library[skill_id] = skill
		simulation.skill_system.initialize(
			simulation.state,
			catalog,
			simulation.event_router,
		)
		for serial: int in range(2):
			var pending := PendingSkillActivation.new()
			pending.activation_serial = serial
			skill.pending_queue.append(pending)
		simulation.state.next_activation_serial = 2
		var target: EnemyEntity = simulation.spawn_fixture_enemy(
			GameTypes.EnemyType.TRACKER,
			Vector2(1.0, 0.0),
			simulation.state.physics_tick + 1,
		)
		target.hp = INF
		target.max_hp = INF
		simulation.step(Vector2.ZERO, DELTA)
		assertions.expect_equal(2, skill.pending_queue.size(), "%s holds pending for same-tick-born enemy" % skill_id)
		simulation.step(Vector2.ZERO, DELTA)
		assertions.expect_equal(1, skill.pending_queue.size(), "%s consumes at most one on next tick" % skill_id)
		simulation.step(Vector2.ZERO, DELTA)
		assertions.expect_equal(0, skill.pending_queue.size(), "%s consumes second FIFO on following tick" % skill_id)


func _test_skill_target_selection(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	if catalog == null:
		return
	var starfall_simulation: CombatSimulation = _new_simulation(catalog)
	_freeze_fixture(starfall_simulation)
	starfall_simulation.weapon_system.attack_elapsed = 0.0
	var starfall: SkillState = _skill(&"starfall", 1, 0, 0.0)
	starfall_simulation.state.skill_library[starfall.skill_id] = starfall
	starfall_simulation.skill_system.initialize(
		starfall_simulation.state,
		catalog,
		starfall_simulation.event_router,
	)
	var starfall_positions: Array[Vector2] = [
		Vector2(-10.0, -5.0),
		Vector2(-9.8, -5.0),
		Vector2(10.0, 5.0),
		Vector2(10.2, 5.0),
		Vector2(9.8, 5.0),
	]
	var starfall_enemies: Array[EnemyEntity] = []
	for position: Vector2 in starfall_positions:
		var enemy: EnemyEntity = starfall_simulation.spawn_fixture_enemy(
			GameTypes.EnemyType.TRACKER,
			position,
		)
		enemy.hp = 100.0
		enemy.max_hp = 100.0
		starfall_enemies.append(enemy)
	starfall.pending_queue.append(PendingSkillActivation.new())
	starfall_simulation.step(Vector2.ZERO, DELTA)
	assertions.expect_float(100.0, starfall_enemies[0].hp, "starfall leaves smaller left cluster untouched")
	assertions.expect_float(100.0, starfall_enemies[1].hp, "starfall leaves second smaller-cluster enemy untouched")
	for index: int in range(2, 5):
		assertions.expect_float(55.0, starfall_enemies[index].hp, "starfall hits densest cluster enemy %d" % index)

	var soul_simulation: CombatSimulation = _new_simulation(catalog)
	_freeze_fixture(soul_simulation)
	soul_simulation.weapon_system.attack_elapsed = 0.0
	var soul: SkillState = _skill(&"soul_chain", 1, 0, 0.0)
	soul_simulation.state.skill_library[soul.skill_id] = soul
	soul_simulation.skill_system.initialize(
		soul_simulation.state,
		catalog,
		soul_simulation.event_router,
	)
	var soul_positions: Array[Vector2] = [
		Vector2(2.0, 0.0),
		Vector2(1.0, 0.0),
		Vector2(-1.0, 0.0),
		Vector2(3.0, 0.0),
		Vector2(4.0, 0.0),
	]
	var soul_enemies: Array[EnemyEntity] = []
	for position: Vector2 in soul_positions:
		var enemy: EnemyEntity = soul_simulation.spawn_fixture_enemy(
			GameTypes.EnemyType.TRACKER,
			position,
		)
		enemy.hp = 100.0
		enemy.max_hp = 100.0
		soul_enemies.append(enemy)
	soul.pending_queue.append(PendingSkillActivation.new())
	soul_simulation.step(Vector2.ZERO, DELTA)
	for index: int in range(4):
		assertions.expect_float(76.0, soul_enemies[index].hp, "soul chain selects ordered target %d" % index)
	assertions.expect_float(100.0, soul_enemies[4].hp, "soul chain level one caps at four targets")

	var area_simulation: CombatSimulation = _new_simulation(catalog)
	_freeze_fixture(area_simulation)
	area_simulation.weapon_system.attack_elapsed = 0.0
	var blades: SkillState = _skill(&"thousand_blades", 1, 0, 0.0)
	area_simulation.state.skill_library[blades.skill_id] = blades
	area_simulation.skill_system.initialize(
		area_simulation.state,
		catalog,
		area_simulation.event_router,
	)
	var area_positions: Array[Vector2] = [
		Vector2(1.0, 0.0),
		Vector2(-1.0, 0.0),
		Vector2(3.0, 0.0),
		Vector2(3.0001, 0.0),
	]
	var area_ids: Array[int] = []
	for position: Vector2 in area_positions:
		var enemy: EnemyEntity = area_simulation.spawn_fixture_enemy(
			GameTypes.EnemyType.TRACKER,
			position,
		)
		area_ids.append(enemy.entity_id)
	blades.pending_queue.append(PendingSkillActivation.new())
	var area_result: Dictionary = area_simulation.skill_system.resolve_pending_candidate(
		area_simulation.skill_system.pending_activation_snapshot()[0],
		area_simulation.enemy_system.snapshot_ids(),
		area_simulation.enemy_system.enemy_store,
		area_simulation.enemy_system.uniform_grid,
		Vector2.ZERO,
		1,
	)
	var ordered_area_hits: Array[int] = []
	for hit: Dictionary in (area_result.get("hits", []) as Array):
		ordered_area_hits.append(int(hit["entity_id"]))
	assertions.expect_equal(
		[area_ids[1], area_ids[0], area_ids[2]],
		ordered_area_hits,
		"skill circle uses cell-key order and includes exact radius boundary only",
	)


func _test_echo_and_crown_replay_execution(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	if catalog == null:
		return
	for weapon_type_value: int in WEAPON_TYPES:
		var weapon_type: GameTypes.MainWeaponType = weapon_type_value as GameTypes.MainWeaponType
		var state: RunState = RunStateFactory.create(20260827 + weapon_type_value, catalog.wave(1))
		state.equipped[GameTypes.EquipmentSlot.MAIN_WEAPON] = _weapon_item(
			weapon_type,
			"echo-weapon-%d" % weapon_type_value,
		)
		state.equipped[GameTypes.EquipmentSlot.HANDS] = _unique_item(
			catalog,
			&"echo_gauntlet",
			"echo-gauntlet-%d" % weapon_type_value,
		)
		var thousand_blades: SkillState = _skill(&"thousand_blades", 1, 0, 0.0)
		state.skill_library[thousand_blades.skill_id] = thousand_blades
		var router := CombatEventRouter.new()
		var pool := ProjectilePool.new()
		var weapon_system := WeaponSystem.new()
		weapon_system.initialize(state, catalog, pool, router)
		var skill_system := CombatSkillSystem.new()
		skill_system.initialize(state, catalog, router)
		var store := EnemyStore.new()
		var target: EnemyEntity = store.try_spawn(
			state,
			GameTypes.EnemyType.TRACKER,
			catalog.enemy(&"tracker"),
			Vector2(1.0, 0.0),
			100.0,
			1.0,
			0,
		)
		var grid := UniformGrid.new()
		grid.insert(target.entity_id, target.position)
		var payload: Dictionary = weapon_system.try_primary_attack_detailed(
			Vector2.ZERO,
			store,
			grid,
			1,
		)
		assertions.expect_true(bool(payload.get("generated", false)), "echo source primary generated %d" % weapon_type_value)
		for _attack: int in range(3):
			skill_system.register_primary_attack(payload, 1)
		assertions.expect_float(3.0, thousand_blades.trigger_progress, "echo source primary count is three %d" % weapon_type_value)
		assertions.expect_equal(1, state.scheduled_proc_replays.size(), "echo schedules one payload %d" % weapon_type_value)
		pool.clear()
		assertions.expect_equal(0, skill_system.take_due_replays(9).size(), "echo is not early %d" % weapon_type_value)
		var due: Array[ScheduledProcReplay] = skill_system.take_due_replays(10)
		assertions.expect_equal(1, due.size(), "echo is due at source tick plus nine %d" % weapon_type_value)
		var replay_result: Dictionary = weapon_system.replay_weapon(
			due[0],
			Vector2.ZERO,
			store,
			grid,
			10,
		)
		assertions.expect_true(bool(replay_result.get("generated", false)), "echo replays weapon payload %d" % weapon_type_value)
		assertions.expect_float(3.0, thousand_blades.trigger_progress, "echo replay does not count as primary %d" % weapon_type_value)
		if weapon_type in [GameTypes.MainWeaponType.BOW, GameTypes.MainWeaponType.STAFF]:
			assertions.expect_equal(1, pool.active_count(), "echo projectile created once %d" % weapon_type_value)
			var projectile: ProjectileState = _first_active_projectile(pool)
			assertions.expect_false(projectile.is_primary, "echo projectile is secondary %d" % weapon_type_value)
			assertions.expect_equal(CombatSkillSystem.ECHO_PROC_ID, projectile.proc_effect_id, "echo projectile proc %d" % weapon_type_value)
			assertions.expect_equal(
				PackedStringArray([String(CombatSkillSystem.ECHO_PROC_ID)]),
				projectile.effect_chain,
				"echo projectile lineage %d" % weapon_type_value,
			)
			var expected_target: Vector2 = (
				Vector2(14.0, 0.0)
				if weapon_type == GameTypes.MainWeaponType.BOW
				else Vector2(1.0, 0.0)
			)
			assertions.expect_equal(expected_target, projectile.target_position, "echo projectile aim rule %d" % weapon_type_value)
		else:
			var replay_event: CombatEvent = replay_result.get("event") as CombatEvent
			assertions.expect_true(replay_event != null, "echo immediate replay event exists %d" % weapon_type_value)
			assertions.expect_false(replay_event.is_primary, "echo immediate event is secondary %d" % weapon_type_value)
			assertions.expect_equal(CombatSkillSystem.ECHO_PROC_ID, replay_event.proc_effect_id, "echo immediate proc %d" % weapon_type_value)
			assertions.expect_float(float(payload["damage_snapshot"]), replay_event.damage_snapshot, "echo immediate damage snapshot %d" % weapon_type_value)

	var crown_state: RunState = RunStateFactory.create(20260827, catalog.wave(1))
	crown_state.equipped[GameTypes.EquipmentSlot.HEAD] = _unique_item(
		catalog,
		&"hollow_crown",
		"crown-execution",
	)
	var crown_skill: SkillState = _skill(&"starfall", 1, 0, 0.0)
	crown_state.skill_library[crown_skill.skill_id] = crown_skill
	var crown_router := CombatEventRouter.new()
	var crown_system := CombatSkillSystem.new()
	crown_system.initialize(crown_state, catalog, crown_router)
	var crown_store := EnemyStore.new()
	var crown_target: EnemyEntity = crown_store.try_spawn(
		crown_state,
		GameTypes.EnemyType.TRACKER,
		catalog.enemy(&"tracker"),
		Vector2(1.0, 0.0),
		100.0,
		1.0,
		0,
	)
	var crown_grid := UniformGrid.new()
	crown_grid.insert(crown_target.entity_id, crown_target.position)
	var crown_pending := PendingSkillActivation.new()
	crown_pending.activation_serial = 0
	crown_skill.pending_queue.append(crown_pending)
	var first_result: Dictionary = crown_system.resolve_pending_candidate(
		crown_system.pending_activation_snapshot()[0],
		[crown_target.entity_id],
		crown_store,
		crown_grid,
		Vector2.ZERO,
		1,
	)
	var first_event: CombatEvent = first_result.get("event") as CombatEvent
	assertions.expect_true(first_event != null, "crown first skill event exists")
	assertions.expect_equal(PackedStringArray(["skill:starfall"]), first_event.effect_chain, "first skill stores its proc")
	assertions.expect_equal(1, crown_state.scheduled_proc_replays.size(), "crown schedules exactly one replay")
	var crown_due: Array[ScheduledProcReplay] = crown_system.take_due_replays(10)
	assertions.expect_equal(1, crown_due.size(), "crown replay is due after nine ticks")
	assertions.expect_equal(
		PackedStringArray(["skill:starfall", String(CombatSkillSystem.CROWN_PROC_ID)]),
		crown_due[0].inherited_effect_chain,
		"crown replay retains parent chain and crown proc",
	)
	var second_result: Dictionary = crown_system.resolve_scheduled_skill(
		crown_due[0],
		[crown_target.entity_id],
		crown_store,
		crown_grid,
		Vector2.ZERO,
		10,
	)
	var second_event: CombatEvent = second_result.get("event") as CombatEvent
	assertions.expect_true(second_event != null, "crown second skill event exists")
	assertions.expect_float(first_event.damage_snapshot, second_event.damage_snapshot, "crown replays identical damage snapshot")
	assertions.expect_equal(CombatSkillSystem.CROWN_PROC_ID, second_event.proc_effect_id, "crown second event proc")
	assertions.expect_equal(0, crown_state.scheduled_proc_replays.size(), "crown replay does not recursively reschedule")


func _test_immortal_hit_and_dps_window(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	if catalog == null:
		return
	var fixture: Dictionary = QaScenarioFactory.build("immortal_100", catalog)
	assertions.expect_true(bool(fixture.get("valid", false)), "immortal combat fixture valid")
	if not bool(fixture.get("valid", false)):
		return
	var immortal_state: RunState = fixture["state"] as RunState
	var immortal_simulation: CombatSimulation = fixture["simulation"] as CombatSimulation
	var bell: SkillState = immortal_state.skill_library[&"bell_of_retribution"] as SkillState
	var initial_time: float = immortal_state.time_remaining
	immortal_simulation.step(Vector2.ZERO, DELTA)
	assertions.expect_float(100.0, immortal_state.current_hp, "100 percent reduction preserves HP after contact")
	assertions.expect_float(0.0, bell.trigger_progress, "fifth hit drains bell threshold")
	assertions.expect_equal(1, bell.pending_queue.size(), "fifth hit queues bell after step-five snapshot")
	immortal_simulation.step(Vector2.ZERO, DELTA)
	assertions.expect_equal(0, bell.pending_queue.size(), "bell resolves on following tick")
	for _tick: int in range(44):
		immortal_simulation.step(Vector2.ZERO, DELTA)
	assertions.expect_float(100.0, immortal_state.current_hp, "repeating contact remains fully reduced")
	assertions.expect_float(1.0, bell.trigger_progress, "contact-only fixture timer reaches another hit")
	assertions.expect_float(initial_time, immortal_state.time_remaining, "immortal fixture countdown remains frozen")
	assertions.expect_float(0.0, immortal_state.spawn_credit, "immortal fixture spawn credit remains frozen")
	assertions.expect_equal(1, immortal_simulation.enemy_system.enemy_store.active_count(), "immortal fixture creates no normal spawns")

	var dps_simulation: CombatSimulation = _new_simulation(catalog)
	_freeze_fixture(dps_simulation)
	dps_simulation.weapon_system.attack_elapsed = 0.0
	dps_simulation.state.physics_tick = 100
	var old_sample := DamageSample.new()
	old_sample.physics_tick = 39
	old_sample.event_serial = 0
	old_sample.applied_damage = 3.0
	var boundary_sample := DamageSample.new()
	boundary_sample.physics_tick = 40
	boundary_sample.event_serial = 1
	boundary_sample.applied_damage = 4.0
	dps_simulation.state.recent_damage_samples = [old_sample, boundary_sample]
	var current_event: CombatEvent = dps_simulation.event_router.create_primary(
		dps_simulation.state,
		&"damage",
		-1,
		&"weapon:wood_stick",
		5.0,
	)
	dps_simulation._update_damage_samples(current_event, 5.0)
	assertions.expect_equal(2, dps_simulation.state.recent_damage_samples.size(), "DPS excludes T-61 and includes T-60")
	assertions.expect_equal(40, dps_simulation.state.recent_damage_samples[0].physics_tick, "DPS closed window begins at T-60")
	assertions.expect_float(9.0, dps_simulation.state.peak_dps, "DPS sums boundary and current sample")

	var overkill_target: EnemyEntity = dps_simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.TRACKER,
		Vector2(5.0, 0.0),
	)
	overkill_target.hp = 5.0
	overkill_target.max_hp = 5.0
	dps_simulation.state.physics_tick = 101
	var overkill_event: CombatEvent = dps_simulation.event_router.create_primary(
		dps_simulation.state,
		&"damage",
		-1,
		&"weapon:wood_stick",
		10.0,
	)
	dps_simulation._apply_enemy_hit_records([{
		"entity_id": overkill_target.entity_id,
		"event": overkill_event,
	}])
	var newest_sample: DamageSample = dps_simulation.state.recent_damage_samples.back()
	assertions.expect_float(5.0, newest_sample.applied_damage, "DPS records applied HP loss without overkill")
	var retained_peak: float = dps_simulation.state.peak_dps
	assertions.expect_true(
		RunStateMachine.transition(dps_simulation.state, GameTypes.RunPhase.FAILED),
		"DPS fixture exits COMBAT",
	)
	assertions.expect_equal(0, dps_simulation.state.recent_damage_samples.size(), "COMBAT exit clears only recent deque")
	assertions.expect_float(retained_peak, dps_simulation.state.peak_dps, "COMBAT exit retains peak DPS")
	assertions.expect_true(dps_simulation.begin_wave(2), "DPS fixture begins next wave")
	assertions.expect_equal(0, dps_simulation.state.recent_damage_samples.size(), "next wave begins with empty DPS window")
	var next_wave_event: CombatEvent = dps_simulation.event_router.create_primary(
		dps_simulation.state,
		&"damage",
		-1,
		&"weapon:wood_stick",
		2.0,
	)
	dps_simulation._update_damage_samples(next_wave_event, 2.0)
	assertions.expect_equal(1, dps_simulation.state.recent_damage_samples.size(), "next wave damage does not combine deques")
	assertions.expect_float(2.0, dps_simulation.state.recent_damage_samples[0].applied_damage, "next wave deque contains only new damage")
	assertions.expect_float(retained_peak, dps_simulation.state.peak_dps, "next wave still retains run peak")


func _test_skill_hud_presentation(assertions: Variant, context: Dictionary) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	if catalog == null:
		return
	var packed := ResourceLoader.load("res://scenes/ui/combat_hud.tscn") as PackedScene
	assertions.expect_true(packed != null, "combat HUD scene loads for Gate 5")
	if packed == null:
		return
	var hud := packed.instantiate() as CombatHud
	context["tree"].root.add_child(hud)
	await context["tree"].process_frame
	var simulation: CombatSimulation = _new_simulation(catalog)
	_freeze_fixture(simulation)
	var skill_zero := hud.get_node("SkillPanel/Content/SkillSlot0/SkillSlot0Value") as Label
	var skill_one := hud.get_node("SkillPanel/Content/SkillSlot1/SkillSlot1Value") as Label
	hud.update_from_snapshot(simulation.build_snapshot())
	assertions.expect_equal("未装着", skill_zero.text, "HUD empty slot zero")
	assertions.expect_equal("未装着", skill_one.text, "HUD empty slot one")

	simulation.state.equipped[GameTypes.EquipmentSlot.SUB_WEAPON] = _unique_item(
		catalog,
		&"broken_clock",
		"hud-clock",
	)
	var cases: Array[Dictionary] = [
		{
			"skill_id": &"starfall",
			"level": 2,
			"progress": 2.5,
			"pending": 2,
			"text": "星落とし Lv2  2.5秒/3.0秒（残り0.5秒） 予約2",
		},
		{
			"skill_id": &"thousand_blades",
			"level": 3,
			"progress": 3.0,
			"pending": 1,
			"text": "千刃陣 Lv3  3/4 予約1",
		},
		{
			"skill_id": &"soul_chain",
			"level": 1,
			"progress": 7.0,
			"pending": 0,
			"text": "魂の連鎖 Lv1  7/8 予約0",
		},
		{
			"skill_id": &"bell_of_retribution",
			"level": 2,
			"progress": 2.0,
			"pending": 3,
			"text": "報復の鐘 Lv2  2/3 予約3",
		},
	]
	for hud_case: Dictionary in cases:
		simulation.state.skill_library.clear()
		var skill: SkillState = _skill(
			hud_case["skill_id"] as StringName,
			int(hud_case["level"]),
			0,
			float(hud_case["progress"]),
		)
		for serial: int in range(int(hud_case["pending"])):
			var pending := PendingSkillActivation.new()
			pending.activation_serial = serial
			skill.pending_queue.append(pending)
		simulation.state.skill_library[skill.skill_id] = skill
		simulation.skill_system.initialize(
			simulation.state,
			catalog,
			simulation.event_router,
		)
		hud.update_from_snapshot(simulation.build_snapshot())
		assertions.expect_equal(str(hud_case["text"]), skill_zero.text, "HUD exact presentation %s" % skill.skill_id)
		assertions.expect_equal("未装着", skill_one.text, "HUD second slot stays empty %s" % skill.skill_id)

	simulation.state.equipped[GameTypes.EquipmentSlot.HEAD] = _unique_item(
		catalog,
		&"hollow_crown",
		"hud-crown",
	)
	simulation.skill_system.synchronize_unique_state()
	hud.update_from_snapshot(simulation.build_snapshot())
	assertions.expect_equal("封印", skill_one.text, "HUD crown seals second skill slot")
	context["tree"].root.remove_child(hud)
	hud.free()


func _catalog(assertions: Variant) -> DefinitionCatalog:
	var catalog := DefinitionCatalog.new()
	assertions.expect_true(catalog.load_and_validate(), "Gate 5 scenario DefinitionCatalog valid")
	return catalog if catalog.is_valid else null


func _new_simulation(catalog: DefinitionCatalog) -> CombatSimulation:
	var state: RunState = RunStateFactory.create(20260827, catalog.wave(1))
	var simulation := CombatSimulation.new()
	simulation.initialize(state, catalog)
	return simulation


func _freeze_fixture(simulation: CombatSimulation) -> void:
	simulation.freeze_enemy_ai = true
	simulation.freeze_enemy_timers = true
	simulation.freeze_normal_spawn = true
	simulation.freeze_countdown = true


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


func _first_active_projectile(pool: ProjectilePool) -> ProjectileState:
	for projectile: ProjectileState in pool.slots:
		if projectile.active:
			return projectile
	return null
