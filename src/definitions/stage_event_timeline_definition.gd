class_name StageEventTimelineDefinition
extends Resource


## 群れ・エリート包囲の予定の正本。null不可。同時刻は包囲を先に処理し、同種は配列順。
## ボス開始は通常区間の終了から導出するため、ここに重複して定義しない。
@export var events: Array[StageEventDefinition] = []
