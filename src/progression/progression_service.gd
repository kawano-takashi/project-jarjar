class_name ProgressionService
extends RefCounted


const UPGRADE_DESCRIPTION_FORMATTER: Script = preload(
	"res://src/progression/upgrade_description_formatter.gd"
)


static func xp_required_for_level(current_level: int) -> int:
	return SurvivalContentManifest.default_required_xp_for_level(current_level)


static func xp_growth_multiplier(current_level: int) -> float:
	return SurvivalContentManifest.default_growth_multiplier_for_level(current_level)


static func xp_required_for_level_with_manifest(
	current_level: int,
	manifest: SurvivalContentManifest,
) -> int:
	if manifest == null:
		return xp_required_for_level(current_level)
	return manifest.required_xp_for_level(current_level)


static func xp_growth_multiplier_with_manifest(
	current_level: int,
	manifest: SurvivalContentManifest,
) -> float:
	if manifest == null:
		return xp_growth_multiplier(current_level)
	return manifest.growth_multiplier_for_level(current_level)


static func add_xp(state: RunState, amount: int, catalog: DefinitionCatalog) -> int:
	if state == null or catalog == null or amount <= 0:
		return 0
	if state.build_maxed:
		_clear_maxed_growth_state(state)
		return 0
	var manifest: SurvivalContentManifest = catalog.manifest()
	var scaled_numerator: int = (
		amount * manifest.xp_yield_percent + state.xp_yield_remainder
	)
	var scaled_amount: int = floori(float(scaled_numerator) / 100.0)
	state.xp_yield_remainder = scaled_numerator % 100
	if scaled_amount <= 0:
		return 0
	var queued_before: int = state.pending_level_ups
	var upgrade_capacity: int = remaining_upgrade_capacity(state, catalog)
	if upgrade_capacity <= 0:
		refresh_build_maxed(state, catalog)
		return 0
	var unprocessed_xp: int = scaled_amount
	while unprocessed_xp > 0 and state.pending_level_ups < upgrade_capacity:
		var required: int = xp_required_for_level_with_manifest(state.level, manifest)
		if required <= 0:
			break
		var growth_multiplier: int = maxi(
			1,
			roundi(xp_growth_multiplier_with_manifest(state.level, manifest)),
		)
		var xp_to_threshold: int = maxi(1, required - state.xp)
		var source_xp_to_threshold: int = ceili(
			float(xp_to_threshold) / float(growth_multiplier)
		)
		var source_xp_used: int = mini(unprocessed_xp, source_xp_to_threshold)
		state.xp += source_xp_used * growth_multiplier
		unprocessed_xp -= source_xp_used
		if state.xp < required:
			break
		state.xp -= required
		state.level += 1
		state.pending_level_ups += 1
	# Once every possible selection is queued, further XP cannot produce another
	# choice. Discard the irrelevant remainder instead of carrying it behind the
	# modal queue.
	if state.pending_level_ups >= upgrade_capacity:
		state.xp = 0
	return state.pending_level_ups - queued_before


static func create_offer(state: RunState, catalog: DefinitionCatalog) -> LevelOffer:
	if state == null or catalog == null or state.pending_level_ups <= 0:
		return null
	if state.active_level_offer != null and not state.active_level_offer.applied:
		return state.active_level_offer
	var candidates: Array[UpgradeOption] = _eligible_options(state, catalog)
	if candidates.is_empty():
		refresh_build_maxed(state, catalog)
		return null
	var offer := LevelOffer.new()
	offer.serial = state.next_offer_serial
	state.next_offer_serial += 1
	offer.offer_level = state.level - state.pending_level_ups + 1
	var available: Array[UpgradeOption] = candidates.duplicate()
	var option_count: int = mini(catalog.manifest().level_offer_count, available.size())
	var has_open_category_slot: bool = (
		state.weapons.size() < catalog.manifest().weapon_slot_count
		or state.passives.size() < catalog.manifest().passive_slot_count
	)
	if has_open_category_slot:
		var owned: Array[UpgradeOption] = []
		for candidate: UpgradeOption in available:
			if candidate.current_level > 0:
				owned.append(candidate)
		var owned_probability: float = _owned_offer_probability(
			state,
			catalog,
			offer.offer_level,
		)
		for _attempt_index: int in range(catalog.manifest().owned_offer_attempt_count):
			if owned.is_empty() or offer.options.size() >= option_count:
				break
			if state.rng_streams.upgrade_rng.randf() >= owned_probability:
				continue
			var selected_owned: UpgradeOption = owned[
				state.rng_streams.upgrade_rng.randi_range(0, owned.size() - 1)
			]
			var selected_token: StringName = _option_token(selected_owned)
			if _offer_has_token(offer, selected_token):
				continue
			offer.options.append(selected_owned)
			_remove_available_token(available, selected_token)
	while offer.options.size() < option_count and not available.is_empty():
		var tokens: Array[StringName] = []
		var weights := PackedFloat64Array()
		for candidate: UpgradeOption in available:
			tokens.append(_option_token(candidate))
			weights.append(candidate.weight)
		var selected_token: StringName = WeightedSelector.select(
			state.rng_streams.upgrade_rng,
			tokens,
			weights,
		)
		var selected_index: int = tokens.find(selected_token)
		if selected_index < 0:
			break
		offer.options.append(available[selected_index])
		available.remove_at(selected_index)
	state.active_level_offer = offer
	return offer


static func apply_offer(
	state: RunState,
	catalog: DefinitionCatalog,
	offer_serial: int,
	choice_index: int,
) -> Dictionary:
	if state == null or catalog == null:
		return _failure(&"invalid_state")
	if state.applied_offer_serials.has(offer_serial):
		return _failure(&"already_applied")
	var offer: LevelOffer = state.active_level_offer
	if offer == null or offer.serial != offer_serial or offer.applied:
		return _failure(&"stale_offer")
	if choice_index < 0 or choice_index >= offer.options.size():
		return _failure(&"invalid_choice")
	var option: UpgradeOption = offer.options[choice_index]
	var result: Dictionary = apply_direct_upgrade(
		state,
		catalog,
		option.kind,
		option.content_id,
	)
	if not bool(result.get(&"success", false)):
		return result
	offer.applied = true
	state.applied_offer_serials[offer_serial] = true
	state.active_level_offer = null
	state.pending_level_ups = maxi(0, state.pending_level_ups - 1)
	state.upgrade_selections_applied += 1
	var remaining: int = remaining_upgrade_capacity(state, catalog)
	state.pending_level_ups = mini(state.pending_level_ups, remaining)
	if remaining <= 0:
		refresh_build_maxed(state, catalog)
	return result


static func apply_direct_upgrade(
	state: RunState,
	catalog: DefinitionCatalog,
	kind: GameTypes.UpgradeKind,
	content_id: StringName,
) -> Dictionary:
	if kind == GameTypes.UpgradeKind.WEAPON:
		var definition: WeaponDefinition = catalog.weapon(content_id)
		if definition == null or definition.is_evolved:
			return _failure(&"invalid_weapon")
		var runtime: RunWeapon = state.weapon_for_lineage(definition.lineage_id)
		if runtime == null:
			if state.weapons.size() >= catalog.manifest().weapon_slot_count:
				return _failure(&"weapon_slots_full")
			var weapon_rng: RandomNumberGenerator = state.rng_streams.create_weapon_rng(
				definition.lineage_id,
				state.weapons.size(),
			)
			runtime = RunWeapon.create(
				definition.weapon_id,
				definition.lineage_id,
				false,
				weapon_rng,
			)
			state.weapons.append(runtime)
			return _success(kind, content_id, runtime.level)
		else:
			var current_definition: WeaponDefinition = catalog.weapon(runtime.weapon_id)
			if runtime.evolved or current_definition == null or runtime.level >= current_definition.max_level:
				return _failure(&"weapon_maxed")
			runtime.level += 1
		runtime.ready_on_resume = true
		return _success(kind, content_id, runtime.level)
	var passive_definition: PassiveDefinition = catalog.passive(content_id)
	if passive_definition == null:
		return _failure(&"invalid_passive")
	var passive_runtime: RunPassive = state.passive(content_id)
	var previous_max_hp: float = state.max_hp
	if passive_runtime == null:
		if state.passives.size() >= catalog.manifest().passive_slot_count:
			return _failure(&"passive_slots_full")
		passive_runtime = RunPassive.create(content_id)
		state.passives.append(passive_runtime)
	elif passive_runtime.level >= passive_definition.max_level:
		return _failure(&"passive_maxed")
	else:
		passive_runtime.level += 1
	_apply_max_hp_passive(state, catalog, previous_max_hp)
	return _success(kind, content_id, passive_runtime.level)


static func remaining_upgrade_capacity(state: RunState, catalog: DefinitionCatalog) -> int:
	if state == null or catalog == null or catalog.manifest() == null:
		return 0
	var remaining: int = 0
	for runtime: RunWeapon in state.weapons:
		var definition: WeaponDefinition = catalog.weapon(runtime.weapon_id)
		if definition != null and not runtime.evolved:
			remaining += maxi(0, definition.max_level - runtime.level)
	remaining += (
		catalog.manifest().weapon_slot_count - state.weapons.size()
	) * 8
	for runtime: RunPassive in state.passives:
		var definition: PassiveDefinition = catalog.passive(runtime.passive_id)
		if definition != null:
			remaining += maxi(0, definition.max_level - runtime.level)
	remaining += (
		catalog.manifest().passive_slot_count - state.passives.size()
	) * 5
	return maxi(0, remaining)


static func is_build_maxed(state: RunState, catalog: DefinitionCatalog) -> bool:
	return remaining_upgrade_capacity(state, catalog) <= 0


static func refresh_build_maxed(state: RunState, catalog: DefinitionCatalog) -> bool:
	if state == null or catalog == null:
		return false
	state.build_maxed = is_build_maxed(state, catalog)
	if state.build_maxed:
		_clear_maxed_growth_state(state)
	return state.build_maxed


static func passive_stat_total(
	state: RunState,
	catalog: DefinitionCatalog,
	stat_id: StringName,
) -> float:
	var total: float = 0.0
	for runtime: RunPassive in state.passives:
		var definition: PassiveDefinition = catalog.passive(runtime.passive_id)
		if definition != null and definition.stat_id == stat_id:
			total += definition.amount_per_level * float(runtime.level)
	return total


static func _eligible_options(
	state: RunState,
	catalog: DefinitionCatalog,
) -> Array[UpgradeOption]:
	var result: Array[UpgradeOption] = []
	var weapon_slots_available: bool = (
		state.weapons.size() < catalog.manifest().weapon_slot_count
	)
	for weapon_id: StringName in catalog.basic_weapon_ids():
		var definition: WeaponDefinition = catalog.weapon(weapon_id)
		var runtime: RunWeapon = state.weapon_for_lineage(definition.lineage_id)
		if runtime == null and not weapon_slots_available:
			continue
		if runtime != null:
			var current_definition: WeaponDefinition = catalog.weapon(runtime.weapon_id)
			if runtime.evolved or current_definition == null or runtime.level >= current_definition.max_level:
				continue
		result.append(_weapon_option(state, catalog, definition, runtime))
	var passive_slots_available: bool = (
		state.passives.size() < catalog.manifest().passive_slot_count
	)
	for passive_id: StringName in catalog.passive_ids():
		var definition: PassiveDefinition = catalog.passive(passive_id)
		var runtime: RunPassive = state.passive(passive_id)
		if runtime == null and not passive_slots_available:
			continue
		if runtime != null and runtime.level >= definition.max_level:
			continue
		result.append(_passive_option(state, catalog, definition, runtime))
	return result


static func _weapon_option(
	_state: RunState,
	catalog: DefinitionCatalog,
	definition: WeaponDefinition,
	runtime: RunWeapon,
) -> UpgradeOption:
	var option := UpgradeOption.new()
	option.kind = GameTypes.UpgradeKind.WEAPON
	option.content_id = definition.weapon_id
	option.display_name = definition.display_name
	option.description = definition.description
	option.current_level = 0 if runtime == null else runtime.level
	option.next_level = option.current_level + 1
	if runtime != null:
		option.upgrade_detail = UPGRADE_DESCRIPTION_FORMATTER.weapon_detail(
			definition,
			option.next_level,
		)
	option.max_level = definition.max_level
	option.weight = definition.selection_weight
	option.pairing_hint = _pairing_hint(catalog, definition.weapon_id)
	return option


static func _passive_option(
	_state: RunState,
	catalog: DefinitionCatalog,
	definition: PassiveDefinition,
	runtime: RunPassive,
) -> UpgradeOption:
	var option := UpgradeOption.new()
	option.kind = GameTypes.UpgradeKind.PASSIVE
	option.content_id = definition.passive_id
	option.display_name = definition.display_name
	option.description = definition.description
	option.current_level = 0 if runtime == null else runtime.level
	option.next_level = option.current_level + 1
	if runtime != null:
		option.upgrade_detail = UPGRADE_DESCRIPTION_FORMATTER.passive_detail(
			definition,
			option.current_level,
			option.next_level,
		)
	option.max_level = definition.max_level
	option.weight = definition.selection_weight
	option.pairing_hint = _pairing_hint(catalog, definition.paired_weapon_id)
	return option


static func _pairing_hint(catalog: DefinitionCatalog, base_weapon_id: StringName) -> String:
	var evolution: EvolutionDefinition = catalog.evolution_for_weapon(base_weapon_id)
	if evolution == null:
		return ""
	var base: WeaponDefinition = catalog.weapon(evolution.base_weapon_id)
	var paired_passive: PassiveDefinition = catalog.passive(evolution.passive_id)
	var evolved: WeaponDefinition = catalog.weapon(evolution.evolved_weapon_id)
	if base == null or paired_passive == null or evolved == null:
		return ""
	return "進化: %s + %s → %s" % [
		base.display_name,
		paired_passive.display_name,
		evolved.display_name,
	]


static func _option_token(option: UpgradeOption) -> StringName:
	return StringName("%d|%s" % [int(option.kind), option.content_id])


static func _owned_offer_probability(
	state: RunState,
	catalog: DefinitionCatalog,
	offer_level: int,
) -> float:
	var luck_pct: float = passive_stat_total(state, catalog, &"luck_pct")
	var total_luck: float = 1.0 + luck_pct / 100.0
	var parity_factor: float = 2.0 if offer_level % 2 == 0 else 1.0
	return clampf(
		1.0
		+ catalog.manifest().owned_offer_luck_coefficient * parity_factor
		- 1.0 / maxf(0.000001, total_luck),
		0.0,
		1.0,
	)


static func _offer_has_token(offer: LevelOffer, token: StringName) -> bool:
	for option: UpgradeOption in offer.options:
		if _option_token(option) == token:
			return true
	return false


static func _remove_available_token(
	available: Array[UpgradeOption],
	token: StringName,
) -> void:
	for index: int in range(available.size()):
		if _option_token(available[index]) == token:
			available.remove_at(index)
			return


static func _apply_max_hp_passive(
	state: RunState,
	catalog: DefinitionCatalog,
	previous_max_hp: float,
) -> void:
	var max_hp_pct: float = passive_stat_total(state, catalog, &"max_hp_pct")
	state.max_hp = state.base_max_hp * (1.0 + max_hp_pct / 100.0)
	var gained_max_hp: float = maxf(0.0, state.max_hp - previous_max_hp)
	state.current_hp = minf(state.max_hp, state.current_hp + gained_max_hp)


static func _clear_maxed_growth_state(state: RunState) -> void:
	state.xp = 0
	state.xp_yield_remainder = 0
	state.pending_level_ups = 0
	state.active_level_offer = null


static func _success(
	kind: GameTypes.UpgradeKind,
	content_id: StringName,
	new_level: int,
) -> Dictionary:
	return {
		&"success": true,
		&"reason": &"",
		&"kind": kind,
		&"content_id": content_id,
		&"new_level": new_level,
	}


static func _failure(reason: StringName) -> Dictionary:
	return {
		&"success": false,
		&"reason": reason,
		&"kind": GameTypes.UpgradeKind.WEAPON,
		&"content_id": &"",
		&"new_level": 0,
	}
