class_name ItemFactory
extends RefCounted


const DefinitionCatalogScript := preload("res://src/core/definition_catalog.gd")
const NameGeneratorScript := preload("res://src/loot/name_generator.gd")


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
	item.category = GameTypes.ItemCategory.WEAPON
	item.weapon_type = GameTypes.WeaponType.WOOD_STICK
	item.rarity = GameTypes.Rarity.COMMON
	item.affixes = []
	item.display_name = "木の棒"
	item.locked = false
	return item


static func create_weapon(
	run_seed: int,
	item_id: String,
	weapon_type: GameTypes.WeaponType,
	rarity: GameTypes.Rarity,
	catalog: DefinitionCatalogScript,
) -> ItemInstance:
	if catalog == null or rarity not in GameTypes.Rarity.values():
		return null
	var definition: WeaponDefinition = catalog.weapon_for_type(weapon_type)
	if definition == null or not definition.lootable:
		return null
	var item := ItemInstance.new()
	item.item_id = item_id
	item.item_seed = derive_item_seed(run_seed, item_id)
	item.category = GameTypes.ItemCategory.WEAPON
	item.weapon_type = weapon_type
	item.rarity = rarity
	item.affixes = []
	item.display_name = weapon_display_name(weapon_type)
	item.locked = false
	return item


static func create_charm(
	run_seed: int,
	item_id: String,
	rarity: GameTypes.Rarity,
	affix_rng: RandomNumberGenerator,
	catalog: DefinitionCatalogScript,
) -> ItemInstance:
	if (
		catalog == null
		or affix_rng == null
		or rarity not in GameTypes.Rarity.values()
	):
		return null
	var item := ItemInstance.new()
	item.item_id = item_id
	item.item_seed = derive_item_seed(run_seed, item_id)
	item.category = GameTypes.ItemCategory.CHARM
	item.weapon_type = GameTypes.WeaponType.NONE
	item.rarity = rarity
	item.affixes = roll_charm_affixes(rarity, affix_rng, catalog)
	item.display_name = NameGeneratorScript.generate_charm(item.item_seed, item.affixes)
	item.locked = false
	return item


static func create_random_item(
	run_seed: int,
	item_id: String,
	category: GameTypes.ItemCategory,
	weapon_type: GameTypes.WeaponType,
	rarity: GameTypes.Rarity,
	rng: RandomNumberGenerator,
	catalog: DefinitionCatalogScript,
) -> ItemInstance:
	if category == GameTypes.ItemCategory.WEAPON:
		return create_weapon(run_seed, item_id, weapon_type, rarity, catalog)
	return create_charm(run_seed, item_id, rarity, rng, catalog)


static func roll_charm_affixes(
	rarity: GameTypes.Rarity,
	rng: RandomNumberGenerator,
	catalog: DefinitionCatalogScript,
) -> Array[AffixRoll]:
	var rolls: Array[AffixRoll] = []
	if catalog == null or rng == null or rarity not in GameTypes.Rarity.values():
		return rolls
	var rarity_definition: RarityDefinition = catalog.rarity(rarity)
	if rarity_definition == null:
		return rolls
	var available: Array[StringName] = catalog.affix_ids()
	for _affix_index: int in range(rarity_definition.affix_count):
		if available.is_empty():
			break
		var selected_index: int = rng.randi_range(0, available.size() - 1)
		var selected_id: StringName = available[selected_index]
		available.remove_at(selected_index)
		var definition: AffixDefinition = catalog.affix(selected_id)
		if definition == null or int(rarity) >= definition.values_by_rarity.size():
			return []
		var roll := AffixRoll.new()
		roll.affix_id = selected_id
		roll.value = definition.values_by_rarity[int(rarity)]
		rolls.append(roll)
	return rolls


static func weapon_display_name(weapon_type: GameTypes.WeaponType) -> String:
	match weapon_type:
		GameTypes.WeaponType.WOOD_STICK:
			return "木の棒"
		GameTypes.WeaponType.BOW:
			return "弓"
		GameTypes.WeaponType.STAFF:
			return "杖"
		GameTypes.WeaponType.SWORD:
			return "剣"
	return "不明な武器"
