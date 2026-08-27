class_name FusionCommitService
extends RefCounted


const FusionServiceScript := preload("res://src/inventory/fusion_service.gd")
const InventoryServiceScript := preload("res://src/inventory/inventory_service.gd")
const PREVIEW_RULE_TEXT: String = "通常なら6部位ランダム／ユニーク率4%"


static func preview(
	state: RunState,
	material_ids: PackedStringArray,
	use_wild: bool,
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

	var wild_count: int = 1 if use_wild else 0
	var validation: Dictionary = FusionServiceScript.validate_materials(
		materials,
		wild_count,
		state.wild_material_count,
		InventoryServiceScript.equipped_item_ids(state),
	)
	if not bool(validation.get("valid", false)):
		return _failure(
			validation.get("error", &"invalid_materials") as StringName,
			_validation_message(validation.get("error", &"") as StringName),
		)
	var unique_names: PackedStringArray = validation.get(
		"unique_names",
		PackedStringArray(),
	) as PackedStringArray
	var material_names := PackedStringArray()
	for item: ItemInstance in materials:
		material_names.append(item.display_name)
	var output_rarity := (
		(int(materials[0].rarity) + 1) as GameTypes.Rarity
	)
	return {
		"success": true,
		"valid": true,
		"error": &"",
		"message": "",
		"material_ids": material_ids.duplicate(),
		"material_names": material_names,
		"material_locations": locations,
		"use_wild": use_wild,
		"wild_count": wild_count,
		"output_rarity": output_rarity,
		"rule_text": PREVIEW_RULE_TEXT,
		"needs_unique_confirmation": not unique_names.is_empty(),
		"unique_names": unique_names,
	}


static func commit(
	state: RunState,
	material_ids: PackedStringArray,
	use_wild: bool,
	unique_confirmed: bool,
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
	var preview_result: Dictionary = preview(state, material_ids, use_wild)
	if not bool(preview_result.get("success", false)):
		return preview_result
	if (
		bool(preview_result.get("needs_unique_confirmation", false))
		and not unique_confirmed
	):
		var confirmation: Dictionary = _failure(
			&"unique_confirmation_required",
			"ユニークを失って合成しますか",
		)
		confirmation["needs_unique_confirmation"] = true
		confirmation["unique_names"] = preview_result["unique_names"]
		confirmation["material_ids"] = material_ids.duplicate()
		return confirmation

	var materials: Array[ItemInstance] = []
	for location_value: Variant in preview_result["material_locations"]:
		var location: Dictionary = location_value as Dictionary
		materials.append(location["item"] as ItemInstance)
	var wild_count: int = int(preview_result["wild_count"])
	var rng_state_before: int = state.rng_streams.fusion_rng.state
	var fusion_result: Dictionary = FusionServiceScript.fuse(
		materials,
		wild_count,
		state.wild_material_count,
		InventoryServiceScript.equipped_item_ids(state),
		unique_confirmed,
		state.run_seed,
		state.wave_number,
		state.drop_serial,
		InventoryServiceScript.current_main_weapon_type(state),
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
	state.wild_material_count -= wild_count
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
		&"wild_limit":
			return "ワイルド素材は最大1個です"
		&"wild_unavailable":
			return "ワイルド素材が不足しています"
		&"material_count":
			return "必要な材料数が揃っていません"
		&"rarity_mismatch":
			return "同じレアリティの装備を選んでください"
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
		"needs_unique_confirmation": false,
		"unique_names": PackedStringArray(),
		"use_wild": false,
		"wild_count": 0,
		"rule_text": PREVIEW_RULE_TEXT,
	}
