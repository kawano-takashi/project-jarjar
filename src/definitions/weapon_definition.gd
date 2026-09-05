class_name WeaponDefinition
extends Resource


const STAT_DAMAGE: StringName = &"damage"
const STAT_COOLDOWN_TICKS: StringName = &"cooldown_ticks"
const STAT_AMOUNT: StringName = &"amount"
const STAT_PROJECTILE_SPEED: StringName = &"projectile_speed"
const STAT_RANGE: StringName = &"range"
const STAT_PROJECTILE_RADIUS: StringName = &"projectile_radius"
const STAT_EFFECT_RADIUS: StringName = &"effect_radius"
const STAT_DURATION_TICKS: StringName = &"duration_ticks"
const STAT_PIERCE: StringName = &"pierce"


class WeaponLevelDelta:
	extends RefCounted

	var stat_id: StringName = &""
	var previous_value: float = 0.0
	var new_value: float = 0.0

	func _init(
		p_stat_id: StringName,
		p_previous_value: float,
		p_new_value: float,
	) -> void:
		stat_id = p_stat_id
		previous_value = p_previous_value
		new_value = p_new_value


## 武器ID。空文字不可、manifest内で重複不可。
@export var weapon_id: StringName = &""
## 表示名。空文字不可。数値説明は実際の設定から生成。
@export var display_name: String = ""
## 武器の動作を説明する文章。数値の重複記載は避ける。
@export_multiline var description: String = ""
## 攻撃処理の種類。WeaponBehaviorの列挙から選択。
@export var behavior: GameTypes.WeaponBehavior = GameTypes.WeaponBehavior.MELEE_WAVE
## 進化専用武器ならtrue。レベル配列長は1、抽選重みは0、進化定義の参照が必須。
@export var is_evolved: bool = false
var max_level: int:
	get:
		return damage_by_level.size()
## 通常の選択肢抽選の相対重み。有限かつ0以上、同種の合計は正。所有優先と宝箱は正重みの候補から均等に選び、0は抽選対象外。
@export_range(0, 100, 0.001, "or_greater") var selection_weight: float = 0.0
## 各レベルのdamage。HP/命中、有限かつ正。Lv1から順に格納、全レベル配列の長さはdamage_by_levelと一致。隣接レベルは最低1項目を変更。
@export_range(0, 100, 0.001, "or_greater") var damage_by_level: PackedFloat32Array = PackedFloat32Array()
## 各レベルのcooldown_ticks。整数tick（60/秒）、有限かつ正。Lv1から順に格納、全レベル配列の長さはdamage_by_levelと一致。隣接レベルは最低1項目を変更。
@export_range(0, 100, 1, "or_greater", "suffix:tick") var cooldown_ticks_by_level: PackedInt32Array = PackedInt32Array()
## 各レベルのamount。個、有限かつ正。Lv1から順に格納、全レベル配列の長さはdamage_by_levelと一致。隣接レベルは最低1項目を変更。
@export_range(0, 100, 1, "or_greater") var amount_by_level: PackedInt32Array = PackedInt32Array()
## 各レベルのprojectile_speed。m/秒、有限かつ0以上。Lv1から順に格納、全レベル配列の長さはdamage_by_levelと一致。隣接レベルは最低1項目を変更。
@export_range(0, 100, 0.001, "or_greater", "suffix:m/s") var projectile_speed_by_level: PackedFloat32Array = PackedFloat32Array()
## 各レベルのrange。m、有限かつ0以上。Lv1から順に格納、全レベル配列の長さはdamage_by_levelと一致。隣接レベルは最低1項目を変更。周回武器のrangeは正。
@export_range(0, 100, 0.001, "or_greater", "suffix:m") var range_by_level: PackedFloat32Array = PackedFloat32Array()
## 各レベルのprojectile_radius。m、有限かつ0以上。Lv1から順に格納、全レベル配列の長さはdamage_by_levelと一致。隣接レベルは最低1項目を変更。
@export_range(0, 100, 0.001, "or_greater", "suffix:m") var projectile_radius_by_level: PackedFloat32Array = PackedFloat32Array()
## 各レベルのeffect_radius。m、有限かつ0以上。Lv1から順に格納、全レベル配列の長さはdamage_by_levelと一致。隣接レベルは最低1項目を変更。
@export_range(0, 100, 0.001, "or_greater", "suffix:m") var effect_radius_by_level: PackedFloat32Array = PackedFloat32Array()
## trueならrangeにarea補正倍率を掛ける。falseなら表の値を使う。最大強化時もcombatの効果外縁以内。
@export var range_scales_with_area: bool = false
## trueならprojectile_radiusにarea補正倍率を掛ける。falseなら表の値を使う。最大強化時もcombatの効果外縁以内。
@export var projectile_radius_scales_with_area: bool = false
## trueならeffect_radiusにarea補正倍率を掛ける。falseなら表の値を使う。最大強化時もcombatの効果外縁以内。
@export var effect_radius_scales_with_area: bool = false
## 各レベルのduration_ticks。整数tick（60/秒）、有限かつ0以上。Lv1から順に格納、全レベル配列の長さはdamage_by_levelと一致。隣接レベルは最低1項目を変更。
@export_range(0, 100, 1, "or_greater", "suffix:tick") var duration_ticks_by_level: PackedInt32Array = PackedInt32Array()
## 各レベルのpierce。追加貫通数、有限かつ0以上。Lv1から順に格納、全レベル配列の長さはdamage_by_levelと一致。隣接レベルは最低1項目を変更。
@export_range(0, 100, 1, "or_greater") var pierce_by_level: PackedInt32Array = PackedInt32Array()
## 1命中ごとのクリティカル確率。有限な0〜1。
@export_range(0.0, 1.0, 0.001) var critical_chance: float = 0.0
## クリティカル時の威力倍率。有限かつ1以上。
@export_range(0, 100, 0.001, "or_greater") var critical_multiplier: float = 0.0
## 与ダメージから回復するHPの割合。有限な0〜1。
@export_range(0.0, 1.0, 0.001) var life_steal_ratio: float = 0.0


func damage_at(level: int) -> float:
	return _float_at(damage_by_level, level)


func cooldown_ticks_at(level: int) -> int:
	return _int_at(cooldown_ticks_by_level, level)


func amount_at(level: int) -> int:
	return _int_at(amount_by_level, level)


func projectile_speed_at(level: int) -> float:
	return _float_at(projectile_speed_by_level, level)


func range_at(level: int) -> float:
	return _float_at(range_by_level, level)


func projectile_radius_at(level: int) -> float:
	return _float_at(projectile_radius_by_level, level)


func effect_radius_at(level: int) -> float:
	return _float_at(effect_radius_by_level, level)


func duration_ticks_at(level: int) -> int:
	return _int_at(duration_ticks_by_level, level)


func pierce_at(level: int) -> int:
	return _int_at(pierce_by_level, level)


func level_deltas(next_level: int) -> Array[WeaponLevelDelta]:
	var result: Array[WeaponLevelDelta] = []
	if next_level < 2 or next_level > max_level:
		return result
	var previous_level: int = next_level - 1
	_append_float_delta(
		result,
		STAT_DAMAGE,
		damage_at(previous_level),
		damage_at(next_level),
	)
	_append_int_delta(
		result,
		STAT_COOLDOWN_TICKS,
		cooldown_ticks_at(previous_level),
		cooldown_ticks_at(next_level),
	)
	_append_int_delta(
		result,
		STAT_AMOUNT,
		amount_at(previous_level),
		amount_at(next_level),
	)
	_append_float_delta(
		result,
		STAT_PROJECTILE_SPEED,
		projectile_speed_at(previous_level),
		projectile_speed_at(next_level),
	)
	_append_float_delta(
		result,
		STAT_RANGE,
		range_at(previous_level),
		range_at(next_level),
	)
	_append_float_delta(
		result,
		STAT_PROJECTILE_RADIUS,
		projectile_radius_at(previous_level),
		projectile_radius_at(next_level),
	)
	_append_float_delta(
		result,
		STAT_EFFECT_RADIUS,
		effect_radius_at(previous_level),
		effect_radius_at(next_level),
	)
	_append_int_delta(
		result,
		STAT_DURATION_TICKS,
		duration_ticks_at(previous_level),
		duration_ticks_at(next_level),
	)
	_append_int_delta(
		result,
		STAT_PIERCE,
		pierce_at(previous_level),
		pierce_at(next_level),
	)
	return result


func _append_float_delta(
	result: Array[WeaponLevelDelta],
	stat_id: StringName,
	previous_value: float,
	new_value: float,
) -> void:
	if previous_value != new_value:
		result.append(WeaponLevelDelta.new(stat_id, previous_value, new_value))


func _append_int_delta(
	result: Array[WeaponLevelDelta],
	stat_id: StringName,
	previous_value: int,
	new_value: int,
) -> void:
	if previous_value != new_value:
		result.append(WeaponLevelDelta.new(stat_id, previous_value, new_value))


func _float_at(values: PackedFloat32Array, level: int) -> float:
	if values.is_empty():
		return 0.0
	var index: int = clampi(level - 1, 0, values.size() - 1)
	return values[index]


func _int_at(values: PackedInt32Array, level: int) -> int:
	if values.is_empty():
		return 0
	var index: int = clampi(level - 1, 0, values.size() - 1)
	return values[index]
