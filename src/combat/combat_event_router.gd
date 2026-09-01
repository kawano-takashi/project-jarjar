class_name CombatEventRouter
extends RefCounted


func create_primary(
	state: RunState,
	event_type: StringName,
	source_entity_id: int,
	source_effect_id: StringName,
	damage_snapshot: float,
	position: Vector2 = Vector2.ZERO,
	direction: Vector2 = Vector2.ZERO,
) -> CombatEvent:
	var event := CombatEvent.new()
	event.event_serial = state.allocate_event_serial()
	event.event_type = event_type
	event.source_entity_id = source_entity_id
	event.source_effect_id = source_effect_id
	event.damage_snapshot = damage_snapshot
	event.position = position
	event.direction = direction
	return event
