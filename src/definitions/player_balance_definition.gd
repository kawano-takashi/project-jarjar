class_name PlayerBalanceDefinition
extends Resource


## 開始時の最大HPと現在HP。有限かつ正。実行中のHPはRunStateで保持。
@export_range(0, 100, 0.001, "or_greater") var base_max_hp: float = 0.0

## 移動速度。m/秒、有限かつ0以上。
@export_range(0, 100, 0.001, "or_greater", "suffix:m/s") var move_speed: float = 0.0

## 身体の当たり判定半径。m、有限かつ正。アリーナに収まること。
@export_range(0, 100, 0.001, "or_greater", "suffix:m") var body_radius: float = 0.0

## 強化選択後の保護時間。tick（60/秒）、0以上。
@export_range(0, 100, 1, "or_greater", "suffix:tick") var level_up_resume_invulnerability_ticks: int = 0

## 連続撃破とみなす間隔。tick（60/秒）、正。
@export_range(0, 100, 1, "or_greater", "suffix:tick") var kill_chain_window_ticks: int = 0
