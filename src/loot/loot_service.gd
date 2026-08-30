class_name LootService
extends RefCounted


const ItemFactoryScript := preload("res://src/loot/item_factory.gd")
const ChestVisualPoolScript := preload("res://src/loot/chest_visual_pool.gd")

const CATEGORY_IDS: Array[StringName] = [&"weapon", &"charm"]
const RARITY_IDS: Array[StringName] = [&"common", &"epic", &"legendary", &"rare"]
const WEAPON_TYPE_IDS: Array[StringName] = [&"bow", &"staff", &"sword"]

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
	if not _is_ready() or _state.rng_streams.loot_rng.randf() >= _wave.normal_chest_rate:
		return null
	return _acquire_natural_reward(position, tick, GameTypes.RewardSource.NORMAL)


func acquire_elite_chests(position: Vector2, tick: int) -> Array[RewardRoll]:
	var rewards: Array[RewardRoll] = []
	if not _is_ready():
		return rewards
	for _index: int in range(3):
		rewards.append(_acquire_natural_reward(position, tick, GameTypes.RewardSource.ELITE))
	return rewards


func acquire_boss_chests(position: Vector2, tick: int) -> Array[RewardRoll]:
	var rewards: Array[RewardRoll] = []
	if not _is_ready():
		return rewards
	for _index: int in range(7):
		rewards.append(_acquire_natural_reward(position, tick, GameTypes.RewardSource.BOSS))
	rewards.append(_acquire_reward(
		_make_item_reward(tick, GameTypes.RewardSource.BOSS, false, GameTypes.Rarity.LEGENDARY),
		position,
	))
	return rewards


func ensure_reward_fallback(position: Vector2, tick: int) -> RewardRoll:
	if not _is_ready() or _state.wave_chests != 0:
		return null
	var reward: RewardRoll
	if _state.wave_number == 1:
		reward = _make_weapon_reward(tick, GameTypes.RewardSource.FALLBACK, true)
	else:
		reward = _make_item_reward(tick, GameTypes.RewardSource.FALLBACK)
	return _acquire_reward(reward, position)


func has_current_wave_weapon_guarantee() -> bool:
	if _state == null:
		return false
	for reward: RewardRoll in _state.unopened_rewards:
		if (
			reward != null
			and reward.wave_number == _state.wave_number
			and reward.is_guaranteed_weapon
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


static func select_category(rng: RandomNumberGenerator) -> GameTypes.ItemCategory:
	var selected_id: StringName = WeightedSelector.select(
		rng,
		CATEGORY_IDS,
		PackedFloat64Array([1.0, 1.0]),
	)
	return (
		GameTypes.ItemCategory.CHARM
		if selected_id == &"charm"
		else GameTypes.ItemCategory.WEAPON
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


static func select_weapon_type(rng: RandomNumberGenerator) -> GameTypes.WeaponType:
	return _weapon_type_from_id(WeightedSelector.select(
		rng,
		WEAPON_TYPE_IDS,
		PackedFloat64Array([1.0, 1.0, 1.0]),
	))


func _is_ready() -> bool:
	return (
		_state != null
		and _catalog != null
		and _wave != null
		and _state.rng_streams != null
		and _state.rng_streams.loot_rng != null
	)


func _acquire_natural_reward(
	position: Vector2,
	tick: int,
	source: GameTypes.RewardSource,
) -> RewardRoll:
	if _state.wave_number == 1 and not has_current_wave_weapon_guarantee():
		return _acquire_reward(_make_weapon_reward(tick, source, true), position)
	return _acquire_reward(_make_item_reward(tick, source), position)


func _acquire_reward(reward: RewardRoll, position: Vector2) -> RewardRoll:
	if reward == null:
		return null
	_state.unopened_rewards.append(reward)
	_state.wave_chests += 1
	_state.total_chests += 1
	if _chest_visual_pool != null:
		_chest_visual_pool.acquire(reward.reward_id, position, reward.acquired_tick)
	return reward


func _make_weapon_reward(
	tick: int,
	source: GameTypes.RewardSource,
	is_guaranteed: bool,
) -> RewardRoll:
	return _build_reward(
		tick,
		source,
		is_guaranteed,
		GameTypes.ItemCategory.WEAPON,
		select_rarity(_wave, _state.rng_streams.loot_rng),
	)


func _make_item_reward(
	tick: int,
	source: GameTypes.RewardSource,
	is_guaranteed: bool = false,
	forced_rarity: int = -1,
) -> RewardRoll:
	var rarity: GameTypes.Rarity = (
		forced_rarity as GameTypes.Rarity
		if forced_rarity >= 0
		else select_rarity(_wave, _state.rng_streams.loot_rng)
	)
	return _build_reward(
		tick,
		source,
		is_guaranteed,
		select_category(_state.rng_streams.loot_rng),
		rarity,
	)


func _build_reward(
	tick: int,
	source: GameTypes.RewardSource,
	is_guaranteed: bool,
	category: GameTypes.ItemCategory,
	rarity: GameTypes.Rarity,
) -> RewardRoll:
	var serial: int = _reserve_drop_serial()
	var item_id: String = ItemFactoryScript.make_item_id(
		_state.run_seed,
		_state.wave_number,
		serial,
	)
	var weapon_type: GameTypes.WeaponType = (
		select_weapon_type(_state.rng_streams.loot_rng)
		if category == GameTypes.ItemCategory.WEAPON
		else GameTypes.WeaponType.NONE
	)
	var reward := RewardRoll.new()
	reward.reward_id = ItemFactoryScript.make_reward_id(
		_state.run_seed,
		_state.wave_number,
		serial,
	)
	reward.wave_number = _state.wave_number
	reward.acquired_tick = tick
	reward.is_guaranteed_weapon = is_guaranteed
	reward.source = source
	reward.item = ItemFactoryScript.create_random_item(
		_state.run_seed,
		item_id,
		category,
		weapon_type,
		rarity,
		_state.rng_streams.loot_rng,
		_catalog,
	)
	reward.rarity_for_presentation = rarity
	reward.revealed = false
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


static func _weapon_type_from_id(type_id: StringName) -> GameTypes.WeaponType:
	match type_id:
		&"bow":
			return GameTypes.WeaponType.BOW
		&"staff":
			return GameTypes.WeaponType.STAFF
	return GameTypes.WeaponType.SWORD
