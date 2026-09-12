extends RefCounted


func test_survival_xp_formula_growth_and_queue(assertions: Variant, _context: Dictionary) -> void:
	var independent := ProgressionBalanceDefinition.new()
	independent.xp_early_max_level = 3
	independent.xp_early_coefficient = 2
	independent.xp_early_offset = 1
	independent.xp_first_transition_requirement = 25
	independent.xp_middle_max_level = 7
	independent.xp_middle_coefficient = 5
	independent.xp_middle_offset = -5
	independent.xp_second_transition_requirement = 40
	independent.xp_late_coefficient = 7
	independent.xp_late_offset = -2
	for example: Vector2i in [Vector2i(1, 3), Vector2i(3, 7), Vector2i(4, 25), Vector2i(5, 20), Vector2i(7, 30), Vector2i(8, 40), Vector2i(9, 61)]:
		assertions.expect_equal(example.y, ProgressionService.xp_required_for_level(example.x, independent), "piecewise XP formula uses independent coefficients and offsets")
	var catalog: DefinitionCatalog = _catalog(assertions)
	var manifest: SurvivalContentManifest = catalog.manifest()
	var original_yield_percent: int = manifest.progression.xp_yield_percent
	manifest.progression.xp_yield_percent = 100
	var state: RunState = RunStateFactory.create(1001, catalog)
	var queued: int = ProgressionService.add_xp(state, 20, catalog)
	manifest.progression.xp_yield_percent = original_yield_percent
	assertions.expect_equal(2, queued, "one pickup may queue multiple levels")
	assertions.expect_equal(3, state.level, "queued levels advance player level")
	assertions.expect_equal(0, state.xp, "threshold XP consumed exactly")


func test_survival_capacity_level_sixty_five_and_growth_application(assertions: Variant, _context: Dictionary) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	var manifest: SurvivalContentManifest = catalog.manifest()
	var original_yield_percent: int = manifest.progression.xp_yield_percent
	manifest.progression.xp_yield_percent = 100
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
	manifest.progression.xp_yield_percent = original_yield_percent
	assertions.expect_equal(0, queued_at_normal_level, "small normal-level pickup does not cross threshold")
	assertions.expect_equal(10, normal_level.xp, "Growth is not applied outside levels 20 and 40")


func test_survival_growth_boundaries_apply_per_level_segment(assertions: Variant, _context: Dictionary) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	var manifest: SurvivalContentManifest = catalog.manifest()
	var original_yield_percent: int = manifest.progression.xp_yield_percent
	manifest.progression.xp_yield_percent = 100
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
	manifest.progression.xp_yield_percent = original_yield_percent
	assertions.expect_equal(1, leaving_twenty_queued, "Growth-assisted XP crosses the level twenty threshold")
	assertions.expect_equal(21, leaving_twenty.level, "Growth compensation ends after leaving level twenty")
	assertions.expect_equal(8, leaving_twenty.xp, "post-threshold remainder returns to normal Growth")


func test_survival_manifest_drives_progression_and_xp_pickups(assertions: Variant, _context: Dictionary) -> void:
	var canonical_catalog: DefinitionCatalog = _catalog(assertions)
	var custom_manifest: SurvivalContentManifest = canonical_catalog.manifest().duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as SurvivalContentManifest
	assertions.expect_true(custom_manifest != null, "manifest duplicates for source-of-truth fixture")
	if custom_manifest == null:
		return
	custom_manifest.progression.xp_early_coefficient = 11
	custom_manifest.progression.xp_growth_compensation_multiplier = 3.0
	assertions.expect_equal(
		6,
		ProgressionService.xp_required_for_level(1, custom_manifest.progression),
		"manifest-aware XP API uses configured coefficient",
	)
	assertions.expect_float(
		3.0,
		ProgressionService.xp_growth_multiplier(20, custom_manifest.progression),
		"manifest-aware Growth API uses configured compensation",
	)
	var custom_catalog := DefinitionCatalog.new()
	custom_manifest.progression.xp_yield_percent = 100
	assertions.expect_true(custom_catalog.validate_manifest(custom_manifest), "valid custom fixture follows normal validation")
	var early_state: RunState = RunStateFactory.create(1301, custom_catalog)
	var growth_state: RunState = RunStateFactory.create(1302, custom_catalog)
	growth_state.level = 20
	var early_queued: int = ProgressionService.add_xp(early_state, 5, custom_catalog)
	assertions.expect_equal(0, early_queued, "add_xp reads the manifest XP coefficient")
	assertions.expect_equal(5, early_state.xp, "custom level-one threshold remains unmet")
	var growth_queued: int = ProgressionService.add_xp(growth_state, 10, custom_catalog)
	assertions.expect_equal(0, growth_queued, "custom Growth fixture remains below level twenty threshold")
	assertions.expect_equal(30, growth_state.xp, "add_xp reads the manifest Growth multiplier")
	var pickup_manifest: SurvivalContentManifest = BalanceTestFixtures.manifest()
	pickup_manifest.progression.xp_pool_capacity = 2
	pickup_manifest.progression.xp_pickup_attract_radius = 1.25
	pickup_manifest.progression.xp_pickup_collect_radius = 0.1
	pickup_manifest.progression.xp_pickup_speed = 1.0
	var pool := BalanceTestFixtures.xp_pool()
	pool.configure(pickup_manifest.progression)
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


func test_survival_xp_yield_fraction_and_growth_order(assertions: Variant, _context: Dictionary) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	var manifest: SurvivalContentManifest = catalog.manifest()
	var original_yield_percent: int = manifest.progression.xp_yield_percent
	manifest.progression.xp_yield_percent = 95
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
	assertions.expect_equal(38, growth_state.xp, "carried scaling fraction resolves before the next Growth application")
	assertions.expect_equal(0, growth_state.xp_yield_remainder, "resolved Growth fixture leaves no XP fraction")
	manifest.progression.xp_yield_percent = 120
	var bonus_state: RunState = RunStateFactory.create(1354, catalog)
	bonus_state.level = 20
	bonus_state.xp = ProgressionService.xp_required_for_level(20, manifest.progression) - 2
	assertions.expect_equal(1, ProgressionService.add_xp(bonus_state, 4, catalog), "XP bonus crosses the Growth boundary within one pickup")
	assertions.expect_equal(21, bonus_state.level, "Growth ends when the bonus pickup advances the level")
	assertions.expect_equal(3, bonus_state.xp, "only the first of four scaled XP receives Growth before crossing")
	assertions.expect_equal(80, bonus_state.xp_yield_remainder, "120 percent scaling carries four fifths of an XP across the level boundary")
	ProgressionService.add_xp(bonus_state, 1, catalog)
	assertions.expect_equal(5, bonus_state.xp, "the next one-XP pickup releases two XP after Growth has ended")
	assertions.expect_equal(0, bonus_state.xp_yield_remainder, "the bonus fraction is retained without loss")
	manifest.progression.xp_yield_percent = original_yield_percent


func test_survival_validator_rejects_all_nonboss_ranged_drift(assertions: Variant, _context: Dictionary) -> void:
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
		canonical.enemies[shooter_index].duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as EnemyDefinition
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
		canonical.enemies[elite_index].duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as EnemyDefinition
	)
	non_finite_elite.body_radius = NAN
	var non_finite_catalog := DefinitionCatalog.new()
	assertions.expect_false(
		non_finite_catalog.validate_manifest(
			_with_enemy(canonical, elite_index, non_finite_elite)
		),
		"validator rejects non-finite ranged drift on an elite",
	)
	assertions.expect_true(
		non_finite_catalog.error_text.contains("body_radius") and non_finite_catalog.error_text.contains("finite"),
		"non-finite physical radius reports its field and constraint",
	)


func test_survival_weighted_unique_offer_and_serial_guard(assertions: Variant, _context: Dictionary) -> void:
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


func test_survival_queued_offer_levels_and_owned_probability(assertions: Variant, _context: Dictionary) -> void:
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


func test_survival_new_weapon_upgrade_is_atomic(assertions: Variant, _context: Dictionary) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	var state: RunState = RunStateFactory.create(3333, catalog)
	var unowned_option: UpgradeOption = _find_option(
		ProgressionService._eligible_options(state, catalog),
		GameTypes.UpgradeKind.WEAPON,
		&"resonance_wave",
	)
	assertions.expect_true(unowned_option != null, "unowned resonance wave enters offers")
	if unowned_option != null:
		assertions.expect_false(unowned_option.description.is_empty(), "new weapon includes its overview")
		assertions.expect_equal("", unowned_option.upgrade_detail, "new weapon has no previous-level delta")
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
	var owned_option: UpgradeOption = _find_option(
		ProgressionService._eligible_options(state, catalog),
		GameTypes.UpgradeKind.WEAPON,
		&"resonance_wave",
	)
	assertions.expect_true(owned_option != null, "owned resonance wave remains eligible")
	if owned_option != null:
		assertions.expect_false(owned_option.upgrade_detail.is_empty(), "owned weapon exposes its next delta")


func test_survival_slot_and_max_rejections(assertions: Variant, _context: Dictionary) -> void:
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


func test_survival_chest_evolution_fallback_and_cap(assertions: Variant, _context: Dictionary) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	var evolution_source: int = catalog.elite_chest_kinds.find(GameTypes.ChestKind.EVOLUTION_CAPABLE)
	var early: RunState = RunStateFactory.create(4444, catalog)
	early.weapon(&"homing_core").level = 8
	ProgressionService.apply_direct_upgrade(early, catalog, GameTypes.UpgradeKind.PASSIVE, &"cycle_crystal")
	assertions.expect_equal(
		1,
		early.passive(&"cycle_crystal").level,
		"a level-one catalyst prepares the standard evolution contract",
	)
	early.pending_chest_sources.append(evolution_source)
	var evolution: ChestOutcome = ChestRewardService.create_outcome(early, catalog)
	assertions.expect_equal(
		GameTypes.ChestOutcomeKind.EVOLUTION,
		evolution.kind,
		"a level-one catalyst is eligible without reaching its maximum level",
	)
	assertions.expect_equal(&"infinite_homing", evolution.content_id, "correct evolution result")
	assertions.expect_equal(evolution_source, evolution.source_elite_index, "outcome keeps its elite source")
	assertions.expect_equal(0, early.combat_tick, "evolution has no time gate")
	var evolution_result: Dictionary = ChestRewardService.apply_outcome(
		early,
		catalog,
		evolution.serial,
	)
	assertions.expect_true(bool(evolution_result[&"success"]), "evolution applies")
	assertions.expect_true(early.weapon_for_lineage(&"homing_core").evolved, "runtime becomes evolved")
	assertions.expect_equal(
		1,
		early.passive(&"cycle_crystal").level,
		"the level-one catalyst remains unconsumed after evolution",
	)
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
		capped.pending_chest_sources.append(evolution_source + _chest_index)
		var outcome: ChestOutcome = ChestRewardService.create_outcome(capped, catalog)
		assertions.expect_equal(GameTypes.ChestOutcomeKind.EVOLUTION, outcome.kind, "first four eligible chests evolve")
		ChestRewardService.apply_outcome(capped, catalog, outcome.serial)
	assertions.expect_equal(4, capped.evolution_count, "run evolution cap is four")
	capped.pending_chest_sources.append(evolution_source + 4)
	var after_cap: ChestOutcome = ChestRewardService.create_outcome(capped, catalog)
	assertions.expect_not_equal(GameTypes.ChestOutcomeKind.EVOLUTION, after_cap.kind, "fifth chest cannot evolve")


func test_survival_chest_owned_upgrade_stability_serial_and_single_effect(assertions: Variant, _context: Dictionary) -> void:
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
	var expected_detail: String = (
		"連射数 1 → 2"
		if outcome.content_id == &"homing_core"
		else "波数 2 → 3"
	)
	assertions.expect_equal(expected_detail, outcome.upgrade_detail, "chest stores the selected content delta")
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


func test_survival_chest_last_upgrade_clears_growth_state(assertions: Variant, _context: Dictionary) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	var state: RunState = _maxed_build_state(catalog)
	var last_passive: RunPassive = state.passive(&"probability_core")
	last_passive.level = 4
	state.evolution_count = catalog.manifest().progression.max_evolutions_per_run
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


func test_survival_chest_source_fifo_and_mismatch_guard(assertions: Variant, _context: Dictionary) -> void:
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


func test_survival_rng_streams_and_lineage_damage(assertions: Variant, _context: Dictionary) -> void:
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


func test_survival_rng_stream_mutual_isolation_and_derived_repeatability(assertions: Variant, _context: Dictionary) -> void:
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


func test_survival_node_drop_effects(assertions: Variant, _context: Dictionary) -> void:
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


func test_survival_build_max_stops_leveling(assertions: Variant, _context: Dictionary) -> void:
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


func _with_enemy(
	manifest: SurvivalContentManifest,
	enemy_index: int,
	enemy: EnemyDefinition,
) -> SurvivalContentManifest:
	var copy: SurvivalContentManifest = manifest.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as SurvivalContentManifest
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
	assertions.expect_true(catalog.validate_manifest(BalanceTestFixtures.manifest()), "survival catalog valid: %s" % catalog.error_text)
	return catalog


func _find_option(
	options: Array[UpgradeOption],
	kind: GameTypes.UpgradeKind,
	content_id: StringName,
) -> UpgradeOption:
	for option: UpgradeOption in options:
		if option.kind == kind and option.content_id == content_id:
			return option
	return null
