class_name SwarmEventScheduleDefinition
extends StageEventDefinition


## 試行間隔。正整数tick（60/秒）。start_tick+(attempt_count−1)×intervalが通常戦終了より前。
@export_range(0, 100, 1, "or_greater", "suffix:tick") var interval_ticks: int = 0
## 試行回数。0以上の整数。0で無効。別の群れが予告・通過中なら試行を消費して見送る。
@export_range(0, 100, 1, "or_greater") var attempt_count: int = 0
## 各試行で群れが発生する確率。有限な0〜1。抽選の相対重みではない。
@export_range(0.0, 1.0, 0.001) var spawn_chance: float = 0.0
## 群れ個体の基礎HP倍率。有限かつ正。通常敵の区間倍率は適用しない。
@export_range(0, 100, 0.001, "or_greater") var hp_multiplier: float = 0.0
## 群れ個体の接触ダメージ倍率。有限かつ0以上。通常敵の区間・共通ダメージ倍率は適用しない。
@export_range(0, 100, 0.001, "or_greater") var damage_multiplier: float = 0.0
