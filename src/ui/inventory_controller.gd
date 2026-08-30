class_name InventoryController
extends RefCounted


const SKILL_ORDER: Array[StringName] = [
	&"starfall",
	&"thousand_blades",
	&"soul_chain",
	&"bell_of_retribution",
]

var state: RunState = null
var catalog: DefinitionCatalog = null
var marked_item_ids: Dictionary[String, bool] = {}
var last_item_focus_id: String = ""
var held_item_source: Dictionary = {}
var held_skill_source: Dictionary = {}

var fusion_open: bool = false
var fusion_rarity: GameTypes.Rarity = GameTypes.Rarity.COMMON
var fusion_material_ids: PackedStringArray = PackedStringArray()
var fusion_use_wild: bool = false
var fusion_status: String = ""


func initialize(p_state: RunState, p_catalog: DefinitionCatalog) -> void:
	state = p_state
	catalog = p_catalog
	marked_item_ids.clear()
	last_item_focus_id = ""
	held_item_source.clear()
	held_skill_source.clear()
	reset_fusion()


func marked_ids() -> PackedStringArray:
	var result := PackedStringArray()
	for item_id: String in marked_item_ids:
		result.append(item_id)
	result.sort()
	return result


func replace_marks(item_ids: PackedStringArray) -> void:
	marked_item_ids.clear()
	for item_id: String in item_ids:
		if not item_id.is_empty():
			marked_item_ids[item_id] = true


func clear_marks() -> void:
	marked_item_ids.clear()


func set_last_item_focus(item_id: String) -> void:
	if not item_id.is_empty() and find_item(item_id).get("found", false):
		last_item_focus_id = item_id


func auto_select(rarity: GameTypes.Rarity, max_count: int = 3) -> PackedStringArray:
	var service: Variant = load("res://src/inventory/inventory_service.gd")
	var selected := PackedStringArray()
	if service != null and service.has_method("auto_select"):
		selected = service.auto_select(state, rarity, catalog, max_count)
	else:
		var candidates: Array[Dictionary] = []
		for location: Dictionary in all_unequipped_locations():
			var item: ItemInstance = location["item"] as ItemInstance
			if (
				item == null
				or item.rarity != rarity
				or item.locked
				or not item.unique_id.is_empty()
			):
				continue
			candidates.append({
				"item_id": item.item_id,
				"build_value": _fallback_build_value(item),
			})
		candidates.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
			if int(left["build_value"]) != int(right["build_value"]):
				return int(left["build_value"]) < int(right["build_value"])
			return str(left["item_id"]) < str(right["item_id"])
		)
		for index: int in range(mini(max_count, candidates.size())):
			selected.append(str(candidates[index]["item_id"]))
	replace_marks(selected)
	return selected


func discard_targets() -> PackedStringArray:
	var marked: PackedStringArray = marked_ids()
	if not marked.is_empty():
		return marked
	if not last_item_focus_id.is_empty() and find_item(last_item_focus_id).get("found", false):
		return PackedStringArray([last_item_focus_id])
	return PackedStringArray()


func unique_names(item_ids: PackedStringArray) -> PackedStringArray:
	var names := PackedStringArray()
	for item_id: String in item_ids:
		var location: Dictionary = find_item(item_id)
		var item: ItemInstance = location.get("item") as ItemInstance
		if item != null and not item.unique_id.is_empty():
			names.append(item.display_name)
	return names


func begin_item_lift(source_kind: StringName, source_index: int) -> bool:
	var item: ItemInstance = item_at(source_kind, source_index)
	if item == null:
		return false
	held_skill_source.clear()
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


func begin_skill_lift(source_kind: StringName, source_id: Variant) -> bool:
	if state == null:
		return false
	var skill_id: StringName = _skill_id_for_source(source_kind, source_id)
	if skill_id.is_empty():
		return false
	held_item_source.clear()
	held_skill_source = {
		"kind": source_kind,
		"id": source_id,
		"skill_id": skill_id,
	}
	return true


func skill_move_request(target_kind: StringName, target_id: Variant) -> Dictionary:
	if held_skill_source.is_empty():
		return {}
	return {
		"source_kind": StringName(held_skill_source["kind"]),
		"source_id": held_skill_source["id"],
		"target_kind": target_kind,
		"target_id": target_id,
	}


func cancel_lift() -> void:
	held_item_source.clear()
	held_skill_source.clear()


func complete_lift() -> void:
	cancel_lift()


func open_fusion(use_wild: bool) -> void:
	clear_marks()
	fusion_open = true
	fusion_rarity = _initial_fusion_rarity()
	fusion_material_ids = PackedStringArray()
	fusion_use_wild = use_wild and state != null and state.wild_material_count > 0
	fusion_status = ""


func reset_fusion() -> void:
	fusion_open = false
	fusion_rarity = GameTypes.Rarity.COMMON
	fusion_material_ids = PackedStringArray()
	fusion_use_wild = false
	fusion_status = ""


func complete_fusion_success(status_text: String) -> void:
	fusion_material_ids = PackedStringArray()
	fusion_use_wild = false
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
	fusion_use_wild = false
	fusion_status = ""


func toggle_fusion_material(item_id: String, manual: bool = true) -> bool:
	var existing_index: int = fusion_material_ids.find(item_id)
	if existing_index >= 0:
		fusion_material_ids.remove_at(existing_index)
		fusion_status = ""
		return true
	var location: Dictionary = find_item(item_id)
	var item: ItemInstance = location.get("item") as ItemInstance
	if not _eligible_fusion_item(item, manual):
		fusion_status = "この装備は材料にできません"
		return false
	if fusion_material_ids.size() >= fusion_required_item_count():
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


func toggle_fusion_wild() -> bool:
	if state == null or state.wild_material_count <= 0:
		fusion_status = "ワイルド素材がありません"
		return false
	fusion_use_wild = not fusion_use_wild
	if fusion_use_wild and fusion_material_ids.size() >= 3:
		fusion_material_ids.remove_at(2)
	fusion_status = ""
	return true


func auto_fill_fusion() -> PackedStringArray:
	fusion_material_ids = PackedStringArray()
	var candidates: Array[Dictionary] = []
	for location: Dictionary in all_unequipped_locations():
		var item: ItemInstance = location["item"] as ItemInstance
		if not _eligible_fusion_item(item, false):
			continue
		candidates.append({
			"item_id": item.item_id,
			"build_value": _build_value(item),
		})
	candidates.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		if int(left["build_value"]) != int(right["build_value"]):
			return int(left["build_value"]) < int(right["build_value"])
		return str(left["item_id"]) < str(right["item_id"])
	)
	var required: int = fusion_required_item_count()
	for index: int in range(mini(required, candidates.size())):
		fusion_material_ids.append(str(candidates[index]["item_id"]))
	var missing: int = required - fusion_material_ids.size()
	fusion_status = "不足 %d件" % missing if missing > 0 else ""
	return fusion_material_ids.duplicate()


func fusion_required_item_count() -> int:
	return 2 if fusion_use_wild else 3


func fusion_is_valid() -> bool:
	if not fusion_open or fusion_material_ids.size() != fusion_required_item_count():
		return false
	if fusion_use_wild and (state == null or state.wild_material_count <= 0):
		return false
	for item_id: String in fusion_material_ids:
		var item: ItemInstance = find_item(item_id).get("item") as ItemInstance
		if not _eligible_fusion_item(item, true):
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
	return "材料: %s\n出力: %s\n部位は6種から均等抽選／UNIQUEはボス宝箱限定" % [
		material_text,
		output_rarity,
	]


func find_item(item_id: String) -> Dictionary:
	if state == null or item_id.is_empty():
		return {"found": false}
	for slot: int in range(GameTypes.EquipmentSlot.size()):
		var equipped_item: ItemInstance = state.equipped.get(slot) as ItemInstance
		if equipped_item != null and equipped_item.item_id == item_id:
			return {"found": true, "kind": &"equipped", "index": slot, "item": equipped_item}
	for index: int in range(state.inventory.size()):
		var inventory_item: ItemInstance = state.inventory[index]
		if inventory_item != null and inventory_item.item_id == item_id:
			return {"found": true, "kind": &"inventory", "index": index, "item": inventory_item}
	for index: int in range(state.overflow.size()):
		var overflow_item: ItemInstance = state.overflow[index]
		if overflow_item.item_id == item_id:
			return {"found": true, "kind": &"overflow", "index": index, "item": overflow_item}
	return {"found": false}


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
		var inventory_item: ItemInstance = state.inventory[index]
		if inventory_item != null:
			result.append({"kind": &"inventory", "index": index, "item": inventory_item})
	for index: int in range(state.overflow.size()):
		result.append({"kind": &"overflow", "index": index, "item": state.overflow[index]})
	return result


func fusion_candidate_locations() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for location: Dictionary in all_unequipped_locations():
		var item: ItemInstance = location.get("item") as ItemInstance
		if _eligible_fusion_item(item, true):
			result.append(location)
	return result


func equipped_skill_ids() -> Array[StringName]:
	var result: Array[StringName] = [&"", &""]
	if state == null:
		return result
	for value: Variant in state.skill_library.values():
		var skill: SkillState = value as SkillState
		if skill != null and skill.equipped_slot >= 0 and skill.equipped_slot < result.size():
			result[skill.equipped_slot] = skill.skill_id
	return result


func skill_id_at_catalog_index(index: int) -> StringName:
	if index < 0 or index >= SKILL_ORDER.size():
		return &""
	return SKILL_ORDER[index]


func skill_is_owned(skill_id: StringName) -> bool:
	return state != null and state.skill_library.has(skill_id)


func rarity_label(rarity: GameTypes.Rarity) -> String:
	match rarity:
		GameTypes.Rarity.RARE:
			return "RARE"
		GameTypes.Rarity.EPIC:
			return "EPIC"
		GameTypes.Rarity.LEGENDARY:
			return "LEGENDARY"
		GameTypes.Rarity.UNIQUE:
			return "★ UNIQUE"
	return "COMMON"


func skill_name(skill_id: StringName) -> String:
	match skill_id:
		&"starfall":
			return "星落とし"
		&"thousand_blades":
			return "千刃陣"
		&"soul_chain":
			return "魂の連鎖"
		&"bell_of_retribution":
			return "報復の鐘"
	return String(skill_id)


func debug_state() -> Dictionary:
	return {
		"marked_item_ids": marked_ids(),
		"last_item_focus_id": last_item_focus_id,
		"held_item_source": held_item_source.duplicate(true),
		"held_skill_source": held_skill_source.duplicate(true),
		"fusion_open": fusion_open,
		"fusion_rarity": fusion_rarity,
		"fusion_material_ids": fusion_material_ids.duplicate(),
		"fusion_use_wild": fusion_use_wild,
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


func _eligible_fusion_item(item: ItemInstance, _manual: bool) -> bool:
	return (
		item != null
		and item.rarity == fusion_rarity
		and item.rarity in [
			GameTypes.Rarity.COMMON,
			GameTypes.Rarity.RARE,
			GameTypes.Rarity.EPIC,
		]
		and not item.locked
		and item.unique_id.is_empty()
		and find_item(item.item_id).get("kind", &"") != &"equipped"
	)


func _build_value(item: ItemInstance) -> int:
	var service: Variant = load("res://src/inventory/inventory_service.gd")
	if service != null and service.has_method("build_value"):
		return service.build_value(item, _current_weapon_type(), catalog)
	return _fallback_build_value(item)


func _fallback_build_value(item: ItemInstance) -> int:
	if item == null:
		return 0
	var affinity_count: int = 0
	for affix: AffixRoll in item.affixes:
		var definition: AffixDefinition = catalog.affix(affix.affix_id) if catalog != null else null
		if definition != null and _current_weapon_type() in definition.affinity_weapon_types:
			affinity_count += 1
	return item.rarity * 100 + item.affixes.size() * 20 + affinity_count * 10


func _current_weapon_type() -> GameTypes.MainWeaponType:
	var main_weapon: ItemInstance = (
		state.equipped.get(GameTypes.EquipmentSlot.MAIN_WEAPON) as ItemInstance
		if state != null
		else null
	)
	return (
		main_weapon.main_weapon_type
		if main_weapon != null
		else GameTypes.MainWeaponType.UNCLASSIFIED
	)


func _next_rarity(rarity: GameTypes.Rarity) -> GameTypes.Rarity:
	match rarity:
		GameTypes.Rarity.COMMON:
			return GameTypes.Rarity.RARE
		GameTypes.Rarity.RARE:
			return GameTypes.Rarity.EPIC
	return GameTypes.Rarity.LEGENDARY


func _skill_id_for_source(source_kind: StringName, source_id: Variant) -> StringName:
	if source_kind == &"catalog":
		var catalog_id := StringName(source_id)
		return catalog_id if skill_is_owned(catalog_id) else &""
	if source_kind != &"slot":
		return &""
	var slot_index: int = int(source_id)
	var equipped_ids: Array[StringName] = equipped_skill_ids()
	return equipped_ids[slot_index] if slot_index >= 0 and slot_index < equipped_ids.size() else &""
