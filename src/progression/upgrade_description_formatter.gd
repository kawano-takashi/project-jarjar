class_name UpgradeDescriptionFormatter
extends RefCounted


static func weapon_detail(definition: WeaponDefinition, next_level: int) -> String:
	if definition == null:
		return ""
	var deltas: Array[WeaponDefinition.WeaponLevelDelta] = definition.level_deltas(next_level)
	if deltas.size() != 1:
		return ""
	var delta: WeaponDefinition.WeaponLevelDelta = deltas[0]
	var label: String = _weapon_stat_label(definition, delta.stat_id)
	match delta.stat_id:
		WeaponDefinition.STAT_COOLDOWN_TICKS, WeaponDefinition.STAT_DURATION_TICKS:
			return "%s %s秒 → %s秒" % [
				label,
				_number(delta.previous_value / float(RunState.TICKS_PER_SECOND)),
				_number(delta.new_value / float(RunState.TICKS_PER_SECOND)),
			]
		WeaponDefinition.STAT_AMOUNT, WeaponDefinition.STAT_PIERCE:
			return "%s %d → %d" % [
				label,
				roundi(delta.previous_value),
				roundi(delta.new_value),
			]
		WeaponDefinition.STAT_PROJECTILE_SPEED:
			return "%s %sm/秒 → %sm/秒" % [
				label,
				_number(delta.previous_value),
				_number(delta.new_value),
			]
		WeaponDefinition.STAT_RANGE, WeaponDefinition.STAT_PROJECTILE_RADIUS, WeaponDefinition.STAT_EFFECT_RADIUS:
			return "%s %sm → %sm" % [
				label,
				_number(delta.previous_value),
				_number(delta.new_value),
			]
		_:
			return "%s %s → %s" % [
				label,
				_number(delta.previous_value),
				_number(delta.new_value),
			]


static func passive_detail(
	definition: PassiveDefinition,
	current_level: int,
	next_level: int,
) -> String:
	if definition == null or current_level <= 0 or next_level <= current_level:
		return ""
	var previous_value: float = definition.amount_per_level * float(current_level)
	var new_value: float = definition.amount_per_level * float(next_level)
	var label: String = _passive_stat_label(definition.stat_id)
	if definition.stat_id == &"recovery_per_second":
		return "%s %s/秒 → %s/秒" % [
			label,
			_signed_number(previous_value),
			_signed_number(new_value),
		]
	return "%s %s%% → %s%%" % [
		label,
		_signed_number(previous_value),
		_signed_number(new_value),
	]


static func _weapon_stat_label(
	definition: WeaponDefinition,
	stat_id: StringName,
) -> String:
	match stat_id:
		WeaponDefinition.STAT_DAMAGE:
			return "威力"
		WeaponDefinition.STAT_COOLDOWN_TICKS:
			return "再展開間隔" if definition.behavior == GameTypes.WeaponBehavior.ORBITAL else "発動間隔"
		WeaponDefinition.STAT_AMOUNT:
			match definition.behavior:
				GameTypes.WeaponBehavior.MELEE_WAVE:
					return "波数"
				GameTypes.WeaponBehavior.ARC_PROJECTILE:
					return "結晶数"
				GameTypes.WeaponBehavior.RETURNING_RING:
					return "環数"
				GameTypes.WeaponBehavior.ORBITAL:
					return "軌道体数"
			return "弾数"
		WeaponDefinition.STAT_PROJECTILE_SPEED:
			return "弾速"
		WeaponDefinition.STAT_RANGE:
			match definition.behavior:
				GameTypes.WeaponBehavior.MELEE_WAVE:
					return "薙ぎ範囲"
				GameTypes.WeaponBehavior.ORBITAL:
					return "周回半径"
			return "射程"
		WeaponDefinition.STAT_PROJECTILE_RADIUS:
			return "弾サイズ" if definition.behavior == GameTypes.WeaponBehavior.MASS_PROJECTILE else "弾半径"
		WeaponDefinition.STAT_EFFECT_RADIUS:
			return "爆発半径" if definition.behavior == GameTypes.WeaponBehavior.ARC_PROJECTILE else "効果半径"
		WeaponDefinition.STAT_DURATION_TICKS:
			return "持続時間"
		WeaponDefinition.STAT_PIERCE:
			return "貫通数"
	return "強化"


static func _passive_stat_label(stat_id: StringName) -> String:
	match stat_id:
		&"max_hp_pct":
			return "最大HP"
		&"cooldown_pct":
			return "クールダウン"
		&"projectile_speed_pct":
			return "弾速"
		&"area_pct":
			return "攻撃範囲"
		&"luck_pct":
			return "Luck"
		&"duration_pct":
			return "持続時間"
		&"might_pct":
			return "威力"
		&"recovery_per_second":
			return "HP回復"
	return "効果"


static func _number(value: float) -> String:
	var result: String = "%.2f" % value
	result = result.trim_suffix("0").trim_suffix("0").trim_suffix(".")
	return result


static func _signed_number(value: float) -> String:
	if value > 0.0:
		return "+%s" % _number(value)
	return _number(value)
