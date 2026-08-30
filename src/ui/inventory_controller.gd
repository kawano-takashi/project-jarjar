class_name InventoryController
extends RefCounted


var state: RunState = null
var catalog: DefinitionCatalog = null
var last_item_focus_id: String = ""
var held_item_source: Dictionary = {}

var fusion_open: bool = false
var fusion_rarity: GameTypes.Rarity = GameTypes.Rarity.COMMON
var fusion_material_ids: PackedStringArray = PackedStringArray()
var fusion_status: String = ""


func initialize(p_state: RunState, p_catalog: DefinitionCatalog) -> void:
	state = p_state
	catalog = p_catalog
	last_item_focus_id = ""
	held_item_source.clear()
	reset_fusion()


func set_last_item_focus(item_id: String) -> void:
	if not item_id.is_empty() and find_item(item_id).get("found", false):
		last_item_focus_id = item_id


func begin_item_lift(source_kind: StringName, source_index: int) -> bool:
	var item: ItemInstance = item_at(source_kind, source_index)
	if item == null:
		return false
	held_item_source = {
		"kind": source_kind,
		"index": source_index,
		"item_id": item.item_id,
	}
	return true


func item_move_request(target_kind: StringName, target_index: int) -> Dictionary:
	if held_item_source.is_empty():
		return {}
	return {
		"source": held_item_source.duplicate(true),
		"target": {"kind": target_kind, "index": target_index},
	}


func cancel_lift() -> void:
	held_item_source.clear()


func complete_lift() -> void:
	cancel_lift()


func open_fusion() -> void:
	fusion_open = true
	fusion_rarity = _initial_fusion_rarity()
	fusion_material_ids = PackedStringArray()
	fusion_status = ""


func reset_fusion() -> void:
	fusion_open = false
	fusion_rarity = GameTypes.Rarity.COMMON
	fusion_material_ids = PackedStringArray()
	fusion_status = ""


func complete_fusion_success(status_text: String) -> void:
	fusion_material_ids = PackedStringArray()
	fusion_status = status_text


func set_fusion_result_status(status_text: String) -> void:
	fusion_status = status_text


func change_fusion_rarity(step: int) -> void:
	var values: Array[GameTypes.Rarity] = [
		GameTypes.Rarity.COMMON,
		GameTypes.Rarity.RARE,
		GameTypes.Rarity.EPIC,
	]
	var index: int = values.find(fusion_rarity)
	index = posmod(index + step, values.size())
	fusion_rarity = values[index]
	fusion_material_ids = PackedStringArray()
	fusion_status = ""


func toggle_fusion_material(item_id: String) -> bool:
	var existing_index: int = fusion_material_ids.find(item_id)
	if existing_index >= 0:
		fusion_material_ids.remove_at(existing_index)
		fusion_status = ""
		return true
	var item: ItemInstance = find_item(item_id).get("item") as ItemInstance
	if not _eligible_fusion_item(item):
		fusion_status = "このアイテムは材料にできません"
		return false
	if fusion_material_ids.size() >= 3:
		fusion_status = "材料枠が埋まっています"
		return false
	fusion_material_ids.append(item_id)
	fusion_status = ""
	return true


func remove_fusion_material(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= fusion_material_ids.size():
		return false
	fusion_material_ids.remove_at(slot_index)
	fusion_status = ""
	return true


func auto_fill_fusion() -> PackedStringArray:
	fusion_material_ids = InventoryService.auto_select(state, fusion_rarity, 3)
	var missing: int = 3 - fusion_material_ids.size()
	fusion_status = "不足 %d件" % missing if missing > 0 else ""
	return fusion_material_ids.duplicate()


func fusion_required_item_count() -> int:
	return 3


func fusion_is_valid() -> bool:
	if not fusion_open or fusion_material_ids.size() != 3:
		return false
	for item_id: String in fusion_material_ids:
		var item: ItemInstance = find_item(item_id).get("item") as ItemInstance
		if not _eligible_fusion_item(item):
			return false
	return true


func fusion_material_names() -> PackedStringArray:
	var result := PackedStringArray()
	for item_id: String in fusion_material_ids:
		var item: ItemInstance = find_item(item_id).get("item") as ItemInstance
		result.append(item.display_name if item != null else item_id)
	return result


func fusion_preview_text() -> String:
	var output_rarity: String = rarity_label(_next_rarity(fusion_rarity))
	var material_names: PackedStringArray = fusion_material_names()
	var material_text: String = "、".join(material_names) if not material_names.is_empty() else "未選択"
	return "材料: %s\n出力: %s\n同レア3個／武器・お守り各50%%" % [material_text, output_rarity]


func find_item(item_id: String) -> Dictionary:
	var location: Dictionary = InventoryService.find_item(state, item_id)
	if location.is_empty():
		return {"found": false}
	location["found"] = true
	return location


func item_at(kind: StringName, index: int) -> ItemInstance:
	if state == null:
		return null
	match kind:
		&"equipped":
			if index >= 0 and index < GameTypes.EquipmentSlot.size():
				return state.equipped.get(index) as ItemInstance
		&"inventory":
			if index >= 0 and index < state.inventory.size():
				return state.inventory[index]
		&"overflow":
			if index >= 0 and index < state.overflow.size():
				return state.overflow[index]
	return null


func all_unequipped_locations() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if state == null:
		return result
	for index: int in range(state.inventory.size()):
		var item: ItemInstance = state.inventory[index]
		if item != null:
			result.append({"kind": &"inventory", "index": index, "item": item})
	for index: int in range(state.overflow.size()):
		result.append({"kind": &"overflow", "index": index, "item": state.overflow[index]})
	return result


func fusion_candidate_locations() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for location: Dictionary in all_unequipped_locations():
		if _eligible_fusion_item(location.get("item") as ItemInstance):
			result.append(location)
	return result


func has_fusion_material_set() -> bool:
	var counts: Dictionary[int, int] = {
		int(GameTypes.Rarity.COMMON): 0,
		int(GameTypes.Rarity.RARE): 0,
		int(GameTypes.Rarity.EPIC): 0,
	}
	for location: Dictionary in all_unequipped_locations():
		var item: ItemInstance = location.get("item") as ItemInstance
		if item == null or item.locked or item.rarity == GameTypes.Rarity.LEGENDARY:
			continue
		var rarity_index: int = int(item.rarity)
		if not counts.has(rarity_index):
			continue
		counts[rarity_index] += 1
		if counts[rarity_index] >= 3:
			return true
	return false


func replace_fusion_material(slot_index: int, item_id: String) -> bool:
	if slot_index < 0 or slot_index >= 3:
		return false
	var item: ItemInstance = find_item(item_id).get("item") as ItemInstance
	if not _eligible_fusion_item(item):
		fusion_status = "このアイテムは材料にできません"
		return false
	var existing_index: int = fusion_material_ids.find(item_id)
	if existing_index == slot_index:
		return true
	if existing_index >= 0 and slot_index < fusion_material_ids.size():
		var displaced_id: String = fusion_material_ids[slot_index]
		fusion_material_ids[slot_index] = item_id
		fusion_material_ids[existing_index] = displaced_id
	elif existing_index >= 0:
		fusion_material_ids.remove_at(existing_index)
		fusion_material_ids.append(item_id)
	elif slot_index < fusion_material_ids.size():
		fusion_material_ids[slot_index] = item_id
	elif fusion_material_ids.size() < 3:
		fusion_material_ids.append(item_id)
	else:
		fusion_status = "材料枠が埋まっています"
		return false
	fusion_status = ""
	return true


func rarity_label(rarity: GameTypes.Rarity) -> String:
	match rarity:
		GameTypes.Rarity.RARE:
			return "RARE"
		GameTypes.Rarity.EPIC:
			return "EPIC"
		GameTypes.Rarity.LEGENDARY:
			return "LEGENDARY"
	return "COMMON"


func debug_state() -> Dictionary:
	return {
		"last_item_focus_id": last_item_focus_id,
		"held_item_source": held_item_source.duplicate(true),
		"fusion_open": fusion_open,
		"fusion_rarity": fusion_rarity,
		"fusion_material_ids": fusion_material_ids.duplicate(),
		"fusion_valid": fusion_is_valid(),
		"fusion_status": fusion_status,
	}


func _initial_fusion_rarity() -> GameTypes.Rarity:
	var item: ItemInstance = find_item(last_item_focus_id).get("item") as ItemInstance
	if item != null and item.rarity in [
		GameTypes.Rarity.COMMON,
		GameTypes.Rarity.RARE,
		GameTypes.Rarity.EPIC,
	]:
		return item.rarity
	return GameTypes.Rarity.COMMON


func _eligible_fusion_item(item: ItemInstance) -> bool:
	return (
		item != null
		and item.rarity == fusion_rarity
		and item.rarity != GameTypes.Rarity.LEGENDARY
		and not item.locked
		and find_item(item.item_id).get("kind", &"") != &"equipped"
	)


func _next_rarity(rarity: GameTypes.Rarity) -> GameTypes.Rarity:
	match rarity:
		GameTypes.Rarity.COMMON:
			return GameTypes.Rarity.RARE
		GameTypes.Rarity.RARE:
			return GameTypes.Rarity.EPIC
	return GameTypes.Rarity.LEGENDARY
