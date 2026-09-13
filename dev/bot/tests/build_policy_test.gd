extends RefCounted

const BotController = preload("res://dev/bot/bot_controller.gd")
const BotKnowledge = preload("res://dev/bot/bot_knowledge.gd")
const BotObservation = preload("res://dev/bot/bot_observation.gd")
const BotBuildPolicy = preload("res://dev/bot/bot_build_policy.gd")


func test_bot_build_acquires_roles_materials_and_grows_nearest_core(a: Variant, _context: Dictionary) -> void:
	var controller := BotController.new(BotKnowledge.new(BalanceTestFixtures.catalog()))
	var observation: BotObservation = _menu([_weapon(&"homing_core", 4)])
	observation.options.assign([_option(&"homing_core", 4), _option(&"zero_field", 0), _passive_option(&"cycle_crystal")])
	a.expect_equal(1, controller.decide(observation).choice_index, "secure the missing area role before strengthening the starter")
	# Asking again without applying the choice must not create an imagined core.
	a.expect_equal(1, controller.decide(observation).choice_index, "unapplied choices do not change the build")
	observation.weapons.append(_weapon(&"zero_field", 3))
	observation.options[1] = _option(&"zero_field", 3)
	a.expect_equal(2, controller.decide(observation).choice_index, "secure an offered core partner early")
	observation.passives.assign([{"id": &"cycle_crystal", "level": 1}, {"id": &"repair_core", "level": 1}])
	observation.options[2] = _option(&"mass_projectile", 0)
	a.expect_equal(0, controller.decide(observation).choice_index, "the core closest to completion wins over another core or a new weapon")
	observation.weapons[0] = _weapon(&"homing_core", 8)
	observation.options[0] = _option(&"orbital_array", 0)
	a.expect_equal(1, controller.decide(observation).choice_index, "the second core stays ahead of new acquisitions after the starter finishes")
	observation.options.assign([_option(&"directional_needle", 0), _option(&"orbital_array", 0), _passive_option(&"probability_core")])
	a.expect_equal(1, controller.decide(observation).choice_index, "the third weapon supplements area coverage when core growth is not offered")
	observation.weapons.append(_weapon(&"orbital_array", 1))
	observation.options.assign([_option(&"orbital_array", 1), _option(&"zero_field", 3), _option(&"resonance_wave", 0)])
	a.expect_equal(1, controller.decide(observation).choice_index, "finish the more developed core instead of spreading into a fourth weapon")
	observation.weapons[2]["level"] = 7
	observation.options[0] = _option(&"orbital_array", 7)
	a.expect_equal(0, controller.decide(observation).choice_index, "completion distance takes precedence over the old behavior score")


func test_bot_build_expands_after_completion_and_resets_between_runs(a: Variant, _context: Dictionary) -> void:
	var controller := BotController.new(BotKnowledge.new(BalanceTestFixtures.catalog()))
	var observation: BotObservation = _menu([_weapon(&"homing_core", 8), _weapon(&"zero_field", 8), _weapon(&"arc_crystal", 3)])
	observation.passives.append({"id": &"repair_core", "level": 1})
	observation.options.assign([_option(&"resonance_wave", 0), _option(&"arc_crystal", 3), _passive_option(&"probability_core")])
	a.expect_equal(1, controller.decide(observation).choice_index, "all current cores must finish before ordinary expansion")
	observation.weapons[0] = _weapon(&"infinite_homing", 1, true)
	observation.weapons[1] = _weapon(&"absorption_field", 1, true)
	a.expect_equal(1, controller.decide(observation).choice_index, "evolved weapons retain their original core lineage and role")
	observation.weapons[2]["level"] = 8
	observation.options[1] = _passive_option(&"repair_core", 1)
	a.expect_equal(0, controller.decide(observation).choice_index, "completed cores allow a fourth weapon")
	observation.weapons.append(_weapon(&"resonance_wave", 1))
	observation.options.assign([_option(&"orbital_array", 0), _option(&"resonance_wave", 1), _passive_option(&"life_lattice")])
	a.expect_equal(2, controller.decide(observation).choice_index, "expansion still secures partners before the next new weapon")
	observation.passives.append({"id": &"life_lattice", "level": 1})
	observation.options[2] = _passive_option(&"life_lattice", 1)
	a.expect_equal(1, controller.decide(observation).choice_index, "grow an expansion weapon before adding a fifth")
	observation.phase = GameTypes.RunPhase.RESULT
	controller.decide(observation)
	observation = _menu([_weapon(&"homing_core", 1)])
	observation.options.assign([_option(&"homing_core", 1), _option(&"zero_field", 0), _passive_option(&"cycle_crystal")])
	a.expect_equal(1, controller.decide(observation).choice_index, "a new run starts with a fresh missing-role decision")


func test_bot_build_preserves_material_slots_on_bad_offers(a: Variant, _context: Dictionary) -> void:
	var controller := BotController.new(BotKnowledge.new(BalanceTestFixtures.catalog()))
	var observation: BotObservation = _menu([_weapon(&"homing_core", 7), _weapon(&"zero_field", 3), _weapon(&"orbital_array", 1)])
	observation.passives.assign([{"id": &"amplifier_core", "level": 1}, {"id": &"scale_lens", "level": 1}])
	observation.options.assign([_passive_option(&"life_lattice"), _option(&"directional_needle", 0), _passive_option(&"probability_core")])
	a.expect_equal(1, controller.decide(observation).choice_index, "an auxiliary fourth weapon preserves space for all three missing partners")
	observation.weapons.append(_weapon(&"directional_needle", 7))
	observation.options.assign([_option(&"directional_needle", 7), _option(&"zero_field", 3), _passive_option(&"probability_core")])
	a.expect_equal(1, controller.decide(observation).choice_index, "an incidental auxiliary is not promoted over an unfinished core")
	observation.options.assign([_passive_option(&"life_lattice"), _passive_option(&"probability_core"), _passive_option(&"speed_gate")])
	a.expect_equal(0, controller.decide(observation).choice_index, "an unavoidable loss still produces the best legal support choice")
	# A single material may support multiple cores. Protect reachable evolutions,
	# rather than blindly reserving one slot for every weapon.
	var content: SurvivalContentManifest = BalanceTestFixtures.manifest()
	for evolution: EvolutionDefinition in content.evolutions:
		if evolution.base_weapon_id == &"orbital_array":
			evolution.passive_id = &"repair_core"
	var catalog := DefinitionCatalog.new()
	a.expect_true(catalog.validate_manifest(content), catalog.error_text)
	controller = BotController.new(BotKnowledge.new(catalog))
	observation.passives.append({"id": &"probability_core", "level": 1})
	observation.passives.append({"id": &"life_lattice", "level": 1})
	observation.options.assign([_passive_option(&"cycle_crystal"), _passive_option(&"repair_core"), _passive_option(&"speed_gate")])
	a.expect_equal(1, controller.decide(observation).choice_index, "the last slot preserves two reachable evolutions instead of one")


func test_bot_evolution_state_requires_reachable_growth_and_remaining_capacity(a: Variant, _context: Dictionary) -> void:
	var content: SurvivalContentManifest = BalanceTestFixtures.manifest()
	content.progression.max_evolutions_per_run = 1
	var catalog := DefinitionCatalog.new()
	a.expect_true(catalog.validate_manifest(content), catalog.error_text)
	var policy := BotBuildPolicy.new(BotKnowledge.new(catalog))
	var observation: BotObservation = _menu([_weapon(&"arc_crystal", 2)])
	policy.observe(observation)
	a.expect_equal(BotBuildPolicy.EvolutionState.PREPARING, policy.evolution_state, "an open material slot keeps an owned weapon's evolution reachable")
	observation.passives.assign([{"id": &"cycle_crystal", "level": 1}, {"id": &"repair_core", "level": 1}, {"id": &"amplifier_core", "level": 1}, {"id": &"life_lattice", "level": 1}, {"id": &"probability_core", "level": 1}])
	policy.observe(observation)
	a.expect_equal(BotBuildPolicy.EvolutionState.NONE, policy.evolution_state, "a full inventory without the material cannot evolve")
	observation.passives[0] = {"id": &"scale_lens", "level": 1}
	observation.weapons[0]["level"] = catalog.weapon(&"arc_crystal").max_level
	policy.observe(observation)
	a.expect_equal(BotBuildPolicy.EvolutionState.READY, policy.evolution_state, "the completed weapon and its owned material are ready")
	observation.weapons.append(_weapon(&"infinite_homing", 1, true))
	policy.observe(observation)
	a.expect_equal(BotBuildPolicy.EvolutionState.NONE, policy.evolution_state, "the cap from the manifest overrides another ready recipe")
	observation.weapons.pop_back()
	observation.weapons[0]["level"] = 2
	catalog.weapon(&"arc_crystal").selection_weight = 0.0
	policy = BotBuildPolicy.new(BotKnowledge.new(catalog))
	policy.observe(observation)
	a.expect_equal(BotBuildPolicy.EvolutionState.NONE, policy.evolution_state, "a weapon excluded from upgrades cannot finish")
	observation.weapons[0]["level"] = catalog.weapon(&"arc_crystal").max_level
	policy.observe(observation)
	a.expect_equal(BotBuildPolicy.EvolutionState.READY, policy.evolution_state, "a previously completed weapon does not need another upgrade offer")
	observation.passives.clear()
	catalog.passive(&"scale_lens").selection_weight = 0.0
	policy = BotBuildPolicy.new(BotKnowledge.new(catalog))
	policy.observe(observation)
	a.expect_equal(BotBuildPolicy.EvolutionState.NONE, policy.evolution_state, "an unavailable missing passive is not an achievable plan")


func _menu(weapons: Array[Dictionary]) -> BotObservation:
	var observation := BotObservation.new()
	observation.phase = GameTypes.RunPhase.LEVEL_UP
	observation.hp = 100.0
	observation.max_hp = 100.0
	observation.weapons.assign(weapons)
	return observation


func _weapon(content_id: StringName, level: int, evolved: bool = false) -> Dictionary:
	return {"id": content_id, "level": level, "evolved": evolved}


func _option(content_id: StringName, level: int) -> Dictionary:
	return {"id": content_id, "level": level, "next": level + 1, "kind": GameTypes.UpgradeKind.WEAPON}


func _passive_option(content_id: StringName, level: int = 0) -> Dictionary:
	return {"id": content_id, "level": level, "next": level + 1, "kind": GameTypes.UpgradeKind.PASSIVE}
