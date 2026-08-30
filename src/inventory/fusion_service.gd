class_name FusionService
extends RefCounted


const DefinitionCatalogScript := preload("res://src/core/definition_catalog.gd")
const ItemFactoryScript := preload("res://src/loot/item_factory.gd")
const LootServiceScript := preload("res://src/loot/loot_service.gd")


static func validate_materials(
	materials: Array[ItemInstance],
	equipped_item_ids: Array[String],
) -> Dictionary:
	if materials.size() != 3:
		return _validation_failure(&"material_count")
	var first: ItemInstance = materials[0]
	if first == null:
		return _validation_failure(&"null_material")
	if first.rarity == GameTypes.Rarity.LEGENDARY:
		return _validation_failure(&"legendary")
	if first.rarity not in [
		GameTypes.Rarity.COMMON,
		GameTypes.Rarity.RARE,
		GameTypes.Rarity.EPIC,
	]:
		return _validation_failure(&"rarity")
	var seen_ids: Dictionary[String, bool] = {}
	for item: ItemInstance in materials:
		if item == null:
			return _validation_failure(&"null_material")
		if seen_ids.has(item.item_id):
			return _validation_failure(&"duplicate_material")
		seen_ids[item.item_id] = true
		if item.rarity != first.rarity:
			return _validation_failure(&"rarity_mismatch")
		if item.locked:
			return _validation_failure(&"locked")
		if item.item_id in equipped_item_ids:
			return _validation_failure(&"equipped")
	return {"valid": true, "error": &""}


static func fuse(
	materials: Array[ItemInstance],
	equipped_item_ids: Array[String],
	run_seed: int,
	wave_number: int,
	drop_serial: int,
	fusion_rng: RandomNumberGenerator,
	catalog: DefinitionCatalogScript,
) -> Dictionary:
	var validation: Dictionary = validate_materials(materials, equipped_item_ids)
	if not bool(validation["valid"]):
		return _fusion_failure(StringName(validation["error"]), drop_serial)
	var output_rarity: GameTypes.Rarity = _next_rarity(materials[0].rarity)
	var category: GameTypes.ItemCategory = LootServiceScript.select_category(fusion_rng)
	var weapon_type: GameTypes.WeaponType = (
		LootServiceScript.select_weapon_type(fusion_rng)
		if category == GameTypes.ItemCategory.WEAPON
		else GameTypes.WeaponType.NONE
	)
	var output_item_id: String = ItemFactoryScript.make_item_id(
		run_seed,
		wave_number,
		drop_serial,
	)
	var output: ItemInstance = ItemFactoryScript.create_random_item(
		run_seed,
		output_item_id,
		category,
		weapon_type,
		output_rarity,
		fusion_rng,
		catalog,
	)
	var material_ids := PackedStringArray()
	for item: ItemInstance in materials:
		material_ids.append(item.item_id)
	return {
		"success": output != null,
		"error": &"" if output != null else &"output_missing",
		"material_ids": material_ids,
		"output_rarity": output_rarity,
		"output": output,
		"drop_serial_before": drop_serial,
		"next_drop_serial": drop_serial + 1 if output != null else drop_serial,
	}


static func _next_rarity(rarity: GameTypes.Rarity) -> GameTypes.Rarity:
	match rarity:
		GameTypes.Rarity.COMMON:
			return GameTypes.Rarity.RARE
		GameTypes.Rarity.RARE:
			return GameTypes.Rarity.EPIC
	return GameTypes.Rarity.LEGENDARY


static func _validation_failure(error: StringName) -> Dictionary:
	return {"valid": false, "error": error}


static func _fusion_failure(error: StringName, drop_serial: int) -> Dictionary:
	return {
		"success": false,
		"error": error,
		"material_ids": PackedStringArray(),
		"output": null,
		"drop_serial_before": drop_serial,
		"next_drop_serial": drop_serial,
	}
