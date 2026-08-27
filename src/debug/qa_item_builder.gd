class_name QaItemBuilder
extends RefCounted


const FIXED_SEED: int = 20260827
const NameGeneratorScript := preload("res://src/loot/name_generator.gd")


static func build(
	catalog: DefinitionCatalog,
	item_id: String,
	slot: GameTypes.EquipmentSlot,
	rarity: GameTypes.Rarity,
	main_weapon_type: GameTypes.MainWeaponType,
	affixes: Array[AffixRoll],
	unique_id: StringName = &"",
	locked: bool = false,
) -> ItemInstance:
	if not _is_valid_request(
		catalog,
		item_id,
		slot,
		rarity,
		main_weapon_type,
		affixes,
		unique_id,
	):
		return null

	var item := ItemInstance.new()
	item.item_id = item_id
	item.item_seed = SeedService.derive(FIXED_SEED, StringName("qa-item:" + item_id))
	item.slot = slot
	item.main_weapon_type = main_weapon_type
	item.rarity = rarity
	item.affixes = _copy_affixes(affixes)
	item.unique_id = unique_id
	item.locked = locked
	if unique_id.is_empty():
		item.display_name = NameGeneratorScript.generate(
			item.item_seed,
			item.slot,
			item.main_weapon_type,
			item.affixes,
		)
	else:
		item.display_name = catalog.unique(unique_id).display_name
	return item


static func _is_valid_request(
	catalog: DefinitionCatalog,
	item_id: String,
	slot: GameTypes.EquipmentSlot,
	rarity: GameTypes.Rarity,
	main_weapon_type: GameTypes.MainWeaponType,
	affixes: Array[AffixRoll],
	unique_id: StringName,
) -> bool:
	if catalog == null or not catalog.is_valid or item_id.is_empty():
		return false
	if slot < 0 or slot >= GameTypes.EquipmentSlot.size():
		return false
	if rarity < 0 or rarity >= GameTypes.Rarity.size():
		return false
	if main_weapon_type < 0 or main_weapon_type >= GameTypes.MainWeaponType.size():
		return false
	if (
		slot != GameTypes.EquipmentSlot.MAIN_WEAPON
		and main_weapon_type != GameTypes.MainWeaponType.UNCLASSIFIED
	):
		return false

	var rarity_definition: RarityDefinition = catalog.rarity(rarity)
	if rarity_definition == null:
		return false
	var expected_affix_count: int = rarity_definition.affix_count
	if not unique_id.is_empty():
		var unique_definition: UniqueDefinition = catalog.unique(unique_id)
		if unique_definition == null or unique_definition.equipment_slot != slot:
			return false
		expected_affix_count = floori(float(expected_affix_count) / 2.0)
	if affixes.size() != expected_affix_count:
		return false

	var seen_ids: Dictionary[StringName, bool] = {}
	for affix: AffixRoll in affixes:
		if affix == null or affix.affix_id.is_empty() or seen_ids.has(affix.affix_id):
			return false
		var definition: AffixDefinition = catalog.affix(affix.affix_id)
		if definition == null or rarity >= definition.values_by_rarity.size():
			return false
		# The common pool is global; otherwise the affix must explicitly support the slot.
		if not definition.in_common_pool and not slot in definition.slot_pool:
			return false
		if not is_finite(affix.value):
			return false
		if affix.value != float(definition.values_by_rarity[rarity]):
			return false
		seen_ids[affix.affix_id] = true
	return true


static func _copy_affixes(source: Array[AffixRoll]) -> Array[AffixRoll]:
	var copies: Array[AffixRoll] = []
	for affix: AffixRoll in source:
		var copy := AffixRoll.new()
		copy.affix_id = affix.affix_id
		copy.value = affix.value
		copies.append(copy)
	return copies
