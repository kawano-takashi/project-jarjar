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
	if parent == null:
		return null
	var reserved_chain: PackedStringArray = reserve_secondary_chain_from_values(
		parent.effect_chain,
		parent.chain_depth,
		proc_effect_id,
	)
	if reserved_chain.is_empty():
		return null
	return create_secondary_from_reserved_chain(
		state,
		reserved_chain,
		event_type,
		source_entity_id,
		source_effect_id,
		proc_effect_id,
		damage_snapshot,
		position,
		direction,
	)


func reserve_secondary_chain(
	parent: CombatEvent,
	proc_effect_id: StringName,
) -> PackedStringArray:
	if parent == null:
		return PackedStringArray()
	return reserve_secondary_chain_from_values(
		parent.effect_chain,
		parent.chain_depth,
		proc_effect_id,
	)


func reserve_secondary_chain_from_values(
	parent_chain: PackedStringArray,
	parent_chain_depth: int,
	proc_effect_id: StringName,
) -> PackedStringArray:
	if proc_effect_id.is_empty():
		return PackedStringArray()
	if parent_chain_depth != parent_chain.size():
		invalid_chain_rejection_count += 1
		return PackedStringArray()
	if parent_chain_depth >= MAX_CHAIN_DEPTH:
		chain_depth_overflow_count += 1
		return PackedStringArray()
	if parent_chain.has(String(proc_effect_id)):
		duplicate_proc_rejection_count += 1
		return PackedStringArray()
	var reserved_chain: PackedStringArray = parent_chain.duplicate()
	reserved_chain.append(String(proc_effect_id))
	return reserved_chain


func create_secondary_from_reserved_chain(
	state: RunState,
	reserved_chain: PackedStringArray,
	event_type: StringName,
	source_entity_id: int,
	source_effect_id: StringName,
	proc_effect_id: StringName,
	damage_snapshot: float,
	position: Vector2 = Vector2.ZERO,
	direction: Vector2 = Vector2.ZERO,
) -> CombatEvent:
	if (
		proc_effect_id.is_empty()
		or reserved_chain.is_empty()
		or reserved_chain.size() > MAX_CHAIN_DEPTH
		or reserved_chain[reserved_chain.size() - 1] != String(proc_effect_id)
	):
		invalid_chain_rejection_count += 1
		return null
	var event := CombatEvent.new()
	event.event_serial = state.next_event_serial
	state.next_event_serial += 1
	event.event_type = event_type
	event.source_entity_id = source_entity_id
	event.source_effect_id = source_effect_id
	event.proc_effect_id = proc_effect_id
	event.is_primary = false
	event.effect_chain = reserved_chain.duplicate()
	event.chain_depth = event.effect_chain.size()
	event.damage_snapshot = damage_snapshot
	event.position = position
	event.direction = direction
	return event
