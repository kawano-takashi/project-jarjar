extends RefCounted


const ARENA_SCENE: PackedScene = preload("res://scenes/gameplay/arena_combat.tscn")
const GAME_APP_SCRIPT: GDScript = preload("res://src/app/game_app.gd")
const CAMERA_SAMPLE_COUNT: int = 64
const CAMERA_LAG_LIMIT_M: float = 0.60
const FIXED_DELTA_SECONDS: float = 1.0 / 60.0


func test_names() -> PackedStringArray:
	return PackedStringArray([
		"combat_snapshot_presentation_defaults_are_backward_compatible",
		"combat_presentation_event_resolves_audio_identity",
		"audio_priority_preserves_important_voices",
		"audio_reserved_groups_and_twelve_cue_admission_cap",
		"camera_projection_and_reversal_hard_contract",
		"reduced_flash_and_evolved_projectile_cues_are_explicit",
		"kill_chain_snapshot_remains_authoritative_across_events",
		"terminal_hold_uses_exact_physics_ticks",
	])


func run_test(test_name: String, assertions: Variant, context: Dictionary) -> void:
	match test_name:
		"combat_snapshot_presentation_defaults_are_backward_compatible":
			_test_snapshot_defaults(assertions)
		"combat_presentation_event_resolves_audio_identity":
			_test_presentation_event(assertions)
		"audio_priority_preserves_important_voices":
			_test_audio_priority(assertions)
		"audio_reserved_groups_and_twelve_cue_admission_cap":
			_test_audio_reserved_groups_and_admission(assertions)
		"camera_projection_and_reversal_hard_contract":
			await _test_camera_hard_contract(assertions, context["tree"] as SceneTree)
		"reduced_flash_and_evolved_projectile_cues_are_explicit":
			await _test_accessible_evolved_cues(assertions, context["tree"] as SceneTree)
		"kill_chain_snapshot_remains_authoritative_across_events":
			await _test_kill_chain_snapshot_authority(assertions, context["tree"] as SceneTree)
		"terminal_hold_uses_exact_physics_ticks":
			_test_terminal_hold_ticks(assertions)
		_:
			assertions.expect_true(false, "registered presentation API test")


func _test_snapshot_defaults(assertions: Variant) -> void:
	var snapshot := CombatSnapshot.new(
		Vector2(2.0, -3.0),
		[Transform3D.IDENTITY],
		[Transform3D.IDENTITY],
	)
	assertions.expect_equal(1, snapshot.active_enemy_count, "legacy enemy transforms still count")
	assertions.expect_equal(1, snapshot.active_projectile_count, "legacy projectile transforms still count")
	assertions.expect_equal(0, snapshot.enemy_visual_kinds.size(), "visual kinds are optional")
	assertions.expect_equal(0, snapshot.presentation_events.size(), "presentation events default empty")
	assertions.expect_true(not snapshot.boss_charge_active, "boss charge defaults inactive")
	assertions.expect_equal(0, snapshot.boss_charge_spoke_count, "boss charge defaults without spokes")


func _test_presentation_event(assertions: Variant) -> void:
	var event := CombatPresentationEvent.new(
		CombatPresentationEvent.Kind.ENEMY_KILLED,
		&"",
		Vector2(4.0, 5.0),
		CombatSnapshot.EnemyVisualKind.ELITE,
		CombatSnapshot.ProjectileVisualKind.HOMING_CORE,
		&"homing_core",
		4,
		1.0,
		CombatPresentationEvent.Priority.IMPORTANT,
		120,
	)
	assertions.expect_equal(&"enemy_kill", event.resolved_event_id(), "kill event resolves default audio id")
	assertions.expect_equal(4, event.count, "batched event preserves count")
	assertions.expect_equal(&"homing_core", event.source_effect_id, "event preserves lineage")
	assertions.expect_equal(CombatSnapshot.EnemyVisualKind.ELITE, event.enemy_type, "event exposes the typed enemy contract")
	assertions.expect_equal(120, event.tick, "event exposes the deterministic tick contract")
	assertions.expect_equal(120, event.combat_tick, "event preserves deterministic tick")


func _test_audio_priority(assertions: Variant) -> void:
	var active: Array[bool] = [true, true]
	var started: Array[int] = [10, 20]
	var priorities := PackedInt32Array([
		AudioVoicePool.Priority.TERMINAL,
		AudioVoicePool.Priority.NORMAL,
	])
	assertions.expect_equal(
		-1,
		AudioVoicePool.select_voice_index_for_priority(
			active,
			started,
			priorities,
			AudioVoicePool.Priority.AMBIENT,
		),
		"ambient feedback cannot steal normal or terminal voices",
	)
	assertions.expect_equal(
		1,
		AudioVoicePool.select_voice_index_for_priority(
			active,
			started,
			priorities,
			AudioVoicePool.Priority.IMPORTANT,
		),
		"important feedback steals the eligible normal voice",
	)


func _test_audio_reserved_groups_and_admission(assertions: Variant) -> void:
	assertions.expect_equal(
		AudioVoicePool.Priority.NORMAL,
		int(SurvivalFeedback.PRIORITY_BY_EVENT[&"enemy_hit"]),
		"enemy hit cues use the combat group rather than consuming pickup voices",
	)
	assertions.expect_equal(
		AudioVoicePool.Priority.AMBIENT,
		int(SurvivalFeedback.PRIORITY_BY_EVENT[&"xp_pickup"]),
		"XP cues remain in the pickup group",
	)
	assertions.expect_equal(
		int(AudioVoicePool.Priority.IMPORTANT),
		int(CombatPresentationEvent.Priority.IMPORTANT),
		"simulation and playback use identical audio-priority ordinals",
	)
	var active: Array[bool] = []
	var started: Array[int] = []
	for voice_index: int in range(AudioVoicePool.VOICE_COUNT):
		active.append(false)
		started.append(voice_index)
	var priorities := PackedInt32Array()
	priorities.resize(AudioVoicePool.VOICE_COUNT)
	priorities.fill(AudioVoicePool.Priority.AMBIENT)
	assertions.expect_equal(
		AudioVoicePool.CRITICAL_VOICE_START,
		AudioVoicePool.select_reserved_voice_index(
			active,
			started,
			priorities,
			AudioVoicePool.Priority.IMPORTANT,
		),
		"important cues start inside the four reserved critical voices",
	)
	assertions.expect_equal(
		AudioVoicePool.COMBAT_VOICE_START,
		AudioVoicePool.select_reserved_voice_index(
			active,
			started,
			priorities,
			AudioVoicePool.Priority.NORMAL,
		),
		"normal combat cues start inside the eight combat voices",
	)
	assertions.expect_equal(
		AudioVoicePool.PICKUP_VOICE_START,
		AudioVoicePool.select_reserved_voice_index(
			active,
			started,
			priorities,
			AudioVoicePool.Priority.AMBIENT,
		),
		"pickup cues start inside the four pickup voices",
	)
	for voice_index: int in range(
		AudioVoicePool.COMBAT_VOICE_START,
		AudioVoicePool.COMBAT_VOICE_START + AudioVoicePool.COMBAT_VOICE_COUNT,
	):
		active[voice_index] = true
		priorities[voice_index] = AudioVoicePool.Priority.NORMAL
	assertions.expect_equal(
		AudioVoicePool.COMBAT_VOICE_START,
		AudioVoicePool.select_reserved_voice_index(
			active,
			started,
			priorities,
			AudioVoicePool.Priority.NORMAL,
		),
		"normal cues recycle the oldest combat voice instead of a free critical voice",
	)

	var pool := AudioVoicePool.new()
	for cue_index: int in range(AudioVoicePool.MAX_NONCRITICAL_CUES_PER_WINDOW):
		assertions.expect_true(
			pool._admit_cue(cue_index, AudioVoicePool.Priority.NORMAL),
			"noncritical cue %d is admitted within its reserved budget" % cue_index,
		)
	assertions.expect_false(
		pool._admit_cue(20, AudioVoicePool.Priority.NORMAL),
		"ninth normal cue is rejected so four admissions remain for critical cues",
	)
	for cue_index: int in range(4):
		assertions.expect_true(
			pool._admit_cue(30 + cue_index, AudioVoicePool.Priority.IMPORTANT),
			"critical cue %d uses the reserved global admission" % cue_index,
		)
	assertions.expect_false(
		pool._admit_cue(40, AudioVoicePool.Priority.TERMINAL),
		"thirteenth cue inside one second is rejected by the global cap",
	)
	assertions.expect_true(
		pool._admit_cue(
			AudioVoicePool.ADMISSION_WINDOW_USEC + 100,
			AudioVoicePool.Priority.TERMINAL,
		),
		"admission recovers after the rolling one-second window",
	)
	pool.free()

	var pickup_admission := AudioCueAdmission.new()
	for pickup_index: int in range(AudioCueAdmission.MAX_PICKUP_CUES_PER_WINDOW):
		assertions.expect_true(
			pickup_admission.try_admit(
				pickup_index,
				60,
				AudioVoicePool.Priority.AMBIENT,
				StringName("pickup_%d" % pickup_index),
			),
			"pickup cue %d is admitted within the four-voice budget" % pickup_index,
		)
	assertions.expect_false(
		pickup_admission.try_admit(
			5,
			60,
			AudioVoicePool.Priority.AMBIENT,
			&"pickup_4",
		),
		"fifth pickup cue is suppressed inside one combat second",
	)
	pickup_admission.reset()
	assertions.expect_equal(0, pickup_admission.admitted_count, "audio reset clears admitted telemetry")
	assertions.expect_equal(0, pickup_admission.suppressed_count, "audio reset clears suppressed telemetry")
	assertions.expect_true(
		pickup_admission.try_admit(
			0,
			60,
			AudioVoicePool.Priority.NORMAL,
			&"hit",
			2,
		),
		"first grouped cue starts its cooldown",
	)
	assertions.expect_false(
		pickup_admission.try_admit(
			1,
			60,
			AudioVoicePool.Priority.NORMAL,
			&"hit",
			2,
		),
		"group cooldown suppresses the next combat-tick cue",
	)
	assertions.expect_true(
		pickup_admission.try_admit(
			1,
			60,
			AudioVoicePool.Priority.TERMINAL,
			&"hit",
			2,
			true,
		),
		"forced terminal cue bypasses group cooldown while retaining the global budget",
	)


func _test_camera_hard_contract(assertions: Variant, tree: SceneTree) -> void:
	var arena: ArenaPresenter = ARENA_SCENE.instantiate() as ArenaPresenter
	assertions.expect_true(arena != null, "arena instantiates for camera hard-contract measurements")
	if arena == null:
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	tree.root.add_child(viewport)
	viewport.add_child(arena)
	await tree.process_frame
	await tree.process_frame
	var camera: Camera3D = arena.get_node("%ArenaCamera") as Camera3D
	assertions.expect_true(camera != null, "camera exists for projection measurements")
	if camera != null:
		arena.present_snapshot(CombatSnapshot.new(Vector2.ZERO), 0.0)
		var viewport_sizes: Array[Vector2i] = [
			Vector2i(1024, 768),
			Vector2i(1280, 800),
			Vector2i(1600, 900),
			Vector2i(2520, 1080),
			Vector2i(1280, 720),
		]
		var aspect_names := PackedStringArray(["4:3", "16:10", "16:9", "21:9", "1280x720 stretch"])
		for aspect_index: int in range(viewport_sizes.size()):
			viewport.size = viewport_sizes[aspect_index]
			await tree.process_frame
			_assert_projected_disc_inside(
				assertions,
				camera,
				viewport_sizes[aspect_index],
				CombatEnvelope.DAMAGE_CENTER_RADIUS,
				"%s radius-10 enemy centers" % aspect_names[aspect_index],
			)
			_assert_projected_disc_inside(
				assertions,
				camera,
				viewport_sizes[aspect_index],
				CombatEnvelope.EFFECT_OUTER_RADIUS,
				"%s radius-9 effect outer edge" % aspect_names[aspect_index],
			)
		assertions.expect_equal(
			"canvas_items",
			str(ProjectSettings.get_setting("display/window/stretch/mode", "")),
			"1280x720 override uses the configured canvas stretch mode",
		)
		assertions.expect_equal(
			"expand",
			str(ProjectSettings.get_setting("display/window/stretch/aspect", "")),
			"stretch expands coverage rather than cropping an aspect",
		)
		assertions.expect_equal(
			1280,
			int(ProjectSettings.get_setting("display/window/size/window_width_override", 0)),
			"release window override exercises 1280 width",
		)
		assertions.expect_equal(
			720,
			int(ProjectSettings.get_setting("display/window/size/window_height_override", 0)),
			"release window override exercises 720 height",
		)

		arena.initialize(null)
		var player_position := Vector2(-5.0, 0.0)
		arena.present_snapshot(CombatSnapshot.new(player_position), FIXED_DELTA_SECONDS)
		for forward_tick: int in range(120):
			player_position.x += CombatSimulation.PLAYER_SPEED * FIXED_DELTA_SECONDS
			arena.present_snapshot(CombatSnapshot.new(player_position), FIXED_DELTA_SECONDS)
		var maximum_reversal_lag: float = 0.0
		for reverse_tick: int in range(120):
			player_position.x -= CombatSimulation.PLAYER_SPEED * FIXED_DELTA_SECONDS
			arena.present_snapshot(CombatSnapshot.new(player_position), FIXED_DELTA_SECONDS)
			var camera_target: Vector3 = camera.position - ArenaPresenter.CAMERA_OFFSET
			maximum_reversal_lag = maxf(
				maximum_reversal_lag,
				Vector2(camera_target.x, camera_target.z).distance_to(player_position),
			)
		assertions.expect_true(
			maximum_reversal_lag <= CAMERA_LAG_LIMIT_M + 0.0001,
			"rapid 4.05-meter-per-second reversal keeps follow lag at or below 0.60 meters (%.4f)" % maximum_reversal_lag,
		)
	viewport.remove_child(arena)
	arena.free()
	tree.root.remove_child(viewport)
	viewport.free()
	await tree.process_frame


func _assert_projected_disc_inside(
	assertions: Variant,
	camera: Camera3D,
	viewport_size: Vector2i,
	radius: float,
	label: String,
) -> void:
	var all_inside: bool = _screen_point_inside(
		camera.unproject_position(Vector3.ZERO),
		viewport_size,
	)
	for sample_index: int in range(CAMERA_SAMPLE_COUNT):
		var direction := Vector2.from_angle(TAU * float(sample_index) / float(CAMERA_SAMPLE_COUNT))
		var world_point := Vector3(direction.x * radius, 0.0, direction.y * radius)
		all_inside = all_inside and _screen_point_inside(
			camera.unproject_position(world_point),
			viewport_size,
		)
	assertions.expect_true(all_inside, "%s remain fully inside the measured viewport" % label)


func _screen_point_inside(screen_point: Vector2, viewport_size: Vector2i) -> bool:
	return (
		screen_point.x >= 0.0
		and screen_point.y >= 0.0
		and screen_point.x <= float(viewport_size.x)
		and screen_point.y <= float(viewport_size.y)
	)


func _test_accessible_evolved_cues(assertions: Variant, tree: SceneTree) -> void:
	var arena: ArenaPresenter = ARENA_SCENE.instantiate() as ArenaPresenter
	assertions.expect_true(arena != null, "arena instantiates for presentation cue checks")
	if arena == null:
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	tree.root.add_child(viewport)
	viewport.add_child(arena)
	await tree.process_frame
	await tree.process_frame

	var enemy_instances: MultiMeshInstance3D = arena.get_node("%EnemyInstances") as MultiMeshInstance3D
	var enemy_material: ShaderMaterial = enemy_instances.multimesh.mesh.material as ShaderMaterial
	var shader_code: String = enemy_material.shader.code
	assertions.expect_true(
		shader_code.contains("mix(0.5, 0.25, reduce_flashes)"),
		"Reduce Flashes caps enemy hit white mixing at twenty-five percent",
	)
	assertions.expect_true(
		shader_code.contains("mix(1.5, 0.35, reduce_flashes)"),
		"Reduce Flashes caps entry emission at thirty-five percent",
	)

	var snapshot := CombatSnapshot.new()
	snapshot.projectile_transforms = [Transform3D.IDENTITY]
	snapshot.projectile_visual_kinds = PackedInt32Array([
		CombatSnapshot.ProjectileVisualKind.HOMING_CORE,
	])
	snapshot.projectile_visual_custom_data = PackedColorArray([Color(1.0, 0.0, 0.0, 0.0)])
	arena.present_snapshot(snapshot, 0.0)
	var inner: MultiMesh = (arena.get_node("%EvolvedOutlineInnerInstances") as MultiMeshInstance3D).multimesh
	var outer: MultiMesh = (arena.get_node("%EvolvedOutlineOuterInstances") as MultiMeshInstance3D).multimesh
	var core: MultiMesh = (arena.get_node("%EvolvedCoreInstances") as MultiMeshInstance3D).multimesh
	assertions.expect_equal(1, inner.visible_instance_count, "evolved projectile adds its inner outline")
	assertions.expect_equal(1, outer.visible_instance_count, "evolved projectile adds its second outline")
	assertions.expect_equal(1, core.visible_instance_count, "evolved projectile adds a white core")
	assertions.expect_equal(12, (inner.mesh as TorusMesh).ring_segments, "inner evolved outline uses twelve segments")
	assertions.expect_equal(18, (outer.mesh as TorusMesh).ring_segments, "outer evolved outline increases to eighteen segments")
	var core_material: StandardMaterial3D = core.mesh.material as StandardMaterial3D
	assertions.expect_equal(Color.WHITE, core_material.albedo_color, "evolved core is explicitly white")

	snapshot.projectile_visual_custom_data = PackedColorArray([Color(0.0, 0.0, 0.0, 0.0)])
	arena.present_snapshot(snapshot, 0.0)
	assertions.expect_equal(0, inner.visible_instance_count, "ordinary projectile has no evolved inner outline")
	assertions.expect_equal(0, outer.visible_instance_count, "ordinary projectile has no evolved outer outline")
	assertions.expect_equal(0, core.visible_instance_count, "ordinary projectile has no evolved white core")

	var hud: CombatHud = arena.get_node("%CombatHUD") as CombatHud
	hud.update_from_values({
		"weapons": [{"display_name": "進化武器", "level": 8, "evolved": true}],
	})
	var hud_state: Dictionary = hud.debug_state()
	var weapon_labels: PackedStringArray = hud_state["weapons"]
	assertions.expect_true(
		weapon_labels[0].ends_with("\nEVO"),
		"compact HUD uses the exact EVO marker for evolved weapons",
	)
	var vfx_instances: MultiMeshInstance3D = arena.get_node("%VfxInstances") as MultiMeshInstance3D
	var vfx_material: ShaderMaterial = vfx_instances.multimesh.mesh.material as ShaderMaterial
	assertions.expect_true(
		vfx_material.shader.code.contains("segment_count = effect_kind < 1.5 ? 12.0 : 18.0"),
		"evolved instant fields add twelve/eighteen-segment outlines",
	)
	assertions.expect_true(
		vfx_material.shader.code.contains("max(base_band, evo_outline * segments)"),
		"evolved instant fields keep a transparent gap between both radial outlines",
	)
	assertions.expect_true(
		vfx_material.shader.code.contains("mix(1.0, 0.25, reduce_flashes)"),
		"evolved instant white cores respect the Reduce Flashes cap",
	)
	var catalog := DefinitionCatalog.new()
	assertions.expect_true(catalog.load_and_validate(), "evolved instant VFX fixture loads content")
	if catalog.is_valid:
		var state: RunState = RunStateFactory.create(9915, catalog)
		var simulation := CombatSimulation.new()
		simulation.initialize(state, catalog)
		simulation._emit_attack_vfx({
			"generated": true,
			"weapon_id": &"vital_resonance",
			"origin": Vector2.ZERO,
			"direction": Vector2.RIGHT,
			"range_m": 4.4,
		}, 1)
		var wave_index: int = simulation.vfx_pool.active_indices_snapshot()[0]
		var evolved_wave: VfxState = simulation.vfx_pool.slots[wave_index]
		assertions.expect_true(evolved_wave.evolved, "evolved resonance carries the non-color visual flag")
		assertions.expect_equal(VfxState.EffectKind.ENERGY_WAVE, evolved_wave.effect_kind, "evolved resonance remains a cyan fan")
		simulation.vfx_pool.clear()
		simulation._emit_attack_vfx({
			"generated": true,
			"weapon_id": &"absorption_field",
			"origin": Vector2.ZERO,
			"direction": Vector2.RIGHT,
			"range_m": 4.4,
		}, 2)
		var aura_index: int = simulation.vfx_pool.active_indices_snapshot()[0]
		var evolved_aura: VfxState = simulation.vfx_pool.slots[aura_index]
		assertions.expect_true(evolved_aura.evolved, "evolved aura carries the non-color visual flag")
		assertions.expect_equal(VfxState.EffectKind.AURA_PULSE, evolved_aura.effect_kind, "evolved aura uses the segmented indigo field")

	viewport.remove_child(arena)
	arena.free()
	tree.root.remove_child(viewport)
	viewport.free()
	await tree.process_frame


func _test_terminal_hold_ticks(assertions: Variant) -> void:
	assertions.expect_equal(
		48,
		GAME_APP_SCRIPT.terminal_hold_ticks_for_phase(GameTypes.RunPhase.RESULT),
		"boss defeat hold is exactly forty-eight physics ticks",
	)
	assertions.expect_equal(
		27,
		GAME_APP_SCRIPT.terminal_hold_ticks_for_phase(GameTypes.RunPhase.FAILED),
		"player defeat hold is exactly twenty-seven physics ticks",
	)
	var boss_remaining: int = GAME_APP_SCRIPT.terminal_hold_ticks_for_phase(
		GameTypes.RunPhase.RESULT
	)
	for physics_tick: int in range(47):
		boss_remaining = GAME_APP_SCRIPT.terminal_hold_ticks_after_physics_tick(
			boss_remaining
		)
	assertions.expect_equal(1, boss_remaining, "boss presentation remains held after tick forty-seven")
	boss_remaining = GAME_APP_SCRIPT.terminal_hold_ticks_after_physics_tick(boss_remaining)
	assertions.expect_equal(0, boss_remaining, "boss presentation releases on tick forty-eight")
	var player_remaining: int = GAME_APP_SCRIPT.terminal_hold_ticks_for_phase(
		GameTypes.RunPhase.FAILED
	)
	for physics_tick: int in range(26):
		player_remaining = GAME_APP_SCRIPT.terminal_hold_ticks_after_physics_tick(
			player_remaining
		)
	assertions.expect_equal(1, player_remaining, "player presentation remains held after tick twenty-six")
	player_remaining = GAME_APP_SCRIPT.terminal_hold_ticks_after_physics_tick(player_remaining)
	assertions.expect_equal(0, player_remaining, "player presentation releases on tick twenty-seven")


func _test_kill_chain_snapshot_authority(assertions: Variant, tree: SceneTree) -> void:
	var arena: ArenaPresenter = ARENA_SCENE.instantiate() as ArenaPresenter
	assertions.expect_true(arena != null, "arena instantiates for kill-chain HUD regression")
	if arena == null:
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	tree.root.add_child(viewport)
	viewport.add_child(arena)
	await tree.process_frame
	await tree.process_frame
	var hud: CombatHud = arena.get_node("%CombatHUD") as CombatHud
	assertions.expect_true(hud != null, "combat HUD exists for kill-chain regression")
	if hud != null:
		hud.update_from_values({
			"combat_tick": 600,
			"total_kills": 30,
			"kill_chain_count": 10,
			"kill_chain_remaining_ticks": 30,
		})
		var snapshot_state: Dictionary = hud.debug_state()
		assertions.expect_equal("CHAIN ×10", snapshot_state["kill_chain"], "snapshot establishes the authoritative chain count")
		assertions.expect_float(0.5, hud._kill_chain_remaining, "snapshot establishes its exact remaining display time")
		var kill_event := CombatPresentationEvent.new(
			CombatPresentationEvent.Kind.ENEMY_KILLED,
			&"enemy_kill",
			Vector2.ZERO,
			CombatSnapshot.EnemyVisualKind.PURSUER,
			CombatSnapshot.ProjectileVisualKind.HOMING_CORE,
			&"homing_core",
			4,
			1.0,
			CombatPresentationEvent.Priority.NORMAL,
			600,
		)
		hud.present_event(kill_event)
		var after_kill_event: Dictionary = hud.debug_state()
		assertions.expect_equal("CHAIN ×10", after_kill_event["kill_chain"], "same-tick batched kill feedback does not count kills twice")
		assertions.expect_equal(10, hud._kill_chain_count, "kill feedback leaves the snapshot chain count untouched")
		assertions.expect_float(0.5, hud._kill_chain_remaining, "ordinary kill feedback leaves snapshot chain timing untouched")
		var milestone_event := CombatPresentationEvent.new(
			CombatPresentationEvent.Kind.CHAIN_MILESTONE,
			&"chain_milestone",
			Vector2.ZERO,
			CombatSnapshot.EnemyVisualKind.PURSUER,
			CombatSnapshot.ProjectileVisualKind.HOMING_CORE,
			&"homing_core",
			10,
			1.0,
			CombatPresentationEvent.Priority.IMPORTANT,
			600,
		)
		hud.present_event(milestone_event)
		var after_milestone: Dictionary = hud.debug_state()
		assertions.expect_equal("CHAIN ×10", after_milestone["kill_chain"], "milestone accent preserves the authoritative count")
		assertions.expect_equal(10, hud._kill_chain_count, "milestone event does not drift the displayed count")
		assertions.expect_float(CombatHud.KILL_CHAIN_SECONDS, hud._kill_chain_remaining, "milestone accent refreshes only the intended display window")
	viewport.remove_child(arena)
	arena.free()
	tree.root.remove_child(viewport)
	viewport.free()
	await tree.process_frame
