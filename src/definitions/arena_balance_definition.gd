class_name ArenaBalanceDefinition
extends Resource


## 開始時に画面外へ配置する破壊物の数。個、0以上かつnode_capacity以下。
@export_range(0, 100, 1, "or_greater") var node_initial_count: int = 0

## 同時に存在できる破壊物の数。個、正整数。上限時は画面外の個体を入れ替える。
@export_range(1, 100, 1, "or_greater") var node_capacity: int = 0

## 破壊物の出現抽選間隔。正整数tick（60/秒）。戦闘中だけ進行する。
@export_range(1, 3600, 1, "or_greater", "suffix:tick") var node_spawn_interval_ticks: int = 0

## 1回の抽選で出現する基本確率。0〜1、node_spawn_chance_max以下。
@export_range(0, 1, 0.001) var node_spawn_chance: float = 0.0

## Luck補正後の出現確率の上限。0〜1。個数上限時は基本確率だけを使う。
@export_range(0, 1, 0.001) var node_spawn_chance_max: float = 0.0

## 破壊可能ノードのHP。有限かつ正。
@export_range(0, 100, 0.001, "or_greater") var node_max_hp: float = 0.0

## ノードの当たり判定半径。m、有限かつ正。
@export_range(0, 100, 0.001, "or_greater", "suffix:m") var node_body_radius: float = 0.0

## 宝箱・パワーアップの回収半径。m、有限かつ0以上。
@export_range(0, 100, 0.001, "or_greater", "suffix:m") var pickup_collect_radius: float = 0.0

## 回復HP。有限かつ0以上。
@export_range(0, 100, 0.001, "or_greater") var node_heal_amount: float = 0.0

## 効果時間。tick（60/秒）、0以上。
@export_range(0, 100, 1, "or_greater", "suffix:tick") var node_stop_ticks: int = 0

## ドロップの相対重み。NONE/HEAL/VACUUM/STOP順、有限・非負、合計は正。
@export_range(0, 100, 0.001, "or_greater") var node_drop_weights: PackedFloat32Array = PackedFloat32Array()
