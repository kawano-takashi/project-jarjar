class_name InventoryService
extends RefCounted


const SkillEquipServiceScript := preload("res://src/skills/skill_equip_service.gd")

const KIND_INVENTORY: StringName = &"inventory"
const KIND_OVERFLOW: StringName = &"overflow"
const KIND_EQUIPPED: StringName = &"equipped"
const MAIN_WEAPON_REQUIRED_MESSAGE: String = (
	"主武器は外せません。別の主武器と交換してください"
)
const SORT_COMPLETE_MESSAGE: String = "高レア順に整理しました"
const SORT_RARITY_ORDER: Array[GameTypes.Rarity] = [
	GameTypes.Rarity.UNIQUE,
	GameTypes.Rarity.LEGENDARY,
	GameTypes.Rarity.EPIC,
	GameTypes.Rarity.RARE,
	GameTypes.Rarity.COMMON,
]


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
	for item: ItemInstance in state.inventory:
		if item != null and item.rarity not in GameTypes.Rarity.values():
			return _failure(&"invalid_rarity", "装備のレアリティが不正です")

	var sorted_items: Array[ItemInstance] = []
	for rarity: GameTypes.Rarity in SORT_RARITY_ORDER:
		for item: ItemInstance in state.inventory:
			if item != null and item.rarity == rarity:
				sorted_items.append(item)

	var no_op: bool = true
	for index: int in range(RunState.INVENTORY_CAPACITY):
		var sorted_item: ItemInstance = (
			sorted_items[index]
			if index < sorted_items.size()
			else null
		)
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
		var slot := slot_value as GameTypes.EquipmentSlot
		var equipped_item: ItemInstance = state.equipped.get(slot, null) as ItemInstance
		if equipped_item != null and equipped_item.item_id == item_id:
			return _location(KIND_EQUIPPED, slot_value, equipped_item)
	for index: int in range(state.inventory.size()):
		var inventory_item: ItemInstance = state.inventory[index]
		if inventory_item != null and inventory_item.item_id == item_id:
			return _location(KIND_INVENTORY, index, inventory_item)
	for index: int in range(state.overflow.size()):
		var overflow_item: ItemInstance = state.overflow[index]
		if overflow_item != null and overflow_item.item_id == item_id:
			return _location(KIND_OVERFLOW, index, overflow_item)
	return {}


static func equipped_item_ids(state: RunState) -> Array[String]:
	var result: Array[String] = []
	if state == null:
		return result
	for slot_value: int in GameTypes.EquipmentSlot.values():
		var item: ItemInstance = state.equipped.get(
			slot_value as GameTypes.EquipmentSlot,
			null,
		) as ItemInstance
		if item != null:
			result.append(item.item_id)
	return result


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
			return _validate_unequip(
				state,
				source_index as GameTypes.EquipmentSlot,
			)
		return _validation_success()

	if source_kind == KIND_EQUIPPED:
		if target_kind == KIND_EQUIPPED:
			return _validation_failure(&"incompatible_slot", "別の装備枠へは移動できません")
		var target_item: ItemInstance = _item_at(state, target_kind, target_index)
		if (
			target_item == null
			and source_index == GameTypes.EquipmentSlot.MAIN_WEAPON
		):
			return _validation_failure(&"main_weapon_required", MAIN_WEAPON_REQUIRED_MESSAGE)
		if target_item != null and target_item.slot != source_index:
			return _validation_failure(&"incompatible_slot", "交換先の装備種別が一致しません")
		return _validation_success()
	if target_kind == KIND_EQUIPPED:
		if source_item.slot != target_index:
			return _validation_failure(&"incompatible_slot", "対応する装備枠へだけ装備できます")
		return _validation_success()
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
		return _failure(
			StringName(validation["error"]),
			str(validation["message"]),
		)
	var source_item: ItemInstance = _item_at(state, source_kind, source_index)
	if source_kind == target_kind and source_index == target_index:
		if source_kind == KIND_EQUIPPED:
			return unequip(state, source_index as GameTypes.EquipmentSlot)
		refill_from_overflow(state)
		return _move_success(true, source_item)

	if source_kind == KIND_EQUIPPED:
		return _move_equipped_to_storage(
			state,
			source_index,
			target_kind,
			target_index,
		)
	if target_kind == KIND_EQUIPPED:
		return _move_storage_to_equipped(
			state,
			source_kind,
			source_index,
			target_index,
		)
	return _move_storage_to_storage(
		state,
		source_kind,
		source_index,
		target_kind,
		target_index,
	)


static func unequip(state: RunState, slot: GameTypes.EquipmentSlot) -> Dictionary:
	var validation: Dictionary = _validate_unequip(state, slot)
	if not bool(validation["success"]):
		return _failure(
			StringName(validation["error"]),
			str(validation["message"]),
		)
	var item: ItemInstance = state.equipped.get(slot, null) as ItemInstance
	state.equipped[slot] = null
	var destination: Dictionary = insert_item(state, item)
	_sync_equipment_side_effects(state)
	refill_from_overflow(state)
	var result: Dictionary = _move_success(false, item)
	result["target_kind"] = destination.get("kind", &"")
	result["target_index"] = int(destination.get("index", -1))
	return result


static func toggle_lock(state: RunState, item_id: String) -> Dictionary:
	var location: Dictionary = find_item(state, item_id)
	var item: ItemInstance = location.get("item", null) as ItemInstance
	if item == null:
		return _failure(&"item_not_found", "対象装備がありません")
	item.locked = not item.locked
	var result: Dictionary = _move_success(false, item)
	result["locked"] = item.locked
	return result


static func compare_item(state: RunState, item_id: String) -> Dictionary:
	var location: Dictionary = find_item(state, item_id)
	var item: ItemInstance = location.get("item", null) as ItemInstance
	if item == null:
		return _failure(&"item_not_found", "比較する装備がありません")
	var equipped_item: ItemInstance = state.equipped.get(item.slot, null) as ItemInstance
	var candidate_values: Dictionary[StringName, float] = _affix_values(item)
	var equipped_values: Dictionary[StringName, float] = _affix_values(equipped_item)
	var deltas: Dictionary[StringName, float] = {}
	var improved := PackedStringArray()
	var reduced := PackedStringArray()
	for affix_id: StringName in StatCalculator.AFFIX_IDS:
		var delta: float = (
			float(candidate_values.get(affix_id, 0.0))
			- float(equipped_values.get(affix_id, 0.0))
		)
		deltas[affix_id] = delta
		if delta > 0.0:
			improved.append(String(affix_id))
		elif delta < 0.0:
			reduced.append(String(affix_id))
	return {
		"success": true,
		"error": &"",
		"message": "",
		"item_id": item.item_id,
		"equipped_item_id": equipped_item.item_id if equipped_item != null else "",
		"slot": item.slot,
		"deltas": deltas,
		"improved_affixes": improved,
		"reduced_affixes": reduced,
		"rarity_delta": item.rarity - (
			equipped_item.rarity if equipped_item != null else GameTypes.Rarity.COMMON
		),
	}


static func build_value(
	item: ItemInstance,
	current_weapon_type: GameTypes.MainWeaponType,
	catalog: DefinitionCatalog,
) -> int:
	if item == null or catalog == null or not catalog.is_valid:
		return -1
	var affinity_count: int = 0
	for affix: AffixRoll in item.affixes:
		if affix == null:
			continue
		var definition: AffixDefinition = catalog.affix(affix.affix_id)
		if (
			definition != null
			and current_weapon_type in definition.affinity_weapon_types
		):
			affinity_count += 1
	return item.rarity * 100 + item.affixes.size() * 20 + affinity_count * 10


static func auto_select(
	state: RunState,
	rarity: GameTypes.Rarity,
	catalog: DefinitionCatalog,
	max_count: int = 3,
) -> PackedStringArray:
	var result := PackedStringArray()
	if (
		not _has_valid_inventory(state)
		or catalog == null
		or not catalog.is_valid
		or rarity not in GameTypes.Rarity.values()
		or max_count <= 0
	):
		return result
	var equipped_ids: Array[String] = equipped_item_ids(state)
	var entries: Array[Dictionary] = []
	var current_type: GameTypes.MainWeaponType = current_main_weapon_type(state)
	for item: ItemInstance in _storage_items(state):
		if (
			item == null
			or item.rarity != rarity
			or item.locked
			or not item.unique_id.is_empty()
			or item.item_id in equipped_ids
		):
			continue
		entries.append({
			"item_id": item.item_id,
			"value": build_value(item, current_type, catalog),
		})
	entries.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_value: int = int(left["value"])
		var right_value: int = int(right["value"])
		if left_value != right_value:
			return left_value < right_value
		return String(left["item_id"]) < String(right["item_id"])
	)
	for index: int in range(mini(max_count, entries.size())):
		result.append(String(entries[index]["item_id"]))
	return result


static func discard(
	state: RunState,
	item_ids: PackedStringArray,
	unique_confirmed: bool = false,
) -> Dictionary:
	if not _has_valid_inventory(state):
		return _failure(&"invalid_state", "インベントリ状態が不正です")
	if item_ids.is_empty():
		return _failure(&"empty_selection", "廃棄対象がありません")
	var seen: Dictionary[String, bool] = {}
	var inventory_indices: Array[int] = []
	var overflow_indices: Array[int] = []
	var target_names := PackedStringArray()
	var unique_names := PackedStringArray()
	for item_id: String in item_ids:
		if item_id.is_empty() or seen.has(item_id):
			return _failure(&"duplicate_target", "廃棄対象が重複しています")
		seen[item_id] = true
		var location: Dictionary = find_item(state, item_id)
		if location.is_empty():
			var missing: Dictionary = _failure(&"target_missing", "廃棄対象が見つかりません")
			missing["targets_disappeared"] = true
			return missing
		var kind: StringName = location["kind"] as StringName
		var item: ItemInstance = location["item"] as ItemInstance
		if kind == KIND_EQUIPPED:
			return _failure(&"equipped", "装備中のアイテムは廃棄できません")
		if item.locked:
			return _failure(&"locked", "ロック中のアイテムは廃棄できません")
		target_names.append(item.display_name)
		if not item.unique_id.is_empty():
			unique_names.append(item.display_name)
		if kind == KIND_INVENTORY:
			inventory_indices.append(int(location["index"]))
		else:
			overflow_indices.append(int(location["index"]))
	if not unique_names.is_empty() and not unique_confirmed:
		var confirmation: Dictionary = _failure(
			&"unique_confirmation_required",
			"ユニークを含めて廃棄しますか",
		)
		confirmation["needs_unique_confirmation"] = true
		confirmation["target_names"] = target_names
		confirmation["unique_names"] = unique_names
		return confirmation

	for index: int in inventory_indices:
		state.inventory[index] = null
	overflow_indices.sort()
	overflow_indices.reverse()
	for index: int in overflow_indices:
		state.overflow.remove_at(index)
	var refill_count: int = refill_from_overflow(state)
	return {
		"success": true,
		"error": &"",
		"message": "",
		"needs_unique_confirmation": false,
		"target_names": target_names,
		"unique_names": unique_names,
		"discarded_item_ids": item_ids.duplicate(),
		"refill_count": refill_count,
		"targets_disappeared": false,
	}


static func current_main_weapon_type(state: RunState) -> GameTypes.MainWeaponType:
	if state == null:
		return GameTypes.MainWeaponType.UNCLASSIFIED
	var main_weapon: ItemInstance = state.equipped.get(
		GameTypes.EquipmentSlot.MAIN_WEAPON,
		null,
	) as ItemInstance
	return (
		main_weapon.main_weapon_type
		if main_weapon != null
		else GameTypes.MainWeaponType.UNCLASSIFIED
	)


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
	var refill_count: int = refill_from_overflow(state)
	var result: Dictionary = _move_success(false, source_item)
	result["refill_count"] = refill_count
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
	else:
		if displaced == null:
			state.overflow.remove_at(source_index)
		else:
			state.overflow[source_index] = displaced
	_sync_equipment_side_effects(state)
	var refill_count: int = refill_from_overflow(state)
	var result: Dictionary = _move_success(false, source_item, displaced)
	result["refill_count"] = refill_count
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
	_sync_equipment_side_effects(state)
	var refill_count: int = refill_from_overflow(state)
	var result: Dictionary = _move_success(false, source_item, target_item)
	result["refill_count"] = refill_count
	return result


static func _sync_equipment_side_effects(state: RunState) -> void:
	var hands: ItemInstance = state.equipped.get(
		GameTypes.EquipmentSlot.HANDS,
		null,
	) as ItemInstance
	var echo_item_id: String = (
		hands.item_id
		if hands != null and hands.unique_id == &"echo_gauntlet"
		else ""
	)
	if state.echo_progress_item_id != echo_item_id:
		state.echo_progress_item_id = echo_item_id
		state.echo_primary_attack_progress = 0
	elif echo_item_id.is_empty():
		state.echo_primary_attack_progress = 0
	SkillEquipServiceScript.apply_crown_seal(state)


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
			result[affix.affix_id] = (
				float(result.get(affix.affix_id, 0.0)) + affix.value
			)
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
			return (
				index >= 0
				and index < RunState.INVENTORY_CAPACITY
				and (allow_empty_inventory or state.inventory[index] != null)
			)
		KIND_OVERFLOW:
			return index >= 0 and index < state.overflow.size()
		KIND_EQUIPPED:
			return (
				index in GameTypes.EquipmentSlot.values()
				and (allow_empty_inventory or state.equipped.get(index, null) != null)
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


static func _validate_unequip(
	state: RunState,
	slot: GameTypes.EquipmentSlot,
) -> Dictionary:
	if not _has_valid_inventory(state) or slot not in GameTypes.EquipmentSlot.values():
		return _validation_failure(&"invalid_slot", "装備枠が不正です")
	var item: ItemInstance = state.equipped.get(slot, null) as ItemInstance
	if item == null:
		return _validation_failure(&"empty_source", "外す装備がありません")
	if slot == GameTypes.EquipmentSlot.MAIN_WEAPON:
		return _validation_failure(&"main_weapon_required", MAIN_WEAPON_REQUIRED_MESSAGE)
	return _validation_success()


static func _validation_success() -> Dictionary:
	return {
		"success": true,
		"error": &"",
		"message": "",
	}


static func _validation_failure(error: StringName, message: String) -> Dictionary:
	return {
		"success": false,
		"error": error,
		"message": message,
	}


static func _location(kind: StringName, index: int, item: ItemInstance) -> Dictionary:
	return {
		"kind": kind,
		"index": index,
		"slot": index if kind == KIND_EQUIPPED else -1,
		"item": item,
	}


static func _location_success(
	kind: StringName,
	index: int,
	item: ItemInstance,
) -> Dictionary:
	var result: Dictionary = _location(kind, index, item)
	result["success"] = true
	result["error"] = &""
	result["message"] = ""
	return result


static func _move_success(
	no_op: bool,
	item: ItemInstance,
	displaced: ItemInstance = null,
) -> Dictionary:
	return {
		"success": true,
		"error": &"",
		"message": "",
		"no_op": no_op,
		"item_id": item.item_id if item != null else "",
		"displaced_item_id": displaced.item_id if displaced != null else "",
		"needs_unique_confirmation": false,
	}


static func _failure(error: StringName, message: String) -> Dictionary:
	return {
		"success": false,
		"error": error,
		"message": message,
		"no_op": true,
		"needs_unique_confirmation": false,
		"target_names": PackedStringArray(),
		"unique_names": PackedStringArray(),
	}
