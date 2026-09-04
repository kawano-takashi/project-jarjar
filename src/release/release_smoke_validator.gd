class_name ReleaseSmokeValidator
extends RefCounted


const RUN_SEED: int = 20260827
const STARTER_WEAPON_ID: StringName = &"homing_core"

const ACTION_START_RUN: StringName = &"start_run"
const ACTION_WAIT_FOR_FAILURE: StringName = &"wait_for_failure"
const ACTION_RETRY_SAME_SEED: StringName = &"retry_same_seed"
const ACTION_RETURN_TO_TITLE: StringName = &"return_to_title"
const ACTION_COMPLETE: StringName = &"complete"

const DefinitionCatalogScript := preload("res://src/core/definition_catalog.gd")
const RunStateFactoryScript := preload("res://src/core/run_state_factory.gd")

enum Stage {
	NEW,
	AWAITING_START,
	AWAITING_FIRST_FAILURE,
	AWAITING_RETRY,
	AWAITING_SECOND_FAILURE,
	AWAITING_TITLE,
	COMPLETE,
	FAILED,
}

var _stage: Stage = Stage.NEW
var _settings_store: Variant = null
var _expected_initial_snapshot: Dictionary = {}
var _first_failed_state_instance_id: int = 0


func begin(game_app: Node, settings_store: Variant) -> Dictionary:
	if _stage != Stage.NEW:
		return _fail(&"invalid_begin_stage")
	var title_validation := _validate_title(game_app)
	if not bool(title_validation["success"]):
		return _fail(title_validation["reason"])
	var settings_validation := _validate_ephemeral_defaults(settings_store, false)
	if not bool(settings_validation["success"]):
		return _fail(settings_validation["reason"])

	var catalog: DefinitionCatalog = DefinitionCatalogScript.new()
	if not catalog.load_and_validate():
		return _fail(&"definition_catalog_invalid")
	var expected_state: RunState = RunStateFactoryScript.create(RUN_SEED, catalog)
	if expected_state == null:
		return _fail(&"run_state_factory_failed")
	_expected_initial_snapshot = _initial_snapshot(expected_state)
	_settings_store = settings_store
	_settings_store.tutorial_completed = true
	_stage = Stage.AWAITING_START
	return _ok(ACTION_START_RUN, {"run_seed": RUN_SEED})


func validate_started_and_prepare_timeout(game_app: Node) -> Dictionary:
	if _stage != Stage.AWAITING_START:
		return _fail(&"invalid_start_stage")
	var runtime_validation := _validate_ephemeral_defaults(
		_settings_store,
		true,
	)
	if not bool(runtime_validation["success"]):
		return _fail(runtime_validation["reason"])
	var initial_validation := _validate_factory_initial_state(game_app)
	if not bool(initial_validation["success"]):
		return _fail(initial_validation["reason"])
	var state: RunState = _run_state(game_app)
	state.current_hp = 0.0
	_stage = Stage.AWAITING_FIRST_FAILURE
	return _ok(ACTION_WAIT_FOR_FAILURE)


func validate_first_failure(game_app: Node) -> Dictionary:
	if _stage != Stage.AWAITING_FIRST_FAILURE:
		return _fail(&"invalid_first_failure_stage")
	var failure_validation := _validate_forced_failure(game_app)
	if not bool(failure_validation["success"]):
		return _fail(failure_validation["reason"])
	_first_failed_state_instance_id = _run_state(game_app).get_instance_id()
	_stage = Stage.AWAITING_RETRY
	return _ok(ACTION_RETRY_SAME_SEED, {"run_seed": RUN_SEED})


func validate_retry_and_prepare_timeout(game_app: Node) -> Dictionary:
	if _stage != Stage.AWAITING_RETRY:
		return _fail(&"invalid_retry_stage")
	var state: RunState = _run_state(game_app)
	if state == null:
		return _fail(&"retry_state_missing")
	if state.get_instance_id() == _first_failed_state_instance_id:
		return _fail(&"retry_state_not_replaced")
	var initial_validation := _validate_factory_initial_state(game_app)
	if not bool(initial_validation["success"]):
		return _fail(initial_validation["reason"])
	state.current_hp = 0.0
	_stage = Stage.AWAITING_SECOND_FAILURE
	return _ok(ACTION_WAIT_FOR_FAILURE)


func validate_second_failure(game_app: Node) -> Dictionary:
	if _stage != Stage.AWAITING_SECOND_FAILURE:
		return _fail(&"invalid_second_failure_stage")
	var failure_validation := _validate_forced_failure(game_app)
	if not bool(failure_validation["success"]):
		return _fail(failure_validation["reason"])
	_stage = Stage.AWAITING_TITLE
	return _ok(ACTION_RETURN_TO_TITLE)


func validate_title_and_finish(game_app: Node) -> Dictionary:
	if _stage != Stage.AWAITING_TITLE:
		return _fail(&"invalid_title_stage")
	var title_validation := _validate_title(game_app)
	if not bool(title_validation["success"]):
		return _fail(title_validation["reason"])
	var runtime_validation := _validate_ephemeral_defaults(
		_settings_store,
		true,
	)
	if not bool(runtime_validation["success"]):
		return _fail(runtime_validation["reason"])
	_stage = Stage.COMPLETE
	return _ok(ACTION_COMPLETE, {"exit_code": 0})


func stage_name() -> StringName:
	match _stage:
		Stage.NEW:
			return &"new"
		Stage.AWAITING_START:
			return &"awaiting_start"
		Stage.AWAITING_FIRST_FAILURE:
			return &"awaiting_first_failure"
		Stage.AWAITING_RETRY:
			return &"awaiting_retry"
		Stage.AWAITING_SECOND_FAILURE:
			return &"awaiting_second_failure"
		Stage.AWAITING_TITLE:
			return &"awaiting_title"
		Stage.COMPLETE:
			return &"complete"
	return &"failed"


func _validate_title(game_app: Node) -> Dictionary:
	if game_app == null or not game_app.has_method("current_run_phase"):
		return _validation_failure(&"game_app_invalid")
	if int(game_app.call("current_run_phase")) != GameTypes.RunPhase.TITLE:
		return _validation_failure(&"title_phase_invalid")
	if _run_state(game_app) != null:
		return _validation_failure(&"title_run_state_present")
	if game_app.get("combat_simulation") != null:
		return _validation_failure(&"title_combat_simulation_present")
	return _validation_ok()


func _validate_ephemeral_defaults(
	settings_store: Variant,
	tutorial_completed_expected: bool,
) -> Dictionary:
	if settings_store == null:
		return _validation_failure(&"settings_store_missing")
	if not bool(settings_store.initialized):
		return _validation_failure(&"settings_not_initialized")
	if bool(settings_store.runner_safe_mode):
		return _validation_failure(&"settings_runner_safe_mode")
	if str(settings_store.active_settings_path) != "":
		return _validation_failure(&"settings_path_not_ephemeral")
	if not is_equal_approx(float(settings_store.master_volume), 1.0):
		return _validation_failure(&"settings_master_not_default")
	if not is_equal_approx(float(settings_store.sfx_volume), 0.9):
		return _validation_failure(&"settings_sfx_not_default")
	if bool(settings_store.reduce_motion):
		return _validation_failure(&"settings_reduce_motion_not_default")
	if bool(settings_store.reduce_flashes):
		return _validation_failure(&"settings_reduce_flashes_not_default")
	if not bool(settings_store.controller_vibration):
		return _validation_failure(&"settings_vibration_not_default")
	if bool(settings_store.tutorial_completed) != tutorial_completed_expected:
		return _validation_failure(&"settings_tutorial_completed_invalid")
	return _validation_ok()


func _validate_factory_initial_state(game_app: Node) -> Dictionary:
	if int(game_app.call("current_run_phase")) != GameTypes.RunPhase.COMBAT:
		return _validation_failure(&"initial_phase_invalid")
	var state: RunState = _run_state(game_app)
	if state == null:
		return _validation_failure(&"initial_state_missing")
	var simulation_value: Variant = game_app.get("combat_simulation")
	if not simulation_value is CombatSimulation:
		return _validation_failure(&"initial_simulation_missing")
	if (simulation_value as CombatSimulation).state != state:
		return _validation_failure(&"initial_simulation_state_mismatch")
	var actual_snapshot := _initial_snapshot(state)
	if actual_snapshot["starter_id"] != STARTER_WEAPON_ID:
		return _validation_failure(&"initial_starter_weapon_invalid")
	for key: String in _expected_initial_snapshot:
		if actual_snapshot.get(key) != _expected_initial_snapshot[key]:
			return _validation_failure(&"initial_state_mismatch", {"field": key})
	return _validation_ok()


func _validate_forced_failure(game_app: Node) -> Dictionary:
	if int(game_app.call("current_run_phase")) != GameTypes.RunPhase.FAILED:
		return _validation_failure(&"forced_failure_phase_invalid")
	var state: RunState = _run_state(game_app)
	if state == null:
		return _validation_failure(&"forced_failure_state_missing")
	if state.run_seed != RUN_SEED:
		return _validation_failure(&"forced_failure_seed_changed")
	if state.current_hp > 0.0:
		return _validation_failure(&"forced_failure_hp_positive")
	var simulation_value: Variant = game_app.get("combat_simulation")
	if not simulation_value is CombatSimulation:
		return _validation_failure(&"forced_failure_simulation_missing")
	if (simulation_value as CombatSimulation).state != state:
		return _validation_failure(&"forced_failure_simulation_state_mismatch")
	return _validation_ok()


func _initial_snapshot(state: RunState) -> Dictionary:
	var starter_id: StringName = &""
	var starter_level: int = 0
	if state.weapons.size() == 1:
		starter_id = state.weapons[0].weapon_id
		starter_level = state.weapons[0].level
	return {
		"run_seed": state.run_seed,
		"phase": state.phase,
		"combat_tick": state.combat_tick,
		"current_hp": state.current_hp,
		"max_hp": state.max_hp,
		"level": state.level,
		"xp": state.xp,
		"starter_id": starter_id,
		"starter_level": starter_level,
		"weapon_count": state.weapons.size(),
		"passive_count": state.passives.size(),
		"pending_level_ups": state.pending_level_ups,
		"pending_chests": state.pending_chest_count(),
		"opened_chests": state.opened_chests,
		"evolution_count": state.evolution_count,
		"boss_spawned": state.boss_spawned,
		"boss_defeated": state.boss_defeated,
		"total_kills": state.total_kills,
		"elite_kills": state.elite_kills,
		"rng": _rng_snapshot(state),
	}


func _rng_snapshot(state: RunState) -> Dictionary:
	if state == null or state.rng_streams == null:
		return {}
	return state.rng_streams.state_digest()


func _run_state(game_app: Node) -> RunState:
	if game_app == null:
		return null
	return game_app.get("run_state") as RunState


func _ok(action: StringName, details: Dictionary = {}) -> Dictionary:
	var result: Dictionary = details.duplicate(true)
	result["success"] = true
	if not result.has("exit_code"):
		result["exit_code"] = -1
	result["reason"] = &""
	result["action"] = action
	result["stage"] = stage_name()
	return result


func _fail(reason: StringName) -> Dictionary:
	_stage = Stage.FAILED
	return {
		"success": false,
		"exit_code": 1,
		"reason": reason,
		"action": &"",
		"stage": stage_name(),
	}


func _validation_ok() -> Dictionary:
	return {"success": true, "reason": &""}


func _validation_failure(reason: StringName, details: Dictionary = {}) -> Dictionary:
	var result: Dictionary = details.duplicate(true)
	result["success"] = false
	result["reason"] = reason
	return result
