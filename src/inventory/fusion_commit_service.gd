class_name FusionCommitService
extends RefCounted


const FusionServiceScript := preload("res://src/inventory/fusion_service.gd")
const InventoryServiceScript := preload("res://src/inventory/inventory_service.gd")
const PREVIEW_RULE_TEXT: String = "同レア3個／出力は武器・お守り各50%"


static func preview(
	state: RunState,
	material_ids: PackedStringArray,
) -> Dictionary:
	if state == null or state.inventory.size() != RunState.INVENTORY_CAPACITY:
		return _failure(&"invalid_state", "ラン状態が不正です")
	var materials: Array[ItemInstance] = []
	var locations: Array[Dictionary] = []
	var seen: Dictionary[String, bool] = {}
	for item_id: String in material_ids:
		if item_id.is_empty() or seen.has(item_id):
			return _failure(&"duplicate_material", "合成材料が重複しています")
		seen[item_id] = true
		var location: Dictionary = InventoryServiceScript.find_item(state, item_id)
		if location.is_empty():
			return _failure(&"material_missing", "合成材料が見つかりません")
		if location.get("kind", &"") == InventoryServiceScript.KIND_EQUIPPED:
			return _failure(&"equipped", "装備中のアイテムは材料にできません")
		var item: ItemInstance = location.get("item", null) as ItemInstance
		if item == null:
			return _failure(&"material_missing", "合成材料が見つかりません")
		materials.append(item)
		locations.append(location)
	var validation: Dictionary = FusionServiceScript.validate_materials(
		materials,
		InventoryServiceScript.equipped_item_ids(state),
	)
	if not bool(validation.get("valid", false)):
		var error := validation.get("error", &"invalid_materials") as StringName
		return _failure(error, _validation_message(error))
	var material_names := PackedStringArray()
	for item: ItemInstance in materials:
		material_names.append(item.display_name)
	return {
		"success": true,
		"valid": true,
		"error": &"",
		"message": "",
		"material_ids": material_ids.duplicate(),
		"material_names": material_names,
		"material_locations": locations,
		"output_rarity": (int(materials[0].rarity) + 1) as GameTypes.Rarity,
		"rule_text": PREVIEW_RULE_TEXT,
	}


static func commit(
	state: RunState,
	material_ids: PackedStringArray,
	catalog: DefinitionCatalog,
) -> Dictionary:
	if (
		catalog == null
		or not catalog.is_valid
		or state == null
		or state.rng_streams == null
		or state.rng_streams.fusion_rng == null
	):
		return _failure(&"invalid_catalog", "合成定義を利用できません")
	var preview_result: Dictionary = preview(state, material_ids)
	if not bool(preview_result.get("success", false)):
		return preview_result
	var materials: Array[ItemInstance] = []
	for location_value: Variant in preview_result["material_locations"]:
		var location: Dictionary = location_value as Dictionary
		materials.append(location["item"] as ItemInstance)
	var rng_state_before: int = state.rng_streams.fusion_rng.state
	var fusion_result: Dictionary = FusionServiceScript.fuse(
		materials,
		InventoryServiceScript.equipped_item_ids(state),
		state.run_seed,
		state.wave_number,
		state.drop_serial,
		state.rng_streams.fusion_rng,
		catalog,
	)
	if not bool(fusion_result.get("success", false)):
		state.rng_streams.fusion_rng.state = rng_state_before
		return fusion_result
	var output: ItemInstance = fusion_result.get("output", null) as ItemInstance
	if output == null:
		state.rng_streams.fusion_rng.state = rng_state_before
		return _failure(&"output_missing", "合成結果を生成できません")

	var inventory_indices: Array[int] = []
	var overflow_indices: Array[int] = []
	for location_value: Variant in preview_result["material_locations"]:
		var location: Dictionary = location_value as Dictionary
		if location["kind"] == InventoryServiceScript.KIND_INVENTORY:
			inventory_indices.append(int(location["index"]))
		else:
			overflow_indices.append(int(location["index"]))
	for index: int in inventory_indices:
		state.inventory[index] = null
	overflow_indices.sort()
	overflow_indices.reverse()
	for index: int in overflow_indices:
		state.overflow.remove_at(index)

	var output_kind: StringName
	var output_index: int
	var empty_index: int = InventoryServiceScript.first_empty_index(state)
	if empty_index >= 0:
		state.inventory[empty_index] = output
		output_kind = InventoryServiceScript.KIND_INVENTORY
		output_index = empty_index
	else:
		state.overflow.append(output)
		output_kind = InventoryServiceScript.KIND_OVERFLOW
		output_index = state.overflow.size() - 1
	state.drop_serial = int(fusion_result["next_drop_serial"])
	state.fusion_count += 1
	var refill_count: int = InventoryServiceScript.refill_from_overflow(state)
	fusion_result["preview"] = preview_result
	fusion_result["output_kind"] = output_kind
	fusion_result["output_index"] = output_index
	fusion_result["refill_count"] = refill_count
	fusion_result["fusion_count"] = state.fusion_count
	return fusion_result


static func _validation_message(error: StringName) -> String:
	match error:
		&"material_count":
			return "同じレアリティのアイテムが3個必要です"
		&"rarity_mismatch":
			return "同じレアリティのアイテムを選んでください"
		&"legendary":
			return "Legendaryは合成できません"
		&"locked":
			return "ロック中のアイテムは材料にできません"
		&"equipped":
			return "装備中のアイテムは材料にできません"
	return "合成材料が不正です"


static func _failure(error: StringName, message: String) -> Dictionary:
	return {
		"success": false,
		"valid": false,
		"error": error,
		"message": message,
		"material_ids": PackedStringArray(),
		"material_names": PackedStringArray(),
		"material_locations": [],
		"rule_text": PREVIEW_RULE_TEXT,
	}
