class_name QaItemBuilder
extends RefCounted


const QA_SEED: int = 20260827


static func weapon(
	catalog: DefinitionCatalog,
	item_id: String,
	weapon_type: GameTypes.WeaponType,
	rarity: GameTypes.Rarity = GameTypes.Rarity.COMMON,
) -> ItemInstance:
	return ItemFactory.create_weapon(QA_SEED, item_id, weapon_type, rarity, catalog)


static func charm(
	catalog: DefinitionCatalog,
	item_id: String,
	rarity: GameTypes.Rarity,
	affix_ids: Array[StringName],
) -> ItemInstance:
	if catalog == null or affix_ids.size() != int(rarity) + 1:
		return null
	var item := ItemInstance.new()
	item.item_id = item_id
	item.item_seed = ItemFactory.derive_item_seed(QA_SEED, item_id)
	item.category = GameTypes.ItemCategory.CHARM
	item.weapon_type = GameTypes.WeaponType.NONE
	item.rarity = rarity
	item.display_name = "QAお守り"
	var seen: Dictionary[StringName, bool] = {}
	for affix_id: StringName in affix_ids:
		if seen.has(affix_id):
			return null
		seen[affix_id] = true
		var definition: AffixDefinition = catalog.affix(affix_id)
		if definition == null or int(rarity) >= definition.values_by_rarity.size():
			return null
		var roll := AffixRoll.new()
		roll.affix_id = affix_id
		roll.value = definition.values_by_rarity[int(rarity)]
		item.affixes.append(roll)
	item.display_name = NameGenerator.generate_charm(item.item_seed, item.affixes)
	return item
