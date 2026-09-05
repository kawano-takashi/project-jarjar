class_name EliteSpawnDefinition
extends Resource


## 区間開始からの出現時刻。整数tick（60/秒）、0以上かつ所属区間のduration_ticks未満。
@export_range(0, 100, 1, "or_greater", "suffix:tick") var offset_ticks: int = 0
## このエリートが落とす宝箱。NORMALは進化不可、EVOLUTION_CAPABLEは装備条件成立時に進化。撃破・回収時刻によらず固定。
@export var chest_kind: GameTypes.ChestKind = GameTypes.ChestKind.NORMAL
