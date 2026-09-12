class_name CombatSimulation
extends RefCounted


const FIXED_DELTA_SECONDS: float = 1.0 / 60.0
const ORIGIN_STEP_METERS: int = 1024
const VFX_HEIGHT_M: float = 0.03
const DEATH_VFX_LIFETIME: float = 0.22
const HIT_GLOW_TICKS: int = 6
const MAX_PRESENTATION_EVENTS_PER_TICK: int = 64
const PRESENTATION_IMPORTANT_RESERVE: int = 32
const PERFORMANCE_PROFILE_NAME: StringName = &"full_hd_500_2000"
const PERFORMANCE_DEFAULT_ENEMY_COUNT: int = 500
const PERFORMANCE_DEFAULT_PROJECTILE_COUNT: int = 1_200
const PERFORMANCE_DEFAULT_VFX_COUNT: int = 800
const PERFORMANCE_DEFAULT_XP_COUNT: int = 1_024
const PERFORMANCE_DEFAULT_WEAPON_COUNT: int = 5
const PERFORMANCE_RECYCLE_INTERVAL_TICKS: int = 30
const PERFORMANCE_FIXTURE_HP: float = 1_000_000_000.0
const PERFORMANCE_PROJECTILE_SPEED: float = 7.0
const PERFORMANCE_PROJECTILE_DISTANCE: float = 10_000.0
const PERFORMANCE_FIXTURE_LIFETIME_SECONDS: float = 3_600.0

var world: RefCounted = CombatNative.create_world()
var envelope: CombatEnvelope = null

var state: RunState = null
var catalog: DefinitionCatalog = null
var player_position: Vector2 = Vector2.ZERO
var world_origin: Vector2i = Vector2i.ZERO
var last_player_displacement: Vector2 = Vector2.ZERO
var view: ArenaView = ArenaView.new()
var enemy_system: EnemySystem = EnemySystem.new()
var projectile_pool: ProjectilePool = ProjectilePool.new()
var vfx_pool: VfxPool = VfxPool.new()
var xp_pickup_pool: XpPickupPool = XpPickupPool.new()
var arena_object_system: ArenaObjectSystem = ArenaObjectSystem.new()
var event_router: CombatEventRouter = CombatEventRouter.new()
var weapon_system: WeaponSystem = WeaponSystem.new()
var weapon_effects: Array[WeaponEffectState] = []
var _weapon_visuals: Dictionary[StringName, Vector2i] = {}

var freeze_all_updates: bool = false

var _manifest: SurvivalContentManifest = null
var _pending_step_events: Array[StringName] = []
var _pending_presentation_events: Array[CombatPresentationEvent] = []
var _step_events: Array[StringName] = []
var _presentation_events: Array[CombatPresentationEvent] = []
# Headless balance runs use combat ticks as the deterministic audio clock. The
# live SurvivalFeedback path separately records wall-clock/voice admission.
var _audio_cue_admission: AudioCueAdmission = AudioCueAdmission.new()
var _hit_feedback_by_source: Dictionary[StringName, Dictionary] = {}
var _kill_feedback_by_key: Dictionary[String, Dictionary] = {}
var _player_hit_this_tick: bool = false
var _absorption_started_tick: int = -1
var _absorption_position: Vector2 = Vector2.ZERO
var _absorption_radius: float = 0.0
var _absorption_enemy_count: int = 0
var _absorption_swarm_count: int = 0
var _absorption_projectile_count: int = 0
var _performance_combat_usec: int = 0
var _performance_combat_max_usec: int = 0
var _performance_snapshot_usec: int = 0
var _performance_snapshot_max_usec: int = 0
var _performance_snapshot_count: int = 0
var _performance_fixture_active: bool = false
var _performance_enemy_target: int = 0
var _performance_projectile_target: int = 0
var _performance_vfx_target: int = 0
var _performance_xp_target: int = 0
var _performance_workload_ticks: int = 0
var _performance_grid_updates: int = 0
var _performance_projectile_collision_resolutions: int = 0
var _performance_weapon_attacks: int = 0
var _performance_enemy_recycles: int = 0
var _performance_enemy_motion_distance: float = 0.0
var _performance_projectile_motion_distance: float = 0.0
var _performance_enemy_serial: int = 0
var _performance_projectile_serial: int = 0
var _performance_projectile_positions := PackedVector2Array()
var _performance_projectile_directions := PackedVector2Array()
var _performance_projectile_template: Dictionary = {}
var _performance_vfx_serial: int = 0
var _performance_xp_serial: int = 0


func initialize(p_state: RunState, p_catalog: DefinitionCatalog) -> void:
	state = p_state
	catalog = p_catalog
	_manifest = catalog.manifest()
	envelope = catalog.envelope
	player_position = Vector2.ZERO
	world_origin = Vector2i.ZERO
	last_player_displacement = Vector2.ZERO
	view.reset(player_position)
	freeze_all_updates = false
	world = CombatNative.create_world()
	_configure_native_visuals()
	projectile_pool.configure(_manifest.combat.projectile_pool_capacity, world)
	projectile_pool.clear()
	vfx_pool.clear()
	weapon_effects.clear()
	xp_pickup_pool.configure(_manifest.progression, world)
	xp_pickup_pool.clear()
	event_router = CombatEventRouter.new()
	enemy_system = EnemySystem.new()
	enemy_system.initialize(state, catalog, view, world)
	weapon_system = WeaponSystem.new()
	weapon_system.initialize(state, catalog, projectile_pool, event_router)
	arena_object_system = ArenaObjectSystem.new()
	arena_object_system.initialize(state, catalog, view, world)
	_pending_step_events.clear()
	_pending_presentation_events.clear()
	_step_events.clear()
	_presentation_events.clear()
	_audio_cue_admission.reset()
	_hit_feedback_by_source.clear()
	_kill_feedback_by_key.clear()
	_player_hit_this_tick = false
	_absorption_started_tick = -1
	_absorption_enemy_count = 0
	_absorption_swarm_count = 0
	_absorption_projectile_count = 0
	_reset_performance_fixture_state()
	_refresh_derived_player_stats()


func step(move_input: Vector2, _delta: float = FIXED_DELTA_SECONDS) -> CombatSnapshot:
	advance_tick(move_input)
	var snapshot: CombatSnapshot = build_snapshot()
	var events: CombatSnapshot = take_events()
	snapshot.presentation_events = events.presentation_events
	snapshot.hud_values["events"] = events.hud_values["events"]
	return snapshot


func advance_tick(move_input: Vector2) -> bool:
	var measured_start: int = Time.get_ticks_usec() if _performance_fixture_active else 0
	last_player_displacement = Vector2.ZERO
	_archive_events()
	_hit_feedback_by_source.clear()
	_kill_feedback_by_key.clear()
	_player_hit_this_tick = false
	if state == null or catalog == null or state.phase != GameTypes.RunPhase.COMBAT:
		return false
	if freeze_all_updates and not _performance_fixture_active:
		return false
	state.combat_tick += 1
	var current_tick: int = state.combat_tick
	world.begin_weapon_visual_tick(current_tick,
		VfxPool.MAX_PRODUCTION_REQUESTS_PER_TICK - VfxPool.IMPORTANT_RESERVED_SLOTS,
		WeaponVisualStyle.TRAIL_INTERVAL_TICKS)
	var effect_index: int = 0
	while effect_index < weapon_effects.size():
		var effect: WeaponEffectState = weapon_effects[effect_index]
		if current_tick >= effect.born_tick + effect.duration_ticks:
			weapon_effects.remove_at(effect_index)
		else:
			effect_index += 1
	# Boss entry is a tick-boundary operation. Removing the old combatants before
	# snapshots are taken guarantees they cannot move, attack, or collide on the boundary.
	enemy_system.encounters.advance(current_tick, enemy_system.enemy_store)
	_move_player(move_input)
	_rebase_if_needed()
	view.advance(player_position, FIXED_DELTA_SECONDS)
	_begin_boss_transition_if_due(current_tick)
	var enemy_snapshot: Array[int] = enemy_system.snapshot_ids()
	var projectile_snapshot: PackedInt64Array = projectile_pool.snapshot_active()
	var tracked_enemy_id: int = -1
	var tracked_enemy_position: Vector2 = Vector2.ZERO
	var tracked_projectile_entry := PackedInt64Array([-1, -1])
	var tracked_projectile_position: Vector2 = Vector2.ZERO
	if _performance_fixture_active and not enemy_snapshot.is_empty():
		tracked_enemy_id = enemy_snapshot[0]
		var tracked_enemy: EnemyEntity = enemy_system.enemy_store.get_by_id(
			tracked_enemy_id
		)
		if tracked_enemy != null:
			tracked_enemy_position = tracked_enemy.position
	if _performance_fixture_active and not projectile_snapshot.is_empty():
		tracked_projectile_entry = projectile_snapshot.slice(0, 2)
		var tracked_projectile: ProjectileState = projectile_pool.resolve_snapshot_entry(
			tracked_projectile_entry
		)
		if tracked_projectile != null:
			tracked_projectile_position = tracked_projectile.position

	# 1. Player movement and pickups.
	_collect_arena_pickups(current_tick)
	var collected_xp: int = xp_pickup_pool.advance_and_collect(
		player_position,
		FIXED_DELTA_SECONDS,
		current_tick,
	)
	if collected_xp > 0:
		ProgressionService.add_xp(state, collected_xp, catalog)
		_step_events.append(&"xp_pickup")
		_queue_presentation_event(_make_presentation_event(
			CombatPresentationEvent.Kind.XP_PICKUP,
			&"xp_pickup",
			player_position,
			CombatPresentationEvent.Priority.AMBIENT,
			collected_xp,
		))
	arena_object_system.advance(current_tick, player_position)

	# 2. Enemy update and time-driven spawns.
	var boss_phase_before: int = state.boss_phase
	var special_enemy_snapshot: Array[int] = enemy_system.advance_snapshot(enemy_snapshot, player_position, current_tick)
	if state.boss_phase != boss_phase_before and state.boss_phase > 0:
		var phase_boss: EnemyEntity = enemy_system.boss_entity()
		_queue_presentation_event(_make_presentation_event(
			CombatPresentationEvent.Kind.BOSS_PHASE_CHANGED,
			&"boss_phase",
			phase_boss.position if phase_boss != null else Vector2.ZERO,
			CombatPresentationEvent.Priority.IMPORTANT,
			state.boss_phase,
		))
	if _performance_fixture_active:
		_performance_grid_updates += 1
		var moved_enemy: EnemyEntity = enemy_system.enemy_store.get_by_id(
			tracked_enemy_id
		)
		if moved_enemy != null:
			_performance_enemy_motion_distance += tracked_enemy_position.distance_to(
				moved_enemy.position
			)
	enemy_system.accrue_spawn_credit()
	var scheduled_spawns: Array[EnemyEntity] = enemy_system.resolve_stage_events(
		player_position,
		current_tick,
	)
	for spawned: EnemyEntity in scheduled_spawns:
		if spawned.enemy_type == GameTypes.EnemyType.BOSS:
			_step_events.append(&"boss_spawn")
		if spawned.enemy_type in [GameTypes.EnemyType.ELITE, GameTypes.EnemyType.BOSS]:
			_queue_presentation_event(_make_presentation_event(
				CombatPresentationEvent.Kind.IMPORTANT_SPAWN,
				&"boss_spawn" if spawned.enemy_type == GameTypes.EnemyType.BOSS else &"important_spawn",
				spawned.position,
				CombatPresentationEvent.Priority.IMPORTANT,
				1,
				spawned.enemy_type,
			))
	enemy_system.resolve_normal_spawns(player_position, current_tick)

	# 3. Allied movement, weapon generation, and damage.
	weapon_system.move_snapshot_projectiles(
		projectile_snapshot,
		enemy_system.enemy_store,
		player_position,
		current_tick,
		state.is_stop_active(),
	)
	if _performance_fixture_active:
		var moved_projectile: ProjectileState = projectile_pool.resolve_snapshot_entry(
			tracked_projectile_entry
		)
		if moved_projectile != null:
			_performance_projectile_motion_distance += (
				tracked_projectile_position.distance_to(moved_projectile.position)
			)
	vfx_pool.advance(FIXED_DELTA_SECONDS, current_tick)
	_damage_nodes_from_projectiles(projectile_snapshot, current_tick)
	var projectile_result: Dictionary = world.resolve_projectiles(projectile_snapshot, true, true)
	arena_object_system.resolve_native_destructions(projectile_result.destroyed_nodes, current_tick)
	_consume_native_damage()
	if _performance_fixture_active:
		_performance_projectile_collision_resolutions += (projectile_snapshot.size() >> 1)
	weapon_system.update_move_direction(move_input)
	var attacks: Array[Dictionary] = weapon_system.advance_and_fire(
		player_position,
		enemy_system.enemy_store,
		enemy_system.uniform_grid,
		current_tick,
	)
	if _performance_fixture_active:
		_performance_weapon_attacks += attacks.size()
	for attack: Dictionary in attacks:
		_emit_attack_visuals(attack, current_tick)
		_damage_nodes_from_attack(attack, current_tick)
		_apply_resolution_hits(attack)
	_consume_native_damage()
	_consume_native_weapon_visuals(current_tick)

	# 4. Enemy damage and special actions. Lethal allied hits remain pending so their
	# current contact still participates before the death stage.
	# The grid was rebuilt from the tick-start enemies, before this tick's spawns.
	# Keep their ID order while excluding cells that cannot touch the player.
	var contact_snapshot: Array[int] = enemy_system.uniform_grid.query_circle_candidates(
		player_position, envelope.player_body_radius, catalog.maximum_enemy_body_radius + 1.0,
	)
	contact_snapshot.sort()
	var player_damage_candidates: Array[Dictionary] = enemy_system.resolve_contact_damage_candidates(
		contact_snapshot,
		player_position,
		current_tick,
	)
	player_damage_candidates.append_array(world.hostile_projectile_hits(projectile_snapshot))
	_apply_player_damage_candidates(player_damage_candidates)
	var boss_before_special: EnemyEntity = enemy_system.boss_entity()
	var boss_was_charging: bool = (
		boss_before_special != null and boss_before_special.boss_charge_active
	)
	var boss_alternate_before: bool = (
		boss_before_special.barrage_alternate if boss_before_special != null else false
	)
	var boss_charge_spoke_count_before: int = (
		boss_before_special.boss_charge_spoke_count if boss_before_special != null else 0
	)
	enemy_system.resolve_ready_enemy_special_actions(
		special_enemy_snapshot,
		player_position,
		current_tick,
		projectile_pool,
	)
	_record_boss_action_feedback(
		boss_was_charging,
		boss_alternate_before,
		boss_charge_spoke_count_before,
	)

	# 5. Death drops, passive recovery, and terminal/modal priority.
	_process_pending_deaths(current_tick)
	# Resolve actual kills first, so a member killed with its owner still drops XP.
	enemy_system.encounters.retire_finished_groups(current_tick, enemy_system.enemy_store)
	_flush_transient_feedback()
	_apply_passive_recovery()
	var victory: bool = state.boss_defeated
	var player_dead: bool = state.current_hp <= 0.0
	if player_dead and not victory:
		_queue_presentation_event(_make_presentation_event(
			CombatPresentationEvent.Kind.PLAYER_DEFEATED,
			&"player_defeated",
			player_position,
			CombatPresentationEvent.Priority.TERMINAL,
		))
	RunStateMachine.resolve_terminal(state, player_dead, victory)
	if state.phase in [GameTypes.RunPhase.RESULT, GameTypes.RunPhase.FAILED]:
		enemy_system.stage_events.finish()
		enemy_system.encounters.clear(enemy_system.enemy_store)
	if state.phase == GameTypes.RunPhase.COMBAT:
		_resolve_modal_priority()
	_record_audio_cue_metrics()
	if _performance_fixture_active and state.phase == GameTypes.RunPhase.COMBAT:
		_performance_workload_ticks += 1
		_maintain_performance_fixture(current_tick)
	_record_visible_enemy_sample(current_tick)
	if _performance_fixture_active:
		var elapsed: int = Time.get_ticks_usec() - measured_start
		_performance_combat_usec += elapsed
		_performance_combat_max_usec = maxi(_performance_combat_max_usec, elapsed)
	return true


func apply_upgrade_choice(choice_index: int) -> bool:
	if state == null or state.phase != GameTypes.RunPhase.LEVEL_UP:
		return false
	var offer: LevelOffer = state.active_level_offer
	if offer == null:
		return false
	var result: Dictionary = ProgressionService.apply_offer(
		state,
		catalog,
		offer.serial,
		choice_index,
	)
	if not bool(result.get(&"success", false)):
		return false
	_record_audio_cue_id(&"level_up")
	_refresh_derived_player_stats()
	_continue_after_modal(true)
	return true


func skip_chest_animation() -> bool:
	if state == null or state.phase != GameTypes.RunPhase.CHEST_REWARD:
		return false
	var outcome: ChestOutcome = state.active_chest_outcome
	if outcome == null:
		return false
	var result: Dictionary = ChestRewardService.apply_outcome(
		state,
		catalog,
		outcome.serial,
	)
	if not bool(result.get(&"success", false)):
		return false
	_record_audio_cue_id(&"chest_open")
	if outcome.kind == GameTypes.ChestOutcomeKind.EVOLUTION:
		_record_audio_cue_id(&"evolution")
	_refresh_derived_player_stats()
	_continue_after_modal(false)
	return true


func complete_chest_reward() -> bool:
	return skip_chest_animation()


func grant_level_up_resume_invulnerability_ticks(ticks: int) -> void:
	if ticks <= 0:
		return
	# The grant occurs between ticks. With an exclusive deadline, T+1 through T+ticks
	# require a deadline of T+ticks+1 to protect exactly `ticks` combat updates.
	RunStateMachine.grant_level_up_resume_invulnerability(state, ticks + 1)


func configure_accessibility(reduce_motion: bool, reduce_flashes: bool) -> void:
	vfx_pool.reduce_motion = reduce_motion
	vfx_pool.reduce_flashes = reduce_flashes


func visible_combat_metrics() -> Dictionary:
	var sample_count: float = float(maxi(1, state.visible_enemy_sample_count))
	return {
		"weapon_hits": state.weapon_hit_count,
		"weapon_kills": state.weapon_kill_count,
		"visible_weapon_hits": state.visible_weapon_hit_count,
		"visible_weapon_kills": state.visible_weapon_kill_count,
		"offscreen_weapon_hits": state.offscreen_weapon_hit_count,
		"offscreen_weapon_kills": state.offscreen_weapon_kill_count,
		"max_hit_center_distance": state.max_weapon_hit_center_distance,
		"max_kill_center_distance": state.max_weapon_kill_center_distance,
		"max_effect_outer_distance": state.max_weapon_effect_outer_distance,
		"peak_visible_enemies": state.peak_visible_enemy_count,
		"mean_visible_enemies": float(state.visible_enemy_count_total) / sample_count,
		"peak_engaged_enemies": state.peak_engaged_enemy_count,
		"mean_engaged_enemies": float(state.engaged_enemy_count_total) / sample_count,
		"peak_materializing_enemies": state.peak_materializing_enemy_count,
		"mean_materializing_enemies": (
			float(state.materializing_enemy_count_total) / sample_count
		),
		"absorbed_normal_count": state.absorbed_normal_count,
		"normal_far_despawns": state.normal_far_despawn_count,
		"absorbed_enemy_projectile_count": state.absorbed_enemy_projectile_count,
		"swarm_event_attempts": state.swarm_event_attempt_count,
		"swarm_event_roll_successes": state.swarm_event_roll_success_count,
		"swarm_event_spawn_failures": state.swarm_event_spawn_failure_count,
		"swarm_event_skipped_busy": state.swarm_event_skipped_busy_count,
		"swarm_event_groups": state.swarm_event_group_count,
		"swarm_event_generated": state.swarm_event_generated_count,
		"swarm_event_kills": state.swarm_event_kill_count,
		"swarm_event_exits": state.swarm_event_exit_count,
		"swarm_event_absorbed": state.swarm_event_absorbed_count,
		"swarm_event_xp": state.swarm_event_xp,
		"vfx_admitted": vfx_pool.admitted_count,
		"vfx_suppressed": vfx_pool.generic_drop_count,
		"important_vfx_dropped": vfx_pool.important_drop_count,
		"audio_admitted": _audio_cue_admission.admitted_count,
		"audio_suppressed": _audio_cue_admission.suppressed_count,
		"feedback_emitted": state.feedback_event_emitted_count,
		"feedback_suppressed": state.feedback_event_suppressed_count,
	}


func build_snapshot() -> CombatSnapshot:
	var measured_start: int = Time.get_ticks_usec() if _performance_fixture_active else 0
	if state == null or catalog == null:
		return CombatSnapshot.new()
	var orbital_runtime: RunWeapon = state.weapon_for_lineage(&"orbital_array")
	var visuals: Dictionary = world.render_snapshot(state.combat_tick, vfx_pool.reduce_motion, vfx_pool.reduce_flashes,
		weapon_system.orbital_transforms(player_position, state.combat_tick), orbital_runtime != null and orbital_runtime.evolved)
	var enemy_transforms: Array[Transform3D] = []
	enemy_transforms.assign(visuals.enemy_transforms)
	var projectile_transforms: Array[Transform3D] = []
	projectile_transforms.assign(visuals.projectile_transforms)
	var xp_transforms: Array[Transform3D] = []
	xp_transforms.assign(visuals.xp_transforms)
	var vfx_transforms: Array[Transform3D] = []
	var vfx_colors: Array[Color] = []
	var vfx_custom_data: Array[Color] = []
	var weapon_transforms: Array[Transform3D] = []
	var weapon_colors: Array[Color] = []
	var weapon_custom: Array[Color] = []
	for effect: WeaponEffectState in weapon_effects:
		weapon_transforms.append(effect.transform())
		weapon_colors.append(WeaponVisualStyle.color_for(effect.visual_kind))
		weapon_custom.append(effect.custom_data(state.combat_tick))
	for pool_index: int in vfx_pool.active_indices_snapshot():
		var vfx: VfxState = vfx_pool.slots[pool_index]
		if vfx.weapon_visual_kind > 0:
			var visual_transform: Transform3D = vfx.current_transform(vfx.weapon_height_m)
			visual_transform.basis.x *= 0.25
			visual_transform.basis.z = visual_transform.basis.z.normalized() * vfx.weapon_trail_length_m * 0.5
			weapon_transforms.append(visual_transform)
			weapon_colors.append(vfx.color)
			weapon_custom.append(Color(vfx.normalized_progress(), float(vfx.weapon_visual_kind), -2.0, 1.0 if vfx.evolved else 0.0))
			continue
		vfx_transforms.append(vfx.current_transform(VFX_HEIGHT_M))
		vfx_colors.append(vfx.color)
		vfx_custom_data.append(vfx.shader_custom_data(
			vfx_pool.reduce_motion,
			vfx_pool.reduce_flashes,
		))
	var snapshot := CombatSnapshot.new(
		player_position,
		enemy_transforms,
		projectile_transforms,
		vfx_transforms,
		_build_hud_values(),
		arena_object_system.chest_transforms(),
		vfx_colors,
		vfx_custom_data,
		xp_transforms,
		arena_object_system.powerup_transforms(),
		arena_object_system.node_transforms(),
		visuals.enemy_kinds,
		visuals.enemy_custom,
		visuals.projectile_kinds,
		visuals.projectile_custom,
	)
	snapshot.native_visuals = visuals
	snapshot.native_visuals["vfx_buffer"] = world.pack_visuals(vfx_transforms, vfx_colors, vfx_custom_data)
	snapshot.weapon_effect_transforms = weapon_transforms
	snapshot.weapon_effect_colors = weapon_colors
	snapshot.weapon_effect_custom_data = weapon_custom
	snapshot.active_vfx_count += weapon_transforms.size()
	snapshot.native_visuals["weapon_effect_buffer"] = world.pack_visuals(weapon_transforms, weapon_colors, weapon_custom)
	snapshot.hud_values["events"] = []
	_apply_snapshot_markers(snapshot)
	snapshot.world_origin = world_origin
	snapshot.chest_guidance = arena_object_system.chest_guidance(player_position)
	snapshot.normal_chest_transforms = arena_object_system.chest_transforms(GameTypes.ChestKind.NORMAL)
	snapshot.evolution_chest_transforms = arena_object_system.chest_transforms(GameTypes.ChestKind.EVOLUTION_CAPABLE)
	var warning: SwarmWarningState = enemy_system.stage_events.swarm_warning
	if warning != null:
		var swarm: SwarmEventDefinition = _manifest.swarm_event
		snapshot.swarm_warning_active = true
		snapshot.swarm_warning_anchor = warning.anchor
		snapshot.swarm_warning_direction = warning.direction
		snapshot.swarm_warning_progress = warning.progress(state.combat_tick)
		snapshot.swarm_warning_width = (
			(float(swarm.lateral_count - 1) + 0.5) * swarm.lateral_pitch
			+ 2.0 * swarm.unit_definition.body_radius
		)
		snapshot.swarm_warning_length = 2.0 * (
			warning.spawn_distance
			+ float(swarm.depth_count - 1) * swarm.depth_pitch
			+ swarm.unit_definition.body_radius
		)
	if _performance_fixture_active:
		var elapsed: int = Time.get_ticks_usec() - measured_start
		_performance_snapshot_usec += elapsed
		_performance_snapshot_max_usec = maxi(_performance_snapshot_max_usec, elapsed)
		_performance_snapshot_count += 1
	return snapshot


func spawn_fixture_enemy(
	enemy_type: GameTypes.EnemyType,
	position: Vector2,
	born_tick: int = -1,
	apply_time_multiplier: bool = false,
	activate_immediately: bool = true,
) -> EnemyEntity:
	var definition: EnemyDefinition = catalog.enemy_for_type(enemy_type)
	if definition == null:
		return null
	var segment: EnemySegmentDefinition = catalog.segment_for_tick(state.combat_tick)
	var hp_multiplier: float = segment.hp_multiplier if apply_time_multiplier and segment != null else 1.0
	var damage_multiplier: float = segment.damage_multiplier if apply_time_multiplier and segment != null else 1.0
	if apply_time_multiplier and enemy_type == GameTypes.EnemyType.BOSS:
		hp_multiplier = _manifest.combat.boss_hp_multiplier
		damage_multiplier = _manifest.combat.boss_damage_multiplier
	elif apply_time_multiplier and enemy_type in EnemySystem.NORMAL_ENEMY_TYPES:
		damage_multiplier *= _manifest.combat.normal_enemy_damage_scale
	var resolved_born_tick: int = state.combat_tick - 1 if born_tick < 0 else born_tick
	var enemy: EnemyEntity = enemy_system.enemy_store.try_spawn(
		state,
		enemy_type,
		definition,
		position,
		hp_multiplier,
		damage_multiplier,
		resolved_born_tick,
		0 if activate_immediately else envelope.entry_ticks_for_enemy_type(enemy_type),
	)
	_rebuild_uniform_grid(state.combat_tick + 1)
	return enemy


func add_fixture_vfx(
	position: Vector2,
	scale_m: float,
	color: Color,
	lifetime: float = 3600.0,
) -> VfxState:
	return vfx_pool.acquire(position, scale_m, lifetime, color, state.combat_tick - 1)


func prepare_performance_fixture(
	enemy_count: int = PERFORMANCE_DEFAULT_ENEMY_COUNT,
	projectile_count: int = PERFORMANCE_DEFAULT_PROJECTILE_COUNT,
	vfx_count: int = PERFORMANCE_DEFAULT_VFX_COUNT,
	xp_count: int = PERFORMANCE_DEFAULT_XP_COUNT,
) -> bool:
	if state == null or enemy_count < 0 or projectile_count < 0 or vfx_count < 0 or vfx_count > VfxPool.CAPACITY or xp_count < 0:
		return false
	# Workload capacities belong to a private manifest, never the production Resources.
	var content := catalog.manifest().duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as SurvivalContentManifest
	content.combat.enemy_pool_capacity = maxi(content.combat.enemy_pool_capacity, enemy_count)
	content.combat.projectile_pool_capacity = maxi(content.combat.projectile_pool_capacity, projectile_count * 2)
	content.progression.xp_pool_capacity = maxi(content.progression.xp_pool_capacity, xp_count)
	var fixture_catalog := DefinitionCatalog.new()
	if not fixture_catalog.validate_manifest(content):
		return false
	initialize(state, fixture_catalog)
	_performance_enemy_target = enemy_count
	_performance_projectile_target = projectile_count
	_performance_vfx_target = vfx_count
	_performance_xp_target = xp_count
	enemy_system.enemy_store.clear()
	projectile_pool.clear()
	vfx_pool.clear()
	xp_pickup_pool.clear()
	vfx_pool.overflow_count = 0
	state.next_entity_id = 1
	state.next_swarm_group_id = 1
	state.phase = GameTypes.RunPhase.COMBAT
	state.current_hp = state.max_hp
	state.pending_level_ups = 0
	state.active_level_offer = null
	state.pending_chest_sources.clear()
	state.active_chest_outcome = null
	state.build_maxed = true
	state.boss_spawned = true
	enemy_system.stage_events.finish()
	state.boss_defeated = false
	state.boss_phase = 0
	state.boss_enrage_stacks = 0
	state.boss_hp = 0.0
	state.boss_max_hp = 0.0
	state.boss_spawn_tick = -1
	state.boss_defeat_tick = -1
	state.stop_until_tick = 0
	state.level_up_invulnerable_until_tick = 0
	state.spawn_credit = 0.0
	state.absorbed_normal_count = 0
	state.normal_far_despawn_count = 0
	state.absorbed_enemy_projectile_count = 0
	state.swarm_event_attempt_count = 0
	state.swarm_event_roll_success_count = 0
	state.swarm_event_spawn_failure_count = 0
	state.swarm_event_skipped_busy_count = 0
	enemy_system.stage_events.swarm_warning = null
	state.swarm_event_group_count = 0
	state.swarm_event_generated_count = 0
	state.swarm_event_kill_count = 0
	state.swarm_event_exit_count = 0
	state.swarm_event_absorbed_count = 0
	state.swarm_event_xp = 0
	state.kill_chain_count = 0
	state.kill_chain_last_tick = -1
	state.kill_chain_accent_milestone = 0
	state.weapon_hit_count = 0
	state.weapon_kill_count = 0
	state.visible_weapon_hit_count = 0
	state.visible_weapon_kill_count = 0
	state.offscreen_weapon_hit_count = 0
	state.offscreen_weapon_kill_count = 0
	state.max_weapon_hit_center_distance = 0.0
	state.max_weapon_kill_center_distance = 0.0
	state.max_weapon_effect_outer_distance = 0.0
	state.visible_enemy_sample_count = 0
	state.visible_enemy_count_total = 0
	state.engaged_enemy_count_total = 0
	state.materializing_enemy_count_total = 0
	state.peak_visible_enemy_count = 0
	state.peak_engaged_enemy_count = 0
	state.peak_materializing_enemy_count = 0
	state.feedback_event_emitted_count = 0
	state.feedback_event_suppressed_count = 0
	state.normal_kills_by_type.fill(0)
	state.normal_kills_by_segment.fill(0)
	state.normal_xp_by_segment.fill(0)
	state.normal_active_samples_by_segment.fill(0)
	state.normal_active_total_by_segment.fill(0)
	state.normal_engaged_total_by_segment.fill(0)
	state.elite_spawn_ticks.fill(-1)
	state.elite_kill_ticks.fill(-1)
	_audio_cue_admission.reset()
	state.weapon_damage_by_lineage.clear()
	state.recent_damage_samples.clear()
	for index: int in range(enemy_count):
		if not _spawn_performance_enemy(index, state.combat_tick - 1):
			return false
	_prepare_projectile_pattern()
	_normalize_performance_projectiles(state.combat_tick - 1)
	for index: int in range(vfx_count):
		if not _spawn_performance_vfx(index, state.combat_tick - 1):
			return false
	for index: int in range(xp_count):
		if not _spawn_performance_xp(index, state.combat_tick - 1):
			return false
	_performance_enemy_serial = enemy_count
	_performance_projectile_serial = projectile_count
	_performance_vfx_serial = vfx_count
	_performance_xp_serial = xp_count
	_ensure_performance_weapons()
	_rebuild_uniform_grid(state.combat_tick + 1)
	enemy_system.enemy_store.reset_reuse_count()
	projectile_pool.reset_reuse_count()
	vfx_pool.reset_reuse_count()
	vfx_pool.request_count = 0
	vfx_pool.admitted_count = 0
	vfx_pool.generic_drop_count = 0
	vfx_pool.important_drop_count = 0
	xp_pickup_pool.reset_reuse_count()
	_performance_fixture_active = true
	freeze_all_updates = true
	return _performance_counts_are_exact()


func performance_fixture_metrics() -> Dictionary:
	return {
		"profile_name": PERFORMANCE_PROFILE_NAME,
		"active_workload": _performance_fixture_active,
		"exact_counts": _performance_counts_are_exact(),
		"active_enemy": enemy_system.enemy_store.active_count(),
		"active_projectile": projectile_pool.active_count(),
		"active_vfx": vfx_pool.active_count(),
		"active_xp": xp_pickup_pool.active_count(),
		"active_weapon": state.weapons.size(),
		"enemy_pool_overflow": enemy_system.enemy_store.overflow_count,
		"projectile_pool_overflow": projectile_pool.overflow_count,
		"vfx_pool_overflow": vfx_pool.overflow_count,
		"xp_pool_overflow_merges": xp_pickup_pool.overflow_merge_count,
		"enemy_pool_reuse": enemy_system.enemy_store.reuse_count,
		"projectile_pool_reuse": projectile_pool.reuse_count,
		"vfx_pool_reuse": vfx_pool.reuse_count,
		"xp_pool_reuse": xp_pickup_pool.reuse_count,
		"pool_orphan_count": (
			enemy_system.enemy_store.orphan_count()
			+ projectile_pool.orphan_count()
			+ vfx_pool.orphan_count()
			+ xp_pickup_pool.orphan_count()
		),
		"workload_ticks": _performance_workload_ticks,
		"grid_updates": _performance_grid_updates,
		"projectile_collision_resolutions": (
			_performance_projectile_collision_resolutions
		),
		"weapon_attacks": _performance_weapon_attacks,
		"enemy_recycles": _performance_enemy_recycles,
		"enemy_motion_distance": _performance_enemy_motion_distance,
		"projectile_motion_distance": _performance_projectile_motion_distance,
	}


func performance_profile_contract() -> Dictionary:
	return {
		"profile_name": PERFORMANCE_PROFILE_NAME,
		"enemy_count": PERFORMANCE_DEFAULT_ENEMY_COUNT,
		"projectile_count": PERFORMANCE_DEFAULT_PROJECTILE_COUNT,
		"vfx_count": PERFORMANCE_DEFAULT_VFX_COUNT,
		"xp_count": PERFORMANCE_DEFAULT_XP_COUNT,
		"weapon_count": PERFORMANCE_DEFAULT_WEAPON_COUNT,
		"active_updates": true,
		"exact_count_lock": true,
	}


func _move_player(move_input: Vector2) -> void:
	var normalized_input: Vector2 = move_input
	if normalized_input.length_squared() > 1.0:
		normalized_input = normalized_input.normalized()
	var before: Vector2 = player_position
	player_position += normalized_input * _manifest.player.move_speed * FIXED_DELTA_SECONDS
	player_position = enemy_system.encounters.constrain_body(player_position, _manifest.player.body_radius)
	last_player_displacement = player_position - before


func set_viewport_size(size: Vector2i) -> void:
	if size.x > 0 and size.y > 0:
		view.viewport_size = size


func _rebase_if_needed() -> void:
	var steps := Vector2i(int(player_position.x / ORIGIN_STEP_METERS), int(player_position.y / ORIGIN_STEP_METERS))
	if steps == Vector2i.ZERO:
		return
	var displacement := Vector2(steps) * ORIGIN_STEP_METERS
	world_origin += steps
	player_position -= displacement
	view.shift_origin(displacement)
	enemy_system.shift_origin(displacement)
	arena_object_system.shift_origin(displacement)
	xp_pickup_pool.shift_origin(displacement)
	projectile_pool.shift_origin(displacement)
	for index: int in vfx_pool.active_indices_snapshot():
		vfx_pool.slots[index].position -= displacement
	for effect: WeaponEffectState in weapon_effects:
		effect.position -= displacement
	_absorption_position -= displacement
	for event: CombatPresentationEvent in _pending_presentation_events:
		event.position -= displacement


func _begin_boss_transition_if_due(current_tick: int) -> void:
	if not enemy_system.stage_events.prepare_tick(current_tick):
		return
	state.spawn_credit = 0.0
	_absorption_started_tick = current_tick
	_absorption_position = player_position
	_absorption_radius = view.ground_rect().size.length() * 0.5
	_absorption_enemy_count = 0
	_absorption_swarm_count = 0
	_absorption_projectile_count = 0
	var absorbed_normals: int = 0
	for entity_id: int in enemy_system.enemy_store.snapshot_ids_sorted():
		var enemy: EnemyEntity = enemy_system.enemy_store.get_by_id(entity_id)
		if enemy == null:
			continue
		var is_swarm_event: bool = enemy.is_swarm_event
		var is_normal: bool = enemy.enemy_type in EnemySystem.NORMAL_ENEMY_TYPES and not is_swarm_event and enemy.encounter_owner_id < 0
		if enemy_system.enemy_store.remove(entity_id):
			if is_normal:
				absorbed_normals += 1
			if is_swarm_event:
				_absorption_swarm_count += 1
			else:
				_absorption_enemy_count += 1
	for pool_index: int in projectile_pool.active_indices_snapshot():
		var projectile: ProjectileState = projectile_pool.slots[pool_index]
		if projectile.faction != ProjectileState.FACTION_ENEMY:
			continue
		if projectile_pool.release(pool_index, projectile.generation):
			_absorption_projectile_count += 1
	enemy_system.encounters.clear(enemy_system.enemy_store)
	state.absorbed_normal_count += absorbed_normals
	state.swarm_event_absorbed_count += _absorption_swarm_count
	state.absorbed_enemy_projectile_count += _absorption_projectile_count
	_rebuild_uniform_grid(current_tick)
	var absorbed_total: int = (
		_absorption_enemy_count
		+ _absorption_swarm_count
		+ _absorption_projectile_count
	)
	if absorbed_total <= 0:
		return
	_queue_presentation_event(_make_presentation_event(
		CombatPresentationEvent.Kind.ABSORPTION,
		&"absorption",
		_absorption_position,
		CombatPresentationEvent.Priority.IMPORTANT,
		absorbed_total,
	))
	vfx_pool.request(
		_absorption_position,
		_absorption_radius,
		float(envelope.boss_entry_ticks) / float(RunState.TICKS_PER_SECOND),
		Color(0.55, 0.08, 0.11, 0.62),
		current_tick,
		VfxPool.PRIORITY_IMPORTANT,
		VfxState.EffectKind.AURA_PULSE,
	)


func _record_visible_enemy_sample(current_tick: int) -> void:
	var counts: Array = world.visible_counts(player_position, current_tick, envelope.damage_center_radius, envelope.target_center_radius)
	state.record_visible_enemy_sample(int(counts[0]), int(counts[1]), int(counts[2]))
	if current_tick < catalog.boss_start_tick:
		state.record_enemy_segment_sample(catalog.segment_index_for_tick(current_tick), int(counts[3]), int(counts[4]))


func _combat_position_is_visible(position: Vector2) -> bool:
	# Camera projection tests establish that this shared ten-metre center envelope is
	# inside the supported viewports, including the maximum follow lag.
	return (
		position.distance_squared_to(player_position)
		<= envelope.damage_center_radius * envelope.damage_center_radius
	)


func _collect_arena_pickups(_current_tick: int) -> void:
	for pickup: ArenaPickup in arena_object_system.collect_at(player_position):
		match pickup.kind:
			ArenaPickup.Kind.CHEST:
				state.pending_chest_sources.append(pickup.source_serial)
				_step_events.append(&"chest_pickup")
			ArenaPickup.Kind.HEAL:
				NodeDropService.apply_drop(state, catalog, GameTypes.NodeDropType.HEAL)
			ArenaPickup.Kind.VACUUM:
				var vacuum_result: Dictionary = NodeDropService.apply_drop(
					state,
					catalog,
					GameTypes.NodeDropType.VACUUM,
				)
				if bool(vacuum_result.get(&"vacuum", false)):
					xp_pickup_pool.begin_vacuum()
			ArenaPickup.Kind.STOP:
				NodeDropService.apply_drop(state, catalog, GameTypes.NodeDropType.STOP)
				_step_events.append(&"stop_pickup")


func _apply_resolution_hits(result: Dictionary) -> void:
	if result.has("native_result"):
		arena_object_system.resolve_native_destructions(result.native_result.destroyed_nodes, state.combat_tick)
		return
	var records: Array[Dictionary] = []
	records.assign(result.get("hits", []))
	_apply_enemy_hit_records(records)


func _apply_enemy_hit_records(records: Array[Dictionary]) -> void:
	world.set_context(CombatNative.context(catalog, state, player_position, state.combat_tick))
	var requests: Array[Dictionary] = []
	for record: Dictionary in records:
		var event: CombatEvent = record.get("event") as CombatEvent
		if event != null:
			requests.append({"entity_id": record.get("entity_id", -1), "damage": event.damage_snapshot,
				"source_effect_id": event.source_effect_id, "effect_outer_distance": record.get("effect_outer_distance", 0.0)})
	world.apply_hits(requests)
	_consume_native_damage()


func _record_enemy_death(enemy: EnemyEntity, source_effect_id: StringName = &"", center_distance: float = 0.0) -> void:
	world.mark_death(enemy.entity_id, source_effect_id, center_distance)


func _process_pending_deaths(current_tick: int) -> void:
	var deaths: Dictionary = world.finish_deaths(current_tick, player_position,
		VfxPool.MAX_PRODUCTION_REQUESTS_PER_TICK - VfxPool.IMPORTANT_RESERVED_SLOTS)
	var total: int = 0
	var last_position: Vector2 = player_position
	for group: Dictionary in deaths.groups:
		var count: int = int(group.count)
		var enemy_type: int = int(group.enemy_type)
		total += count
		last_position = group.position
		state.visible_weapon_kill_count += int(group.visible)
		state.offscreen_weapon_kill_count += count - int(group.visible)
		state.max_weapon_kill_center_distance = maxf(state.max_weapon_kill_center_distance, float(group.maximum_center))
		if bool(group.is_swarm_event):
			state.swarm_event_kill_count += count
			state.swarm_event_xp += int(group.xp)
		elif not bool(group.is_encircler):
			if enemy_type < GameTypes.EnemyType.ELITE:
				state.normal_kills += count
				state.normal_kills_by_type[enemy_type] += count
				var segment: int = catalog.segment_index_for_tick(current_tick)
				if segment >= 0:
					state.normal_kills_by_segment[segment] += count
					state.normal_xp_by_segment[segment] += int(group.xp)
		var source: StringName = group.source_effect_id
		if source.is_empty():
			source = &"weapon"
		var key: String = "%s:%d" % [source, enemy_type]
		var feedback: Dictionary = _kill_feedback_by_key.get(key, {})
		feedback.count = int(feedback.get("count", 0)) + count
		feedback.position = group.position
		feedback.enemy_type = enemy_type
		feedback.source_effect_id = source
		_kill_feedback_by_key[key] = feedback
	state.total_kills += total
	state.weapon_kill_count += total
	for milestone: int in state.record_kill_chain_batch(current_tick, total):
		_queue_presentation_event(_make_presentation_event(
			CombatPresentationEvent.Kind.CHAIN_MILESTONE, &"chain_milestone", last_position,
			CombatPresentationEvent.Priority.IMPORTANT, milestone))
	for death: Dictionary in deaths.important:
		var enemy_type: int = int(death.enemy_type)
		if enemy_type == GameTypes.EnemyType.ELITE:
			state.elite_kills += 1
			var serial: int = int(death.elite_serial)
			if serial >= 0 and serial < state.elite_kill_ticks.size():
				state.elite_kill_ticks[serial] = current_tick
			arena_object_system.spawn_chest(death.position, serial)
		elif enemy_type == GameTypes.EnemyType.BOSS:
			state.boss_kills += 1
			state.boss_defeated = true
			state.boss_defeat_tick = current_tick
			state.boss_hp = 0.0
			_queue_presentation_event(_make_presentation_event(
				CombatPresentationEvent.Kind.BOSS_DEFEATED, &"boss_defeated", death.position,
				CombatPresentationEvent.Priority.TERMINAL, 1, enemy_type, death.source_effect_id))
	for death: Dictionary in deaths.effects:
		var enemy_type: int = int(death.enemy_type)
		var priority: int = VfxPool.PRIORITY_KILL
		if enemy_type == GameTypes.EnemyType.ELITE:
			priority = VfxPool.PRIORITY_IMPORTANT
		elif enemy_type == GameTypes.EnemyType.BOSS:
			priority = VfxPool.PRIORITY_TERMINAL
		vfx_pool.request(death.position, maxf(0.5, float(death.body_radius) * 2.0), DEATH_VFX_LIFETIME,
			_enemy_kill_color(enemy_type), current_tick, priority, _enemy_kill_effect_kind(enemy_type),
			(death.position - player_position).normalized())
	vfx_pool.record_suppressed_requests(int(deaths.omitted_effects), current_tick)


func _apply_player_damage_candidates(candidates: Array[Dictionary]) -> void:
	var selected: Dictionary = _select_player_damage_candidate(candidates)
	if not selected.is_empty():
		_apply_raw_player_damage(float(selected.get("raw_damage", 0.0)))


func _select_player_damage_candidate(candidates: Array[Dictionary]) -> Dictionary:
	var selected: Dictionary = {}
	for candidate: Dictionary in candidates:
		if float(candidate.get("raw_damage", 0.0)) <= 0.0:
			continue
		if selected.is_empty() or _player_damage_candidate_is_preferred(candidate, selected):
			selected = candidate
	return selected


func _player_damage_candidate_is_preferred(candidate: Dictionary, selected: Dictionary) -> bool:
	var candidate_damage: float = float(candidate.get("raw_damage", 0.0))
	var selected_damage: float = float(selected.get("raw_damage", 0.0))
	if candidate_damage != selected_damage:
		return candidate_damage > selected_damage
	var candidate_source: String = str(candidate.get("source_effect_id", &""))
	var selected_source: String = str(selected.get("source_effect_id", &""))
	if candidate_source != selected_source:
		return candidate_source < selected_source
	var candidate_entity: int = int(candidate.get("source_entity_id", -1))
	var selected_entity: int = int(selected.get("source_entity_id", -1))
	if candidate_entity != selected_entity:
		return candidate_entity < selected_entity
	var candidate_pool: int = int(candidate.get("source_pool_index", -1))
	var selected_pool: int = int(selected.get("source_pool_index", -1))
	if candidate_pool != selected_pool:
		return candidate_pool < selected_pool
	return int(candidate.get("source_generation", -1)) < int(
		selected.get("source_generation", -1)
	)


func _apply_raw_player_damage(raw_damage: float) -> void:
	if (
		raw_damage <= 0.0
		or _performance_fixture_active
		or state.is_level_up_resume_invulnerable()
	):
		return
	state.current_hp = maxf(0.0, state.current_hp - raw_damage)
	_step_events.append(&"player_hit")
	_player_hit_this_tick = true


func _accumulate_hit_feedback(
	source_effect_id: StringName,
	position: Vector2,
	enemy_type: GameTypes.EnemyType,
	applied_damage: float,
) -> void:
	var key: StringName = source_effect_id if not source_effect_id.is_empty() else &"weapon"
	var entry: Dictionary = _hit_feedback_by_source.get(key, {})
	entry["count"] = int(entry.get("count", 0)) + 1
	entry["position"] = position
	entry["enemy_type"] = enemy_type
	entry["intensity"] = maxf(float(entry.get("intensity", 0.0)), applied_damage)
	_hit_feedback_by_source[key] = entry


func _accumulate_kill_feedback(
	source_effect_id: StringName,
	position: Vector2,
	enemy_type: GameTypes.EnemyType,
) -> void:
	var resolved_source: StringName = (
		source_effect_id if not source_effect_id.is_empty() else &"weapon"
	)
	var key: String = "%s:%d" % [String(resolved_source), int(enemy_type)]
	var entry: Dictionary = _kill_feedback_by_key.get(key, {})
	entry["count"] = int(entry.get("count", 0)) + 1
	entry["position"] = position
	entry["enemy_type"] = enemy_type
	entry["source_effect_id"] = resolved_source
	_kill_feedback_by_key[key] = entry


func _flush_transient_feedback() -> void:
	var hit_keys: Array[StringName] = []
	for key: StringName in _hit_feedback_by_source:
		hit_keys.append(key)
	hit_keys.sort()
	for key: StringName in hit_keys:
		var hit: Dictionary = _hit_feedback_by_source[key]
		_queue_presentation_event(_make_presentation_event(
			CombatPresentationEvent.Kind.ENEMY_HIT,
			&"enemy_hit",
			hit.get("position", Vector2.ZERO),
			CombatPresentationEvent.Priority.NORMAL,
			int(hit.get("count", 1)),
			int(hit.get("enemy_type", GameTypes.EnemyType.PURSUER)),
			key,
			minf(1.0, float(hit.get("intensity", 1.0)) / 100.0),
		))
	var kill_keys: Array[String] = []
	for key: String in _kill_feedback_by_key:
		kill_keys.append(key)
	kill_keys.sort()
	for key: String in kill_keys:
		var kill: Dictionary = _kill_feedback_by_key[key]
		var enemy_type: int = int(kill.get("enemy_type", GameTypes.EnemyType.PURSUER))
		var event_id: StringName = &"elite_kill" if enemy_type == GameTypes.EnemyType.ELITE else &"enemy_kill"
		var priority: CombatPresentationEvent.Priority = (
			CombatPresentationEvent.Priority.IMPORTANT
			if enemy_type in [GameTypes.EnemyType.ELITE, GameTypes.EnemyType.BOSS]
			else CombatPresentationEvent.Priority.NORMAL
		)
		_queue_presentation_event(_make_presentation_event(
			CombatPresentationEvent.Kind.ENEMY_KILLED,
			event_id,
			kill.get("position", Vector2.ZERO),
			priority,
			int(kill.get("count", 1)),
			enemy_type,
			StringName(kill.get("source_effect_id", &"weapon")),
		))
	if _player_hit_this_tick:
		_queue_presentation_event(_make_presentation_event(
			CombatPresentationEvent.Kind.PLAYER_HIT,
			&"player_hit",
			player_position,
			CombatPresentationEvent.Priority.NORMAL,
		))


func _record_boss_action_feedback(
	was_charging: bool,
	alternate_before: bool,
	latched_spoke_count: int,
) -> void:
	var boss: EnemyEntity = enemy_system.boss_entity()
	if boss == null:
		return
	var volley_fired: bool = boss.barrage_alternate != alternate_before
	if volley_fired:
		var volley_count: int = maxi(1, latched_spoke_count)
		_queue_presentation_event(_make_presentation_event(
			CombatPresentationEvent.Kind.BOSS_VOLLEY,
			&"boss_volley",
			boss.position,
			CombatPresentationEvent.Priority.IMPORTANT,
			volley_count,
			GameTypes.EnemyType.BOSS,
		))
	if boss.boss_charge_active and (not was_charging or volley_fired):
		_queue_presentation_event(_make_presentation_event(
			CombatPresentationEvent.Kind.BOSS_CHARGE,
			&"boss_charge",
			boss.position,
			CombatPresentationEvent.Priority.IMPORTANT,
			boss.boss_charge_spoke_count,
			GameTypes.EnemyType.BOSS,
		))


func _make_presentation_event(
	kind: CombatPresentationEvent.Kind,
	event_id: StringName,
	position: Vector2,
	priority: CombatPresentationEvent.Priority,
	count: int = 1,
	enemy_type: int = -1,
	source_effect_id: StringName = &"",
	intensity: float = 1.0,
) -> CombatPresentationEvent:
	var event := CombatPresentationEvent.new()
	event.kind = kind
	event.event_id = event_id
	event.position = position
	event.priority = priority
	event.count = maxi(1, count)
	event.source_effect_id = source_effect_id
	event.intensity = maxf(0.0, intensity)
	event.tick = state.combat_tick
	event.combat_tick = state.combat_tick
	if enemy_type >= 0:
		event.enemy_type = enemy_type
		event.enemy_visual_kind = _enemy_visual_kind(enemy_type)
	return event


func _queue_presentation_event(event: CombatPresentationEvent) -> void:
	if event == null:
		return
	var normal_limit: int = (
		MAX_PRESENTATION_EVENTS_PER_TICK - PRESENTATION_IMPORTANT_RESERVE
	)
	if event.priority < CombatPresentationEvent.Priority.IMPORTANT and (
		_presentation_ordinary_count() >= normal_limit
	):
		if _merge_presentation_event(event):
			return
		if _replace_lower_priority_presentation_event(event):
			return
		state.feedback_event_suppressed_count += 1
		return
	if _presentation_events.size() >= MAX_PRESENTATION_EVENTS_PER_TICK:
		if _merge_presentation_event(event):
			return
		if _replace_lower_priority_presentation_event(event):
			return
		state.feedback_event_suppressed_count += 1
		return
	_presentation_events.append(event)
	state.feedback_event_emitted_count += 1


func _presentation_ordinary_count() -> int:
	var count: int = 0
	for event: CombatPresentationEvent in _presentation_events:
		if event.priority < CombatPresentationEvent.Priority.IMPORTANT:
			count += 1
	return count


func _replace_lower_priority_presentation_event(
	incoming: CombatPresentationEvent,
) -> bool:
	for index: int in range(_presentation_events.size()):
		if _presentation_events[index].priority >= incoming.priority:
			continue
		_presentation_events[index] = incoming
		state.feedback_event_suppressed_count += 1
		return true
	return false


func _merge_presentation_event(incoming: CombatPresentationEvent) -> bool:
	for existing: CombatPresentationEvent in _presentation_events:
		if (
			existing.kind != incoming.kind
			or existing.event_id != incoming.event_id
			or existing.source_effect_id != incoming.source_effect_id
			or existing.enemy_type != incoming.enemy_type
		):
			continue
		existing.count += incoming.count
		existing.intensity = maxf(existing.intensity, incoming.intensity)
		existing.position = incoming.position
		if incoming.priority > existing.priority:
			existing.priority = incoming.priority
		return true
	return false


func _record_audio_cue_metrics() -> void:
	var typed_event_ids: Dictionary[StringName, bool] = {}
	for event: CombatPresentationEvent in _presentation_events:
		if event == null:
			continue
		var event_id: StringName = event.resolved_event_id()
		if event_id.is_empty():
			continue
		typed_event_ids[event_id] = true
		var group: StringName = event_id
		if not event.source_effect_id.is_empty():
			group = StringName("%s:%s" % [event_id, event.source_effect_id])
		_record_audio_cue_id(
			event_id,
			int(event.priority),
			group,
			event.priority == CombatPresentationEvent.Priority.TERMINAL,
		)
	for event_id: StringName in _step_events:
		if event_id == &"chest_pickup" or typed_event_ids.has(event_id):
			continue
		_record_audio_cue_id(event_id)


func _record_audio_cue_id(
	event_id: StringName,
	priority: int = -1,
	group: StringName = &"",
	force: bool = false,
) -> void:
	if event_id.is_empty():
		return
	var resolved_priority: int = priority
	if resolved_priority < 0:
		resolved_priority = int(SurvivalFeedback.PRIORITY_BY_EVENT.get(
			event_id,
			AudioVoicePool.Priority.NORMAL,
		))
	var resolved_group: StringName = event_id if group.is_empty() else group
	var cooldown_usec: int = int(
		SurvivalFeedback.COOLDOWN_USEC_BY_EVENT.get(event_id, 0)
	)
	var cooldown_ticks: int = ceili(
		float(cooldown_usec) * float(RunState.TICKS_PER_SECOND) / 1_000_000.0
	)
	_audio_cue_admission.try_admit(
		state.combat_tick,
		RunState.TICKS_PER_SECOND,
		resolved_priority,
		resolved_group,
		cooldown_ticks,
		force,
	)


func _apply_passive_recovery() -> void:
	var stats: Dictionary = StatCalculator.aggregate(state, catalog)
	var recovery: float = StatCalculator.recovery_per_second(stats)
	if recovery > 0.0 and state.current_hp > 0.0:
		state.current_hp = minf(
			state.max_hp,
			state.current_hp + recovery * FIXED_DELTA_SECONDS,
		)


func _damage_nodes_from_projectiles(entries: PackedInt64Array, current_tick: int) -> void:
	arena_object_system.resolve_native_destructions(world.damage_projectile_nodes(entries), current_tick)


func _damage_nodes_from_attack(attack: Dictionary, current_tick: int) -> void:
	var zones: Array[Dictionary] = []
	zones.assign(attack.get("node_damage_zones", []))
	for zone: Dictionary in zones:
		arena_object_system.damage_nodes_circle(
			zone.get("center", Vector2.ZERO),
			float(zone.get("radius", 0.0)),
			float(zone.get("damage", 0.0)),
			current_tick,
		)


func _emit_attack_visuals(attack: Dictionary, current_tick: int) -> void:
	if not bool(attack.get("generated", false)):
		return
	var weapon_id := StringName(str(attack.get("weapon_id", "")))
	if not _weapon_visuals.has(weapon_id):
		return
	var visual: Vector2i = _weapon_visuals[weapon_id]
	# Multiple simultaneous swings can share the exact same region. Draw its
	# boundary once, while leaving every damage application in WeaponSystem intact.
	var shown: Array[Dictionary] = []
	for shape: Dictionary in attack.get("visual_shapes", []):
		if shape in shown or float(shape["radius"]) <= 0.0:
			continue
		shown.append(shape)
		weapon_effects.append(WeaponEffectState.new(shape, visual.x, visual.y != 0,
			current_tick, WeaponVisualStyle.ATTACK_TICKS))


func _consume_native_weapon_visuals(current_tick: int) -> void:
	var batch: Dictionary = world.take_weapon_visuals()
	for impact: Dictionary in batch.impacts:
		var visual: Vector2i = _weapon_visuals.get(impact.weapon_id, Vector2i.ZERO)
		weapon_effects.append(WeaponEffectState.new(impact, visual.x, visual.y != 0,
			current_tick, WeaponVisualStyle.IMPACT_TICKS))
	vfx_pool.record_suppressed_requests(int(batch.omitted_hits), current_tick)
	# The enemy's hit flag provides feedback. Native hit requests still consume
	# the decorative budget before trails, without producing floating hit marks.
	for cue: Dictionary in batch.trails:
		_emit_weapon_trail(cue, current_tick)


func _emit_weapon_trail(cue: Dictionary, current_tick: int) -> void:
	if vfx_pool.reduce_motion:
		return
	var visual: Vector2i = _weapon_visuals.get(cue.weapon_id, Vector2i.ZERO)
	if visual.x <= 0:
		return
	var ticks: int = WeaponVisualStyle.TRAIL_TICKS
	var slot: VfxState = vfx_pool.request(cue.position,
		float(cue.radius), float(ticks) / 60.0,
		WeaponVisualStyle.color_for(visual.x), current_tick,
		VfxPool.PRIORITY_GENERIC,
		VfxState.EffectKind.GENERIC, cue.direction, 1.0, visual.y != 0)
	if slot != null:
		slot.weapon_visual_kind = visual.x
		slot.weapon_duration_ticks = ticks
		slot.weapon_trail_length_m = float(cue.length)
		slot.weapon_height_m = float(cue.height)


func _resolve_modal_priority() -> void:
	if state.pending_level_ups > 0:
		if ProgressionService.create_offer(state, catalog) != null:
			RunStateMachine.transition(state, GameTypes.RunPhase.LEVEL_UP)
			return
	if not state.pending_chest_sources.is_empty():
		if ChestRewardService.create_outcome(state, catalog) != null:
			RunStateMachine.transition(state, GameTypes.RunPhase.CHEST_REWARD)


func _continue_after_modal(grant_level_up_protection: bool) -> void:
	if state.pending_level_ups > 0:
		ProgressionService.create_offer(state, catalog)
		state.phase = GameTypes.RunPhase.LEVEL_UP
		return
	if not state.pending_chest_sources.is_empty():
		ChestRewardService.create_outcome(state, catalog)
		state.phase = GameTypes.RunPhase.CHEST_REWARD
		return
	state.phase = GameTypes.RunPhase.COMBAT
	if grant_level_up_protection:
		grant_level_up_resume_invulnerability_ticks(
			_manifest.player.level_up_resume_invulnerability_ticks
		)


func _refresh_derived_player_stats() -> void:
	var stats: Dictionary = StatCalculator.aggregate(state, catalog)
	var expected_max_hp: float = StatCalculator.effective_max_hp(state.base_max_hp, stats)
	if not is_equal_approx(expected_max_hp, state.max_hp):
		var gained_hp: float = maxf(0.0, expected_max_hp - state.max_hp)
		state.max_hp = expected_max_hp
		state.current_hp = minf(state.max_hp, state.current_hp + gained_hp)


func _build_hud_values() -> Dictionary:
	var passives: Array[Dictionary] = []
	for runtime: RunPassive in state.passives:
		var definition: PassiveDefinition = catalog.passive(runtime.passive_id)
		if definition != null:
			passives.append({
				"passive_id": runtime.passive_id,
				"display_name": definition.display_name,
				"level": runtime.level,
				"max_level": definition.max_level,
			})
	return {
		"time_seconds": state.elapsed_seconds(),
		"current_hp": state.current_hp,
		"max_hp": state.max_hp,
		"level": state.level,
		"xp": state.xp,
		"xp_for_next_level": 0 if state.build_maxed else ProgressionService.xp_required_for_level(state.level, _manifest.progression),
		"build_maxed": state.build_maxed,
		"total_kills": state.total_kills,
		"weapon_slot_count": _manifest.progression.weapon_slot_count,
		"passive_slot_count": _manifest.progression.passive_slot_count,
		"weapons": weapon_system.build_hud_weapons(),
		"passives": passives,
		"boss_active": state.boss_spawned and not state.boss_defeated,
		"boss_hp": state.boss_hp,
		"boss_max_hp": state.boss_max_hp,
		"boss_phase": state.boss_phase,
		"boss_enrage_stacks": state.boss_enrage_stacks,
		"kill_chain_count": state.kill_chain_count if state.kill_chain_is_visible() else 0,
		"kill_chain_remaining_ticks": (
			maxi(0, state.kill_chain_window_ticks - (state.combat_tick - state.kill_chain_last_tick))
			if state.kill_chain_last_tick >= 0
			else 0
		),
		"stop_active": state.is_stop_active(),
		"active_enemy": enemy_system.enemy_store.active_count(),
		"active_projectile": projectile_pool.active_count(),
		"active_vfx": vfx_pool.active_count(),
		"active_xp": xp_pickup_pool.active_count(),
		"active_chest": arena_object_system.chest_transforms().size(),
		"active_node": arena_object_system.active_node_count(),
		"enemy_pool_overflow": enemy_system.enemy_store.overflow_count,
		"projectile_pool_overflow": projectile_pool.overflow_count,
		"vfx_pool_overflow": vfx_pool.overflow_count,
		"vfx_requests": vfx_pool.request_count,
		"vfx_admitted": vfx_pool.admitted_count,
		"vfx_suppressed": vfx_pool.generic_drop_count,
		"important_vfx_dropped": vfx_pool.important_drop_count,
		"audio_admitted": _audio_cue_admission.admitted_count,
		"audio_suppressed": _audio_cue_admission.suppressed_count,
		"feedback_emitted": state.feedback_event_emitted_count,
		"feedback_suppressed": state.feedback_event_suppressed_count,
		"xp_pool_overflow_merges": xp_pickup_pool.overflow_merge_count,
		"events": _step_events.duplicate(),
	}


func _reset_performance_fixture_state() -> void:
	_performance_combat_usec = 0
	_performance_combat_max_usec = 0
	_performance_snapshot_usec = 0
	_performance_snapshot_max_usec = 0
	_performance_snapshot_count = 0
	_performance_fixture_active = false
	_performance_enemy_target = 0
	_performance_projectile_target = 0
	_performance_vfx_target = 0
	_performance_xp_target = 0
	_performance_workload_ticks = 0
	_performance_grid_updates = 0
	_performance_projectile_collision_resolutions = 0
	_performance_weapon_attacks = 0
	_performance_enemy_recycles = 0
	_performance_enemy_motion_distance = 0.0
	_performance_projectile_motion_distance = 0.0
	_performance_enemy_serial = 0
	_performance_projectile_serial = 0
	_performance_vfx_serial = 0
	_performance_xp_serial = 0
	freeze_all_updates = false


func _maintain_performance_fixture(current_tick: int) -> void:
	var enemy_changed: bool = false
	if current_tick % PERFORMANCE_RECYCLE_INTERVAL_TICKS == 0:
		enemy_changed = _recycle_performance_enemy() or enemy_changed
		_recycle_performance_projectile()
		_recycle_performance_vfx()
		_recycle_performance_xp()
	var normalization_changed_enemies: bool = _normalize_performance_enemies(
		current_tick
	)
	enemy_changed = normalization_changed_enemies or enemy_changed
	_normalize_performance_projectiles(current_tick)
	_normalize_performance_vfx(current_tick)
	_normalize_performance_xp(current_tick)
	if enemy_changed:
		_rebuild_uniform_grid(current_tick + 1)


func _normalize_performance_enemies(current_tick: int) -> bool:
	var changed: bool = false
	while enemy_system.enemy_store.active_count() > _performance_enemy_target:
		var entity_ids: Array[int] = enemy_system.enemy_store.snapshot_ids_sorted()
		if entity_ids.is_empty():
			break
		if not enemy_system.enemy_store.remove(entity_ids.back()):
			break
		changed = true
	while enemy_system.enemy_store.active_count() < _performance_enemy_target:
		if not _spawn_performance_enemy(_performance_enemy_serial, current_tick):
			break
		_performance_enemy_serial += 1
		changed = true
	return changed


func _normalize_performance_projectiles(current_tick: int) -> void:
	world.trim_projectiles(_performance_projectile_target)
	var missing: int = _performance_projectile_target - projectile_pool.active_count()
	if missing > 0:
		_performance_projectile_serial += world.spawn_projectile_pattern(_performance_projectile_template,
			_performance_projectile_positions, _performance_projectile_directions, player_position,
			_performance_projectile_serial, missing, current_tick)


func _normalize_performance_vfx(current_tick: int) -> void:
	while vfx_pool.active_count() > _performance_vfx_target:
		var indices: Array[int] = vfx_pool.active_indices_snapshot()
		if indices.is_empty():
			break
		var pool_index: int = indices.back()
		var vfx: VfxState = vfx_pool.slots[pool_index]
		if not vfx_pool.release(pool_index, vfx.generation):
			break
	while vfx_pool.active_count() < _performance_vfx_target:
		if not _spawn_performance_vfx(_performance_vfx_serial, current_tick):
			break
		_performance_vfx_serial += 1


func _normalize_performance_xp(current_tick: int) -> void:
	while xp_pickup_pool.active_count() > _performance_xp_target:
		var indices: Array[int] = xp_pickup_pool.active_indices_snapshot()
		if indices.is_empty():
			break
		var pool_index: int = indices.back()
		var pickup: XpPickupState = xp_pickup_pool.slots[pool_index]
		if not xp_pickup_pool.release(pool_index, pickup.generation):
			break
	while xp_pickup_pool.active_count() < _performance_xp_target:
		if not _spawn_performance_xp(_performance_xp_serial, current_tick):
			break
		_performance_xp_serial += 1


func _recycle_performance_enemy() -> bool:
	var entity_ids: Array[int] = enemy_system.enemy_store.snapshot_ids_sorted()
	if entity_ids.is_empty():
		return false
	if not enemy_system.enemy_store.remove(entity_ids[0]):
		return false
	_performance_enemy_recycles += 1
	return true


func _recycle_performance_projectile() -> void:
	var indices: Array[int] = projectile_pool.active_indices_snapshot()
	if indices.is_empty():
		return
	var projectile: ProjectileState = projectile_pool.slots[indices[0]]
	projectile_pool.release(projectile.pool_index, projectile.generation)


func _recycle_performance_vfx() -> void:
	var indices: Array[int] = vfx_pool.active_indices_snapshot()
	if indices.is_empty():
		return
	var vfx: VfxState = vfx_pool.slots[indices[0]]
	vfx_pool.release(vfx.pool_index, vfx.generation)


func _recycle_performance_xp() -> void:
	var indices: Array[int] = xp_pickup_pool.active_indices_snapshot()
	if indices.is_empty():
		return
	var pickup: XpPickupState = xp_pickup_pool.slots[indices[0]]
	xp_pickup_pool.release(pickup.pool_index, pickup.generation)


func _spawn_performance_enemy(serial: int, born_tick: int) -> bool:
	if _performance_enemy_target <= 0:
		return false
	var enemy_type: GameTypes.EnemyType
	match serial % 4:
		0:
			enemy_type = GameTypes.EnemyType.PURSUER
		1:
			enemy_type = GameTypes.EnemyType.SWARMER
		2:
			enemy_type = GameTypes.EnemyType.BULWARK
		_:
			enemy_type = GameTypes.EnemyType.SHOOTER
	var definition: EnemyDefinition = catalog.enemy_for_type(enemy_type)
	if definition == null:
		return false
	var fixture_index: int = serial % _performance_enemy_target
	var enemy: EnemyEntity = enemy_system.enemy_store.try_spawn(
		state,
		enemy_type,
		definition,
		_performance_position(fixture_index, _performance_enemy_target, 0.0),
		1.0,
		1.0,
		born_tick,
	)
	if enemy == null:
		return false
	enemy.max_hp = PERFORMANCE_FIXTURE_HP
	enemy.hp = PERFORMANCE_FIXTURE_HP
	return true


func _spawn_performance_vfx(serial: int, born_tick: int) -> bool:
	if _performance_vfx_target <= 0:
		return false
	var fixture_index: int = serial % _performance_vfx_target
	return vfx_pool.acquire(
		_performance_position(fixture_index, _performance_vfx_target, 0.36),
		0.16 + 0.04 * float(serial % 3),
		PERFORMANCE_FIXTURE_LIFETIME_SECONDS,
		Color(0.30, 0.75, 1.0, 0.75),
		born_tick,
	) != null


func _spawn_performance_xp(serial: int, born_tick: int) -> bool:
	if _performance_xp_target <= 0:
		return false
	var fixture_index: int = serial % _performance_xp_target
	return xp_pickup_pool.acquire(
		_performance_position(fixture_index, _performance_xp_target, 0.54),
		1,
		born_tick,
		player_position,
	) != null


func _performance_counts_are_exact() -> bool:
	return (
		state != null
		and enemy_system.enemy_store.active_count() == _performance_enemy_target
		and projectile_pool.active_count() == _performance_projectile_target
		and vfx_pool.active_count() == _performance_vfx_target
		and xp_pickup_pool.active_count() == _performance_xp_target
		and state.weapons.size() == PERFORMANCE_DEFAULT_WEAPON_COUNT
	)


func _performance_position(index: int, count: int, offset: float) -> Vector2:
	if count <= 0:
		return Vector2.ZERO
	const COLUMN_COUNT: int = 40
	var row_count: int = maxi(1, ceili(float(count) / float(COLUMN_COUNT)))
	var column: int = index % COLUMN_COUNT
	var row: int = floori(float(index) / float(COLUMN_COUNT))
	var x_ratio: float = float(column) / float(COLUMN_COUNT - 1)
	var y_ratio: float = float(row) / float(maxi(1, row_count - 1))
	return Vector2(
		player_position.x + lerpf(-15.35, 15.35, x_ratio) + offset,
		player_position.y + lerpf(-15.35, 15.35, y_ratio),
	)


func _ensure_performance_weapons() -> void:
	state.weapons.clear()
	for weapon_id: StringName in catalog.basic_weapon_ids():
		if state.weapons.size() >= PERFORMANCE_DEFAULT_WEAPON_COUNT:
			break
		var definition: WeaponDefinition = catalog.weapon(weapon_id)
		if definition == null:
			continue
		var runtime: RunWeapon = RunWeapon.create(
			definition.weapon_id,
			catalog.lineage_for_weapon(definition.weapon_id),
			false,
			state.rng_streams.create_weapon_rng(catalog.lineage_for_weapon(definition.weapon_id), state.weapons.size()),
		)
		runtime.level = definition.max_level
		runtime.ready_on_resume = true
		state.weapons.append(runtime)
	weapon_system.initialize(state, catalog, projectile_pool, event_router)


func _rebuild_uniform_grid(current_tick: int) -> void:
	enemy_system.uniform_grid.rebuild_enemies(enemy_system.enemy_store, current_tick)


func _apply_snapshot_markers(snapshot: CombatSnapshot) -> void:
	snapshot.boss_boundary_active = enemy_system.encounters.boss_active
	snapshot.boss_boundary_center = enemy_system.encounters.boss_center
	snapshot.boss_boundary_radius = enemy_system.encounters.boss_radius
	snapshot.boss_boundary_progress = enemy_system.encounters.boss_progress
	var boss: EnemyEntity = enemy_system.boss_entity()
	if boss != null and boss.boss_charge_active:
		snapshot.boss_charge_active = true
		snapshot.boss_charge_position = boss.position
		snapshot.boss_charge_progress = boss.boss_charge_progress()
		snapshot.boss_charge_radius = maxf(2.4, boss.body_radius() * 1.6)
		snapshot.boss_charge_spoke_count = boss.boss_charge_spoke_count
		if boss.boss_charge_spoke_count > 0 and boss.boss_charge_half_step:
			snapshot.boss_charge_angle_offset = (
				TAU * 0.5 / float(boss.boss_charge_spoke_count)
			)
	var important: EnemyEntity = _materializing_important_enemy()
	if important != null:
		snapshot.important_marker_active = true
		snapshot.important_marker_kind = (
			CombatSnapshot.ImportantMarkerKind.BOSS
			if important.enemy_type == GameTypes.EnemyType.BOSS
			else CombatSnapshot.ImportantMarkerKind.ELITE
		)
		snapshot.important_marker_position = important.position
		snapshot.important_marker_progress = important.materialization_progress(
			state.combat_tick
		)
		snapshot.important_marker_radius = maxf(1.0, important.body_radius() * 1.45)
	if (
		_absorption_started_tick >= 0
		and state.combat_tick < _absorption_started_tick + envelope.boss_entry_ticks
	):
		var progress: float = clampf(
			float(state.combat_tick - _absorption_started_tick)
			/ float(envelope.boss_entry_ticks),
			0.0,
			1.0,
		)
		snapshot.absorption_active = true
		snapshot.absorption_position = _absorption_position
		snapshot.absorption_progress = progress
		snapshot.absorption_radius = lerpf(
			_absorption_radius,
			0.8,
			progress * progress * (3.0 - 2.0 * progress),
		)


func _materializing_important_enemy() -> EnemyEntity:
	var elite: EnemyEntity = null
	var boss: EnemyEntity = null
	for entity_id: int in world.important_ids():
		var enemy: EnemyEntity = enemy_system.enemy_store.get_by_id(entity_id)
		if enemy.enemy_type != GameTypes.EnemyType.BOSS and enemy.enemy_type != GameTypes.EnemyType.ELITE:
			continue
		if not enemy.is_materializing(state.combat_tick):
			continue
		if enemy.enemy_type == GameTypes.EnemyType.BOSS and (boss == null or enemy.entity_id < boss.entity_id):
			boss = enemy
		if enemy.enemy_type == GameTypes.EnemyType.ELITE and (elite == null or enemy.entity_id < elite.entity_id):
			elite = enemy
	return boss if boss != null else elite


func _enemy_visual_kind(enemy_type: int) -> int:
	match enemy_type:
		GameTypes.EnemyType.SWARMER:
			return CombatSnapshot.EnemyVisualKind.SWARMER
		GameTypes.EnemyType.BULWARK:
			return CombatSnapshot.EnemyVisualKind.BULWARK
		GameTypes.EnemyType.SHOOTER:
			return CombatSnapshot.EnemyVisualKind.SHOOTER
		GameTypes.EnemyType.ELITE:
			return CombatSnapshot.EnemyVisualKind.ELITE
		GameTypes.EnemyType.BOSS:
			return CombatSnapshot.EnemyVisualKind.BOSS
	return CombatSnapshot.EnemyVisualKind.PURSUER


func _enemy_kill_color(enemy_type: int) -> Color:
	match enemy_type:
		GameTypes.EnemyType.SWARMER:
			return Color(1.0, 0.58, 0.18, 0.82)
		GameTypes.EnemyType.BULWARK:
			return Color(0.9, 0.24, 0.16, 0.84)
		GameTypes.EnemyType.SHOOTER:
			return Color(1.0, 0.22, 0.55, 0.84)
		GameTypes.EnemyType.ELITE:
			return Color(1.0, 0.78, 0.18, 0.9)
		GameTypes.EnemyType.BOSS:
			return Color(1.0, 0.12, 0.16, 0.94)
	return Color(1.0, 0.34, 0.22, 0.82)


func _enemy_kill_effect_kind(enemy_type: int) -> VfxState.EffectKind:
	match enemy_type:
		GameTypes.EnemyType.SWARMER, GameTypes.EnemyType.SHOOTER:
			return VfxState.EffectKind.ENERGY_WAVE
		GameTypes.EnemyType.BULWARK, GameTypes.EnemyType.ELITE, GameTypes.EnemyType.BOSS:
			return VfxState.EffectKind.AURA_PULSE
	return VfxState.EffectKind.GENERIC


func _consume_native_damage() -> void:
	for row: Dictionary in world.take_damage_totals():
		var source: StringName = row.source
		var damage: float = float(row.damage)
		var count: int = int(row.count)
		state.record_weapon_damage(source, damage)
		state.weapon_hit_count += count
		state.next_event_serial += count
		state.visible_weapon_hit_count += int(row.visible)
		state.offscreen_weapon_hit_count += count - int(row.visible)
		state.max_weapon_hit_center_distance = maxf(state.max_weapon_hit_center_distance, float(row.maximum_center))
		state.max_weapon_effect_outer_distance = maxf(state.max_weapon_effect_outer_distance, float(row.maximum_outer))
		var key: StringName = source if not source.is_empty() else &"weapon"
		var feedback: Dictionary = _hit_feedback_by_source.get(key, {})
		feedback.count = int(feedback.get("count", 0)) + count
		feedback.position = row.position
		feedback.enemy_type = int(row.enemy_type)
		feedback.intensity = maxf(float(feedback.get("intensity", 0.0)), float(row.maximum_damage))
		_hit_feedback_by_source[key] = feedback
		var life_steal: float = weapon_system.life_steal_for_lineage(source)
		if life_steal > 0.0:
			state.current_hp = minf(state.max_hp, state.current_hp + damage * life_steal)
	var boss: EnemyEntity = enemy_system.boss_entity()
	if boss != null:
		state.boss_hp = boss.hp


func _configure_native_visuals() -> void:
	var kinds: Dictionary[StringName, int] = {
		&"resonance_wave": CombatSnapshot.ProjectileVisualKind.RESONANCE_WAVE,
		&"homing_core": CombatSnapshot.ProjectileVisualKind.HOMING_CORE,
		&"directional_needle": CombatSnapshot.ProjectileVisualKind.DIRECTIONAL_NEEDLE,
		&"arc_crystal": CombatSnapshot.ProjectileVisualKind.ARC_CRYSTAL,
		&"returning_ring": CombatSnapshot.ProjectileVisualKind.RETURNING_RING,
		&"orbital_array": CombatSnapshot.ProjectileVisualKind.ORBITAL_ARRAY,
		&"mass_projectile": CombatSnapshot.ProjectileVisualKind.MASS_PROJECTILE,
		&"zero_field": CombatSnapshot.ProjectileVisualKind.ZERO_FIELD,
	}
	_weapon_visuals.clear()
	for definition: WeaponDefinition in catalog.weapons.values():
		_weapon_visuals[definition.weapon_id] = Vector2i(kinds.get(catalog.lineage_for_weapon(definition.weapon_id), 0), int(definition.is_evolved))
	world.configure_visuals(_weapon_visuals)


func _archive_events() -> void:
	_pending_step_events.append_array(_step_events)
	_pending_presentation_events.append_array(_presentation_events)
	_step_events.clear()
	_presentation_events.clear()


## Draining events never constructs rendering data. A snapshot is read-only;
## multiple simulation ticks retain their events until this explicit drain.
func take_events() -> CombatSnapshot:
	_archive_events()
	var events := CombatSnapshot.new()
	events.player_position = player_position
	events.world_origin = world_origin
	events.hud_values = {"events": _pending_step_events.duplicate()}
	events.presentation_events = _pending_presentation_events.duplicate()
	_pending_step_events.clear()
	_pending_presentation_events.clear()
	return events


func performance_timings() -> Dictionary:
	return {
		"combat_mean_usec": _performance_combat_usec / float(maxi(1, _performance_workload_ticks)),
		"combat_max_usec": _performance_combat_max_usec, "combat_ticks": _performance_workload_ticks,
		"snapshot_mean_usec": _performance_snapshot_usec / float(maxi(1, _performance_snapshot_count)),
		"snapshot_max_usec": _performance_snapshot_max_usec, "snapshots": _performance_snapshot_count,
		"static_memory_bytes": OS.get_static_memory_usage(),
	}


func _prepare_projectile_pattern() -> void:
	_performance_projectile_positions.clear()
	_performance_projectile_directions.clear()
	for index: int in _performance_projectile_target:
		_performance_projectile_positions.append(_performance_position(index, _performance_projectile_target, 0.18) - player_position)
	for index: int in 360:
		_performance_projectile_directions.append(Vector2.from_angle(TAU * index / 360.0))
	_performance_projectile_template = {
		"faction": ProjectileState.FACTION_ALLY, "weapon_id": &"performance", "source_effect_id": &"performance",
		"speed": PERFORMANCE_PROJECTILE_SPEED, "radius": 0.16, "damage": 0.0,
		"remaining_distance": PERFORMANCE_PROJECTILE_DISTANCE, "remaining_lifetime": PERFORMANCE_FIXTURE_LIFETIME_SECONDS,
		"pierce_remaining": 8, "total_lifetime_ticks": roundi(PERFORMANCE_FIXTURE_LIFETIME_SECONDS * RunState.TICKS_PER_SECOND),
	}
