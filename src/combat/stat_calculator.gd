class_name StatCalculator
extends RefCounted


const BASE_MOVE_SPEED: float = 5.0
const MIN_COOLDOWN_MULTIPLIER: float = 0.05
const MIN_DURATION_MULTIPLIER: float = 0.05
const MIN_PROJECTILE_SPEED_MULTIPLIER: float = 0.05
const MIN_AREA_MULTIPLIER: float = 0.05


static func aggregate(state: RunState, catalog: DefinitionCatalog) -> Dictionary:
	var totals: Dictionary[StringName, float] = {}
	if state == null or catalog == null:
		return totals
	for runtime: RunPassive in state.passives:
		var definition: PassiveDefinition = catalog.passive(runtime.passive_id)
		if definition == null:
			continue
		totals[definition.stat_id] = (
			totals.get(definition.stat_id, 0.0)
			+ definition.amount_per_level * float(runtime.level)
		)
	return totals


static func stat_value(stats: Dictionary, stat_id: StringName) -> float:
	return float(stats.get(stat_id, 0.0))


static func effective_max_hp(base_max_hp: float, stats: Dictionary) -> float:
	return maxf(1.0, base_max_hp * (1.0 + stat_value(stats, &"max_hp_pct") / 100.0))


static func cooldown_multiplier(stats: Dictionary) -> float:
	return maxf(
		MIN_COOLDOWN_MULTIPLIER,
		1.0 + stat_value(stats, &"cooldown_pct") / 100.0,
	)


static func projectile_speed_multiplier(stats: Dictionary) -> float:
	return maxf(
		MIN_PROJECTILE_SPEED_MULTIPLIER,
		1.0 + stat_value(stats, &"projectile_speed_pct") / 100.0,
	)


static func area_multiplier(stats: Dictionary) -> float:
	return maxf(
		MIN_AREA_MULTIPLIER,
		1.0 + stat_value(stats, &"area_pct") / 100.0,
	)


static func duration_multiplier(stats: Dictionary) -> float:
	return maxf(
		MIN_DURATION_MULTIPLIER,
		1.0 + stat_value(stats, &"duration_pct") / 100.0,
	)


static func might_multiplier(stats: Dictionary) -> float:
	return maxf(0.0, 1.0 + stat_value(stats, &"might_pct") / 100.0)


static func luck_pct(stats: Dictionary) -> float:
	return maxf(0.0, stat_value(stats, &"luck_pct"))


static func recovery_per_second(stats: Dictionary) -> float:
	return maxf(0.0, stat_value(stats, &"recovery_per_second"))
