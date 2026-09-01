class_name EnemyDefinition
extends Resource


@export var enemy_id: StringName = &""
@export var display_name: String = ""
@export var enemy_type: GameTypes.EnemyType = GameTypes.EnemyType.PURSUER
@export var base_hp: float = 0.0
@export var move_speed: float = 0.0
@export var body_radius: float = 0.0
@export var contact_interval_ticks: int = 0
@export var contact_damage: float = 0.0
@export var preferred_distance_min: float = 0.0
@export var preferred_distance_max: float = 0.0
@export var special_interval_ticks: int = 0
@export var telegraph_ticks: int = 0
@export var area_radius: float = 0.0
@export var projectile_damage: float = 0.0
@export var projectile_speed: float = 0.0
@export var projectile_radius: float = 0.0
@export var projectile_lifetime_ticks: int = 0
@export var volley_count: int = 0
@export var summon_interval_ticks: int = 0
@export var summon_count: int = 0
@export var xp_value: int = 0
@export var drops_chest: bool = false
@export var is_boss: bool = false
