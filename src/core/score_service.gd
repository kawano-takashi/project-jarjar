class_name ScoreService
extends RefCounted


static func calculate(
	normal_kills: int,
	elite_kills: int,
	boss_kills: int,
	post_quota_kills: int,
	cleared_waves: int,
	run_cleared: bool,
	equipped_items: Array[ItemInstance],
	definition: ScoreDefinition,
) -> Dictionary:
	var equipment_counts := PackedInt32Array([0, 0, 0, 0])
	for item: ItemInstance in equipped_items:
		if item == null:
			continue
		var rarity_index: int = int(item.rarity)
		if rarity_index >= 0 and rarity_index < equipment_counts.size():
			equipment_counts[rarity_index] += 1

	var normal_kill_score: int = normal_kills * definition.normal_kill
	var post_quota_score: int = post_quota_kills * definition.post_quota_bonus
	var elite_score: int = elite_kills * definition.elite_kill
	var boss_score: int = boss_kills * definition.boss_kill
	var wave_clear_score: int = cleared_waves * definition.wave_clear
	var run_clear_score: int = definition.run_clear if run_cleared else 0
	var equipment_score: int = 0
	for rarity: int in range(equipment_counts.size()):
		equipment_score += equipment_counts[rarity] * definition.equipment_scores[rarity]
	var combat_score: int = (
		normal_kill_score
		+ post_quota_score
		+ elite_score
		+ boss_score
		+ wave_clear_score
		+ run_clear_score
	)
	return {
		&"normal_kills": normal_kill_score,
		&"post_quota_bonus": post_quota_score,
		&"elite_kills": elite_score,
		&"boss_kills": boss_score,
		&"wave_clears": wave_clear_score,
		&"run_clear": run_clear_score,
		&"equipment": equipment_score,
		&"combat_score": combat_score,
		&"final_build_score": equipment_score,
		&"total": combat_score + equipment_score,
	}
