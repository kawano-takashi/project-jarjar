class_name SpawnBalanceDefinition
extends Resource


## 通常敵の目標数へ補充する基準時間。tick（60/秒）、有限かつ正。
@export_range(0, 100, 1, "or_greater", "suffix:tick") var target_ramp_ticks: int = 0

## 出現距離の内側。m、0以上かつ外側以下。
@export_range(0, 100, 0.001, "or_greater", "suffix:m") var inner_half_extent: float = 0.0

## 出現距離の外側。m、内側以上。
@export_range(0, 100, 0.001, "or_greater", "suffix:m") var outer_half_extent: float = 0.0

## 通常敵を消去する遠方距離。m、出現の外側より大きい。
@export_range(0, 100, 0.001, "or_greater", "suffix:m") var normal_despawn_half_extent: float = 0.0

## 通常敵の出現保護時間。tick（60/秒）、0以上。
@export_range(0, 100, 1, "or_greater", "suffix:tick") var normal_entry_ticks: int = 0

## エリートの出現保護時間。tick（60/秒）、0以上。
@export_range(0, 100, 1, "or_greater", "suffix:tick") var elite_entry_ticks: int = 0

## ボスの出現保護時間。tick（60/秒）、0以上。
@export_range(0, 100, 1, "or_greater", "suffix:tick") var boss_entry_ticks: int = 0

## 目標未達時の最低補充速度。体/秒、有限かつ0以上。
@export_range(0, 100, 0.001, "or_greater") var minimum_spawns_per_second: float = 0.0
