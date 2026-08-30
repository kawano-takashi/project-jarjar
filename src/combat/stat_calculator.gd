class_name StatCalculator
extends RefCounted


const ATTACK_INTERVAL_MIN_SECONDS: float = 0.05
const BASE_MOVE_SPEED: float = 5.0
const BASE_MAX_HP: float = 100.0
const AFFIX_IDS: Array[StringName] = [
	&"damage_pct",
	&"attack_speed_pct",
	&"area_pct",
	&"pierce",
	&"max_hp",
	&"damage_reduction_pct",
	&"move_speed_pct",
]


static func aggregate_affixes(equipped: Dictionary) -> Dictionary:
	var totals: Dictionary = {}
	for affix_id: StringName in AFFIX_IDS:
		totals[affix_id] = 0.0
	for value: Variant in equipped.values():
		var item: ItemInstance = value as ItemInstance
		if item == null or item.category != GameTypes.ItemCategory.CHARM:
			continue
		for affix: AffixRoll in item.affixes:
			if affix == null or affix.affix_id not in AFFIX_IDS:
				continue
			totals[affix.affix_id] = float(totals[affix.affix_id]) + affix.value
	return totals


static func damage_multiplier(stats: Dictionary) -> float:
	return maxf(0.0, 1.0 + float(stats.get(&"damage_pct", 0.0)) / 100.0)


static func effective_attack_interval(base_interval: float, stats: Dictionary) -> float:
	var attack_speed_pct: float = float(stats.get(&"attack_speed_pct", 0.0))
	var speed_denominator: float = maxf(0.01, 1.0 + attack_speed_pct / 100.0)
	return maxf(ATTACK_INTERVAL_MIN_SECONDS, base_interval / speed_denominator)


static func effective_damage_reduction_pct(equipped: Dictionary) -> float:
	var stats: Dictionary = aggregate_affixes(equipped)
	return clampf(float(stats.get(&"damage_reduction_pct", 0.0)), 0.0, 100.0)


static func apply_incoming_damage(raw_damage: float, damage_reduction_pct: float) -> float:
	return maxf(0.0, raw_damage) * (
		1.0 - clampf(damage_reduction_pct, 0.0, 100.0) / 100.0
	)


static func effective_move_speed(stats: Dictionary) -> float:
	return BASE_MOVE_SPEED * maxf(
		0.0,
		1.0 + float(stats.get(&"move_speed_pct", 0.0)) / 100.0,
	)


static func effective_max_hp(stats: Dictionary) -> float:
	return BASE_MAX_HP + float(stats.get(&"max_hp", 0.0))


static func effective_area_multiplier(stats: Dictionary) -> float:
	return maxf(0.01, 1.0 + float(stats.get(&"area_pct", 0.0)) / 100.0)


static func effective_pierce(stats: Dictionary) -> int:
	return maxi(0, int(round(float(stats.get(&"pierce", 0.0)))))
