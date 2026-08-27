class_name FusionService
extends RefCounted


const DefinitionCatalogScript := preload("res://src/core/definition_catalog.gd")
const ItemFactoryScript := preload("res://src/loot/item_factory.gd")
const UniqueSelectorScript := preload("res://src/loot/unique_selector.gd")
const UNIQUE_CHANCE: float = 0.04
const SLOT_IDS: Array[StringName] = [
	&"body", &"feet", &"hands", &"head", &"main_weapon", &"sub_weapon",
]
const WEAPON_TYPE_IDS: Array[StringName] = [&"bow", &"staff", &"sword"]


static func validate_materials(
	materials: Array[ItemInstance],
	wild_count: int,
	available_wild_count: int,
	equipped_item_ids: Array[String]
) -> Dictionary:
	if wild_count < 0 or wild_count > 1:
		return _validation_failure(&"wild_limit")
	if available_wild_count < 0 or wild_count > available_wild_count:
		return _validation_failure(&"wild_unavailable")
	var required_items: int = 3 - wild_count
	if materials.size() != required_items:
		return _validation_failure(&"material_count")
	if materials.is_empty():
		return _validation_failure(&"material_count")
	var first: ItemInstance = materials[0]
	if first == null:
		return _validation_failure(&"null_material")
	if first.rarity == GameTypes.Rarity.LEGENDARY:
		return _validation_failure(&"legendary")
	var seen_ids: Dictionary[String, bool] = {}
	var unique_names: PackedStringArray = PackedStringArray()
	for item: ItemInstance in materials:
		if item == null:
			return _validation_failure(&"null_material")
		if seen_ids.has(item.item_id):
			return _validation_failure(&"duplicate_material")
		seen_ids[item.item_id] = true
		if item.rarity != first.rarity:
			return _validation_failure(&"rarity_mismatch")
		if item.rarity == GameTypes.Rarity.LEGENDARY:
			return _validation_failure(&"legendary")
		if item.locked:
			return _validation_failure(&"locked")
		if item.item_id in equipped_item_ids:
			return _validation_failure(&"equipped")
		if not item.unique_id.is_empty():
			unique_names.append(item.display_name)
	return {
		"valid": true,
		"error": &"",
		"unique_names": unique_names,
	}


static func fuse(
	materials: Array[ItemInstance],
	wild_count: int,
	available_wild_count: int,
	equipped_item_ids: Array[String],
	unique_confirmed: bool,
	run_seed: int,
	wave_number: int,
	drop_serial: int,
	current_weapon_type: GameTypes.MainWeaponType,
	fusion_rng: RandomNumberGenerator,
	catalog: DefinitionCatalogScript
) -> Dictionary:
	var validation: Dictionary = validate_materials(
		materials,
		wild_count,
		available_wild_count,
		equipped_item_ids
	)
	if not bool(validation["valid"]):
		return _fusion_failure(StringName(validation["error"]), drop_serial)
	var unique_names: PackedStringArray = validation["unique_names"] as PackedStringArray
	if not unique_names.is_empty() and not unique_confirmed:
		var confirmation_result: Dictionary = _fusion_failure(
			&"unique_confirmation_required",
			drop_serial
		)
		confirmation_result["needs_unique_confirmation"] = true
		confirmation_result["unique_names"] = unique_names
		return confirmation_result

	var output_rarity: GameTypes.Rarity = _next_rarity(materials[0].rarity)
	var output_unique_id: StringName = &""
	var output_slot: GameTypes.EquipmentSlot = GameTypes.EquipmentSlot.MAIN_WEAPON
	var output_weapon_type: GameTypes.MainWeaponType = GameTypes.MainWeaponType.UNCLASSIFIED
	if fusion_rng.randf() < UNIQUE_CHANCE:
		output_unique_id = UniqueSelectorScript.select_won(fusion_rng)
		var unique_definition: UniqueDefinition = catalog.unique(output_unique_id)
		if unique_definition == null:
			return _fusion_failure(&"catalog", drop_serial)
		output_slot = unique_definition.equipment_slot
	else:
		var slot_weights := PackedFloat64Array()
		slot_weights.resize(SLOT_IDS.size())
		slot_weights.fill(1.0)
		var slot_id: StringName = WeightedSelector.select(fusion_rng, SLOT_IDS, slot_weights)
		output_slot = _slot_from_id(slot_id)
		if output_slot == GameTypes.EquipmentSlot.MAIN_WEAPON:
			var weapon_weights := PackedFloat64Array()
			weapon_weights.resize(WEAPON_TYPE_IDS.size())
			weapon_weights.fill(1.0)
			output_weapon_type = _weapon_type_from_id(
				WeightedSelector.select(fusion_rng, WEAPON_TYPE_IDS, weapon_weights)
			)

	var output_item_id: String = ItemFactoryScript.make_item_id(
		run_seed,
		wave_number,
		drop_serial
	)
	var output: ItemInstance = ItemFactoryScript.create_item(
		run_seed,
		output_item_id,
		output_slot,
		output_weapon_type,
		output_rarity,
		output_unique_id,
		current_weapon_type,
		fusion_rng,
		catalog
	)
	var material_ids: PackedStringArray = PackedStringArray()
	for item: ItemInstance in materials:
		material_ids.append(item.item_id)
	return {
		"success": true,
		"error": &"",
		"needs_unique_confirmation": false,
		"unique_names": unique_names,
		"material_ids": material_ids,
		"wild_consumed": wild_count,
		"output_rarity": output_rarity,
		"output": output,
		"drop_serial_before": drop_serial,
		"next_drop_serial": drop_serial + 1,
	}


static func _next_rarity(rarity: GameTypes.Rarity) -> GameTypes.Rarity:
	match rarity:
		GameTypes.Rarity.COMMON:
			return GameTypes.Rarity.RARE
		GameTypes.Rarity.RARE:
			return GameTypes.Rarity.EPIC
		GameTypes.Rarity.EPIC:
			return GameTypes.Rarity.LEGENDARY
	return GameTypes.Rarity.LEGENDARY


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


static func _validation_failure(error: StringName) -> Dictionary:
	return {
		"valid": false,
		"error": error,
		"unique_names": PackedStringArray(),
	}


static func _fusion_failure(error: StringName, drop_serial: int) -> Dictionary:
	return {
		"success": false,
		"error": error,
		"needs_unique_confirmation": false,
		"unique_names": PackedStringArray(),
		"material_ids": PackedStringArray(),
		"wild_consumed": 0,
		"output": null,
		"drop_serial_before": drop_serial,
		"next_drop_serial": drop_serial,
	}
