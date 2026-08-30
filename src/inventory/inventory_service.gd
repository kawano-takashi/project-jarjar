class_name InventoryService
extends RefCounted


const KIND_INVENTORY: StringName = &"inventory"
const KIND_OVERFLOW: StringName = &"overflow"
const KIND_EQUIPPED: StringName = &"equipped"
const WEAPON_REQUIRED_MESSAGE: String = "武器は最低1本必要です"
const SORT_COMPLETE_MESSAGE: String = "高レア順に整理しました"


static func first_empty_index(state: RunState) -> int:
	if not _has_valid_inventory(state):
		return -1
	for index: int in range(RunState.INVENTORY_CAPACITY):
		if state.inventory[index] == null:
			return index
	return -1


static func insert_item(state: RunState, item: ItemInstance) -> Dictionary:
	if not _has_valid_inventory(state) or item == null:
		return _failure(&"invalid_item", "追加する装備が不正です")
	var empty_index: int = first_empty_index(state)
	if empty_index >= 0:
		state.inventory[empty_index] = item
		return _location_success(KIND_INVENTORY, empty_index, item)
	state.overflow.append(item)
	return _location_success(KIND_OVERFLOW, state.overflow.size() - 1, item)


static func refill_from_overflow(state: RunState) -> int:
	if not _has_valid_inventory(state):
		return 0
	var moved_count: int = 0
	var empty_index: int = first_empty_index(state)
	while empty_index >= 0 and not state.overflow.is_empty():
		var item: ItemInstance = state.overflow.pop_front() as ItemInstance
		if item == null:
			continue
		state.inventory[empty_index] = item
		moved_count += 1
		empty_index = first_empty_index(state)
	return moved_count


static func sort_inventory_by_rarity(state: RunState) -> Dictionary:
	if not _has_valid_inventory(state):
		return _failure(&"invalid_state", "インベントリ状態が不正です")
	var sorted_items: Array[ItemInstance] = []
	for item: ItemInstance in state.inventory:
		if item != null:
			sorted_items.append(item)
	sorted_items.sort_custom(_inventory_item_less)
	var no_op: bool = true
	for index: int in range(RunState.INVENTORY_CAPACITY):
		var sorted_item: ItemInstance = sorted_items[index] if index < sorted_items.size() else null
		if state.inventory[index] != sorted_item:
			no_op = false
		state.inventory[index] = sorted_item
	return {
		"success": true,
		"error": &"",
		"message": SORT_COMPLETE_MESSAGE,
		"no_op": no_op,
	}


static func find_item(state: RunState, item_id: String) -> Dictionary:
	if state == null or item_id.is_empty():
		return {}
	for slot_value: int in GameTypes.EquipmentSlot.values():
		var item: ItemInstance = state.equipped.get(slot_value, null) as ItemInstance
		if item != null and item.item_id == item_id:
			return _location(KIND_EQUIPPED, slot_value, item)
	for index: int in range(state.inventory.size()):
		var item: ItemInstance = state.inventory[index]
		if item != null and item.item_id == item_id:
			return _location(KIND_INVENTORY, index, item)
	for index: int in range(state.overflow.size()):
		var item: ItemInstance = state.overflow[index]
		if item != null and item.item_id == item_id:
			return _location(KIND_OVERFLOW, index, item)
	return {}


static func equipped_item_ids(state: RunState) -> Array[String]:
	var result: Array[String] = []
	if state == null:
		return result
	for slot_value: int in GameTypes.EquipmentSlot.values():
		var item: ItemInstance = state.equipped.get(slot_value, null) as ItemInstance
		if item != null:
			result.append(item.item_id)
	return result


static func equipped_items(state: RunState) -> Array[ItemInstance]:
	var result: Array[ItemInstance] = []
	if state == null:
		return result
	for slot_value: int in GameTypes.EquipmentSlot.values():
		var item: ItemInstance = state.equipped.get(slot_value, null) as ItemInstance
		if item != null:
			result.append(item)
	return result


static func equipped_weapon_count(state: RunState) -> int:
	var count: int = 0
	if state == null:
		return count
	for slot: GameTypes.EquipmentSlot in GameTypes.weapon_slots():
		var item: ItemInstance = state.equipped.get(slot, null) as ItemInstance
		if item != null and item.category == GameTypes.ItemCategory.WEAPON:
			count += 1
	return count


static func validate_move(
	state: RunState,
	source_kind: StringName,
	source_index: int,
	target_kind: StringName,
	target_index: int,
) -> Dictionary:
	if not _has_valid_inventory(state):
		return _validation_failure(&"invalid_state", "インベントリ状態が不正です")
	if not _is_valid_location(state, source_kind, source_index, false):
		return _validation_failure(&"invalid_source", "移動元が不正です")
	if not _is_valid_location(state, target_kind, target_index, true):
		return _validation_failure(&"invalid_target", "移動先が不正です")
	var source_item: ItemInstance = _item_at(state, source_kind, source_index)
	if source_item == null:
		return _validation_failure(&"empty_source", "移動する装備がありません")
	if source_kind == target_kind and source_index == target_index:
		if source_kind == KIND_EQUIPPED:
			return _validate_unequip(state, source_index as GameTypes.EquipmentSlot)
		return _validation_success()
	var target_item: ItemInstance = _item_at(state, target_kind, target_index)
	if target_kind == KIND_EQUIPPED:
		var target_slot := target_index as GameTypes.EquipmentSlot
		if source_item.category != GameTypes.category_for_slot(target_slot):
			return _validation_failure(&"incompatible_slot", "同じカテゴリの装備枠へだけ移動できます")
	if source_kind == KIND_EQUIPPED:
		var source_slot := source_index as GameTypes.EquipmentSlot
		if target_kind == KIND_EQUIPPED:
			if GameTypes.category_for_slot(source_slot) != GameTypes.category_for_slot(target_index as GameTypes.EquipmentSlot):
				return _validation_failure(&"incompatible_slot", "武器枠とお守り枠は交換できません")
			return _validation_success()
		if target_item != null and target_item.category != GameTypes.category_for_slot(source_slot):
			return _validation_failure(&"incompatible_slot", "交換する装備のカテゴリが一致しません")
		if (
			target_item == null
			and source_item.category == GameTypes.ItemCategory.WEAPON
			and equipped_weapon_count(state) <= 1
		):
			return _validation_failure(&"weapon_required", WEAPON_REQUIRED_MESSAGE)
	if source_kind == KIND_OVERFLOW and target_kind == KIND_OVERFLOW:
		return _validation_failure(&"overflow_reorder", "一時受取欄内では並べ替えできません")
	return _validation_success()


static func apply_move(
	state: RunState,
	source_kind: StringName,
	source_index: int,
	target_kind: StringName,
	target_index: int,
) -> Dictionary:
	var validation: Dictionary = validate_move(
		state,
		source_kind,
		source_index,
		target_kind,
		target_index,
	)
	if not bool(validation["success"]):
		return _failure(StringName(validation["error"]), str(validation["message"]))
	var source_item: ItemInstance = _item_at(state, source_kind, source_index)
	if source_kind == target_kind and source_index == target_index:
		if source_kind == KIND_EQUIPPED:
			return unequip(state, source_index as GameTypes.EquipmentSlot)
		refill_from_overflow(state)
		return _move_success(true, source_item)
	if source_kind == KIND_EQUIPPED and target_kind == KIND_EQUIPPED:
		return _move_equipped_to_equipped(state, source_index, target_index)
	if source_kind == KIND_EQUIPPED:
		return _move_equipped_to_storage(state, source_index, target_kind, target_index)
	if target_kind == KIND_EQUIPPED:
		return _move_storage_to_equipped(state, source_kind, source_index, target_index)
	return _move_storage_to_storage(state, source_kind, source_index, target_kind, target_index)


static func unequip(state: RunState, slot: GameTypes.EquipmentSlot) -> Dictionary:
	var validation: Dictionary = _validate_unequip(state, slot)
	if not bool(validation["success"]):
		return _failure(StringName(validation["error"]), str(validation["message"]))
	var item: ItemInstance = state.equipped.get(slot, null) as ItemInstance
	state.equipped[slot] = null
	var destination: Dictionary = insert_item(state, item)
	_sync_player_stats(state)
	refill_from_overflow(state)
	var result: Dictionary = _move_success(false, item)
	result["target_kind"] = destination.get("kind", &"")
	result["target_index"] = int(destination.get("index", -1))
	return result


static func toggle_lock(state: RunState, item_id: String) -> Dictionary:
	var item: ItemInstance = find_item(state, item_id).get("item", null) as ItemInstance
	if item == null:
		return _failure(&"item_not_found", "対象装備がありません")
	item.locked = not item.locked
	var result: Dictionary = _move_success(false, item)
	result["locked"] = item.locked
	return result


static func compare_item(
	state: RunState,
	item_id: String,
	target_slot: GameTypes.EquipmentSlot,
	catalog: DefinitionCatalog,
) -> Dictionary:
	var item: ItemInstance = find_item(state, item_id).get("item", null) as ItemInstance
	if item == null or item.category != GameTypes.category_for_slot(target_slot):
		return _failure(&"incompatible_slot", "比較先が一致しません")
	var equipped_item: ItemInstance = state.equipped.get(target_slot, null) as ItemInstance
	var deltas: Dictionary[StringName, float] = {}
	var item_values: Dictionary[StringName, float] = _affix_values(item)
	var equipped_values: Dictionary[StringName, float] = _affix_values(equipped_item)
	for affix_id: StringName in StatCalculator.AFFIX_IDS:
		deltas[affix_id] = float(item_values.get(affix_id, 0.0)) - float(equipped_values.get(affix_id, 0.0))
	var result: Dictionary = {
		"success": true,
		"error": &"",
		"message": "",
		"item_id": item.item_id,
		"equipped_item_id": equipped_item.item_id if equipped_item != null else "",
		"target_slot": target_slot,
		"deltas": deltas,
		"rarity_delta": int(item.rarity) - int(equipped_item.rarity) if equipped_item != null else int(item.rarity),
	}
	if item.category == GameTypes.ItemCategory.WEAPON and catalog != null:
		var candidate_definition: WeaponDefinition = catalog.weapon_for_type(item.weapon_type)
		var equipped_definition: WeaponDefinition = (
			catalog.weapon_for_type(equipped_item.weapon_type)
			if equipped_item != null
			else null
		)
		result["candidate_damage"] = candidate_definition.damage_for_rarity(item.rarity) if candidate_definition != null else 0.0
		result["equipped_damage"] = equipped_definition.damage_for_rarity(equipped_item.rarity) if equipped_definition != null else 0.0
	return result


static func auto_select(
	state: RunState,
	rarity: GameTypes.Rarity,
	max_count: int = 3,
) -> PackedStringArray:
	var result := PackedStringArray()
	if not _has_valid_inventory(state) or rarity not in GameTypes.Rarity.values() or max_count <= 0:
		return result
	for item: ItemInstance in _storage_items(state):
		if item == null or item.rarity != rarity or item.locked:
			continue
		result.append(item.item_id)
		if result.size() >= max_count:
			break
	return result


static func discard(state: RunState, item_ids: PackedStringArray) -> Dictionary:
	if not _has_valid_inventory(state):
		return _failure(&"invalid_state", "インベントリ状態が不正です")
	if item_ids.is_empty():
		return _failure(&"empty_selection", "廃棄対象がありません")
	var seen: Dictionary[String, bool] = {}
	var inventory_indices: Array[int] = []
	var overflow_indices: Array[int] = []
	var target_names := PackedStringArray()
	for item_id: String in item_ids:
		if item_id.is_empty() or seen.has(item_id):
			return _failure(&"duplicate_target", "廃棄対象が重複しています")
		seen[item_id] = true
		var location: Dictionary = find_item(state, item_id)
		if location.is_empty():
			return _failure(&"target_missing", "廃棄対象が見つかりません")
		var item: ItemInstance = location["item"] as ItemInstance
		if location["kind"] == KIND_EQUIPPED:
			return _failure(&"equipped", "装備中のアイテムは廃棄できません")
		if item.locked:
			return _failure(&"locked", "ロック中のアイテムは廃棄できません")
		target_names.append(item.display_name)
		if location["kind"] == KIND_INVENTORY:
			inventory_indices.append(int(location["index"]))
		else:
			overflow_indices.append(int(location["index"]))
	for index: int in inventory_indices:
		state.inventory[index] = null
	overflow_indices.sort()
	overflow_indices.reverse()
	for index: int in overflow_indices:
		state.overflow.remove_at(index)
	return {
		"success": true,
		"error": &"",
		"message": "",
		"target_names": target_names,
		"discarded_item_ids": item_ids.duplicate(),
		"refill_count": refill_from_overflow(state),
	}


static func _move_storage_to_storage(
	state: RunState,
	source_kind: StringName,
	source_index: int,
	target_kind: StringName,
	target_index: int,
) -> Dictionary:
	var source_item: ItemInstance = _item_at(state, source_kind, source_index)
	var target_item: ItemInstance = _item_at(state, target_kind, target_index)
	if source_kind == KIND_INVENTORY and target_kind == KIND_INVENTORY:
		state.inventory[source_index] = target_item
		state.inventory[target_index] = source_item
	elif source_kind == KIND_OVERFLOW and target_kind == KIND_INVENTORY:
		state.inventory[target_index] = source_item
		if target_item == null:
			state.overflow.remove_at(source_index)
		else:
			state.overflow[source_index] = target_item
	elif source_kind == KIND_INVENTORY and target_kind == KIND_OVERFLOW:
		state.inventory[source_index] = target_item
		state.overflow[target_index] = source_item
	else:
		return _failure(&"invalid_move", "この移動はできません")
	var result: Dictionary = _move_success(false, source_item)
	result["refill_count"] = refill_from_overflow(state)
	return result


static func _move_storage_to_equipped(
	state: RunState,
	source_kind: StringName,
	source_index: int,
	target_slot_value: int,
) -> Dictionary:
	var target_slot := target_slot_value as GameTypes.EquipmentSlot
	var source_item: ItemInstance = _item_at(state, source_kind, source_index)
	var displaced: ItemInstance = state.equipped.get(target_slot, null) as ItemInstance
	state.equipped[target_slot] = source_item
	if source_kind == KIND_INVENTORY:
		state.inventory[source_index] = displaced
	elif displaced == null:
		state.overflow.remove_at(source_index)
	else:
		state.overflow[source_index] = displaced
	_sync_player_stats(state)
	var result: Dictionary = _move_success(false, source_item, displaced)
	result["refill_count"] = refill_from_overflow(state)
	return result


static func _move_equipped_to_storage(
	state: RunState,
	source_slot_value: int,
	target_kind: StringName,
	target_index: int,
) -> Dictionary:
	var source_slot := source_slot_value as GameTypes.EquipmentSlot
	var source_item: ItemInstance = state.equipped.get(source_slot, null) as ItemInstance
	var target_item: ItemInstance = _item_at(state, target_kind, target_index)
	state.equipped[source_slot] = target_item
	if target_kind == KIND_INVENTORY:
		state.inventory[target_index] = source_item
	else:
		state.overflow[target_index] = source_item
	_sync_player_stats(state)
	var result: Dictionary = _move_success(false, source_item, target_item)
	result["refill_count"] = refill_from_overflow(state)
	return result


static func _move_equipped_to_equipped(
	state: RunState,
	source_slot_value: int,
	target_slot_value: int,
) -> Dictionary:
	var source_slot := source_slot_value as GameTypes.EquipmentSlot
	var target_slot := target_slot_value as GameTypes.EquipmentSlot
	var source_item: ItemInstance = state.equipped.get(source_slot, null) as ItemInstance
	var target_item: ItemInstance = state.equipped.get(target_slot, null) as ItemInstance
	state.equipped[source_slot] = target_item
	state.equipped[target_slot] = source_item
	_sync_player_stats(state)
	return _move_success(false, source_item, target_item)


static func _sync_player_stats(state: RunState) -> void:
	var stats: Dictionary = StatCalculator.aggregate_affixes(state.equipped)
	state.max_hp = StatCalculator.effective_max_hp(stats)
	state.current_hp = minf(state.current_hp, state.max_hp)


static func _storage_items(state: RunState) -> Array[ItemInstance]:
	var result: Array[ItemInstance] = []
	for item: ItemInstance in state.inventory:
		if item != null:
			result.append(item)
	for item: ItemInstance in state.overflow:
		if item != null:
			result.append(item)
	return result


static func _affix_values(item: ItemInstance) -> Dictionary[StringName, float]:
	var result: Dictionary[StringName, float] = {}
	if item == null:
		return result
	for affix: AffixRoll in item.affixes:
		if affix != null:
			result[affix.affix_id] = float(result.get(affix.affix_id, 0.0)) + affix.value
	return result


static func _has_valid_inventory(state: RunState) -> bool:
	if state == null or state.inventory.size() != RunState.INVENTORY_CAPACITY:
		return false
	for item: ItemInstance in state.overflow:
		if item == null:
			return false
	return true


static func _is_valid_location(
	state: RunState,
	kind: StringName,
	index: int,
	allow_empty_inventory: bool,
) -> bool:
	match kind:
		KIND_INVENTORY:
			return index >= 0 and index < RunState.INVENTORY_CAPACITY and (
				allow_empty_inventory or state.inventory[index] != null
			)
		KIND_OVERFLOW:
			return index >= 0 and index < state.overflow.size()
		KIND_EQUIPPED:
			return index in GameTypes.EquipmentSlot.values() and (
				allow_empty_inventory or state.equipped.get(index, null) != null
			)
	return false


static func _item_at(state: RunState, kind: StringName, index: int) -> ItemInstance:
	match kind:
		KIND_INVENTORY:
			return state.inventory[index]
		KIND_OVERFLOW:
			return state.overflow[index]
		KIND_EQUIPPED:
			return state.equipped.get(index, null) as ItemInstance
	return null


static func _validate_unequip(state: RunState, slot: GameTypes.EquipmentSlot) -> Dictionary:
	if not _has_valid_inventory(state) or slot not in GameTypes.EquipmentSlot.values():
		return _validation_failure(&"invalid_slot", "装備枠が不正です")
	var item: ItemInstance = state.equipped.get(slot, null) as ItemInstance
	if item == null:
		return _validation_failure(&"empty_source", "外す装備がありません")
	if item.category == GameTypes.ItemCategory.WEAPON and equipped_weapon_count(state) <= 1:
		return _validation_failure(&"weapon_required", WEAPON_REQUIRED_MESSAGE)
	return _validation_success()


static func _inventory_item_less(left: ItemInstance, right: ItemInstance) -> bool:
	if left.rarity != right.rarity:
		return int(left.rarity) > int(right.rarity)
	if left.category != right.category:
		return int(left.category) < int(right.category)
	if left.category == GameTypes.ItemCategory.WEAPON and left.weapon_type != right.weapon_type:
		return int(left.weapon_type) < int(right.weapon_type)
	if left.display_name != right.display_name:
		return left.display_name < right.display_name
	return left.item_id < right.item_id


static func _validation_success() -> Dictionary:
	return {"success": true, "error": &"", "message": ""}


static func _validation_failure(error: StringName, message: String) -> Dictionary:
	return {"success": false, "error": error, "message": message}


static func _location(kind: StringName, index: int, item: ItemInstance) -> Dictionary:
	return {"kind": kind, "index": index, "slot": index if kind == KIND_EQUIPPED else -1, "item": item}


static func _location_success(kind: StringName, index: int, item: ItemInstance) -> Dictionary:
	var result: Dictionary = _location(kind, index, item)
	result["success"] = true
	result["error"] = &""
	result["message"] = ""
	return result


static func _move_success(no_op: bool, item: ItemInstance, displaced: ItemInstance = null) -> Dictionary:
	return {
		"success": true,
		"error": &"",
		"message": "",
		"no_op": no_op,
		"item_id": item.item_id if item != null else "",
		"displaced_item_id": displaced.item_id if displaced != null else "",
	}


static func _failure(error: StringName, message: String) -> Dictionary:
	return {
		"success": false,
		"error": error,
		"message": message,
		"no_op": true,
		"target_names": PackedStringArray(),
	}
