class_name SpawnBalanceDefinition
extends Resource


## 通常敵の目標数へ補充する基準時間。tick（60/秒）、有限かつ正。
@export_range(0, 100, 1, "or_greater", "suffix:tick") var target_ramp_ticks: int = 0

## 可視範囲の外に設ける出現帯の幅。m、有限かつ正。身体全体が画面外に収まる。
@export_range(0, 100, 0.001, "or_greater", "suffix:m") var offscreen_band_width: float = 0.0

## 出現帯の外側から遠方整理までの余白。m、有限かつ正。
## 通常敵は消去、エリート・ボスは同じ個体のまま画面外へ再配置する。
@export_range(0, 100, 0.001, "or_greater", "suffix:m") var despawn_margin: float = 0.0

## 通常敵の出現保護時間。tick（60/秒）、0以上。
@export_range(0, 100, 1, "or_greater", "suffix:tick") var normal_entry_ticks: int = 0

## エリートの出現保護時間。tick（60/秒）、0以上。
@export_range(0, 100, 1, "or_greater", "suffix:tick") var elite_entry_ticks: int = 0

## ボスの出現保護時間。tick（60/秒）、0以上。
@export_range(0, 100, 1, "or_greater", "suffix:tick") var boss_entry_ticks: int = 0

## 目標未達時の最低補充速度。体/秒、有限かつ0以上。
@export_range(0, 100, 0.001, "or_greater") var minimum_spawns_per_second: float = 0.0
