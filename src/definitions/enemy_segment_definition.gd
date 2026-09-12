class_name EnemySegmentDefinition
extends Resource

## 区間の長さ。tick（60/秒）、正。開始・終了は配列順から算出。
@export_range(0, 100, 1, "or_greater", "suffix:tick") var duration_ticks: int = 0
## 同時に存在する通常敵の目標数。0以上、EnemyStoreの容量以下。
@export_range(0, 768, 1) var target_active: int = 0
## 基礎HPに掛ける倍率。有限かつ正。
@export_range(0, 100, 0.001, "or_greater") var hp_multiplier: float = 0.0
## 接触ダメージに掛ける倍率。有限かつ0以上。
@export_range(0, 100, 0.001, "or_greater") var damage_multiplier: float = 0.0
## EnemyType順の相対重み。有限・非負・合計正。ELITE/BOSSは0。
@export_range(0, 100, 0.001, "or_greater") var spawn_weights: PackedFloat32Array = PackedFloat32Array()

func weight_for(enemy_type: GameTypes.EnemyType) -> float:
	var index: int = int(enemy_type)
	return 0.0 if index < 0 or index >= spawn_weights.size() else spawn_weights[index]
