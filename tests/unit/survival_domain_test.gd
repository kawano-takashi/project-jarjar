extends RefCounted


func test_names() -> PackedStringArray:
	return PackedStringArray([
		"survival_all_content_fixed_contract",
		"survival_close_range_outer_edges_are_linear",
		"survival_xp_formula_growth_and_queue",
		"survival_capacity_level_sixty_five_and_growth_application",
		"survival_growth_boundaries_apply_per_level_segment",
		"survival_manifest_drives_progression_and_xp_pickups",
		"survival_xp_yield_fraction_and_growth_order",
		"survival_validator_rejects_fixed_boss_enrage_drift",
		"survival_validator_rejects_all_nonboss_ranged_drift",
		"survival_segment_tuning_bounds_and_steps",
		"survival_weighted_unique_offer_and_serial_guard",
		"survival_queued_offer_levels_and_owned_probability",
		"survival_owned_offer_uses_uniform_owned_selection",
		"survival_duplicate_owned_attempt_falls_back_without_reroll",
		"survival_full_inventory_skips_owned_offer_attempts",
		"survival_new_weapon_upgrade_is_atomic",
		"survival_slot_and_max_rejections",
		"survival_chest_evolution_fallback_and_cap",
		"survival_chest_owned_upgrade_stability_serial_and_single_effect",
		"survival_chest_last_upgrade_clears_growth_state",
		"survival_chest_source_fifo_and_mismatch_guard",
		"survival_rng_streams_and_lineage_damage",
		"survival_rng_stream_mutual_isolation_and_derived_repeatability",
		"survival_node_drop_effects",
		"survival_build_max_stops_leveling",
	])


func run_test(test_name: String, assertions: Variant, _context: Dictionary) -> void:
	match test_name:
		"survival_all_content_fixed_contract":
			_test_all_content_fixed_contract(assertions)
		"survival_close_range_outer_edges_are_linear":
			_test_close_range_outer_edges(assertions)
		"survival_xp_formula_growth_and_queue":
			_test_xp(assertions)
		"survival_capacity_level_sixty_five_and_growth_application":
			_test_capacity_level_and_growth(assertions)
		"survival_growth_boundaries_apply_per_level_segment":
			_test_growth_boundaries(assertions)
		"survival_manifest_drives_progression_and_xp_pickups":
			_test_manifest_driven_xp(assertions)
		"survival_xp_yield_fraction_and_growth_order":
			_test_xp_yield_fraction_and_growth_order(assertions)
		"survival_validator_rejects_fixed_boss_enrage_drift":
			_test_boss_enrage_validation(assertions)
		"survival_validator_rejects_all_nonboss_ranged_drift":
			_test_nonboss_ranged_validation(assertions)
		"survival_segment_tuning_bounds_and_steps":
			_test_segment_tuning_contract(assertions)
		"survival_weighted_unique_offer_and_serial_guard":
			_test_offer(assertions)
		"survival_queued_offer_levels_and_owned_probability":
			_test_queued_offer_levels_and_owned_probability(assertions)
		"survival_owned_offer_uses_uniform_owned_selection":
			_test_owned_offer_uses_uniform_owned_selection(assertions)
		"survival_duplicate_owned_attempt_falls_back_without_reroll":
			_test_duplicate_owned_attempt_falls_back_without_reroll(assertions)
		"survival_full_inventory_skips_owned_offer_attempts":
			_test_full_inventory_skips_owned_offer_attempts(assertions)
		"survival_new_weapon_upgrade_is_atomic":
			_test_new_weapon_atomic(assertions)
		"survival_slot_and_max_rejections":
			_test_slot_and_max_rejections(assertions)
		"survival_chest_evolution_fallback_and_cap":
			_test_chests(assertions)
		"survival_chest_owned_upgrade_stability_serial_and_single_effect":
			_test_chest_owned_upgrade_contract(assertions)
		"survival_chest_last_upgrade_clears_growth_state":
			_test_chest_last_upgrade_clears_growth_state(assertions)
		"survival_chest_source_fifo_and_mismatch_guard":
			_test_chest_source_fifo_and_mismatch_guard(assertions)
		"survival_rng_streams_and_lineage_damage":
			_test_rng_and_damage(assertions)
		"survival_rng_stream_mutual_isolation_and_derived_repeatability":
			_test_rng_stream_isolation(assertions)
		"survival_node_drop_effects":
			_test_node_drops(assertions)
		"survival_build_max_stops_leveling":
			_test_build_max(assertions)
		_:
			assertions.expect_true(false, "registered survival progression test")


func _test_all_content_fixed_contract(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	var expected_base_ids: Array[StringName] = [
		&"arc_crystal",
		&"directional_needle",
		&"homing_core",
		&"mass_projectile",
		&"orbital_array",
		&"resonance_wave",
		&"returning_ring",
		&"zero_field",
	]
	var expected_evolved_ids: Array[StringName] = [
		&"absorption_field",
		&"collapse_projectile",
		&"critical_ring",
		&"eternal_orbit",
		&"infinite_homing",
		&"infinite_needles",
		&"spiral_crystal",
		&"vital_resonance",
	]
	var expected_passive_ids: Array[StringName] = [
		&"amplifier_core",
		&"cycle_crystal",
		&"duration_ring",
		&"life_lattice",
		&"probability_core",
		&"repair_core",
		&"scale_lens",
		&"speed_gate",
	]
	assertions.expect_equal(expected_base_ids, catalog.basic_weapon_ids(), "all eight base weapon IDs are fixed")
	assertions.expect_equal(expected_evolved_ids, catalog.evolved_weapon_ids(), "all eight evolved weapon IDs are fixed")
	assertions.expect_equal(expected_passive_ids, catalog.passive_ids(), "all eight passive IDs are fixed")
	assertions.expect_equal(&"homing_core", catalog.manifest().starter_weapon_id, "nearest-target weapon is the starter")
	assertions.expect_equal(2, catalog.manifest().owned_offer_attempt_count, "owned offer uses two attempts")
	assertions.expect_float(0.3, catalog.manifest().owned_offer_luck_coefficient, "owned offer luck coefficient")
	assertions.expect_equal(90, catalog.manifest().xp_yield_percent, "revision five tuned XP yield supports the denser arena")
	assertions.expect_float(
		0.55,
		catalog.manifest().normal_enemy_damage_scale,
		"revision five keeps dense contact pressure survivable",
	)
	assertions.expect_equal(
		50,
		catalog.enemy_for_type(GameTypes.EnemyType.ELITE).xp_value,
		"calibrated elite XP supports the intended evolution pacing",
	)
	var expected_segment_targets: Array[int] = [16, 24, 36, 52, 72, 96, 120, 144, 168, 192]
	var expected_segment_hp: Array[float] = [
		0.15, 0.17, 0.20, 0.24, 0.30, 0.45, 0.65, 0.90, 1.25, 1.75,
	]
	var expected_segment_damage: Array[float] = [
		0.18, 0.20, 0.22, 0.25, 0.29, 0.36, 0.45, 0.56, 0.72, 0.95,
	]
	for segment_index: int in range(10):
		var segment: EnemySegmentDefinition = catalog.segment(segment_index)
		assertions.expect_equal(
			expected_segment_targets[segment_index],
			segment.target_active,
			"segment %d calibrated active-enemy pressure" % (segment_index + 1),
		)
		assertions.expect_float(
			expected_segment_hp[segment_index],
			segment.hp_multiplier,
			"segment %d calibrated HP pressure" % (segment_index + 1),
		)
		assertions.expect_float(
			expected_segment_damage[segment_index],
			segment.damage_multiplier,
			"segment %d calibrated contact pressure" % (segment_index + 1),
		)
	var expected_weapon_ranges: Dictionary = {
		&"resonance_wave": PackedFloat32Array([2.2, 2.3714286, 2.5428571, 2.7142857, 2.8857143, 3.0571429, 3.2285714, 3.4]),
		&"vital_resonance": PackedFloat32Array([4.4]),
		&"homing_core": PackedFloat32Array([5.5, 5.5, 6.0, 6.0, 6.5, 6.5, 7.0, 7.5]),
		&"infinite_homing": PackedFloat32Array([8.0]),
		&"directional_needle": PackedFloat32Array([6.0, 6.0, 6.5, 6.5, 7.0, 7.0, 7.5, 8.0]),
		&"infinite_needles": PackedFloat32Array([8.0]),
		&"arc_crystal": PackedFloat32Array([4.5, 4.5, 4.75, 4.75, 5.0, 5.0, 5.25, 5.25]),
		&"spiral_crystal": PackedFloat32Array([8.0]),
		&"returning_ring": PackedFloat32Array([5.5, 5.5, 6.0, 6.0, 6.5, 6.5, 7.0, 7.5]),
		&"critical_ring": PackedFloat32Array([8.0]),
		&"orbital_array": PackedFloat32Array([1.5, 1.6428571, 1.7857143, 1.9285714, 2.0714286, 2.2142857, 2.3571429, 2.5]),
		&"eternal_orbit": PackedFloat32Array([3.3]),
		&"mass_projectile": PackedFloat32Array([5.0, 5.0, 5.5, 5.5, 6.0, 6.0, 6.5, 6.75]),
		&"collapse_projectile": PackedFloat32Array([5.5]),
		&"zero_field": PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]),
		&"absorption_field": PackedFloat32Array([0.0]),
	}
	for weapon_id: StringName in expected_weapon_ranges:
		assertions.expect_equal(
			expected_weapon_ranges[weapon_id],
			catalog.weapon(weapon_id).range_by_level,
			"%s revision five range table" % weapon_id,
		)
	assertions.expect_equal(
		PackedFloat32Array([0.22, 0.22, 0.24, 0.24, 0.26, 0.26, 0.28, 0.3]),
		catalog.weapon(&"arc_crystal").projectile_radius_by_level,
		"base arc uses a compact physical projectile radius",
	)
	assertions.expect_equal(
		PackedFloat32Array([1.5, 1.7, 1.7, 1.9, 1.9, 2.1, 2.3, 2.5]),
		catalog.weapon(&"arc_crystal").effect_radius_by_level,
		"base arc stores its explosion radius explicitly",
	)
	assertions.expect_equal(
		PackedFloat32Array([0.55]),
		catalog.weapon(&"spiral_crystal").projectile_radius_by_level,
		"evolved spiral uses the approved physical radius",
	)
	var initial_state: RunState = RunStateFactory.create(1000, catalog)
	assertions.expect_equal(1, initial_state.weapons.size(), "a run starts with exactly one weapon")
	assertions.expect_true(initial_state.weapon(&"homing_core") != null, "starter runtime owns homing core")
	assertions.expect_true(initial_state.weapon(&"resonance_wave") == null, "resonance wave returns to normal offers")
	for spec: Dictionary in _fixed_content_specs():
		var base_id := StringName(spec[&"base_id"])
		var evolved_id := StringName(spec[&"evolved_id"])
		var passive_id := StringName(spec[&"passive_id"])
		var base: WeaponDefinition = catalog.weapon(base_id)
		var evolved: WeaponDefinition = catalog.weapon(evolved_id)
		var passive: PassiveDefinition = catalog.passive(passive_id)
		var evolution: EvolutionDefinition = catalog.evolution_for_weapon(base_id)
		assertions.expect_true(base != null, "%s base definition exists" % base_id)
		assertions.expect_true(evolved != null, "%s evolved definition exists" % evolved_id)
		assertions.expect_true(passive != null, "%s passive definition exists" % passive_id)
		assertions.expect_true(evolution != null, "%s evolution mapping exists" % base_id)
		if base == null or evolved == null or passive == null or evolution == null:
			continue
		assertions.expect_equal(String(spec[&"base_name"]), base.display_name, "%s Japanese name" % base_id)
		assertions.expect_float(float(spec[&"base_weight"]), base.selection_weight, "%s selection weight" % base_id)
		assertions.expect_equal(8, base.max_level, "%s max level" % base_id)
		assertions.expect_false(base.is_evolved, "%s remains a base weapon" % base_id)
		assertions.expect_equal(base_id, base.lineage_id, "%s base lineage" % base_id)
		assertions.expect_equal(passive_id, base.paired_passive_id, "%s paired passive" % base_id)
		assertions.expect_equal(int(spec[&"behavior"]), int(base.behavior), "%s behavior" % base_id)
		assertions.expect_equal(String(spec[&"evolved_name"]), evolved.display_name, "%s Japanese name" % evolved_id)
		assertions.expect_float(0.0, evolved.selection_weight, "%s never appears in level offers" % evolved_id)
		assertions.expect_equal(1, evolved.max_level, "%s max level" % evolved_id)
		assertions.expect_true(evolved.is_evolved, "%s is evolved" % evolved_id)
		assertions.expect_equal(base_id, evolved.lineage_id, "%s lineage" % evolved_id)
		assertions.expect_equal(passive_id, evolved.paired_passive_id, "%s paired passive" % evolved_id)
		assertions.expect_equal(int(spec[&"behavior"]), int(evolved.behavior), "%s behavior" % evolved_id)
		assertions.expect_equal(String(spec[&"passive_name"]), passive.display_name, "%s Japanese name" % passive_id)
		assertions.expect_float(float(spec[&"passive_weight"]), passive.selection_weight, "%s selection weight" % passive_id)
		assertions.expect_equal(5, passive.max_level, "%s max level" % passive_id)
		assertions.expect_equal(StringName(spec[&"stat_id"]), passive.stat_id, "%s effect stat" % passive_id)
		assertions.expect_float(float(spec[&"amount"]), passive.amount_per_level, "%s effect per level" % passive_id)
		assertions.expect_equal(base_id, passive.paired_weapon_id, "%s paired weapon" % passive_id)
		assertions.expect_equal(base_id, evolution.base_weapon_id, "%s evolution base" % base_id)
		assertions.expect_equal(passive_id, evolution.passive_id, "%s evolution passive" % base_id)
		assertions.expect_equal(evolved_id, evolution.evolved_weapon_id, "%s evolution target" % base_id)


func _test_close_range_outer_edges(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	var lineages: Array[StringName] = [
		&"resonance_wave",
		&"orbital_array",
		&"zero_field",
	]
	for lineage_id: StringName in lineages:
		var definition: WeaponDefinition = catalog.weapon(lineage_id)
		var evolution: EvolutionDefinition = catalog.evolution_for_weapon(lineage_id)
		var evolved: WeaponDefinition = catalog.weapon(evolution.evolved_weapon_id)
		var level_one_edge: float = _effective_outer_edge(definition, 1)
		var level_eight_edge: float = _effective_outer_edge(definition, 8)
		var evolved_edge: float = _effective_outer_edge(evolved, 1)
		assertions.expect_true(
			level_one_edge >= 1.8 and level_one_edge <= 2.4,
			"%s Lv1 outer edge is 1.8..2.4m" % lineage_id,
		)
		assertions.expect_true(
			level_eight_edge >= 3.2 and level_eight_edge <= 3.8,
			"%s Lv8 outer edge is 3.2..3.8m" % lineage_id,
		)
		assertions.expect_true(
			evolved_edge >= 4.2 and evolved_edge <= 4.8,
			"%s evolved outer edge is 4.2..4.8m" % lineage_id,
		)
		var previous_edge: float = level_one_edge
		for level: int in range(2, 9):
			var actual_edge: float = _effective_outer_edge(definition, level)
			var expected_edge: float = lerpf(
				level_one_edge,
				level_eight_edge,
				float(level - 1) / 7.0,
			)
			assertions.expect_true(
				actual_edge > previous_edge,
				"%s effective edge grows at level %d" % [lineage_id, level],
			)
			assertions.expect_float(
				expected_edge,
				actual_edge,
				"%s effective edge linearly interpolates at level %d" % [lineage_id, level],
			)
			previous_edge = actual_edge


func _effective_outer_edge(definition: WeaponDefinition, level: int) -> float:
	match definition.behavior:
		GameTypes.WeaponBehavior.MELEE_WAVE:
			return definition.range_at(level)
		GameTypes.WeaponBehavior.ORBITAL:
			return definition.range_at(level) + definition.effect_radius_at(level)
		GameTypes.WeaponBehavior.AURA:
			return definition.effect_radius_at(level)
		_:
			return (
				definition.range_at(level)
				+ maxf(
					definition.projectile_radius_at(level),
					definition.effect_radius_at(level),
				)
			)


func _test_xp(assertions: Variant) -> void:
	assertions.expect_equal(5, ProgressionService.xp_required_for_level(1), "level one XP")
	assertions.expect_equal(185, ProgressionService.xp_required_for_level(19), "level nineteen XP")
	assertions.expect_equal(795, ProgressionService.xp_required_for_level(20), "level twenty compensated XP")
	assertions.expect_equal(442, ProgressionService.xp_required_for_level(39), "level thirty-nine XP")
	assertions.expect_equal(2855, ProgressionService.xp_required_for_level(40), "level forty compensated XP")
	assertions.expect_equal(471, ProgressionService.xp_required_for_level(41), "level forty-one XP")
	var cumulative: int = 0
	for level: int in range(1, 65):
		cumulative += ProgressionService.xp_required_for_level(level)
	assertions.expect_equal(27350, cumulative, "level 65 cumulative XP")
	assertions.expect_float(2.0, ProgressionService.xp_growth_multiplier(20), "level twenty growth compensation")
	assertions.expect_float(2.0, ProgressionService.xp_growth_multiplier(40), "level forty growth compensation")
	var catalog: DefinitionCatalog = _catalog(assertions)
	var manifest: SurvivalContentManifest = catalog.manifest()
	var original_yield_percent: int = manifest.xp_yield_percent
	manifest.xp_yield_percent = 100
	var state: RunState = RunStateFactory.create(1001, catalog)
	var queued: int = ProgressionService.add_xp(state, 20, catalog)
	manifest.xp_yield_percent = original_yield_percent
	assertions.expect_equal(2, queued, "one pickup may queue multiple levels")
	assertions.expect_equal(3, state.level, "queued levels advance player level")
	assertions.expect_equal(0, state.xp, "threshold XP consumed exactly")


func _test_capacity_level_and_growth(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	var manifest: SurvivalContentManifest = catalog.manifest()
	var original_yield_percent: int = manifest.xp_yield_percent
	manifest.xp_yield_percent = 100
	var state: RunState = RunStateFactory.create(1101, catalog)
	assertions.expect_equal(64, ProgressionService.remaining_upgrade_capacity(state, catalog), "starter build has exactly 64 selections")
	var queued: int = ProgressionService.add_xp(state, 27350, catalog)
	assertions.expect_equal(64, queued, "cumulative XP queues every available selection")
	assertions.expect_equal(64, state.pending_level_ups, "all 64 selections remain pending")
	assertions.expect_equal(65, state.level, "64 selections advance initial level one to final level 65")
	assertions.expect_equal(0, state.xp, "approved cumulative XP is exact")
	var level_twenty: RunState = RunStateFactory.create(1102, catalog)
	level_twenty.level = 20
	var queued_at_twenty: int = ProgressionService.add_xp(level_twenty, 10, catalog)
	assertions.expect_equal(0, queued_at_twenty, "small level 20 pickup does not cross threshold")
	assertions.expect_equal(20, level_twenty.xp, "level 20 Growth doubles XP actually added")
	var level_forty: RunState = RunStateFactory.create(1103, catalog)
	level_forty.level = 40
	var queued_at_forty: int = ProgressionService.add_xp(level_forty, 10, catalog)
	assertions.expect_equal(0, queued_at_forty, "small level 40 pickup does not cross threshold")
	assertions.expect_equal(20, level_forty.xp, "level 40 Growth doubles XP actually added")
	var normal_level: RunState = RunStateFactory.create(1104, catalog)
	normal_level.level = 21
	var queued_at_normal_level: int = ProgressionService.add_xp(normal_level, 10, catalog)
	manifest.xp_yield_percent = original_yield_percent
	assertions.expect_equal(0, queued_at_normal_level, "small normal-level pickup does not cross threshold")
	assertions.expect_equal(10, normal_level.xp, "Growth is not applied outside levels 20 and 40")


func _test_growth_boundaries(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	var manifest: SurvivalContentManifest = catalog.manifest()
	var original_yield_percent: int = manifest.xp_yield_percent
	manifest.xp_yield_percent = 100
	var into_twenty: RunState = RunStateFactory.create(1201, catalog)
	into_twenty.level = 19
	into_twenty.xp = 180
	var into_twenty_queued: int = ProgressionService.add_xp(into_twenty, 10, catalog)
	assertions.expect_equal(1, into_twenty_queued, "one pickup crosses level 19 into 20")
	assertions.expect_equal(20, into_twenty.level, "level 19 boundary reaches level 20")
	assertions.expect_equal(10, into_twenty.xp, "only the pickup remainder inside level 20 receives Growth")
	var out_of_twenty: RunState = RunStateFactory.create(1202, catalog)
	out_of_twenty.level = 20
	out_of_twenty.xp = 790
	var out_of_twenty_queued: int = ProgressionService.add_xp(out_of_twenty, 10, catalog)
	assertions.expect_equal(1, out_of_twenty_queued, "one pickup crosses level 20 into 21")
	assertions.expect_equal(21, out_of_twenty.level, "level 20 boundary reaches level 21")
	assertions.expect_equal(8, out_of_twenty.xp, "Growth stops for the pickup remainder after level 20")
	var into_forty: RunState = RunStateFactory.create(1203, catalog)
	into_forty.level = 39
	into_forty.xp = 437
	var into_forty_queued: int = ProgressionService.add_xp(into_forty, 10, catalog)
	assertions.expect_equal(1, into_forty_queued, "one pickup crosses level 39 into 40")
	assertions.expect_equal(40, into_forty.level, "level 39 boundary reaches level 40")
	assertions.expect_equal(10, into_forty.xp, "only the pickup remainder inside level 40 receives Growth")
	var out_of_forty: RunState = RunStateFactory.create(1204, catalog)
	out_of_forty.level = 40
	out_of_forty.xp = 2850
	var out_of_forty_queued: int = ProgressionService.add_xp(out_of_forty, 10, catalog)
	assertions.expect_equal(1, out_of_forty_queued, "one pickup crosses level 40 into 41")
	assertions.expect_equal(41, out_of_forty.level, "level 40 boundary reaches level 41")
	assertions.expect_equal(8, out_of_forty.xp, "Growth stops for the pickup remainder after level 40")
	var both_boundaries: RunState = RunStateFactory.create(1205, catalog)
	both_boundaries.level = 19
	both_boundaries.xp = 180
	var both_queued: int = ProgressionService.add_xp(both_boundaries, 8005, catalog)
	assertions.expect_equal(22, both_queued, "one large pickup queues every level across both Growth boundaries")
	assertions.expect_equal(41, both_boundaries.level, "one large pickup crosses levels 20 and 40")
	assertions.expect_equal(1, both_boundaries.xp, "both odd Growth thresholds carry exactly one adjusted XP")
	var entering_twenty: RunState = RunStateFactory.create(1105, catalog)
	entering_twenty.level = 19
	entering_twenty.xp = 180
	var entering_twenty_queued: int = ProgressionService.add_xp(entering_twenty, 10, catalog)
	assertions.expect_equal(1, entering_twenty_queued, "one bulk collection crosses into level twenty")
	assertions.expect_equal(20, entering_twenty.level, "level nineteen threshold advances to twenty")
	assertions.expect_equal(10, entering_twenty.xp, "only XP processed after entering level twenty is doubled")
	var leaving_twenty: RunState = RunStateFactory.create(1106, catalog)
	leaving_twenty.level = 20
	leaving_twenty.xp = 790
	var leaving_twenty_queued: int = ProgressionService.add_xp(leaving_twenty, 10, catalog)
	manifest.xp_yield_percent = original_yield_percent
	assertions.expect_equal(1, leaving_twenty_queued, "Growth-assisted XP crosses the level twenty threshold")
	assertions.expect_equal(21, leaving_twenty.level, "Growth compensation ends after leaving level twenty")
	assertions.expect_equal(8, leaving_twenty.xp, "post-threshold remainder returns to normal Growth")


func _test_manifest_driven_xp(assertions: Variant) -> void:
	var canonical_catalog: DefinitionCatalog = _catalog(assertions)
	var custom_manifest: SurvivalContentManifest = canonical_catalog.manifest().duplicate(true) as SurvivalContentManifest
	assertions.expect_true(custom_manifest != null, "manifest duplicates for source-of-truth fixture")
	if custom_manifest == null:
		return
	custom_manifest.xp_early_coefficient = 11
	custom_manifest.xp_growth_compensation_multiplier = 3.0
	assertions.expect_equal(5, ProgressionService.xp_required_for_level(1), "static XP API retains approved compatibility")
	assertions.expect_equal(
		6,
		ProgressionService.xp_required_for_level_with_manifest(1, custom_manifest),
		"manifest-aware XP API uses configured coefficient",
	)
	assertions.expect_float(
		3.0,
		ProgressionService.xp_growth_multiplier_with_manifest(20, custom_manifest),
		"manifest-aware Growth API uses configured compensation",
	)
	var custom_catalog := DefinitionCatalog.new()
	assertions.expect_false(custom_catalog.validate_manifest(custom_manifest), "non-approved fixture is rejected for production")
	var early_state: RunState = RunStateFactory.create(1301, canonical_catalog)
	var growth_state: RunState = RunStateFactory.create(1302, canonical_catalog)
	growth_state.level = 20
	var canonical_manifest: SurvivalContentManifest = canonical_catalog.manifest()
	var original_early_coefficient: int = canonical_manifest.xp_early_coefficient
	var original_growth_multiplier: float = canonical_manifest.xp_growth_compensation_multiplier
	var original_yield_percent: int = canonical_manifest.xp_yield_percent
	canonical_manifest.xp_early_coefficient = 11
	canonical_manifest.xp_growth_compensation_multiplier = 3.0
	canonical_manifest.xp_yield_percent = 100
	var early_queued: int = ProgressionService.add_xp(early_state, 5, canonical_catalog)
	assertions.expect_equal(0, early_queued, "add_xp reads the manifest XP coefficient")
	assertions.expect_equal(5, early_state.xp, "custom level-one threshold remains unmet")
	var growth_queued: int = ProgressionService.add_xp(growth_state, 10, canonical_catalog)
	canonical_manifest.xp_early_coefficient = original_early_coefficient
	canonical_manifest.xp_growth_compensation_multiplier = original_growth_multiplier
	canonical_manifest.xp_yield_percent = original_yield_percent
	assertions.expect_equal(0, growth_queued, "custom Growth fixture remains below level twenty threshold")
	assertions.expect_equal(30, growth_state.xp, "add_xp reads the manifest Growth multiplier")
	var pickup_manifest := SurvivalContentManifest.new()
	pickup_manifest.xp_pool_capacity = 2
	pickup_manifest.xp_pickup_attract_radius = 1.25
	pickup_manifest.xp_pickup_collect_radius = 0.1
	pickup_manifest.xp_pickup_speed = 1.0
	var pool := XpPickupPool.new()
	pool.configure(pickup_manifest)
	assertions.expect_equal(2, pool.capacity, "XP pool capacity comes from manifest")
	assertions.expect_equal(2, pool.slots.size(), "XP pool storage follows manifest capacity")
	assertions.expect_float(1.25, pool.attract_radius, "XP attraction radius comes from manifest")
	assertions.expect_float(0.1, pool.collect_radius, "XP collection radius comes from manifest")
	assertions.expect_float(1.0, pool.attract_speed, "XP attraction speed comes from manifest")
	pool.acquire(Vector2(1.0, 0.0), 1, 0, Vector2.ZERO)
	pool.acquire(Vector2(1.1, 0.0), 2, 0, Vector2.ZERO)
	pool.acquire(Vector2(1.2, 0.0), 3, 0, Vector2.ZERO)
	assertions.expect_equal(2, pool.active_count(), "configured XP capacity controls overflow")
	assertions.expect_equal(6, pool.total_value(), "configured overflow still preserves all XP")
	pool.clear()
	var moving_pickup: XpPickupState = pool.acquire(Vector2(1.0, 0.0), 1, 0, Vector2.ZERO)
	var collected_while_moving: int = pool.advance_and_collect(Vector2.ZERO, 0.5, 1)
	assertions.expect_equal(0, collected_while_moving, "pickup remains outside configured collect radius")
	assertions.expect_equal(Vector2(0.5, 0.0), moving_pickup.position, "pickup uses configured attraction radius and speed")
	pool.clear()
	pool.acquire(Vector2(0.05, 0.0), 7, 0, Vector2.ZERO)
	var collected_nearby: int = pool.advance_and_collect(Vector2.ZERO, 0.0, 1)
	assertions.expect_equal(7, collected_nearby, "pickup uses configured collection radius")


func _test_xp_yield_fraction_and_growth_order(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	var manifest: SurvivalContentManifest = catalog.manifest()
	var original_yield_percent: int = manifest.xp_yield_percent
	manifest.xp_yield_percent = 95
	var fractional_state: RunState = RunStateFactory.create(1351, catalog)
	fractional_state.level = 10
	for _pickup_index: int in range(20):
		ProgressionService.add_xp(fractional_state, 1, catalog)
	assertions.expect_equal(19, fractional_state.xp, "twenty one-XP pickups preserve a 95 percent total")
	assertions.expect_equal(0, fractional_state.xp_yield_remainder, "fractional XP carry closes exactly at a whole total")
	var first_fraction: RunState = RunStateFactory.create(1352, catalog)
	first_fraction.level = 10
	ProgressionService.add_xp(first_fraction, 1, catalog)
	assertions.expect_equal(0, first_fraction.xp, "sub-one scaled XP waits for a later pickup")
	assertions.expect_equal(95, first_fraction.xp_yield_remainder, "scaled XP fraction is stored in RunState")
	ProgressionService.add_xp(first_fraction, 1, catalog)
	assertions.expect_equal(1, first_fraction.xp, "the next pickup releases one carried XP")
	assertions.expect_equal(90, first_fraction.xp_yield_remainder, "unused hundredths continue carrying forward")
	var growth_state: RunState = RunStateFactory.create(1353, catalog)
	growth_state.level = 20
	ProgressionService.add_xp(growth_state, 10, catalog)
	assertions.expect_equal(18, growth_state.xp, "95 percent scaling occurs before level-20 Growth doubles XP")
	assertions.expect_equal(50, growth_state.xp_yield_remainder, "Growth does not multiply the scaling fraction")
	ProgressionService.add_xp(growth_state, 10, catalog)
	manifest.xp_yield_percent = original_yield_percent
	assertions.expect_equal(38, growth_state.xp, "carried scaling fraction resolves before the next Growth application")
	assertions.expect_equal(0, growth_state.xp_yield_remainder, "resolved Growth fixture leaves no XP fraction")


func _test_boss_enrage_validation(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	var canonical: SurvivalContentManifest = catalog.manifest()
	assertions.expect_float(0.5625, canonical.boss_hp_multiplier, "calibrated boss HP matches the twelve-run gate")
	assertions.expect_float(0.57, canonical.boss_damage_multiplier, "calibrated boss damage matches the twelve-run gate")
	assertions.expect_float(1.0, canonical.boss_action_rate_multiplier, "canonical boss action rate starts neutral")
	assertions.expect_float(
		0.55,
		canonical.normal_enemy_damage_scale,
		"canonical contact-only enemies use the common damage lever",
	)
	var normal_scale_lower: SurvivalContentManifest = canonical.duplicate(true) as SurvivalContentManifest
	normal_scale_lower.normal_enemy_damage_scale = 0.25
	assertions.expect_true(
		DefinitionCatalog.new().validate_manifest(normal_scale_lower),
		"validator accepts the authorized normal-enemy damage lower bound",
	)
	var normal_scale_off_step: SurvivalContentManifest = canonical.duplicate(true) as SurvivalContentManifest
	normal_scale_off_step.normal_enemy_damage_scale = 0.57
	assertions.expect_false(
		DefinitionCatalog.new().validate_manifest(normal_scale_off_step),
		"validator rejects normal-enemy damage outside five-percent steps",
	)
	var lower_bound: SurvivalContentManifest = canonical.duplicate(true) as SurvivalContentManifest
	lower_bound.boss_hp_multiplier = SurvivalContentManifest.DEFAULT_BOSS_HP_MULTIPLIER * 0.25
	lower_bound.boss_damage_multiplier = SurvivalContentManifest.DEFAULT_BOSS_DAMAGE_MULTIPLIER * 0.25
	lower_bound.boss_action_rate_multiplier = SurvivalContentManifest.DEFAULT_BOSS_ACTION_RATE_MULTIPLIER * 0.25
	var lower_bound_catalog := DefinitionCatalog.new()
	assertions.expect_true(lower_bound_catalog.validate_manifest(lower_bound), "validator accepts the extended boss -75 percent bound")
	var hp_lower_bound: SurvivalContentManifest = canonical.duplicate(true) as SurvivalContentManifest
	hp_lower_bound.boss_hp_multiplier = (
		SurvivalContentManifest.DEFAULT_BOSS_HP_MULTIPLIER * 0.15
	)
	assertions.expect_true(
		DefinitionCatalog.new().validate_manifest(hp_lower_bound),
		"validator accepts the extended boss-HP -85 percent bound",
	)
	var upper_bound: SurvivalContentManifest = canonical.duplicate(true) as SurvivalContentManifest
	upper_bound.boss_hp_multiplier = SurvivalContentManifest.DEFAULT_BOSS_HP_MULTIPLIER * 1.10
	upper_bound.boss_damage_multiplier = SurvivalContentManifest.DEFAULT_BOSS_DAMAGE_MULTIPLIER * 1.10
	upper_bound.boss_action_rate_multiplier = SurvivalContentManifest.DEFAULT_BOSS_ACTION_RATE_MULTIPLIER * 1.10
	var upper_bound_catalog := DefinitionCatalog.new()
	assertions.expect_true(upper_bound_catalog.validate_manifest(upper_bound), "validator accepts the authorized boss +10 percent bound")
	var off_step: SurvivalContentManifest = canonical.duplicate(true) as SurvivalContentManifest
	off_step.boss_hp_multiplier = SurvivalContentManifest.DEFAULT_BOSS_HP_MULTIPLIER * 0.97
	var off_step_catalog := DefinitionCatalog.new()
	assertions.expect_false(off_step_catalog.validate_manifest(off_step), "validator rejects boss tuning outside five-percent steps")
	assertions.expect_true(off_step_catalog.error_text.contains("boss HP multiplier"), "boss step rejection names the changed multiplier")
	var below_bound: SurvivalContentManifest = canonical.duplicate(true) as SurvivalContentManifest
	below_bound.boss_hp_multiplier = SurvivalContentManifest.DEFAULT_BOSS_HP_MULTIPLIER * 0.10
	assertions.expect_false(
		DefinitionCatalog.new().validate_manifest(below_bound),
		"validator rejects a boss multiplier below the authorized lower bound",
	)
	var above_bound: SurvivalContentManifest = canonical.duplicate(true) as SurvivalContentManifest
	above_bound.boss_damage_multiplier = SurvivalContentManifest.DEFAULT_BOSS_DAMAGE_MULTIPLIER * 1.15
	assertions.expect_false(
		DefinitionCatalog.new().validate_manifest(above_bound),
		"validator rejects a boss multiplier above the authorized upper bound",
	)
	var non_finite: SurvivalContentManifest = canonical.duplicate(true) as SurvivalContentManifest
	non_finite.boss_action_rate_multiplier = NAN
	assertions.expect_false(
		DefinitionCatalog.new().validate_manifest(non_finite),
		"validator rejects a non-finite boss multiplier",
	)
	var attack_drift: SurvivalContentManifest = canonical.duplicate(true) as SurvivalContentManifest
	attack_drift.boss_attack_bonus_per_stack = 0.11
	var attack_catalog := DefinitionCatalog.new()
	assertions.expect_false(attack_catalog.validate_manifest(attack_drift), "validator rejects boss attack drift")
	assertions.expect_true(attack_catalog.error_text.contains("+10%"), "boss attack rejection is specific")
	var interval_drift: SurvivalContentManifest = canonical.duplicate(true) as SurvivalContentManifest
	interval_drift.boss_interval_reduction_per_stack = 0.11
	var interval_catalog := DefinitionCatalog.new()
	assertions.expect_false(interval_catalog.validate_manifest(interval_drift), "validator rejects boss interval drift")
	assertions.expect_true(interval_catalog.error_text.contains("-10%"), "boss interval rejection is specific")
	var cap_drift: SurvivalContentManifest = canonical.duplicate(true) as SurvivalContentManifest
	cap_drift.boss_enrage_max_stacks = 11
	var cap_catalog := DefinitionCatalog.new()
	assertions.expect_false(cap_catalog.validate_manifest(cap_drift), "validator rejects boss enrage cap drift")
	assertions.expect_true(cap_catalog.error_text.contains("10 stacks"), "boss cap rejection is specific")


func _test_nonboss_ranged_validation(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	var canonical: SurvivalContentManifest = catalog.manifest()
	var shooter_index: int = _enemy_index_for_type(
		canonical,
		GameTypes.EnemyType.SHOOTER,
	)
	var elite_index: int = _enemy_index_for_type(
		canonical,
		GameTypes.EnemyType.ELITE,
	)
	assertions.expect_true(shooter_index >= 0 and elite_index >= 0, "contact-only validation fixtures exist")
	if shooter_index < 0 or elite_index < 0:
		return
	var negative_shooter: EnemyDefinition = (
		canonical.enemies[shooter_index].duplicate(true) as EnemyDefinition
	)
	negative_shooter.projectile_damage = -1.0
	var negative_catalog := DefinitionCatalog.new()
	assertions.expect_false(
		negative_catalog.validate_manifest(
			_with_enemy(canonical, shooter_index, negative_shooter)
		),
		"validator rejects negative ranged drift on a normal enemy",
	)
	assertions.expect_true(
		negative_catalog.error_text.contains("contact-only"),
		"negative ranged drift reports the contact-only contract",
	)
	var non_finite_elite: EnemyDefinition = (
		canonical.enemies[elite_index].duplicate(true) as EnemyDefinition
	)
	non_finite_elite.preferred_distance_max = NAN
	var non_finite_catalog := DefinitionCatalog.new()
	assertions.expect_false(
		non_finite_catalog.validate_manifest(
			_with_enemy(canonical, elite_index, non_finite_elite)
		),
		"validator rejects non-finite ranged drift on an elite",
	)
	assertions.expect_true(
		non_finite_catalog.error_text.contains("contact-only"),
		"non-finite ranged drift reports the contact-only contract",
	)


func _test_segment_tuning_contract(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	var canonical: SurvivalContentManifest = catalog.manifest()
	var relaxed: SurvivalContentManifest = canonical.duplicate(true) as SurvivalContentManifest
	var relaxed_segments: Array[EnemySegmentDefinition] = []
	relaxed_segments.assign(canonical.segments)
	var relaxed_first: EnemySegmentDefinition = canonical.segments[0].duplicate(true) as EnemySegmentDefinition
	relaxed_first.damage_multiplier = DefinitionCatalog.BASELINE_DAMAGE_MULTIPLIERS[0] * 0.15
	relaxed_first.hp_multiplier = DefinitionCatalog.BASELINE_HP_MULTIPLIERS[0] * 0.10
	relaxed_first.target_active = roundi(float(DefinitionCatalog.EXPECTED_TARGETS[0]) * 0.10)
	relaxed_segments[0] = relaxed_first
	relaxed.segments = relaxed_segments
	var relaxed_catalog := DefinitionCatalog.new()
	assertions.expect_true(relaxed_catalog.validate_manifest(relaxed), "road pressure accepts the extended -90-percent bound")

	var late_boost: SurvivalContentManifest = canonical.duplicate(true) as SurvivalContentManifest
	var boosted_segments: Array[EnemySegmentDefinition] = []
	boosted_segments.assign(canonical.segments)
	var boosted_seventh: EnemySegmentDefinition = canonical.segments[6].duplicate(true) as EnemySegmentDefinition
	boosted_seventh.damage_multiplier = DefinitionCatalog.BASELINE_DAMAGE_MULTIPLIERS[6] * 1.10
	boosted_seventh.hp_multiplier = DefinitionCatalog.BASELINE_HP_MULTIPLIERS[6] * 1.05
	boosted_seventh.target_active = roundi(float(DefinitionCatalog.EXPECTED_TARGETS[6]) * 1.10)
	boosted_segments[6] = boosted_seventh
	late_boost.segments = boosted_segments
	var late_boost_catalog := DefinitionCatalog.new()
	assertions.expect_true(late_boost_catalog.validate_manifest(late_boost), "segments seven through ten accept authorized strengthening")

	var early_boost: SurvivalContentManifest = canonical.duplicate(true) as SurvivalContentManifest
	var early_segments: Array[EnemySegmentDefinition] = []
	early_segments.assign(canonical.segments)
	var boosted_first: EnemySegmentDefinition = canonical.segments[0].duplicate(true) as EnemySegmentDefinition
	boosted_first.damage_multiplier = DefinitionCatalog.BASELINE_DAMAGE_MULTIPLIERS[0] * 1.05
	early_segments[0] = boosted_first
	early_boost.segments = early_segments
	var early_boost_catalog := DefinitionCatalog.new()
	assertions.expect_false(early_boost_catalog.validate_manifest(early_boost), "segments one through six reject strengthening")

	var off_step: SurvivalContentManifest = canonical.duplicate(true) as SurvivalContentManifest
	var off_step_segments: Array[EnemySegmentDefinition] = []
	off_step_segments.assign(canonical.segments)
	var off_step_seventh: EnemySegmentDefinition = canonical.segments[6].duplicate(true) as EnemySegmentDefinition
	off_step_seventh.hp_multiplier = DefinitionCatalog.BASELINE_HP_MULTIPLIERS[6] * 0.97
	off_step_segments[6] = off_step_seventh
	off_step.segments = off_step_segments
	var off_step_catalog := DefinitionCatalog.new()
	assertions.expect_false(off_step_catalog.validate_manifest(off_step), "segment pressure rejects non-five-percent drift")

	var below_target_segment: EnemySegmentDefinition = canonical.segments[0].duplicate(true) as EnemySegmentDefinition
	below_target_segment.target_active = 1
	assertions.expect_false(
		DefinitionCatalog.new().validate_manifest(_with_segment(canonical, 0, below_target_segment)),
		"segment target rejects values below the ten-percent lower bound",
	)
	var above_target_segment: EnemySegmentDefinition = canonical.segments[0].duplicate(true) as EnemySegmentDefinition
	above_target_segment.target_active = 42
	assertions.expect_false(
		DefinitionCatalog.new().validate_manifest(_with_segment(canonical, 0, above_target_segment)),
		"early segment target rejects values above baseline",
	)
	var below_hp_segment: EnemySegmentDefinition = canonical.segments[0].duplicate(true) as EnemySegmentDefinition
	below_hp_segment.hp_multiplier = DefinitionCatalog.BASELINE_HP_MULTIPLIERS[0] * 0.05
	assertions.expect_false(
		DefinitionCatalog.new().validate_manifest(_with_segment(canonical, 0, below_hp_segment)),
		"segment HP rejects values below the ten-percent lower bound",
	)
	var below_damage_segment: EnemySegmentDefinition = canonical.segments[0].duplicate(true) as EnemySegmentDefinition
	below_damage_segment.damage_multiplier = DefinitionCatalog.BASELINE_DAMAGE_MULTIPLIERS[0] * 0.10
	assertions.expect_false(
		DefinitionCatalog.new().validate_manifest(_with_segment(canonical, 0, below_damage_segment)),
		"segment damage rejects values below the fifteen-percent lower bound",
	)
	var non_finite_segment: EnemySegmentDefinition = canonical.segments[0].duplicate(true) as EnemySegmentDefinition
	non_finite_segment.hp_multiplier = INF
	assertions.expect_false(
		DefinitionCatalog.new().validate_manifest(_with_segment(canonical, 0, non_finite_segment)),
		"segment tuning rejects a non-finite multiplier",
	)


func _test_offer(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	var first: RunState = RunStateFactory.create(2222, catalog)
	var second: RunState = RunStateFactory.create(2222, catalog)
	first.pending_level_ups = 1
	second.pending_level_ups = 1
	var first_offer: LevelOffer = ProgressionService.create_offer(first, catalog)
	var rebuilt_offer: LevelOffer = ProgressionService.create_offer(first, catalog)
	var second_offer: LevelOffer = ProgressionService.create_offer(second, catalog)
	assertions.expect_true(first_offer == rebuilt_offer, "UI reconstruction cannot reroll an active offer")
	assertions.expect_equal(3, first_offer.options.size(), "three level choices")
	var first_ids := PackedStringArray()
	var second_ids := PackedStringArray()
	var seen: Dictionary[StringName, bool] = {}
	for option: UpgradeOption in first_offer.options:
		first_ids.append(String(option.content_id))
		assertions.expect_false(seen.has(option.content_id), "offer choices are unique")
		seen[option.content_id] = true
		assertions.expect_true(not option.pairing_hint.is_empty(), "evolution pairing visible from start")
	for option: UpgradeOption in second_offer.options:
		second_ids.append(String(option.content_id))
	assertions.expect_equal(first_ids, second_ids, "same seed gives the same offer")
	var result: Dictionary = ProgressionService.apply_offer(
		first,
		catalog,
		first_offer.serial,
		0,
	)
	assertions.expect_true(bool(result[&"success"]), "first offer application succeeds")
	assertions.expect_equal(0, first.pending_level_ups, "offer consumes one queued level")
	var rejected: Dictionary = ProgressionService.apply_offer(
		first,
		catalog,
		first_offer.serial,
		0,
	)
	assertions.expect_false(bool(rejected[&"success"]), "offer serial cannot apply twice")
	assertions.expect_equal(&"already_applied", rejected[&"reason"], "double apply has stable reason")


func _test_queued_offer_levels_and_owned_probability(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	var queued_state: RunState = RunStateFactory.create(2251, catalog)
	queued_state.level = 4
	queued_state.pending_level_ups = 3
	var expected_offer_levels := PackedInt32Array([2, 3, 4])
	for expected_offer_level: int in expected_offer_levels:
		var offer: LevelOffer = ProgressionService.create_offer(queued_state, catalog)
		assertions.expect_true(offer != null, "queued level creates an offer")
		if offer == null:
			return
		assertions.expect_equal(expected_offer_level, offer.offer_level, "queued offer keeps its earned level and parity")
		assertions.expect_equal(3, offer.options.size(), "every queued offer still has three choices")
		var seen_tokens: Dictionary[StringName, bool] = {}
		for option: UpgradeOption in offer.options:
			var token := StringName("%d|%s" % [int(option.kind), option.content_id])
			assertions.expect_false(seen_tokens.has(token), "queued offer never duplicates a weapon or passive")
			seen_tokens[token] = true
		var applied: Dictionary = ProgressionService.apply_offer(queued_state, catalog, offer.serial, 0)
		assertions.expect_true(bool(applied[&"success"]), "queued offer applies once")
	var no_luck_state: RunState = RunStateFactory.create(2252, catalog)
	assertions.expect_float(
		0.3,
		ProgressionService._owned_offer_probability(no_luck_state, catalog, 3),
		"odd-level owned probability is 1 + 0.3 - 1 / totalLuck",
	)
	assertions.expect_float(
		0.6,
		ProgressionService._owned_offer_probability(no_luck_state, catalog, 4),
		"even-level owned probability is 1 + 0.6 - 1 / totalLuck",
	)
	var luck_state: RunState = RunStateFactory.create(2253, catalog)
	var luck_result: Dictionary = ProgressionService.apply_direct_upgrade(
		luck_state,
		catalog,
		GameTypes.UpgradeKind.PASSIVE,
		&"probability_core",
	)
	assertions.expect_true(bool(luck_result[&"success"]), "Luck fixture acquires probability core")
	var total_luck: float = 1.0 + 10.0 / 100.0
	assertions.expect_float(
		clampf(1.0 + 0.3 - 1.0 / total_luck, 0.0, 1.0),
		ProgressionService._owned_offer_probability(luck_state, catalog, 3),
		"Luck increases the odd-level owned attempt probability",
	)
	assertions.expect_float(
		clampf(1.0 + 0.6 - 1.0 / total_luck, 0.0, 1.0),
		ProgressionService._owned_offer_probability(luck_state, catalog, 4),
		"Luck increases the even-level owned attempt probability",
	)


func _test_owned_offer_uses_uniform_owned_selection(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	var selected_seed: int = -1
	var expected_owned_token: StringName = &""
	for run_seed: int in range(1, 4097):
		var scan_state: RunState = _two_owned_offer_state(run_seed, catalog)
		var owned: Array[UpgradeOption] = _owned_eligible_options(scan_state, catalog)
		if owned.size() != 2:
			continue
		var scan_rng: RandomNumberGenerator = _clone_rng(scan_state.rng_streams.upgrade_rng)
		var probability: float = ProgressionService._owned_offer_probability(
			scan_state,
			catalog,
			2,
		)
		if scan_rng.randf() >= probability:
			continue
		var uniform_rng: RandomNumberGenerator = _clone_rng(scan_rng)
		var weighted_rng: RandomNumberGenerator = _clone_rng(scan_rng)
		var selected_index: int = uniform_rng.randi_range(0, owned.size() - 1)
		var uniform_token: StringName = _upgrade_option_token(owned[selected_index])
		var owned_tokens: Array[StringName] = []
		var owned_weights := PackedFloat64Array()
		for option: UpgradeOption in owned:
			owned_tokens.append(_upgrade_option_token(option))
			owned_weights.append(option.weight)
		var weighted_token: StringName = WeightedSelector.select(
			weighted_rng,
			owned_tokens,
			owned_weights,
		)
		if uniform_token == weighted_token or uniform_rng.randf() < probability:
			continue
		selected_seed = run_seed
		expected_owned_token = uniform_token
		break
	assertions.expect_true(selected_seed > 0, "bounded seed scan finds a uniform owned-selection fixture")
	if selected_seed <= 0:
		return
	var state: RunState = _two_owned_offer_state(selected_seed, catalog)
	var expected_rng: RandomNumberGenerator = _clone_rng(state.rng_streams.upgrade_rng)
	var available: Array[UpgradeOption] = ProgressionService._eligible_options(state, catalog)
	var expected_owned: Array[UpgradeOption] = _owned_options_from(available)
	var expected_probability: float = ProgressionService._owned_offer_probability(
		state,
		catalog,
		2,
	)
	assertions.expect_float(0.6, expected_probability, "even level retains canonical owned probability")
	assertions.expect_true(expected_rng.randf() < expected_probability, "first owned attempt succeeds")
	var weighted_alternative_rng: RandomNumberGenerator = _clone_rng(expected_rng)
	var expected_owned_tokens: Array[StringName] = []
	var expected_owned_weights := PackedFloat64Array()
	for option: UpgradeOption in expected_owned:
		expected_owned_tokens.append(_upgrade_option_token(option))
		expected_owned_weights.append(option.weight)
	var weighted_alternative_token: StringName = WeightedSelector.select(
		weighted_alternative_rng,
		expected_owned_tokens,
		expected_owned_weights,
	)
	var expected_index: int = expected_rng.randi_range(0, expected_owned.size() - 1)
	var selected_token: StringName = _upgrade_option_token(expected_owned[expected_index])
	assertions.expect_equal(expected_owned_token, selected_token, "bounded scan and cloned uniform draw agree")
	assertions.expect_not_equal(
		weighted_alternative_token,
		selected_token,
		"the same RNG state would select a different owned option under weighted choice",
	)
	_remove_upgrade_option(available, selected_token)
	assertions.expect_true(expected_rng.randf() >= expected_probability, "second owned attempt fails for this fixture")
	var expected_tokens: Array[StringName] = [selected_token]
	expected_tokens.append_array(_draw_weighted_tokens(expected_rng, available, 2))
	var offer: LevelOffer = ProgressionService.create_offer(state, catalog)
	assertions.expect_true(offer != null, "multiple-owned fixture creates an offer")
	if offer == null:
		return
	assertions.expect_equal(
		expected_tokens,
		_offer_option_tokens(offer),
		"owned selection follows the cloned uniform draw before weighted fill",
	)
	assertions.expect_equal(
		expected_rng.state,
		state.rng_streams.upgrade_rng.state,
		"uniform owned selection consumes the predicted RNG sequence",
	)


func _test_duplicate_owned_attempt_falls_back_without_reroll(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	var selected_seed: int = -1
	for run_seed: int in range(1, 4097):
		var scan_state: RunState = _single_owned_offer_state(run_seed, catalog)
		var scan_rng: RandomNumberGenerator = _clone_rng(scan_state.rng_streams.upgrade_rng)
		var scan_probability: float = ProgressionService._owned_offer_probability(
			scan_state,
			catalog,
			2,
		)
		if scan_rng.randf() >= scan_probability:
			continue
		scan_rng.randi_range(0, 0)
		if scan_rng.randf() >= scan_probability:
			continue
		scan_rng.randi_range(0, 0)
		selected_seed = run_seed
		break
	assertions.expect_true(selected_seed > 0, "bounded seed scan finds two successful owned attempts")
	if selected_seed <= 0:
		return
	var state: RunState = _single_owned_offer_state(selected_seed, catalog)
	var expected_rng: RandomNumberGenerator = _clone_rng(state.rng_streams.upgrade_rng)
	var available: Array[UpgradeOption] = ProgressionService._eligible_options(state, catalog)
	var owned: Array[UpgradeOption] = _owned_options_from(available)
	assertions.expect_equal(1, owned.size(), "duplicate fixture has exactly one unfinished owned choice")
	var probability: float = ProgressionService._owned_offer_probability(state, catalog, 2)
	assertions.expect_true(expected_rng.randf() < probability, "first duplicate-fixture attempt succeeds")
	expected_rng.randi_range(0, 0)
	var owned_token: StringName = _upgrade_option_token(owned[0])
	_remove_upgrade_option(available, owned_token)
	assertions.expect_true(expected_rng.randf() < probability, "second duplicate-fixture attempt also succeeds")
	expected_rng.randi_range(0, 0)
	var expected_tokens: Array[StringName] = [owned_token]
	expected_tokens.append_array(_draw_weighted_tokens(expected_rng, available, 2))
	var offer: LevelOffer = ProgressionService.create_offer(state, catalog)
	assertions.expect_true(offer != null, "duplicate-owned fixture creates an offer")
	if offer == null:
		return
	var actual_tokens: Array[StringName] = _offer_option_tokens(offer)
	assertions.expect_equal(expected_tokens, actual_tokens, "duplicate second attempt falls through to normal weighted fill")
	assertions.expect_equal(1, actual_tokens.count(owned_token), "the owned option appears only once")
	assertions.expect_equal(0, offer.options[1].current_level, "first fallback option is unowned")
	assertions.expect_equal(0, offer.options[2].current_level, "second fallback option is unowned")
	assertions.expect_equal(
		expected_rng.state,
		state.rng_streams.upgrade_rng.state,
		"duplicate success consumes no hidden retry beyond the two configured attempts",
	)


func _test_full_inventory_skips_owned_offer_attempts(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	var state: RunState = RunStateFactory.create(2299, catalog)
	var extra_weapon_ids: Array[StringName] = [
		&"arc_crystal",
		&"directional_needle",
		&"resonance_wave",
		&"returning_ring",
	]
	for weapon_id: StringName in extra_weapon_ids:
		var weapon_result: Dictionary = ProgressionService.apply_direct_upgrade(
			state,
			catalog,
			GameTypes.UpgradeKind.WEAPON,
			weapon_id,
		)
		assertions.expect_true(bool(weapon_result[&"success"]), "full-slot fixture adds weapon %s" % weapon_id)
	var passive_ids: Array[StringName] = [
		&"cycle_crystal",
		&"life_lattice",
		&"probability_core",
		&"scale_lens",
		&"speed_gate",
	]
	for passive_id: StringName in passive_ids:
		var passive_result: Dictionary = ProgressionService.apply_direct_upgrade(
			state,
			catalog,
			GameTypes.UpgradeKind.PASSIVE,
			passive_id,
		)
		assertions.expect_true(bool(passive_result[&"success"]), "full-slot fixture adds passive %s" % passive_id)
	assertions.expect_equal(5, state.weapons.size(), "weapon inventory is full")
	assertions.expect_equal(5, state.passives.size(), "passive inventory is full")
	state.level = 2
	state.pending_level_ups = 1
	var available: Array[UpgradeOption] = ProgressionService._eligible_options(state, catalog)
	assertions.expect_equal(10, available.size(), "all ten owned entries remain unfinished and eligible")
	var expected_rng: RandomNumberGenerator = _clone_rng(state.rng_streams.upgrade_rng)
	var expected_tokens: Array[StringName] = _draw_weighted_tokens(expected_rng, available, 3)
	var offer: LevelOffer = ProgressionService.create_offer(state, catalog)
	assertions.expect_true(offer != null, "full-inventory fixture creates an offer")
	if offer == null:
		return
	assertions.expect_equal(
		expected_tokens,
		_offer_option_tokens(offer),
		"full inventory starts directly with three normal weighted draws",
	)
	assertions.expect_equal(
		expected_rng.state,
		state.rng_streams.upgrade_rng.state,
		"full inventory consumes no owned-attempt RNG draws",
	)


func _test_new_weapon_atomic(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	var state: RunState = RunStateFactory.create(3333, catalog)
	var result: Dictionary = ProgressionService.apply_direct_upgrade(
		state,
		catalog,
		GameTypes.UpgradeKind.WEAPON,
		&"resonance_wave",
	)
	assertions.expect_true(bool(result[&"success"]), "new weapon acquisition succeeds")
	assertions.expect_equal(2, state.weapons.size(), "new weapon appended exactly once")
	assertions.expect_equal(0, state.passives.size(), "weapon acquisition never falls into passive mutation")
	assertions.expect_equal(1, state.weapon(&"resonance_wave").level, "new weapon starts at level one")
	assertions.expect_true(state.weapon(&"resonance_wave").ready_on_resume, "new weapon fires on resume")


func _test_slot_and_max_rejections(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	var state: RunState = RunStateFactory.create(3434, catalog)
	var added_weapon_ids: Array[StringName] = [
		&"resonance_wave",
		&"directional_needle",
		&"arc_crystal",
		&"returning_ring",
	]
	for weapon_id: StringName in added_weapon_ids:
		var acquisition: Dictionary = ProgressionService.apply_direct_upgrade(
			state,
			catalog,
			GameTypes.UpgradeKind.WEAPON,
			weapon_id,
		)
		assertions.expect_true(bool(acquisition[&"success"]), "%s acquisition succeeds before slot cap" % weapon_id)
	assertions.expect_equal(5, state.weapons.size(), "weapon slots stop at five owned weapons")
	var rejected_weapon: Dictionary = ProgressionService.apply_direct_upgrade(
		state,
		catalog,
		GameTypes.UpgradeKind.WEAPON,
		&"orbital_array",
	)
	assertions.expect_false(bool(rejected_weapon[&"success"]), "sixth weapon is rejected")
	assertions.expect_equal(&"weapon_slots_full", rejected_weapon[&"reason"], "weapon slot rejection reason is stable")
	assertions.expect_equal(5, state.weapons.size(), "rejected weapon does not mutate slots")
	var added_passive_ids: Array[StringName] = [
		&"life_lattice",
		&"cycle_crystal",
		&"speed_gate",
		&"scale_lens",
		&"probability_core",
	]
	for passive_id: StringName in added_passive_ids:
		var acquisition: Dictionary = ProgressionService.apply_direct_upgrade(
			state,
			catalog,
			GameTypes.UpgradeKind.PASSIVE,
			passive_id,
		)
		assertions.expect_true(bool(acquisition[&"success"]), "%s acquisition succeeds before slot cap" % passive_id)
	assertions.expect_equal(5, state.passives.size(), "passive slots stop at five owned passives")
	var rejected_passive: Dictionary = ProgressionService.apply_direct_upgrade(
		state,
		catalog,
		GameTypes.UpgradeKind.PASSIVE,
		&"duration_ring",
	)
	assertions.expect_false(bool(rejected_passive[&"success"]), "sixth passive is rejected")
	assertions.expect_equal(&"passive_slots_full", rejected_passive[&"reason"], "passive slot rejection reason is stable")
	assertions.expect_equal(5, state.passives.size(), "rejected passive does not mutate slots")
	var maxed_weapon: RunWeapon = state.weapon_for_lineage(&"homing_core")
	maxed_weapon.level = 8
	var rejected_weapon_level: Dictionary = ProgressionService.apply_direct_upgrade(
		state,
		catalog,
		GameTypes.UpgradeKind.WEAPON,
		&"homing_core",
	)
	assertions.expect_false(bool(rejected_weapon_level[&"success"]), "max-level weapon rejects another level")
	assertions.expect_equal(&"weapon_maxed", rejected_weapon_level[&"reason"], "weapon max rejection reason is stable")
	assertions.expect_equal(8, maxed_weapon.level, "rejected weapon level does not mutate runtime")
	var maxed_passive: RunPassive = state.passive(&"life_lattice")
	maxed_passive.level = 5
	var rejected_passive_level: Dictionary = ProgressionService.apply_direct_upgrade(
		state,
		catalog,
		GameTypes.UpgradeKind.PASSIVE,
		&"life_lattice",
	)
	assertions.expect_false(bool(rejected_passive_level[&"success"]), "max-level passive rejects another level")
	assertions.expect_equal(&"passive_maxed", rejected_passive_level[&"reason"], "passive max rejection reason is stable")
	assertions.expect_equal(5, maxed_passive.level, "rejected passive level does not mutate runtime")


func _test_chests(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	var early: RunState = RunStateFactory.create(4444, catalog)
	early.weapon(&"homing_core").level = 8
	ProgressionService.apply_direct_upgrade(early, catalog, GameTypes.UpgradeKind.PASSIVE, &"cycle_crystal")
	early.pending_chest_sources.append(0)
	var evolution: ChestOutcome = ChestRewardService.create_outcome(early, catalog)
	assertions.expect_equal(GameTypes.ChestOutcomeKind.EVOLUTION, evolution.kind, "eligible chest evolves")
	assertions.expect_equal(&"infinite_homing", evolution.content_id, "correct evolution result")
	assertions.expect_equal(0, evolution.source_elite_index, "outcome keeps its elite source")
	assertions.expect_equal(0, early.combat_tick, "evolution has no time gate")
	var evolution_result: Dictionary = ChestRewardService.apply_outcome(
		early,
		catalog,
		evolution.serial,
	)
	assertions.expect_true(bool(evolution_result[&"success"]), "evolution applies")
	assertions.expect_true(early.weapon_for_lineage(&"homing_core").evolved, "runtime becomes evolved")
	assertions.expect_equal(1, early.passive(&"cycle_crystal").level, "paired passive is not consumed")
	assertions.expect_equal(0, early.pending_chest_count(), "chest consumes one pending pickup")
	var healing: RunState = RunStateFactory.create(5555, catalog)
	healing.weapon(&"homing_core").level = 8
	healing.current_hp = 10.0
	healing.pending_chest_sources.append(1)
	var full_heal: ChestOutcome = ChestRewardService.create_outcome(healing, catalog)
	assertions.expect_equal(GameTypes.ChestOutcomeKind.FULL_HEAL, full_heal.kind, "no owned upgrade falls back to full heal")
	ChestRewardService.apply_outcome(healing, catalog, full_heal.serial)
	assertions.expect_float(healing.max_hp, healing.current_hp, "full-heal fallback restores HP")
	var capped: RunState = _five_evolution_ready_state(catalog)
	for _chest_index: int in range(4):
		capped.pending_chest_sources.append(_chest_index)
		var outcome: ChestOutcome = ChestRewardService.create_outcome(capped, catalog)
		assertions.expect_equal(GameTypes.ChestOutcomeKind.EVOLUTION, outcome.kind, "first four eligible chests evolve")
		ChestRewardService.apply_outcome(capped, catalog, outcome.serial)
	assertions.expect_equal(4, capped.evolution_count, "run evolution cap is four")
	capped.pending_chest_sources.append(4)
	var after_cap: ChestOutcome = ChestRewardService.create_outcome(capped, catalog)
	assertions.expect_not_equal(GameTypes.ChestOutcomeKind.EVOLUTION, after_cap.kind, "fifth chest cannot evolve")


func _test_chest_owned_upgrade_contract(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	var state: RunState = RunStateFactory.create(4545, catalog)
	var added_weapon: Dictionary = ProgressionService.apply_direct_upgrade(
		state,
		catalog,
		GameTypes.UpgradeKind.WEAPON,
		&"resonance_wave",
	)
	assertions.expect_true(bool(added_weapon[&"success"]), "second owned weapon prepares a real chest choice")
	state.current_hp = 40.0
	state.pending_chest_sources.append(2)
	var before_chest_rng: int = state.rng_streams.chest_rng.state
	var outcome: ChestOutcome = ChestRewardService.create_outcome(state, catalog)
	assertions.expect_equal(GameTypes.ChestOutcomeKind.UPGRADE, outcome.kind, "owned unfinished content receives a rank")
	assertions.expect_equal(GameTypes.UpgradeKind.WEAPON, outcome.upgrade_kind, "one of the owned weapons is selected")
	assertions.expect_true(state.weapon(outcome.content_id) != null, "upgrade targets owned content only")
	assertions.expect_equal(1, outcome.previous_level, "upgrade records previous level")
	assertions.expect_equal(2, outcome.new_level, "upgrade records exactly one new level")
	assertions.expect_not_equal(before_chest_rng, state.rng_streams.chest_rng.state, "first outcome creation consumes chest RNG")
	var stable_chest_rng: int = state.rng_streams.chest_rng.state
	var rebuilt: ChestOutcome = ChestRewardService.create_outcome(state, catalog)
	assertions.expect_true(outcome == rebuilt, "rebuilding chest UI returns the stable outcome")
	assertions.expect_equal(outcome.serial, rebuilt.serial, "stable outcome keeps its serial")
	assertions.expect_equal(stable_chest_rng, state.rng_streams.chest_rng.state, "stable outcome never rerolls chest RNG")
	var before_weapon_count: int = state.weapons.size()
	var before_passive_count: int = state.passives.size()
	var before_hp: float = state.current_hp
	var before_evolutions: int = state.evolution_count
	var other_weapon_id := &"homing_core" if outcome.content_id == &"resonance_wave" else &"resonance_wave"
	var applied: Dictionary = ChestRewardService.apply_outcome(state, catalog, outcome.serial)
	assertions.expect_true(bool(applied[&"success"]), "owned upgrade outcome applies")
	assertions.expect_equal(2, state.weapon(outcome.content_id).level, "chest applies exactly one weapon rank")
	assertions.expect_equal(1, state.weapon(other_weapon_id).level, "chest leaves other owned weapon unchanged")
	assertions.expect_equal(before_weapon_count, state.weapons.size(), "owned upgrade does not add a second effect")
	assertions.expect_equal(before_passive_count, state.passives.size(), "owned upgrade does not add a passive")
	assertions.expect_float(before_hp, state.current_hp, "owned upgrade does not also heal")
	assertions.expect_equal(before_evolutions, state.evolution_count, "owned upgrade does not also evolve")
	assertions.expect_equal(0, state.pending_chest_count(), "one outcome consumes one pending chest")
	assertions.expect_equal(1, state.opened_chests, "one outcome increments opened chest once")
	var rejected: Dictionary = ChestRewardService.apply_outcome(state, catalog, outcome.serial)
	assertions.expect_false(bool(rejected[&"success"]), "chest serial cannot apply twice")
	assertions.expect_equal(&"already_applied", rejected[&"reason"], "double chest application has stable reason")
	assertions.expect_equal(2, state.weapon(outcome.content_id).level, "double application cannot add another rank")
	assertions.expect_equal(1, state.opened_chests, "double application cannot increment chest stats")


func _test_chest_last_upgrade_clears_growth_state(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	var state: RunState = _maxed_build_state(catalog)
	var last_passive: RunPassive = state.passive(&"probability_core")
	last_passive.level = 4
	state.evolution_count = ChestRewardService.MAX_EVOLUTIONS_PER_RUN
	state.xp = 3
	state.xp_yield_remainder = 75
	state.pending_level_ups = 2
	state.active_level_offer = LevelOffer.new()
	state.pending_chest_sources.append(3)
	assertions.expect_equal(
		1,
		ProgressionService.remaining_upgrade_capacity(state, catalog),
		"fixture leaves exactly one selectable rank",
	)
	var outcome: ChestOutcome = ChestRewardService.create_outcome(state, catalog)
	assertions.expect_equal(
		GameTypes.ChestOutcomeKind.UPGRADE,
		outcome.kind,
		"the final selectable rank is a chest upgrade",
	)
	assertions.expect_equal(
		&"probability_core",
		outcome.content_id,
		"the only unfinished passive is selected",
	)
	var result: Dictionary = ChestRewardService.apply_outcome(
		state,
		catalog,
		outcome.serial,
	)
	assertions.expect_true(bool(result[&"success"]), "the final chest rank applies")
	assertions.expect_true(state.build_maxed, "the final chest rank marks the build MAX")
	assertions.expect_equal(0, state.xp, "MAX discards partial whole XP")
	assertions.expect_equal(0, state.xp_yield_remainder, "MAX discards fractional XP carry")
	assertions.expect_equal(0, state.pending_level_ups, "MAX clears queued level selections")
	assertions.expect_true(state.active_level_offer == null, "MAX clears a pending level offer")


func _test_chest_source_fifo_and_mismatch_guard(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	var state: RunState = RunStateFactory.create(4646, catalog)
	state.pending_chest_sources.append(3)
	state.pending_chest_sources.append(1)
	var first: ChestOutcome = ChestRewardService.create_outcome(state, catalog)
	assertions.expect_true(first != null, "FIFO head creates the first chest outcome")
	if first == null:
		return
	assertions.expect_equal(3, first.source_elite_index, "first outcome records the FIFO head source")
	state.pending_chest_sources[0] = 1
	var mismatch: Dictionary = ChestRewardService.apply_outcome(state, catalog, first.serial)
	assertions.expect_false(bool(mismatch[&"success"]), "changed FIFO head rejects a stale source")
	assertions.expect_equal(&"chest_source_mismatch", mismatch[&"reason"], "source mismatch has a stable rejection reason")
	assertions.expect_false(first.applied, "source mismatch leaves the outcome unapplied")
	assertions.expect_equal(0, state.opened_chests, "source mismatch does not increment chest stats")
	assertions.expect_equal(2, state.pending_chest_count(), "source mismatch consumes no queued chest")
	state.pending_chest_sources[0] = 3
	var first_applied: Dictionary = ChestRewardService.apply_outcome(state, catalog, first.serial)
	assertions.expect_true(bool(first_applied[&"success"]), "restored FIFO source allows the original outcome")
	assertions.expect_equal(Array([1]), state.pending_chest_sources, "applying the head preserves later chest order")
	var second: ChestOutcome = ChestRewardService.create_outcome(state, catalog)
	assertions.expect_true(second != null, "the next FIFO source creates another outcome")
	if second == null:
		return
	assertions.expect_equal(1, second.source_elite_index, "second outcome records the next elite source")
	assertions.expect_equal(first.serial + 1, second.serial, "FIFO outcomes retain monotonic serials")
	var second_applied: Dictionary = ChestRewardService.apply_outcome(state, catalog, second.serial)
	assertions.expect_true(bool(second_applied[&"success"]), "second FIFO outcome applies")
	assertions.expect_equal(0, state.pending_chest_count(), "two applications drain exactly two queued chests")
	assertions.expect_equal(2, state.opened_chests, "two FIFO outcomes increment the chest count twice")


func _test_rng_and_damage(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	var state: RunState = RunStateFactory.create(6666, catalog)
	var before: Dictionary = state.rng_streams.state_digest()
	state.pending_level_ups = 1
	ProgressionService.create_offer(state, catalog)
	var after_offer: Dictionary = state.rng_streams.state_digest()
	assertions.expect_equal(before[&"spawn"], after_offer[&"spawn"], "offers do not alter spawn RNG")
	assertions.expect_equal(before[&"chest"], after_offer[&"chest"], "offers do not alter chest RNG")
	assertions.expect_equal(before[&"powerup"], after_offer[&"powerup"], "offers do not alter powerup RNG")
	assertions.expect_not_equal(before[&"upgrade"], after_offer[&"upgrade"], "offers advance only upgrade RNG")
	var before_derived: Dictionary = state.rng_streams.state_digest()
	state.rng_streams.create_enemy_rng(42)
	state.rng_streams.create_weapon_rng(&"resonance_wave", 0)
	assertions.expect_equal(before_derived, state.rng_streams.state_digest(), "derived entity RNGs do not mutate shared streams")
	state.record_weapon_damage(&"resonance_wave", 12.5)
	state.record_weapon_damage(&"resonance_wave", 7.5)
	assertions.expect_float(20.0, state.weapon_damage_by_lineage[&"resonance_wave"], "base/evolved damage shares lineage total")


func _test_rng_stream_isolation(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	var chest_state: RunState = RunStateFactory.create(6767, catalog)
	ProgressionService.apply_direct_upgrade(
		chest_state,
		catalog,
		GameTypes.UpgradeKind.WEAPON,
		&"resonance_wave",
	)
	chest_state.pending_chest_sources.append(0)
	var before_chest: Dictionary = chest_state.rng_streams.state_digest()
	var chest_outcome: ChestOutcome = ChestRewardService.create_outcome(chest_state, catalog)
	var after_chest: Dictionary = chest_state.rng_streams.state_digest()
	assertions.expect_true(chest_outcome != null, "chest outcome exists for RNG contract")
	assertions.expect_not_equal(before_chest[&"chest"], after_chest[&"chest"], "chest outcome advances chest RNG")
	assertions.expect_equal(before_chest[&"spawn"], after_chest[&"spawn"], "chest outcome does not alter spawn RNG")
	assertions.expect_equal(before_chest[&"upgrade"], after_chest[&"upgrade"], "chest outcome does not alter upgrade RNG")
	assertions.expect_equal(before_chest[&"powerup"], after_chest[&"powerup"], "chest outcome does not alter powerup RNG")
	var powerup_state: RunState = RunStateFactory.create(6767, catalog)
	var before_powerup: Dictionary = powerup_state.rng_streams.state_digest()
	var drop: GameTypes.NodeDropType = NodeDropService.roll_drop(powerup_state, catalog)
	var after_powerup: Dictionary = powerup_state.rng_streams.state_digest()
	assertions.expect_true(drop in GameTypes.NodeDropType.values(), "powerup roll returns a valid drop")
	assertions.expect_not_equal(before_powerup[&"powerup"], after_powerup[&"powerup"], "powerup roll advances powerup RNG")
	assertions.expect_equal(before_powerup[&"spawn"], after_powerup[&"spawn"], "powerup roll does not alter spawn RNG")
	assertions.expect_equal(before_powerup[&"upgrade"], after_powerup[&"upgrade"], "powerup roll does not alter upgrade RNG")
	assertions.expect_equal(before_powerup[&"chest"], after_powerup[&"chest"], "powerup roll does not alter chest RNG")
	var spawn_state: RunState = RunStateFactory.create(6767, catalog)
	var before_spawn: Dictionary = spawn_state.rng_streams.state_digest()
	var spawn_roll: float = spawn_state.rng_streams.spawn_rng.randf()
	var after_spawn: Dictionary = spawn_state.rng_streams.state_digest()
	assertions.expect_true(spawn_roll >= 0.0 and spawn_roll < 1.0, "spawn RNG produces a valid unit roll")
	assertions.expect_not_equal(before_spawn[&"spawn"], after_spawn[&"spawn"], "spawn roll advances spawn RNG")
	assertions.expect_equal(before_spawn[&"upgrade"], after_spawn[&"upgrade"], "spawn roll does not alter upgrade RNG")
	assertions.expect_equal(before_spawn[&"chest"], after_spawn[&"chest"], "spawn roll does not alter chest RNG")
	assertions.expect_equal(before_spawn[&"powerup"], after_spawn[&"powerup"], "spawn roll does not alter powerup RNG")
	var order_a: RunState = RunStateFactory.create(6868, catalog)
	var order_b: RunState = RunStateFactory.create(6868, catalog)
	order_a.pending_chest_sources.append(0)
	order_b.pending_chest_sources.append(0)
	var unrelated_spawn_roll: int = order_a.rng_streams.spawn_rng.randi()
	assertions.expect_true(unrelated_spawn_roll >= 0, "unrelated spawn consumption completes")
	var order_a_outcome: ChestOutcome = ChestRewardService.create_outcome(order_a, catalog)
	var order_b_outcome: ChestOutcome = ChestRewardService.create_outcome(order_b, catalog)
	assertions.expect_equal(order_b_outcome.kind, order_a_outcome.kind, "spawn consumption cannot change chest kind")
	assertions.expect_equal(order_b_outcome.content_id, order_a_outcome.content_id, "spawn consumption cannot change chest content")
	var powerup_order_a: RunState = RunStateFactory.create(6969, catalog)
	var powerup_order_b: RunState = RunStateFactory.create(6969, catalog)
	ProgressionService.apply_direct_upgrade(
		powerup_order_a,
		catalog,
		GameTypes.UpgradeKind.WEAPON,
		&"homing_core",
	)
	powerup_order_a.pending_chest_sources.append(0)
	ChestRewardService.create_outcome(powerup_order_a, catalog)
	var order_a_drop: GameTypes.NodeDropType = NodeDropService.roll_drop(powerup_order_a, catalog)
	var order_b_drop: GameTypes.NodeDropType = NodeDropService.roll_drop(powerup_order_b, catalog)
	assertions.expect_equal(order_b_drop, order_a_drop, "chest consumption cannot change powerup result")
	var derived_state: RunState = RunStateFactory.create(7070, catalog)
	var before_derived: Dictionary = derived_state.rng_streams.state_digest()
	var weapon_a: RandomNumberGenerator = derived_state.rng_streams.create_weapon_rng(&"resonance_wave", 0)
	var weapon_b: RandomNumberGenerator = derived_state.rng_streams.create_weapon_rng(&"resonance_wave", 0)
	var weapon_other_slot: RandomNumberGenerator = derived_state.rng_streams.create_weapon_rng(&"resonance_wave", 1)
	assertions.expect_equal(weapon_a.seed, weapon_b.seed, "same weapon lineage and slot derive the same seed")
	assertions.expect_not_equal(weapon_a.seed, weapon_other_slot.seed, "weapon slot participates in derived seed")
	for draw_index: int in range(4):
		assertions.expect_equal(weapon_a.randi(), weapon_b.randi(), "same weapon RNG repeats draw %d" % draw_index)
	var enemy_a: RandomNumberGenerator = derived_state.rng_streams.create_enemy_rng(42)
	var enemy_b: RandomNumberGenerator = derived_state.rng_streams.create_enemy_rng(42)
	var enemy_other: RandomNumberGenerator = derived_state.rng_streams.create_enemy_rng(43)
	assertions.expect_equal(enemy_a.seed, enemy_b.seed, "same enemy ID derives the same seed")
	assertions.expect_not_equal(enemy_a.seed, enemy_other.seed, "enemy ID participates in derived seed")
	for draw_index: int in range(4):
		assertions.expect_equal(enemy_a.randi(), enemy_b.randi(), "same enemy RNG repeats draw %d" % draw_index)
	assertions.expect_equal(before_derived, derived_state.rng_streams.state_digest(), "derived RNG creation and use cannot mutate shared streams")


func _test_node_drops(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	var state: RunState = RunStateFactory.create(7777, catalog)
	state.current_hp = 50.0
	var heal: Dictionary = NodeDropService.apply_drop(
		state,
		catalog,
		GameTypes.NodeDropType.HEAL,
	)
	assertions.expect_true(bool(heal[&"success"]), "heal pickup applies")
	assertions.expect_float(80.0, state.current_hp, "heal pickup restores approved amount")
	state.combat_tick = 100
	NodeDropService.apply_drop(state, catalog, GameTypes.NodeDropType.STOP)
	assertions.expect_equal(400, state.stop_until_tick, "stop pickup lasts 300 ticks")
	var vacuum: Dictionary = NodeDropService.apply_drop(
		state,
		catalog,
		GameTypes.NodeDropType.VACUUM,
	)
	assertions.expect_true(bool(vacuum[&"vacuum"]), "vacuum pickup requests all-XP collection")


func _test_build_max(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	var state: RunState = _maxed_build_state(catalog)
	state.xp = 7
	state.xp_yield_remainder = 33
	state.pending_level_ups = 2
	state.active_level_offer = LevelOffer.new()
	assertions.expect_equal(0, ProgressionService.remaining_upgrade_capacity(state, catalog), "max build has no upgrade capacity")
	var queued: int = ProgressionService.add_xp(state, 100000, catalog)
	assertions.expect_equal(0, queued, "max build stops level queue")
	assertions.expect_true(state.build_maxed, "max build exposes MAX state")
	assertions.expect_equal(0, state.xp, "max build no longer stores XP")
	assertions.expect_equal(0, state.xp_yield_remainder, "max build clears fractional XP carry")
	assertions.expect_equal(0, state.pending_level_ups, "max build clears queued selections")
	assertions.expect_true(state.active_level_offer == null, "max build clears the active offer")


func _single_owned_offer_state(run_seed: int, catalog: DefinitionCatalog) -> RunState:
	var state: RunState = RunStateFactory.create(run_seed, catalog)
	state.level = 2
	state.pending_level_ups = 1
	return state


func _two_owned_offer_state(run_seed: int, catalog: DefinitionCatalog) -> RunState:
	var state: RunState = _single_owned_offer_state(run_seed, catalog)
	ProgressionService.apply_direct_upgrade(
		state,
		catalog,
		GameTypes.UpgradeKind.WEAPON,
		&"zero_field",
	)
	return state


func _owned_eligible_options(
	state: RunState,
	catalog: DefinitionCatalog,
) -> Array[UpgradeOption]:
	return _owned_options_from(ProgressionService._eligible_options(state, catalog))


func _owned_options_from(options: Array[UpgradeOption]) -> Array[UpgradeOption]:
	var owned: Array[UpgradeOption] = []
	for option: UpgradeOption in options:
		if option.current_level > 0:
			owned.append(option)
	return owned


func _clone_rng(source: RandomNumberGenerator) -> RandomNumberGenerator:
	var clone := RandomNumberGenerator.new()
	clone.seed = source.seed
	clone.state = source.state
	return clone


func _draw_weighted_tokens(
	rng: RandomNumberGenerator,
	options: Array[UpgradeOption],
	count: int,
) -> Array[StringName]:
	var available: Array[UpgradeOption] = options.duplicate()
	var result: Array[StringName] = []
	while result.size() < count and not available.is_empty():
		var tokens: Array[StringName] = []
		var weights := PackedFloat64Array()
		for option: UpgradeOption in available:
			tokens.append(_upgrade_option_token(option))
			weights.append(option.weight)
		var selected_token: StringName = WeightedSelector.select(rng, tokens, weights)
		result.append(selected_token)
		_remove_upgrade_option(available, selected_token)
	return result


func _offer_option_tokens(offer: LevelOffer) -> Array[StringName]:
	var result: Array[StringName] = []
	for option: UpgradeOption in offer.options:
		result.append(_upgrade_option_token(option))
	return result


func _upgrade_option_token(option: UpgradeOption) -> StringName:
	return StringName("%d|%s" % [int(option.kind), option.content_id])


func _remove_upgrade_option(
	options: Array[UpgradeOption],
	token: StringName,
) -> void:
	for index: int in range(options.size()):
		if _upgrade_option_token(options[index]) == token:
			options.remove_at(index)
			return


func _five_evolution_ready_state(catalog: DefinitionCatalog) -> RunState:
	var state: RunState = RunStateFactory.create(8888, catalog)
	var weapon_ids: Array[StringName] = [
		&"resonance_wave", &"directional_needle", &"arc_crystal", &"returning_ring",
	]
	for weapon_id: StringName in weapon_ids:
		ProgressionService.apply_direct_upgrade(state, catalog, GameTypes.UpgradeKind.WEAPON, weapon_id)
	for runtime: RunWeapon in state.weapons:
		runtime.level = 8
	var passive_ids: Array[StringName] = [
		&"life_lattice", &"cycle_crystal", &"speed_gate", &"scale_lens", &"probability_core",
	]
	for passive_id: StringName in passive_ids:
		ProgressionService.apply_direct_upgrade(state, catalog, GameTypes.UpgradeKind.PASSIVE, passive_id)
	return state


func _maxed_build_state(catalog: DefinitionCatalog) -> RunState:
	var state: RunState = RunStateFactory.create(9999, catalog)
	var weapon_ids: Array[StringName] = [
		&"resonance_wave", &"directional_needle", &"arc_crystal", &"returning_ring",
	]
	for weapon_id: StringName in weapon_ids:
		ProgressionService.apply_direct_upgrade(state, catalog, GameTypes.UpgradeKind.WEAPON, weapon_id)
	for runtime: RunWeapon in state.weapons:
		runtime.level = 8
	var passive_ids: Array[StringName] = [
		&"life_lattice", &"cycle_crystal", &"speed_gate", &"scale_lens", &"probability_core",
	]
	for passive_id: StringName in passive_ids:
		ProgressionService.apply_direct_upgrade(state, catalog, GameTypes.UpgradeKind.PASSIVE, passive_id)
	for runtime: RunPassive in state.passives:
		runtime.level = 5
	return state


func _fixed_content_specs() -> Array[Dictionary]:
	return [
		{
			&"base_id": &"resonance_wave",
			&"base_name": "共鳴波",
			&"base_weight": 100.0,
			&"evolved_id": &"vital_resonance",
			&"evolved_name": "生命共鳴",
			&"passive_id": &"life_lattice",
			&"passive_name": "生命格子",
			&"passive_weight": 90.0,
			&"stat_id": &"max_hp_pct",
			&"amount": 20.0,
			&"behavior": GameTypes.WeaponBehavior.MELEE_WAVE,
		},
		{
			&"base_id": &"homing_core",
			&"base_name": "追尾核",
			&"base_weight": 100.0,
			&"evolved_id": &"infinite_homing",
			&"evolved_name": "無限追尾",
			&"passive_id": &"cycle_crystal",
			&"passive_name": "周期結晶",
			&"passive_weight": 50.0,
			&"stat_id": &"cooldown_pct",
			&"amount": -8.0,
			&"behavior": GameTypes.WeaponBehavior.HOMING_PROJECTILE,
		},
		{
			&"base_id": &"directional_needle",
			&"base_name": "方向針",
			&"base_weight": 100.0,
			&"evolved_id": &"infinite_needles",
			&"evolved_name": "無限針列",
			&"passive_id": &"speed_gate",
			&"passive_name": "速度門",
			&"passive_weight": 100.0,
			&"stat_id": &"projectile_speed_pct",
			&"amount": 10.0,
			&"behavior": GameTypes.WeaponBehavior.DIRECTIONAL_PROJECTILE,
		},
		{
			&"base_id": &"arc_crystal",
			&"base_name": "弧晶",
			&"base_weight": 100.0,
			&"evolved_id": &"spiral_crystal",
			&"evolved_name": "螺旋晶",
			&"passive_id": &"scale_lens",
			&"passive_name": "尺度レンズ",
			&"passive_weight": 100.0,
			&"stat_id": &"area_pct",
			&"amount": 10.0,
			&"behavior": GameTypes.WeaponBehavior.ARC_PROJECTILE,
		},
		{
			&"base_id": &"returning_ring",
			&"base_name": "反転環",
			&"base_weight": 80.0,
			&"evolved_id": &"critical_ring",
			&"evolved_name": "臨界環",
			&"passive_id": &"probability_core",
			&"passive_name": "確率核",
			&"passive_weight": 100.0,
			&"stat_id": &"luck_pct",
			&"amount": 10.0,
			&"behavior": GameTypes.WeaponBehavior.RETURNING_RING,
		},
		{
			&"base_id": &"orbital_array",
			&"base_name": "軌道陣",
			&"base_weight": 80.0,
			&"evolved_id": &"eternal_orbit",
			&"evolved_name": "永続軌道",
			&"passive_id": &"duration_ring",
			&"passive_name": "持続環",
			&"passive_weight": 100.0,
			&"stat_id": &"duration_pct",
			&"amount": 10.0,
			&"behavior": GameTypes.WeaponBehavior.ORBITAL,
		},
		{
			&"base_id": &"mass_projectile",
			&"base_name": "質量弾",
			&"base_weight": 80.0,
			&"evolved_id": &"collapse_projectile",
			&"evolved_name": "崩壊弾",
			&"passive_id": &"amplifier_core",
			&"passive_name": "増幅核",
			&"passive_weight": 100.0,
			&"stat_id": &"might_pct",
			&"amount": 10.0,
			&"behavior": GameTypes.WeaponBehavior.MASS_PROJECTILE,
		},
		{
			&"base_id": &"zero_field",
			&"base_name": "零界",
			&"base_weight": 70.0,
			&"evolved_id": &"absorption_field",
			&"evolved_name": "吸収界",
			&"passive_id": &"repair_core",
			&"passive_name": "修復核",
			&"passive_weight": 90.0,
			&"stat_id": &"recovery_per_second",
			&"amount": 0.2,
			&"behavior": GameTypes.WeaponBehavior.AURA,
		},
	]


func _with_segment(
	manifest: SurvivalContentManifest,
	segment_index: int,
	segment: EnemySegmentDefinition,
) -> SurvivalContentManifest:
	var copy: SurvivalContentManifest = manifest.duplicate(true) as SurvivalContentManifest
	var segments: Array[EnemySegmentDefinition] = []
	segments.assign(manifest.segments)
	segments[segment_index] = segment
	copy.segments = segments
	return copy


func _with_enemy(
	manifest: SurvivalContentManifest,
	enemy_index: int,
	enemy: EnemyDefinition,
) -> SurvivalContentManifest:
	var copy: SurvivalContentManifest = manifest.duplicate(true) as SurvivalContentManifest
	var enemy_definitions: Array[EnemyDefinition] = []
	enemy_definitions.assign(manifest.enemies)
	enemy_definitions[enemy_index] = enemy
	copy.enemies = enemy_definitions
	return copy


func _enemy_index_for_type(
	manifest: SurvivalContentManifest,
	enemy_type: GameTypes.EnemyType,
) -> int:
	for index: int in range(manifest.enemies.size()):
		if manifest.enemies[index].enemy_type == enemy_type:
			return index
	return -1


func _catalog(assertions: Variant) -> DefinitionCatalog:
	var catalog := DefinitionCatalog.new()
	assertions.expect_true(catalog.load_and_validate(), "survival catalog valid: %s" % catalog.error_text)
	return catalog
