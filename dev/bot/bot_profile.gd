extends RefCounted

## Inclusive elapsed times. These wrappers are instantiated only on request.
var totals: Dictionary[StringName, Array] = {}

func record(label: StringName, started: int) -> void:
	var elapsed: int = Time.get_ticks_usec() - started
	if not totals.has(label):
		totals[label] = [0, 0]
	var previous: Array = totals[label]
	previous[0] += elapsed
	previous[1] += 1

func report() -> void:
	var labels: Array = totals.keys()
	labels.sort_custom(func(a: StringName, b: StringName) -> bool: return totals[a][0] > totals[b][0])
	for label: StringName in labels:
		var value: Array = totals[label]
		print("BOT_PROFILE %s ms=%.3f calls=%d" % [label, value[0] / 1000.0, value[1]])

func create_simulation() -> ProfiledSimulation:
	var sim := ProfiledSimulation.new()
	sim.timer = self
	sim.xp_pickup_pool = ProfiledXp.new()
	sim.xp_pickup_pool.timer = self
	sim.vfx_pool = ProfiledVfx.new()
	sim.vfx_pool.timer = self
	return sim


func instrument(previous: RefCounted, replacement: RefCounted) -> RefCounted:
	# Keep initialized state and RNGs; only replace dispatch with timed wrappers.
	for property: Dictionary in previous.get_property_list():
		if int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			replacement.set(property["name"], previous.get(property["name"]))
	replacement.timer = self
	return replacement

func create_controller(knowledge: RefCounted) -> ProfiledController:
	var controller := ProfiledController.new(knowledge)
	controller.timer = self
	return controller

func create_observer() -> ProfiledObserver:
	var observer := ProfiledObserver.new()
	observer.timer = self
	return observer


class ProfiledSimulation extends "res://dev/bot/recorded_simulation.gd":
	var timer: RefCounted

	func initialize(p_state: RunState, p_catalog: DefinitionCatalog) -> void:
		super(p_state, p_catalog)
		enemy_system = timer.instrument(enemy_system, ProfiledEnemies.new())
		enemy_system.uniform_grid = timer.instrument(enemy_system.uniform_grid, ProfiledGrid.new())
		weapon_system = timer.instrument(weapon_system, ProfiledWeapons.new())

	func advance_tick(move_input: Vector2) -> bool:
		var started: int = Time.get_ticks_usec()
		var result: bool = super(move_input)
		timer.record(&"combat_simulation.advance_tick", started)
		return result

	func _process_pending_deaths(current_tick: int) -> void:
		var started: int = Time.get_ticks_usec()
		super(current_tick)
		timer.record(&"combat_simulation._process_pending_deaths", started)

	func _apply_enemy_hit_records(records: Array[Dictionary]) -> void:
		var started: int = Time.get_ticks_usec()
		super(records)
		timer.record(&"combat_simulation._apply_enemy_hit_records", started)

	func _flush_transient_feedback() -> void:
		var started: int = Time.get_ticks_usec()
		super()
		timer.record(&"combat_simulation._flush_transient_feedback", started)

	func _record_audio_cue_metrics() -> void:
		var started: int = Time.get_ticks_usec()
		super()
		timer.record(&"combat_simulation._record_audio_cue_metrics", started)

	func _record_visible_enemy_sample(current_tick: int) -> void:
		var started: int = Time.get_ticks_usec()
		super(current_tick)
		timer.record(&"combat_simulation._record_visible_enemy_sample", started)

	func _apply_passive_recovery() -> void:
		var started: int = Time.get_ticks_usec()
		super()
		timer.record(&"combat_simulation._apply_passive_recovery", started)

	func _damage_nodes_from_projectiles(entries: Array[PackedInt64Array], current_tick: int) -> void:
		var started: int = Time.get_ticks_usec()
		super(entries, current_tick)
		timer.record(&"combat_simulation._damage_nodes_from_projectiles", started)

	func _apply_snapshot_markers(snapshot: CombatSnapshot) -> void:
		var started: int = Time.get_ticks_usec()
		super(snapshot)
		timer.record(&"combat_simulation._apply_snapshot_markers", started)

class ProfiledEnemies extends EnemySystem:
	var timer: RefCounted

	func advance_snapshot(ids: Array[int], player_position: Vector2, current_tick: int,) -> Array[int]:
		var started: int = Time.get_ticks_usec()
		var result: Array[int] = super(ids, player_position, current_tick)
		timer.record(&"enemy_system.advance_snapshot", started)
		return result

	func accrue_spawn_credit() -> void:
		var started: int = Time.get_ticks_usec()
		super()
		timer.record(&"enemy_system.accrue_spawn_credit", started)

	func resolve_normal_spawns(player_position: Vector2, current_tick: int) -> Array[EnemyEntity]:
		var started: int = Time.get_ticks_usec()
		var result: Array[EnemyEntity] = super(player_position, current_tick)
		timer.record(&"enemy_system.resolve_normal_spawns", started)
		return result

	func resolve_swarm_event_spawns(player_position: Vector2, current_tick: int,) -> Array[EnemyEntity]:
		var started: int = Time.get_ticks_usec()
		var result: Array[EnemyEntity] = super(player_position, current_tick)
		timer.record(&"enemy_system.resolve_swarm_event_spawns", started)
		return result

	func resolve_contact_damage_candidates(ids: Array[int], player_position: Vector2, current_tick: int,) -> Array[Dictionary]:
		var started: int = Time.get_ticks_usec()
		var result: Array[Dictionary] = super(ids, player_position, current_tick)
		timer.record(&"enemy_system.resolve_contact_damage_candidates", started)
		return result

	func resolve_ready_enemy_special_actions(ids: Array[int], _player_position: Vector2, current_tick: int, projectile_pool: ProjectilePool,) -> void:
		var started: int = Time.get_ticks_usec()
		super(ids, _player_position, current_tick, projectile_pool)
		timer.record(&"enemy_system.resolve_ready_enemy_special_actions", started)

	func _resolve_enemy_collisions(ids: Array[int], current_tick: int) -> void:
		var started: int = Time.get_ticks_usec()
		super(ids, current_tick)
		timer.record(&"enemy_system._resolve_enemy_collisions", started)

	func _rebuild_grid(current_tick: int) -> void:
		var started: int = Time.get_ticks_usec()
		super(current_tick)
		timer.record(&"enemy_system._rebuild_grid", started)

class ProfiledWeapons extends WeaponSystem:
	var timer: RefCounted

	func advance_and_fire(player_position: Vector2, enemy_store: EnemyStore, uniform_grid: UniformGrid, current_tick: int,) -> Array[Dictionary]:
		var started: int = Time.get_ticks_usec()
		var result: Array[Dictionary] = super(player_position, enemy_store, uniform_grid, current_tick)
		timer.record(&"weapon_system.advance_and_fire", started)
		return result

	func move_snapshot_projectiles(entries: Array[PackedInt64Array], enemy_store: EnemyStore, player_position: Vector2, current_tick: int, stop_active: bool,) -> void:
		var started: int = Time.get_ticks_usec()
		super(entries, enemy_store, player_position, current_tick, stop_active)
		timer.record(&"weapon_system.move_snapshot_projectiles", started)

	func _first_target(enemy_store: EnemyStore, sort_origin: Vector2, player_position: Vector2, current_tick: int,) -> EnemyEntity:
		var started: int = Time.get_ticks_usec()
		var result: EnemyEntity = super(enemy_store, sort_origin, player_position, current_tick)
		timer.record(&"weapon_system._first_target", started)
		return result

class ProfiledXp extends XpPickupPool:
	var timer: RefCounted

	func advance_and_collect(player_position: Vector2, delta: float, current_tick: int) -> int:
		var started: int = Time.get_ticks_usec()
		var result: int = super(player_position, delta, current_tick)
		timer.record(&"xp_pickup_pool.advance_and_collect", started)
		return result

	func visual_slot_indices() -> PackedInt32Array:
		var started: int = Time.get_ticks_usec()
		var result: PackedInt32Array = super()
		timer.record(&"xp_pickup_pool.visual_slot_indices", started)
		return result

class ProfiledGrid extends UniformGrid:
	var timer: RefCounted

	func query_aabb_candidates(aabb_min: Vector2, aabb_max: Vector2) -> Array[int]:
		var started: int = Time.get_ticks_usec()
		var result: Array[int] = super(aabb_min, aabb_max)
		timer.record(&"uniform_grid.query_aabb_candidates", started)
		return result

class ProfiledVfx extends VfxPool:
	var timer: RefCounted

	func advance(delta: float, current_tick: int) -> void:
		var started: int = Time.get_ticks_usec()
		super(delta, current_tick)
		timer.record(&"vfx_pool.advance", started)

	func request(position: Vector2, scale_m: float, lifetime: float, color: Color, born_tick: int, priority: int = PRIORITY_GENERIC, effect_kind: VfxState.EffectKind = VfxState.EffectKind.GENERIC, direction: Vector2 = Vector2.RIGHT, sweep_sign: float = 1.0, evolved: bool = false,) -> VfxState:
		var started: int = Time.get_ticks_usec()
		var result: VfxState = super(position, scale_m, lifetime, color, born_tick, priority, effect_kind, direction, sweep_sign, evolved)
		timer.record(&"vfx_pool.request", started)
		return result

class ProfiledController extends "res://dev/bot/bot_controller.gd":
	var timer: RefCounted

	func _observe_bodies(observation: BotObservation, inverse: Transform3D, contact_damage: Dictionary[int, float]) -> void:
		var started: int = Time.get_ticks_usec()
		super(observation, inverse, contact_damage)
		timer.record(&"bot_controller._observe_bodies", started)

	func _remember_loot(observation: BotObservation, inverse: Transform3D) -> void:
		var started: int = Time.get_ticks_usec()
		super(observation, inverse)
		timer.record(&"bot_controller._remember_loot", started)

	func _choose_target(observation: BotObservation) -> void:
		var started: int = Time.get_ticks_usec()
		super(observation)
		timer.record(&"bot_controller._choose_target", started)

	func _route_to_goal(player: Vector2) -> void:
		var started: int = Time.get_ticks_usec()
		super(player)
		timer.record(&"bot_controller._route_to_goal", started)

	func _choose_move(observation: BotObservation, contact_damage: Dictionary[int, float]) -> Vector2:
		var started: int = Time.get_ticks_usec()
		var result: Vector2 = super(observation, contact_damage)
		timer.record(&"bot_controller._choose_move", started)
		return result


class ProfiledObserver extends "res://dev/bot/bot_observer.gd":
	var timer: RefCounted

	func _capture_enemies(simulation: CombatSimulation, culler: Culler, observation: BotObservation) -> void:
		var started: int = Time.get_ticks_usec()
		super(simulation, culler, observation)
		timer.record(&"bot_observer._capture_enemies", started)

	func _capture_projectiles(simulation: CombatSimulation, culler: Culler, observation: BotObservation) -> void:
		var started: int = Time.get_ticks_usec()
		super(simulation, culler, observation)
		timer.record(&"bot_observer._capture_projectiles", started)

	func _capture_xp(simulation: CombatSimulation, culler: Culler, observation: BotObservation) -> void:
		var started: int = Time.get_ticks_usec()
		super(simulation, culler, observation)
		timer.record(&"bot_observer._capture_xp", started)

	func _capture_arena_loot(simulation: CombatSimulation, culler: Culler, observation: BotObservation) -> void:
		var started: int = Time.get_ticks_usec()
		super(simulation, culler, observation)
		timer.record(&"bot_observer._capture_arena_loot", started)

	func _capture_warnings(simulation: CombatSimulation, culler: Culler, observation: BotObservation) -> void:
		var started: int = Time.get_ticks_usec()
		super(simulation, culler, observation)
		timer.record(&"bot_observer._capture_warnings", started)
