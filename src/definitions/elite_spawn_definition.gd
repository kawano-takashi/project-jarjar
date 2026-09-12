class_name EliteSpawnDefinition
extends StageEventDefinition


## このエリートが落とす宝箱。NORMALは進化不可、EVOLUTION_CAPABLEは装備条件成立時に進化。撃破・回収時刻によらず固定。
@export var chest_kind: GameTypes.ChestKind = GameTypes.ChestKind.NORMAL
