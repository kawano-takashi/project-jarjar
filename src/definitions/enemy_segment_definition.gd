class_name EnemySegmentDefinition
extends Resource


@export var segment_index: int = 0
@export var start_tick: int = 0
@export var end_tick: int = 0
@export var target_active: int = 0
@export var hp_multiplier: float = 1.0
@export var damage_multiplier: float = 1.0
@export var spawn_weights: PackedFloat32Array = PackedFloat32Array()


func weight_for(enemy_type: GameTypes.EnemyType) -> float:
	var index: int = int(enemy_type)
	return 0.0 if index < 0 or index >= spawn_weights.size() else spawn_weights[index]
