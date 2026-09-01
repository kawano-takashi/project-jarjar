class_name NodeDropService
extends RefCounted


static func roll_drop(
	state: RunState,
	catalog: DefinitionCatalog,
) -> GameTypes.NodeDropType:
	if state == null or catalog == null or catalog.manifest() == null:
		return GameTypes.NodeDropType.NONE
	var source_weights: PackedFloat32Array = catalog.manifest().node_drop_weights
	var candidates: Array[StringName] = []
	var adjusted_weights := PackedFloat64Array()
	var luck_multiplier: float = 1.0 + (
		ProgressionService.passive_stat_total(state, catalog, &"luck_pct") / 100.0
	)
	for drop_value: int in GameTypes.NodeDropType.values():
		var drop_type := drop_value as GameTypes.NodeDropType
		candidates.append(GameTypes.node_drop_type_to_key(drop_type))
		var weight: float = source_weights[drop_value]
		if drop_type != GameTypes.NodeDropType.NONE:
			weight *= luck_multiplier
		adjusted_weights.append(weight)
	var selected: StringName = WeightedSelector.select(
		state.rng_streams.powerup_rng,
		candidates,
		adjusted_weights,
	)
	return _drop_type_from_key(selected)


static func apply_drop(
	state: RunState,
	catalog: DefinitionCatalog,
	drop_type: GameTypes.NodeDropType,
) -> Dictionary:
	if state == null or catalog == null:
		return {&"success": false, &"vacuum": false}
	match drop_type:
		GameTypes.NodeDropType.NONE:
			return {&"success": true, &"vacuum": false}
		GameTypes.NodeDropType.HEAL:
			state.current_hp = minf(
				state.max_hp,
				state.current_hp + catalog.manifest().node_heal_amount,
			)
			return {&"success": true, &"vacuum": false}
		GameTypes.NodeDropType.VACUUM:
			return {&"success": true, &"vacuum": true}
		GameTypes.NodeDropType.STOP:
			state.stop_until_tick = maxi(
				state.stop_until_tick,
				state.combat_tick + catalog.manifest().node_stop_ticks,
			)
			return {&"success": true, &"vacuum": false}
	return {&"success": false, &"vacuum": false}


static func _drop_type_from_key(key: StringName) -> GameTypes.NodeDropType:
	for drop_value: int in GameTypes.NodeDropType.values():
		var drop_type := drop_value as GameTypes.NodeDropType
		if GameTypes.node_drop_type_to_key(drop_type) == key:
			return drop_type
	return GameTypes.NodeDropType.NONE
