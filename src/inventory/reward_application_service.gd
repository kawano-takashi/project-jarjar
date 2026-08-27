class_name RewardApplicationService
extends RefCounted


const InventoryServiceScript := preload("res://src/inventory/inventory_service.gd")
const SkillEquipServiceScript := preload("res://src/skills/skill_equip_service.gd")


static func ordered_revealed_rewards(state: RunState) -> Array[RewardRoll]:
	var result: Array[RewardRoll] = []
	if state == null:
		return result
	for reward: RewardRoll in state.unopened_rewards:
		if (
			reward != null
			and reward.wave_number == state.wave_number
			and reward.revealed
		):
			result.append(reward)
	result.sort_custom(func(left: RewardRoll, right: RewardRoll) -> bool:
		if left.acquired_tick != right.acquired_tick:
			return left.acquired_tick < right.acquired_tick
		return left.reward_id < right.reward_id
	)
	return result


static func apply_revealed(state: RunState) -> Dictionary:
	if state == null or state.inventory.size() != RunState.INVENTORY_CAPACITY:
		return _failure(&"invalid_state", "ラン状態が不正です")
	for overflow_item: ItemInstance in state.overflow:
		if overflow_item == null:
			return _failure(&"invalid_state", "ラン状態が不正です")
	var current_rewards: Array[RewardRoll] = []
	var prospective_skill_ids: Dictionary[StringName, bool] = {}
	for skill_id: StringName in state.skill_library:
		var skill: SkillState = state.skill_library[skill_id]
		if (
			skill == null
			or skill.skill_id != skill_id
			or skill.level < 1
			or skill.level > 3
		):
			return _failure(&"invalid_skill_library", "スキルライブラリが不正です")
		prospective_skill_ids[skill_id] = true
	for reward: RewardRoll in state.unopened_rewards:
		if reward == null or reward.wave_number != state.wave_number:
			continue
		if not reward.revealed:
			return _failure(&"unrevealed_reward", "未公開の報酬が残っています")
		if (
			reward.kind == GameTypes.RewardKind.EQUIPMENT
			and reward.equipment == null
		):
			return _failure(&"invalid_equipment_reward", "装備報酬が不正です")
		if (
			reward.kind == GameTypes.RewardKind.SKILL
			and reward.skill_id.is_empty()
		):
			return _failure(&"invalid_skill_reward", "スキル報酬が不正です")
		if reward.kind == GameTypes.RewardKind.SKILL:
			prospective_skill_ids[reward.skill_id] = true
		current_rewards.append(reward)
	if prospective_skill_ids.size() > 4:
		return _failure(&"skill_library_full", "スキルライブラリが上限です")
	current_rewards.sort_custom(func(left: RewardRoll, right: RewardRoll) -> bool:
		if left.acquired_tick != right.acquired_tick:
			return left.acquired_tick < right.acquired_tick
		return left.reward_id < right.reward_id
	)

	var equipment_count: int = 0
	var inventory_count: int = 0
	var overflow_count: int = 0
	var new_skill_count: int = 0
	var level_up_count: int = 0
	var wild_gained: int = 0
	var applied_reward_ids := PackedStringArray()
	for reward: RewardRoll in current_rewards:
		applied_reward_ids.append(reward.reward_id)
		if reward.kind == GameTypes.RewardKind.EQUIPMENT:
			var insertion: Dictionary = InventoryServiceScript.insert_item(
				state,
				reward.equipment,
			)
			if not bool(insertion.get("success", false)):
				return _failure(&"equipment_insert_failed", "装備報酬を格納できません")
			equipment_count += 1
			if insertion.get("kind", &"") == InventoryServiceScript.KIND_INVENTORY:
				inventory_count += 1
			else:
				overflow_count += 1
			continue

		var skill_result: Dictionary = _apply_skill_reward(state, reward.skill_id)
		if not bool(skill_result.get("success", false)):
			return skill_result
		new_skill_count += int(skill_result.get("new_skill_count", 0))
		level_up_count += int(skill_result.get("level_up_count", 0))
		wild_gained += int(skill_result.get("wild_gained", 0))

	var retained: Array[RewardRoll] = []
	for reward: RewardRoll in state.unopened_rewards:
		if reward == null or reward.wave_number != state.wave_number:
			retained.append(reward)
	state.unopened_rewards = retained
	return {
		"success": true,
		"error": &"",
		"message": "",
		"applied_reward_ids": applied_reward_ids,
		"equipment_count": equipment_count,
		"inventory_count": inventory_count,
		"overflow_count": overflow_count,
		"new_skill_count": new_skill_count,
		"level_up_count": level_up_count,
		"wild_gained": wild_gained,
	}


static func _apply_skill_reward(state: RunState, skill_id: StringName) -> Dictionary:
	var existing: SkillState = state.skill_library.get(skill_id, null) as SkillState
	if existing != null:
		if existing.level < 3:
			existing.level += 1
			return {
				"success": true,
				"error": &"",
				"message": "",
				"new_skill_count": 0,
				"level_up_count": 1,
				"wild_gained": 0,
			}
		state.wild_material_count += 1
		return {
			"success": true,
			"error": &"",
			"message": "",
			"new_skill_count": 0,
			"level_up_count": 0,
			"wild_gained": 1,
		}

	if state.skill_library.size() >= 4:
		return _failure(&"skill_library_full", "スキルライブラリが上限です")
	var skill := SkillState.new()
	skill.skill_id = skill_id
	skill.level = 1
	skill.equipped_slot = _first_available_slot(state)
	state.skill_library[skill_id] = skill
	return {
		"success": true,
		"error": &"",
		"message": "",
		"new_skill_count": 1,
		"level_up_count": 0,
		"wild_gained": 0,
	}


static func _first_available_slot(state: RunState) -> int:
	var occupied: Dictionary[int, bool] = {}
	for value: Variant in state.skill_library.values():
		var skill: SkillState = value as SkillState
		if skill != null and skill.equipped_slot >= 0:
			occupied[skill.equipped_slot] = true
	for slot_index: int in range(2):
		if (
			not occupied.has(slot_index)
			and not SkillEquipServiceScript.is_slot_sealed(state, slot_index)
		):
			return slot_index
	return -1


static func _failure(error: StringName, message: String) -> Dictionary:
	return {
		"success": false,
		"error": error,
		"message": message,
		"applied_reward_ids": PackedStringArray(),
		"equipment_count": 0,
		"inventory_count": 0,
		"overflow_count": 0,
		"new_skill_count": 0,
		"level_up_count": 0,
		"wild_gained": 0,
	}
