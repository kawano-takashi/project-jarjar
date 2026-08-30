class_name QaScenarioFactory
extends RefCounted


const FIXED_SEED: int = 20260827
const VALID_IDS: Array[String] = [
	"weapon_wood_stick",
	"weapon_bow",
	"weapon_staff",
	"weapon_sword",
	"weapon_stagger",
	"pre_quota_death",
	"pre_quota_timeout",
	"post_quota_death",
	"reward_controls",
	"inventory_controller",
	"result_controller",
	"boss_299",
]


static func build(scenario_id: String, catalog: DefinitionCatalog) -> Dictionary:
	if catalog == null or not catalog.is_valid or not scenario_id in VALID_IDS:
		return {"valid": false}
	var first_wave: WaveDefinition = catalog.wave(1)
	if first_wave == null:
		return {"valid": false}
	var state: RunState = RunStateFactory.create(FIXED_SEED, first_wave)
	var rng_before: Dictionary = _rng_snapshot(state)
	var fixture_valid: bool = true
	match scenario_id:
		"weapon_bow":
			fixture_valid = _replace_starter_weapon(state, catalog, GameTypes.WeaponType.BOW)
		"weapon_staff":
			fixture_valid = _replace_starter_weapon(state, catalog, GameTypes.WeaponType.STAFF)
		"weapon_sword":
			fixture_valid = _replace_starter_weapon(state, catalog, GameTypes.WeaponType.SWORD)
		"weapon_stagger":
			fixture_valid = _prepare_weapon_stagger_state(state, catalog)
		"reward_controls":
			fixture_valid = _prepare_rewards(state, catalog)
		"inventory_controller":
			fixture_valid = _prepare_inventory(state, catalog)
		"result_controller":
			fixture_valid = _prepare_result(state, catalog)
		"boss_299":
			state.wave_number = 8
			state.time_remaining = catalog.wave(8).duration_seconds
		_:
			pass
	if not fixture_valid:
		return {"valid": false, "rng_unchanged": rng_before == _rng_snapshot(state)}
	var simulation := CombatSimulation.new()
	simulation.initialize(state, catalog)
	match scenario_id:
		"weapon_wood_stick", "weapon_bow", "weapon_staff", "weapon_sword":
			_prepare_weapon_combat(scenario_id, simulation)
		"weapon_stagger":
			_prepare_weapon_stagger(simulation)
		"pre_quota_death":
			_prepare_quota_resolution(simulation, false, true)
		"pre_quota_timeout":
			_prepare_quota_resolution(simulation, false, false)
		"post_quota_death":
			_prepare_quota_resolution(simulation, true, true)
		"reward_controls":
			simulation.enemy_system.enemy_store.clear()
			state.phase = GameTypes.RunPhase.REWARD_REVEAL
		"inventory_controller":
			simulation.enemy_system.enemy_store.clear()
			state.phase = GameTypes.RunPhase.INVENTORY
		"result_controller":
			simulation.enemy_system.enemy_store.clear()
			state.phase = GameTypes.RunPhase.RESULT
		"boss_299":
			state.non_boss_spawned = 299
			simulation.freeze_normal_spawn = true
		_:
			pass
	return {
		"valid": true,
		"state": state,
		"simulation": simulation,
		"tutorial_active": false,
		"rng_unchanged": rng_before == _rng_snapshot(state),
	}


static func _replace_starter_weapon(
	state: RunState,
	catalog: DefinitionCatalog,
	weapon_type: GameTypes.WeaponType,
) -> bool:
	var weapon: ItemInstance = QaItemBuilder.weapon(
		catalog,
		"qa-weapon-%s" % GameTypes.weapon_type_to_key(weapon_type),
		weapon_type,
	)
	if weapon == null:
		return false
	state.inventory[0] = state.equipped[GameTypes.EquipmentSlot.WEAPON_1]
	state.equipped[GameTypes.EquipmentSlot.WEAPON_1] = weapon
	return true


static func _prepare_weapon_stagger_state(
	state: RunState,
	catalog: DefinitionCatalog,
) -> bool:
	state.inventory[0] = state.equipped[GameTypes.EquipmentSlot.WEAPON_1]
	for index: int in range(3):
		var weapon: ItemInstance = QaItemBuilder.weapon(
			catalog,
			"qa-stagger-bow-%d" % index,
			GameTypes.WeaponType.BOW,
		)
		if weapon == null:
			return false
		state.equipped[GameTypes.weapon_slots()[index]] = weapon
	return true


static func _prepare_weapon_combat(
	scenario_id: String,
	simulation: CombatSimulation,
) -> void:
	simulation.freeze_normal_spawn = true
	simulation.freeze_enemy_ai = true
	simulation.freeze_enemy_timers = true
	simulation.freeze_countdown = true
	simulation.weapon_damage_override = 5000.0
	var distance: float = 1.2
	if scenario_id in ["weapon_bow", "weapon_staff"]:
		distance = 8.0
	simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.TRACKER,
		Vector2(distance, 0.0),
	)


static func _prepare_weapon_stagger(simulation: CombatSimulation) -> void:
	simulation.enemy_system.enemy_store.clear()
	simulation.enemy_system.uniform_grid.clear()
	simulation.freeze_normal_spawn = true
	simulation.freeze_enemy_ai = true
	simulation.freeze_enemy_timers = true
	simulation.freeze_countdown = true
	simulation.weapon_damage_override = 0.0
	simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.TRACKER,
		Vector2(8.0, 0.0),
	)


static func _prepare_quota_resolution(
	simulation: CombatSimulation,
	quota_reached: bool,
	player_dead: bool,
) -> void:
	simulation.freeze_normal_spawn = true
	simulation.freeze_enemy_ai = true
	simulation.freeze_enemy_timers = true
	if quota_reached:
		simulation.state.wave_kills = simulation.wave.kill_quota
	if player_dead:
		simulation.state.current_hp = 0.0
	else:
		simulation.state.time_remaining = 1.0 / 60.0


static func _prepare_rewards(state: RunState, catalog: DefinitionCatalog) -> bool:
	state.unopened_rewards.clear()
	var fixtures: Array[Dictionary] = [
		{"type": GameTypes.WeaponType.BOW, "rarity": GameTypes.Rarity.COMMON},
		{"type": GameTypes.WeaponType.STAFF, "rarity": GameTypes.Rarity.RARE},
		{"type": GameTypes.WeaponType.SWORD, "rarity": GameTypes.Rarity.EPIC},
		{"type": GameTypes.WeaponType.BOW, "rarity": GameTypes.Rarity.LEGENDARY},
	]
	for index: int in range(fixtures.size()):
		var fixture: Dictionary = fixtures[index]
		var item: ItemInstance = QaItemBuilder.weapon(
			catalog,
			"qa-reward-item-%d" % index,
			fixture["type"] as GameTypes.WeaponType,
			fixture["rarity"] as GameTypes.Rarity,
		)
		if item == null:
			return false
		state.unopened_rewards.append(_reward_for(item, index))
	state.wave_chests = state.unopened_rewards.size()
	state.total_chests = state.wave_chests
	return true


static func _prepare_inventory(state: RunState, catalog: DefinitionCatalog) -> bool:
	var ids: Array[StringName] = catalog.affix_ids()
	for index: int in range(3):
		var charm: ItemInstance = QaItemBuilder.charm(
			catalog,
			"qa-common-charm-%d" % index,
			GameTypes.Rarity.COMMON,
			[ids[index]],
		)
		if charm == null:
			return false
		state.inventory[index] = charm
	var bow: ItemInstance = QaItemBuilder.weapon(
		catalog,
		"qa-inventory-bow",
		GameTypes.WeaponType.BOW,
		GameTypes.Rarity.RARE,
	)
	var staff: ItemInstance = QaItemBuilder.weapon(
		catalog,
		"qa-inventory-staff",
		GameTypes.WeaponType.STAFF,
		GameTypes.Rarity.EPIC,
	)
	if bow == null or staff == null:
		return false
	state.inventory[3] = bow
	state.inventory[4] = staff
	var locked: ItemInstance = QaItemBuilder.weapon(
		catalog,
		"qa-locked-sword",
		GameTypes.WeaponType.SWORD,
		GameTypes.Rarity.RARE,
	)
	if locked == null:
		return false
	locked.locked = true
	state.inventory[5] = locked
	state.overflow.append(QaItemBuilder.weapon(
		catalog,
		"qa-overflow-bow",
		GameTypes.WeaponType.BOW,
		GameTypes.Rarity.COMMON,
	))
	return state.overflow[0] != null


static func _prepare_result(state: RunState, catalog: DefinitionCatalog) -> bool:
	state.wave_number = 8
	state.cleared_waves = 8
	state.normal_kills = 500
	state.elite_kills = 8
	state.boss_kills = 1
	state.total_kills = 509
	state.total_chests = 24
	state.fusion_count = 3
	var weapons: Array[GameTypes.WeaponType] = [
		GameTypes.WeaponType.BOW,
		GameTypes.WeaponType.STAFF,
		GameTypes.WeaponType.SWORD,
	]
	for index: int in range(3):
		var weapon: ItemInstance = QaItemBuilder.weapon(
			catalog,
			"qa-result-weapon-%d" % index,
			weapons[index],
			GameTypes.Rarity.LEGENDARY,
		)
		if weapon == null:
			return false
		state.equipped[GameTypes.weapon_slots()[index]] = weapon
	var ids: Array[StringName] = catalog.affix_ids()
	for index: int in range(3):
		var charm: ItemInstance = QaItemBuilder.charm(
			catalog,
			"qa-result-charm-%d" % index,
			GameTypes.Rarity.EPIC,
			[ids[index], ids[index + 1], ids[index + 2]],
		)
		if charm == null:
			return false
		state.equipped[GameTypes.charm_slots()[index]] = charm
	state.score_breakdown = ScoreService.calculate(
		state.normal_kills,
		state.elite_kills,
		state.boss_kills,
		state.post_quota_kills,
		state.cleared_waves,
		true,
		InventoryService.equipped_items(state),
		catalog.score_definition(),
	)
	return true


static func _reward_for(item: ItemInstance, index: int) -> RewardRoll:
	var reward := RewardRoll.new()
	reward.reward_id = "qa-reward-%d" % index
	reward.wave_number = 1
	reward.acquired_tick = index
	reward.source = GameTypes.RewardSource.NORMAL
	reward.item = item
	reward.rarity_for_presentation = item.rarity
	return reward


static func _rng_snapshot(state: RunState) -> Dictionary:
	return {
		"combat": state.rng_streams.combat_rng.state,
		"loot": state.rng_streams.loot_rng.state,
		"fusion": state.rng_streams.fusion_rng.state,
	}
