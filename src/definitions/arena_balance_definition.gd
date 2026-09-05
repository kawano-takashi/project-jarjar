class_name ArenaBalanceDefinition
extends Resource


## アリーナの幅と奥行。m、両成分が有限かつ正。全配置と身体が収まる寸法。
@export var size: Vector2 = Vector2.ZERO

## 破壊可能ノードの配置座標。m、各ノードがアリーナ内に収まる位置。
@export var node_site_positions: PackedVector2Array = PackedVector2Array()

## 初期に有効な配置番号。重複なし、配置配列の範囲内。以後もこの個数まで再配置する。
@export_range(0, 100, 1, "or_greater") var initial_active_sites: PackedInt32Array = PackedInt32Array()

## 破壊可能ノードのHP。有限かつ正。
@export_range(0, 100, 0.001, "or_greater") var node_max_hp: float = 0.0

## ノードの当たり判定半径。m、有限かつ正。
@export_range(0, 100, 0.001, "or_greater", "suffix:m") var node_body_radius: float = 0.0

## 宝箱・パワーアップの回収半径。m、有限かつ0以上。
@export_range(0, 100, 0.001, "or_greater", "suffix:m") var pickup_collect_radius: float = 0.0

## ノード破壊から再配置までの時間。正整数tick（60/秒）。
@export_range(0, 100, 1, "or_greater", "suffix:tick") var node_respawn_ticks: int = 0

## 回復HP。有限かつ0以上。
@export_range(0, 100, 0.001, "or_greater") var node_heal_amount: float = 0.0

## 効果時間。tick（60/秒）、0以上。
@export_range(0, 100, 1, "or_greater", "suffix:tick") var node_stop_ticks: int = 0

## ドロップの相対重み。NONE/HEAL/VACUUM/STOP順、有限・非負、合計は正。
@export_range(0, 100, 0.001, "or_greater") var node_drop_weights: PackedFloat32Array = PackedFloat32Array()
