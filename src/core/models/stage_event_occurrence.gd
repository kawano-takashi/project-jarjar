class_name StageEventOccurrence
extends RefCounted


enum Kind { BOSS, ELITE_ENCOUNTER, SWARM }

## 検証済み定義から展開した読み取り専用の予定。消費状態は実行器が保持する。
var kind: Kind = Kind.SWARM
var tick: int = 0
var definition: StageEventDefinition = null
var definition_order: int = 0
var elite_serial: int = -1
