extends RefCounted


const ARENA_SCENE: PackedScene = preload("res://scenes/gameplay/arena_combat.tscn")


func test_audio_priority_preserves_important_voices(assertions: Variant, _context: Dictionary) -> void:
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


func test_audio_reserved_groups_and_twelve_cue_admission_cap(assertions: Variant, _context: Dictionary) -> void:
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


func test_kill_chain_snapshot_remains_authoritative_across_events(assertions: Variant, context: Dictionary) -> void:
	var tree: SceneTree = context["tree"]
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
		"weapon_slot_count": 5,
		"passive_slot_count": 5,
			"combat_tick": 600,
			"total_kills": 30,
			"kill_chain_count": 10,
			"kill_chain_remaining_ticks": 30,
		})
		var snapshot_state: Dictionary = hud.debug_state()
		assertions.expect_equal(10, hud._kill_chain_count, "snapshot establishes the authoritative chain count")
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
		assertions.expect_equal(snapshot_state["kill_chain"], after_kill_event["kill_chain"], "same-tick batched kill feedback does not count kills twice")
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
		assertions.expect_equal(snapshot_state["kill_chain"], after_milestone["kill_chain"], "milestone accent preserves the authoritative count")
		assertions.expect_equal(10, hud._kill_chain_count, "milestone event does not drift the displayed count")
		assertions.expect_float(CombatHud.KILL_CHAIN_SECONDS, hud._kill_chain_remaining, "milestone accent refreshes only the intended display window")
	viewport.remove_child(arena)
	arena.free()
	tree.root.remove_child(viewport)
	viewport.free()
	await tree.process_frame
