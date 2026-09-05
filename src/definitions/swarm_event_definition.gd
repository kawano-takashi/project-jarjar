class_name SwarmEventDefinition
extends Resource


## 群れイベントID。空文字不可。
@export var event_id: StringName = &""
## 群れ個体のEnemyDefinition。必須、接触専用のSWARMER。
@export var unit_definition: EnemyDefinition = null
var member_count: int:
	get:
		return lateral_count * depth_count
## 隊列の横方向の人数。正整数。depth_countとの積が敵プール容量以下。
@export_range(0, 100, 1, "or_greater") var lateral_count: int = 0
## 隊列の奥行方向の人数。正整数。lateral_countとの積が敵プール容量以下。
@export_range(0, 100, 1, "or_greater") var depth_count: int = 0
## 横方向の個体間隔。m、有限かつ正。
@export_range(0, 100, 0.001, "or_greater", "suffix:m") var lateral_pitch: float = 0.0
## 奥行方向の個体間隔。m、有限かつ正。
@export_range(0, 100, 0.001, "or_greater", "suffix:m") var depth_pitch: float = 0.0
