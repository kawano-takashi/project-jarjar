class_name RunStateFactory
extends RefCounted


static func create(run_seed: int, catalog: DefinitionCatalog) -> RunState:
	var state := RunState.new()
	state.run_seed = run_seed
	state.rng_streams = RunRngStreams.create(run_seed)
	state.phase = GameTypes.RunPhase.COMBAT
	if not catalog.is_valid:
		push_error("Cannot create RunState from invalid content: %s" % catalog.error_text)
		return null
	state.base_max_hp = catalog.manifest().player.base_max_hp
	state.max_hp = state.base_max_hp
	state.current_hp = state.max_hp
	state.kill_chain_window_ticks = catalog.manifest().player.kill_chain_window_ticks
	state.boss_start_tick = catalog.boss_start_tick
	for key: String in ["normal_kills_by_segment", "normal_xp_by_segment", "normal_active_samples_by_segment", "normal_active_total_by_segment", "normal_engaged_total_by_segment"]:
		var values: Variant = state.get(key)
		values.resize(catalog.segments.size())
		values.fill(0)
		state.set(key, values)
	state.elite_spawn_ticks.resize(catalog.elite_spawn_ticks.size())
	state.elite_spawn_ticks.fill(-1)
	state.elite_kill_ticks.resize(catalog.elite_spawn_ticks.size())
	state.elite_kill_ticks.fill(-1)
	var starter_definition: WeaponDefinition = catalog.weapon(
		catalog.manifest().progression.starter_weapon_id
	)
	var starter_rng: RandomNumberGenerator = state.rng_streams.create_weapon_rng(
		catalog.lineage_for_weapon(starter_definition.weapon_id),
		0,
	)
	state.weapons.append(RunWeapon.create(
		starter_definition.weapon_id,
		catalog.lineage_for_weapon(starter_definition.weapon_id),
		false,
		starter_rng,
	))
	return state
