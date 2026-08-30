class_name ScoreService
extends RefCounted


static func calculate(
	normal_kills: int,
	elite_kills: int,
	boss_kills: int,
	post_quota_kills: int,
	cleared_waves: int,
	run_cleared: bool,
	held_equipment: Array[ItemInstance],
	skill_library: Dictionary,
	wild_material_count: int,
	definition: ScoreDefinition
) -> Dictionary:
	var equipment_counts: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
	var unique_count: int = 0
	for item: ItemInstance in held_equipment:
		if item == null:
			continue
		var score_rarity: int = (
			GameTypes.Rarity.LEGENDARY
			if item.rarity == GameTypes.Rarity.UNIQUE
			else int(item.rarity)
		)
		if score_rarity >= 0 and score_rarity < equipment_counts.size():
			equipment_counts[score_rarity] += 1
		if not item.unique_id.is_empty():
			unique_count += 1
	var skill_level_total: int = 0
	for value: Variant in skill_library.values():
		var skill: SkillState = value as SkillState
		if skill != null:
			skill_level_total += skill.level

	var normal_kill_score: int = normal_kills * definition.normal_kill
	var post_quota_score: int = post_quota_kills * definition.post_quota_bonus
	var elite_score: int = elite_kills * definition.elite_kill
	var boss_score: int = boss_kills * definition.boss_kill
	var wave_clear_score: int = cleared_waves * definition.wave_clear
	var run_clear_score: int = definition.run_clear if run_cleared else 0
	var equipment_score: int = 0
	for rarity: int in range(equipment_counts.size()):
		equipment_score += equipment_counts[rarity] * definition.equipment_scores[rarity]
	var unique_score: int = unique_count * definition.unique_tag
	var skill_score: int = skill_level_total * definition.skill_level
	var wild_score: int = wild_material_count * definition.wild_material
	var combat_score: int = (
		normal_kill_score
		+ post_quota_score
		+ elite_score
		+ boss_score
		+ wave_clear_score
		+ run_clear_score
	)
	var final_build_score: int = equipment_score + unique_score + skill_score + wild_score
	return {
		&"normal_kills": normal_kill_score,
		&"post_quota_bonus": post_quota_score,
		&"elite_kills": elite_score,
		&"boss_kills": boss_score,
		&"wave_clears": wave_clear_score,
		&"run_clear": run_clear_score,
		&"equipment": equipment_score,
		&"unique_tags": unique_score,
		&"skill_levels": skill_score,
		&"wild_materials": wild_score,
		&"combat_score": combat_score,
		&"final_build_score": final_build_score,
		&"total": combat_score + final_build_score,
	}
