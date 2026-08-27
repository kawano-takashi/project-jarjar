class_name StatCalculator
extends RefCounted


const ATTACK_INTERVAL_MIN_SECONDS: float = 0.05
const TIME_SKILL_INTERVAL_MIN_SECONDS: float = 0.25
const BASE_MOVE_SPEED: float = 5.0
const BASE_MAX_HP: float = 100.0
const AFFIX_IDS: Array[StringName] = [
	&"damage_pct",
	&"attack_speed_pct",
	&"cooldown_reduction_pct",
	&"area_pct",
	&"pierce",
	&"max_hp",
	&"damage_reduction_pct",
	&"move_speed_pct",
	&"skill_power_pct",
]


static func aggregate_affixes(equipped: Dictionary) -> Dictionary:
	var totals: Dictionary = {}
	for affix_id: StringName in AFFIX_IDS:
		totals[affix_id] = 0.0
	for value: Variant in equipped.values():
		var item: ItemInstance = value as ItemInstance
		if item == null:
			continue
		for affix: AffixRoll in item.affixes:
			var current: float = float(totals.get(affix.affix_id, 0.0))
			totals[affix.affix_id] = current + affix.value
	return totals


static func equipped_unique_ids(equipped: Dictionary) -> Array[StringName]:
	var ids: Array[StringName] = []
	for value: Variant in equipped.values():
		var item: ItemInstance = value as ItemInstance
		if item != null and not item.unique_id.is_empty():
			ids.append(item.unique_id)
	return WeightedSelector.sort_ordinal(ids)


static func damage_multiplier(
	stats: Dictionary,
	unique_ids: Array[StringName],
	is_skill: bool = false,
	coward_stationary_active: bool = false
) -> float:
	var multiplier: float = 1.0 + float(stats.get(&"damage_pct", 0.0)) / 100.0
	if is_skill:
		multiplier *= 1.0 + float(stats.get(&"skill_power_pct", 0.0)) / 100.0
	var sorted_ids: Array[StringName] = WeightedSelector.sort_ordinal(unique_ids)
	for unique_id: StringName in sorted_ids:
		match unique_id:
			&"bloodied_dagger", &"immortal_breastplate":
				multiplier *= 0.5
			&"broken_clock":
				if is_skill:
					multiplier *= 0.5
			&"coward_boots":
				if coward_stationary_active:
					multiplier *= 3.0
	return multiplier


static func effective_attack_interval(
	base_interval: float,
	main_weapon_type: GameTypes.MainWeaponType,
	stats: Dictionary,
	unique_ids: Array[StringName] = [],
	bloodied_wave_kills: int = 0,
	coward_stationary_active: bool = false
) -> float:
	var attack_speed_pct: float = float(stats.get(&"attack_speed_pct", 0.0))
	if &"bloodied_dagger" in unique_ids:
		attack_speed_pct += float(maxi(0, bloodied_wave_kills))
	var speed_denominator: float = maxf(0.01, 1.0 + attack_speed_pct / 100.0)
	if &"coward_boots" in unique_ids and coward_stationary_active:
		speed_denominator *= 2.0
	var interval: float = base_interval / speed_denominator
	if main_weapon_type == GameTypes.MainWeaponType.STAFF:
		var cooldown_factor: float = maxf(
			0.0,
			1.0 - float(stats.get(&"cooldown_reduction_pct", 0.0)) / 100.0
		)
		interval = base_interval * cooldown_factor / speed_denominator
	return maxf(ATTACK_INTERVAL_MIN_SECONDS, interval)


static func effective_time_skill_interval(
	base_interval: float,
	stats: Dictionary,
	unique_ids: Array[StringName] = []
) -> float:
	var interval: float = base_interval * maxf(
		0.0,
		1.0 - float(stats.get(&"cooldown_reduction_pct", 0.0)) / 100.0
	)
	if &"broken_clock" in unique_ids:
		interval *= 0.5
	return maxf(TIME_SKILL_INTERVAL_MIN_SECONDS, interval)


static func effective_skill_threshold(
	definition: SkillDefinition,
	stats: Dictionary,
	unique_ids: Array[StringName] = [],
) -> float:
	if definition == null:
		return 0.0
	if definition.trigger_type == GameTypes.TriggerType.TIME:
		return effective_time_skill_interval(
			definition.base_threshold,
			stats,
			unique_ids,
		)
	if &"broken_clock" in unique_ids:
		return float(int(ceil(definition.base_threshold * 0.5)))
	return definition.base_threshold


static func effective_damage_reduction_pct(equipped: Dictionary) -> float:
	var immortal_item: ItemInstance = equipped.get(
		GameTypes.EquipmentSlot.BODY,
		null
	) as ItemInstance
	var immortal_equipped: bool = (
		immortal_item != null
		and immortal_item.unique_id == &"immortal_breastplate"
	)
	var total: float = 0.0
	for value: Variant in equipped.values():
		var item: ItemInstance = value as ItemInstance
		if item == null:
			continue
		var item_reduction: float = 0.0
		for affix: AffixRoll in item.affixes:
			if affix.affix_id == &"damage_reduction_pct":
				item_reduction += affix.value
		if immortal_equipped and item != immortal_item:
			item_reduction *= 2.0
		total += item_reduction
	return clampf(total, 0.0, 100.0)


static func apply_incoming_damage(raw_damage: float, damage_reduction_pct: float) -> float:
	return maxf(0.0, raw_damage) * (
		1.0 - clampf(damage_reduction_pct, 0.0, 100.0) / 100.0
	)


static func effective_move_speed(stats: Dictionary) -> float:
	return BASE_MOVE_SPEED * maxf(
		0.0,
		1.0 + float(stats.get(&"move_speed_pct", 0.0)) / 100.0
	)


static func effective_max_hp(stats: Dictionary) -> float:
	return BASE_MAX_HP + float(stats.get(&"max_hp", 0.0))


static func effective_area_multiplier(stats: Dictionary) -> float:
	return maxf(0.01, 1.0 + float(stats.get(&"area_pct", 0.0)) / 100.0)


static func effective_pierce(stats: Dictionary) -> int:
	return int(round(float(stats.get(&"pierce", 0.0))))
