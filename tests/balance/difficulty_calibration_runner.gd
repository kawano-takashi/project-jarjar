extends SceneTree


const BotScript = preload("res://tests/balance/difficulty_calibration_bot.gd")
const AcceptanceScript = preload("res://tests/balance/difficulty_acceptance.gd")

const BALANCE_REVISION: int = 5
const RUN_SEEDS: Array[int] = [17, 29, 43, 61]
const POLICIES: Array[int] = [0, 1, 2]
const CHECKPOINT_TICKS: Array[int] = [
	7_200,
	10_800,
	14_400,
	18_000,
	21_600,
	25_200,
	28_800,
	36_000,
]
const MAX_COMBAT_TICK: int = 54_000
const MAX_MODAL_CHAIN: int = 128
const RUNNER_TIMEOUT_MS: int = 1_200_000
const OUTPUT_ROOT: String = "res://artifacts/balance/revision-5"
const RUNS_FILENAME: String = "difficulty-runs.csv"
const CHECKPOINTS_FILENAME: String = "difficulty-checkpoints.csv"
const SUMMARY_FILENAME: String = "difficulty-summary.txt"
const RUN_COLUMNS: Array[String] = [
	"balance_revision",
	"policy",
	"seed",
	"outcome",
	"terminal_tick",
	"terminal_seconds",
	"boss_reached",
	"boss_cleared",
	"death_before_two_minutes",
	"first_evolution_tick",
	"first_evolution_minutes",
	"final_hp",
	"final_max_hp",
	"minimum_hp_ratio",
	"final_level",
	"final_xp",
	"total_kills",
	"elite_kills",
	"opened_chests",
	"evolution_count",
	"damage_tick_count",
	"net_damage_taken",
	"boss_hp",
	"boss_max_hp",
	"weapon_hits",
	"weapon_kills",
	"visible_weapon_hits",
	"visible_weapon_kills",
	"offscreen_weapon_hits",
	"offscreen_weapon_kills",
	"max_hit_center_distance",
	"max_kill_center_distance",
	"max_effect_outer_distance",
	"peak_visible_enemies",
	"mean_visible_enemies",
	"peak_engaged_enemies",
	"mean_engaged_enemies",
	"peak_materializing_enemies",
	"mean_materializing_enemies",
	"absorbed_normal_count",
	"absorbed_enemy_projectile_count",
	"feedback_emitted",
	"feedback_suppressed",
	"vfx_admitted",
	"vfx_suppressed",
	"important_vfx_dropped",
	"audio_admitted",
	"audio_suppressed",
	"enemy_pool_overflow",
	"projectile_pool_overflow",
	"vfx_pool_overflow",
	"xp_overflow_merges",
	"pool_overflow_count",
	"pool_orphan_count",
	"digest",
]
const VISIBLE_METRIC_KEYS: Array[String] = [
	"weapon_hits",
	"weapon_kills",
	"visible_weapon_hits",
	"visible_weapon_kills",
	"offscreen_weapon_hits",
	"offscreen_weapon_kills",
	"max_hit_center_distance",
	"max_kill_center_distance",
	"max_effect_outer_distance",
	"peak_visible_enemies",
	"mean_visible_enemies",
	"peak_engaged_enemies",
	"mean_engaged_enemies",
	"peak_materializing_enemies",
	"mean_materializing_enemies",
	"absorbed_normal_count",
	"absorbed_enemy_projectile_count",
	"feedback_emitted",
	"feedback_suppressed",
	"vfx_admitted",
	"vfx_suppressed",
	"important_vfx_dropped",
	"audio_admitted",
	"audio_suppressed",
]
const CHECKPOINT_COLUMNS: Array[String] = [
	"balance_revision",
	"policy",
	"seed",
	"checkpoint_tick",
	"observed_tick",
	"alive",
	"hp",
	"max_hp",
	"hp_ratio",
	"level",
	"xp",
	"total_kills",
	"elite_kills",
	"opened_chests",
	"evolution_count",
	"active_enemies",
	"active_projectiles",
	"active_xp",
	"boss_reached",
	"boss_hp",
	"boss_max_hp",
]

var _runner_started_ms: int = 0


func _initialize() -> void:
	_runner_started_ms = Time.get_ticks_msec()
	_run()


func _run() -> void:
	if not OS.get_cmdline_user_args().is_empty():
		print("DIFFICULTY_CALIBRATION_ERROR reason=arguments_not_allowed")
		quit(2)
		return
	var setup: Dictionary = _load_catalog()
	if not bool(setup.get("valid", false)):
		print("DIFFICULTY_CALIBRATION_ERROR reason=%s" % str(setup.get("reason", "catalog")))
		quit(2)
		return
	var catalog: DefinitionCatalog = setup.get("catalog") as DefinitionCatalog
	var run_rows: Array[Dictionary] = []
	var checkpoint_rows: Array[Dictionary] = []
	var infrastructure_error: String = ""
	for policy_value: int in POLICIES:
		for run_seed: int in RUN_SEEDS:
			var run_result: Dictionary = _run_one(
				catalog,
				policy_value,
				run_seed,
				checkpoint_rows,
			)
			infrastructure_error = str(run_result.get("infrastructure_error", ""))
			if not infrastructure_error.is_empty():
				break
			run_result.erase("infrastructure_error")
			run_rows.append(run_result)
			print(
				"DIFFICULTY_RUN policy=%s seed=%d outcome=%s tick=%d level=%d kills=%d evolution_tick=%d"
				% [
					str(run_result["policy"]),
					run_seed,
					str(run_result["outcome"]),
					int(run_result["terminal_tick"]),
					int(run_result["final_level"]),
					int(run_result["total_kills"]),
					int(run_result["first_evolution_tick"]),
				]
			)
		if not infrastructure_error.is_empty():
			break

	var acceptance: Dictionary = AcceptanceScript.evaluate(run_rows)
	var write_error: String = _write_artifacts(
		run_rows,
		checkpoint_rows,
		acceptance,
		infrastructure_error,
	)
	if not write_error.is_empty():
		print("DIFFICULTY_CALIBRATION_ERROR reason=%s" % write_error)
		quit(2)
		return
	if not infrastructure_error.is_empty():
		print("DIFFICULTY_CALIBRATION_ERROR reason=%s" % infrastructure_error)
		quit(2)
		return
	if bool(acceptance.get("passed", false)):
		print(
			"DIFFICULTY_CALIBRATION_OK runs=%d boss_reached=%d boss_cleared=%d normal_by_5m=%d normal_by_7m=%d normal_mean_seconds=%.3f"
			% [
				int(acceptance["run_count"]),
				int(acceptance["boss_reached"]),
				int(acceptance["boss_cleared"]),
				int(acceptance["normal_evolved_by_five"]),
				int(acceptance["normal_evolved_by_seven"]),
				float(acceptance["normal_mean_evolution_seconds"]),
			]
		)
		quit(0)
		return
	var reasons: PackedStringArray = acceptance.get("reasons", PackedStringArray())
	print("DIFFICULTY_CALIBRATION_FAILED reasons=%s" % " | ".join(reasons))
	quit(1)


func _load_catalog() -> Dictionary:
	var catalog := DefinitionCatalog.new()
	if not catalog.load_and_validate():
		return {"valid": false, "reason": "definition_catalog_invalid"}
	var balance: BalanceManifest = catalog.balance_manifest()
	if balance == null or balance.balance_revision != BALANCE_REVISION:
		return {"valid": false, "reason": "balance_revision_mismatch"}
	if catalog.manifest().starter_weapon_id != &"homing_core":
		return {"valid": false, "reason": "starter_weapon_must_be_homing_core"}
	return {"valid": true, "reason": "", "catalog": catalog}


func _run_one(
	catalog: DefinitionCatalog,
	policy_value: int,
	run_seed: int,
	checkpoint_rows: Array[Dictionary],
) -> Dictionary:
	var state: RunState = RunStateFactory.create(run_seed, catalog)
	var simulation := CombatSimulation.new()
	simulation.initialize(state, catalog)
	if not simulation.has_method(&"advance_tick"):
		return {"infrastructure_error": "combat_simulation_advance_tick_missing"}
	if not simulation.has_method(&"visible_combat_metrics"):
		return {"infrastructure_error": "visible_combat_metrics_missing"}
	var bot: RefCounted = BotScript.new()
	if not bot.initialize(policy_value, run_seed):
		return {"infrastructure_error": "bot_policy_invalid"}
	var runtime: Dictionary = {
		"first_evolution_tick": -1,
		"minimum_hp_ratio": 1.0,
		"damage_tick_count": 0,
		"net_damage_taken": 0.0,
	}
	var checkpoint_index: int = 0
	var infrastructure_error: String = ""

	while (
		state.phase != GameTypes.RunPhase.RESULT
		and state.phase != GameTypes.RunPhase.FAILED
		and state.combat_tick < MAX_COMBAT_TICK
	):
		if Time.get_ticks_msec() - _runner_started_ms >= RUNNER_TIMEOUT_MS:
			infrastructure_error = "runner_timeout"
			break
		if state.phase != GameTypes.RunPhase.COMBAT:
			infrastructure_error = _resolve_modals(simulation, bot, runtime)
			if not infrastructure_error.is_empty():
				break
			continue
		var hp_before: float = state.current_hp
		var move_input: Vector2 = bot.movement_input(simulation)
		var advance_result: Variant = simulation.call(&"advance_tick", move_input)
		if typeof(advance_result) != TYPE_BOOL or not bool(advance_result):
			infrastructure_error = "combat_advance_failed tick=%d" % state.combat_tick
			break
		var net_damage: float = maxf(0.0, hp_before - state.current_hp)
		if net_damage > 0.000001:
			runtime["damage_tick_count"] = int(runtime["damage_tick_count"]) + 1
			runtime["net_damage_taken"] = float(runtime["net_damage_taken"]) + net_damage
		infrastructure_error = _resolve_modals(simulation, bot, runtime)
		if not infrastructure_error.is_empty():
			break
		_update_minimum_hp_ratio(state, runtime)
		while (
			checkpoint_index < CHECKPOINT_TICKS.size()
			and state.combat_tick >= CHECKPOINT_TICKS[checkpoint_index]
		):
			checkpoint_rows.append(_checkpoint_row(
				simulation,
				policy_value,
				run_seed,
				CHECKPOINT_TICKS[checkpoint_index],
			))
			checkpoint_index += 1

	if not infrastructure_error.is_empty():
		return {"infrastructure_error": infrastructure_error}
	while checkpoint_index < CHECKPOINT_TICKS.size():
		checkpoint_rows.append(_checkpoint_row(
			simulation,
			policy_value,
			run_seed,
			CHECKPOINT_TICKS[checkpoint_index],
		))
		checkpoint_index += 1
	runtime["bot_state"] = bot.deterministic_state_values()
	return _run_row(simulation, policy_value, run_seed, runtime)


func _resolve_modals(
	simulation: CombatSimulation,
	bot: RefCounted,
	runtime: Dictionary,
) -> String:
	var resolved_count: int = 0
	while simulation.state.phase in [
		GameTypes.RunPhase.LEVEL_UP,
		GameTypes.RunPhase.CHEST_REWARD,
	]:
		resolved_count += 1
		if resolved_count > MAX_MODAL_CHAIN:
			return "modal_chain_limit tick=%d" % simulation.state.combat_tick
		if simulation.state.phase == GameTypes.RunPhase.LEVEL_UP:
			var offer: LevelOffer = simulation.state.active_level_offer
			var choice_index: int = bot.choose_upgrade(offer, simulation.state, simulation.catalog)
			if choice_index < 0 or not simulation.apply_upgrade_choice(choice_index):
				return "level_offer_apply_failed tick=%d" % simulation.state.combat_tick
		else:
			if (
				simulation.state.pending_level_ups > 0
				or simulation.state.active_level_offer != null
			):
				return "chest_before_level_queue tick=%d" % simulation.state.combat_tick
			var evolution_before: int = simulation.state.evolution_count
			if not simulation.complete_chest_reward():
				return "chest_apply_failed tick=%d" % simulation.state.combat_tick
			if (
				simulation.state.evolution_count > evolution_before
				and int(runtime["first_evolution_tick"]) < 0
			):
				runtime["first_evolution_tick"] = simulation.state.combat_tick
	return ""


func _update_minimum_hp_ratio(state: RunState, runtime: Dictionary) -> void:
	var hp_ratio: float = state.current_hp / maxf(1.0, state.max_hp)
	runtime["minimum_hp_ratio"] = minf(float(runtime["minimum_hp_ratio"]), hp_ratio)


func _run_row(
	simulation: CombatSimulation,
	policy_value: int,
	run_seed: int,
	runtime: Dictionary,
) -> Dictionary:
	var state: RunState = simulation.state
	var first_evolution_tick: int = int(runtime["first_evolution_tick"])
	var outcome: String = "BOSS_TIMEOUT"
	if state.phase == GameTypes.RunPhase.RESULT:
		outcome = "RESULT"
	elif state.phase == GameTypes.RunPhase.FAILED:
		outcome = "FAILED"
	var enemy_overflow: int = simulation.enemy_system.enemy_store.overflow_count
	var projectile_overflow: int = simulation.projectile_pool.overflow_count
	var vfx_overflow: int = simulation.vfx_pool.overflow_count
	var xp_overflow_merges: int = simulation.xp_pickup_pool.overflow_merge_count
	var orphan_count: int = (
		simulation.enemy_system.enemy_store.orphan_count()
		+ simulation.projectile_pool.orphan_count()
		+ simulation.vfx_pool.orphan_count()
		+ simulation.xp_pickup_pool.orphan_count()
	)
	var visible_metrics_value: Variant = simulation.call(&"visible_combat_metrics")
	if typeof(visible_metrics_value) != TYPE_DICTIONARY:
		return {"infrastructure_error": "visible_combat_metrics_invalid"}
	var visible_metrics: Dictionary = visible_metrics_value
	for metric_key: String in VISIBLE_METRIC_KEYS:
		if not visible_metrics.has(metric_key):
			return {
				"infrastructure_error": "visible_combat_metric_missing_%s" % metric_key,
			}
	var row: Dictionary = {
		"infrastructure_error": "",
		"balance_revision": BALANCE_REVISION,
		"policy": BotScript.policy_name_for(policy_value),
		"seed": run_seed,
		"outcome": outcome,
		"terminal_tick": state.combat_tick,
		"terminal_seconds": float(state.combat_tick) / 60.0,
		"boss_reached": state.boss_spawned,
		"boss_cleared": state.boss_defeated,
		"death_before_two_minutes": (
			state.phase == GameTypes.RunPhase.FAILED
			and state.combat_tick <= AcceptanceScript.TWO_MINUTE_TICK
		),
		"first_evolution_tick": first_evolution_tick,
		"first_evolution_minutes": (
			-1.0 if first_evolution_tick < 0 else float(first_evolution_tick) / 3_600.0
		),
		"final_hp": state.current_hp,
		"final_max_hp": state.max_hp,
		"minimum_hp_ratio": float(runtime["minimum_hp_ratio"]),
		"final_level": state.level,
		"final_xp": state.xp,
		"total_kills": state.total_kills,
		"elite_kills": state.elite_kills,
		"opened_chests": state.opened_chests,
		"evolution_count": state.evolution_count,
		"damage_tick_count": int(runtime["damage_tick_count"]),
		"net_damage_taken": float(runtime["net_damage_taken"]),
		"boss_hp": state.boss_hp,
		"boss_max_hp": state.boss_max_hp,
		"enemy_pool_overflow": enemy_overflow,
		"projectile_pool_overflow": projectile_overflow,
		"vfx_pool_overflow": vfx_overflow,
		"xp_overflow_merges": xp_overflow_merges,
		"pool_overflow_count": (
			enemy_overflow
			+ projectile_overflow
			+ vfx_overflow
			+ xp_overflow_merges
		),
		"pool_orphan_count": orphan_count,
		"digest": _digest(simulation, runtime),
	}
	for metric_key: String in VISIBLE_METRIC_KEYS:
		row[metric_key] = visible_metrics[metric_key]
	return row


func _checkpoint_row(
	simulation: CombatSimulation,
	policy_value: int,
	run_seed: int,
	checkpoint_tick: int,
) -> Dictionary:
	var state: RunState = simulation.state
	return {
		"balance_revision": BALANCE_REVISION,
		"policy": BotScript.policy_name_for(policy_value),
		"seed": run_seed,
		"checkpoint_tick": checkpoint_tick,
		"observed_tick": state.combat_tick,
		"alive": state.phase != GameTypes.RunPhase.FAILED and state.current_hp > 0.0,
		"hp": state.current_hp,
		"max_hp": state.max_hp,
		"hp_ratio": state.current_hp / maxf(1.0, state.max_hp),
		"level": state.level,
		"xp": state.xp,
		"total_kills": state.total_kills,
		"elite_kills": state.elite_kills,
		"opened_chests": state.opened_chests,
		"evolution_count": state.evolution_count,
		"active_enemies": simulation.enemy_system.enemy_store.active_count(),
		"active_projectiles": simulation.projectile_pool.active_count(),
		"active_xp": simulation.xp_pickup_pool.active_count(),
		"boss_reached": state.boss_spawned,
		"boss_hp": state.boss_hp,
		"boss_max_hp": state.boss_max_hp,
	}


func _digest(simulation: CombatSimulation, runtime: Dictionary) -> String:
	var state: RunState = simulation.state
	var weapons: Array = []
	for weapon: RunWeapon in state.weapons:
		weapons.append([
			String(weapon.weapon_id),
			String(weapon.lineage_id),
			weapon.level,
			weapon.evolved,
			weapon.cooldown_remaining_ticks,
			weapon.ready_on_resume,
			0 if weapon.rng == null else weapon.rng.state,
		])
	var passives: Array = []
	for passive: RunPassive in state.passives:
		passives.append([String(passive.passive_id), passive.level])
	var enemies: Array = []
	for entity_id: int in simulation.enemy_system.enemy_store.snapshot_ids_sorted():
		var enemy: EnemyEntity = simulation.enemy_system.enemy_store.get_by_id(entity_id)
		if enemy != null:
			enemies.append([
				entity_id,
				int(enemy.enemy_type),
				enemy.position,
				enemy.hp,
				enemy.activation_tick,
				enemy.special_elapsed_ticks,
				enemy.telegraph_elapsed_ticks,
				enemy.telegraph_active,
				enemy.barrage_alternate,
				enemy.boss_charge_active,
				enemy.boss_charge_elapsed_ticks,
				enemy.boss_charge_interval_ticks,
				enemy.boss_charge_spoke_count,
				enemy.boss_charge_half_step,
				enemy.boss_action_age_ticks,
			])
	var projectile_indices: Array[int] = simulation.projectile_pool.active_indices_snapshot()
	projectile_indices.sort()
	var projectiles: Array = []
	for pool_index: int in projectile_indices:
		var projectile: ProjectileState = simulation.projectile_pool.slots[pool_index]
		projectiles.append([
			pool_index,
			projectile.generation,
			String(projectile.faction),
			String(projectile.weapon_id),
			projectile.position,
			projectile.velocity,
			projectile.damage,
			projectile.remaining_distance,
			projectile.outbound_distance_remaining,
			projectile.remaining_lifetime,
		])
	var xp_indices: Array[int] = simulation.xp_pickup_pool.active_indices_snapshot()
	xp_indices.sort()
	var xp_pickups: Array = []
	for pool_index: int in xp_indices:
		var pickup: XpPickupState = simulation.xp_pickup_pool.slots[pool_index]
		xp_pickups.append([pool_index, pickup.generation, pickup.position, pickup.value])
	var values: Array = [
		state.run_seed,
		int(state.phase),
		state.combat_tick,
		simulation.player_position,
		state.current_hp,
		state.max_hp,
		state.level,
		state.xp,
		state.total_kills,
		state.elite_kills,
		state.opened_chests,
		state.evolution_count,
		state.boss_spawned,
		state.boss_defeated,
		state.boss_hp,
		state.rng_streams.state_digest(),
		runtime.duplicate(true),
		simulation.call(&"visible_combat_metrics"),
		weapons,
		passives,
		enemies,
		projectiles,
		xp_pickups,
	]
	return var_to_bytes(values).hex_encode().sha256_text()


func _write_artifacts(
	run_rows: Array[Dictionary],
	checkpoint_rows: Array[Dictionary],
	acceptance: Dictionary,
	infrastructure_error: String,
) -> String:
	var output_directory: String = ProjectSettings.globalize_path(OUTPUT_ROOT).replace("\\", "/").simplify_path()
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(output_directory)
	if directory_error != OK:
		return "artifact_directory code=%d" % directory_error
	var runs_error: String = _write_csv(
		output_directory.path_join(RUNS_FILENAME),
		RUN_COLUMNS,
		run_rows,
	)
	if not runs_error.is_empty():
		return runs_error
	var checkpoints_error: String = _write_csv(
		output_directory.path_join(CHECKPOINTS_FILENAME),
		CHECKPOINT_COLUMNS,
		checkpoint_rows,
	)
	if not checkpoints_error.is_empty():
		return checkpoints_error
	return _write_summary(
		output_directory.path_join(SUMMARY_FILENAME),
		acceptance,
		infrastructure_error,
	)


func _write_csv(
	path: String,
	columns: Array[String],
	rows: Array[Dictionary],
) -> String:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "artifact_open path=%s code=%d" % [path, FileAccess.get_open_error()]
	var lines: PackedStringArray = PackedStringArray()
	lines.append(_csv_line(columns))
	for row: Dictionary in rows:
		var values: Array[String] = []
		for column: String in columns:
			values.append(_format_value(row.get(column, "")))
		lines.append(_csv_line(values))
	var stored: bool = file.store_string("\n".join(lines) + "\n")
	file.close()
	return "" if stored else "artifact_write path=%s" % path


func _write_summary(
	path: String,
	acceptance: Dictionary,
	infrastructure_error: String,
) -> String:
	var reasons: PackedStringArray = acceptance.get("reasons", PackedStringArray())
	var lines: PackedStringArray = PackedStringArray([
		"balance_revision=%d" % BALANCE_REVISION,
		"run_count=%d" % int(acceptance.get("run_count", 0)),
		"early_deaths=%d" % int(acceptance.get("early_deaths", 0)),
		"boss_reached=%d" % int(acceptance.get("boss_reached", 0)),
		"boss_cleared=%d" % int(acceptance.get("boss_cleared", 0)),
		"evolved_by_3m=%d" % int(acceptance.get("evolved_by_three", 0)),
		"normal_run_count=%d" % int(acceptance.get("normal_run_count", 0)),
		"normal_evolved_by_5m=%d" % int(acceptance.get("normal_evolved_by_five", 0)),
		"normal_evolved_by_7m=%d" % int(acceptance.get("normal_evolved_by_seven", 0)),
		"normal_first_evolution_mean_seconds=%.6f" % float(acceptance.get("normal_mean_evolution_seconds", -1.0)),
		"normal_first_evolution_mean_minutes=%.6f" % float(acceptance.get("normal_mean_evolution_minutes", -1.0)),
		"pool_overflow_runs=%d" % int(acceptance.get("overflow_runs", 0)),
		"pool_orphan_runs=%d" % int(acceptance.get("orphan_runs", 0)),
		"missing_visible_metric_runs=%d" % int(acceptance.get("missing_visible_metric_runs", 0)),
		"no_weapon_combat_runs=%d" % int(acceptance.get("no_weapon_combat_runs", 0)),
		"offscreen_weapon_hit_runs=%d" % int(acceptance.get("offscreen_weapon_hit_runs", 0)),
		"offscreen_weapon_kill_runs=%d" % int(acceptance.get("offscreen_weapon_kill_runs", 0)),
		"hit_distance_runs=%d" % int(acceptance.get("hit_distance_runs", 0)),
		"kill_distance_runs=%d" % int(acceptance.get("kill_distance_runs", 0)),
		"effect_outer_distance_runs=%d" % int(acceptance.get("effect_outer_distance_runs", 0)),
		"feedback_suppressed_runs=%d" % int(acceptance.get("feedback_suppressed_runs", 0)),
		"audio_admitted_total=%d" % int(acceptance.get("audio_admitted_total", 0)),
		"audio_suppressed_total=%d" % int(acceptance.get("audio_suppressed_total", 0)),
		"infrastructure_error=%s" % infrastructure_error,
		"passed=%s" % str(bool(acceptance.get("passed", false)) and infrastructure_error.is_empty()).to_lower(),
		"reasons=%s" % " | ".join(reasons),
	])
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "artifact_open path=%s code=%d" % [path, FileAccess.get_open_error()]
	var stored: bool = file.store_string("\n".join(lines) + "\n")
	file.close()
	return "" if stored else "artifact_write path=%s" % path


func _csv_line(values: Array[String]) -> String:
	var escaped: PackedStringArray = PackedStringArray()
	for value: String in values:
		escaped.append('"%s"' % value.replace('"', '""'))
	return ",".join(escaped)


func _format_value(value: Variant) -> String:
	if value is bool:
		return str(value).to_lower()
	if value is float:
		return "%.9f" % float(value)
	return str(value)
