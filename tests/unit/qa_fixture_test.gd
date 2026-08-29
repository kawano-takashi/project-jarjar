extends RefCounted


const LaunchArgumentsScript = preload("res://src/app/launch_arguments.gd")
const SettingsStoreScript = preload("res://src/core/settings_store.gd")
const GameAppScript = preload("res://src/app/game_app.gd")


func test_names() -> PackedStringArray:
	return PackedStringArray([
		"qa_id_launch_and_settings_contract",
		"qa_inventory_and_result_fixtures",
		"qa_immortal_and_boss_fixtures",
	])


func run_test(test_name: String, assertions: Variant, context: Dictionary) -> void:
	match test_name:
		"qa_id_launch_and_settings_contract":
			_test_qa_id_launch_and_settings(assertions, context)
		"qa_inventory_and_result_fixtures":
			_test_inventory_and_result(assertions)
		"qa_immortal_and_boss_fixtures":
			_test_immortal_and_boss(assertions)
		_:
			assertions.expect_true(false, "registered inventory QA fixture test")


func _test_qa_id_launch_and_settings(assertions: Variant, context: Dictionary) -> void:
	var expected_ids: Array[String] = [
		"weapon_bow",
		"weapon_staff",
		"weapon_sword",
		"pre_quota_death",
		"pre_quota_timeout",
		"post_quota_death",
		"reward_controls",
		"inventory_controller",
		"result_controller",
		"immortal_100",
		"boss_299",
	]
	assertions.expect_equal(expected_ids, QaScenarioFactory.VALID_IDS, "inventory factory exposes the exact QA ID list")
	assertions.expect_equal(expected_ids, LaunchArgumentsScript.QA_SCENARIOS, "inventory parser exposes the exact QA ID list")
	var runtime_scenario_ids: Array[String] = [
		"inventory_controller",
		"result_controller",
		"immortal_100",
		"boss_299",
	]
	for scenario_id: String in runtime_scenario_ids:
		var settings_path: String = String(context["test_user_root"]).path_join(
			"qa-scenario-%s/settings.cfg" % scenario_id
		)
		if FileAccess.file_exists(settings_path):
			assertions.expect_equal(
				OK,
				DirAccess.remove_absolute(settings_path),
				"%s removes prior isolated QA settings" % scenario_id,
			)
		var parsed: Dictionary = LaunchArgumentsScript.parse_debug(PackedStringArray([
			"--qa-scenario=" + scenario_id,
		]))
		assertions.expect_true(parsed.get("valid", false), "%s launch arguments accepted" % scenario_id)
		assertions.expect_equal(LaunchArgumentsScript.MODE_QA_SCENARIO, parsed.get("mode"), "%s QA launch mode" % scenario_id)
		assertions.expect_equal(scenario_id, parsed.get("qa_scenario"), "%s parsed QA ID" % scenario_id)
		var settings_store: Variant = SettingsStoreScript.new()
		var game_app: Variant = GameAppScript.new()
		game_app.set("_launch", parsed)
		assertions.expect_equal(
			OK,
			game_app.call("_initialize_settings_for_launch", settings_store),
			"%s runtime settings initialize" % scenario_id,
		)
		assertions.expect_true(settings_store.tutorial_seen, "%s runtime tutorial inactive" % scenario_id)
		assertions.expect_equal("", settings_store.active_settings_path, "%s runtime settings stay ephemeral" % scenario_id)
		assertions.expect_false(FileAccess.file_exists(settings_path), "%s writes no settings file" % scenario_id)
		game_app.free()
		settings_store.free()
	var rejected: Dictionary = LaunchArgumentsScript.parse_debug(PackedStringArray([
		"--qa-scenario=unknown",
	]))
	assertions.expect_false(rejected.get("valid", true), "unknown QA ID rejected before runtime state")
	assertions.expect_equal("--qa-scenario", rejected.get("rejected_name"), "unknown QA rejection marker")


func _test_inventory_and_result(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	if catalog == null:
		return
	var inventory_result: Dictionary = QaScenarioFactory.build(
		"inventory_controller",
		catalog,
	)
	assertions.expect_true(inventory_result.get("valid", false), "inventory QA fixture valid")
	assertions.expect_true(inventory_result.get("rng_unchanged", false), "inventory QA leaves run RNG streams unchanged")
	assertions.expect_false(inventory_result.get("tutorial_active", true), "inventory QA tutorial inactive")
	if not inventory_result.get("valid", false):
		return
	var state: RunState = inventory_result["state"] as RunState
	assertions.expect_equal(GameTypes.RunPhase.INVENTORY, state.phase, "inventory fixture phase")
	assertions.expect_equal(7, state.wave_number, "inventory fixture wave")
	assertions.expect_true(state.wave_cleared, "inventory fixture represents a cleared wave")
	assertions.expect_equal(7, state.cleared_waves, "inventory fixture cleared-wave total")
	assertions.expect_equal(36, _non_null_count(state.inventory), "inventory fixture fills 36 stable indices")
	assertions.expect_equal(4, state.overflow.size(), "inventory fixture has four overflow items")
	assertions.expect_equal(1, state.wild_material_count, "inventory fixture has one wild material")
	for slot_index: int in range(GameTypes.EquipmentSlot.size()):
		var equipped: ItemInstance = state.equipped.get(slot_index, null) as ItemInstance
		assertions.expect_true(equipped != null, "equipped fixture slot %d populated" % slot_index)
		if equipped == null:
			continue
		assertions.expect_equal("qa-equipped-%02d" % slot_index, equipped.item_id, "equipped fixture id %d" % slot_index)
		assertions.expect_equal(slot_index, equipped.slot, "equipped fixture slot enum %d" % slot_index)
		assertions.expect_equal(GameTypes.Rarity.COMMON, equipped.rarity, "equipped fixture Common %d" % slot_index)
		assertions.expect_false(equipped.locked, "equipped fixture unlocked %d" % slot_index)
		assertions.expect_equal(&"", equipped.unique_id, "equipped fixture non-unique %d" % slot_index)
		assertions.expect_equal(
			GameTypes.MainWeaponType.BOW if slot_index == GameTypes.EquipmentSlot.MAIN_WEAPON else GameTypes.MainWeaponType.UNCLASSIFIED,
			equipped.main_weapon_type,
			"equipped fixture weapon type %d" % slot_index,
		)
		_assert_matches_normal_fixture_item(assertions, catalog, equipped)
	var expected_rarities: Array[int] = []
	for index: int in range(36):
		var expected_slot: GameTypes.EquipmentSlot = (
			index % GameTypes.EquipmentSlot.size()
		) as GameTypes.EquipmentSlot
		if index == 33:
			expected_slot = GameTypes.EquipmentSlot.SUB_WEAPON
		elif index == 34:
			expected_slot = GameTypes.EquipmentSlot.HANDS
		elif index == 35:
			expected_slot = GameTypes.EquipmentSlot.FEET
		expected_rarities.append(
			GameTypes.Rarity.COMMON
			if index <= 17 or index == 34
			else GameTypes.Rarity.RARE
			if index <= 26 or index == 33
			else GameTypes.Rarity.EPIC
			if index <= 32
			else GameTypes.Rarity.LEGENDARY
		)
		var item: ItemInstance = state.inventory[index]
		assertions.expect_equal("qa-inventory-%02d" % index, item.item_id, "inventory stable item id %02d" % index)
		assertions.expect_equal(expected_rarities[index], item.rarity, "inventory rarity %02d" % index)
		assertions.expect_equal(expected_slot, item.slot, "inventory slot %02d" % index)
		var expected_weapon_type: GameTypes.MainWeaponType = GameTypes.MainWeaponType.UNCLASSIFIED
		if expected_slot == GameTypes.EquipmentSlot.MAIN_WEAPON:
			expected_weapon_type = [
				GameTypes.MainWeaponType.BOW,
				GameTypes.MainWeaponType.STAFF,
				GameTypes.MainWeaponType.SWORD,
			][floori(float(index) / 6.0) % 3]
		assertions.expect_equal(expected_weapon_type, item.main_weapon_type, "inventory weapon type %02d" % index)
		assertions.expect_equal(index == 34, item.locked, "inventory lock state %02d" % index)
		assertions.expect_equal(
			&"bloodied_dagger" if index == 33 else &"",
			item.unique_id,
			"inventory unique state %02d" % index,
		)
		assertions.expect_equal(
			SeedService.derive(QaScenarioFactory.FIXED_SEED, StringName("qa-item:" + item.item_id)),
			item.item_seed,
			"inventory QA item seed %02d" % index,
		)
	for index: int in range(3):
		_assert_single_affix(assertions, state.inventory[index], &"max_hp", 10.0)
	for index: int in range(3, 18):
		_assert_single_affix(assertions, state.inventory[index], &"attack_speed_pct", 8.0)
	for index: int in range(18, 33):
		_assert_matches_normal_fixture_item(assertions, catalog, state.inventory[index])
	var dagger: ItemInstance = state.inventory[33]
	assertions.expect_equal(&"bloodied_dagger", dagger.unique_id, "inventory index 33 fixed dagger")
	_assert_single_affix(assertions, dagger, &"damage_pct", 14.0)
	assertions.expect_true(state.inventory[34].locked, "inventory index 34 locked")
	assertions.expect_equal(GameTypes.Rarity.LEGENDARY, state.inventory[35].rarity, "inventory index 35 Legendary")
	_assert_matches_normal_fixture_item(assertions, catalog, state.inventory[34])
	_assert_matches_normal_fixture_item(assertions, catalog, state.inventory[35])
	var overflow_slots: Array[int] = [
		GameTypes.EquipmentSlot.MAIN_WEAPON,
		GameTypes.EquipmentSlot.SUB_WEAPON,
		GameTypes.EquipmentSlot.HEAD,
		GameTypes.EquipmentSlot.BODY,
	]
	for index: int in range(4):
		var overflow_item: ItemInstance = state.overflow[index]
		assertions.expect_equal("qa-overflow-%02d" % index, overflow_item.item_id, "overflow stable id %02d" % index)
		assertions.expect_equal(overflow_slots[index], overflow_item.slot, "overflow slot %02d" % index)
		assertions.expect_equal(GameTypes.Rarity.COMMON, overflow_item.rarity, "overflow Common %02d" % index)
		assertions.expect_equal(
			GameTypes.MainWeaponType.STAFF if index == 0 else GameTypes.MainWeaponType.UNCLASSIFIED,
			overflow_item.main_weapon_type,
			"overflow weapon type %02d" % index,
		)
		assertions.expect_false(overflow_item.locked, "overflow unlocked %02d" % index)
		assertions.expect_equal(&"", overflow_item.unique_id, "overflow non-unique %02d" % index)
		assertions.expect_equal(
			SeedService.derive(QaScenarioFactory.FIXED_SEED, StringName("qa-item:" + overflow_item.item_id)),
			overflow_item.item_seed,
			"overflow QA item seed %02d" % index,
		)
		_assert_single_affix(assertions, overflow_item, &"attack_speed_pct", 8.0)
	_assert_skill(assertions, state, &"starfall", 3, 0, 0.0)
	_assert_skill(assertions, state, &"thousand_blades", 2, 1, 0.0)
	_assert_skill(assertions, state, &"soul_chain", 1, -1, 0.0)
	_assert_skill(assertions, state, &"bell_of_retribution", 3, -1, 0.0)

	var result_fixture: Dictionary = QaScenarioFactory.build("result_controller", catalog)
	assertions.expect_true(result_fixture.get("valid", false), "result QA fixture valid")
	assertions.expect_true(result_fixture.get("rng_unchanged", false), "result QA leaves run RNG streams unchanged")
	assertions.expect_false(result_fixture.get("tutorial_active", true), "result QA tutorial inactive")
	if not result_fixture.get("valid", false):
		return
	var result_state: RunState = result_fixture["state"] as RunState
	assertions.expect_equal(GameTypes.RunPhase.RESULT, result_state.phase, "result fixture phase")
	assertions.expect_equal(QaScenarioFactory.FIXED_SEED, result_state.run_seed, "result fixture fixed seed")
	assertions.expect_equal(8, result_state.wave_number, "result fixture wave number")
	assertions.expect_true(result_state.wave_cleared, "result fixture final wave cleared")
	assertions.expect_true(result_state.boss_defeated, "result fixture boss defeated")
	assertions.expect_equal(8, result_state.cleared_waves, "result fixture clears eight waves")
	assertions.expect_equal(100, result_state.normal_kills, "result normal kills")
	assertions.expect_equal(1, result_state.elite_kills, "result elite kills")
	assertions.expect_equal(1, result_state.boss_kills, "result boss kills")
	assertions.expect_equal(102, result_state.total_kills, "result total kills")
	assertions.expect_equal(20, result_state.post_quota_kills, "result post-quota kills")
	assertions.expect_equal(160, result_state.total_chests, "result chest total")
	assertions.expect_equal(12, result_state.fusion_count, "result fusion count")
	assertions.expect_float(999.0, result_state.peak_dps, "result peak DPS")
	assertions.expect_equal(2, result_state.wild_material_count, "result wild material count")
	assertions.expect_equal(9000, result_state.score_breakdown[&"combat_score"], "result combat score")
	assertions.expect_equal(3055, result_state.score_breakdown[&"final_build_score"], "result build score")
	assertions.expect_equal(12055, result_state.score_breakdown[&"total"], "result total score")
	assertions.expect_equal(null, result_state.equipped[GameTypes.EquipmentSlot.HEAD], "result HEAD empty")
	assertions.expect_equal(null, result_state.equipped[GameTypes.EquipmentSlot.FEET], "result FEET empty")
	assertions.expect_equal(0, _non_null_count(result_state.inventory), "result inventory empty")
	assertions.expect_equal(0, result_state.overflow.size(), "result overflow empty")
	assertions.expect_equal(1000, result_state.score_breakdown[&"normal_kills"], "result normal score row")
	assertions.expect_equal(200, result_state.score_breakdown[&"post_quota_bonus"], "result quota bonus row")
	assertions.expect_equal(300, result_state.score_breakdown[&"elite_kills"], "result elite score row")
	assertions.expect_equal(1500, result_state.score_breakdown[&"boss_kills"], "result boss score row")
	assertions.expect_equal(4000, result_state.score_breakdown[&"wave_clears"], "result wave score row")
	assertions.expect_equal(2000, result_state.score_breakdown[&"run_clear"], "result run-clear score row")
	assertions.expect_equal(1755, result_state.score_breakdown[&"equipment"], "result equipment score row")
	assertions.expect_equal(600, result_state.score_breakdown[&"unique_tags"], "result unique score row")
	assertions.expect_equal(500, result_state.score_breakdown[&"skill_levels"], "result skill score row")
	assertions.expect_equal(200, result_state.score_breakdown[&"wild_materials"], "result wild score row")
	_assert_result_equipment(assertions, result_state)
	_assert_skill(assertions, result_state, &"starfall", 3, 0, 0.0)
	_assert_skill(assertions, result_state, &"thousand_blades", 2, 1, 0.0)


func _test_immortal_and_boss(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _catalog(assertions)
	if catalog == null:
		return
	var immortal_result: Dictionary = QaScenarioFactory.build("immortal_100", catalog)
	assertions.expect_true(immortal_result.get("valid", false), "immortal QA fixture valid")
	assertions.expect_true(immortal_result.get("rng_unchanged", false), "immortal QA leaves run RNG streams unchanged")
	assertions.expect_false(immortal_result.get("tutorial_active", true), "immortal QA tutorial inactive")
	if not immortal_result.get("valid", false):
		return
	var immortal_state: RunState = immortal_result["state"] as RunState
	var immortal_simulation: CombatSimulation = immortal_result["simulation"] as CombatSimulation
	assertions.expect_equal(GameTypes.RunPhase.COMBAT, immortal_state.phase, "immortal fixture phase")
	assertions.expect_equal(5, immortal_state.wave_number, "immortal fixture wave")
	assertions.expect_float(100.0, immortal_state.current_hp, "immortal fixture HP")
	assertions.expect_equal(
		&"immortal_breastplate",
		(immortal_state.equipped[GameTypes.EquipmentSlot.BODY] as ItemInstance).unique_id,
		"immortal breastplate equipped",
	)
	assertions.expect_float(
		100.0,
		StatCalculator.effective_damage_reduction_pct(immortal_state.equipped),
		"immortal fixture reaches 100 percent damage reduction",
	)
	_assert_skill(assertions, immortal_state, &"bell_of_retribution", 1, 0, 4.0)
	assertions.expect_equal(1, immortal_simulation.enemy_system.enemy_store.active_count(), "immortal fixture has one tracker")
	var tracker: EnemyEntity = immortal_simulation.enemy_system.enemy_store.get_by_id(0)
	assertions.expect_true(tracker != null and is_inf(tracker.hp), "immortal tracker has infinite fixture HP")
	assertions.expect_true(immortal_simulation.freeze_normal_spawn, "immortal normal spawn stopped")
	assertions.expect_true(immortal_simulation.freeze_countdown, "immortal countdown stopped")
	assertions.expect_true(immortal_simulation.freeze_enemy_ai, "immortal enemy AI stopped")
	assertions.expect_true(immortal_simulation.freeze_enemy_timers, "immortal non-contact timers stopped")
	assertions.expect_true(immortal_simulation.allow_contact_timers_only, "immortal allows only fixture contact timers")
	assertions.expect_equal(immortal_simulation.player_position, tracker.position, "immortal tracker overlaps player")
	assertions.expect_float(tracker.definition.contact_interval, tracker.contact_elapsed, "immortal contact is ready")
	_assert_immortal_equipment(assertions, immortal_state)

	var boss_result: Dictionary = QaScenarioFactory.build("boss_299", catalog)
	assertions.expect_true(boss_result.get("valid", false), "boss boundary QA fixture valid")
	assertions.expect_true(boss_result.get("rng_unchanged", false), "boss QA leaves run RNG streams unchanged")
	assertions.expect_false(boss_result.get("tutorial_active", true), "boss QA tutorial inactive")
	if not boss_result.get("valid", false):
		return
	var boss_state: RunState = boss_result["state"] as RunState
	var boss_simulation: CombatSimulation = boss_result["simulation"] as CombatSimulation
	assertions.expect_equal(GameTypes.RunPhase.COMBAT, boss_state.phase, "boss fixture phase")
	assertions.expect_equal(8, boss_state.wave_number, "boss fixture wave")
	assertions.expect_float(30.0, boss_state.time_remaining, "boss fixture remaining seconds")
	assertions.expect_equal(299, boss_state.non_boss_spawned, "boss fixture non-boss cap")
	assertions.expect_equal(299, boss_state.wave_kills, "boss fixture kill boundary")
	assertions.expect_false(boss_state.boss_defeated, "boss fixture not defeated")
	assertions.expect_equal(1, boss_state.next_entity_id, "boss fixture next entity id")
	assertions.expect_equal(1, boss_simulation.enemy_system.enemy_store.active_count(), "boss fixture has only boss")
	var boss: EnemyEntity = boss_simulation.enemy_system.enemy_store.get_by_id(0)
	assertions.expect_equal(GameTypes.EnemyType.BOSS, boss.enemy_type, "boss fixture entity zero type")
	assertions.expect_equal(Vector2(14.25, 8.25), boss.position, "boss fixture fixed position")
	assertions.expect_float(4500.0, boss.hp, "boss fixture fixed HP")
	assertions.expect_float(4500.0, boss.max_hp, "boss fixture fixed max HP")
	assertions.expect_float(0.0, boss.contact_elapsed, "boss contact timer fixed")
	assertions.expect_float(0.0, boss.special_elapsed, "boss special timer fixed")
	assertions.expect_float(0.0, boss.summon_elapsed, "boss summon timer fixed")
	assertions.expect_float(0.0, boss.telegraph_elapsed, "boss telegraph timer fixed")
	assertions.expect_false(boss.telegraph_active, "boss telegraph inactive")
	assertions.expect_float(5000.0, float(boss_simulation.get("main_weapon_damage_override")), "boss fixture damage override")
	assertions.expect_equal("qa-boss-bow", (boss_state.equipped[GameTypes.EquipmentSlot.MAIN_WEAPON] as ItemInstance).item_id, "boss QA bow equipped")
	assertions.expect_true(boss_state.inventory[0] != null, "boss QA retains wood stick")
	var boss_bow: ItemInstance = boss_state.equipped[GameTypes.EquipmentSlot.MAIN_WEAPON] as ItemInstance
	assertions.expect_equal(GameTypes.Rarity.COMMON, boss_bow.rarity, "boss QA bow Common")
	assertions.expect_equal(GameTypes.MainWeaponType.BOW, boss_bow.main_weapon_type, "boss QA bow type")
	assertions.expect_equal(&"", boss_bow.unique_id, "boss QA bow non-unique")
	assertions.expect_false(boss_bow.locked, "boss QA bow unlocked")
	_assert_single_affix(assertions, boss_bow, &"max_hp", 10.0)
	assertions.expect_equal(
		"i-%016x-00-0000" % QaScenarioFactory.FIXED_SEED,
		boss_state.inventory[0].item_id,
		"boss QA retains exact initial wood stick",
	)
	boss_state.spawn_credit = 3.0
	assertions.expect_equal(
		0,
		boss_simulation.enemy_system.resolve_normal_spawns(boss_simulation.player_position, boss_state.physics_tick).size(),
		"boss QA blocks normal spawns at 299 before boss defeat",
	)
	assertions.expect_equal(299, boss_state.non_boss_spawned, "boss gate preserves pre-defeat spawn count")
	_assert_boss_gate_resume(assertions, boss_state, boss_simulation, boss)


func _catalog(assertions: Variant) -> DefinitionCatalog:
	var catalog := DefinitionCatalog.new()
	assertions.expect_true(catalog.load_and_validate(), "inventory QA DefinitionCatalog valid")
	return catalog if catalog.is_valid else null


func _non_null_count(items: Array[ItemInstance]) -> int:
	var count: int = 0
	for item: ItemInstance in items:
		if item != null:
			count += 1
	return count


func _assert_single_affix(
	assertions: Variant,
	item: ItemInstance,
	affix_id: StringName,
	value: float,
) -> void:
	assertions.expect_equal(1, item.affixes.size(), "%s has one affix" % item.item_id)
	if item.affixes.size() != 1:
		return
	assertions.expect_equal(affix_id, item.affixes[0].affix_id, "%s affix id" % item.item_id)
	assertions.expect_float(value, item.affixes[0].value, "%s affix value" % item.item_id)


func _assert_skill(
	assertions: Variant,
	state: RunState,
	skill_id: StringName,
	level: int,
	slot: int,
	progress: float,
) -> void:
	var skill: SkillState = state.skill_library.get(skill_id, null) as SkillState
	assertions.expect_true(skill != null, "%s skill present" % skill_id)
	if skill == null:
		return
	assertions.expect_equal(level, skill.level, "%s skill level" % skill_id)
	assertions.expect_equal(slot, skill.equipped_slot, "%s equipped slot" % skill_id)
	assertions.expect_float(progress, skill.trigger_progress, "%s trigger progress" % skill_id)


func _assert_matches_normal_fixture_item(
	assertions: Variant,
	catalog: DefinitionCatalog,
	actual: ItemInstance,
) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SeedService.derive(
		QaScenarioFactory.FIXED_SEED,
		StringName("qa-affix:" + actual.item_id),
	)
	var expected: ItemInstance = ItemFactory.create_item(
		QaScenarioFactory.FIXED_SEED,
		actual.item_id,
		actual.slot,
		actual.main_weapon_type,
		actual.rarity,
		&"",
		actual.main_weapon_type,
		rng,
		catalog,
	)
	assertions.expect_true(expected != null, "%s normal fixture reference created" % actual.item_id)
	if expected == null:
		return
	expected.item_seed = SeedService.derive(
		QaScenarioFactory.FIXED_SEED,
		StringName("qa-item:" + actual.item_id),
	)
	expected.display_name = NameGenerator.generate(
		expected.item_seed,
		expected.slot,
		expected.main_weapon_type,
		expected.affixes,
	)
	assertions.expect_equal(expected.display_name, actual.display_name, "%s normal generated name" % actual.item_id)
	assertions.expect_equal(expected.affixes.size(), actual.affixes.size(), "%s normal affix count" % actual.item_id)
	for index: int in range(mini(expected.affixes.size(), actual.affixes.size())):
		assertions.expect_equal(expected.affixes[index].affix_id, actual.affixes[index].affix_id, "%s normal affix id %d" % [actual.item_id, index])
		assertions.expect_float(expected.affixes[index].value, actual.affixes[index].value, "%s normal affix value %d" % [actual.item_id, index])


func _assert_result_equipment(assertions: Variant, state: RunState) -> void:
	var bow: ItemInstance = state.equipped[GameTypes.EquipmentSlot.MAIN_WEAPON] as ItemInstance
	assertions.expect_equal("qa-result-common-bow", bow.item_id, "result exact bow id")
	assertions.expect_equal(GameTypes.EquipmentSlot.MAIN_WEAPON, bow.slot, "result exact bow slot")
	assertions.expect_equal(GameTypes.Rarity.COMMON, bow.rarity, "result exact bow rarity")
	assertions.expect_equal(GameTypes.MainWeaponType.BOW, bow.main_weapon_type, "result exact bow type")
	assertions.expect_equal(&"", bow.unique_id, "result exact bow non-unique")
	_assert_single_affix(assertions, bow, &"max_hp", 10.0)
	var dagger: ItemInstance = state.equipped[GameTypes.EquipmentSlot.SUB_WEAPON] as ItemInstance
	assertions.expect_equal("qa-result-rare-dagger", dagger.item_id, "result exact dagger id")
	assertions.expect_equal(GameTypes.EquipmentSlot.SUB_WEAPON, dagger.slot, "result exact dagger slot")
	assertions.expect_equal(GameTypes.Rarity.RARE, dagger.rarity, "result exact dagger rarity")
	assertions.expect_equal(&"bloodied_dagger", dagger.unique_id, "result exact dagger unique")
	assertions.expect_equal("血塗れの短剣", dagger.display_name, "result exact dagger name")
	_assert_single_affix(assertions, dagger, &"damage_pct", 14.0)
	var body: ItemInstance = state.equipped[GameTypes.EquipmentSlot.BODY] as ItemInstance
	assertions.expect_equal("qa-result-epic-body", body.item_id, "result exact body id")
	assertions.expect_equal(GameTypes.EquipmentSlot.BODY, body.slot, "result exact body slot")
	assertions.expect_equal(GameTypes.Rarity.EPIC, body.rarity, "result exact body rarity")
	assertions.expect_equal(&"", body.unique_id, "result exact body non-unique")
	_assert_affixes(assertions, body, [&"max_hp", &"damage_reduction_pct", &"skill_power_pct"], [30.0, 15.0, 30.0])
	var hands: ItemInstance = state.equipped[GameTypes.EquipmentSlot.HANDS] as ItemInstance
	assertions.expect_equal("qa-result-legendary-hands", hands.item_id, "result exact hands id")
	assertions.expect_equal(GameTypes.EquipmentSlot.HANDS, hands.slot, "result exact hands slot")
	assertions.expect_equal(GameTypes.Rarity.LEGENDARY, hands.rarity, "result exact hands rarity")
	assertions.expect_equal(&"", hands.unique_id, "result exact hands non-unique")
	_assert_affixes(assertions, hands, [&"damage_pct", &"attack_speed_pct", &"pierce", &"area_pct"], [40.0, 40.0, 3.0, 48.0])
	for item: ItemInstance in [bow, dagger, body, hands]:
		assertions.expect_false(item.locked, "%s result item unlocked" % item.item_id)
		assertions.expect_equal(
			SeedService.derive(QaScenarioFactory.FIXED_SEED, StringName("qa-item:" + item.item_id)),
			item.item_seed,
			"%s result QA item seed" % item.item_id,
		)


func _assert_immortal_equipment(assertions: Variant, state: RunState) -> void:
	var body: ItemInstance = state.equipped[GameTypes.EquipmentSlot.BODY] as ItemInstance
	assertions.expect_equal("qa-immortal-body", body.item_id, "immortal body id")
	assertions.expect_equal(GameTypes.Rarity.COMMON, body.rarity, "immortal body rarity")
	assertions.expect_equal(&"immortal_breastplate", body.unique_id, "immortal body unique")
	assertions.expect_false(body.locked, "immortal body unlocked")
	assertions.expect_equal(0, body.affixes.size(), "immortal body has no own reduction affix")
	var head: ItemInstance = state.equipped[GameTypes.EquipmentSlot.HEAD] as ItemInstance
	assertions.expect_equal("qa-immortal-head", head.item_id, "immortal head id")
	assertions.expect_equal(GameTypes.Rarity.LEGENDARY, head.rarity, "immortal head rarity")
	assertions.expect_equal(&"", head.unique_id, "immortal head non-unique")
	assertions.expect_false(head.locked, "immortal head unlocked")
	_assert_affixes(assertions, head, [&"damage_reduction_pct", &"skill_power_pct", &"cooldown_reduction_pct", &"area_pct"], [25.0, 50.0, 24.0, 48.0])
	var hands: ItemInstance = state.equipped[GameTypes.EquipmentSlot.HANDS] as ItemInstance
	assertions.expect_equal("qa-immortal-hands", hands.item_id, "immortal hands id")
	assertions.expect_equal(GameTypes.Rarity.LEGENDARY, hands.rarity, "immortal hands rarity")
	assertions.expect_equal(&"", hands.unique_id, "immortal hands non-unique")
	assertions.expect_false(hands.locked, "immortal hands unlocked")
	_assert_affixes(assertions, hands, [&"damage_reduction_pct", &"damage_pct", &"attack_speed_pct", &"area_pct"], [25.0, 40.0, 40.0, 48.0])
	for item: ItemInstance in [body, head, hands]:
		assertions.expect_equal(
			SeedService.derive(QaScenarioFactory.FIXED_SEED, StringName("qa-item:" + item.item_id)),
			item.item_seed,
			"%s immortal QA item seed" % item.item_id,
		)


func _assert_affixes(
	assertions: Variant,
	item: ItemInstance,
	ids: Array[StringName],
	values: Array[float],
) -> void:
	assertions.expect_equal(ids.size(), item.affixes.size(), "%s affix count" % item.item_id)
	for index: int in range(mini(ids.size(), item.affixes.size())):
		assertions.expect_equal(ids[index], item.affixes[index].affix_id, "%s affix id %d" % [item.item_id, index])
		assertions.expect_float(values[index], item.affixes[index].value, "%s affix value %d" % [item.item_id, index])


func _assert_boss_gate_resume(
	assertions: Variant,
	state: RunState,
	simulation: CombatSimulation,
	boss: EnemyEntity,
) -> void:
	state.current_hp = 1000000.0
	state.max_hp = 1000000.0
	simulation.player_position = boss.position - Vector2(5.0, 0.0)
	simulation.weapon_system.attack_elapsed = 999.0
	for _tick: int in range(45):
		simulation.step(Vector2.ZERO, 1.0 / 60.0)
		if state.boss_defeated:
			break
	assertions.expect_true(state.boss_defeated, "boss QA 5000-damage bow defeats boss")
	assertions.expect_equal(1, state.boss_kills, "boss QA records boss kill")
	assertions.expect_equal(300, state.wave_kills, "boss QA reaches the exact 300-kill boundary")
	assertions.expect_true(state.wave_cleared, "boss QA marks W8 clear after boss defeat")
	var count_before: int = state.non_boss_spawned
	for _tick: int in range(180):
		simulation.step(Vector2.ZERO, 1.0 / 60.0)
		if state.non_boss_spawned > count_before:
			break
	assertions.expect_true(state.non_boss_spawned > count_before, "boss QA normal spawning resumes after boss defeat")
