class_name RunStateFactory
extends RefCounted


static func create(run_seed: int, catalog: DefinitionCatalog = null) -> RunState:
	var resolved_catalog: DefinitionCatalog = catalog
	if resolved_catalog == null:
		resolved_catalog = DefinitionCatalog.new()
		resolved_catalog.load_and_validate()
	var state := RunState.new()
	state.run_seed = run_seed
	state.rng_streams = RunRngStreams.create(run_seed)
	state.phase = GameTypes.RunPhase.COMBAT
	if not resolved_catalog.is_valid:
		push_error("Cannot create RunState from invalid content: %s" % resolved_catalog.error_text)
		return state
	var starter_definition: WeaponDefinition = resolved_catalog.weapon(
		resolved_catalog.manifest().starter_weapon_id
	)
	var starter_rng: RandomNumberGenerator = state.rng_streams.create_weapon_rng(
		starter_definition.lineage_id,
		0,
	)
	state.weapons.append(RunWeapon.create(
		starter_definition.weapon_id,
		starter_definition.lineage_id,
		false,
		starter_rng,
	))
	return state
