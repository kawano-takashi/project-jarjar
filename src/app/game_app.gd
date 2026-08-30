extends Node


const LaunchArgumentsScript = preload("res://src/app/launch_arguments.gd")
const DefinitionCatalogScript = preload("res://src/core/definition_catalog.gd")
const RunStateFactoryScript = preload("res://src/core/run_state_factory.gd")
const SeedServiceScript = preload("res://src/core/seed_service.gd")
const TutorialControllerScript = preload("res://src/tutorial/tutorial_controller.gd")
const TutorialOverlayScript = preload("res://src/tutorial/tutorial_overlay.gd")
const AudioFactoryScript = preload("res://src/audio/audio_factory.gd")
const AudioVoicePoolScript = preload("res://src/audio/audio_voice_pool.gd")
const ReleasePackAuditorScript = preload("res://src/release/release_pack_auditor.gd")
const ReleaseSmokeValidatorScript = preload("res://src/release/release_smoke_validator.gd")
const TITLE_SCENE: PackedScene = preload("res://scenes/ui/title_screen.tscn")
const ARENA_SCENE: PackedScene = preload("res://scenes/gameplay/arena_combat.tscn")
const REWARD_REVEAL_SCENE: PackedScene = preload("res://scenes/ui/reward_reveal_screen.tscn")
const INVENTORY_SCENE_PATH: String = "res://scenes/ui/inventory_screen.tscn"
const RESULT_SCENE_PATH: String = "res://scenes/ui/result_screen.tscn"
const FAILED_SCENE_PATH: String = "res://scenes/ui/failed_screen.tscn"

var _launch_valid: bool = false
var _launch: Dictionary = {}
var _definition_catalog: DefinitionCatalog = null
var _active_screen: Node = null
var _smoke_frames_remaining: int = 0
var _logical_phase: GameTypes.RunPhase = GameTypes.RunPhase.BOOT
var _tutorial_controller: RefCounted = TutorialControllerScript.new()
var _tutorial_overlay: CanvasLayer = null
var _audio_pool: Node = null
var _audio_streams: Dictionary[StringName, AudioStream] = {}
var _release_smoke_validator: RefCounted = null

var run_state: RunState = null
var combat_simulation: CombatSimulation = null


func _enter_tree() -> void:
	_launch = (
		LaunchArgumentsScript.parse_debug(OS.get_cmdline_user_args())
		if OS.is_debug_build()
		else LaunchArgumentsScript.parse_release(OS.get_cmdline_user_args())
	)
	if not _launch["valid"]:
		_reject_arguments(_launch["rejected_name"])
		return

	var settings_store: Variant = get_node_or_null("/root/SettingsStore")
	if settings_store == null:
		print("SETTINGS_INITIALIZATION_FAILED code=%d" % ERR_DOES_NOT_EXIST)
		_quit_deferred(1)
		return

	if _launch.get("mode", LaunchArgumentsScript.MODE_NORMAL) == LaunchArgumentsScript.MODE_RELEASE_PACK_AUDIT:
		_run_release_pack_audit()
		return

	var initialize_error: Error = _initialize_settings_for_launch(settings_store)
	if initialize_error != OK:
		print("SETTINGS_INITIALIZATION_FAILED code=%d" % initialize_error)
		_quit_deferred(1)
		return

	_definition_catalog = DefinitionCatalogScript.new()
	if not _definition_catalog.load_and_validate():
		print(
			"DEFINITION_CATALOG_INVALID count=%d"
			% _definition_catalog.validation_errors.size()
		)
		_quit_deferred(2)
		return

	_launch_valid = true


func _initialize_settings_for_launch(settings_store: Variant) -> Error:
	var mode: StringName = _launch.get("mode", LaunchArgumentsScript.MODE_NORMAL)
	var initialize_error: Error = (
		settings_store.initialize_ephemeral()
		if mode in [
			LaunchArgumentsScript.MODE_RELEASE_SMOKE,
			LaunchArgumentsScript.MODE_SMOKE_QUIT,
			LaunchArgumentsScript.MODE_QA_SCENARIO,
			LaunchArgumentsScript.MODE_PERFORMANCE,
		]
		else settings_store.initialize_for_game(_launch["settings_path"])
	)
	if initialize_error == OK and mode in [
		LaunchArgumentsScript.MODE_QA_SCENARIO,
		LaunchArgumentsScript.MODE_PERFORMANCE,
	]:
		settings_store.tutorial_seen = true
	return initialize_error


func _ready() -> void:
	if not _launch_valid or _launch["mode"] == LaunchArgumentsScript.MODE_RELEASE_PACK_AUDIT:
		return
	_tutorial_overlay = TutorialOverlayScript.new()
	add_child(_tutorial_overlay)
	_tutorial_overlay.cancel_input_observed.connect(_on_tutorial_cancel_input_observed)
	_audio_pool = AudioVoicePoolScript.new()
	add_child(_audio_pool)
	_audio_streams = {
		&"pickup": AudioFactoryScript.pickup(),
		&"normal_open": AudioFactoryScript.normal_open(),
		&"rare_open": AudioFactoryScript.rare_open(),
		&"epic_prealert": AudioFactoryScript.epic_prealert(),
		&"legendary_prealert": AudioFactoryScript.legendary_prealert(),
		&"unique_prealert": AudioFactoryScript.unique_prealert(),
		&"wave_clear": AudioFactoryScript.wave_clear(),
		&"fusion": AudioFactoryScript.fusion(),
	}
	match _launch.get("mode", LaunchArgumentsScript.MODE_NORMAL):
		LaunchArgumentsScript.MODE_QA_SCENARIO:
			_start_qa_mode(_launch["qa_scenario"])
		LaunchArgumentsScript.MODE_RELEASE_SMOKE:
			_show_title()
			_start_release_smoke()
		LaunchArgumentsScript.MODE_PERFORMANCE:
			_start_performance_mode()
		_:
			_show_title()


func _process(_delta: float) -> void:
	_advance_release_smoke()
	_refresh_tutorial_overlay()


func _physics_process(_delta: float) -> void:
	if _smoke_frames_remaining <= 0:
		return
	_smoke_frames_remaining -= 1
	if _smoke_frames_remaining == 0:
		get_tree().quit(0)


func current_run_phase() -> GameTypes.RunPhase:
	return run_state.phase if run_state != null else _logical_phase


func _show_title() -> void:
	_clear_active_screen()
	run_state = null
	combat_simulation = null
	_logical_phase = GameTypes.RunPhase.TITLE
	_tutorial_controller.dismiss_noncombat()
	var title_screen := TITLE_SCENE.instantiate() as Control
	_active_screen = title_screen
	title_screen.connect("start_requested", _start_new_run)
	title_screen.connect("exit_requested", _exit_game)
	add_child(title_screen)
	_raise_tutorial_overlay()

	match _launch.get("mode", LaunchArgumentsScript.MODE_NORMAL):
		LaunchArgumentsScript.MODE_SMOKE_QUIT:
			_smoke_frames_remaining = _launch["smoke_frames"]


func _start_new_run() -> void:
	start_new_run_with_seed(SeedServiceScript.generate_run_seed())


func start_new_run_with_seed(run_seed: int) -> bool:
	if _definition_catalog == null:
		_definition_catalog = DefinitionCatalogScript.new()
		if not _definition_catalog.load_and_validate():
			return false
	var first_wave: WaveDefinition = _definition_catalog.wave(1)
	if first_wave == null:
		return false
	run_state = RunStateFactoryScript.create(run_seed, first_wave)
	var settings_store: Variant = (
		get_node_or_null("/root/SettingsStore") if is_inside_tree() else null
	)
	_tutorial_controller.begin_run(
		bool(settings_store.tutorial_seen) if settings_store != null else false
	)
	combat_simulation = CombatSimulation.new()
	combat_simulation.initialize(run_state, _definition_catalog)
	_show_combat_arena(false)
	return true


func _show_combat_arena(paused: bool) -> bool:
	if run_state == null or combat_simulation == null:
		return false
	_clear_active_screen()
	var arena_node: Node = ARENA_SCENE.instantiate()
	if not arena_node is ArenaPresenter:
		arena_node.free()
		push_error("Arena scene root must be ArenaPresenter")
		return false
	var arena := arena_node as ArenaPresenter
	_active_screen = arena
	add_child(arena)
	arena.phase_changed.connect(_on_combat_phase_changed)
	arena.audio_event_requested.connect(_play_audio_event)
	arena.initialize(combat_simulation, _tutorial_controller)
	arena.set_simulation_paused(paused)
	_logical_phase = GameTypes.RunPhase.COMBAT
	_raise_tutorial_overlay()
	return true


func _show_reward_reveal() -> void:
	if run_state == null or run_state.phase != GameTypes.RunPhase.REWARD_REVEAL:
		return
	_clear_active_screen()
	var reward_screen := REWARD_REVEAL_SCENE.instantiate() as RewardRevealScreen
	_active_screen = reward_screen
	reward_screen.reveal_completed.connect(_on_reward_reveal_completed)
	reward_screen.audio_event_requested.connect(_play_audio_event)
	reward_screen.initialize(run_state, _definition_catalog)
	add_child(reward_screen)
	_logical_phase = GameTypes.RunPhase.REWARD_REVEAL
	_tutorial_controller.enter_reward(run_state.wave_number)
	_raise_tutorial_overlay()


func _on_combat_phase_changed(phase: GameTypes.RunPhase) -> void:
	if phase == GameTypes.RunPhase.REWARD_REVEAL:
		run_state.cleared_waves = maxi(run_state.cleared_waves, run_state.wave_number)
		_show_reward_reveal.call_deferred()
	elif phase == GameTypes.RunPhase.FAILED:
		_refresh_score(false)
		_show_failed.call_deferred()


func _on_reward_reveal_completed() -> void:
	if run_state == null or run_state.phase != GameTypes.RunPhase.REWARD_REVEAL:
		return
	var application: Dictionary = RewardApplicationService.apply_revealed(run_state)
	if not bool(application.get("success", false)):
		push_error("Reward application failed: %s" % application.get("error", &"unknown"))
		return
	if not RunStateMachine.can_transition_state(run_state, GameTypes.RunPhase.INVENTORY):
		push_error("Reward reveal could not enter inventory")
		return
	RunStateMachine.transition(run_state, GameTypes.RunPhase.INVENTORY)
	_show_inventory()


func _show_inventory() -> bool:
	if run_state == null or run_state.phase != GameTypes.RunPhase.INVENTORY:
		return false
	var screen: Control = _instantiate_control_scene(INVENTORY_SCENE_PATH)
	if screen == null:
		return false
	_clear_active_screen()
	_active_screen = screen
	screen.connect("item_move_requested", _on_inventory_item_move_requested)
	screen.connect("item_lock_requested", _on_inventory_item_lock_requested)
	screen.connect("sort_requested", _on_inventory_sort_requested)
	screen.connect("discard_requested", _on_inventory_discard_requested)
	screen.connect("fusion_requested", _on_inventory_fusion_requested)
	screen.connect("skill_move_requested", _on_inventory_skill_move_requested)
	screen.connect("continue_requested", _on_inventory_continue_requested)
	screen.call("initialize", run_state, _definition_catalog)
	add_child(screen)
	_logical_phase = GameTypes.RunPhase.INVENTORY
	_tutorial_controller.enter_inventory(run_state.wave_number)
	_raise_tutorial_overlay()
	return true


func _on_inventory_item_move_requested(source: Dictionary, target: Dictionary) -> void:
	var result: Dictionary = InventoryService.apply_move(
		run_state,
		StringName(source.get("kind", &"")),
		int(source.get("index", -1)),
		StringName(target.get("kind", &"")),
		int(target.get("index", -1)),
	)
	_apply_inventory_command_result(&"item_move", result)


func _on_inventory_item_lock_requested(item_id: String) -> void:
	_apply_inventory_command_result(
		&"item_lock",
		InventoryService.toggle_lock(run_state, item_id),
	)


func _on_inventory_sort_requested() -> void:
	_apply_inventory_command_result(
		&"sort",
		InventoryService.sort_inventory_by_rarity(run_state),
	)


func _on_inventory_discard_requested(
	item_ids: PackedStringArray,
	unique_confirmed: bool,
) -> void:
	_apply_inventory_command_result(
		&"discard",
		InventoryService.discard(run_state, item_ids, unique_confirmed),
	)


func _on_inventory_fusion_requested(
	material_ids: PackedStringArray,
	use_wild: bool,
) -> void:
	_apply_inventory_command_result(
		&"fusion",
		FusionCommitService.commit(
			run_state,
			material_ids,
			use_wild,
			_definition_catalog,
		),
	)


func _on_inventory_skill_move_requested(
	source_kind: StringName,
	source_id: Variant,
	target_kind: StringName,
	target_id: Variant,
) -> void:
	_apply_inventory_command_result(
		&"skill_move",
		SkillEquipService.apply_move(
			run_state,
			source_kind,
			source_id,
			target_kind,
			target_id,
		),
	)


func _apply_inventory_command_result(
	command_kind: StringName,
	result: Dictionary,
) -> void:
	if _active_screen != null and _active_screen.has_method("apply_command_result"):
		_active_screen.call("apply_command_result", command_kind, result)
	if command_kind == &"fusion" and bool(result.get("success", false)):
		_play_audio_event(&"fusion")


func _on_inventory_continue_requested() -> void:
	if run_state == null or run_state.phase != GameTypes.RunPhase.INVENTORY:
		return
	if run_state.wave_number == 8:
		if not RunStateMachine.can_transition_state(run_state, GameTypes.RunPhase.RESULT):
			_apply_inventory_command_result(
				&"continue",
				{"success": false, "error": &"inventory_gate", "message": _inventory_gate_message()},
			)
			return
		_refresh_score(true)
		RunStateMachine.transition(run_state, GameTypes.RunPhase.RESULT)
		_show_result()
		return
	if not RunStateMachine.can_transition_state(run_state, GameTypes.RunPhase.COMBAT):
		_apply_inventory_command_result(
			&"continue",
			{"success": false, "error": &"inventory_gate", "message": _inventory_gate_message()},
		)
		return
	var next_wave_number: int = run_state.wave_number + 1
	if _definition_catalog.wave(next_wave_number) == null:
		return
	_complete_w1_tutorial_if_needed()
	RunStateMachine.transition(run_state, GameTypes.RunPhase.COMBAT)
	if not combat_simulation.begin_wave(next_wave_number):
		push_error("Failed to begin wave %d" % next_wave_number)
		return
	_show_combat_arena(false)


func _show_result() -> bool:
	return _show_run_summary(RESULT_SCENE_PATH, GameTypes.RunPhase.RESULT)


func _show_failed() -> bool:
	return _show_run_summary(FAILED_SCENE_PATH, GameTypes.RunPhase.FAILED)


func _show_run_summary(
	scene_path: String,
	phase: GameTypes.RunPhase,
) -> bool:
	if run_state == null or run_state.phase != phase:
		return false
	var screen: Control = _instantiate_control_scene(scene_path)
	if screen == null:
		return false
	_clear_active_screen()
	_active_screen = screen
	screen.connect("retry_same_seed_requested", _retry_same_seed)
	screen.connect("retry_new_seed_requested", _retry_new_seed)
	screen.connect("title_requested", _show_title)
	screen.connect("exit_requested", _exit_game)
	screen.call("initialize", run_state, _definition_catalog)
	add_child(screen)
	_logical_phase = phase
	_tutorial_controller.dismiss_noncombat()
	_raise_tutorial_overlay()
	return true


func _complete_w1_tutorial_if_needed() -> void:
	if run_state == null or not _tutorial_controller.leave_w1_inventory(run_state.wave_number):
		return
	var settings_store: Variant = get_node_or_null("/root/SettingsStore")
	if settings_store == null:
		return
	settings_store.tutorial_seen = true
	if not str(settings_store.active_settings_path).is_empty():
		var save_error: Error = settings_store.save_settings()
		if save_error != OK:
			push_error("Tutorial setting save failed: %d" % save_error)


func _refresh_tutorial_overlay() -> void:
	if _tutorial_overlay == null or not is_instance_valid(_tutorial_overlay):
		return
	var phase: GameTypes.RunPhase = current_run_phase()
	var wave_number: int = run_state.wave_number if run_state != null else 0
	var message: String = _tutorial_controller.current_message(
		phase == GameTypes.RunPhase.COMBAT,
		wave_number,
	)
	if message.is_empty():
		_tutorial_overlay.hide_message()
	else:
		_tutorial_overlay.show_message(message)


func _on_tutorial_cancel_input_observed() -> void:
	_dismiss_noncombat_tutorial()


func _dismiss_noncombat_tutorial() -> void:
	if (
		current_run_phase() != GameTypes.RunPhase.COMBAT
		and _tutorial_controller.dismiss_noncombat()
	):
		_refresh_tutorial_overlay()


func _raise_tutorial_overlay() -> void:
	if (
		_tutorial_overlay != null
		and is_instance_valid(_tutorial_overlay)
		and _tutorial_overlay.get_parent() == self
	):
		move_child(_tutorial_overlay, get_child_count() - 1)


func _play_audio_event(event_id: StringName) -> void:
	if _audio_pool == null or not _audio_streams.has(event_id):
		return
	var settings_store: Variant = get_node_or_null("/root/SettingsStore")
	var master_volume: float = (
		float(settings_store.master_volume) if settings_store != null else 1.0
	)
	var sfx_volume: float = (
		float(settings_store.sfx_volume) if settings_store != null else 0.9
	)
	_audio_pool.call(
		"play_stream",
		_audio_streams[event_id],
		master_volume,
		sfx_volume,
	)


func _run_release_pack_audit() -> void:
	var result: Dictionary = ReleasePackAuditorScript.audit(
		str(_launch.get("manifest_path", ""))
	)
	var exit_code: int = int(result.get("exit_code", 3))
	if exit_code == 2:
		print("RELEASE_ARGUMENT_REJECTED name=--release-pack-audit")
	elif bool(result.get("success", false)):
		print(str(result.get("message", "")))
	else:
		print("PACK_AUDIT_FAILED reason=%s" % str(result.get("reason", &"unknown")))
	_quit_deferred(exit_code)


func _start_release_smoke() -> void:
	var settings_store: Variant = get_node_or_null("/root/SettingsStore")
	_release_smoke_validator = ReleaseSmokeValidatorScript.new()
	var result: Dictionary = _release_smoke_validator.call("begin", self, settings_store)
	if not _release_smoke_step_succeeded(result):
		return
	if not start_new_run_with_seed(int(result.get("run_seed", 20260827))):
		_fail_release_smoke(&"start_run_failed")
		return
	result = _release_smoke_validator.call("validate_started_and_prepare_timeout", self)
	_release_smoke_step_succeeded(result)


func _advance_release_smoke() -> void:
	if _release_smoke_validator == null:
		return
	var stage: StringName = _release_smoke_validator.call("stage_name")
	if stage == &"awaiting_first_failure" and _logical_phase == GameTypes.RunPhase.FAILED:
		var first_result: Dictionary = _release_smoke_validator.call(
			"validate_first_failure",
			self,
		)
		if not _release_smoke_step_succeeded(first_result):
			return
		_retry_same_seed()
		var retry_result: Dictionary = _release_smoke_validator.call(
			"validate_retry_and_prepare_timeout",
			self,
		)
		_release_smoke_step_succeeded(retry_result)
	elif stage == &"awaiting_second_failure" and _logical_phase == GameTypes.RunPhase.FAILED:
		var second_result: Dictionary = _release_smoke_validator.call(
			"validate_second_failure",
			self,
		)
		if not _release_smoke_step_succeeded(second_result):
			return
		_show_title()
		var title_result: Dictionary = _release_smoke_validator.call(
			"validate_title_and_finish",
			self,
		)
		if _release_smoke_step_succeeded(title_result):
			print("RELEASE_SMOKE_OK seed=20260827 failures=2")
			_release_smoke_validator = null
			get_tree().quit(0)


func _release_smoke_step_succeeded(result: Dictionary) -> bool:
	if bool(result.get("success", false)):
		return true
	_fail_release_smoke(StringName(result.get("reason", &"unknown")))
	return false


func _fail_release_smoke(reason: StringName) -> void:
	print("RELEASE_SMOKE_FAILED reason=%s" % String(reason))
	_release_smoke_validator = null
	get_tree().quit(1)


func _start_performance_mode() -> void:
	if not start_new_run_with_seed(int(_launch.get("run_seed", 0))):
		print("PERFORMANCE_FAILED reasons=start_run_failed")
		get_tree().quit(1)
		return
	var runner_script: Variant = load("res://src/debug/performance_runner.gd")
	if runner_script == null:
		print("PERFORMANCE_FAILED reasons=runner_missing")
		get_tree().quit(1)
		return
	var runner: Node = runner_script.new()
	runner.connect("completed", _on_performance_completed)
	add_child(runner)
	var output_directory: String = ProjectSettings.globalize_path(
		"res://artifacts/performance"
	)
	if not DirAccess.dir_exists_absolute(output_directory):
		var directory_error := DirAccess.make_dir_recursive_absolute(output_directory)
		if directory_error != OK:
			print("PERFORMANCE_FAILED reasons=output_directory code=%d" % directory_error)
			get_tree().quit(1)
			return
	var initialize_error: Error = runner.call(
		"initialize",
		combat_simulation,
		output_directory,
	)
	if initialize_error != OK:
		print(
			"PERFORMANCE_FAILED reasons=%s"
			% str(runner.get("last_error_message"))
		)
		get_tree().quit(1)


func _on_performance_completed(exit_code: int, _summary: Dictionary) -> void:
	get_tree().quit(exit_code)


func _retry_same_seed() -> void:
	if run_state == null:
		return
	start_new_run_with_seed(run_state.run_seed)


func _retry_new_seed() -> void:
	start_new_run_with_seed(SeedServiceScript.generate_run_seed())


func _refresh_score(run_cleared: bool) -> void:
	if run_state == null or _definition_catalog == null:
		return
	run_state.score_breakdown = ScoreService.calculate(
		run_state.normal_kills,
		run_state.elite_kills,
		run_state.boss_kills,
		run_state.post_quota_kills,
		run_state.cleared_waves,
		run_cleared,
		_held_equipment(),
		run_state.skill_library,
		run_state.wild_material_count,
		_definition_catalog.score_definition(),
	)


func _held_equipment() -> Array[ItemInstance]:
	var result: Array[ItemInstance] = []
	var seen: Dictionary[String, bool] = {}
	if run_state == null:
		return result
	for value: Variant in run_state.equipped.values():
		_append_held_item(result, seen, value as ItemInstance)
	for item: ItemInstance in run_state.inventory:
		_append_held_item(result, seen, item)
	for item: ItemInstance in run_state.overflow:
		_append_held_item(result, seen, item)
	return result


func _append_held_item(
	items: Array[ItemInstance],
	seen: Dictionary[String, bool],
	item: ItemInstance,
) -> void:
	if item == null or seen.has(item.item_id):
		return
	seen[item.item_id] = true
	items.append(item)


func _inventory_gate_message() -> String:
	if run_state == null:
		return "ラン状態がありません"
	if not run_state.overflow.is_empty():
		return "一時受取欄の残り %d 件を整理してください" % run_state.overflow.size()
	if run_state.equipped.get(GameTypes.EquipmentSlot.MAIN_WEAPON, null) == null:
		return "主武器が必要です"
	return "現在の状態では進めません"


func _instantiate_control_scene(scene_path: String) -> Control:
	var resource: Resource = load(scene_path)
	if not resource is PackedScene:
		push_error("Missing UI scene: %s" % scene_path)
		return null
	var node: Node = (resource as PackedScene).instantiate()
	if not node is Control:
		node.free()
		push_error("UI scene root must be Control: %s" % scene_path)
		return null
	return node as Control


func _start_qa_mode(scenario_id: String) -> void:
	var factory_script: Variant = load("res://src/debug/qa_scenario_factory.gd")
	if factory_script == null:
		print("QA_SCENARIO_FAILED reason=factory")
		get_tree().quit(1)
		return
	var result: Dictionary = factory_script.build(scenario_id, _definition_catalog)
	if not result.get("valid", false):
		print("QA_SCENARIO_REJECTED name=--qa-scenario")
		get_tree().quit(2)
		return
	run_state = result["state"] as RunState
	combat_simulation = result["simulation"] as CombatSimulation
	match run_state.phase:
		GameTypes.RunPhase.REWARD_REVEAL:
			_show_reward_reveal()
		GameTypes.RunPhase.INVENTORY:
			_show_inventory()
		GameTypes.RunPhase.RESULT:
			_show_result()
		GameTypes.RunPhase.FAILED:
			_show_failed()
		_:
			_show_combat_arena(false)


func _clear_active_screen() -> void:
	if _active_screen != null:
		var previous_screen: Node = _active_screen
		_active_screen = null
		remove_child(previous_screen)
		previous_screen.call_deferred("free")


func _reject_arguments(argument_name: String) -> void:
	if OS.is_debug_build():
		print("DEBUG_ARGUMENT_REJECTED name=%s child_nodes=0 run_state=0" % argument_name)
	else:
		print("RELEASE_ARGUMENT_REJECTED name=%s" % argument_name)
	_quit_deferred(2)


func _quit_deferred(exit_code: int) -> void:
	get_tree().call_deferred("quit", exit_code)


func _exit_game() -> void:
	get_tree().quit(0)
