class_name CombatSimulation
extends RefCounted


const FIXED_DELTA_SECONDS: float = 1.0 / 60.0
const PLAYER_SPEED: float = 5.0
const PLAYER_RADIUS: float = 0.45
const ARENA_MIN: Vector2 = Vector2(-19.55, -19.55)
const ARENA_MAX: Vector2 = Vector2(19.55, 19.55)
const VFX_HEIGHT_M: float = 0.03
const DEATH_VFX_LIFETIME: float = 0.22
const ATTACK_VFX_LIFETIME: float = 0.12
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
const PERFORMANCE_INVULNERABLE_UNTIL_TICK: int = 2_000_000_000

var state: RunState = null
var catalog: DefinitionCatalog = null
var player_position: Vector2 = Vector2.ZERO
var enemy_system: EnemySystem = EnemySystem.new()
var projectile_pool: ProjectilePool = ProjectilePool.new()
var vfx_pool: VfxPool = VfxPool.new()
var xp_pickup_pool: XpPickupPool = XpPickupPool.new()
var arena_object_system: ArenaObjectSystem = ArenaObjectSystem.new()
var event_router: CombatEventRouter = CombatEventRouter.new()
var weapon_system: WeaponSystem = WeaponSystem.new()

var freeze_all_updates: bool = false

var _manifest: SurvivalContentManifest = null
var _pending_deaths: Array[Dictionary] = []
var _pending_death_ids: Dictionary[int, bool] = {}
var _step_events: Array[StringName] = []
var _vacuum_collecting: bool = false
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
var _performance_vfx_serial: int = 0
var _performance_xp_serial: int = 0


func initialize(p_state: RunState, p_catalog: DefinitionCatalog) -> void:
	state = p_state
	catalog = p_catalog
	_manifest = catalog.manifest()
	player_position = Vector2.ZERO
	freeze_all_updates = false
	projectile_pool.clear()
	vfx_pool.clear()
	xp_pickup_pool.configure(_manifest)
	xp_pickup_pool.clear()
	event_router = CombatEventRouter.new()
	enemy_system = EnemySystem.new()
	enemy_system.initialize(state, catalog)
	weapon_system = WeaponSystem.new()
	weapon_system.initialize(state, catalog, projectile_pool, event_router)
	arena_object_system = ArenaObjectSystem.new()
	arena_object_system.initialize(state, catalog)
	_pending_deaths.clear()
	_pending_death_ids.clear()
	_step_events.clear()
	_vacuum_collecting = false
	_reset_performance_fixture_state()
	_refresh_derived_player_stats()


func step(move_input: Vector2, _delta: float = FIXED_DELTA_SECONDS) -> CombatSnapshot:
	advance_tick(move_input)
	return build_snapshot()


func advance_tick(move_input: Vector2) -> bool:
	_step_events.clear()
	if state == null or catalog == null or state.phase != GameTypes.RunPhase.COMBAT:
		return false
	if freeze_all_updates and not _performance_fixture_active:
		return false
	state.combat_tick += 1
	var current_tick: int = state.combat_tick
	_pending_deaths.clear()
	_pending_death_ids.clear()
	var enemy_snapshot: Array[int] = enemy_system.snapshot_ids()
	var projectile_snapshot: Array[Vector2i] = projectile_pool.snapshot_active()
	var tracked_enemy_id: int = -1
	var tracked_enemy_position: Vector2 = Vector2.ZERO
	var tracked_projectile_entry: Vector2i = Vector2i(-1, -1)
	var tracked_projectile_position: Vector2 = Vector2.ZERO
	if _performance_fixture_active and not enemy_snapshot.is_empty():
		tracked_enemy_id = enemy_snapshot[0]
		var tracked_enemy: EnemyEntity = enemy_system.enemy_store.get_by_id(
			tracked_enemy_id
		)
		if tracked_enemy != null:
			tracked_enemy_position = tracked_enemy.position
	if _performance_fixture_active and not projectile_snapshot.is_empty():
		tracked_projectile_entry = projectile_snapshot[0]
		var tracked_projectile: ProjectileState = projectile_pool.resolve_snapshot_entry(
			tracked_projectile_entry
		)
		if tracked_projectile != null:
			tracked_projectile_position = tracked_projectile.position

	# 1. Player movement and pickups.
	_move_player(move_input)
	_collect_arena_pickups(current_tick)
	var collected_xp: int = xp_pickup_pool.advance_and_collect(
		player_position,
		FIXED_DELTA_SECONDS,
		current_tick,
		_vacuum_collecting,
	)
	if collected_xp > 0:
		ProgressionService.add_xp(state, collected_xp, catalog)
		_step_events.append(&"xp_pickup")
	if _vacuum_collecting and xp_pickup_pool.active_count() == 0:
		_vacuum_collecting = false
	arena_object_system.advance(current_tick)

	# 2. Enemy update and time-driven spawns.
	enemy_system.advance_snapshot(enemy_snapshot, player_position, current_tick)
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
	var scheduled_spawns: Array[EnemyEntity] = enemy_system.resolve_scheduled_spawns(
		player_position,
		current_tick,
	)
	for spawned: EnemyEntity in scheduled_spawns:
		if spawned.enemy_type == GameTypes.EnemyType.BOSS:
			_step_events.append(&"boss_spawn")
	enemy_system.resolve_normal_spawns(player_position, current_tick)
	enemy_system.resolve_ready_boss_summons(enemy_snapshot, current_tick)

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
	for projectile_entry: Vector2i in projectile_snapshot:
		if _performance_fixture_active:
			_performance_projectile_collision_resolutions += 1
		var projectile_resolution: Dictionary = {}
		var hit_records: Array[Dictionary] = weapon_system.resolve_ally_projectile(
			projectile_entry,
			enemy_system.enemy_store,
			enemy_system.uniform_grid,
			current_tick,
			projectile_resolution,
		)
		_damage_nodes_from_projectile_resolution(
			projectile_resolution,
			current_tick,
		)
		_apply_enemy_hit_records(hit_records)
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
		_emit_attack_vfx(attack, current_tick)
		_damage_nodes_from_attack(attack, current_tick)
		_apply_resolution_hits(attack)

	# 4. Enemy damage and special actions. Lethal allied hits remain pending so an
	# action that was already ready this tick still resolves before the death stage.
	_apply_player_damage_records(enemy_system.resolve_ready_enemy_damage_actions(
		enemy_snapshot,
		player_position,
		current_tick,
	))
	for projectile_entry: Vector2i in projectile_snapshot:
		var enemy_projectile_hit: Dictionary = weapon_system.resolve_enemy_projectile(
			projectile_entry,
			player_position,
			current_tick,
		)
		if not enemy_projectile_hit.is_empty():
			_apply_raw_player_damage(float(enemy_projectile_hit.get("damage", 0.0)))
	enemy_system.resolve_ready_enemy_special_actions(
		enemy_snapshot,
		player_position,
		current_tick,
		projectile_pool,
	)

	# 5. Death drops, passive recovery, and terminal/modal priority.
	_process_pending_deaths(current_tick)
	_apply_passive_recovery()
	var victory: bool = state.boss_defeated
	var player_dead: bool = state.current_hp <= 0.0
	RunStateMachine.resolve_terminal(state, player_dead, victory)
	if state.phase == GameTypes.RunPhase.COMBAT:
		_resolve_modal_priority()
	if _performance_fixture_active and state.phase == GameTypes.RunPhase.COMBAT:
		_performance_workload_ticks += 1
		_maintain_performance_fixture(current_tick)
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
	_refresh_derived_player_stats()
	_continue_after_modal()
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
	_refresh_derived_player_stats()
	_continue_after_modal()
	return true


func complete_chest_reward() -> bool:
	return skip_chest_animation()


func grant_resume_invulnerability_ticks(ticks: int = 45) -> void:
	if ticks <= 0:
		return
	# The grant occurs between ticks. With an exclusive deadline, T+1 through T+ticks
	# require a deadline of T+ticks+1 to protect exactly `ticks` combat updates.
	RunStateMachine.grant_modal_resume_invulnerability(state, ticks + 1)


func configure_accessibility(reduce_motion: bool, reduce_flashes: bool) -> void:
	vfx_pool.reduce_motion = reduce_motion
	vfx_pool.reduce_flashes = reduce_flashes


func build_snapshot() -> CombatSnapshot:
	if state == null or catalog == null:
		return CombatSnapshot.new()
	var enemy_transforms: Array[Transform3D] = []
	for entity_id: int in enemy_system.enemy_store.snapshot_ids_sorted():
		var enemy: EnemyEntity = enemy_system.enemy_store.get_by_id(entity_id)
		if enemy == null:
			continue
		var diameter_scale: float = maxf(0.35, enemy.body_radius() / 0.4)
		var height_scale: float = _enemy_height_scale(enemy.enemy_type)
		enemy_transforms.append(Transform3D(
			Basis.IDENTITY.scaled(Vector3(diameter_scale, height_scale, diameter_scale)),
			Vector3(enemy.position.x, 0.5 * height_scale, enemy.position.y),
		))
	var projectile_transforms: Array[Transform3D] = []
	for pool_index: int in projectile_pool.active_indices_snapshot():
		var projectile: ProjectileState = projectile_pool.slots[pool_index]
		var projectile_scale: float = maxf(0.25, projectile.radius / 0.16)
		projectile_transforms.append(Transform3D(
			Basis.IDENTITY.scaled(Vector3.ONE * projectile_scale),
			Vector3(
				projectile.position.x,
				projectile.visual_height(),
				projectile.position.y,
			),
		))
	projectile_transforms.append_array(weapon_system.orbital_transforms(
		player_position,
		state.combat_tick,
	))
	var vfx_transforms: Array[Transform3D] = []
	var vfx_colors: Array[Color] = []
	var vfx_custom_data: Array[Color] = []
	for pool_index: int in vfx_pool.active_indices_snapshot():
		var vfx: VfxState = vfx_pool.slots[pool_index]
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
		xp_pickup_pool.transforms(),
		arena_object_system.powerup_transforms(),
		arena_object_system.node_transforms(),
	)
	_step_events.clear()
	return snapshot


func spawn_fixture_enemy(
	enemy_type: GameTypes.EnemyType,
	position: Vector2,
	born_tick: int = -1,
	apply_time_multiplier: bool = false,
	summoned_by_boss: bool = false,
) -> EnemyEntity:
	var definition: EnemyDefinition = catalog.enemy_for_type(enemy_type)
	if definition == null:
		return null
	var segment: EnemySegmentDefinition = catalog.segment_for_tick(state.combat_tick)
	var hp_multiplier: float = segment.hp_multiplier if apply_time_multiplier and segment != null else 1.0
	var damage_multiplier: float = segment.damage_multiplier if apply_time_multiplier and segment != null else 1.0
	if apply_time_multiplier and enemy_type == GameTypes.EnemyType.BOSS:
		hp_multiplier = _manifest.boss_hp_multiplier
		damage_multiplier = _manifest.boss_damage_multiplier
	var resolved_born_tick: int = state.combat_tick - 1 if born_tick < 0 else born_tick
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
	_reset_performance_fixture_state()
	if (
		state == null
		or enemy_count < 0
		or enemy_count > EnemyStore.CAPACITY
		or projectile_count < 0
		or projectile_count > ProjectilePool.CAPACITY
		or vfx_count < 0
		or vfx_count > VfxPool.CAPACITY
		or xp_count < 0
		or xp_count > xp_pickup_pool.capacity
	):
		return false
	_performance_enemy_target = enemy_count
	_performance_projectile_target = projectile_count
	_performance_vfx_target = vfx_count
	_performance_xp_target = xp_count
	enemy_system.enemy_store.clear()
	projectile_pool.clear()
	vfx_pool.clear()
	xp_pickup_pool.clear()
	enemy_system.enemy_store.overflow_count = 0
	projectile_pool.overflow_count = 0
	vfx_pool.overflow_count = 0
	state.next_entity_id = 1
	state.phase = GameTypes.RunPhase.COMBAT
	state.current_hp = state.max_hp
	state.pending_level_ups = 0
	state.active_level_offer = null
	state.pending_chest_sources.clear()
	state.active_chest_outcome = null
	state.build_maxed = true
	state.boss_spawned = true
	state.boss_defeated = false
	state.boss_phase = 0
	state.boss_enrage_stacks = 0
	state.boss_hp = 0.0
	state.boss_max_hp = 0.0
	state.stop_until_tick = 0
	state.damage_invulnerable_until_tick = PERFORMANCE_INVULNERABLE_UNTIL_TICK
	state.modal_invulnerable_until_tick = PERFORMANCE_INVULNERABLE_UNTIL_TICK
	state.spawn_credit = 0.0
	state.weapon_damage_by_lineage.clear()
	state.recent_damage_samples.clear()
	enemy_system._elite_spawned.fill(1)
	_vacuum_collecting = false
	for index: int in range(enemy_count):
		if not _spawn_performance_enemy(index, state.combat_tick - 1):
			return false
	for index: int in range(projectile_count):
		if not _spawn_performance_projectile(index, state.combat_tick - 1):
			return false
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
	player_position += normalized_input * PLAYER_SPEED * FIXED_DELTA_SECONDS
	player_position = Vector2(
		clampf(player_position.x, ARENA_MIN.x, ARENA_MAX.x),
		clampf(player_position.y, ARENA_MIN.y, ARENA_MAX.y),
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
				_vacuum_collecting = bool(vacuum_result.get(&"vacuum", false))
			ArenaPickup.Kind.STOP:
				NodeDropService.apply_drop(state, catalog, GameTypes.NodeDropType.STOP)
				_step_events.append(&"stop_pickup")


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
		state.record_weapon_damage(event.source_effect_id, applied_damage)
		var life_steal_ratio: float = weapon_system.life_steal_for_lineage(event.source_effect_id)
		if life_steal_ratio > 0.0:
			state.current_hp = minf(
				state.max_hp,
				state.current_hp + applied_damage * life_steal_ratio,
			)
		if enemy.enemy_type == GameTypes.EnemyType.BOSS:
			state.boss_hp = enemy.hp
		if enemy.hp <= 0.0:
			_record_enemy_death(enemy)


func _record_enemy_death(enemy: EnemyEntity) -> void:
	if _pending_death_ids.has(enemy.entity_id):
		return
	_pending_death_ids[enemy.entity_id] = true
	_pending_deaths.append({
		"entity_id": enemy.entity_id,
		"enemy_type": enemy.enemy_type,
		"position": enemy.position,
		"body_radius": enemy.body_radius(),
		"xp_value": enemy.definition.xp_value,
		"elite_serial": enemy.elite_serial,
	})


func _process_pending_deaths(current_tick: int) -> void:
	_pending_deaths.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return int(left["entity_id"]) < int(right["entity_id"])
	)
	for death: Dictionary in _pending_deaths:
		var entity_id: int = int(death["entity_id"])
		var enemy: EnemyEntity = enemy_system.enemy_store.get_by_id(entity_id)
		if enemy == null or not enemy_system.enemy_store.remove(entity_id):
			continue
		var position: Vector2 = death["position"]
		vfx_pool.acquire(
			position,
			maxf(0.5, float(death["body_radius"]) * 2.0),
			DEATH_VFX_LIFETIME,
			Color(1.0, 0.28, 0.2, 0.82),
			current_tick,
		)
		state.total_kills += 1
		match int(death["enemy_type"]):
			GameTypes.EnemyType.ELITE:
				state.elite_kills += 1
			GameTypes.EnemyType.BOSS:
				state.boss_kills += 1
				state.boss_defeated = true
				state.boss_hp = 0.0
			_:
				state.normal_kills += 1
		xp_pickup_pool.acquire(
			position,
			maxi(1, int(death["xp_value"])),
			current_tick,
			player_position,
		)
		if death["enemy_type"] == GameTypes.EnemyType.ELITE:
			arena_object_system.spawn_chest(position, int(death["elite_serial"]))
	_pending_deaths.clear()
	_pending_death_ids.clear()


func _apply_player_damage_records(records: Array[Dictionary]) -> void:
	for record: Dictionary in records:
		var source_entity_id: int = int(record.get("source_entity_id", -1))
		if source_entity_id >= 0 and not enemy_system.enemy_store.has_entity(source_entity_id):
			continue
		_apply_raw_player_damage(float(record.get("raw_damage", 0.0)))


func _apply_raw_player_damage(raw_damage: float) -> void:
	if raw_damage <= 0.0 or state.is_invulnerable():
		return
	state.current_hp = maxf(0.0, state.current_hp - raw_damage)
	state.damage_invulnerable_until_tick = maxi(
		state.damage_invulnerable_until_tick,
		state.combat_tick + _manifest.damage_invulnerability_ticks + 1,
	)
	_step_events.append(&"player_hit")


func _apply_passive_recovery() -> void:
	var stats: Dictionary = StatCalculator.aggregate(state, catalog)
	var recovery: float = StatCalculator.recovery_per_second(stats)
	if recovery > 0.0 and state.current_hp > 0.0:
		state.current_hp = minf(
			state.max_hp,
			state.current_hp + recovery * FIXED_DELTA_SECONDS,
		)


func _damage_nodes_from_projectiles(entries: Array[Vector2i], current_tick: int) -> void:
	for entry: Vector2i in entries:
		var projectile: ProjectileState = projectile_pool.resolve_snapshot_entry(entry)
		if projectile == null or projectile.faction != ProjectileState.FACTION_ALLY:
			continue
		# Arc crystals only affect nodes with their one resolved impact explosion.
		# Their airborne path must not behave like a piercing straight projectile.
		if projectile.movement_kind == ProjectileState.MovementKind.ARC:
			continue
		arena_object_system.damage_nodes_segment(
			projectile.previous_position,
			projectile.position,
			projectile.radius,
			projectile.damage,
			current_tick,
			projectile.hit_node_sites,
		)


func _damage_nodes_from_projectile_resolution(
	resolution: Dictionary,
	current_tick: int,
) -> void:
	if not resolution.has(&"arc_impact_position"):
		return
	arena_object_system.damage_nodes_circle(
		resolution.get(&"arc_impact_position", Vector2.ZERO),
		float(resolution.get(&"arc_explosion_radius", 0.0)),
		float(resolution.get(&"arc_damage", 0.0)),
		current_tick,
	)


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


func _emit_attack_vfx(attack: Dictionary, current_tick: int) -> void:
	if not bool(attack.get("generated", false)):
		return
	var origin: Vector2 = attack.get("origin", player_position)
	var direction: Vector2 = attack.get("direction", Vector2.RIGHT)
	var range_m: float = maxf(0.4, float(attack.get("range_m", 1.0)))
	vfx_pool.acquire(
		origin + direction.normalized() * range_m * 0.4,
		minf(4.0, range_m),
		ATTACK_VFX_LIFETIME,
		Color(0.25, 0.88, 1.0, 0.72),
		current_tick,
	)


func _resolve_modal_priority() -> void:
	if state.pending_level_ups > 0:
		if ProgressionService.create_offer(state, catalog) != null:
			RunStateMachine.transition(state, GameTypes.RunPhase.LEVEL_UP)
			return
	if not state.pending_chest_sources.is_empty():
		if ChestRewardService.create_outcome(state, catalog) != null:
			RunStateMachine.transition(state, GameTypes.RunPhase.CHEST_REWARD)


func _continue_after_modal() -> void:
	if state.pending_level_ups > 0:
		ProgressionService.create_offer(state, catalog)
		state.phase = GameTypes.RunPhase.LEVEL_UP
		return
	if not state.pending_chest_sources.is_empty():
		ChestRewardService.create_outcome(state, catalog)
		state.phase = GameTypes.RunPhase.CHEST_REWARD
		return
	state.phase = GameTypes.RunPhase.COMBAT
	grant_resume_invulnerability_ticks(_manifest.modal_resume_invulnerability_ticks)


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
		"xp_for_next_level": 0 if state.build_maxed else ProgressionService.xp_required_for_level(state.level),
		"build_maxed": state.build_maxed,
		"total_kills": state.total_kills,
		"weapons": weapon_system.build_hud_weapons(),
		"passives": passives,
		"boss_active": state.boss_spawned and not state.boss_defeated,
		"boss_hp": state.boss_hp,
		"boss_max_hp": state.boss_max_hp,
		"boss_phase": state.boss_phase,
		"boss_enrage_stacks": state.boss_enrage_stacks,
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
		"xp_pool_overflow_merges": xp_pickup_pool.overflow_merge_count,
		"events": _step_events.duplicate(),
	}


func _reset_performance_fixture_state() -> void:
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
	while projectile_pool.active_count() > _performance_projectile_target:
		var indices: Array[int] = projectile_pool.active_indices_snapshot()
		if indices.is_empty():
			break
		var pool_index: int = indices.back()
		var projectile: ProjectileState = projectile_pool.slots[pool_index]
		if not projectile_pool.release(pool_index, projectile.generation):
			break
	while projectile_pool.active_count() < _performance_projectile_target:
		if not _spawn_performance_projectile(
			_performance_projectile_serial,
			current_tick,
		):
			break
		_performance_projectile_serial += 1


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
		false,
	)
	if enemy == null:
		return false
	enemy.max_hp = PERFORMANCE_FIXTURE_HP
	enemy.hp = PERFORMANCE_FIXTURE_HP
	return true


func _spawn_performance_projectile(serial: int, born_tick: int) -> bool:
	if _performance_projectile_target <= 0:
		return false
	var fixture_index: int = serial % _performance_projectile_target
	var position: Vector2 = _performance_position(
		fixture_index,
		_performance_projectile_target,
		0.18,
	)
	var angle: float = TAU * float(serial % 360) / 360.0
	var direction: Vector2 = Vector2.from_angle(angle)
	return projectile_pool.acquire(
		ProjectileState.FACTION_ALLY,
		&"performance",
		-1,
		position,
		direction * PERFORMANCE_PROJECTILE_SPEED,
		0.16,
		0.0,
		PERFORMANCE_PROJECTILE_DISTANCE,
		PERFORMANCE_FIXTURE_LIFETIME_SECONDS,
		position + direction * PERFORMANCE_PROJECTILE_DISTANCE,
		8,
		born_tick,
		&"performance",
		ProjectileState.MovementKind.STRAIGHT,
		-1,
		roundi(
			PERFORMANCE_FIXTURE_LIFETIME_SECONDS
			* float(RunState.TICKS_PER_SECOND)
		),
	) != null


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
		lerpf(ARENA_MIN.x + 0.25, ARENA_MAX.x - 0.25, x_ratio) + offset,
		lerpf(ARENA_MIN.y + 0.25, ARENA_MAX.y - 0.25, y_ratio),
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
			definition.lineage_id,
			false,
			state.rng_streams.create_weapon_rng(definition.lineage_id, state.weapons.size()),
		)
		runtime.level = definition.max_level
		runtime.ready_on_resume = true
		state.weapons.append(runtime)
	weapon_system.initialize(state, catalog, projectile_pool, event_router)


func _rebuild_uniform_grid(current_tick: int) -> void:
	enemy_system.uniform_grid.clear()
	for enemy: EnemyEntity in enemy_system.enemy_store.entities:
		if enemy.is_targetable(current_tick):
			enemy_system.uniform_grid.insert(enemy.entity_id, enemy.position)


func _enemy_height_scale(enemy_type: GameTypes.EnemyType) -> float:
	match enemy_type:
		GameTypes.EnemyType.SWARMER:
			return 0.65
		GameTypes.EnemyType.BULWARK:
			return 1.35
		GameTypes.EnemyType.SHOOTER:
			return 1.1
		GameTypes.EnemyType.ELITE:
			return 1.7
		GameTypes.EnemyType.BOSS:
			return 2.4
	return 1.0
