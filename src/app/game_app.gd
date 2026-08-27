extends Node


const LaunchArgumentsScript = preload("res://src/app/launch_arguments.gd")
const DefinitionCatalogScript = preload("res://src/core/definition_catalog.gd")
const RunStateFactoryScript = preload("res://src/core/run_state_factory.gd")
const SeedServiceScript = preload("res://src/core/seed_service.gd")
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
var _prepared_evidence_id: String = ""

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
		_launch_valid = true
		_quit_deferred(0)
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
			LaunchArgumentsScript.MODE_QA_SCENARIO,
		]
		else settings_store.initialize_for_game(_launch["settings_path"])
	)
	if initialize_error == OK and mode == LaunchArgumentsScript.MODE_QA_SCENARIO:
		settings_store.tutorial_seen = true
	return initialize_error


func _ready() -> void:
	if not _launch_valid or _launch["mode"] == LaunchArgumentsScript.MODE_RELEASE_PACK_AUDIT:
		return
	match _launch.get("mode", LaunchArgumentsScript.MODE_NORMAL):
		LaunchArgumentsScript.MODE_EVIDENCE:
			_start_evidence_mode(_launch["evidence"])
		LaunchArgumentsScript.MODE_QA_SCENARIO:
			_start_qa_mode(_launch["qa_scenario"])
		_:
			_show_title()


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
	var title_screen := TITLE_SCENE.instantiate() as Control
	_active_screen = title_screen
	title_screen.connect("start_requested", _start_new_run)
	title_screen.connect("exit_requested", _exit_game)
	add_child(title_screen)

	match _launch.get("mode", LaunchArgumentsScript.MODE_NORMAL):
		LaunchArgumentsScript.MODE_SMOKE_QUIT:
			_smoke_frames_remaining = _launch["smoke_frames"]
		LaunchArgumentsScript.MODE_RELEASE_SMOKE:
			_smoke_frames_remaining = 1


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
	arena.initialize(combat_simulation)
	arena.set_simulation_paused(paused)
	_logical_phase = GameTypes.RunPhase.COMBAT
	return true


func _show_reward_reveal(evidence_mode: String = "") -> void:
	if run_state == null or run_state.phase != GameTypes.RunPhase.REWARD_REVEAL:
		return
	_clear_active_screen()
	var reward_screen := REWARD_REVEAL_SCENE.instantiate() as RewardRevealScreen
	_active_screen = reward_screen
	reward_screen.reveal_completed.connect(_on_reward_reveal_completed)
	reward_screen.initialize(run_state)
	if not evidence_mode.is_empty():
		reward_screen.set_evidence_mode(evidence_mode)
	add_child(reward_screen)
	_logical_phase = GameTypes.RunPhase.REWARD_REVEAL


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


func _show_inventory(evidence_mode: String = "") -> bool:
	if run_state == null or run_state.phase != GameTypes.RunPhase.INVENTORY:
		return false
	var screen: Control = _instantiate_control_scene(INVENTORY_SCENE_PATH)
	if screen == null:
		return false
	if not evidence_mode.is_empty():
		if not screen.has_method("set_evidence_mode"):
			screen.free()
			return false
		var mode_accepted: bool = bool(screen.call("set_evidence_mode", evidence_mode))
		if not mode_accepted:
			screen.free()
			return false
	_clear_active_screen()
	_active_screen = screen
	screen.connect("item_move_requested", _on_inventory_item_move_requested)
	screen.connect("item_lock_requested", _on_inventory_item_lock_requested)
	screen.connect("discard_requested", _on_inventory_discard_requested)
	screen.connect("fusion_requested", _on_inventory_fusion_requested)
	screen.connect("skill_move_requested", _on_inventory_skill_move_requested)
	screen.connect("continue_requested", _on_inventory_continue_requested)
	screen.call("initialize", run_state, _definition_catalog)
	add_child(screen)
	_logical_phase = GameTypes.RunPhase.INVENTORY
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
	unique_confirmed: bool,
) -> void:
	_apply_inventory_command_result(
		&"fusion",
		FusionCommitService.commit(
			run_state,
			material_ids,
			use_wild,
			unique_confirmed,
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
	RunStateMachine.transition(run_state, GameTypes.RunPhase.COMBAT)
	if not combat_simulation.begin_wave(next_wave_number):
		push_error("Failed to begin wave %d" % next_wave_number)
		return
	_show_combat_arena(false)


func _show_result(evidence_mode: String = "") -> bool:
	return _show_run_summary(
		RESULT_SCENE_PATH,
		GameTypes.RunPhase.RESULT,
		evidence_mode,
	)


func _show_failed() -> bool:
	return _show_run_summary(FAILED_SCENE_PATH, GameTypes.RunPhase.FAILED)


func _show_run_summary(
	scene_path: String,
	phase: GameTypes.RunPhase,
	evidence_mode: String = "",
) -> bool:
	if run_state == null or run_state.phase != phase:
		return false
	var screen: Control = _instantiate_control_scene(scene_path)
	if screen == null:
		return false
	if not evidence_mode.is_empty():
		if not screen.has_method("set_evidence_mode"):
			screen.free()
			return false
		var mode_accepted: bool = bool(screen.call("set_evidence_mode", evidence_mode))
		if not mode_accepted:
			screen.free()
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
	return true


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


func _start_evidence_mode(evidence_id: String) -> void:
	if evidence_id.begins_with("gate_05:"):
		_start_gate_five_evidence(evidence_id)
		return
	var first_wave: WaveDefinition = _definition_catalog.wave(1)
	run_state = RunStateFactoryScript.create(20260827, first_wave)
	combat_simulation = CombatSimulation.new()
	combat_simulation.initialize(run_state, _definition_catalog)
	combat_simulation.freeze_enemy_ai = true
	combat_simulation.freeze_enemy_timers = true
	combat_simulation.freeze_normal_spawn = true
	combat_simulation.freeze_countdown = true
	match evidence_id:
		"gate_03:arena_combat":
			combat_simulation.evidence_caption = "TRACKER  •  FAST  •  ARMORED  •  RANGED"
			_build_arena_combat_evidence()
		"gate_03:weapon_shapes":
			combat_simulation.evidence_caption = "弓：軌道  ／  杖：着弾範囲  ／  剣：120°扇形"
			_build_weapon_shapes_evidence()
		"gate_03:boss_gate":
			combat_simulation.begin_wave(8)
			combat_simulation.evidence_caption = "W8 BOSS GATE"
			combat_simulation.freeze_enemy_ai = true
			combat_simulation.freeze_enemy_timers = true
			combat_simulation.freeze_normal_spawn = true
			combat_simulation.freeze_countdown = true
			var evidence_boss: EnemyEntity = combat_simulation.enemy_system.enemy_store.get_by_id(0)
			if evidence_boss != null:
				evidence_boss.position = Vector2(5.0, 2.0)
			run_state.wave_kills = 299
			run_state.non_boss_spawned = 299
			run_state.boss_defeated = false
		"gate_04:chest_absorb":
			combat_simulation.evidence_caption = "獲得済み宝箱  •  0.25秒で自動吸収"
			for chest_index in range(5):
				var chest_position := Vector2(
					-2.5 + float(chest_index) * 1.25,
					0.3 + (-0.5 if chest_index % 2 == 0 else 0.5),
				)
				combat_simulation.loot_service.acquire_fixed_chests(
					1,
					chest_position,
					run_state.physics_tick,
				)
			combat_simulation.chest_visual_pool.advance(0.12)
		"gate_04:epic_prealert", "gate_04:reward_grid":
			var factory_script: Variant = load("res://src/debug/qa_scenario_factory.gd")
			var result: Dictionary = factory_script.build("reward_controls", _definition_catalog)
			if not result.get("valid", false):
				print("EVIDENCE_CAPTURE_FAILED reason=reward_fixture")
				get_tree().quit(1)
				return
			run_state = result["state"] as RunState
			combat_simulation = result["simulation"] as CombatSimulation
			_show_reward_reveal(evidence_id.trim_prefix("gate_04:"))
			_attach_evidence_capture()
			return
		_:
			_show_title()
			_attach_evidence_capture()
			return
	_show_combat_arena(true)
	_attach_evidence_capture()


func _start_gate_five_evidence(evidence_id: String) -> void:
	_prepared_evidence_id = ""
	var scenario_id: String
	match evidence_id:
		"gate_05:inventory_full", "gate_05:fusion_unique_warning":
			scenario_id = "inventory_controller"
		"gate_05:broken_build":
			scenario_id = "immortal_100"
		"gate_05:final_result":
			scenario_id = "result_controller"
		_:
			print("EVIDENCE_ARGUMENT_REJECTED name=--evidence")
			get_tree().quit(2)
			return
	var factory_script: Variant = load("res://src/debug/qa_scenario_factory.gd")
	var result: Dictionary = factory_script.build(scenario_id, _definition_catalog)
	if not result.get("valid", false):
		print("EVIDENCE_CAPTURE_FAILED reason=gate05_fixture")
		get_tree().quit(1)
		return
	run_state = result["state"] as RunState
	combat_simulation = result["simulation"] as CombatSimulation
	var prepared: bool = false
	match evidence_id:
		"gate_05:inventory_full":
			prepared = _show_inventory("inventory_full")
		"gate_05:fusion_unique_warning":
			prepared = _show_inventory("fusion_unique_warning")
		"gate_05:broken_build":
			prepared = (
				_configure_broken_build_evidence()
				and _show_combat_arena(true)
			)
		"gate_05:final_result":
			prepared = _show_result("final_result")
	if not prepared:
		_fail_evidence_capture("gate05_screen_setup")
		return
	_prepared_evidence_id = evidence_id
	_attach_evidence_capture()


func _configure_broken_build_evidence() -> bool:
	if run_state == null or combat_simulation == null:
		return false
	var bell: SkillState = run_state.skill_library.get(
		&"bell_of_retribution",
		null,
	) as SkillState
	if bell == null:
		return false
	var starfall := SkillState.new()
	starfall.skill_id = &"starfall"
	starfall.level = 2
	starfall.equipped_slot = 1
	starfall.trigger_progress = 2.5
	run_state.skill_library[starfall.skill_id] = starfall
	var pending := PendingSkillActivation.new()
	pending.activation_serial = run_state.next_activation_serial
	run_state.next_activation_serial += 1
	pending.origin_event_serial = -1
	bell.pending_queue.append(pending)
	combat_simulation.evidence_caption = "被ダメージ軽減 100%  •  火力 50%"
	return true


func validate_evidence_capture_state(evidence_id: String) -> Dictionary:
	if (
		_launch.get("mode", LaunchArgumentsScript.MODE_NORMAL)
		!= LaunchArgumentsScript.MODE_EVIDENCE
		or str(_launch.get("evidence", "")) != evidence_id
	):
		return _evidence_validation_failure("gate05_argument")
	if _prepared_evidence_id != evidence_id:
		return _evidence_validation_failure("gate05_not_prepared")
	if (
		run_state == null
		or _active_screen == null
		or not is_instance_valid(_active_screen)
		or not _active_screen.is_inside_tree()
	):
		return _evidence_validation_failure("gate05_active_screen")
	if _active_screen is CanvasItem and not (_active_screen as CanvasItem).is_visible_in_tree():
		return _evidence_validation_failure("gate05_screen_hidden")

	match evidence_id:
		"gate_05:inventory_full":
			return _validate_inventory_evidence("inventory_full", false)
		"gate_05:fusion_unique_warning":
			return _validate_inventory_evidence("fusion_unique_warning", true)
		"gate_05:broken_build":
			return _validate_broken_build_evidence()
		"gate_05:final_result":
			return _validate_final_result_evidence()
	return _evidence_validation_failure("gate05_unknown_state")


func _validate_inventory_evidence(mode: String, expect_warning: bool) -> Dictionary:
	if run_state.phase != GameTypes.RunPhase.INVENTORY:
		return _evidence_validation_failure("gate05_inventory_phase")
	if not _active_screen.has_method("debug_state"):
		return _evidence_validation_failure("gate05_inventory_debug")
	var debug_value: Variant = _active_screen.call("debug_state")
	if not debug_value is Dictionary:
		return _evidence_validation_failure("gate05_inventory_debug")
	var debug_state: Dictionary = debug_value as Dictionary
	if str(debug_state.get("evidence_mode", "")) != mode:
		return _evidence_validation_failure("gate05_inventory_mode")
	if _inventory_item_count() != RunState.INVENTORY_CAPACITY:
		return _evidence_validation_failure("gate05_inventory_count")
	if run_state.overflow.size() != 4 or int(debug_state.get("overflow_count", -1)) != 4:
		return _evidence_validation_failure("gate05_overflow_count")
	if expect_warning:
		var expected_materials := PackedStringArray([
			"qa-inventory-18",
			"qa-inventory-19",
			"qa-inventory-33",
		])
		if (
			not bool(debug_state.get("fusion_open", false))
			or not bool(debug_state.get("confirmation_open", false))
			or debug_state.get("fusion_material_ids", PackedStringArray()) != expected_materials
		):
			return _evidence_validation_failure("gate05_unique_warning")
	elif (
		bool(debug_state.get("fusion_open", false))
		or bool(debug_state.get("confirmation_open", false))
	):
		return _evidence_validation_failure("gate05_inventory_overlay")
	return {"valid": true, "reason": ""}


func _validate_broken_build_evidence() -> Dictionary:
	if (
		run_state.phase != GameTypes.RunPhase.COMBAT
		or not _active_screen is ArenaPresenter
		or combat_simulation == null
		or combat_simulation.state != run_state
	):
		return _evidence_validation_failure("gate05_broken_build_phase")
	if not is_equal_approx(
		StatCalculator.effective_damage_reduction_pct(run_state.equipped),
		100.0,
	):
		return _evidence_validation_failure("gate05_broken_build_reduction")
	var snapshot: CombatSnapshot = combat_simulation.build_snapshot()
	var skill_slots: Array = snapshot.hud_values.get("skill_slots", []) as Array
	if skill_slots.size() != 2:
		return _evidence_validation_failure("gate05_broken_build_skills")
	var first_slot: Dictionary = skill_slots[0] as Dictionary
	var second_slot: Dictionary = skill_slots[1] as Dictionary
	if (
		str(first_slot.get("skill_id", "")) != "bell_of_retribution"
		or int(first_slot.get("pending_count", 0)) != 1
		or str(second_slot.get("skill_id", "")) != "starfall"
	):
		return _evidence_validation_failure("gate05_broken_build_skills")
	var hud: Node = _active_screen.get_node_or_null("%CombatHUD")
	if hud == null:
		return _evidence_validation_failure("gate05_broken_build_hud")
	var first_label := hud.get_node_or_null("%SkillSlot0Value") as Label
	var second_label := hud.get_node_or_null("%SkillSlot1Value") as Label
	if (
		first_label == null
		or second_label == null
		or not "報復の鐘" in first_label.text
		or not "予約1" in first_label.text
		or not "星落とし" in second_label.text
		or not "予約0" in second_label.text
	):
		return _evidence_validation_failure("gate05_broken_build_hud")
	return {"valid": true, "reason": ""}


func _validate_final_result_evidence() -> Dictionary:
	if run_state.phase != GameTypes.RunPhase.RESULT:
		return _evidence_validation_failure("gate05_result_phase")
	if not _active_screen.has_method("debug_state"):
		return _evidence_validation_failure("gate05_result_debug")
	var debug_value: Variant = _active_screen.call("debug_state")
	if not debug_value is Dictionary:
		return _evidence_validation_failure("gate05_result_debug")
	var debug_state: Dictionary = debug_value as Dictionary
	if (
		str(debug_state.get("screen", "")) != "result"
		or int(debug_state.get("run_seed", -1)) != 20260827
		or int(debug_state.get("combat_score", -1)) != 9000
		or int(debug_state.get("final_build_score", -1)) != 3055
		or int(debug_state.get("total", -1)) != 12055
	):
		return _evidence_validation_failure("gate05_result_values")
	var run_text: String = str(debug_state.get("run_text", ""))
	var score_text: String = str(debug_state.get("score_text", ""))
	if (
		not "SEED  20260827" in run_text
		or not "戦闘由来小計  9000" in score_text
		or not "最終ビルド小計  3055" in score_text
		or not "合計  12055" in score_text
	):
		return _evidence_validation_failure("gate05_result_text")
	return {"valid": true, "reason": ""}


func _inventory_item_count() -> int:
	var count: int = 0
	for item: ItemInstance in run_state.inventory:
		if item != null:
			count += 1
	return count


func _evidence_validation_failure(reason: String) -> Dictionary:
	return {"valid": false, "reason": reason}


func _build_arena_combat_evidence() -> void:
	combat_simulation.player_position = Vector2(-1.5, 0.5)
	combat_simulation.spawn_fixture_enemy(GameTypes.EnemyType.TRACKER, Vector2(-7.0, -3.0))
	combat_simulation.spawn_fixture_enemy(GameTypes.EnemyType.FAST, Vector2(-3.0, -4.5))
	combat_simulation.spawn_fixture_enemy(GameTypes.EnemyType.ARMORED, Vector2(3.0, -2.0))
	combat_simulation.spawn_fixture_enemy(GameTypes.EnemyType.RANGED, Vector2(7.0, 2.5))


func _build_weapon_shapes_evidence() -> void:
	combat_simulation.player_position = Vector2.ZERO
	for index: int in range(25):
		combat_simulation.add_fixture_vfx(
			Vector2(-11.0 + float(index) * 0.75, -4.5),
			0.18,
			Color(1.0, 0.72, 0.2),
		)
	for index: int in range(40):
		var angle: float = TAU * float(index) / 40.0
		combat_simulation.add_fixture_vfx(
			Vector2(-4.0, 2.5) + Vector2(cos(angle), sin(angle)) * 2.25,
			0.2,
			Color(0.35, 0.75, 1.0),
		)
	for ray_index: int in range(7):
		var ray_angle: float = deg_to_rad(-60.0 + float(ray_index) * 20.0)
		for step_index: int in range(1, 8):
			combat_simulation.add_fixture_vfx(
				Vector2(5.0, 2.0) + Vector2(cos(ray_angle), sin(ray_angle)) * float(step_index) * 0.34,
				0.14,
				Color(1.0, 0.35, 0.3),
			)


func _attach_evidence_capture() -> bool:
	var evidence_scene_resource := load("res://scenes/debug/evidence_scene.tscn")
	if not evidence_scene_resource is PackedScene:
		_fail_evidence_capture("scene")
		return false
	add_child((evidence_scene_resource as PackedScene).instantiate())
	return true


func _fail_evidence_capture(reason: String) -> void:
	print("EVIDENCE_CAPTURE_FAILED reason=%s" % reason)
	get_tree().quit(1)


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
