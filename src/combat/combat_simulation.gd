class_name CombatSimulation
extends RefCounted


const PLAYER_SPEED: float = 5.0
const PLAYER_RADIUS: float = 0.45
const ARENA_MIN: Vector2 = Vector2(-15.0, -9.0)
const ARENA_MAX: Vector2 = Vector2(15.0, 9.0)

var state: RunState = null
var catalog: DefinitionCatalog = null
var wave: WaveDefinition = null
var player_position: Vector2 = Vector2.ZERO
var enemy_system: EnemySystem = EnemySystem.new()
var projectile_pool: ProjectilePool = ProjectilePool.new()
var vfx_pool: VfxPool = VfxPool.new()
var chest_visual_pool: ChestVisualPool = ChestVisualPool.new()
var event_router: CombatEventRouter = CombatEventRouter.new()
var weapon_system: WeaponSystem = WeaponSystem.new()
var skill_system: CombatSkillSystem = CombatSkillSystem.new()
var loot_service: LootService = LootService.new()

var freeze_enemy_ai: bool = false
var freeze_enemy_timers: bool = false
var freeze_normal_spawn: bool = false
var freeze_countdown: bool = false
var freeze_all_updates: bool = false
var allow_contact_timers_only: bool = false
var main_weapon_damage_override: float = -1.0

var _pending_deaths: Array[Dictionary] = []


func initialize(
	p_state: RunState,
	p_catalog: DefinitionCatalog,
	rng_source: Variant = null,
) -> void:
	freeze_all_updates = false
	state = p_state
	catalog = p_catalog
	wave = catalog.wave(state.wave_number)
	player_position = Vector2.ZERO
	projectile_pool.clear()
	vfx_pool.clear()
	chest_visual_pool = ChestVisualPool.new()
	event_router = CombatEventRouter.new()
	loot_service = LootService.new()
	loot_service.initialize(state, catalog, chest_visual_pool)
	var stats: Dictionary = StatCalculator.aggregate_affixes(state.equipped)
	state.max_hp = StatCalculator.effective_max_hp(stats)
	state.current_hp = state.max_hp
	state.wave_main_weapon_type = _equipped_main_weapon_type()
	enemy_system = EnemySystem.new()
	enemy_system.initialize(state, catalog, wave, rng_source)
	weapon_system = WeaponSystem.new()
	weapon_system.initialize(state, catalog, projectile_pool, event_router)
	skill_system = CombatSkillSystem.new()
	skill_system.initialize(state, catalog, event_router)
	skill_system.prepare_for_combat()
	_rebuild_uniform_grid(enemy_system.snapshot_ids(), state.physics_tick + 1)


func begin_wave(wave_number: int, rng_source: Variant = null) -> bool:
	var next_wave: WaveDefinition = catalog.wave(wave_number)
	if next_wave == null:
		return false
	freeze_all_updates = false
	state.wave_number = wave_number
	state.phase = GameTypes.RunPhase.COMBAT
	state.time_remaining = next_wave.duration_seconds
	state.wave_kills = 0
	state.wave_chests = 0
	state.wave_cleared = false
	state.boss_defeated = false
	state.spawn_credit = 0.0
	state.non_boss_spawned = 0
	state.scheduled_proc_replays.clear()
	state.recent_damage_samples.clear()
	state.coward_stationary_elapsed = 0.0
	wave = next_wave
	var stats: Dictionary = StatCalculator.aggregate_affixes(state.equipped)
	state.max_hp = StatCalculator.effective_max_hp(stats)
	state.current_hp = state.max_hp
	state.wave_main_weapon_type = _equipped_main_weapon_type()
	player_position = Vector2.ZERO
	projectile_pool.clear()
	vfx_pool.clear()
	chest_visual_pool.clear()
	loot_service.initialize(state, catalog, chest_visual_pool)
	enemy_system = EnemySystem.new()
	enemy_system.initialize(state, catalog, wave, rng_source)
	weapon_system = WeaponSystem.new()
	weapon_system.initialize(state, catalog, projectile_pool, event_router)
	if skill_system == null:
		skill_system = CombatSkillSystem.new()
	skill_system.initialize(state, catalog, event_router)
	skill_system.prepare_for_combat()
	return true


func step(move_input: Vector2, delta: float) -> CombatSnapshot:
	if state == null or wave == null or state.phase != GameTypes.RunPhase.COMBAT:
		return build_snapshot()
	if freeze_all_updates:
		return build_snapshot()
	state.physics_tick += 1
	var current_tick: int = state.physics_tick
	_pending_deaths.clear()
	var enemy_snapshot: Array[int] = enemy_system.snapshot_ids()
	var projectile_snapshot: Array[Vector2i] = projectile_pool.snapshot_active()

	var previous_player_position: Vector2 = player_position
	_move_player(move_input, delta)
	skill_system.update_coward_motion(previous_player_position, player_position, delta)
	if not freeze_enemy_ai and not freeze_enemy_timers:
		enemy_system.advance_snapshot(
			enemy_snapshot,
			player_position,
			delta,
			current_tick,
		)
	elif allow_contact_timers_only:
		_advance_fixture_contact_timers(enemy_snapshot, delta, current_tick)
	else:
		_rebuild_uniform_grid(enemy_snapshot, current_tick)
	weapon_system.move_snapshot_projectiles(projectile_snapshot, delta, current_tick)
	vfx_pool.advance(delta, current_tick)
	chest_visual_pool.advance(delta)
	if not freeze_normal_spawn:
		enemy_system.accrue_spawn_credit(delta)

	if not freeze_enemy_timers:
		enemy_system.resolve_ready_boss_summons(
			enemy_snapshot,
			player_position,
			current_tick,
		)
	if not freeze_normal_spawn:
		enemy_system.resolve_normal_spawns(player_position, current_tick)

	skill_system.advance_time_progress(delta)
	for replay: ScheduledProcReplay in skill_system.take_due_replays(current_tick):
		var replay_result: Dictionary
		if replay.proc_effect_id == CombatSkillSystem.ECHO_PROC_ID:
			replay_result = weapon_system.replay_weapon(
				replay,
				player_position,
				enemy_system.enemy_store,
				enemy_system.uniform_grid,
				current_tick,
			)
		else:
			replay_result = skill_system.resolve_scheduled_skill(
				replay,
				enemy_snapshot,
				enemy_system.enemy_store,
				enemy_system.uniform_grid,
				player_position,
				current_tick,
			)
		_apply_resolution_hits(replay_result)

	for projectile_entry: Vector2i in projectile_snapshot:
		var ally_hits: Array[Dictionary] = weapon_system.resolve_ally_projectile(
			projectile_entry,
			enemy_system.enemy_store,
			enemy_system.uniform_grid,
			current_tick,
		)
		_apply_enemy_hit_records(ally_hits)


	if not skill_system.combat_progress_paused():
		var coward_active: bool = skill_system.coward_stationary_active()
		weapon_system.advance_attack_timer(delta, coward_active)
		var primary_result: Dictionary = weapon_system.try_primary_attack_detailed(
			player_position,
			enemy_system.enemy_store,
			enemy_system.uniform_grid,
			current_tick,
			coward_active,
			main_weapon_damage_override,
		)
		skill_system.register_primary_attack(primary_result, current_tick)
		_apply_resolution_hits(primary_result)

	var pending_candidates: Array[Dictionary] = skill_system.pending_activation_snapshot()
	for candidate: Dictionary in pending_candidates:
		var skill_result: Dictionary = skill_system.resolve_pending_candidate(
			candidate,
			enemy_snapshot,
			enemy_system.enemy_store,
			enemy_system.uniform_grid,
			player_position,
			current_tick,
		)
		_apply_resolution_hits(skill_result)

	if not freeze_enemy_timers or allow_contact_timers_only:
		var enemy_damage: Array[Dictionary] = enemy_system.resolve_ready_enemy_damage_actions(
			enemy_snapshot,
			player_position,
			current_tick,
		)
		_apply_player_damage_records(enemy_damage)

	var enemy_projectile_hits: Array[Dictionary] = weapon_system.resolve_enemy_projectiles(
		projectile_snapshot,
		player_position,
		current_tick,
	)
	_apply_enemy_projectile_damage(enemy_projectile_hits)

	if not freeze_enemy_timers:
		enemy_system.resolve_ready_enemy_special_actions(
			enemy_snapshot,
			player_position,
			current_tick,
			projectile_pool,
		)

	_process_pending_loot(current_tick)
	if not state.wave_cleared and RunStateMachine.quota_reached(state, wave):
		loot_service.ensure_guarantee_fallback(player_position, current_tick)

	var player_dead: bool = state.current_hp <= 0.0
	if freeze_countdown:
		_latch_quota_without_countdown()
	else:
		RunStateMachine.resolve_combat_tick(state, wave, player_dead, delta)
	if state.phase == GameTypes.RunPhase.REWARD_REVEAL:
		chest_visual_pool.absorb_all()
	elif state.phase == GameTypes.RunPhase.FAILED:
		chest_visual_pool.clear()
		loot_service.discard_current_wave_rewards()
	if (
		state.phase == GameTypes.RunPhase.COMBAT
		and not player_dead
		and not freeze_countdown
	):
		enemy_system.resolve_w4_elite_after_countdown(player_position, current_tick)
	return build_snapshot()


func step_tutorial_movement(move_input: Vector2, delta: float) -> CombatSnapshot:
	if state == null or wave == null or state.phase != GameTypes.RunPhase.COMBAT:
		return build_snapshot()
	_move_player(move_input, maxf(0.0, delta))
	return build_snapshot()


func configure_accessibility(reduce_motion: bool, reduce_flashes: bool) -> void:
	chest_visual_pool.reduce_motion = reduce_motion
	chest_visual_pool.reduce_flashes = reduce_flashes


func build_snapshot() -> CombatSnapshot:
	if state == null or wave == null:
		return CombatSnapshot.new()
	var enemy_transforms: Array[Transform3D] = []
	for entity_id: int in enemy_system.enemy_store.snapshot_ids_sorted():
		var enemy: EnemyEntity = enemy_system.enemy_store.get_by_id(entity_id)
		if enemy == null:
			continue
		var diameter_scale: float = maxf(0.35, enemy.body_radius() / 0.4)
		var height_scale: float = _enemy_height_scale(enemy.enemy_type)
		var basis := Basis.IDENTITY.scaled(Vector3(diameter_scale, height_scale, diameter_scale))
		enemy_transforms.append(Transform3D(
			basis,
			Vector3(enemy.position.x, 0.5 * height_scale, enemy.position.y),
		))
	var projectile_transforms: Array[Transform3D] = []
	for projectile: ProjectileState in projectile_pool.slots:
		if not projectile.active:
			continue
		var projectile_scale: float = maxf(0.25, projectile.radius / 0.16)
		projectile_transforms.append(Transform3D(
			Basis.IDENTITY.scaled(Vector3.ONE * projectile_scale),
			Vector3(projectile.position.x, 0.35, projectile.position.y),
		))
	var vfx_transforms: Array[Transform3D] = []
	for vfx: VfxState in vfx_pool.slots:
		if not vfx.active:
			continue
		vfx_transforms.append(Transform3D(
			Basis.IDENTITY.scaled(Vector3(vfx.scale_m, 1.0, vfx.scale_m)),
			Vector3(vfx.position.x, 0.12, vfx.position.y),
		))
	var chest_transforms: Array[Transform3D] = chest_visual_pool.transforms()
	return CombatSnapshot.new(
		player_position,
		enemy_transforms,
		projectile_transforms,
		vfx_transforms,
		_build_hud_values(),
		chest_transforms,
	)


func spawn_fixture_enemy(
	enemy_type: GameTypes.EnemyType,
	position: Vector2,
	born_tick: int = -1,
	apply_wave_multiplier: bool = false,
	summoned_by_boss: bool = false,
) -> EnemyEntity:
	var definition: EnemyDefinition = catalog.enemy(GameTypes.enemy_type_to_key(enemy_type))
	if definition == null:
		return null
	var hp_multiplier: float = wave.hp_multiplier if apply_wave_multiplier else 1.0
	var damage_multiplier: float = wave.damage_multiplier if apply_wave_multiplier else 1.0
	var resolved_born_tick: int = state.physics_tick - 1 if born_tick < 0 else born_tick
	var enemy: EnemyEntity = enemy_system.enemy_store.try_spawn(
		state,
		enemy_type,
		definition,
		position,
		hp_multiplier,
		damage_multiplier,
		resolved_born_tick,
		summoned_by_boss,
	)
	_rebuild_uniform_grid(enemy_system.snapshot_ids(), state.physics_tick + 1)
	return enemy


func add_fixture_vfx(
	position: Vector2,
	scale_m: float,
	color: Color,
	lifetime: float = 3600.0,
) -> VfxState:
	return vfx_pool.acquire(position, scale_m, lifetime, color, state.physics_tick - 1)


func prepare_performance_fixture(
	enemy_count: int = 500,
	projectile_count: int = 1200,
	vfx_count: int = 800,
) -> bool:
	if (
		state == null
		or wave == null
		or enemy_count < 0
		or enemy_count > EnemyStore.CAPACITY
		or projectile_count < 0
		or projectile_count > ProjectilePool.CAPACITY
		or vfx_count < 0
		or vfx_count > VfxPool.CAPACITY
	):
		return false
	enemy_system.enemy_store.clear()
	projectile_pool.clear()
	vfx_pool.clear()
	enemy_system.enemy_store.overflow_count = 0
	projectile_pool.overflow_count = 0
	vfx_pool.overflow_count = 0
	event_router.chain_depth_overflow_count = 0
	state.next_entity_id = 0
	var enemy_types: Array[GameTypes.EnemyType] = [
		GameTypes.EnemyType.TRACKER,
		GameTypes.EnemyType.FAST,
		GameTypes.EnemyType.ARMORED,
		GameTypes.EnemyType.RANGED,
	]
	for index: int in range(enemy_count):
		var enemy_type: GameTypes.EnemyType = enemy_types[index % enemy_types.size()]
		var definition: EnemyDefinition = catalog.enemy(
			GameTypes.enemy_type_to_key(enemy_type)
		)
		var position := _performance_position(index, enemy_count, 0.0)
		if enemy_system.enemy_store.try_spawn(
			state,
			enemy_type,
			definition,
			position,
			1.0,
			1.0,
			state.physics_tick - 1,
		) == null:
			return false
	_rebuild_uniform_grid(enemy_system.snapshot_ids(), state.physics_tick + 1)
	for index: int in range(projectile_count):
		var position := _performance_position(index, projectile_count, 0.18)
		if projectile_pool.acquire(
			&"ally",
			&"performance",
			-1,
			position,
			Vector2.ZERO,
			0.16,
			0.0,
			9999.0,
			3600.0,
			position,
			0,
			state.physics_tick - 1,
		) == null:
			return false
	for index: int in range(vfx_count):
		var position := _performance_position(index, vfx_count, 0.36)
		if vfx_pool.acquire(
			position,
			0.16 + 0.04 * float(index % 3),
			3600.0,
			Color(0.30, 0.75, 1.0, 0.75),
			state.physics_tick - 1,
		) == null:
			return false
	freeze_enemy_ai = true
	freeze_enemy_timers = true
	freeze_normal_spawn = true
	freeze_countdown = true
	freeze_all_updates = true
	return (
		enemy_system.enemy_store.active_count() == enemy_count
		and projectile_pool.active_count() == projectile_count
		and vfx_pool.active_count() == vfx_count
	)


func performance_fixture_metrics() -> Dictionary:
	return {
		"active_enemy": enemy_system.enemy_store.active_count(),
		"active_projectile": projectile_pool.active_count(),
		"active_vfx": vfx_pool.active_count(),
		"projectile_pool_used": projectile_pool.active_count(),
		"vfx_pool_used": vfx_pool.active_count(),
		"enemy_pool_overflow": enemy_system.enemy_store.overflow_count,
		"projectile_pool_overflow": projectile_pool.overflow_count,
		"vfx_pool_overflow": vfx_pool.overflow_count,
		"effect_chain_depth_overflow": event_router.chain_depth_overflow_count,
	}


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
		lerpf(ARENA_MIN.x + 0.25, ARENA_MAX.x - 0.25, x_ratio) + offset,
		lerpf(ARENA_MIN.y + 0.25, ARENA_MAX.y - 0.25, y_ratio),
	)


func _move_player(move_input: Vector2, delta: float) -> void:
	var normalized_input: Vector2 = move_input
	if normalized_input.length_squared() > 1.0:
		normalized_input = normalized_input.normalized()
	var stats: Dictionary = StatCalculator.aggregate_affixes(state.equipped)
	var speed: float = StatCalculator.effective_move_speed(stats)
	player_position += normalized_input * speed * delta
	player_position = Vector2(
		clampf(player_position.x, ARENA_MIN.x, ARENA_MAX.x),
		clampf(player_position.y, ARENA_MIN.y, ARENA_MAX.y),
	)


func _apply_resolution_hits(result: Dictionary) -> void:
	var records: Array[Dictionary] = []
	records.assign(result.get("hits", []))
	_apply_enemy_hit_records(records)


func _apply_enemy_hit_records(records: Array[Dictionary]) -> void:
	for record: Dictionary in records:
		var event: CombatEvent = record.get("event") as CombatEvent
		if event == null:
			continue
		var entity_id: int = int(record.get("entity_id", -1))
		var enemy: EnemyEntity = enemy_system.enemy_store.get_by_id(entity_id)
		if enemy == null:
			continue
		var applied_damage: float = minf(enemy.hp, maxf(0.0, event.damage_snapshot))
		enemy.hp = maxf(0.0, enemy.hp - applied_damage)
		_update_damage_samples(event, applied_damage)
		if enemy.hp <= 0.0:
			_record_enemy_death(enemy, event)


func _update_damage_samples(event: CombatEvent, applied_damage: float) -> void:
	if applied_damage > 0.0:
		var sample := DamageSample.new()
		sample.physics_tick = state.physics_tick
		sample.event_serial = event.event_serial
		sample.applied_damage = applied_damage
		state.recent_damage_samples.append(sample)
	var minimum_tick: int = state.physics_tick - 60
	while (
		not state.recent_damage_samples.is_empty()
		and state.recent_damage_samples[0].physics_tick < minimum_tick
	):
		state.recent_damage_samples.pop_front()
	var current_dps: float = 0.0
	for sample: DamageSample in state.recent_damage_samples:
		current_dps += sample.applied_damage
	state.peak_dps = maxf(state.peak_dps, current_dps)


func _record_enemy_death(enemy: EnemyEntity, cause_event: CombatEvent) -> void:
	var already_cleared: bool = state.wave_cleared
	_pending_deaths.append({
		"entity_id": enemy.entity_id,
		"enemy_type": enemy.enemy_type,
		"position": enemy.position,
	})
	enemy_system.enemy_store.remove(enemy.entity_id)
	state.wave_kills += 1
	state.total_kills += 1
	if already_cleared:
		state.post_quota_kills += 1
	match enemy.enemy_type:
		GameTypes.EnemyType.ELITE:
			state.elite_kills += 1
		GameTypes.EnemyType.BOSS:
			state.boss_kills += 1
			state.boss_defeated = true
		_:
			state.normal_kills += 1
	skill_system.register_kill(cause_event)


func _process_pending_loot(current_tick: int) -> void:
	_pending_deaths.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return int(left["entity_id"]) < int(right["entity_id"])
	)
	for death: Dictionary in _pending_deaths:
		var enemy_type: GameTypes.EnemyType = death["enemy_type"]
		var position: Vector2 = death["position"]
		match enemy_type:
			GameTypes.EnemyType.ELITE:
				loot_service.acquire_fixed_chests(3, position, current_tick)
			GameTypes.EnemyType.BOSS:
				loot_service.acquire_fixed_chests(8, position, current_tick)
			_:
				loot_service.try_normal_drop(position, current_tick)
	_pending_deaths.clear()


func _apply_player_damage_records(records: Array[Dictionary]) -> void:
	for record: Dictionary in records:
		var source_entity_id: int = int(record.get("source_entity_id", -1))
		var source_effect_id: StringName = StringName(record.get("source_effect_id", &"enemy"))
		var raw_damage: float = float(record.get("raw_damage", 0.0))
		var position: Vector2 = record.get("position", player_position) as Vector2
		var event: CombatEvent = event_router.create_primary(
			state,
			&"player_damage",
			source_entity_id,
			source_effect_id,
			raw_damage,
			position,
			Vector2.ZERO,
		)
		skill_system.register_hit(event)
		_apply_raw_player_damage(raw_damage)


func _apply_enemy_projectile_damage(records: Array[Dictionary]) -> void:
	for record: Dictionary in records:
		var raw_damage: float = float(record.get("damage", 0.0))
		var source_entity_id: int = int(record.get("source_entity_id", -1))
		var event: CombatEvent = event_router.create_primary(
			state,
			&"player_damage",
			source_entity_id,
			&"enemy_projectile",
			raw_damage,
			player_position,
			Vector2.ZERO,
		)
		skill_system.register_hit(event)
		_apply_raw_player_damage(raw_damage)


func _apply_raw_player_damage(raw_damage: float) -> void:
	var reduction: float = StatCalculator.effective_damage_reduction_pct(state.equipped)
	var final_damage: float = StatCalculator.apply_incoming_damage(raw_damage, reduction)
	state.current_hp = maxf(0.0, state.current_hp - final_damage)


func _latch_quota_without_countdown() -> void:
	if not state.wave_cleared and RunStateMachine.quota_reached(state, wave):
		state.wave_cleared = true


func _advance_fixture_contact_timers(
	ids: Array[int],
	delta: float,
	current_tick: int,
) -> void:
	for entity_id: int in ids:
		var enemy: EnemyEntity = enemy_system.enemy_store.get_by_id(entity_id)
		if (
			enemy == null
			or enemy.definition == null
			or not enemy.is_targetable(current_tick)
			or enemy.definition.contact_interval <= 0.0
		):
			continue
		enemy.contact_elapsed = TimerMath.advance_clamped(
			enemy.contact_elapsed,
			enemy.definition.contact_interval,
			delta,
		)
	_rebuild_uniform_grid(ids, current_tick)


func _rebuild_uniform_grid(ids: Array[int], current_tick: int) -> void:
	enemy_system.uniform_grid.clear()
	for entity_id: int in ids:
		var enemy: EnemyEntity = enemy_system.enemy_store.get_by_id(entity_id)
		if enemy != null and enemy.is_targetable(current_tick):
			enemy_system.uniform_grid.insert(entity_id, enemy.position)


func _build_hud_values() -> Dictionary:
	var main_weapon: ItemInstance = state.equipped.get(
		GameTypes.EquipmentSlot.MAIN_WEAPON,
		null,
	) as ItemInstance
	return {
		"wave_number": state.wave_number,
		"time_remaining": state.time_remaining,
		"wave_kills": state.wave_kills,
		"kill_quota": wave.kill_quota,
		"current_hp": state.current_hp,
		"max_hp": state.max_hp,
		"weapon_name": main_weapon.display_name if main_weapon != null else "木の棒",
		"wave_chests": state.wave_chests,
		"wave_cleared": state.wave_cleared,
		"boss_defeated": state.boss_defeated,
		"non_boss_spawned": state.non_boss_spawned,
		"active_enemy": enemy_system.enemy_store.active_count(),
		"active_projectile": projectile_pool.active_count(),
		"active_vfx": vfx_pool.active_count(),
		"active_chest": chest_visual_pool.active_count(),
		"enemy_pool_overflow": enemy_system.enemy_store.overflow_count,
		"projectile_pool_overflow": projectile_pool.overflow_count,
		"vfx_pool_overflow": vfx_pool.overflow_count,
		"skill_slots": skill_system.build_hud_slots(),
	}


func _equipped_main_weapon_type() -> GameTypes.MainWeaponType:
	var main_weapon: ItemInstance = state.equipped.get(
		GameTypes.EquipmentSlot.MAIN_WEAPON,
		null,
	) as ItemInstance
	return (
		main_weapon.main_weapon_type
		if main_weapon != null
		else GameTypes.MainWeaponType.UNCLASSIFIED
	)


func _enemy_height_scale(enemy_type: GameTypes.EnemyType) -> float:
	match enemy_type:
		GameTypes.EnemyType.FAST:
			return 0.65
		GameTypes.EnemyType.ARMORED:
			return 1.35
		GameTypes.EnemyType.RANGED:
			return 1.1
		GameTypes.EnemyType.ELITE:
			return 1.7
		GameTypes.EnemyType.BOSS:
			return 2.4
	return 1.0
