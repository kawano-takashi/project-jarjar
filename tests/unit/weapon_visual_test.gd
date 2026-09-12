extends RefCounted


func test_weapon_regions_keep_actual_geometry_when_decorations_are_full(a: Variant, _context: Dictionary) -> void:
	var content: SurvivalContentManifest = BalanceTestFixtures.manifest()
	for definition: WeaponDefinition in content.weapons:
		if definition.weapon_id == &"resonance_wave":
			definition.range_scales_with_area = false
			for level: int in definition.range_by_level.size():
				definition.range_by_level[level] += 3.3
		if definition.weapon_id == &"zero_field":
			definition.effect_radius_scales_with_area = false
			for level: int in definition.effect_radius_by_level.size():
				definition.effect_radius_by_level[level] += 2.75
	content.combat.melee_arc_degrees = 70.0
	var catalog := DefinitionCatalog.new()
	a.expect_true(catalog.validate_manifest(content), catalog.error_text)
	if not catalog.is_valid:
		return
	for weapon_id: StringName in [&"resonance_wave", &"zero_field"]:
		var simulation: CombatSimulation = _simulation(catalog, weapon_id)
		for index: int in VfxPool.CAPACITY:
			simulation.vfx_pool.acquire(Vector2.ZERO, 0.1, 1.0, Color.WHITE, 0)
		var snapshot: CombatSnapshot = simulation.step(Vector2.ZERO)
		var wave: bool = weapon_id == &"resonance_wave"
		a.expect_equal(2 if wave else 1, snapshot.weapon_effect_transforms.size(), "the attack body survives a full decorative pool")
		for index: int in snapshot.weapon_effect_transforms.size():
			var transform: Transform3D = snapshot.weapon_effect_transforms[index]
			a.expect_float(5.5 if wave else 4.75, transform.basis.x.length(), "display range is not independently clamped to four metres")
			a.expect_equal(Vector2.ZERO, Vector2(transform.origin.x, transform.origin.z), "the displayed region starts at the real attack origin")
			a.expect_float(70.0 / 360.0 if wave else 1.0, snapshot.weapon_effect_custom_data[index].b, "fan angle and full-circle coverage come from the attack shape")
		if wave and snapshot.weapon_effect_transforms.size() == 2:
			a.expect_true(snapshot.weapon_effect_transforms[0].basis.z.normalized().is_equal_approx(-snapshot.weapon_effect_transforms[1].basis.z.normalized()), "both actual sweep directions are visible")


func test_native_weapon_hit_budget_does_not_limit_damage(a: Variant, _context: Dictionary) -> void:
	var simulation: CombatSimulation = _simulation(BalanceTestFixtures.catalog(), &"resonance_wave")
	simulation.state.combat_tick = 1
	for index: int in 80:
		simulation.spawn_fixture_enemy(GameTypes.EnemyType.BULWARK, Vector2(2.0, float(index) * 0.01), -1)
	simulation.world.set_context(CombatNative.context(simulation.catalog, simulation.state, Vector2.ZERO, 1))
	simulation.world.begin_weapon_visual_tick(1, 4, 3)
	simulation.world.attack_shapes([{"center": Vector2.ZERO, "radius": 5.0}], {
		"damage": 1.0, "critical_chance": 0.0, "critical_multiplier": 1.0, "outer": 5.0,
		"source": &"resonance_wave", "weapon_id": &"resonance_wave", "deduplicate": true,
	}, simulation.state.weapons[0].rng)
	var batch: Dictionary = simulation.world.take_weapon_visuals()
	a.expect_equal(4, batch.hits.size(), "native hit requests stop at the supplied decorative budget")
	a.expect_equal(76, int(batch.omitted_hits), "omitted decorations are still accounted for")
	var totals: Array = simulation.world.take_damage_totals()
	a.expect_equal(80, int(totals[0].count), "all successful hits contribute to gameplay")
	a.expect_float(80.0, float(totals[0].damage), "decorative suppression never changes applied damage")
	a.expect_true(simulation.world.take_weapon_visuals().hits.is_empty(), "visual batches drain once")


func test_arc_impact_region_is_once_even_when_no_enemy_is_hit(a: Variant, _context: Dictionary) -> void:
	for victims: int in [0, 3]:
		_check_arc_impact(a, victims)


func _check_arc_impact(a: Variant, victims: int) -> void:
	var simulation: CombatSimulation = _simulation(BalanceTestFixtures.catalog(), &"")
	for index: int in victims:
		var position := Vector2(3.05, 0.0) + Vector2.from_angle(PI * 0.5 + TAU * float(index) / 3.0) * 1.25
		simulation.spawn_fixture_enemy(GameTypes.EnemyType.BULWARK, position, -1)
	for index: int in VfxPool.CAPACITY:
		simulation.vfx_pool.acquire(Vector2.ZERO, 0.1, 1.0, Color.WHITE, 0)
	var projectile: ProjectileState = simulation.projectile_pool.acquire(
		ProjectileState.FACTION_ALLY, &"arc_crystal", -1, Vector2(3.0, 0.0), Vector2(3.0, 0.0),
		0.2, 10.0, 0.05, 1.0 / 60.0, Vector2(3.05, 0.0), 0, 0, &"arc_crystal",
		ProjectileState.MovementKind.ARC, -1, 1, 0, 1.2,
	)
	a.expect_true(projectile != null, "an expiring lob is created")
	var snapshot: CombatSnapshot = simulation.step(Vector2.ZERO)
	a.expect_equal(0, simulation.projectile_pool.active_count(), "the lob is consumed on impact")
	a.expect_equal(1, snapshot.weapon_effect_transforms.size(), "one explosion region survives decoration saturation regardless of the number of victims")
	a.expect_equal(victims, simulation.state.weapon_hit_count, "every victim is hit even when its impact decoration is suppressed")
	if snapshot.weapon_effect_transforms.is_empty():
		return
	var transform: Transform3D = snapshot.weapon_effect_transforms[0]
	a.expect_float(3.05, transform.origin.x, "the region uses the resolved impact point")
	a.expect_float(1.2, transform.basis.x.length(), "the region uses the actual explosion radius")
	simulation.take_events()
	a.expect_equal(snapshot.weapon_effect_transforms, simulation.build_snapshot().weapon_effect_transforms, "repeated reads do not re-emit the explosion")
	simulation.advance_tick(Vector2.ZERO)
	a.expect_equal(1, simulation.weapon_effects.size(), "the released projectile cannot create a second explosion")


func test_weapon_visual_lifetime_handles_pause_origin_shift_and_restart(a: Variant, _context: Dictionary) -> void:
	var catalog: DefinitionCatalog = BalanceTestFixtures.catalog()
	var simulation: CombatSimulation = _simulation(catalog, &"zero_field")
	simulation.spawn_fixture_enemy(GameTypes.EnemyType.BULWARK, Vector2(1.5, 0.0), -1)
	var before: CombatSnapshot = simulation.step(Vector2.ZERO)
	a.expect_equal(1, simulation.state.weapon_hit_count, "the field actually hits its target")
	a.expect_true(before.enemy_visual_custom_data[0].g > 0.0, "the real hit reaches the enemy shader's flash flag")
	a.expect_equal(1, before.weapon_effect_transforms.size(), "a hit displays the attack region without floating hit marks")
	simulation.state.weapons.clear()
	simulation.freeze_all_updates = true
	simulation.configure_accessibility(true, true)
	simulation.advance_tick(Vector2.ZERO)
	a.expect_equal(before.weapon_effect_custom_data, simulation.build_snapshot().weapon_effect_custom_data, "pausing also freezes the display age")
	a.expect_float(before.enemy_visual_custom_data[0].g, simulation.build_snapshot().enemy_visual_custom_data[0].g, "pausing retains the enemy's hit flash")
	simulation.player_position = Vector2(1025.0, 0.0)
	simulation._rebase_if_needed()
	var rebased: CombatSnapshot = simulation.build_snapshot()
	a.expect_float(-1024.0, rebased.weapon_effect_transforms[0].origin.x, "the active region follows a world origin shift")
	a.expect_float(0.0, before.weapon_effect_transforms[0].origin.x, "an older snapshot stays immutable")
	simulation.freeze_all_updates = false
	for index: int in WeaponVisualStyle.ATTACK_TICKS:
		simulation.advance_tick(Vector2.ZERO)
	a.expect_true(simulation.build_snapshot().weapon_effect_transforms.is_empty(), "a field is not visible between its attacks")
	simulation.initialize(RunStateFactory.create(4900, catalog), catalog)
	a.expect_true(simulation.build_snapshot().weapon_effect_transforms.is_empty(), "a new run has no effects from the previous run")


func test_weapon_qa_launches_build_single_and_mixed_loadouts(a: Variant, _context: Dictionary) -> void:
	var catalog: DefinitionCatalog = BalanceTestFixtures.catalog()
	for scenario: String in LaunchArguments.QA_SCENARIOS:
		if not scenario.begins_with("weapon_"):
			continue
		var launch: Dictionary = LaunchArguments.parse_debug(PackedStringArray(["--qa-scenario=" + scenario]))
		a.expect_true(launch.valid, "weapon QA launch accepts " + scenario)
		var result: Dictionary = QaScenarioFactory.build(scenario, catalog)
		a.expect_true(result.get("valid", false), "weapon QA builds " + scenario)
		if result.get("valid", false):
			a.expect_equal(5 if scenario.begins_with("weapon_mix_") else 1, result.state.weapons.size(), "QA equipment is ready for visual inspection")
			a.expect_true(result.rng_unchanged, "QA setup preserves the reproducible combat streams")


func _simulation(catalog: DefinitionCatalog, weapon_id: StringName) -> CombatSimulation:
	var state: RunState = RunStateFactory.create(4900, catalog)
	state.weapons.clear()
	if not weapon_id.is_empty():
		var definition: WeaponDefinition = catalog.weapon(weapon_id)
		var lineage: StringName = catalog.lineage_for_weapon(weapon_id)
		state.weapons.append(RunWeapon.create(weapon_id, lineage, definition.is_evolved,
			state.rng_streams.create_weapon_rng(lineage, 0)))
	var simulation := CombatSimulation.new()
	simulation.initialize(state, catalog)
	return simulation
