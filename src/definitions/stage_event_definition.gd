class_name StageEventDefinition
extends Resource


## イベント予定ID。空文字不可、タイムライン全体で重複不可。
@export var event_id: StringName = &""
## ラン開始からの絶対時刻。整数tick（60/秒）、0以上かつ通常戦終了より前。
## 群れでは最初の予告試行、包囲ではエリートと花の出現を開始する。
@export_range(0, 72000, 1, "or_greater", "suffix:tick") var start_tick: int = 0
