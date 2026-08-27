extends Node


const LaunchArgumentsScript = preload("res://src/app/launch_arguments.gd")
const DefinitionCatalogScript = preload("res://src/core/definition_catalog.gd")
const RunStateFactoryScript = preload("res://src/core/run_state_factory.gd")
const SeedServiceScript = preload("res://src/core/seed_service.gd")
const TITLE_SCENE: PackedScene = preload("res://scenes/ui/title_screen.tscn")
const ARENA_SCENE: PackedScene = preload("res://scenes/gameplay/arena_combat.tscn")

var _launch_valid: bool = false
var _launch: Dictionary = {}
var _definition_catalog: DefinitionCatalog = null
var _active_screen: Node = null
var _smoke_frames_remaining: int = 0
var _logical_phase: GameTypes.RunPhase = GameTypes.RunPhase.BOOT

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


func _show_combat_arena(paused: bool) -> void:
	_clear_active_screen()
	var arena := ARENA_SCENE.instantiate() as ArenaPresenter
	_active_screen = arena
	add_child(arena)
	arena.initialize(combat_simulation)
	arena.set_simulation_paused(paused)
	_logical_phase = GameTypes.RunPhase.COMBAT


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
	_show_combat_arena(false)


func _start_evidence_mode(evidence_id: String) -> void:
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
		_:
			_show_title()
			_attach_evidence_capture()
			return
	_show_combat_arena(true)
	_attach_evidence_capture()


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


func _attach_evidence_capture() -> void:
	var evidence_scene_resource := load("res://scenes/debug/evidence_scene.tscn")
	if not evidence_scene_resource is PackedScene:
		print("EVIDENCE_CAPTURE_FAILED reason=scene")
		get_tree().quit(1)
		return
	add_child((evidence_scene_resource as PackedScene).instantiate())


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
