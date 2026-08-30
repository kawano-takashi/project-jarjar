class_name QaScenarioFactory
extends RefCounted


const FIXED_SEED: int = 20260827
const QaItemBuilderScript := preload("res://src/debug/qa_item_builder.gd")
const ItemFactoryScript := preload("res://src/loot/item_factory.gd")
const NameGeneratorScript := preload("res://src/loot/name_generator.gd")
const VALID_IDS: Array[String] = [
	"weapon_wood_stick",
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

static func build(scenario_id: String, catalog: DefinitionCatalog) -> Dictionary:
	if (
		catalog == null
		or not catalog.is_valid
		or catalog.wave(1) == null
		or not scenario_id in VALID_IDS
	):
		return {"valid": false}
	var state: RunState = RunStateFactory.create(FIXED_SEED, catalog.wave(1))
	var combat_rng_state: int = state.rng_streams.combat_rng.state
	var loot_rng_state: int = state.rng_streams.loot_rng.state
	var fusion_rng_state: int = state.rng_streams.fusion_rng.state
	var simulation := CombatSimulation.new()
	var fixture_valid: bool = true
	match scenario_id:
		"weapon_wood_stick":
			fixture_valid = _equip_qa_echo_gauntlet(state, catalog)
		"weapon_bow":
			fixture_valid = _equip_qa_weapon(
				state,
				catalog,
				GameTypes.MainWeaponType.BOW,
				"qa-weapon-bow",
			)
		"weapon_staff":
			fixture_valid = _equip_qa_weapon(
				state,
				catalog,
				GameTypes.MainWeaponType.STAFF,
				"qa-weapon-staff",
			)
		"weapon_sword":
			fixture_valid = _equip_qa_weapon(
				state,
				catalog,
				GameTypes.MainWeaponType.SWORD,
				"qa-weapon-sword",
			)
			if fixture_valid:
				fixture_valid = _equip_qa_echo_gauntlet(state, catalog)
		"inventory_controller":
			fixture_valid = _prepare_inventory_controller(state, catalog)
		"result_controller":
			fixture_valid = _prepare_result_controller(state, catalog)
		"immortal_100":
			fixture_valid = _prepare_immortal_100(state, catalog)
		"boss_299":
			fixture_valid = _prepare_boss_299(state, catalog)
	if not fixture_valid:
		return {"valid": false, "rng_unchanged": _rng_states_match(
			state,
			combat_rng_state,
			loot_rng_state,
			fusion_rng_state,
		)}
	simulation.initialize(state, catalog)
	match scenario_id:
		"weapon_wood_stick", "weapon_bow", "weapon_staff", "weapon_sword":
			_build_weapon_fixture(scenario_id, simulation)
		"pre_quota_death":
			fixture_valid = _build_death_fixture(
				state,
				simulation,
				catalog,
				false,
				"qa-reward-death",
				"qa-item-death",
			)
		"pre_quota_timeout":
			fixture_valid = _build_timeout_fixture(state, simulation, catalog)
		"post_quota_death":
			fixture_valid = _build_death_fixture(
				state,
				simulation,
				catalog,
				true,
				"qa-reward-post-death",
				"qa-item-post-death",
			)
		"reward_controls":
			fixture_valid = _build_reward_controls_fixture(state, catalog)
		"inventory_controller":
			# Inventory fixtures do not own live combat entities.
			simulation.enemy_system.enemy_store.clear()
		"result_controller":
			# Initializing W8 creates its normal boss; RESULT must be presentation-only.
			simulation.enemy_system.enemy_store.clear()
			state.next_entity_id = 0
		"immortal_100":
			fixture_valid = _build_immortal_100_combat(state, simulation)
		"boss_299":
			fixture_valid = _build_boss_299_combat(state, simulation)
	var rng_unchanged: bool = _rng_states_match(
		state,
		combat_rng_state,
		loot_rng_state,
		fusion_rng_state,
	)
	return {
		"valid": fixture_valid and rng_unchanged,
		"state": state,
		"simulation": simulation,
		"tutorial_active": false,
		"rng_unchanged": rng_unchanged,
	}


static func _prepare_inventory_controller(
	state: RunState,
	catalog: DefinitionCatalog,
) -> bool:
	state.wave_number = 7
	state.phase = GameTypes.RunPhase.INVENTORY
	state.wave_cleared = true
	state.cleared_waves = 7
	state.wild_material_count = 1
	state.inventory.fill(null)
	state.overflow.clear()

	for slot_index: int in range(GameTypes.EquipmentSlot.size()):
		var slot: GameTypes.EquipmentSlot = slot_index as GameTypes.EquipmentSlot
		var weapon_type: GameTypes.MainWeaponType = (
			GameTypes.MainWeaponType.BOW
			if slot == GameTypes.EquipmentSlot.MAIN_WEAPON
			else GameTypes.MainWeaponType.UNCLASSIFIED
		)
		var equipped_item: ItemInstance = _make_normal_fixture_item(
			catalog,
			"qa-equipped-%02d" % slot_index,
			slot,
			GameTypes.Rarity.COMMON,
			weapon_type,
			false,
		)
		if equipped_item == null:
			return false
		state.equipped[slot] = equipped_item

	for index: int in range(RunState.INVENTORY_CAPACITY):
		var item: ItemInstance = null
		var slot: GameTypes.EquipmentSlot = (
			index % GameTypes.EquipmentSlot.size()
		) as GameTypes.EquipmentSlot
		var weapon_type := GameTypes.MainWeaponType.UNCLASSIFIED
		if slot == GameTypes.EquipmentSlot.MAIN_WEAPON:
			weapon_type = [
				GameTypes.MainWeaponType.BOW,
				GameTypes.MainWeaponType.STAFF,
				GameTypes.MainWeaponType.SWORD,
			][floori(float(index) / float(GameTypes.EquipmentSlot.size())) % 3]
		var item_id: String = "qa-inventory-%02d" % index
		if index <= 2:
			item = _make_normal_fixture_item_with_affixes(
				catalog,
				item_id,
				slot,
				GameTypes.Rarity.COMMON,
				weapon_type,
				[_make_affix(&"max_hp", 10.0)],
			)
		elif index <= 17:
			item = _make_normal_fixture_item_with_affixes(
				catalog,
				item_id,
				slot,
				GameTypes.Rarity.COMMON,
				weapon_type,
				[_make_affix(&"attack_speed_pct", 8.0)],
			)
		elif index <= 26:
			item = _make_normal_fixture_item(
				catalog,
				item_id,
				slot,
				GameTypes.Rarity.RARE,
				weapon_type,
				false,
			)
		elif index <= 32:
			item = _make_normal_fixture_item(
				catalog,
				item_id,
				slot,
				GameTypes.Rarity.EPIC,
				weapon_type,
				false,
			)
		elif index == 33:
			item = _make_fixed_item(
				catalog,
				item_id,
				GameTypes.EquipmentSlot.SUB_WEAPON,
				GameTypes.Rarity.UNIQUE,
				GameTypes.MainWeaponType.UNCLASSIFIED,
				[[]],
				&"bloodied_dagger",
			)
		elif index == 34:
			item = _make_normal_fixture_item(
				catalog,
				item_id,
				GameTypes.EquipmentSlot.HANDS,
				GameTypes.Rarity.COMMON,
				GameTypes.MainWeaponType.UNCLASSIFIED,
				true,
			)
		else:
			item = _make_normal_fixture_item(
				catalog,
				item_id,
				GameTypes.EquipmentSlot.FEET,
				GameTypes.Rarity.LEGENDARY,
				GameTypes.MainWeaponType.UNCLASSIFIED,
				false,
			)
		if item == null:
			return false
		state.inventory[index] = item

	var overflow_specs: Array[Dictionary] = [
		{"slot": GameTypes.EquipmentSlot.MAIN_WEAPON, "weapon": GameTypes.MainWeaponType.STAFF},
		{"slot": GameTypes.EquipmentSlot.SUB_WEAPON, "weapon": GameTypes.MainWeaponType.UNCLASSIFIED},
		{"slot": GameTypes.EquipmentSlot.HEAD, "weapon": GameTypes.MainWeaponType.UNCLASSIFIED},
		{"slot": GameTypes.EquipmentSlot.BODY, "weapon": GameTypes.MainWeaponType.UNCLASSIFIED},
	]
	for index: int in range(overflow_specs.size()):
		var spec: Dictionary = overflow_specs[index]
		var overflow_item: ItemInstance = _make_normal_fixture_item_with_affixes(
			catalog,
			"qa-overflow-%02d" % index,
			spec["slot"],
			GameTypes.Rarity.COMMON,
			spec["weapon"],
			[_make_affix(&"attack_speed_pct", 8.0)],
		)
		if overflow_item == null:
			return false
		state.overflow.append(overflow_item)

	state.skill_library.clear()
	_add_skill(state, &"starfall", 3, 0)
	_add_skill(state, &"thousand_blades", 2, 1)
	_add_skill(state, &"soul_chain", 1, -1)
	_add_skill(state, &"bell_of_retribution", 3, -1)
	return true


static func _prepare_result_controller(
	state: RunState,
	catalog: DefinitionCatalog,
) -> bool:
	state.wave_number = 8
	state.phase = GameTypes.RunPhase.RESULT
	state.wave_cleared = true
	state.boss_defeated = true
	state.cleared_waves = 8
	state.normal_kills = 100
	state.elite_kills = 1
	state.boss_kills = 1
	state.total_kills = 102
	state.post_quota_kills = 20
	state.total_chests = 160
	state.fusion_count = 12
	state.peak_dps = 999.0
	state.wild_material_count = 2
	state.inventory.fill(null)
	state.overflow.clear()
	for slot_index: int in range(GameTypes.EquipmentSlot.size()):
		var slot: GameTypes.EquipmentSlot = slot_index as GameTypes.EquipmentSlot
		state.equipped[slot] = null

	var items: Array[ItemInstance] = [
		_make_fixed_item(
			catalog,
			"qa-result-common-bow",
			GameTypes.EquipmentSlot.MAIN_WEAPON,
			GameTypes.Rarity.COMMON,
			GameTypes.MainWeaponType.BOW,
			[[_make_affix(&"max_hp", 10.0)]],
		),
		_make_fixed_item(
			catalog,
			"qa-result-rare-dagger",
			GameTypes.EquipmentSlot.SUB_WEAPON,
			GameTypes.Rarity.UNIQUE,
			GameTypes.MainWeaponType.UNCLASSIFIED,
			[[]],
			&"bloodied_dagger",
		),
		_make_fixed_item(
			catalog,
			"qa-result-epic-body",
			GameTypes.EquipmentSlot.BODY,
			GameTypes.Rarity.EPIC,
			GameTypes.MainWeaponType.UNCLASSIFIED,
			[[
				_make_affix(&"max_hp", 30.0),
				_make_affix(&"damage_reduction_pct", 15.0),
				_make_affix(&"skill_power_pct", 30.0),
			]],
		),
		_make_fixed_item(
			catalog,
			"qa-result-legendary-hands",
			GameTypes.EquipmentSlot.HANDS,
			GameTypes.Rarity.LEGENDARY,
			GameTypes.MainWeaponType.UNCLASSIFIED,
			[[
				_make_affix(&"damage_pct", 40.0),
				_make_affix(&"attack_speed_pct", 40.0),
				_make_affix(&"pierce", 3.0),
				_make_affix(&"area_pct", 48.0),
			]],
		),
	]
	for item: ItemInstance in items:
		if item == null:
			return false
		state.equipped[item.slot] = item
	state.skill_library.clear()
	_add_skill(state, &"starfall", 3, 0)
	_add_skill(state, &"thousand_blades", 2, 1)
	state.score_breakdown = ScoreService.calculate(
		state.normal_kills,
		state.elite_kills,
		state.boss_kills,
		state.post_quota_kills,
		state.cleared_waves,
		true,
		items,
		state.skill_library,
		state.wild_material_count,
		catalog.score_definition(),
	)
	return (
		int(state.score_breakdown.get(&"combat_score", -1)) == 9000
		and int(state.score_breakdown.get(&"final_build_score", -1)) == 4210
		and int(state.score_breakdown.get(&"total", -1)) == 13210
	)


static func _prepare_immortal_100(
	state: RunState,
	catalog: DefinitionCatalog,
) -> bool:
	state.wave_number = 5
	state.phase = GameTypes.RunPhase.COMBAT
	state.time_remaining = catalog.wave(5).duration_seconds
	var body: ItemInstance = _make_fixed_item(
		catalog,
		"qa-immortal-body",
		GameTypes.EquipmentSlot.BODY,
		GameTypes.Rarity.UNIQUE,
		GameTypes.MainWeaponType.UNCLASSIFIED,
		[[]],
		&"immortal_breastplate",
	)
	var head: ItemInstance = _make_fixed_item(
		catalog,
		"qa-immortal-head",
		GameTypes.EquipmentSlot.HEAD,
		GameTypes.Rarity.LEGENDARY,
		GameTypes.MainWeaponType.UNCLASSIFIED,
		[[
			_make_affix(&"damage_reduction_pct", 25.0),
			_make_affix(&"skill_power_pct", 50.0),
			_make_affix(&"cooldown_reduction_pct", 24.0),
			_make_affix(&"area_pct", 48.0),
		]],
	)
	var hands: ItemInstance = _make_fixed_item(
		catalog,
		"qa-immortal-hands",
		GameTypes.EquipmentSlot.HANDS,
		GameTypes.Rarity.LEGENDARY,
		GameTypes.MainWeaponType.UNCLASSIFIED,
		[[
			_make_affix(&"damage_reduction_pct", 25.0),
			_make_affix(&"damage_pct", 40.0),
			_make_affix(&"attack_speed_pct", 40.0),
			_make_affix(&"area_pct", 48.0),
		]],
	)
	if body == null or head == null or hands == null:
		return false
	state.equipped[GameTypes.EquipmentSlot.BODY] = body
	state.equipped[GameTypes.EquipmentSlot.HEAD] = head
	state.equipped[GameTypes.EquipmentSlot.HANDS] = hands
	state.skill_library.clear()
	_add_skill(state, &"bell_of_retribution", 1, 0, 4.0)
	return true


static func _prepare_boss_299(
	state: RunState,
	catalog: DefinitionCatalog,
) -> bool:
	state.wave_number = 8
	state.phase = GameTypes.RunPhase.COMBAT
	state.time_remaining = 30.0
	state.wave_kills = 299
	state.non_boss_spawned = 299
	state.boss_defeated = false
	state.inventory.fill(null)
	var bow: ItemInstance = _make_fixed_item(
		catalog,
		"qa-boss-bow",
		GameTypes.EquipmentSlot.MAIN_WEAPON,
		GameTypes.Rarity.COMMON,
		GameTypes.MainWeaponType.BOW,
		[[_make_affix(&"max_hp", 10.0)]],
	)
	if bow == null:
		return false
	state.inventory[0] = state.equipped[GameTypes.EquipmentSlot.MAIN_WEAPON]
	state.equipped[GameTypes.EquipmentSlot.MAIN_WEAPON] = bow
	state.next_entity_id = 0
	return true


static func _build_immortal_100_combat(
	state: RunState,
	simulation: CombatSimulation,
) -> bool:
	simulation.freeze_enemy_ai = true
	simulation.freeze_enemy_timers = true
	simulation.freeze_normal_spawn = true
	simulation.freeze_countdown = true
	simulation.allow_contact_timers_only = true
	var tracker: EnemyEntity = simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.TRACKER,
		simulation.player_position,
	)
	if tracker == null:
		return false
	tracker.hp = INF
	tracker.max_hp = INF
	tracker.contact_elapsed = tracker.definition.contact_interval
	state.current_hp = 100.0
	state.max_hp = 100.0
	return true


static func _build_boss_299_combat(
	state: RunState,
	simulation: CombatSimulation,
) -> bool:
	var boss: EnemyEntity = simulation.enemy_system.enemy_store.get_by_id(0)
	if boss == null or boss.enemy_type != GameTypes.EnemyType.BOSS:
		return false
	boss.position = Vector2(14.25, 8.25)
	boss.hp = 4500.0
	boss.max_hp = 4500.0
	boss.contact_elapsed = 0.0
	boss.special_elapsed = 0.0
	boss.summon_elapsed = 0.0
	boss.telegraph_elapsed = 0.0
	boss.telegraph_active = false
	state.next_entity_id = 1
	simulation.main_weapon_damage_override = 5000.0
	return true


static func _make_normal_fixture_item(
	catalog: DefinitionCatalog,
	item_id: String,
	slot: GameTypes.EquipmentSlot,
	rarity: GameTypes.Rarity,
	weapon_type: GameTypes.MainWeaponType,
	locked: bool,
) -> ItemInstance:
	var affix_rng := RandomNumberGenerator.new()
	affix_rng.seed = SeedService.derive(FIXED_SEED, StringName("qa-affix:" + item_id))
	var item: ItemInstance = ItemFactoryScript.create_normal_item(
		FIXED_SEED,
		item_id,
		slot,
		weapon_type,
		rarity,
		weapon_type,
		affix_rng,
		catalog,
	)
	if item == null:
		return null
	item.item_seed = SeedService.derive(FIXED_SEED, StringName("qa-item:" + item_id))
	item.display_name = NameGeneratorScript.generate(
		item.item_seed,
		item.slot,
		item.main_weapon_type,
		item.affixes,
	)
	item.locked = locked
	return item


static func _make_normal_fixture_item_with_affixes(
	catalog: DefinitionCatalog,
	item_id: String,
	slot: GameTypes.EquipmentSlot,
	rarity: GameTypes.Rarity,
	weapon_type: GameTypes.MainWeaponType,
	fixture_affixes: Array[AffixRoll],
	locked: bool = false,
) -> ItemInstance:
	# These QA rows still travel through ItemFactory with their item-local RNG.
	# The table then replaces the rolled affix payload with its explicitly fixed
	# values so controller expectations stay independent of balance-pool drift.
	var item: ItemInstance = _make_normal_fixture_item(
		catalog,
		item_id,
		slot,
		rarity,
		weapon_type,
		locked,
	)
	if item == null:
		return null
	item.affixes = []
	for source: AffixRoll in fixture_affixes:
		if source == null:
			return null
		var copy := AffixRoll.new()
		copy.affix_id = source.affix_id
		copy.value = source.value
		item.affixes.append(copy)
	item.display_name = NameGeneratorScript.generate(
		item.item_seed,
		item.slot,
		item.main_weapon_type,
		item.affixes,
	)
	return item


static func _make_fixed_item(
	catalog: DefinitionCatalog,
	item_id: String,
	slot: GameTypes.EquipmentSlot,
	rarity: GameTypes.Rarity,
	weapon_type: GameTypes.MainWeaponType,
	affix_groups: Array,
	unique_id: StringName = &"",
	locked: bool = false,
) -> ItemInstance:
	var affixes: Array[AffixRoll] = []
	if not affix_groups.is_empty():
		for value: Variant in affix_groups[0]:
			affixes.append(value as AffixRoll)
	return QaItemBuilderScript.build(
		catalog,
		item_id,
		slot,
		rarity,
		weapon_type,
		affixes,
		unique_id,
		locked,
	)


static func _add_skill(
	state: RunState,
	skill_id: StringName,
	level: int,
	equipped_slot: int,
	progress: float = 0.0,
) -> void:
	var skill := SkillState.new()
	skill.skill_id = skill_id
	skill.level = level
	skill.equipped_slot = equipped_slot
	skill.trigger_progress = progress
	state.skill_library[skill_id] = skill


static func _equip_qa_weapon(
	state: RunState,
	catalog: DefinitionCatalog,
	weapon_type: GameTypes.MainWeaponType,
	item_id: String,
) -> bool:
	var affixes: Array[AffixRoll] = [_make_affix(&"max_hp", 10.0)]
	var weapon: ItemInstance = QaItemBuilderScript.build(
		catalog,
		item_id,
		GameTypes.EquipmentSlot.MAIN_WEAPON,
		GameTypes.Rarity.COMMON,
		weapon_type,
		affixes,
		&"",
		false,
	)
	if weapon == null:
		return false
	var wood_stick: ItemInstance = state.equipped.get(
		GameTypes.EquipmentSlot.MAIN_WEAPON,
		null,
	) as ItemInstance
	state.inventory[0] = wood_stick
	state.equipped[GameTypes.EquipmentSlot.MAIN_WEAPON] = weapon
	return true


static func _equip_qa_echo_gauntlet(
	state: RunState,
	catalog: DefinitionCatalog,
) -> bool:
	var affixes: Array[AffixRoll] = []
	var gauntlet: ItemInstance = QaItemBuilderScript.build(
		catalog,
		"qa-echo-gauntlet",
		GameTypes.EquipmentSlot.HANDS,
		GameTypes.Rarity.UNIQUE,
		GameTypes.MainWeaponType.UNCLASSIFIED,
		affixes,
		&"echo_gauntlet",
		false,
	)
	if gauntlet == null:
		return false
	state.equipped[GameTypes.EquipmentSlot.HANDS] = gauntlet
	return true


static func _build_weapon_fixture(scenario_id: String, simulation: CombatSimulation) -> void:
	simulation.freeze_enemy_ai = true
	simulation.freeze_enemy_timers = true
	simulation.freeze_normal_spawn = true
	simulation.freeze_countdown = true
	if scenario_id in ["weapon_wood_stick", "weapon_sword"]:
		simulation.main_weapon_damage_override = 0.0
	for index: int in range(20):
		var position: Vector2
		match scenario_id:
			"weapon_wood_stick":
				if index == 0:
					position = Vector2(1.0, 0.0)
				else:
					var wood_angle: float = deg_to_rad(
						125.0 + 110.0 * float(index - 1) / 18.0
					)
					position = Vector2(cos(wood_angle), sin(wood_angle)) * 4.0
			"weapon_bow":
				position = Vector2(10.0, (float(index) - 9.5) * 0.08)
			"weapon_staff":
				var staff_angle: float = TAU * float(index) / 20.0
				position = Vector2(10.0, 0.0) + Vector2(cos(staff_angle), sin(staff_angle)) * 2.0
			_:
				if index == 0:
					position = Vector2(1.8, 0.0)
				else:
					var sword_angle: float = deg_to_rad(
						125.0 + 110.0 * float(index - 1) / 18.0
					)
					position = Vector2(cos(sword_angle), sin(sword_angle)) * 4.0
		simulation.spawn_fixture_enemy(GameTypes.EnemyType.TRACKER, position)


static func _build_death_fixture(
	state: RunState,
	simulation: CombatSimulation,
	catalog: DefinitionCatalog,
	post_quota: bool,
	reward_id: String,
	item_id: String,
) -> bool:
	var slot: GameTypes.EquipmentSlot = (
		GameTypes.EquipmentSlot.HANDS
		if post_quota
		else GameTypes.EquipmentSlot.HEAD
	)
	var affix_id: StringName = &"damage_pct" if post_quota else &"skill_power_pct"
	var affix_value: float = 8.0 if post_quota else 10.0
	var reward: RewardRoll = _make_reward(
		reward_id,
		item_id,
		slot,
		affix_id,
		affix_value,
		catalog,
	)
	if reward == null:
		return false
	state.wave_kills = 40 if post_quota else 39
	state.wave_cleared = post_quota
	state.current_hp = 1.0
	state.wave_chests = 1
	simulation.weapon_system.attack_elapsed = 0.0
	simulation.freeze_normal_spawn = true
	var enemy: EnemyEntity = simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.TRACKER,
		simulation.player_position,
	)
	enemy.contact_elapsed = enemy.definition.contact_interval
	state.unopened_rewards.append(reward)
	return true


static func _build_timeout_fixture(
	state: RunState,
	simulation: CombatSimulation,
	catalog: DefinitionCatalog,
) -> bool:
	var reward: RewardRoll = _make_reward(
		"qa-reward-timeout",
		"qa-item-timeout",
		GameTypes.EquipmentSlot.HEAD,
		&"skill_power_pct",
		10.0,
		catalog,
	)
	if reward == null:
		return false
	state.wave_kills = 39
	state.wave_cleared = false
	state.time_remaining = 1.0 / 60.0
	state.wave_chests = 1
	simulation.freeze_normal_spawn = true
	state.unopened_rewards.append(reward)
	return true


static func _make_reward(
	reward_id: String,
	item_id: String,
	slot: GameTypes.EquipmentSlot,
	affix_id: StringName,
	affix_value: float,
	catalog: DefinitionCatalog,
) -> RewardRoll:
	var affixes: Array[AffixRoll] = [_make_affix(affix_id, affix_value)]
	var item: ItemInstance = QaItemBuilderScript.build(
		catalog,
		item_id,
		slot,
		GameTypes.Rarity.COMMON,
		GameTypes.MainWeaponType.UNCLASSIFIED,
		affixes,
		&"",
		false,
	)
	if item == null:
		return null
	var reward := RewardRoll.new()
	reward.reward_id = reward_id
	reward.wave_number = 1
	reward.acquired_tick = 0
	reward.is_guaranteed_main_weapon = false
	reward.kind = GameTypes.RewardKind.EQUIPMENT
	reward.equipment = item
	reward.rarity_for_presentation = GameTypes.Rarity.COMMON
	reward.revealed = false
	return reward


static func _make_affix(affix_id: StringName, value: float) -> AffixRoll:
	var affix := AffixRoll.new()
	affix.affix_id = affix_id
	affix.value = value
	return affix


static func _build_reward_controls_fixture(
	state: RunState,
	catalog: DefinitionCatalog,
) -> bool:
	state.wave_number = 3
	state.phase = GameTypes.RunPhase.REWARD_REVEAL
	state.wave_cleared = true
	state.unopened_rewards.clear()
	var fixtures: Array[Dictionary] = [
		{
			"reward_id": "qa-reward-common-bow",
			"item_id": "qa-item-common-bow",
			"slot": GameTypes.EquipmentSlot.MAIN_WEAPON,
			"weapon_type": GameTypes.MainWeaponType.BOW,
			"rarity": GameTypes.Rarity.COMMON,
			"affixes": [_make_affix(&"max_hp", 10.0)],
		},
		{
			"reward_id": "qa-reward-rare-body",
			"item_id": "qa-item-rare-body",
			"slot": GameTypes.EquipmentSlot.BODY,
			"weapon_type": GameTypes.MainWeaponType.UNCLASSIFIED,
			"rarity": GameTypes.Rarity.RARE,
			"affixes": [
				_make_affix(&"max_hp", 18.0),
				_make_affix(&"damage_reduction_pct", 9.0),
			],
		},
		{
			"reward_id": "qa-reward-epic-hands",
			"item_id": "qa-item-epic-hands",
			"slot": GameTypes.EquipmentSlot.HANDS,
			"weapon_type": GameTypes.MainWeaponType.UNCLASSIFIED,
			"rarity": GameTypes.Rarity.EPIC,
			"affixes": [
				_make_affix(&"damage_pct", 24.0),
				_make_affix(&"attack_speed_pct", 24.0),
				_make_affix(&"area_pct", 30.0),
			],
		},
		{
			"reward_id": "qa-reward-legendary-feet",
			"item_id": "qa-item-legendary-feet",
			"slot": GameTypes.EquipmentSlot.FEET,
			"weapon_type": GameTypes.MainWeaponType.UNCLASSIFIED,
			"rarity": GameTypes.Rarity.LEGENDARY,
			"affixes": [
				_make_affix(&"move_speed_pct", 25.0),
				_make_affix(&"max_hp", 50.0),
				_make_affix(&"damage_reduction_pct", 25.0),
				_make_affix(&"skill_power_pct", 50.0),
			],
		},
		{
			"reward_id": "qa-reward-unique-clock",
			"item_id": "qa-item-unique-clock",
			"slot": GameTypes.EquipmentSlot.SUB_WEAPON,
			"weapon_type": GameTypes.MainWeaponType.UNCLASSIFIED,
			"rarity": GameTypes.Rarity.UNIQUE,
			"affixes": [],
			"unique_id": &"broken_clock",
			"source": GameTypes.RewardSource.BOSS,
		},
	]
	for index: int in fixtures.size():
		var fixture: Dictionary = fixtures[index]
		var affixes: Array[AffixRoll] = []
		for value: Variant in fixture["affixes"]:
			affixes.append(value as AffixRoll)
		var item: ItemInstance = QaItemBuilderScript.build(
			catalog,
			String(fixture["item_id"]),
			fixture["slot"],
			fixture["rarity"],
			fixture["weapon_type"],
			affixes,
			StringName(fixture.get("unique_id", &"")),
			false,
		)
		if item == null:
			return false
		var reward := RewardRoll.new()
		reward.reward_id = String(fixture["reward_id"])
		reward.wave_number = 3
		reward.acquired_tick = index
		reward.is_guaranteed_main_weapon = false
		reward.kind = GameTypes.RewardKind.EQUIPMENT
		reward.source = int(
			fixture.get("source", GameTypes.RewardSource.NORMAL)
		) as GameTypes.RewardSource
		reward.equipment = item
		reward.skill_id = &""
		reward.rarity_for_presentation = int(fixture["rarity"])
		reward.revealed = false
		state.unopened_rewards.append(reward)
	state.wave_chests = state.unopened_rewards.size()
	return true


static func _rng_states_match(
	state: RunState,
	combat_rng_state: int,
	loot_rng_state: int,
	fusion_rng_state: int,
) -> bool:
	return (
		combat_rng_state == state.rng_streams.combat_rng.state
		and loot_rng_state == state.rng_streams.loot_rng.state
		and fusion_rng_state == state.rng_streams.fusion_rng.state
	)
