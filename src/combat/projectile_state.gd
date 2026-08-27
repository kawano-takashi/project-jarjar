class_name ProjectileState
extends RefCounted


const FACTION_ALLY: StringName = &"ally"
const FACTION_ENEMY: StringName = &"enemy"

var pool_index: int = -1
var generation: int = 0
var active: bool = false
var faction: StringName = &""
var weapon_id: StringName = &""
var source_entity_id: int = -1
var position: Vector2 = Vector2.ZERO
var previous_position: Vector2 = Vector2.ZERO
var velocity: Vector2 = Vector2.ZERO
var radius: float = 0.0
var damage: float = 0.0
var remaining_distance: float = 0.0
var previous_remaining_distance: float = 0.0
var remaining_lifetime: float = 0.0
var target_position: Vector2 = Vector2.ZERO
var pierce_remaining: int = 0
var born_physics_tick: int = 0
var hit_entity_ids: Dictionary[int, bool] = {}
var source_effect_id: StringName = &""
var proc_effect_id: StringName = &""
var is_primary: bool = true
var effect_chain: PackedStringArray = PackedStringArray()
var chain_depth: int = 0


func activate(
	p_faction: StringName,
	p_weapon_id: StringName,
	p_source_entity_id: int,
	p_position: Vector2,
	p_velocity: Vector2,
	p_radius: float,
	p_damage: float,
	p_remaining_distance: float,
	p_remaining_lifetime: float,
	p_target_position: Vector2,
	p_pierce_remaining: int,
	p_born_physics_tick: int,
	p_source_effect_id: StringName = &"",
	p_proc_effect_id: StringName = &"",
	p_is_primary: bool = true,
	p_effect_chain: PackedStringArray = PackedStringArray(),
) -> void:
	active = true
	faction = p_faction
	weapon_id = p_weapon_id
	source_entity_id = p_source_entity_id
	position = p_position
	previous_position = p_position
	velocity = p_velocity
	radius = p_radius
	damage = p_damage
	remaining_distance = p_remaining_distance
	previous_remaining_distance = p_remaining_distance
	remaining_lifetime = p_remaining_lifetime
	target_position = p_target_position
	pierce_remaining = p_pierce_remaining
	born_physics_tick = p_born_physics_tick
	hit_entity_ids.clear()
	source_effect_id = p_source_effect_id
	proc_effect_id = p_proc_effect_id
	is_primary = p_is_primary
	effect_chain = p_effect_chain.duplicate()
	chain_depth = effect_chain.size()


func deactivate() -> void:
	active = false
	faction = &""
	weapon_id = &""
	source_entity_id = -1
	position = Vector2.ZERO
	previous_position = Vector2.ZERO
	velocity = Vector2.ZERO
	radius = 0.0
	damage = 0.0
	remaining_distance = 0.0
	previous_remaining_distance = 0.0
	remaining_lifetime = 0.0
	target_position = Vector2.ZERO
	pierce_remaining = 0
	born_physics_tick = 0
	hit_entity_ids.clear()
	source_effect_id = &""
	proc_effect_id = &""
	is_primary = true
	effect_chain = PackedStringArray()
	chain_depth = 0
