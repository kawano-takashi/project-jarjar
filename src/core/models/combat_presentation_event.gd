class_name CombatPresentationEvent
extends RefCounted


enum Kind {
	NONE,
	ENEMY_HIT,
	ENEMY_KILLED,
	IMPORTANT_SPAWN,
	BOSS_CHARGE,
	BOSS_VOLLEY,
	PLAYER_HIT,
	BOSS_DEFEATED,
	PLAYER_DEFEATED,
	ABSORPTION,
	XP_PICKUP,
	BOSS_PHASE_CHANGED,
	CHAIN_MILESTONE,
}

enum Priority {
	AMBIENT,
	NORMAL,
	IMPORTANT,
	TERMINAL,
}


var kind: Kind = Kind.NONE
var event_id: StringName = &""
var tick: int = 0
var position: Vector2 = Vector2.ZERO
var enemy_type: int = -1
# Presentation-specific aliases retained for existing consumers.
var enemy_visual_kind: int = 0
var projectile_visual_kind: int = 0
var source_effect_id: StringName = &""
var count: int = 1
var intensity: float = 1.0
var priority: Priority = Priority.NORMAL
var combat_tick: int = 0


func _init(
	p_kind: Kind = Kind.NONE,
	p_event_id: StringName = &"",
	p_position: Vector2 = Vector2.ZERO,
	p_enemy_type: int = -1,
	p_projectile_visual_kind: int = 0,
	p_source_effect_id: StringName = &"",
	p_count: int = 1,
	p_intensity: float = 1.0,
	p_priority: Priority = Priority.NORMAL,
	p_combat_tick: int = 0,
) -> void:
	kind = p_kind
	event_id = p_event_id
	tick = maxi(0, p_combat_tick)
	position = p_position
	enemy_type = p_enemy_type
	enemy_visual_kind = maxi(0, p_enemy_type)
	projectile_visual_kind = maxi(0, p_projectile_visual_kind)
	source_effect_id = p_source_effect_id
	count = maxi(1, p_count)
	intensity = maxf(0.0, p_intensity)
	priority = p_priority
	combat_tick = tick


func resolved_event_id() -> StringName:
	if not event_id.is_empty():
		return event_id
	match kind:
		Kind.ENEMY_HIT:
			return &"enemy_hit"
		Kind.ENEMY_KILLED:
			return &"enemy_kill"
		Kind.IMPORTANT_SPAWN:
			return &"important_spawn"
		Kind.BOSS_CHARGE:
			return &"boss_charge"
		Kind.BOSS_VOLLEY:
			return &"boss_volley"
		Kind.PLAYER_HIT:
			return &"player_hit"
		Kind.BOSS_DEFEATED:
			return &"boss_defeated"
		Kind.PLAYER_DEFEATED:
			return &"player_defeated"
		Kind.ABSORPTION:
			return &"absorption"
		Kind.XP_PICKUP:
			return &"xp_pickup"
		Kind.BOSS_PHASE_CHANGED:
			return &"boss_phase"
		Kind.CHAIN_MILESTONE:
			return &"chain_milestone"
	return &""
