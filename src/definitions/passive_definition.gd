class_name PassiveDefinition
extends Resource


## パッシブID。空文字不可、manifest内で重複不可。進化定義から参照する。
@export var passive_id: StringName = &""
## 表示名。空文字不可。数値説明は実際の設定から生成。
@export var display_name: String = ""
## パッシブの最大強化レベル。正整数。能力補正はamount_per_level×現在レベル。
@export_range(0, 100, 1, "or_greater") var max_level: int = 0
## 通常の選択肢抽選の相対重み。有限かつ0以上、同種の合計は正。所有優先と宝箱は正重みの候補から均等に選び、0は抽選対象外。
@export_range(0, 100, 0.001, "or_greater") var selection_weight: float = 0.0
## 補正対象。might_pct/cooldown_pct/projectile_speed_pct/area_pct/duration_pct/max_hp_pct/luck_pct/recovery_per_second。
@export var stat_id: StringName = &""
## 1レベルごとの符号付き補正。有限かつ非0。pctは加算する百分率、recovery_per_secondはHP/秒。最大構成でもHPとLuckの倍率が正、攻撃外縁が上限内。
@export_range(-100, 100, 0.001, "or_greater", "or_less") var amount_per_level: float = 0.0
