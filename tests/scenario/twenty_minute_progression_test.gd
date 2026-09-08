extends RefCounted


func test_chest_kind_survives_delayed_elite_death_and_collection(a: Variant, _context: Dictionary) -> void:
	var sim: CombatSimulation = _simulation(_catalog(_content(), a))
	var system: EnemySystem = sim.enemy_system
	sim.state.combat_tick = 1
	var first: EnemyEntity = system.resolve_scheduled_spawns(Vector2.ZERO, 1)[0]
	a.expect_equal(0, first.elite_serial, "scheduled source identifies the ordinary elite")
	# The first elite is killed only after the capable elite has already appeared.
	sim.state.combat_tick = 6
	a.expect_equal(2, system.resolve_scheduled_spawns(Vector2.ZERO, 6).size(), "later elites retain separate scheduled sources")
	first.position = Vector2(2, 0)
	_kill(sim, first)
	var chest: ArenaPickup = sim.arena_object_system.pickups[0]
	a.expect_equal(GameTypes.ChestKind.NORMAL, chest.chest_kind, "late death still drops an ordinary chest")
	a.expect_equal(0, chest.source_serial, "drop preserves source index")
	_prepare_evolution(sim.state, sim.catalog)
	sim.state.combat_tick = 60
	sim.player_position = chest.position
	sim._collect_arena_pickups(60)
	sim._resolve_modal_priority()
	var outcome: ChestOutcome = sim.state.active_chest_outcome
	a.expect_true(outcome != null, "stored floor chest remains collectible")
	if outcome == null:
		return
	a.expect_equal(GameTypes.ChestKind.NORMAL, outcome.source_chest_kind, "result retains ordinary kind after prolonged storage")
	a.expect_equal(GameTypes.ChestOutcomeKind.UPGRADE, outcome.kind, "prepared evolution cannot use the stored ordinary chest")
	a.expect_true(sim.complete_chest_reward(), "ordinary upgrade applies")
	a.expect_equal(0, sim.state.evolution_count, "ordinary chest cannot evolve even late")
	var capable: EnemyEntity = null
	for enemy: EnemyEntity in system.enemy_store.entities:
		if enemy.elite_serial == 1:
			capable = enemy
	a.expect_true(capable != null, "capable elite remains alive until delayed kill")
	if capable == null:
		return
	capable.position = sim.player_position
	_kill(sim, capable)
	sim._collect_arena_pickups(60)
	sim._resolve_modal_priority()
	a.expect_equal(GameTypes.ChestKind.EVOLUTION_CAPABLE, sim.state.active_chest_outcome.source_chest_kind, "late capable drop retains its kind")
	a.expect_equal(GameTypes.ChestOutcomeKind.EVOLUTION, sim.state.active_chest_outcome.kind, "eligible capable chest evolves without a global time gate")


func test_mixed_chest_queue_preserves_level_priority_and_fallbacks(a: Variant, _context: Dictionary) -> void:
	var catalog: DefinitionCatalog = _catalog(_content(), a)
	var sim: CombatSimulation = _simulation(catalog)
	_prepare_evolution(sim.state, catalog)
	# Collection order deliberately differs from source/spawn order.
	for source: int in [2, 1, 0]:
		sim.arena_object_system.spawn_chest(Vector2.ZERO, source)
	sim._collect_arena_pickups(0)
	sim.state.pending_level_ups = 1
	sim._resolve_modal_priority()
	a.expect_equal(GameTypes.RunPhase.LEVEL_UP, sim.state.phase, "level-up takes priority over both chest types")
	a.expect_equal([2, 1, 0], sim.state.pending_chest_sources, "mixed pickups preserve FIFO order")
	a.expect_true(sim.apply_upgrade_choice(0), "level-up resolves before chest")
	var expected_kinds: Array[int] = [GameTypes.ChestKind.NORMAL, GameTypes.ChestKind.EVOLUTION_CAPABLE, GameTypes.ChestKind.NORMAL]
	for expected: int in expected_kinds:
		var outcome: ChestOutcome = sim.state.active_chest_outcome
		a.expect_true(outcome != null, "next queued chest has a result")
		if outcome == null:
			return
		a.expect_equal(expected, int(outcome.source_chest_kind), "each queued result keeps its source kind")
		var serial: int = outcome.serial
		a.expect_true(sim.complete_chest_reward(), "queued result applies once")
		a.expect_false(bool(ChestRewardService.apply_outcome(sim.state, catalog, serial)[&"success"]), "replayed result cannot apply twice or consume next chest")
	a.expect_equal(3, sim.state.opened_chests, "exactly three chest rewards applied")
	a.expect_equal(1, sim.state.evolution_count, "only the capable box evolves")
	a.expect_equal(GameTypes.RunPhase.COMBAT, sim.state.phase, "mixed modal chain resumes combat")
	for source: int in [0, 1]:
		var fresh: RunState = RunStateFactory.create(2082, catalog)
		fresh.pending_chest_sources.append(source)
		a.expect_equal(GameTypes.ChestOutcomeKind.UPGRADE, ChestRewardService.create_outcome(fresh, catalog).kind, "either type upgrades when no evolution is prepared")
		var maxed: RunState = RunStateFactory.create(2083, catalog)
		maxed.weapons[0].level = catalog.weapon(maxed.weapons[0].weapon_id).max_level
		maxed.current_hp = 1.0
		maxed.pending_chest_sources.append(source)
		var healing: ChestOutcome = ChestRewardService.create_outcome(maxed, catalog)
		a.expect_equal(GameTypes.ChestOutcomeKind.FULL_HEAL, healing.kind, "either type heals when no owned upgrade or evolution is eligible")
		ChestRewardService.apply_outcome(maxed, catalog, healing.serial)
		a.expect_float(maxed.max_hp, maxed.current_hp, "fallback restores full HP")
	var capped: RunState = RunStateFactory.create(2084, catalog)
	_prepare_evolution(capped, catalog)
	capped.evolution_count = catalog.manifest().progression.max_evolutions_per_run
	capped.pending_chest_sources.append(1)
	a.expect_equal(GameTypes.ChestOutcomeKind.UPGRADE, ChestRewardService.create_outcome(capped, catalog).kind, "evolution cap falls back to owned upgrade")


func test_swarm_warning_locks_route_and_consumes_busy_attempts(a: Variant, _context: Dictionary) -> void:
	var sim: CombatSimulation = _simulation(_catalog(_content(), a))
	var system: EnemySystem = sim.enemy_system
	var anchor := Vector2(2, -3)
	sim.state.combat_tick = 10
	a.expect_true(system.resolve_swarm_event_spawns(anchor, 10).is_empty(), "attempt starts warning without spawning enemies")
	var warning: SwarmWarningState = system.swarm_warning
	a.expect_true(warning != null, "warning is pending")
	if warning == null:
		return
	a.expect_equal(15, warning.spawn_tick, "warning deadline uses definition tick duration")
	var direction: Vector2 = warning.direction
	for tick: int in [12, 14]:
		sim.state.combat_tick = tick
		a.expect_true(system.resolve_swarm_event_spawns(-anchor, tick).is_empty(), "busy warning consumes extra attempts without a second route")
		a.expect_true(system.swarm_warning == warning, "warning is not replaced when the player moves")
	sim.state.combat_tick = 15
	var group: Array[EnemyEntity] = system.resolve_swarm_event_spawns(-anchor, 15)
	a.expect_equal(3, group.size(), "exact deadline spawns the complete group")
	a.expect_true(system.swarm_warning == null, "warning ends on spawn")
	for enemy: EnemyEntity in group:
		a.expect_true(direction.is_equal_approx(enemy.fixed_direction), "actual trajectory matches warning direction")
		a.expect_float(warning.spawn_distance, -(enemy.position - anchor).dot(direction), "actual trajectory stays anchored to the warned position")
		a.expect_float(9.0, enemy.max_hp, "schedule HP multiplier is independent of regular segment multiplier")
		a.expect_float(8.0, enemy.definition.contact_damage * enemy.damage_multiplier, "schedule damage bypasses regular segment and common multipliers")
	system.resolve_swarm_event_spawns(Vector2.ZERO, 16)
	a.expect_true(system.swarm_warning == null, "living swarm prevents another warning")
	a.expect_equal(3, sim.state.swarm_event_skipped_busy_count, "both pending and living conflicts are consumed")
	system.enemy_store.clear()
	system.resolve_swarm_event_spawns(Vector2.ZERO, 24)
	a.expect_true(system.swarm_warning == null, "clearing a group does not release a backlog")
	a.expect_equal(1, sim.state.swarm_event_group_count, "skipped groups never spawn later")
	system.resolve_swarm_event_spawns(Vector2.ZERO, 25)
	a.expect_true(system.swarm_warning != null, "next fresh schedule can start after the group is gone")
	a.expect_equal(5, sim.state.swarm_event_attempt_count, "each scheduled attempt is consumed exactly once")


func test_swarm_warning_pauses_and_is_cancelled_at_short_boss_boundary(a: Variant, _context: Dictionary) -> void:
	var sim: CombatSimulation = _simulation(_catalog(_content(), a))
	sim.state.combat_tick = 10
	sim.enemy_system.resolve_swarm_event_spawns(Vector2.ZERO, 10)
	var warning: SwarmWarningState = sim.enemy_system.swarm_warning
	sim.freeze_all_updates = true
	for _tick: int in range(30):
		a.expect_false(sim.advance_tick(Vector2.RIGHT), "pause does not advance combat")
	a.expect_equal(10, sim.state.combat_tick, "pause excludes time from boss and warning clocks")
	a.expect_float(0.0, warning.progress(sim.state.combat_tick), "pause freezes warning progress")
	sim.freeze_all_updates = false
	sim.state.pending_level_ups = 1
	sim._resolve_modal_priority()
	a.expect_false(sim.advance_tick(Vector2.ZERO), "choice modal also freezes warning")
	sim.apply_upgrade_choice(0)
	a.expect_true(sim.advance_tick(Vector2.ZERO), "warning resumes with combat")
	a.expect_equal(11, sim.state.combat_tick, "resume advances exactly one tick")
	# Independent 80-tick fixture must use the same transition as the long run.
	sim.enemy_system.cancel_swarm_warning()
	sim.enemy_system.enemy_store.clear()
	sim.state.combat_tick = 78
	sim.enemy_system.resolve_swarm_event_spawns(Vector2.ZERO, 78)
	a.expect_true(sim.enemy_system.swarm_warning != null, "late warning starts before shortened boss boundary")
	sim.state.combat_tick = 79
	sim.advance_tick(Vector2.ZERO)
	a.expect_equal(80, sim.state.boss_spawn_tick, "boss follows sum of independent segment lengths")
	a.expect_true(sim.enemy_system.swarm_warning == null, "boss transition cancels warning even before its deadline")
	a.expect_equal(0, sim.enemy_system.resolve_scheduled_spawns(Vector2.ZERO, 80).size(), "boss is not spawned twice")
	sim.advance_tick(Vector2.ZERO)
	var boss: EnemyEntity = sim.enemy_system.boss_entity()
	a.expect_true(boss != null, "boss persists until defeated")
	if boss == null:
		return
	boss.position = sim.player_position + Vector2(1, 0)
	_kill(sim, boss)
	sim.advance_tick(Vector2.ZERO)
	a.expect_equal(GameTypes.RunPhase.RESULT, sim.state.phase, "boss death ends the shortened run with victory")
	a.expect_equal(1, sim.state.boss_kills, "boss victory records one kill")


func test_swarm_kills_open_a_gap(a: Variant, _context: Dictionary) -> void:
	var sim: CombatSimulation = _simulation(_catalog(_content(), a))
	sim.state.combat_tick = 20
	var group: Array[EnemyEntity] = sim.enemy_system._spawn_swarm_group(Vector2.ZERO, Vector2.RIGHT, 20, 2.0, 3.0, 4.0)
	var middle: EnemyEntity = group[1]
	var gap_position: Vector2 = middle.position
	_kill(sim, middle)
	a.expect_equal(2, sim.enemy_system.enemy_store.active_count(), "killing a member leaves a physical gap")
	a.expect_equal(1, sim.state.swarm_event_kill_count, "breaking through counts as a swarm kill")
	a.expect_equal(0, sim.enemy_system.resolve_contact_damage_candidates(sim.enemy_system.snapshot_ids(), gap_position, 20).size(), "player can occupy the killed member's gap without contact")


func test_chest_shapes_and_swarm_warning_match_gameplay_snapshot(a: Variant, context: Dictionary) -> void:
	var tree: SceneTree = context["tree"]
	var sim: CombatSimulation = _simulation(_catalog(_content(), a))
	sim.arena_object_system.spawn_chest(Vector2(-2, 0), 0)
	sim.arena_object_system.spawn_chest(Vector2(2, 0), 1)
	sim.state.combat_tick = 10
	sim.enemy_system.resolve_swarm_event_spawns(Vector2(3, 4), 10)
	var snapshot: CombatSnapshot = sim.build_snapshot()
	var arena: ArenaPresenter = (load("res://scenes/gameplay/arena_combat.tscn") as PackedScene).instantiate() as ArenaPresenter
	arena.initialize(sim)
	tree.root.add_child(arena)
	var overlay: SurvivalOverlay = (load("res://scenes/ui/survival_overlay.tscn") as PackedScene).instantiate() as SurvivalOverlay
	overlay.initialize(sim.catalog)
	tree.root.add_child(overlay)
	await tree.process_frame
	arena.present_snapshot(snapshot, 0.0)
	var normal: MultiMesh = (arena.get_node("%ChestInstances") as MultiMeshInstance3D).multimesh
	var capable: MultiMesh = (arena.get_node("%EvolutionChestInstances") as MultiMeshInstance3D).multimesh
	a.expect_equal(1, normal.visible_instance_count, "ordinary floor boxes have their own instances")
	a.expect_equal(1, capable.visible_instance_count, "capable floor boxes have their own instances")
	a.expect_true(normal.mesh is BoxMesh and capable.mesh is CylinderMesh, "kinds differ in silhouette as well as color")
	a.expect_not_equal((normal.mesh.material as StandardMaterial3D).albedo_color, (capable.mesh.material as StandardMaterial3D).albedo_color, "chest materials have distinct colors")
	var marker: MeshInstance3D = arena.get_node("%SwarmWarningMarker") as MeshInstance3D
	var arrows: MultiMesh = (arena.get_node("%SwarmWarningArrows") as MultiMeshInstance3D).multimesh
	a.expect_true(marker.visible, "warning band is visible")
	var forward := Vector3(snapshot.swarm_warning_direction.x, 0.0, snapshot.swarm_warning_direction.y)
	a.expect_true(marker.basis.x.normalized().is_equal_approx(forward), "long axis matches the real diagonal route without skew")
	a.expect_float(snapshot.swarm_warning_length, marker.basis.x.length(), "warning retains actual path length after rotation")
	a.expect_float(snapshot.swarm_warning_width, marker.basis.z.length(), "warning retains formation width after rotation")
	a.expect_equal(Vector3(3, 0.07, 4), marker.position, "warning remains fixed on captured ground position")
	a.expect_equal(6, arrows.visible_instance_count, "three chevrons communicate travel direction")
	for source: int in [0, 1]:
		sim.state.pending_chest_sources.append(source)
		var outcome: ChestOutcome = ChestRewardService.create_outcome(sim.state, sim.catalog)
		overlay.show_chest_outcome(outcome)
		a.expect_equal(GameTypes.chest_kind_label(outcome.source_chest_kind), overlay.debug_state()["chest_heading"], "reward heading names the source chest type")
		ChestRewardService.apply_outcome(sim.state, sim.catalog, outcome.serial)
	sim.enemy_system.cancel_swarm_warning()
	arena.present_snapshot(sim.build_snapshot(), 0.0)
	a.expect_false(marker.visible, "cancelled warning band is removed")
	a.expect_equal(0, arrows.visible_instance_count, "cancelled warning arrows are removed")
	arena.queue_free()
	overlay.queue_free()
	await tree.process_frame


func test_elite_and_swarm_resources_reject_invalid_schedules(a: Variant, _context: Dictionary) -> void:
	for invalid_case: int in range(5):
		var content: SurvivalContentManifest = _content()
		var field: String
		match invalid_case:
			0:
				content.segments[0].elite_spawns[0] = null
				field = "elite_spawns"
			1:
				content.segments[0].elite_spawns[0].offset_ticks = content.segments[0].duration_ticks
				field = "offset_ticks"
			2:
				content.segments[0].elite_spawns[0].set("chest_kind", 99)
				field = "chest_kind"
			3:
				content.swarm_event.telegraph_ticks = 0
				field = "telegraph_ticks"
			4:
				content.segments[0].swarm_schedules[0].hp_multiplier = 0.0
				field = "hp_multiplier"
		var catalog := DefinitionCatalog.new()
		a.expect_false(catalog.validate_manifest(content), "invalid schedule is rejected before play")
		a.expect_true(catalog.error_text.contains(field), "validation identifies the offending public field")


func _content() -> SurvivalContentManifest:
	var content: SurvivalContentManifest = BalanceTestFixtures.manifest()
	content.segments.resize(2)
	for segment: EnemySegmentDefinition in content.segments:
		segment.duration_ticks = 40
		segment.target_active = 0
		segment.hp_multiplier = 11.0
		segment.damage_multiplier = 13.0
		segment.elite_spawns.clear()
		segment.swarm_schedules.clear()
	content.segments[0].elite_spawns = BalanceTestFixtures.elite_spawns([1, 3, 5])
	content.segments[0].elite_spawns[1].chest_kind = GameTypes.ChestKind.EVOLUTION_CAPABLE
	content.spawn.elite_entry_ticks = 1
	content.spawn.boss_entry_ticks = 1
	content.swarm_event.telegraph_ticks = 5
	content.swarm_event.lateral_count = 3
	content.swarm_event.depth_count = 1
	content.swarm_event.lateral_pitch = 2.0
	content.swarm_event.unit_definition.base_hp = 3.0
	content.swarm_event.unit_definition.contact_damage = 2.0
	content.segments[0].swarm_schedules.append(_schedule(&"dense", 10, 2, 4))
	content.segments[0].swarm_schedules.append(_schedule(&"fresh", 25, 1, 1))
	content.segments[1].swarm_schedules.append(_schedule(&"late", 38, 1, 1))
	return content


func _schedule(id: StringName, offset: int, interval: int, attempts: int) -> SwarmEventScheduleDefinition:
	var schedule := SwarmEventScheduleDefinition.new()
	schedule.schedule_id = id
	schedule.first_offset_ticks = offset
	schedule.interval_ticks = interval
	schedule.attempt_count = attempts
	schedule.spawn_chance = 1.0
	schedule.hp_multiplier = 3.0
	schedule.damage_multiplier = 4.0
	return schedule


func _catalog(content: SurvivalContentManifest, a: Variant) -> DefinitionCatalog:
	var catalog := DefinitionCatalog.new()
	a.expect_true(catalog.validate_manifest(content), "detached short timeline is valid: %s" % catalog.error_text)
	return catalog


func _simulation(catalog: DefinitionCatalog) -> CombatSimulation:
	var sim := CombatSimulation.new()
	sim.initialize(RunStateFactory.create(2080, catalog), catalog)
	return sim


func _prepare_evolution(state: RunState, catalog: DefinitionCatalog) -> void:
	var weapon: RunWeapon = state.weapons[0]
	weapon.level = catalog.weapon(weapon.weapon_id).max_level
	var evolution: EvolutionDefinition = catalog.evolution_for_weapon(weapon.weapon_id)
	ProgressionService.apply_direct_upgrade(state, catalog, GameTypes.UpgradeKind.PASSIVE, evolution.passive_id)


func _kill(sim: CombatSimulation, enemy: EnemyEntity) -> void:
	var event: CombatEvent = sim.event_router.create_primary(sim.state, &"weapon_hit", -1, &"homing_core", enemy.max_hp)
	sim._apply_enemy_hit_records([{"entity_id": enemy.entity_id, "event": event}])
	sim._process_pending_deaths(sim.state.combat_tick)
