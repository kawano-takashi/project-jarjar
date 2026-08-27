class_name CombatEventRouter
extends RefCounted


const MAX_CHAIN_DEPTH: int = 16

var chain_depth_overflow_count: int = 0
var duplicate_proc_rejection_count: int = 0
var invalid_chain_rejection_count: int = 0


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
	event.event_serial = state.next_event_serial
	state.next_event_serial += 1
	event.event_type = event_type
	event.source_entity_id = source_entity_id
	event.source_effect_id = source_effect_id
	event.proc_effect_id = &""
	event.is_primary = true
	event.effect_chain = PackedStringArray()
	event.chain_depth = 0
	event.damage_snapshot = damage_snapshot
	event.position = position
	event.direction = direction
	return event


func create_secondary(
	state: RunState,
	parent: CombatEvent,
	event_type: StringName,
	source_entity_id: int,
	source_effect_id: StringName,
	proc_effect_id: StringName,
	damage_snapshot: float,
	position: Vector2 = Vector2.ZERO,
	direction: Vector2 = Vector2.ZERO,
) -> CombatEvent:
	if parent == null or proc_effect_id.is_empty():
		return null
	if parent.chain_depth != parent.effect_chain.size():
		invalid_chain_rejection_count += 1
		return null
	if parent.chain_depth >= MAX_CHAIN_DEPTH:
		chain_depth_overflow_count += 1
		return null
	if parent.effect_chain.has(String(proc_effect_id)):
		duplicate_proc_rejection_count += 1
		return null
	var event := CombatEvent.new()
	event.event_serial = state.next_event_serial
	state.next_event_serial += 1
	event.event_type = event_type
	event.source_entity_id = source_entity_id
	event.source_effect_id = source_effect_id
	event.proc_effect_id = proc_effect_id
	event.is_primary = false
	event.effect_chain = parent.effect_chain.duplicate()
	event.effect_chain.append(String(proc_effect_id))
	event.chain_depth = event.effect_chain.size()
	event.damage_snapshot = damage_snapshot
	event.position = position
	event.direction = direction
	return event
