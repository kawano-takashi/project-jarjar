extends RefCounted


func test_names() -> PackedStringArray:
	return [
		"balance_saved_resource_uses_normal_loading_path",
		"balance_custom_player_enemy_xp_and_hud",
		"balance_unequal_timeline_events_and_boss",
		"balance_relative_weights_and_zero_candidates",
		"balance_variable_growth_and_multiple_stat_descriptions",
		"balance_invalid_values_report_source_field_and_rule",
		"balance_external_resources_are_isolated_between_runs",
		"balance_arena_and_scrollable_variable_ui",
		"balance_boss_telegraph_and_volley_follow_definition",
		"balance_stationary_projectile_values_remain_finite",
		"balance_evolution_definition_controls_pair_and_lineage",
	]


func run_test(name: String, assertions: Variant, context: Dictionary) -> void:
	match name:
		"balance_saved_resource_uses_normal_loading_path":
			_test_saved_resource(assertions, context)
		"balance_custom_player_enemy_xp_and_hud":
			_test_custom_values(assertions)
		"balance_unequal_timeline_events_and_boss":
			_test_timeline(assertions)
		"balance_relative_weights_and_zero_candidates":
			_test_weights(assertions)
		"balance_variable_growth_and_multiple_stat_descriptions":
			_test_growth(assertions)
		"balance_invalid_values_report_source_field_and_rule":
			_test_validation(assertions)
		"balance_external_resources_are_isolated_between_runs":
			_test_isolation(assertions)
		"balance_arena_and_scrollable_variable_ui":
			await _test_ui(assertions, context["tree"] as SceneTree)
		"balance_boss_telegraph_and_volley_follow_definition":
			_test_boss(assertions)
		"balance_stationary_projectile_values_remain_finite":
			_test_stationary_projectile(assertions)
		"balance_evolution_definition_controls_pair_and_lineage":
			_test_evolution_source(assertions)


func _test_saved_resource(a: Variant, context: Dictionary) -> void:
	var content: SurvivalContentManifest = BalanceTestFixtures.manifest()
	content.player.base_max_hp = 61.75
	content.segments[0].target_active = 23
	var path: String = String(context["test_path"]).get_base_dir().path_join("balance_fixture.tres")
	a.expect_equal(OK, ResourceSaver.save(content, path), "detached external definitions save as an editable Resource")
	var catalog := DefinitionCatalog.new()
	a.expect_true(catalog.load_and_validate(path), catalog.error_text)
	var simulation: CombatSimulation = _simulation(catalog, 71)
	a.expect_float(61.75, simulation.state.current_hp, "normal manifest loader accepts changed HP")
	a.expect_equal(23, catalog.segment(0).target_active, "normal manifest loader accepts enemy count")
	content.segments[0].target_active = -1
	var invalid_path: String = path.get_basename() + "_invalid.tres"
	a.expect_equal(OK, ResourceSaver.save(content, invalid_path), "invalid Resource fixture saves")
	var invalid := DefinitionCatalog.new()
	a.expect_false(invalid.load_and_validate(invalid_path), "normal loading rejects invalid input before run creation")
	a.expect_true(invalid.error_text.contains("target_active=-1"), "normal load error identifies invalid field and actual value")


func _test_custom_values(a: Variant) -> void:
	var content: SurvivalContentManifest = BalanceTestFixtures.manifest()
	content.player.base_max_hp = 73.25
	content.player.move_speed = 6.0
	content.player.body_radius = 0.3
	content.progression.xp_yield_percent = 100
	content.progression.xp_early_coefficient = 17
	content.progression.xp_early_offset = 4
	content.spawn.normal_entry_ticks = 0
	content.spawn.target_ramp_ticks = 9
	var segment: EnemySegmentDefinition = content.segments[0]
	segment.target_active = 9
	segment.hp_multiplier = 2.5
	segment.damage_multiplier = 1.3
	segment.spawn_weights = PackedFloat32Array([0, 3, 0, 0, 0, 0])
	var catalog: DefinitionCatalog = _catalog(content, a)
	var unit: EnemyDefinition = catalog.enemy_for_type(GameTypes.EnemyType.SWARMER)
	# Mutations are made on detached inputs and revalidated before use.
	unit.base_hp = 7.0
	unit.contact_damage = 5.0
	unit.xp_value = 11
	unit.move_speed = 0.0
	a.expect_true(catalog.validate_manifest(content), catalog.error_text)
	var simulation: CombatSimulation = _simulation(catalog, 97)
	for tick: int in range(9):
		simulation.state.combat_tick = tick + 1
		simulation.enemy_system.accrue_spawn_credit()
		simulation.enemy_system.resolve_normal_spawns(Vector2.ZERO, tick + 1)
	a.expect_equal(9, simulation.enemy_system.enemy_store.active_count(), "custom target and ramp control enemy amount")
	var enemy: EnemyEntity = simulation.enemy_system.enemy_store.entities[0]
	a.expect_float(17.5, enemy.hp, "custom enemy HP combines with segment HP")
	a.expect_float(5.0 * 1.3 * content.combat.normal_enemy_damage_scale, unit.contact_damage * enemy.damage_multiplier, "custom contact damage uses configured multipliers")
	for _tick: int in range(60):
		simulation._move_player(Vector2.RIGHT)
	a.expect_float(6.0, simulation.player_position.x, "custom speed moves six metres in sixty ticks")
	simulation._record_enemy_death(enemy)
	simulation._process_pending_deaths(9)
	a.expect_equal(11, simulation.xp_pickup_pool.total_value(), "enemy's configured XP reaches the pickup pool")
	a.expect_equal(11, simulation.state.normal_xp_by_segment[0], "XP metrics use the same definition")
	ProgressionService.add_xp(simulation.state, 10, catalog)
	var values: Dictionary = simulation.build_snapshot().hud_values
	a.expect_float(73.25, values["max_hp"], "HUD receives custom initial HP")
	a.expect_float(73.25, values["current_hp"], "initial HP is initialized by the factory")
	a.expect_equal(21, values["xp_for_next_level"], "HUD uses the configured XP formula")
	a.expect_equal(10, values["xp"], "HUD displays actual accumulated XP")
	segment.target_active = 0
	a.expect_true(catalog.validate_manifest(content), "zero enemy target is valid")
	var empty: CombatSimulation = _simulation(catalog, 98)
	empty.state.spawn_credit = 16.0
	a.expect_equal(0, empty.enemy_system.resolve_normal_spawns(Vector2.ZERO, 1).size(), "zero target emits no enemies")


func _test_timeline(a: Variant) -> void:
	var content: SurvivalContentManifest = BalanceTestFixtures.manifest()
	var segments: Array[EnemySegmentDefinition] = []
	for duration: int in [5, 7, 3]:
		var segment: EnemySegmentDefinition = content.segments[0].duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as EnemySegmentDefinition
		segment.duration_ticks = duration
		segment.target_active = 0
		segment.elite_spawns = []
		segment.swarm_schedules = []
		segments.append(segment)
	segments[0].elite_spawns = BalanceTestFixtures.elite_spawns([0, 3])
	segments[1].elite_spawns = BalanceTestFixtures.elite_spawns([1, 1])
	segments[2].elite_spawns = BalanceTestFixtures.elite_spawns([2])
	for id: StringName in [&"first", &"second"]:
		var schedule := SwarmEventScheduleDefinition.new()
		schedule.hp_multiplier = 1.0
		schedule.damage_multiplier = 0.5
		schedule.schedule_id = id
		schedule.first_offset_ticks = 2
		schedule.interval_ticks = 2
		schedule.attempt_count = 2
		schedule.spawn_chance = 1.0 if id == &"first" else 0.0
		segments[1].swarm_schedules.append(schedule)
	content.segments = segments
	content.swarm_event.lateral_count = 2
	content.swarm_event.depth_count = 1
	content.swarm_event.telegraph_ticks = 1
	var catalog: DefinitionCatalog = _catalog(content, a)
	a.expect_equal(PackedInt32Array([0, 5, 12]), catalog.segment_start_ticks, "starts accumulate ordered durations")
	a.expect_equal(PackedInt32Array([5, 12, 15]), catalog.segment_end_ticks, "unequal ends are exclusive")
	a.expect_equal(PackedInt32Array([0, 3, 6, 6, 14]), catalog.elite_spawn_ticks, "elite offsets expand in segment/array order")
	a.expect_equal([7, 9, 7, 9], catalog.swarm_attempts.map(func(event: Dictionary) -> int: return int(event[&"tick"])), "same-tick attempts retain definition order")
	var simulation: CombatSimulation = _simulation(catalog, 83)
	simulation.state.weapons.clear()
	for tick: int in range(16):
		simulation.state.combat_tick = tick
		simulation.enemy_system.resolve_scheduled_spawns(Vector2.ZERO, tick)
		simulation.enemy_system.resolve_swarm_event_spawns(Vector2.ZERO, tick)
		simulation._record_visible_enemy_sample(tick)
		if tick in [0, 4, 5, 11, 12, 14, 15]:
			var expected: int = 0 if tick < 5 else (1 if tick < 12 else (2 if tick < 15 else -1))
			a.expect_equal(expected, catalog.segment_index_for_tick(tick), "exclusive boundary at tick %d" % tick)
	a.expect_equal(15, simulation.state.boss_spawn_tick, "boss appears exactly at accumulated end")
	a.expect_equal(PackedInt32Array([5, 7, 3]), simulation.state.normal_active_samples_by_segment, "metrics follow configured segment lengths")
	a.expect_equal(5, simulation.state.elite_spawn_ticks.size(), "elite state follows scheduled event count")
	a.expect_equal(catalog.elite_spawn_ticks, simulation.state.elite_spawn_ticks, "every scheduled elite fires at its absolute tick")
	a.expect_equal(4, simulation.state.swarm_event_attempt_count, "each attempt is consumed once")
	a.expect_equal(1, simulation.state.swarm_event_group_count, "busy follow-up is consumed while the first formation remains")
	a.expect_equal(2, simulation.state.swarm_event_generated_count, "formation dimensions determine member count")
	a.expect_equal(1, simulation.state.swarm_event_skipped_busy_count, "busy attempt is separately recorded")


func _test_weights(a: Variant) -> void:
	a.expect_false(WeightedSelector.chance_succeeds_with_value(0.0, 0.0), "probability zero never succeeds, including a zero draw")
	a.expect_true(WeightedSelector.chance_succeeds_with_value(1.0, 1.0), "probability one always succeeds, including Godot's inclusive endpoint")
	a.expect_true(WeightedSelector.chance_succeeds_with_value(0.25, 0.24), "probability uses the expected fractional interval")
	a.expect_false(WeightedSelector.chance_succeeds_with_value(0.25, 0.25), "interior cumulative boundary is exclusive")
	a.expect_false(WeightedSelector.chance_succeeds_with_value(1.1, 0.5), "invalid probability never enters a draw")
	var ids: Array[StringName] = [&"zero", &"one", &"three"]
	var weights := PackedFloat64Array([0, 1, 3])
	var scaled := PackedFloat64Array([0, 17, 51])
	for value: float in [0.0, 0.24, 0.25, 0.99, 1.0]:
		a.expect_equal(WeightedSelector.select_with_value(ids, weights, value), WeightedSelector.select_with_value(ids, scaled, value), "relative weights preserve ratios")
	a.expect_equal(&"one", WeightedSelector.select_with_value(ids, weights, 0.0), "zero-weight leading candidate is never selected")
	a.expect_equal(&"three", WeightedSelector.select_with_value(ids, weights, 0.25), "exact cumulative boundary selects the next positive candidate")
	a.expect_false(WeightedSelector.validate_weights(ids, PackedFloat64Array([0, 0, 0])), "all-zero distribution is invalid")
	a.expect_false(WeightedSelector.validate_weights(ids, PackedFloat64Array([0, NAN, 1])), "non-finite distribution is invalid")
	var content: SurvivalContentManifest = BalanceTestFixtures.manifest()
	content.arena.node_drop_weights = PackedFloat32Array([0, 0, 7, 0])
	var catalog: DefinitionCatalog = _catalog(content, a)
	var state: RunState = RunStateFactory.create(81, catalog)
	for _draw: int in range(32):
		a.expect_equal(GameTypes.NodeDropType.VACUUM, NodeDropService.roll_drop(state, catalog), "node drops use relative weights and skip zero")
	for weapon: WeaponDefinition in content.weapons:
		if not weapon.is_evolved:
			weapon.selection_weight = 0.0 if weapon.weapon_id == content.progression.starter_weapon_id else 7.0
	a.expect_true(catalog.validate_manifest(content), catalog.error_text)
	state.pending_level_ups = 1
	var offer: LevelOffer = ProgressionService.create_offer(state, catalog)
	for option: UpgradeOption in offer.options:
		a.expect_true(option.content_id != content.progression.starter_weapon_id, "owned-offer branch also skips zero weight")

	state.pending_chest_sources.append(0)
	a.expect_equal(GameTypes.ChestOutcomeKind.FULL_HEAL, ChestRewardService.create_outcome(state, catalog).kind, "chest skips the owned zero-weight weapon")


func _test_growth(a: Variant) -> void:
	var content: SurvivalContentManifest = BalanceTestFixtures.manifest()
	var first: WeaponDefinition = _find_weapon(content, content.progression.starter_weapon_id)
	var second: WeaponDefinition = _find_weapon(content, &"resonance_wave")
	_set_levels(first, 3)
	_set_levels(second, 2)
	content.weapons = [first, second]
	content.evolutions = []
	var passive: PassiveDefinition = content.passives[0]
	passive.max_level = 2
	content.passives = [passive]
	content.progression.weapon_slot_count = 10
	content.progression.passive_slot_count = 12
	content.progression.level_offer_count = 17
	var catalog: DefinitionCatalog = _catalog(content, a)
	var state: RunState = RunStateFactory.create(91, catalog)
	a.expect_equal(6, ProgressionService.remaining_upgrade_capacity(state, catalog), "capacity counts reachable upgrades, not unreachable empty slots")
	state.pending_level_ups = 1
	var offer: LevelOffer = ProgressionService.create_offer(state, catalog)
	a.expect_equal(3, offer.options.size(), "offer shows only existing candidates")
	var detail: String = UpgradeDescriptionFormatter.weapon_detail(first, 2)
	a.expect_true(detail.contains("威力 4 → 5") and detail.contains("弾数 1 → 3"), "all simultaneous changes including amount +2 are displayed")
	a.expect_equal(2, detail.split("\n").size(), "each changed stat has its own line")
	var precise_passive: PassiveDefinition = passive.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as PassiveDefinition
	precise_passive.amount_per_level = -0.003
	a.expect_true(UpgradeDescriptionFormatter.passive_detail(precise_passive, 1, 2).contains("-0.003% → -0.006%"), "signed fractional passive amounts are displayed from the actual configuration")
	var precise: WeaponDefinition = first.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as WeaponDefinition
	precise.damage_by_level[1] = precise.damage_by_level[0] + 0.00001
	a.expect_equal(2, precise.level_deltas(2).size(), "small valid changes are not erased by approximate equality")
	a.expect_true(UpgradeDescriptionFormatter.weapon_detail(precise, 2).contains("4.00001"), "small changes remain visible in the description")
	for _choice: int in range(8):
		if state.build_maxed:
			break
		state.pending_level_ups = 1
		offer = ProgressionService.create_offer(state, catalog)
		a.expect_true(offer != null, "remaining capacity always produces an offer")
		if offer == null:
			break
		ProgressionService.apply_offer(state, catalog, offer.serial, 0)
	a.expect_true(state.build_maxed, "growth ends even with unreachable empty slots")
	a.expect_equal(2, state.weapons.size(), "weapon count stops at available content")
	a.expect_equal(1, state.passives.size(), "passive count stops at available content")
	a.expect_equal(0, ProgressionService.remaining_upgrade_capacity(state, catalog), "maximum levels follow independent array lengths")


func _test_validation(a: Variant) -> void:
	for case: String in ["hp", "speed", "target", "weights", "chance", "offset", "duration", "duplicate", "missing", "shape", "unchanged", "outer", "signed"]:
		var content: SurvivalContentManifest = BalanceTestFixtures.manifest()
		var field: String = ""
		match case:
			"hp":
				content.player.base_max_hp = 0.0
				field = "base_max_hp"
			"speed":
				content.player.move_speed = INF
				field = "move_speed"
			"target":
				content.segments[0].target_active = EnemyStore.CAPACITY + 1
				field = "target_active"
			"weights":
				content.segments[0].spawn_weights.fill(0.0)
				field = "spawn_weights"
			"chance":
				content.segments[2].swarm_schedules[0].spawn_chance = 1.1
				field = "spawn_chance"
			"offset":
				content.segments[2].swarm_schedules[0].first_offset_ticks = content.segments[2].duration_ticks
				field = "first_offset_ticks"
			"duration":
				content.segments[0].duration_ticks = 0
				field = "duration_ticks"
			"duplicate":
				content.weapons.append(content.weapons[0])
				field = "weapon_id"
			"missing":
				content.player = null
				field = "player"
			"shape":
				content.weapons[0].amount_by_level = []
				field = "amount_by_level"
			"unchanged":
				_set_levels(content.weapons[0], 2)
				content.weapons[0].damage_by_level[1] = 4.0
				content.weapons[0].amount_by_level[1] = 1
				field = "level[2]"
			"outer":
				content.weapons[0].range_by_level.fill(content.combat.effect_outer_radius * 2.0)
				field = "effective_outer_radius"
			"signed":
				content.passives[0].stat_id = &"max_hp_pct"
				content.passives[0].amount_per_level = -100.0
				field = "minimum_total"
		var catalog := DefinitionCatalog.new()
		a.expect_false(catalog.validate_manifest(content), "invalid %s input is rejected" % case)
		a.expect_true(catalog.error_text.contains(field) and catalog.error_text.contains("=") and catalog.error_text.contains(";"), "error includes source, field, actual value and rule: %s" % catalog.error_text)
	var path_content: SurvivalContentManifest = BalanceTestFixtures.manifest()
	path_content.segments[0].resource_path = "res://data/balance/segments/invalid_test_fixture.tres"
	path_content.segments[0].target_active = -1
	var path_catalog := DefinitionCatalog.new()
	a.expect_false(path_catalog.validate_manifest(path_content), "negative count is rejected")
	a.expect_true(path_catalog.error_text.contains("res://data/balance/segments/invalid_test_fixture.tres: target_active=-1"), "error locates the actual Resource path")


func _test_isolation(a: Variant) -> void:
	var canonical: SurvivalContentManifest = BalanceTestFixtures.catalog().manifest()
	var before: String = JSON.stringify(_values(canonical))
	var content: SurvivalContentManifest = BalanceTestFixtures.manifest()
	a.expect_true(content.weapons[0] != canonical.weapons[0] and content.player != canonical.player, "external resources are deeply duplicated")
	content.player.base_max_hp = 187.0
	content.segments[0].target_active = 3
	var catalog: DefinitionCatalog = _catalog(content, a)
	var detached_before: String = JSON.stringify(_values(content))
	var left: CombatSimulation = _simulation(catalog, 107)
	var right: CombatSimulation = _simulation(catalog, 107)
	for _tick: int in range(180):
		left.advance_tick(Vector2.RIGHT)
		right.advance_tick(Vector2.RIGHT)
	a.expect_equal(JSON.stringify(left.build_snapshot().hud_values), JSON.stringify(right.build_snapshot().hud_values), "same seed runs retain separate identical state")
	left.state.current_hp = 1.0
	a.expect_float(187.0, right.state.current_hp, "runtime HP does not leak into another run")
	a.expect_equal(detached_before, JSON.stringify(_values(content)), "combat does not mutate definition resources")
	a.expect_equal(before, JSON.stringify(_values(canonical)), "detached fixture changes never mutate cached external Resources")


func _test_ui(a: Variant, tree: SceneTree) -> void:
	var content: SurvivalContentManifest = BalanceTestFixtures.manifest()
	content.arena.size = Vector2(50.0, 28.0)
	content.arena.node_site_positions = PackedVector2Array([Vector2(-10, 0), Vector2(10, 0), Vector2(0, 5)])
	content.arena.initial_active_sites = PackedInt32Array([1])
	content.progression.xp_pool_capacity = 2377
	content.segments[0].elite_spawns = BalanceTestFixtures.elite_spawns([1, 2, 3, 4, 5, 6])
	content.progression.weapon_slot_count = 7
	content.progression.passive_slot_count = 9
	content.progression.level_offer_count = 9
	_set_levels(_find_weapon(content, content.progression.starter_weapon_id), 3)
	var catalog: DefinitionCatalog = _catalog(content, a)
	var simulation: CombatSimulation = _simulation(catalog, 123)
	a.expect_equal(25, simulation.enemy_system.uniform_grid.column_count, "grid width follows arena")
	a.expect_equal(14, simulation.enemy_system.uniform_grid.row_count, "grid height follows arena")
	a.expect_equal(3, simulation.arena_object_system.nodes.size(), "node count derives from site positions")
	a.expect_equal(1, simulation.arena_object_system.active_node_count(), "active node count derives from selected site indices")
	simulation.player_position = Vector2(100, 100)
	simulation._move_player(Vector2.ZERO)
	a.expect_equal(Vector2(25, 14) - Vector2.ONE * content.player.body_radius, simulation.player_position, "movement uses each arena dimension")
	var arena: ArenaPresenter = (load("res://scenes/gameplay/arena_combat.tscn") as PackedScene).instantiate() as ArenaPresenter
	arena.initialize(simulation)
	tree.root.add_child(arena)
	var overlay: SurvivalOverlay = (load("res://scenes/ui/survival_overlay.tscn") as PackedScene).instantiate() as SurvivalOverlay
	overlay.initialize(catalog)
	tree.root.add_child(overlay)
	await tree.process_frame
	var hud: CombatHud = arena.get_node("%CombatHUD") as CombatHud
	hud.update_from_snapshot(simulation.build_snapshot())
	a.expect_equal(2377, (arena.get_node("%XpInstances") as MultiMeshInstance3D).multimesh.instance_count, "XP drawing covers the configured pool")
	a.expect_equal(3, (arena.get_node("%NodeInstances") as MultiMeshInstance3D).multimesh.instance_count, "node drawing follows site count")
	a.expect_equal(catalog.elite_spawn_ticks.size(), (arena.get_node("%ChestInstances") as MultiMeshInstance3D).multimesh.instance_count, "chest drawing covers every configured elite")
	var boss_snapshot := CombatSnapshot.new()
	boss_snapshot.boss_charge_active = true
	boss_snapshot.boss_charge_spoke_count = 29
	arena.present_snapshot(boss_snapshot, 0.0)
	a.expect_equal(29, (arena.get_node("%BossChargeSpokes") as MultiMeshInstance3D).multimesh.visible_instance_count, "boss warning draws every spoke beyond the old fixed count")
	hud.update_from_snapshot(simulation.build_snapshot())
	a.expect_equal(7, hud.debug_state()["weapons"].size(), "HUD renders all configured weapon slots")
	a.expect_equal(9, hud.debug_state()["passives"].size(), "HUD renders all configured passive slots")
	a.expect_equal(Vector3(50, 0.1, 28), ((arena.get_node("Floor") as MeshInstance3D).mesh as BoxMesh).size, "floor drawing follows arena dimensions")
	simulation.state.pending_level_ups = 1
	var offer: LevelOffer = ProgressionService.create_offer(simulation.state, catalog)
	overlay.show_level_offer(offer)
	await tree.process_frame
	a.expect_equal(9, overlay.debug_state()["option_texts"].size(), "UI displays more than three choices")
	var scroll: ScrollContainer = overlay.get_node("%ChoiceScroll") as ScrollContainer
	a.expect_true(scroll.get_v_scroll_bar().max_value > scroll.size.y, "long choices are reachable by scrolling")
	a.expect_true(String(overlay.debug_state()["evolution_guide"]).contains("Lv3"), "evolution guide uses actual maximum level")
	arena.queue_free()
	overlay.queue_free()
	await tree.process_frame


func _test_boss(a: Variant) -> void:
	var content: SurvivalContentManifest = BalanceTestFixtures.manifest()
	var catalog: DefinitionCatalog = _catalog(content, a)
	var definition: EnemyDefinition = catalog.enemy_for_type(GameTypes.EnemyType.BOSS)
	definition.telegraph_ticks = 7
	definition.volley_count = 13
	a.expect_true(catalog.validate_manifest(content), catalog.error_text)
	var simulation: CombatSimulation = _simulation(catalog, 102)
	var boss: EnemyEntity = simulation.spawn_fixture_enemy(GameTypes.EnemyType.BOSS, Vector2.ZERO, -1, true)
	simulation.enemy_system._start_boss_charge(boss, 20)
	a.expect_equal(13, boss.boss_charge_spoke_count, "warning uses configured volley count")
	boss.boss_charge_elapsed_ticks = 3.5
	a.expect_float(0.5, boss.boss_charge_progress(), "warning progress uses configured telegraph duration")
	boss.boss_charge_elapsed_ticks = 6.0
	simulation.enemy_system._fire_ready_boss_volley(boss, 6, simulation.projectile_pool)
	a.expect_equal(0, simulation.projectile_pool.active_count(), "volley waits until final telegraph tick")
	boss.boss_charge_elapsed_ticks = 7.0
	simulation.enemy_system._fire_ready_boss_volley(boss, 7, simulation.projectile_pool)
	a.expect_equal(13, simulation.projectile_pool.active_count(), "actual volley uses same configured count")


func _test_stationary_projectile(a: Variant) -> void:
	var content: SurvivalContentManifest = BalanceTestFixtures.manifest()
	var arc: WeaponDefinition = _find_weapon(content, &"arc_crystal")
	_set_levels(arc, 2)
	arc.projectile_speed_by_level.fill(0.0)
	content.weapons = [arc]
	content.evolutions = []
	content.progression.starter_weapon_id = arc.weapon_id
	var catalog: DefinitionCatalog = _catalog(content, a)
	var simulation: CombatSimulation = _simulation(catalog, 103)
	simulation.weapon_system._spawn_ally_projectile(
		simulation.state.weapons[0], arc, Vector2.ZERO, Vector2.RIGHT,
		-1, {}, 0, ProjectileState.MovementKind.ARC, Vector2(2, 0),
	)
	a.expect_equal(1, simulation.projectile_pool.active_count(), "zero-speed projectile is a valid stationary effect")
	var projectile: ProjectileState = simulation.projectile_pool.resolve_snapshot_entry(simulation.projectile_pool.snapshot_active()[0])
	a.expect_true(is_finite(projectile.remaining_lifetime), "zero speed never divides by zero while determining travel duration")
	a.expect_equal(Vector2.ZERO, projectile.velocity, "zero speed is not replaced by a hidden minimum")


func _test_evolution_source(a: Variant) -> void:
	var content: SurvivalContentManifest = BalanceTestFixtures.manifest()
	content.progression.max_evolutions_per_run = 1
	var catalog: DefinitionCatalog = _catalog(content, a)
	var first: EvolutionDefinition = catalog.evolution_for_weapon(&"homing_core")
	var second: EvolutionDefinition = catalog.evolution_for_weapon(&"resonance_wave")
	var first_target: StringName = first.evolved_weapon_id
	first.evolved_weapon_id = second.evolved_weapon_id
	second.evolved_weapon_id = first_target
	a.expect_true(catalog.validate_manifest(content), "evolution references can change without editing duplicated weapon pairing fields")
	a.expect_equal(&"resonance_wave", catalog.lineage_for_weapon(first_target), "evolution Resource determines evolved damage lineage")
	var state: RunState = RunStateFactory.create(109, catalog)
	state.weapons[0].level = catalog.weapon(first.base_weapon_id).max_level
	ProgressionService.apply_direct_upgrade(state, catalog, GameTypes.UpgradeKind.PASSIVE, first.passive_id)
	state.pending_chest_sources.append(catalog.elite_chest_kinds.find(GameTypes.ChestKind.EVOLUTION_CAPABLE))
	var before: String = JSON.stringify(_values(content))
	var outcome: ChestOutcome = ChestRewardService.create_outcome(state, catalog)
	a.expect_equal(first.evolved_weapon_id, outcome.content_id, "chest follows the newly configured pairing")
	a.expect_true(ChestRewardService.apply_outcome(state, catalog, outcome.serial)[&"success"], "configured evolution applies")
	a.expect_equal(first.base_weapon_id, state.weapons[0].lineage_id, "evolved runtime retains its derived base lineage")
	ProgressionService.apply_direct_upgrade(state, catalog, GameTypes.UpgradeKind.WEAPON, second.base_weapon_id)
	state.weapon_for_lineage(second.base_weapon_id).level = catalog.weapon(second.base_weapon_id).max_level
	ProgressionService.apply_direct_upgrade(state, catalog, GameTypes.UpgradeKind.PASSIVE, second.passive_id)
	a.expect_true(ChestRewardService._eligible_evolutions(state, catalog).is_empty(), "custom evolution cap of one prevents a second otherwise eligible evolution")
	a.expect_equal(before, JSON.stringify(_values(content)), "evolving never mutates definition Resources")


func _catalog(content: SurvivalContentManifest, a: Variant) -> DefinitionCatalog:
	var catalog := DefinitionCatalog.new()
	a.expect_true(catalog.validate_manifest(content), catalog.error_text)
	return catalog


func _simulation(catalog: DefinitionCatalog, run_seed: int) -> CombatSimulation:
	var simulation := CombatSimulation.new()
	simulation.initialize(RunStateFactory.create(run_seed, catalog), catalog)
	return simulation


func _find_weapon(content: SurvivalContentManifest, id: StringName) -> WeaponDefinition:
	for weapon: WeaponDefinition in content.weapons:
		if weapon.weapon_id == id:
			return weapon
	return null


func _set_levels(weapon: WeaponDefinition, count: int) -> void:
	for key: String in ["damage_by_level", "cooldown_ticks_by_level", "amount_by_level", "projectile_speed_by_level", "range_by_level", "projectile_radius_by_level", "effect_radius_by_level", "duration_ticks_by_level", "pierce_by_level"]:
		var values: Variant = weapon.get(key)
		values.resize(count)
		for index: int in range(count):
			match key:
				"damage_by_level": values[index] = 4 + index
				"cooldown_ticks_by_level": values[index] = 60
				"amount_by_level": values[index] = 1 + index * 2
				"projectile_speed_by_level": values[index] = 4.0
				"range_by_level": values[index] = 2.0
				"projectile_radius_by_level": values[index] = 0.2
				"duration_ticks_by_level": values[index] = 120
				_: values[index] = 0
		weapon.set(key, values)


func _values(value: Variant) -> Variant:
	if value is Resource:
		var result: Dictionary = {}
		for property: Dictionary in (value as Resource).get_property_list():
			if (int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
				result[property.name] = _values(value.get(property.name))
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value:
			result.append(_values(item))
		return result
	return var_to_str(value)
