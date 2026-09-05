class_name StatCalculator
extends RefCounted


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
	return base_max_hp * (1.0 + stat_value(stats, &"max_hp_pct") / 100.0)


static func cooldown_multiplier(stats: Dictionary, balance: CombatBalanceDefinition) -> float:
	return maxf(
		balance.min_cooldown_multiplier,
		1.0 + stat_value(stats, &"cooldown_pct") / 100.0,
	)


static func projectile_speed_multiplier(stats: Dictionary, balance: CombatBalanceDefinition) -> float:
	return maxf(
		balance.min_projectile_speed_multiplier,
		1.0 + stat_value(stats, &"projectile_speed_pct") / 100.0,
	)


static func area_multiplier(stats: Dictionary, balance: CombatBalanceDefinition) -> float:
	return maxf(
		balance.min_area_multiplier,
		1.0 + stat_value(stats, &"area_pct") / 100.0,
	)


static func duration_multiplier(stats: Dictionary, balance: CombatBalanceDefinition) -> float:
	return maxf(
		balance.min_duration_multiplier,
		1.0 + stat_value(stats, &"duration_pct") / 100.0,
	)


static func might_multiplier(stats: Dictionary) -> float:
	return maxf(0.0, 1.0 + stat_value(stats, &"might_pct") / 100.0)


static func luck_pct(stats: Dictionary) -> float:
	return maxf(0.0, stat_value(stats, &"luck_pct"))


static func recovery_per_second(stats: Dictionary) -> float:
	return maxf(0.0, stat_value(stats, &"recovery_per_second"))

static func weapon_range(definition: WeaponDefinition, level: int, area: float) -> float:
	return definition.range_at(level) * (maxf(0.0, area) if definition.range_scales_with_area else 1.0)


static func weapon_projectile_radius(definition: WeaponDefinition, level: int, area: float) -> float:
	return definition.projectile_radius_at(level) * (maxf(0.0, area) if definition.projectile_radius_scales_with_area else 1.0)


static func weapon_effect_radius(definition: WeaponDefinition, level: int, area: float) -> float:
	return definition.effect_radius_at(level) * (maxf(0.0, area) if definition.effect_radius_scales_with_area else 1.0)


static func weapon_outer_radius(definition: WeaponDefinition, level: int, area: float) -> float:
	var reach: float = weapon_range(definition, level, area)
	var effect: float = weapon_effect_radius(definition, level, area)
	match definition.behavior:
		GameTypes.WeaponBehavior.MELEE_WAVE:
			return reach
		GameTypes.WeaponBehavior.ORBITAL:
			return reach + effect
		GameTypes.WeaponBehavior.AURA:
			return effect
	return reach + maxf(weapon_projectile_radius(definition, level, area), effect)
