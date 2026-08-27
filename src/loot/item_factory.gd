class_name ItemFactory
extends RefCounted


const DefinitionCatalogScript := preload("res://src/core/definition_catalog.gd")
const NameGeneratorScript := preload("res://src/loot/name_generator.gd")
const SLOT_SPECIFIC_CHANCE: float = 0.75


static func make_item_id(run_seed: int, wave_number: int, drop_serial: int) -> String:
	return "i-%016x-%02d-%04d" % [run_seed, wave_number, drop_serial]


static func make_reward_id(run_seed: int, wave_number: int, drop_serial: int) -> String:
	return "r-%016x-%02d-%04d" % [run_seed, wave_number, drop_serial]


static func derive_item_seed(run_seed: int, item_id: String) -> int:
	return SeedService.derive(run_seed, StringName("item:" + item_id))


static func create_initial_wood_stick(run_seed: int) -> ItemInstance:
	var item := ItemInstance.new()
	item.item_id = make_item_id(run_seed, 0, 0)
	item.item_seed = derive_item_seed(run_seed, item.item_id)
	item.slot = GameTypes.EquipmentSlot.MAIN_WEAPON
	item.main_weapon_type = GameTypes.MainWeaponType.UNCLASSIFIED
	item.rarity = GameTypes.Rarity.COMMON
	item.affixes = []
	item.unique_id = &""
	item.display_name = "木の棒"
	item.locked = false
	return item


static func create_item(
	run_seed: int,
	item_id: String,
	slot: GameTypes.EquipmentSlot,
	main_weapon_type: GameTypes.MainWeaponType,
	rarity: GameTypes.Rarity,
	unique_id: StringName,
	affinity_weapon_type: GameTypes.MainWeaponType,
	affix_rng: RandomNumberGenerator,
	catalog: DefinitionCatalogScript
) -> ItemInstance:
	var item := ItemInstance.new()
	item.item_id = item_id
	item.item_seed = derive_item_seed(run_seed, item_id)
	item.slot = slot
	item.main_weapon_type = (
		main_weapon_type
		if slot == GameTypes.EquipmentSlot.MAIN_WEAPON
		else GameTypes.MainWeaponType.UNCLASSIFIED
	)
	item.rarity = rarity
	item.unique_id = unique_id
	item.affixes = roll_affixes(
		slot,
		rarity,
		unique_id,
		affinity_weapon_type,
		affix_rng,
		catalog
	)
	if unique_id.is_empty():
		item.display_name = NameGeneratorScript.generate(
			item.item_seed,
			item.slot,
			item.main_weapon_type,
			item.affixes
		)
	else:
		var unique_definition: UniqueDefinition = catalog.unique(unique_id)
		item.display_name = unique_definition.display_name if unique_definition != null else ""
	return item


static func roll_affixes(
	slot: GameTypes.EquipmentSlot,
	rarity: GameTypes.Rarity,
	unique_id: StringName,
	affinity_weapon_type: GameTypes.MainWeaponType,
	rng: RandomNumberGenerator,
	catalog: DefinitionCatalogScript
) -> Array[AffixRoll]:
	var rarity_definition: RarityDefinition = catalog.rarity(rarity)
	if rarity_definition == null:
		return []
	var affix_count: int = rarity_definition.affix_count
	if not unique_id.is_empty():
		affix_count = floori(float(affix_count) / 2.0)
	var selected_ids: Array[StringName] = []
	var rolls: Array[AffixRoll] = []
	for _affix_index: int in range(affix_count):
		var prefer_specific: bool = choose_slot_specific_pool(rng)
		var candidates: Array[StringName] = _available_candidates(
			catalog.affix_ids_for_slot(slot) if prefer_specific else catalog.common_affix_ids(),
			selected_ids
		)
		if candidates.is_empty():
			candidates = _available_candidates(
				catalog.common_affix_ids() if prefer_specific else catalog.affix_ids_for_slot(slot),
				selected_ids
			)
		if candidates.is_empty():
			break
		var chosen_id: StringName = select_affix_id(
			candidates,
			affinity_weapon_type,
			rng,
			catalog
		)
		if chosen_id.is_empty():
			break
		var definition: AffixDefinition = catalog.affix(chosen_id)
		if definition == null or rarity >= definition.values_by_rarity.size():
			break
		var roll := AffixRoll.new()
		roll.affix_id = chosen_id
		roll.value = definition.values_by_rarity[rarity]
		rolls.append(roll)
		selected_ids.append(chosen_id)
	return rolls


static func choose_slot_specific_pool(rng: RandomNumberGenerator) -> bool:
	return rng.randf() < SLOT_SPECIFIC_CHANCE


static func select_affix_id(
	candidates: Array[StringName],
	affinity_weapon_type: GameTypes.MainWeaponType,
	rng: RandomNumberGenerator,
	catalog: DefinitionCatalogScript
) -> StringName:
	var weights := PackedFloat64Array()
	for candidate: StringName in candidates:
		var definition: AffixDefinition = catalog.affix(candidate)
		if definition == null:
			return &""
		weights.append(2.0 if affinity_weapon_type in definition.affinity_weapon_types else 1.0)
	return WeightedSelector.select(rng, candidates, weights)


static func select_affix_id_with_value(
	candidates: Array[StringName],
	affinity_weapon_type: GameTypes.MainWeaponType,
	randf_value: float,
	catalog: DefinitionCatalogScript
) -> StringName:
	var weights := PackedFloat64Array()
	for candidate: StringName in candidates:
		var definition: AffixDefinition = catalog.affix(candidate)
		if definition == null:
			return &""
		weights.append(2.0 if affinity_weapon_type in definition.affinity_weapon_types else 1.0)
	return WeightedSelector.select_with_value(candidates, weights, randf_value)


static func _available_candidates(
	pool: Array[StringName],
	selected_ids: Array[StringName]
) -> Array[StringName]:
	var available: Array[StringName] = []
	for affix_id: StringName in pool:
		if not affix_id in selected_ids:
			available.append(affix_id)
	return WeightedSelector.sort_ordinal(available)
