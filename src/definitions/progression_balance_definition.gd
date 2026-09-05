class_name ProgressionBalanceDefinition
extends Resource


## 必要経験値の一次式の係数。XP/レベル、整数。到達可能レベルで必要XPが正。
@export_range(-100, 100, 1, "or_greater", "or_less") var xp_early_coefficient: int = 0

## 経験値の最初の一次式を使う最後のレベル。正整数。次の1レベルはfirst_transition_requirementを使う。
@export_range(0, 100, 1, "or_greater") var xp_early_max_level: int = 0

## 必要経験値の一次式に加える符号付きXP。到達可能レベルで必要XPが正になる値。
@export_range(-100, 100, 1, "or_greater", "or_less") var xp_early_offset: int = 0

## 経験値補償を適用する現在レベル。重複のない正整数。
@export_range(0, 100, 1, "or_greater") var xp_growth_compensation_levels: PackedInt32Array = PackedInt32Array()

## 補償レベルでの獲得XP倍率。有限な1以上の整数。
@export_range(0, 100, 0.001, "or_greater") var xp_growth_compensation_multiplier: float = 0.0

## 必要経験値の一次式の係数。XP/レベル、整数。到達可能レベルで必要XPが正。
@export_range(-100, 100, 1, "or_greater", "or_less") var xp_late_coefficient: int = 0

## 必要経験値の一次式に加える符号付きXP。到達可能レベルで必要XPが正になる値。
@export_range(-100, 100, 1, "or_greater", "or_less") var xp_late_offset: int = 0

## 最初の境界レベル（early_max_level+1）の必要XP。正整数。
@export_range(0, 100, 1, "or_greater") var xp_first_transition_requirement: int = 0

## 2番目の境界レベル（middle_max_level+1）の必要XP。正整数。
@export_range(0, 100, 1, "or_greater") var xp_second_transition_requirement: int = 0

## 必要経験値の一次式の係数。XP/レベル、整数。到達可能レベルで必要XPが正。
@export_range(-100, 100, 1, "or_greater", "or_less") var xp_middle_coefficient: int = 0

## 経験値の中間一次式を使う最後のレベル。early_max_level+1より大きい。次の1レベルはsecond_transition_requirementを使う。
@export_range(0, 100, 1, "or_greater") var xp_middle_max_level: int = 0

## 必要経験値の一次式に加える符号付きXP。到達可能レベルで必要XPが正になる値。
@export_range(-100, 100, 1, "or_greater", "or_less") var xp_middle_offset: int = 0

## 経験値回収の半径。m、有限かつ0以上。回収半径は吸引半径以下。
@export_range(0, 100, 0.001, "or_greater", "suffix:m") var xp_pickup_attract_radius: float = 0.0

## 経験値回収の半径。m、有限かつ0以上。回収半径は吸引半径以下。
@export_range(0, 100, 0.001, "or_greater", "suffix:m") var xp_pickup_collect_radius: float = 0.0

## 経験値吸引速度。m/秒、有限かつ0以上。
@export_range(0, 100, 0.001, "or_greater", "suffix:m/s") var xp_pickup_speed: float = 0.0

## 経験値ピックアップのプール個数。正整数。満杯では既存ピックアップへ経験値を合算。
@export_range(0, 100, 1, "or_greater") var xp_pool_capacity: int = 0

## 獲得XPの割合。%、0以上の整数。余りはrun状態で保持。
@export_range(0, 100, 1, "or_greater") var xp_yield_percent: int = 0

## 所持できる武器の枠数。正整数。開始武器を含む。
@export_range(0, 100, 1, "or_greater") var weapon_slot_count: int = 0

## 所持できるパッシブの枠数。0以上の整数。0なら選択肢に出ない。
@export_range(0, 100, 1, "or_greater") var passive_slot_count: int = 0

## 1回のレベルアップで提示する最大候補数。正整数。候補不足なら存在する数のみ提示。
@export_range(0, 100, 1, "or_greater") var level_offer_count: int = 0

## 空き装備枠があるときの所有済み候補の優先試行回数。0以上の整数。
@export_range(0, 100, 1, "or_greater") var owned_offer_attempt_count: int = 0

## Luckに対する所有済み候補の抽選係数。有限かつ0以上。
@export_range(0, 100, 0.001, "or_greater") var owned_offer_luck_coefficient: float = 0.0

## 偶数レベルで所有済み候補の抽選係数に掛ける倍率。有限かつ0以上。
@export_range(0, 100, 0.001, "or_greater") var owned_offer_even_level_multiplier: float = 0.0

## 開始武器ID。manifest内の通常武器を参照。
@export var starter_weapon_id: StringName = &""

## 1runの進化上限。回、0以上。
@export_range(0, 100, 1, "or_greater") var max_evolutions_per_run: int = 0
