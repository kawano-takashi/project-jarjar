class_name RewardApplicationService
extends RefCounted


const InventoryServiceScript := preload("res://src/inventory/inventory_service.gd")


static func ordered_revealed_rewards(state: RunState) -> Array[RewardRoll]:
	var result: Array[RewardRoll] = []
	if state == null:
		return result
	for reward: RewardRoll in state.unopened_rewards:
		if reward != null and reward.wave_number == state.wave_number and reward.revealed:
			result.append(reward)
	result.sort_custom(_reward_less)
	return result


static func apply_revealed(state: RunState) -> Dictionary:
	if state == null or state.inventory.size() != RunState.INVENTORY_CAPACITY:
		return _failure(&"invalid_state", "ラン状態が不正です")
	for overflow_item: ItemInstance in state.overflow:
		if overflow_item == null:
			return _failure(&"invalid_state", "ラン状態が不正です")
	var current_rewards: Array[RewardRoll] = []
	for reward: RewardRoll in state.unopened_rewards:
		if reward == null or reward.wave_number != state.wave_number:
			continue
		if not reward.revealed:
			return _failure(&"unrevealed_reward", "未公開の報酬が残っています")
		var item_error: StringName = _item_error(reward.item)
		if not item_error.is_empty():
			return _failure(item_error, "アイテム報酬が不正です")
		current_rewards.append(reward)
	current_rewards.sort_custom(_reward_less)

	var inventory_count: int = 0
	var overflow_count: int = 0
	var applied_reward_ids := PackedStringArray()
	for reward: RewardRoll in current_rewards:
		applied_reward_ids.append(reward.reward_id)
		var insertion: Dictionary = InventoryServiceScript.insert_item(state, reward.item)
		if not bool(insertion.get("success", false)):
			return _failure(&"item_insert_failed", "アイテム報酬を格納できません")
		if insertion.get("kind", &"") == InventoryServiceScript.KIND_INVENTORY:
			inventory_count += 1
		else:
			overflow_count += 1

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
		"item_count": current_rewards.size(),
		"inventory_count": inventory_count,
		"overflow_count": overflow_count,
	}


static func _item_error(item: ItemInstance) -> StringName:
	if item == null or item.item_id.is_empty() or item.display_name.is_empty():
		return &"invalid_item_reward"
	if item.category == GameTypes.ItemCategory.WEAPON:
		if item.weapon_type == GameTypes.WeaponType.NONE or not item.affixes.is_empty():
			return &"invalid_weapon_reward"
		return &""
	if item.category == GameTypes.ItemCategory.CHARM:
		if item.weapon_type != GameTypes.WeaponType.NONE:
			return &"invalid_charm_reward"
		var expected_count: int = int(item.rarity) + 1
		if item.affixes.size() != expected_count:
			return &"invalid_charm_reward"
		var seen: Dictionary[StringName, bool] = {}
		for affix: AffixRoll in item.affixes:
			if affix == null or seen.has(affix.affix_id):
				return &"invalid_charm_reward"
			seen[affix.affix_id] = true
		return &""
	return &"invalid_item_reward"


static func _reward_less(left: RewardRoll, right: RewardRoll) -> bool:
	if left.acquired_tick != right.acquired_tick:
		return left.acquired_tick < right.acquired_tick
	return left.reward_id < right.reward_id


static func _failure(error: StringName, message: String) -> Dictionary:
	return {
		"success": false,
		"error": error,
		"message": message,
		"applied_reward_ids": PackedStringArray(),
		"item_count": 0,
		"inventory_count": 0,
		"overflow_count": 0,
	}
