class_name CombatBalanceDefinition
extends Resource

## 群れ・包囲・ボスを含む敵の同時存在上限。単位は体、正の整数。
## 包囲の人数と対戦相手の合計、および群れの人数がそれぞれ収まること。
@export_range(1, 65536, 1, "or_greater") var enemy_pool_capacity: int = 0
## 味方と敵を合わせた弾の同時存在上限。単位は発、正の整数。
@export_range(1, 65536, 1, "or_greater") var projectile_pool_capacity: int = 0

## 通常敵の接触ダメージに追加で掛ける倍率。有限かつ0以上。エリート・群れ・ボスには適用しない。
@export_range(0, 100, 0.001, "or_greater") var normal_enemy_damage_scale: float = 0.0

## ボスの基礎行動速度倍率。有限かつ正。特殊攻撃の基礎間隔をこの値で割る。
@export_range(0, 100, 0.001, "or_greater") var boss_action_rate_multiplier: float = 0.0

## 激昂1段階ごとの加算威力倍率。有限かつ0以上。最終倍率は1+段階数×この値。
@export_range(0, 100, 0.001, "or_greater") var boss_attack_bonus_per_stack: float = 0.0

## ボス専用の基礎威力倍率。有限かつ0以上。区間倍率と独立。
@export_range(0, 100, 0.001, "or_greater") var boss_damage_multiplier: float = 0.0

## ボスの経過間隔。tick（60/秒）、正。
@export_range(0, 100, 1, "or_greater", "suffix:tick") var boss_enrage_interval_ticks: int = 0

## 激昂の最大段階数。0以上の整数。
@export_range(0, 100, 1, "or_greater") var boss_enrage_max_stacks: int = 0

## ボス専用のHP倍率。有限かつ正。区間倍率と独立。
@export_range(0, 100, 0.001, "or_greater") var boss_hp_multiplier: float = 0.0

## 激昂1段階ごとの行動間隔倍率の減算量。有限かつ0以上。最終間隔倍率は設定された下限で制限。
@export_range(0, 100, 0.001, "or_greater") var boss_interval_reduction_per_stack: float = 0.0

## 能力補正後の下限倍率。有限かつ正。
@export_range(0, 100, 0.001, "or_greater") var min_cooldown_multiplier: float = 0.0

## 能力補正後の下限倍率。有限かつ正。
@export_range(0, 100, 0.001, "or_greater") var min_duration_multiplier: float = 0.0

## 能力補正後の下限倍率。有限かつ正。
@export_range(0, 100, 0.001, "or_greater") var min_projectile_speed_multiplier: float = 0.0

## 能力補正後の下限倍率。有限かつ正。
@export_range(0, 100, 0.001, "or_greater") var min_area_multiplier: float = 0.0

## 攻撃の対象選択半径。m、正かつ効果外縁以下。
@export_range(0, 100, 0.001, "or_greater", "suffix:m") var target_center_radius: float = 0.0

## 攻撃効果の最大外縁。m、正かつダメージ判定半径以下。
@export_range(0, 100, 0.001, "or_greater", "suffix:m") var effect_outer_radius: float = 0.0

## 敵中心に対するダメージ判定半径。m、有限かつ正。
@export_range(0, 100, 0.001, "or_greater", "suffix:m") var damage_center_radius: float = 0.0

## 近接波の扇形角度。度、0より大きく360以下。
@export_range(0.0, 360.0, 0.1, "degrees") var melee_arc_degrees: float = 0.0

## 帰還環の隣接弾の開き。度、0以上360以下。
@export_range(0.0, 360.0, 0.1, "degrees") var returning_ring_spread_degrees: float = 0.0

## ボスの段階ごとの行動間隔倍率。有限かつ正。
@export_range(0, 100, 0.001, "or_greater") var boss_phase_interval_multiplier: float = 0.0

## 激昂と段階を合成した間隔倍率の下限。有限かつ正。
@export_range(0, 100, 0.001, "or_greater") var boss_min_interval_multiplier: float = 0.0

## ボス第2段階のHP割合。0より大きく1以下、第3段階より大きい。
@export_range(0.0, 1.0, 0.001) var boss_phase_two_hp_ratio: float = 0.0

## ボス第3段階のHP割合。0以上、第2段階より小さい。
@export_range(0.0, 1.0, 0.001) var boss_phase_three_hp_ratio: float = 0.0

## STOP中のボス本体と弾の時間倍率。有限かつ0以上1以下。
@export_range(0.0, 1.0, 0.001) var boss_stop_time_scale: float = 0.0

## 周回攻撃の命中間隔。tick（60/秒）、正。
@export_range(0, 100, 1, "or_greater", "suffix:tick") var orbital_damage_interval_ticks: int = 0

## ボスの段階ごとの追加弾数。0以上。
@export_range(0, 100, 1, "or_greater") var boss_volley_phase_bonus: int = 0
