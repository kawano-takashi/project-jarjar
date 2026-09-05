class_name SwarmEventScheduleDefinition
extends Resource


## 群れの予定ID。空文字不可、所属区間内で重複不可。
@export var schedule_id: StringName = &""
## 最初の試行時刻。区間開始からの整数tick、0以上。全試行を区間内に収める。
@export_range(0, 100, 1, "or_greater", "suffix:tick") var first_offset_ticks: int = 0
## 試行間隔。正整数tick（60/秒）。first_offset+(attempt_count−1)×intervalが区間長未満。
@export_range(0, 100, 1, "or_greater", "suffix:tick") var interval_ticks: int = 0
## 試行回数。0以上の整数。0で無効。
@export_range(0, 100, 1, "or_greater") var attempt_count: int = 0
## 各試行で群れが発生する確率。有限な0〜1。抽選の相対重みではない。
@export_range(0.0, 1.0, 0.001) var spawn_chance: float = 0.0
