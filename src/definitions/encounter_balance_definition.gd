class_name EncounterBalanceDefinition
extends Resource


## 包囲個体の専用定義。必須の追跡型PURSUER。HPは出現時レベルを掛け、区間HP倍率は掛けない。
@export var unit_definition: EnemyDefinition = null
## エリート1体に所属する包囲個体数。正整数、相手を含め敵プール容量以下。
@export_range(1, 767, 1) var member_count: int = 0
## 出現時の楕円の横半径。m、有限かつ正。相手と包囲個体の身体が重ならない広さ。
@export_range(0, 100, 0.01, "or_greater", "suffix:m") var elite_radius_x: float = 0.0
## 出現時の楕円の縦半径。m、有限かつ正。相手と包囲個体の身体が重ならない広さ。
@export_range(0, 100, 0.01, "or_greater", "suffix:m") var elite_radius_y: float = 0.0
## 出現保護終了からの包囲寿命。正整数tick（60/秒）。STOPでは停止しない。
@export_range(1, 7200, 1, "or_greater", "suffix:tick") var elite_lifetime_ticks: int = 0
## プレイヤーから相手の初期中心までの距離。m、身体が重ならず両方の囲いに収まること。
@export_range(0, 100, 0.01, "or_greater", "suffix:m") var opponent_distance: float = 0.0
## ボス囲いの出現半径。m、終了半径以上。中心は出現時のプレイヤー位置に固定。
@export_range(0, 100, 0.01, "or_greater", "suffix:m") var boss_initial_radius: float = 0.0
## 縮小停止後のボス囲いの半径。m、プレイヤーとボスの身体が収まる正の値。
@export_range(0, 100, 0.01, "or_greater", "suffix:m") var boss_final_radius: float = 0.0
## ボス出現保護終了から縮小停止まで。正整数tick（60/秒）。STOPでは停止しない。
@export_range(1, 7200, 1, "or_greater", "suffix:tick") var boss_shrink_ticks: int = 0
