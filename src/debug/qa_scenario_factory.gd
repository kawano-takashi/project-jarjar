class_name QaScenarioFactory
extends RefCounted


const FIXED_SEED: int = 20260827
const VALID_IDS: Array[String] = LaunchArguments.QA_SCENARIOS
const WEAPON_SCENARIO_IDS: Dictionary[String, StringName] = {
	"weapon_resonance_wave": &"resonance_wave",
	"weapon_homing_core": &"homing_core",
	"weapon_direction_needle": &"directional_needle",
	"weapon_arc_crystal": &"arc_crystal",
	"weapon_return_ring": &"returning_ring",
	"weapon_orbit_array": &"orbital_array",
	"weapon_mass_shot": &"mass_projectile",
	"weapon_zero_field": &"zero_field",
	"weapon_vital_resonance": &"vital_resonance",
	"weapon_infinite_homing": &"infinite_homing",
	"weapon_infinite_needles": &"infinite_needles",
	"weapon_spiral_crystal": &"spiral_crystal",
	"weapon_critical_ring": &"critical_ring",
	"weapon_eternal_orbit": &"eternal_orbit",
	"weapon_collapse_projectile": &"collapse_projectile",
	"weapon_absorption_field": &"absorption_field",
}


static func build(scenario_id: String, catalog: DefinitionCatalog) -> Dictionary:
	if catalog == null or not catalog.is_valid or not scenario_id in VALID_IDS:
		return {"valid": false}
	var state: RunState = RunStateFactory.create(FIXED_SEED, catalog)
	var rng_before: Dictionary = state.rng_streams.state_digest()
	var simulation := CombatSimulation.new()
	var valid: bool = true
	var mixed: bool = scenario_id in ["weapon_mix_projectiles", "weapon_mix_areas"]
	if mixed:
		var weapon_ids: Array[StringName] = []
		weapon_ids.assign(
			[&"infinite_homing", &"infinite_needles", &"spiral_crystal", &"critical_ring", &"collapse_projectile"]
			if scenario_id == "weapon_mix_projectiles" else
			[&"vital_resonance", &"eternal_orbit", &"absorption_field", &"arc_crystal", &"directional_needle"]
		)
		state.weapons.clear()
		for weapon_id: StringName in weapon_ids:
			valid = _append_weapon(state, catalog, weapon_id) and valid
	elif WEAPON_SCENARIO_IDS.has(scenario_id):
		valid = _prepare_weapon_state(
			state,
			catalog,
			WEAPON_SCENARIO_IDS[scenario_id],
		)
	elif scenario_id == "level_up_modal":
		valid = _prepare_level_up_state(state, catalog)
	elif scenario_id == "chest_reward":
		valid = _prepare_chest_state(state, catalog)
	elif scenario_id == "result":
		_prepare_result_state(state, catalog)
	if not valid:
		return {
			"valid": false,
			"rng_unchanged": rng_before == state.rng_streams.state_digest(),
		}

	simulation.initialize(state, catalog)
	if WEAPON_SCENARIO_IDS.has(scenario_id) or mixed:
		_prepare_weapon_combat(simulation)
	elif scenario_id == "boss_phase_three":
		valid = _prepare_boss_phase_three(state, simulation)
	_restore_rng_states(state.rng_streams, rng_before)
	return {
		"valid": valid,
		"state": state,
		"simulation": simulation,
		"tutorial_active": false,
		"rng_unchanged": rng_before == state.rng_streams.state_digest(),
	}


static func _prepare_weapon_state(
	state: RunState,
	catalog: DefinitionCatalog,
	weapon_id: StringName,
) -> bool:
	state.weapons.clear()
	return _append_weapon(state, catalog, weapon_id)


static func _append_weapon(state: RunState, catalog: DefinitionCatalog, weapon_id: StringName) -> bool:
	var definition: WeaponDefinition = catalog.weapon(weapon_id)
	if definition == null:
		return false
	var runtime := RunWeapon.create(
		definition.weapon_id,
		catalog.lineage_for_weapon(definition.weapon_id),
		definition.is_evolved,
		state.rng_streams.create_weapon_rng(catalog.lineage_for_weapon(definition.weapon_id), state.weapons.size()),
	)
	runtime.level = definition.max_level
	runtime.ready_on_resume = true
	state.weapons.append(runtime)
	return true


static func _prepare_weapon_combat(simulation: CombatSimulation) -> void:
	var runtime: RunWeapon = simulation.state.weapons[0]
	var definition: WeaponDefinition = simulation.catalog.weapon(runtime.weapon_id)
	var target_distance: float = 2.0
	if definition.behavior in [
		GameTypes.WeaponBehavior.HOMING_PROJECTILE,
		GameTypes.WeaponBehavior.DIRECTIONAL_PROJECTILE,
		GameTypes.WeaponBehavior.ARC_PROJECTILE,
		GameTypes.WeaponBehavior.MASS_PROJECTILE,
	]:
		target_distance = 8.0
	var first_target: EnemyEntity = simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.BULWARK,
		Vector2(target_distance, 0.0),
	)
	if first_target != null:
		first_target.hp = 100_000.0
		first_target.max_hp = first_target.hp
	# Targets on both sides and at several distances expose real patterns and areas.
	for index: int in range(8):
		var near_distance: float = 5.0 if target_distance > 2.0 else 2.5
		var distance_m: float = near_distance if index % 2 == 0 else 6.5
		var enemy: EnemyEntity = simulation.spawn_fixture_enemy(GameTypes.EnemyType.BULWARK,
			Vector2.from_angle(TAU * float(index) / 8.0) * distance_m)
		if enemy != null:
			enemy.hp = 100_000.0
			enemy.max_hp = enemy.hp


static func _prepare_level_up_state(
	state: RunState,
	catalog: DefinitionCatalog,
) -> bool:
	state.pending_level_ups = 1
	var offer: LevelOffer = ProgressionService.create_offer(state, catalog)
	if offer == null or offer.options.size() != catalog.manifest().progression.level_offer_count:
		return false
	state.phase = GameTypes.RunPhase.LEVEL_UP
	return true


static func _prepare_chest_state(
	state: RunState,
	catalog: DefinitionCatalog,
) -> bool:
	var starter: RunWeapon = state.weapon_for_lineage(&"homing_core")
	if starter == null:
		return false
	starter.level = catalog.weapon(starter.weapon_id).max_level
	if not bool(ProgressionService.apply_direct_upgrade(
		state,
		catalog,
		GameTypes.UpgradeKind.PASSIVE,
		&"cycle_crystal",
	).get(&"success", false)):
		return false
	var source_index: int = catalog.elite_chest_kinds.find(GameTypes.ChestKind.EVOLUTION_CAPABLE)
	if source_index < 0:
		return false
	state.pending_chest_sources.append(source_index)
	var outcome: ChestOutcome = ChestRewardService.create_outcome(state, catalog)
	if outcome == null or outcome.kind != GameTypes.ChestOutcomeKind.EVOLUTION:
		return false
	state.phase = GameTypes.RunPhase.CHEST_REWARD
	return true


static func _prepare_boss_phase_three(
	state: RunState,
	simulation: CombatSimulation,
) -> bool:
	state.combat_tick = state.boss_start_tick + 1800 * 3
	var boss: EnemyEntity = simulation.spawn_fixture_enemy(
		GameTypes.EnemyType.BOSS,
		Vector2(8.0, 0.0),
		state.combat_tick - 1,
		true,
	)
	if boss == null:
		return false
	boss.hp = boss.max_hp * 0.3
	boss.boss_phase = 3
	boss.boss_action_age_ticks = float(simulation.catalog.manifest().combat.boss_enrage_interval_ticks * 3)
	state.boss_transition_started = true
	state.boss_spawned = true
	state.boss_spawn_tick = boss.spawn_tick
	simulation.enemy_system.encounters.begin_boss(Vector2.ZERO, boss.activation_tick)
	state.boss_phase = 3
	state.boss_enrage_stacks = 3
	state.boss_hp = boss.hp
	state.boss_max_hp = boss.max_hp
	return true


static func _prepare_result_state(
	state: RunState,
	catalog: DefinitionCatalog,
) -> void:
	state.combat_tick = state.boss_start_tick + 733
	state.level = 42
	state.total_kills = 912
	state.normal_kills = 907
	state.elite_kills = 4
	state.boss_kills = 1
	state.boss_spawned = true
	state.boss_defeated = true
	state.evolution_count = 2
	state.weapon_damage_by_lineage[&"resonance_wave"] = 12345.0
	state.weapon_damage_by_lineage[&"homing_core"] = 9876.0
	var starter: RunWeapon = state.weapon_for_lineage(&"homing_core")
	if starter != null:
		starter.weapon_id = catalog.evolution_for_weapon(&"homing_core").evolved_weapon_id
		starter.level = 1
		starter.evolved = true
	state.phase = GameTypes.RunPhase.RESULT


static func _restore_rng_states(
	streams: RunRngStreams,
	digest: Dictionary,
) -> void:
	streams.spawn_rng.state = int(digest[&"spawn"])
	streams.upgrade_rng.state = int(digest[&"upgrade"])
	streams.chest_rng.state = int(digest[&"chest"])
	streams.powerup_rng.state = int(digest[&"powerup"])
	streams.swarm_event_rng.state = int(digest[&"swarm_event"])
	streams.node_spawn_rng.state = int(digest[&"node_spawn"])
