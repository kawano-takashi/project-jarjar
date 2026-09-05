class_name CombatEnvelope
extends RefCounted


const BOT_AWARENESS_RADIUS: float = 10.0
const CAMERA_SIZE: float = 18.0
const CAMERA_FOLLOW_TAU_SECONDS: float = 0.12

var arena_size: Vector2
var arena_min: Vector2
var arena_max: Vector2
var player_body_radius: float
var player_center_min: Vector2
var player_center_max: Vector2
var target_center_radius: float
var effect_outer_radius: float
var damage_center_radius: float
var spawn_inner_half_extent: float
var spawn_outer_half_extent: float
var normal_despawn_half_extent: float
var normal_entry_ticks: int
var elite_entry_ticks: int
var boss_entry_ticks: int


func _init(manifest: SurvivalContentManifest) -> void:
	arena_size = manifest.arena.size
	arena_min = -arena_size * 0.5
	arena_max = arena_size * 0.5
	player_body_radius = manifest.player.body_radius
	player_center_min = arena_min + Vector2.ONE * player_body_radius
	player_center_max = arena_max - Vector2.ONE * player_body_radius
	target_center_radius = manifest.combat.target_center_radius
	effect_outer_radius = manifest.combat.effect_outer_radius
	damage_center_radius = manifest.combat.damage_center_radius
	spawn_inner_half_extent = manifest.spawn.inner_half_extent
	spawn_outer_half_extent = manifest.spawn.outer_half_extent
	normal_despawn_half_extent = manifest.spawn.normal_despawn_half_extent
	normal_entry_ticks = manifest.spawn.normal_entry_ticks
	elite_entry_ticks = manifest.spawn.elite_entry_ticks
	boss_entry_ticks = manifest.spawn.boss_entry_ticks


func entry_ticks_for_enemy_type(enemy_type: GameTypes.EnemyType) -> int:
	match enemy_type:
		GameTypes.EnemyType.ELITE:
			return elite_entry_ticks
		GameTypes.EnemyType.BOSS:
			return boss_entry_ticks
		_:
			return normal_entry_ticks


func enemy_center_limit(body_radius: float) -> Vector2:
	return Vector2(maxf(0.0, arena_max.x - body_radius), maxf(0.0, arena_max.y - body_radius))
