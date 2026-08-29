class_name CombatSnapshot
extends RefCounted


var player_position: Vector2 = Vector2.ZERO
var enemy_transforms: Array[Transform3D] = []
var projectile_transforms: Array[Transform3D] = []
var vfx_transforms: Array[Transform3D] = []
var vfx_colors: Array[Color] = []
var vfx_custom_data: Array[Color] = []
var chest_transforms: Array[Transform3D] = []
var active_enemy_count: int = 0
var active_projectile_count: int = 0
var active_vfx_count: int = 0
var active_chest_count: int = 0
var hud_values: Dictionary = {}


func _init(
	p_player_position: Vector2 = Vector2.ZERO,
	p_enemy_transforms: Array[Transform3D] = [],
	p_projectile_transforms: Array[Transform3D] = [],
	p_vfx_transforms: Array[Transform3D] = [],
	p_hud_values: Dictionary = {},
	p_chest_transforms: Array[Transform3D] = [],
	p_vfx_colors: Array[Color] = [],
	p_vfx_custom_data: Array[Color] = [],
) -> void:
	player_position = p_player_position
	enemy_transforms = p_enemy_transforms.duplicate(true)
	projectile_transforms = p_projectile_transforms.duplicate(true)
	vfx_transforms = p_vfx_transforms.duplicate(true)
	vfx_colors = p_vfx_colors.duplicate(true)
	vfx_custom_data = p_vfx_custom_data.duplicate(true)
	chest_transforms = p_chest_transforms.duplicate(true)
	active_enemy_count = enemy_transforms.size()
	active_projectile_count = projectile_transforms.size()
	active_vfx_count = vfx_transforms.size()
	active_chest_count = chest_transforms.size()
	hud_values = p_hud_values.duplicate(true)
