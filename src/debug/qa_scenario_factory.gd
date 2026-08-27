class_name QaScenarioFactory
extends RefCounted


const FIXED_SEED: int = 20260827
const QaItemBuilderScript := preload("res://src/debug/qa_item_builder.gd")
const VALID_IDS: Array[String] = [
	"weapon_bow",
	"weapon_staff",
	"weapon_sword",
	"pre_quota_death",
	"pre_quota_timeout",
	"post_quota_death",
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
	if not fixture_valid:
		return {"valid": false, "rng_unchanged": _rng_states_match(
			state,
			combat_rng_state,
			loot_rng_state,
			fusion_rng_state,
		)}
	simulation.initialize(state, catalog)
	match scenario_id:
		"weapon_bow", "weapon_staff", "weapon_sword":
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


static func _build_weapon_fixture(scenario_id: String, simulation: CombatSimulation) -> void:
	simulation.freeze_enemy_ai = true
	simulation.freeze_enemy_timers = true
	simulation.freeze_normal_spawn = true
	simulation.freeze_countdown = true
	for index: int in range(20):
		var position: Vector2
		match scenario_id:
			"weapon_bow":
				position = Vector2(10.0, (float(index) - 9.5) * 0.08)
			"weapon_staff":
				var staff_angle: float = TAU * float(index) / 20.0
				position = Vector2(10.0, 0.0) + Vector2(cos(staff_angle), sin(staff_angle)) * 2.0
			_:
				var sword_angle: float = deg_to_rad(-55.0 + 110.0 * float(index) / 19.0)
				position = Vector2(cos(sword_angle), sin(sword_angle)) * 2.0
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
