class_name EnemyDefinition
extends Resource


## 敵ID。空文字不可、通常の敵一覧内で重複不可。
@export var enemy_id: StringName = &""
## 表示名。空文字不可。数値説明は実際の設定から生成。
@export var display_name: String = ""
## 敵の動作種別。EnemyTypeの列挙値、manifest内で各種別に1定義。
@export var enemy_type: GameTypes.EnemyType = GameTypes.EnemyType.PURSUER
## 敵の基礎HP。有限かつ正。通常は区間倍率、ボスは専用倍率、包囲個体は出現時プレイヤーレベルを掛ける。
@export_range(0, 100, 0.001, "or_greater") var base_hp: float = 0.0
## 移動速度。m/秒、有限かつ0以上。
@export_range(0, 100, 0.001, "or_greater", "suffix:m/s") var move_speed: float = 0.0
## 身体の当たり判定半径。m、有限かつ正。アリーナに収まること。
@export_range(0, 100, 0.001, "or_greater", "suffix:m") var body_radius: float = 0.0
## 接触時の基礎ダメージ。HP/tick、有限かつ0以上。区間/ボスの倍率を掛ける。
@export_range(0, 100, 0.001, "or_greater") var contact_damage: float = 0.0
## ボス特殊攻撃の基礎間隔。整数tick（60/秒）。0で無効、通常敵は0。
@export_range(0, 100, 1, "or_greater", "suffix:tick") var special_interval_ticks: int = 0
## ボス弾の予告時間。整数tick（60/秒）。特殊攻撃ありなら正、通常敵は0。予告時間は実際の発射間隔の下限。
@export_range(0, 100, 1, "or_greater", "suffix:tick") var telegraph_ticks: int = 0
## ボス弾1命中の基礎ダメージ。HP、有限かつ0以上、通常敵は0。
@export_range(0, 100, 0.001, "or_greater") var projectile_damage: float = 0.0
## ボス弾の速度。m/秒、有限かつ0以上、通常敵は0。
@export_range(0, 100, 0.001, "or_greater", "suffix:m/s") var projectile_speed: float = 0.0
## ボス弾の当たり判定半径。m、有限かつ0以上、通常敵は0。
@export_range(0, 100, 0.001, "or_greater", "suffix:m") var projectile_radius: float = 0.0
## ボス弾の寿命。整数tick（60/秒）。特殊攻撃ありなら正、通常敵は0。
@export_range(0, 100, 1, "or_greater", "suffix:tick") var projectile_lifetime_ticks: int = 0
## ボス第1段階の放射弾数。整数。特殊攻撃ありなら正、通常敵は0。段階ごとにcombatの追加数を加算。
@export_range(0, 100, 1, "or_greater") var volley_count: int = 0
## 撃破時に出す基礎経験値。XP、0以上の整数。0なら経験値を出さない。
@export_range(0, 100, 1, "or_greater") var xp_value: int = 0
