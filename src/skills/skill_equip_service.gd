class_name SkillEquipService
extends RefCounted


const SOURCE_CATALOG: StringName = &"catalog"
const SOURCE_SLOT: StringName = &"slot"
const SLOT_COUNT: int = 2


static func apply_move(
	state: RunState,
	source_kind: StringName,
	source_id: Variant,
	target_kind: StringName,
	target_id: Variant,
) -> Dictionary:
	if state == null:
		return _failure(&"invalid_state", "ラン状態がありません")
	if not _has_valid_equipped_slots(state):
		return _failure(&"invalid_skill_slots", "スキル装着状態が不正です")
	if source_kind not in [SOURCE_CATALOG, SOURCE_SLOT]:
		return _failure(&"invalid_source", "持ち上げ元が不正です")
	if target_kind not in [SOURCE_CATALOG, SOURCE_SLOT]:
		return _failure(&"invalid_target", "配置先が不正です")

	var source_skill: SkillState = _skill_from_source(state, source_kind, source_id)
	if source_skill == null:
		if source_kind == SOURCE_SLOT and _slot_index(source_id) in range(SLOT_COUNT):
			return _success(true)
		return _failure(&"skill_not_found", "対象スキルがありません")

	if target_kind == SOURCE_CATALOG:
		if source_kind == SOURCE_CATALOG:
			return _failure(&"catalog_to_catalog", "ライブラリカード同士は配置できません")
		var target_skill_id := StringName(str(target_id))
		if target_skill_id != source_skill.skill_id:
			return _failure(&"different_catalog", "別スキルのカードへは配置できません")
		source_skill.equipped_slot = -1
		return _success(false, source_skill.skill_id)

	var target_slot: int = _slot_index(target_id)
	if target_slot < 0 or target_slot >= SLOT_COUNT:
		return _failure(&"invalid_target_slot", "装着先スロットが不正です")
	if is_slot_sealed(state, target_slot):
		return _failure(&"sealed_slot", "第2スキル枠は封印されています")
	if source_skill.equipped_slot == target_slot:
		return _success(true, source_skill.skill_id)

	var before: Dictionary = capture_snapshot(state)
	var previous_slot: int = source_skill.equipped_slot
	var displaced: SkillState = _skill_in_slot(state, target_slot)
	if displaced != null and displaced != source_skill:
		displaced.equipped_slot = previous_slot if previous_slot >= 0 else -1
	source_skill.equipped_slot = target_slot

	if not _has_valid_equipped_slots(state):
		_restore_snapshot_unchecked(state, before)
		return _failure(&"invalid_skill_slots", "スキル装着状態を維持できません")
	return _success(
		false,
		source_skill.skill_id,
		displaced.skill_id if displaced != null else &"",
	)


static func capture_snapshot(state: RunState) -> Dictionary:
	var snapshot: Dictionary = {}
	if state == null:
		return snapshot
	for skill_id: StringName in state.skill_library:
		var skill: SkillState = state.skill_library[skill_id]
		if skill != null:
			snapshot[skill_id] = skill.equipped_slot
	return snapshot


static func restore_snapshot(state: RunState, snapshot: Dictionary) -> bool:
	if state == null:
		return false
	var current: Dictionary = capture_snapshot(state)
	_restore_snapshot_unchecked(state, snapshot)
	if not _has_valid_equipped_slots(state):
		_restore_snapshot_unchecked(state, current)
		return false
	return true


static func apply_crown_seal(state: RunState) -> Dictionary:
	if state == null:
		return _failure(&"invalid_state", "ラン状態がありません")
	if not is_slot_sealed(state, 1):
		return _success(true)
	var displaced: SkillState = _skill_in_slot(state, 1)
	if displaced == null:
		return _success(true)
	displaced.equipped_slot = -1
	var result: Dictionary = _success(false, displaced.skill_id)
	result["sealed_skill_id"] = displaced.skill_id
	return result


static func is_slot_sealed(state: RunState, slot_index: int) -> bool:
	if state == null or slot_index != 1:
		return false
	var head: ItemInstance = state.equipped.get(
		GameTypes.EquipmentSlot.HEAD,
		null,
	) as ItemInstance
	return head != null and head.unique_id == &"hollow_crown"


static func slot_skill_ids(state: RunState) -> PackedStringArray:
	var result := PackedStringArray(["", ""])
	if state == null:
		return result
	for skill_id: StringName in state.skill_library:
		var skill: SkillState = state.skill_library[skill_id]
		if skill != null and skill.equipped_slot in range(SLOT_COUNT):
			result[skill.equipped_slot] = String(skill.skill_id)
	return result


static func _skill_from_source(
	state: RunState,
	source_kind: StringName,
	source_id: Variant,
) -> SkillState:
	if source_kind == SOURCE_CATALOG:
		return state.skill_library.get(StringName(str(source_id)), null) as SkillState
	var source_slot: int = _slot_index(source_id)
	if source_slot < 0 or source_slot >= SLOT_COUNT:
		return null
	return _skill_in_slot(state, source_slot)


static func _skill_in_slot(state: RunState, slot_index: int) -> SkillState:
	for value: Variant in state.skill_library.values():
		var skill: SkillState = value as SkillState
		if skill != null and skill.equipped_slot == slot_index:
			return skill
	return null


static func _slot_index(value: Variant) -> int:
	if value is int:
		return value as int
	var text := str(value)
	return text.to_int() if text.is_valid_int() else -1


static func _has_valid_equipped_slots(state: RunState) -> bool:
	var occupied: Dictionary[int, bool] = {}
	for value: Variant in state.skill_library.values():
		var skill: SkillState = value as SkillState
		if skill == null or skill.level < 1 or skill.level > 3:
			return false
		if skill.equipped_slot < -1 or skill.equipped_slot >= SLOT_COUNT:
			return false
		if skill.equipped_slot < 0:
			continue
		if occupied.has(skill.equipped_slot):
			return false
		if is_slot_sealed(state, skill.equipped_slot):
			return false
		occupied[skill.equipped_slot] = true
	return true


static func _restore_snapshot_unchecked(state: RunState, snapshot: Dictionary) -> void:
	for skill_id: StringName in state.skill_library:
		var skill: SkillState = state.skill_library[skill_id]
		if skill != null:
			skill.equipped_slot = int(snapshot.get(skill_id, -1))


static func _success(
	no_op: bool,
	moved_skill_id: StringName = &"",
	displaced_skill_id: StringName = &"",
) -> Dictionary:
	return {
		"success": true,
		"error": &"",
		"message": "",
		"no_op": no_op,
		"moved_skill_id": moved_skill_id,
		"displaced_skill_id": displaced_skill_id,
	}


static func _failure(error: StringName, message: String) -> Dictionary:
	return {
		"success": false,
		"error": error,
		"message": message,
		"no_op": true,
		"moved_skill_id": &"",
		"displaced_skill_id": &"",
	}
