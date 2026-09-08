class_name EncounterSystem
extends RefCounted


var boss_active: bool = false
var boss_center: Vector2 = Vector2.ZERO
var boss_radius: float = 0.0
var boss_progress: float = 0.0
var _boss_activation_tick: int = 0
var _definition: EncounterBalanceDefinition
var _groups: Dictionary[int, Dictionary] = {}


func initialize(definition: EncounterBalanceDefinition) -> void:
	_definition = definition
	_groups.clear()
	boss_active = false
	boss_radius = 0.0
	boss_progress = 0.0
	boss_center = Vector2.ZERO
	_boss_activation_tick = 0


func spawn_ring(owner: EnemyEntity, center: Vector2, state: RunState, store: EnemyStore, damage_multiplier: float) -> void:
	var ids: Array[int] = []
	for index: int in range(_definition.member_count):
		var direction := Vector2.from_angle(TAU * float(index) / _definition.member_count)
		var position: Vector2 = center + direction * Vector2(_definition.elite_radius_x, _definition.elite_radius_y)
		var member: EnemyEntity = store.try_spawn(
			state, GameTypes.EnemyType.PURSUER, _definition.unit_definition, position,
			float(state.level), damage_multiplier, owner.spawn_tick,
			owner.activation_tick - owner.spawn_tick,
		)
		assert(member != null, "Encounter capacity must be reserved before spawning")
		member.encounter_owner_id = owner.entity_id
		ids.append(member.entity_id)
	_groups[owner.entity_id] = {
		"members": ids,
		"expiry_tick": owner.activation_tick + _definition.elite_lifetime_ticks,
	}


func begin_boss(center: Vector2, activation_tick: int) -> void:
	boss_active = true
	boss_center = center
	_boss_activation_tick = activation_tick
	boss_radius = _definition.boss_initial_radius
	boss_progress = 0.0


func advance(current_tick: int, store: EnemyStore) -> void:
	retire_finished_groups(current_tick, store)
	if boss_active:
		boss_progress = clampf(float(current_tick - _boss_activation_tick) / _definition.boss_shrink_ticks, 0.0, 1.0)
		boss_radius = lerpf(_definition.boss_initial_radius, _definition.boss_final_radius, boss_progress)


func retire_finished_groups(current_tick: int, store: EnemyStore) -> void:
	for owner_id: int in _groups.keys():
		var group: Dictionary = _groups[owner_id]
		if store.has_entity(owner_id) and current_tick < int(group["expiry_tick"]):
			continue
		for member_id: int in group["members"]:
			store.remove(member_id)
		_groups.erase(owner_id)


func constrain_body(position: Vector2, body_radius: float) -> Vector2:
	if not boss_active:
		return position
	return EncounterGeometry.constrain_body(position, body_radius, boss_center, boss_radius)


func clear(store: EnemyStore) -> void:
	for group: Dictionary in _groups.values():
		for member_id: int in group["members"]:
			store.remove(member_id)
	initialize(_definition)


func shift_origin(displacement: Vector2) -> void:
	boss_center -= displacement
