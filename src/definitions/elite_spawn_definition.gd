class_name EliteSpawnDefinition
extends StageEventDefinition


## この出現で使う基礎HP倍率。有限かつ正。通常敵の区間倍率や出現の遅延に影響されない。
@export_range(0, 100, 0.001, "or_greater") var hp_multiplier: float = 0.0


## このエリートが落とす宝箱。NORMALは進化不可、EVOLUTION_CAPABLEは装備条件成立時に進化。撃破・回収時刻によらず固定。
@export var chest_kind: GameTypes.ChestKind = GameTypes.ChestKind.NORMAL
