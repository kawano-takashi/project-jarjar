class_name LootService
extends RefCounted


const ItemFactoryScript := preload("res://src/loot/item_factory.gd")
const UniqueSelectorScript := preload("res://src/loot/unique_selector.gd")
const ChestVisualPoolScript := preload("res://src/loot/chest_visual_pool.gd")

const REWARD_KIND_IDS: Array[StringName] = [&"equipment", &"skill"]
const RARITY_IDS: Array[StringName] = [&"common", &"epic", &"legendary", &"rare"]
const SLOT_IDS: Array[StringName] = [
	&"body", &"feet", &"hands", &"head", &"main_weapon", &"sub_weapon",
]
const WEAPON_TYPE_IDS: Array[StringName] = [&"bow", &"staff", &"sword"]
const SKILL_IDS: Array[StringName] = [
	&"bell_of_retribution",
	&"soul_chain",
	&"starfall",
	&"thousand_blades",
]

var _state: RunState = null
var _catalog: DefinitionCatalog = null
var _wave: WaveDefinition = null
var _chest_visual_pool: ChestVisualPoolScript = null


func initialize(
	state: RunState,
	catalog: DefinitionCatalog,
	p_chest_visual_pool: ChestVisualPoolScript = null,
) -> void:
	_state = state
	_catalog = catalog
	_wave = catalog.wave(state.wave_number) if catalog != null and state != null else null
	_chest_visual_pool = p_chest_visual_pool


func try_normal_drop(position: Vector2, tick: int) -> RewardRoll:
	if not _is_ready():
		return null
	if _state.rng_streams.loot_rng.randf() >= _wave.normal_chest_rate:
		return null
	return _acquire_natural_reward(position, tick)


func acquire_fixed_chests(count: int, position: Vector2, tick: int) -> Array[RewardRoll]:
	var rewards: Array[RewardRoll] = []
	if not _is_ready():
		return rewards
	for _index: int in range(maxi(0, count)):
		rewards.append(_acquire_natural_reward(position, tick))
	return rewards


func ensure_guarantee_fallback(position: Vector2, tick: int) -> RewardRoll:
	if (
		not _is_ready()
		or _state.wave_chests != 0
		or has_current_wave_guarantee()
	):
		return null
	return _acquire_reward(_make_guaranteed_reward(tick), position)


func has_current_wave_guarantee() -> bool:
	if _state == null:
		return false
	for reward: RewardRoll in _state.unopened_rewards:
		if (
			reward != null
			and reward.wave_number == _state.wave_number
			and reward.is_guaranteed_main_weapon
		):
			return true
	return false


func discard_current_wave_rewards() -> int:
	if _state == null:
		return 0
	var discarded_chests: int = _state.wave_chests
	var retained: Array[RewardRoll] = []
	for reward: RewardRoll in _state.unopened_rewards:
		if reward == null or reward.wave_number != _state.wave_number:
			retained.append(reward)
	_state.unopened_rewards = retained
	_state.wave_chests = 0
	_state.total_chests = maxi(0, _state.total_chests - discarded_chests)
	return discarded_chests


static func select_reward_kind(rng: RandomNumberGenerator) -> GameTypes.RewardKind:
	var weights := PackedFloat64Array([0.90, 0.10])
	var selected_id: StringName = WeightedSelector.select(
		rng,
		REWARD_KIND_IDS,
		weights,
	)
	return (
		GameTypes.RewardKind.SKILL
		if selected_id == &"skill"
		else GameTypes.RewardKind.EQUIPMENT
	)


static func select_rarity(
	wave: WaveDefinition,
	rng: RandomNumberGenerator,
) -> GameTypes.Rarity:
	var weights := PackedFloat64Array([
		float(wave.rarity_weights.get(GameTypes.Rarity.COMMON, 0.0)),
		float(wave.rarity_weights.get(GameTypes.Rarity.EPIC, 0.0)),
		float(wave.rarity_weights.get(GameTypes.Rarity.LEGENDARY, 0.0)),
		float(wave.rarity_weights.get(GameTypes.Rarity.RARE, 0.0)),
	])
	return _rarity_from_id(WeightedSelector.select(rng, RARITY_IDS, weights))


static func select_normal_equipment_shape(
	rng: RandomNumberGenerator,
	catalog: DefinitionCatalog,
) -> Dictionary:
	if rng.randf() < UniqueSelectorScript.UNIQUE_CHANCE:
		var unique_id: StringName = UniqueSelectorScript.select_won(rng)
		var unique_definition: UniqueDefinition = catalog.unique(unique_id)
		return {
			"unique_id": unique_id,
			"slot": (
				unique_definition.equipment_slot
				if unique_definition != null
				else GameTypes.EquipmentSlot.MAIN_WEAPON
			),
			"main_weapon_type": GameTypes.MainWeaponType.UNCLASSIFIED,
		}
	var slot: GameTypes.EquipmentSlot = select_non_unique_slot(rng)
	return {
		"unique_id": &"",
		"slot": slot,
		"main_weapon_type": (
			select_main_weapon_type(rng)
			if slot == GameTypes.EquipmentSlot.MAIN_WEAPON
			else GameTypes.MainWeaponType.UNCLASSIFIED
		),
	}


static func select_non_unique_slot(rng: RandomNumberGenerator) -> GameTypes.EquipmentSlot:
	var weights := PackedFloat64Array()
	weights.resize(SLOT_IDS.size())
	weights.fill(1.0)
	return _slot_from_id(WeightedSelector.select(rng, SLOT_IDS, weights))


static func select_main_weapon_type(rng: RandomNumberGenerator) -> GameTypes.MainWeaponType:
	var weights := PackedFloat64Array()
	weights.resize(WEAPON_TYPE_IDS.size())
	weights.fill(1.0)
	return _weapon_type_from_id(WeightedSelector.select(rng, WEAPON_TYPE_IDS, weights))


static func select_guaranteed_main_weapon_type(
	wave_number: int,
	snapshot: GameTypes.MainWeaponType,
	rng: RandomNumberGenerator,
) -> GameTypes.MainWeaponType:
	var weights := PackedFloat64Array([1.0, 1.0, 1.0])
	if wave_number >= 2 and snapshot != GameTypes.MainWeaponType.UNCLASSIFIED:
		weights = PackedFloat64Array([0.25, 0.25, 0.25])
		match snapshot:
			GameTypes.MainWeaponType.BOW:
				weights[0] = 0.50
			GameTypes.MainWeaponType.STAFF:
				weights[1] = 0.50
			GameTypes.MainWeaponType.SWORD:
				weights[2] = 0.50
	return _weapon_type_from_id(WeightedSelector.select(rng, WEAPON_TYPE_IDS, weights))


static func select_skill_id(rng: RandomNumberGenerator) -> StringName:
	var weights := PackedFloat64Array()
	weights.resize(SKILL_IDS.size())
	weights.fill(1.0)
	return WeightedSelector.select(rng, SKILL_IDS, weights)


func _is_ready() -> bool:
	return (
		_state != null
		and _catalog != null
		and _wave != null
		and _state.rng_streams != null
		and _state.rng_streams.loot_rng != null
	)


func _acquire_natural_reward(position: Vector2, tick: int) -> RewardRoll:
	if not has_current_wave_guarantee():
		return _acquire_reward(_make_guaranteed_reward(tick), position)
	return _acquire_reward(_make_normal_reward(tick), position)


func _acquire_reward(reward: RewardRoll, position: Vector2) -> RewardRoll:
	_state.unopened_rewards.append(reward)
	_state.wave_chests += 1
	_state.total_chests += 1
	if _chest_visual_pool != null:
		_chest_visual_pool.acquire(reward.reward_id, position, reward.acquired_tick)
	return reward


func _make_guaranteed_reward(tick: int) -> RewardRoll:
	var serial: int = _reserve_drop_serial()
	var rarity: GameTypes.Rarity = select_rarity(_wave, _state.rng_streams.loot_rng)
	var weapon_type: GameTypes.MainWeaponType = select_guaranteed_main_weapon_type(
		_state.wave_number,
		_state.wave_main_weapon_type,
		_state.rng_streams.loot_rng,
	)
	var item_id: String = ItemFactoryScript.make_item_id(
		_state.run_seed,
		_state.wave_number,
		serial,
	)
	var item: ItemInstance = ItemFactoryScript.create_item(
		_state.run_seed,
		item_id,
		GameTypes.EquipmentSlot.MAIN_WEAPON,
		weapon_type,
		rarity,
		&"",
		_state.wave_main_weapon_type,
		_state.rng_streams.loot_rng,
		_catalog,
	)
	var reward := RewardRoll.new()
	reward.reward_id = ItemFactoryScript.make_reward_id(
		_state.run_seed,
		_state.wave_number,
		serial,
	)
	reward.wave_number = _state.wave_number
	reward.acquired_tick = tick
	reward.is_guaranteed_main_weapon = true
	reward.kind = GameTypes.RewardKind.EQUIPMENT
	reward.equipment = item
	reward.skill_id = &""
	reward.rarity_for_presentation = rarity
	reward.revealed = false
	return reward


func _make_normal_reward(tick: int) -> RewardRoll:
	var serial: int = _reserve_drop_serial()
	var reward := RewardRoll.new()
	reward.reward_id = ItemFactoryScript.make_reward_id(
		_state.run_seed,
		_state.wave_number,
		serial,
	)
	reward.wave_number = _state.wave_number
	reward.acquired_tick = tick
	reward.is_guaranteed_main_weapon = false
	reward.kind = select_reward_kind(_state.rng_streams.loot_rng)
	reward.revealed = false
	if reward.kind == GameTypes.RewardKind.SKILL:
		reward.equipment = null
		reward.skill_id = select_skill_id(_state.rng_streams.loot_rng)
		reward.rarity_for_presentation = -1
		return reward

	var rarity: GameTypes.Rarity = select_rarity(_wave, _state.rng_streams.loot_rng)
	var shape: Dictionary = select_normal_equipment_shape(
		_state.rng_streams.loot_rng,
		_catalog,
	)
	var item_id: String = ItemFactoryScript.make_item_id(
		_state.run_seed,
		_state.wave_number,
		serial,
	)
	reward.equipment = ItemFactoryScript.create_item(
		_state.run_seed,
		item_id,
		shape["slot"] as GameTypes.EquipmentSlot,
		shape["main_weapon_type"] as GameTypes.MainWeaponType,
		rarity,
		shape["unique_id"] as StringName,
		_state.wave_main_weapon_type,
		_state.rng_streams.loot_rng,
		_catalog,
	)
	reward.skill_id = &""
	reward.rarity_for_presentation = rarity
	return reward


func _reserve_drop_serial() -> int:
	var serial: int = _state.drop_serial
	_state.drop_serial += 1
	return serial


static func _rarity_from_id(rarity_id: StringName) -> GameTypes.Rarity:
	match rarity_id:
		&"rare":
			return GameTypes.Rarity.RARE
		&"epic":
			return GameTypes.Rarity.EPIC
		&"legendary":
			return GameTypes.Rarity.LEGENDARY
	return GameTypes.Rarity.COMMON


static func _slot_from_id(slot_id: StringName) -> GameTypes.EquipmentSlot:
	match slot_id:
		&"main_weapon":
			return GameTypes.EquipmentSlot.MAIN_WEAPON
		&"sub_weapon":
			return GameTypes.EquipmentSlot.SUB_WEAPON
		&"head":
			return GameTypes.EquipmentSlot.HEAD
		&"body":
			return GameTypes.EquipmentSlot.BODY
		&"hands":
			return GameTypes.EquipmentSlot.HANDS
	return GameTypes.EquipmentSlot.FEET


static func _weapon_type_from_id(type_id: StringName) -> GameTypes.MainWeaponType:
	match type_id:
		&"bow":
			return GameTypes.MainWeaponType.BOW
		&"staff":
			return GameTypes.MainWeaponType.STAFF
	return GameTypes.MainWeaponType.SWORD
