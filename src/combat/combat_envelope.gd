class_name CombatEnvelope
extends RefCounted


const BOT_AWARENESS_RADIUS: float = 10.0

var player_body_radius: float
var target_center_radius: float
var effect_outer_radius: float
var damage_center_radius: float
var offscreen_band_width: float
var despawn_margin: float
var normal_entry_ticks: int
var elite_entry_ticks: int
var boss_entry_ticks: int


func _init(manifest: SurvivalContentManifest) -> void:
	player_body_radius = manifest.player.body_radius
	target_center_radius = manifest.combat.target_center_radius
	effect_outer_radius = manifest.combat.effect_outer_radius
	damage_center_radius = manifest.combat.damage_center_radius
	offscreen_band_width = manifest.spawn.offscreen_band_width
	despawn_margin = manifest.spawn.despawn_margin
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
