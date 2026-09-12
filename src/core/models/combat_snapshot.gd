class_name CombatSnapshot
extends RefCounted


enum EnemyVisualKind {
	PURSUER,
	SWARMER,
	BULWARK,
	SHOOTER,
	ELITE,
	BOSS,
	SWARMER_EVENT_RED,
	ENCIRCLER,
}

enum ProjectileVisualKind {
	DEFAULT,
	RESONANCE_WAVE,
	HOMING_CORE,
	DIRECTIONAL_NEEDLE,
	ARC_CRYSTAL,
	RETURNING_RING,
	ORBITAL_ARRAY,
	MASS_PROJECTILE,
	ZERO_FIELD,
	ENEMY,
}

enum ImportantMarkerKind {
	NONE,
	ELITE,
	BOSS,
}


## Immutable native render buffers, independent of the event queue.
var native_visuals: Dictionary = {}
var player_position: Vector2 = Vector2.ZERO
## Integer count of 1024m origin shifts. All positions in this snapshot are local.
var world_origin: Vector2i = Vector2i.ZERO
## Up to two visible compass cues: kind, direction, screen_position only.
var chest_guidance: Array[Dictionary] = []
var enemy_transforms: Array[Transform3D] = []
var enemy_visual_kinds: PackedInt32Array = PackedInt32Array()
var enemy_visual_custom_data: PackedColorArray = PackedColorArray()
var projectile_transforms: Array[Transform3D] = []
var projectile_visual_kinds: PackedInt32Array = PackedInt32Array()
var projectile_visual_custom_data: PackedColorArray = PackedColorArray()
var vfx_transforms: Array[Transform3D] = []
var vfx_colors: Array[Color] = []
var vfx_custom_data: Array[Color] = []
## Attack bodies and admitted weapon decorations, independent of event/audio queues.
var weapon_effect_transforms: Array[Transform3D] = []
var weapon_effect_colors: Array[Color] = []
var weapon_effect_custom_data: Array[Color] = []
var chest_transforms: Array[Transform3D] = []
var normal_chest_transforms: Array[Transform3D] = []
var evolution_chest_transforms: Array[Transform3D] = []
var xp_transforms: Array[Transform3D] = []
var pickup_transforms: Array[Transform3D] = []
var node_transforms: Array[Transform3D] = []
var active_enemy_count: int = 0
var active_projectile_count: int = 0
var active_vfx_count: int = 0
var active_chest_count: int = 0
var active_xp_count: int = 0
var active_pickup_count: int = 0
var active_node_count: int = 0
var hud_values: Dictionary = {}
var presentation_events: Array[CombatPresentationEvent] = []

var swarm_warning_active: bool = false
var swarm_warning_anchor: Vector2 = Vector2.ZERO
var swarm_warning_direction: Vector2 = Vector2.ZERO
var swarm_warning_progress: float = 0.0
var swarm_warning_width: float = 0.0
var swarm_warning_length: float = 0.0

var boss_charge_active: bool = false
var boss_boundary_active: bool = false
var boss_boundary_center: Vector2 = Vector2.ZERO
var boss_boundary_radius: float = 0.0
var boss_boundary_progress: float = 0.0
var boss_charge_position: Vector2 = Vector2.ZERO
var boss_charge_progress: float = 0.0
var boss_charge_radius: float = 1.0
var boss_charge_spoke_count: int = 0
var boss_charge_angle_offset: float = 0.0

var important_marker_active: bool = false
var important_marker_kind: ImportantMarkerKind = ImportantMarkerKind.NONE
var important_marker_position: Vector2 = Vector2.ZERO
var important_marker_progress: float = 0.0
var important_marker_radius: float = 1.0

var absorption_active: bool = false
var absorption_position: Vector2 = Vector2.ZERO
var absorption_progress: float = 0.0
var absorption_radius: float = 1.0


func _init(
	p_player_position: Vector2 = Vector2.ZERO,
	p_enemy_transforms: Array[Transform3D] = [],
	p_projectile_transforms: Array[Transform3D] = [],
	p_vfx_transforms: Array[Transform3D] = [],
	p_hud_values: Dictionary = {},
	p_chest_transforms: Array[Transform3D] = [],
	p_vfx_colors: Array[Color] = [],
	p_vfx_custom_data: Array[Color] = [],
	p_xp_transforms: Array[Transform3D] = [],
	p_pickup_transforms: Array[Transform3D] = [],
	p_node_transforms: Array[Transform3D] = [],
	p_enemy_visual_kinds: PackedInt32Array = PackedInt32Array(),
	p_enemy_visual_custom_data: PackedColorArray = PackedColorArray(),
	p_projectile_visual_kinds: PackedInt32Array = PackedInt32Array(),
	p_projectile_visual_custom_data: PackedColorArray = PackedColorArray(),
	p_presentation_events: Array[CombatPresentationEvent] = [],
) -> void:
	player_position = p_player_position
	enemy_transforms = p_enemy_transforms
	projectile_transforms = p_projectile_transforms
	vfx_transforms = p_vfx_transforms
	vfx_colors = p_vfx_colors
	vfx_custom_data = p_vfx_custom_data
	chest_transforms = p_chest_transforms
	xp_transforms = p_xp_transforms
	pickup_transforms = p_pickup_transforms
	node_transforms = p_node_transforms
	enemy_visual_kinds = p_enemy_visual_kinds
	enemy_visual_custom_data = p_enemy_visual_custom_data
	projectile_visual_kinds = p_projectile_visual_kinds
	projectile_visual_custom_data = p_projectile_visual_custom_data
	presentation_events = p_presentation_events
	active_enemy_count = enemy_transforms.size()
	active_projectile_count = projectile_transforms.size()
	active_vfx_count = vfx_transforms.size()
	active_chest_count = chest_transforms.size()
	active_xp_count = xp_transforms.size()
	active_pickup_count = pickup_transforms.size()
	active_node_count = node_transforms.size()
	hud_values = p_hud_values
