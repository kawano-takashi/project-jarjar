class_name ChestRewardService
extends RefCounted


const UPGRADE_DESCRIPTION_FORMATTER: Script = preload(
	"res://src/progression/upgrade_description_formatter.gd"
)


static func create_outcome(
	state: RunState,
	catalog: DefinitionCatalog,
) -> ChestOutcome:
	if state == null or catalog == null or state.pending_chest_sources.is_empty():
		return null
	if state.active_chest_outcome != null and not state.active_chest_outcome.applied:
		return state.active_chest_outcome
	var outcome := ChestOutcome.new()
	outcome.serial = state.next_chest_serial
	outcome.source_elite_index = state.pending_chest_sources[0]
	state.next_chest_serial += 1
	var evolution_candidates: Array[EvolutionDefinition] = _eligible_evolutions(
		state,
		catalog,
	)
	if not evolution_candidates.is_empty():
		var selected_evolution: EvolutionDefinition = evolution_candidates[
			state.rng_streams.chest_rng.randi_range(0, evolution_candidates.size() - 1)
		]
		var evolved_definition: WeaponDefinition = catalog.weapon(
			selected_evolution.evolved_weapon_id
		)
		outcome.kind = GameTypes.ChestOutcomeKind.EVOLUTION
		outcome.upgrade_kind = GameTypes.UpgradeKind.WEAPON
		outcome.content_id = selected_evolution.evolved_weapon_id
		outcome.source_weapon_id = selected_evolution.base_weapon_id
		outcome.display_name = evolved_definition.display_name
		outcome.previous_level = catalog.weapon(selected_evolution.base_weapon_id).max_level
		outcome.new_level = 1
		state.active_chest_outcome = outcome
		return outcome
	var upgrades: Array[UpgradeOption] = _eligible_owned_upgrades(state, catalog)
	if not upgrades.is_empty():
		var selected: UpgradeOption = upgrades[
			state.rng_streams.chest_rng.randi_range(0, upgrades.size() - 1)
		]
		outcome.kind = GameTypes.ChestOutcomeKind.UPGRADE
		outcome.upgrade_kind = selected.kind
		outcome.content_id = selected.content_id
		outcome.display_name = selected.display_name
		outcome.upgrade_detail = selected.upgrade_detail
		outcome.previous_level = selected.current_level
		outcome.new_level = selected.next_level
		state.active_chest_outcome = outcome
		return outcome
	outcome.kind = GameTypes.ChestOutcomeKind.FULL_HEAL
	outcome.display_name = "HP全回復"
	state.active_chest_outcome = outcome
	return outcome


static func apply_outcome(
	state: RunState,
	catalog: DefinitionCatalog,
	outcome_serial: int,
) -> Dictionary:
	if state == null or catalog == null:
		return _failure(&"invalid_state")
	if state.applied_chest_serials.has(outcome_serial):
		return _failure(&"already_applied")
	var outcome: ChestOutcome = state.active_chest_outcome
	if outcome == null or outcome.serial != outcome_serial or outcome.applied:
		return _failure(&"stale_outcome")
	if (
		state.pending_chest_sources.is_empty()
		or state.pending_chest_sources[0] != outcome.source_elite_index
	):
		return _failure(&"chest_source_mismatch")
	var result: Dictionary
	match outcome.kind:
		GameTypes.ChestOutcomeKind.EVOLUTION:
			result = _apply_evolution(state, catalog, outcome)
		GameTypes.ChestOutcomeKind.UPGRADE:
			var upgrade_result: Dictionary = ProgressionService.apply_direct_upgrade(
				state,
				catalog,
				outcome.upgrade_kind,
				outcome.content_id,
			)
			if bool(upgrade_result.get(&"success", false)):
				result = _success(outcome, int(upgrade_result[&"new_level"]))
			else:
				result = upgrade_result
		GameTypes.ChestOutcomeKind.FULL_HEAL:
			state.current_hp = state.max_hp
			result = _success(outcome, 0)
		_:
			result = _failure(&"invalid_outcome")
	if not bool(result.get(&"success", false)):
		return result
	outcome.applied = true
	state.applied_chest_serials[outcome_serial] = true
	state.active_chest_outcome = null
	state.pending_chest_sources.pop_front()
	state.opened_chests += 1
	ProgressionService.refresh_build_maxed(state, catalog)
	return result


static func _eligible_evolutions(
	state: RunState,
	catalog: DefinitionCatalog,
) -> Array[EvolutionDefinition]:
	var result: Array[EvolutionDefinition] = []
	if state.evolution_count >= catalog.manifest().progression.max_evolutions_per_run:
		return result
	for base_weapon_id: StringName in catalog.basic_weapon_ids():
		var evolution: EvolutionDefinition = catalog.evolution_for_weapon(base_weapon_id)
		if evolution == null:
			continue
		var runtime: RunWeapon = state.weapon_for_lineage(base_weapon_id)
		var base_definition: WeaponDefinition = catalog.weapon(base_weapon_id)
		if (
			runtime != null
			and not runtime.evolved
			and runtime.level >= base_definition.max_level
			and state.passive(evolution.passive_id) != null
		):
			result.append(evolution)
	return result


static func _eligible_owned_upgrades(
	state: RunState,
	catalog: DefinitionCatalog,
) -> Array[UpgradeOption]:
	var result: Array[UpgradeOption] = []
	for runtime: RunWeapon in state.weapons:
		if runtime.evolved:
			continue
		var definition: WeaponDefinition = catalog.weapon(runtime.weapon_id)
		if definition == null or definition.selection_weight <= 0.0 or runtime.level >= definition.max_level:
			continue
		var option := UpgradeOption.new()
		option.kind = GameTypes.UpgradeKind.WEAPON
		option.content_id = definition.weapon_id
		option.display_name = definition.display_name
		option.current_level = runtime.level
		option.next_level = runtime.level + 1
		option.upgrade_detail = UPGRADE_DESCRIPTION_FORMATTER.weapon_detail(
			definition,
			option.next_level,
		)
		option.max_level = definition.max_level
		result.append(option)
	for runtime: RunPassive in state.passives:
		var definition: PassiveDefinition = catalog.passive(runtime.passive_id)
		if definition == null or definition.selection_weight <= 0.0 or runtime.level >= definition.max_level:
			continue
		var option := UpgradeOption.new()
		option.kind = GameTypes.UpgradeKind.PASSIVE
		option.content_id = definition.passive_id
		option.display_name = definition.display_name
		option.current_level = runtime.level
		option.next_level = runtime.level + 1
		option.upgrade_detail = UPGRADE_DESCRIPTION_FORMATTER.passive_detail(
			definition,
			option.current_level,
			option.next_level,
		)
		option.max_level = definition.max_level
		result.append(option)
	result.sort_custom(_upgrade_option_less)
	return result


static func _apply_evolution(
	state: RunState,
	catalog: DefinitionCatalog,
	outcome: ChestOutcome,
) -> Dictionary:
	if state.evolution_count >= catalog.manifest().progression.max_evolutions_per_run:
		return _failure(&"evolution_cap")
	var mapping: EvolutionDefinition = catalog.evolution_for_weapon(
		outcome.source_weapon_id
	)
	var runtime: RunWeapon = state.weapon_for_lineage(outcome.source_weapon_id)
	if (
		mapping == null
		or mapping.evolved_weapon_id != outcome.content_id
		or runtime == null
		or runtime.evolved
		or state.passive(mapping.passive_id) == null
	):
		return _failure(&"evolution_no_longer_eligible")
	var base_definition: WeaponDefinition = catalog.weapon(mapping.base_weapon_id)
	if base_definition == null or runtime.level < base_definition.max_level:
		return _failure(&"weapon_not_maxed")
	runtime.weapon_id = mapping.evolved_weapon_id
	runtime.level = 1
	runtime.evolved = true
	runtime.cooldown_remaining_ticks = 0
	runtime.ready_on_resume = true
	state.evolution_count += 1
	return _success(outcome, runtime.level)


static func _success(outcome: ChestOutcome, new_level: int) -> Dictionary:
	return {
		&"success": true,
		&"reason": &"",
		&"kind": outcome.kind,
		&"upgrade_kind": outcome.upgrade_kind,
		&"content_id": outcome.content_id,
		&"new_level": new_level,
	}


static func _failure(reason: StringName) -> Dictionary:
	return {
		&"success": false,
		&"reason": reason,
		&"kind": GameTypes.ChestOutcomeKind.FULL_HEAL,
		&"upgrade_kind": GameTypes.UpgradeKind.WEAPON,
		&"content_id": &"",
		&"new_level": 0,
	}


static func _upgrade_option_less(left: UpgradeOption, right: UpgradeOption) -> bool:
	if left.kind != right.kind:
		return int(left.kind) < int(right.kind)
	return String(left.content_id) < String(right.content_id)
