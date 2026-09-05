class_name DifficultyAcceptance
extends RefCounted


const EXPECTED_RUN_COUNT: int = 12
const EXPECTED_NORMAL_RUN_COUNT: int = 4
const TWO_MINUTE_TICK: int = 7_200
const NINE_MINUTE_TICK: int = 32_400
const BOSS_REACH_MIN: int = 9
const BOSS_REACH_MAX: int = 11
const BOSS_CLEAR_MIN: int = 5
const BOSS_CLEAR_MAX: int = 8
const NORMAL_EVOLUTION_MEAN_SECONDS_MIN: float = 420.0
const NORMAL_EVOLUTION_MEAN_SECONDS_MAX: float = 540.0
const BOSS_FIGHT_SECONDS_MIN: float = 60.0
const BOSS_FIGHT_SECONDS_MAX: float = 120.0
const ELITE_SIXTY_SECOND_RATIO_MIN: float = 0.75
const PRESSURE_REDUCTION_MIN: float = 0.25
const PRESSURE_REDUCTION_MAX: float = 0.35
const PEAK_GAIN_MIN: float = 0.15
const PEAK_GAIN_MAX: float = 0.30
const XP_KILL_GAIN_DIFFERENCE_MAX: float = 0.05


static func evaluate(
	results: Array[Dictionary],
	segment_rows: Array[Dictionary] = [],
	wide_mode: bool = false,
) -> Dictionary:
	var reasons: PackedStringArray = PackedStringArray()
	var early_deaths: int = 0
	var boss_reached: int = 0
	var boss_cleared: int = 0
	var evolved_before_first_chest: int = 0
	var normal_run_count: int = 0
	var normal_evolved_by_nine: int = 0
	var normal_build_maxed_seconds: Array[float] = []
	var normal_evolved_runs: int = 0
	var normal_evolution_seconds_total: float = 0.0
	var overflow_runs: int = 0
	var orphan_runs: int = 0
	var missing_visible_metric_runs: int = 0
	var no_weapon_combat_runs: int = 0
	var offscreen_weapon_hit_runs: int = 0
	var offscreen_weapon_kill_runs: int = 0
	var hit_distance_runs: int = 0
	var kill_distance_runs: int = 0
	var effect_outer_distance_runs: int = 0
	var feedback_suppressed_runs: int = 0
	var important_vfx_drop_runs: int = 0
	var audio_admitted_total: int = 0
	var audio_suppressed_total: int = 0
	var elite_spawn_count: int = 0
	var elite_killed_within_sixty: int = 0
	var boss_fight_seconds: Array[float] = []

	for result: Dictionary in results:
		if bool(result.get("death_before_two_minutes", false)):
			early_deaths += 1
		if bool(result.get("boss_reached", false)):
			boss_reached += 1
		if bool(result.get("boss_cleared", false)):
			boss_cleared += 1
			var fight_seconds: float = float(result.get("boss_fight_seconds", -1.0))
			if fight_seconds >= 0.0:
				boss_fight_seconds.append(fight_seconds)
		var evolution_tick: int = int(result.get("first_evolution_tick", -1))
		var first_chest_tick: int = int(result.get("first_evolution_chest_tick", -1))
		if first_chest_tick < 0:
			reasons.append("first_evolution_chest_tick missing or invalid")
		if evolution_tick >= 0 and evolution_tick < first_chest_tick:
			evolved_before_first_chest += 1
		if str(result.get("policy", "")) == "normal":
			normal_run_count += 1
			var build_tick: int = int(result.get("build_maxed_tick", -1))
			if build_tick >= 0:
				normal_build_maxed_seconds.append(float(build_tick) / float(RunState.TICKS_PER_SECOND))
			if evolution_tick >= 0:
				normal_evolved_runs += 1
				normal_evolution_seconds_total += float(evolution_tick) / 60.0
				if evolution_tick <= NINE_MINUTE_TICK:
					normal_evolved_by_nine += 1
			var elite_spawns: PackedInt32Array = result.get("elite_spawn_ticks", PackedInt32Array())
			var elite_kills: PackedInt32Array = result.get("elite_kill_ticks", PackedInt32Array())
			for elite_index: int in range(elite_spawns.size()):
				var spawn_tick: int = elite_spawns[elite_index]
				if spawn_tick < 0:
					continue
				elite_spawn_count += 1
				var kill_tick: int = elite_kills[elite_index] if elite_index < elite_kills.size() else -1
				var kill_seconds: float = float(kill_tick - spawn_tick) / float(RunState.TICKS_PER_SECOND)
				if kill_tick >= spawn_tick and kill_seconds <= 60.0:
					elite_killed_within_sixty += 1
		if int(result.get("pool_overflow_count", 0)) > 0:
			overflow_runs += 1
		if int(result.get("pool_orphan_count", 0)) > 0:
			orphan_runs += 1
		var required_metric_keys: Array[String] = [
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
		var metrics_present: bool = true
		for metric_key: String in required_metric_keys:
			if not result.has(metric_key):
				metrics_present = false
				break
		if not metrics_present:
			missing_visible_metric_runs += 1
			continue
		if int(result["weapon_hits"]) <= 0 or int(result["weapon_kills"]) <= 0:
			no_weapon_combat_runs += 1
		if int(result["offscreen_weapon_hits"]) != 0:
			offscreen_weapon_hit_runs += 1
		if int(result["offscreen_weapon_kills"]) != 0:
			offscreen_weapon_kill_runs += 1
		if float(result["max_hit_center_distance"]) > 10.0 + 0.0001:
			hit_distance_runs += 1
		if float(result["max_kill_center_distance"]) > 10.0 + 0.0001:
			kill_distance_runs += 1
		if float(result["max_effect_outer_distance"]) > 9.0 + 0.0001:
			effect_outer_distance_runs += 1
		if int(result["feedback_suppressed"]) != 0:
			feedback_suppressed_runs += 1
		if int(result["important_vfx_dropped"]) != 0:
			important_vfx_drop_runs += 1
		audio_admitted_total += int(result["audio_admitted"])
		audio_suppressed_total += int(result["audio_suppressed"])

	var normal_mean_evolution_seconds: float = (
		-1.0
		if normal_evolved_runs <= 0
		else normal_evolution_seconds_total / float(normal_evolved_runs)
	)
	var expected_run_count: int = 24 if wide_mode else EXPECTED_RUN_COUNT
	var expected_normal_count: int = 8 if wide_mode else EXPECTED_NORMAL_RUN_COUNT
	var boss_reach_min: int = 18 if wide_mode else BOSS_REACH_MIN
	var boss_reach_max: int = 22 if wide_mode else BOSS_REACH_MAX
	var boss_clear_min: int = 10 if wide_mode else BOSS_CLEAR_MIN
	var boss_clear_max: int = 16 if wide_mode else BOSS_CLEAR_MAX
	var normal_by_nine: int = expected_normal_count
	if results.size() != expected_run_count:
		reasons.append("run_count expected=%d actual=%d" % [expected_run_count, results.size()])
	if early_deaths != 0:
		reasons.append("deaths_by_2m expected=0 actual=%d" % early_deaths)
	if boss_reached < boss_reach_min or boss_reached > boss_reach_max:
		reasons.append(
			"boss_reached expected=%d..%d actual=%d"
			% [boss_reach_min, boss_reach_max, boss_reached]
		)
	if boss_cleared < boss_clear_min or boss_cleared > boss_clear_max:
		reasons.append(
			"boss_cleared expected=%d..%d actual=%d"
			% [boss_clear_min, boss_clear_max, boss_cleared]
		)
	if evolved_before_first_chest != 0:
		reasons.append("evolved_before_first_chest expected=0 actual=%d" % evolved_before_first_chest)
	if normal_run_count != expected_normal_count:
		reasons.append(
			"normal_run_count expected=%d actual=%d"
			% [expected_normal_count, normal_run_count]
		)
	if normal_evolved_by_nine != normal_by_nine:
		reasons.append(
			"normal_evolved_by_9m expected=%d actual=%d"
			% [normal_by_nine, normal_evolved_by_nine]
		)
	if (
		normal_mean_evolution_seconds < NORMAL_EVOLUTION_MEAN_SECONDS_MIN
		or normal_mean_evolution_seconds > NORMAL_EVOLUTION_MEAN_SECONDS_MAX
	):
		reasons.append(
			"normal_first_evolution_mean_seconds expected=%.1f..%.1f actual=%.3f"
			% [
				NORMAL_EVOLUTION_MEAN_SECONDS_MIN,
				NORMAL_EVOLUTION_MEAN_SECONDS_MAX,
				normal_mean_evolution_seconds,
			]
		)
	if overflow_runs != 0:
		reasons.append("pool_overflow_runs expected=0 actual=%d" % overflow_runs)
	if orphan_runs != 0:
		reasons.append("pool_orphan_runs expected=0 actual=%d" % orphan_runs)
	if missing_visible_metric_runs != 0:
		reasons.append(
			"missing_visible_metric_runs expected=0 actual=%d"
			% missing_visible_metric_runs
		)
	if no_weapon_combat_runs != 0:
		reasons.append("no_weapon_combat_runs expected=0 actual=%d" % no_weapon_combat_runs)
	if offscreen_weapon_hit_runs != 0:
		reasons.append(
			"offscreen_weapon_hit_runs expected=0 actual=%d"
			% offscreen_weapon_hit_runs
		)
	if offscreen_weapon_kill_runs != 0:
		reasons.append(
			"offscreen_weapon_kill_runs expected=0 actual=%d"
			% offscreen_weapon_kill_runs
		)
	if hit_distance_runs != 0:
		reasons.append("hit_distance_runs expected=0 actual=%d" % hit_distance_runs)
	if kill_distance_runs != 0:
		reasons.append("kill_distance_runs expected=0 actual=%d" % kill_distance_runs)
	if effect_outer_distance_runs != 0:
		reasons.append(
			"effect_outer_distance_runs expected=0 actual=%d"
			% effect_outer_distance_runs
		)
	if important_vfx_drop_runs != 0:
		reasons.append(
			"important_vfx_drop_runs expected=0 actual=%d"
			% important_vfx_drop_runs
		)
	var boss_fight_median_seconds: float = _median(boss_fight_seconds)
	var elite_killed_within_sixty_ratio: float = (
		-1.0
		if elite_spawn_count <= 0
		else float(elite_killed_within_sixty) / float(elite_spawn_count)
	)
	var wave_pair_metrics: Array[Dictionary] = _wave_pair_metrics(segment_rows)
	if not segment_rows.is_empty():
		if (
			boss_fight_median_seconds < BOSS_FIGHT_SECONDS_MIN
			or boss_fight_median_seconds > BOSS_FIGHT_SECONDS_MAX
		):
			reasons.append(
				"boss_fight_median_seconds expected=%.1f..%.1f actual=%.3f"
				% [BOSS_FIGHT_SECONDS_MIN, BOSS_FIGHT_SECONDS_MAX, boss_fight_median_seconds]
			)
		if elite_killed_within_sixty_ratio < ELITE_SIXTY_SECOND_RATIO_MIN:
			reasons.append(
				"elite_killed_within_60s_ratio expected>=%.2f actual=%.3f"
				% [ELITE_SIXTY_SECOND_RATIO_MIN, elite_killed_within_sixty_ratio]
			)
		for pair: Dictionary in wave_pair_metrics:
			if not bool(pair["passed"]):
				reasons.append(str(pair["reason"]))

	return {
		"passed": reasons.is_empty(),
		"reasons": reasons,
		"run_count": results.size(),
		"early_deaths": early_deaths,
		"boss_reached": boss_reached,
		"boss_cleared": boss_cleared,
		"evolved_before_first_chest": evolved_before_first_chest,
		"normal_run_count": normal_run_count,
		"normal_evolved_runs": normal_evolved_runs,
		"normal_evolution_missing_runs": normal_run_count - normal_evolved_runs,
		"normal_build_maxed_runs": normal_build_maxed_seconds.size(),
		"normal_build_maxed_missing_runs": normal_run_count - normal_build_maxed_seconds.size(),
		"normal_build_maxed_median_seconds": _median(normal_build_maxed_seconds),
		"normal_evolved_by_nine": normal_evolved_by_nine,
		"normal_mean_evolution_seconds": normal_mean_evolution_seconds,
		"normal_mean_evolution_minutes": (
			-1.0
			if normal_mean_evolution_seconds < 0.0
			else normal_mean_evolution_seconds / 60.0
		),
		"overflow_runs": overflow_runs,
		"orphan_runs": orphan_runs,
		"missing_visible_metric_runs": missing_visible_metric_runs,
		"no_weapon_combat_runs": no_weapon_combat_runs,
		"offscreen_weapon_hit_runs": offscreen_weapon_hit_runs,
		"offscreen_weapon_kill_runs": offscreen_weapon_kill_runs,
		"hit_distance_runs": hit_distance_runs,
		"kill_distance_runs": kill_distance_runs,
		"effect_outer_distance_runs": effect_outer_distance_runs,
		"feedback_suppressed_runs": feedback_suppressed_runs,
		"important_vfx_drop_runs": important_vfx_drop_runs,
		"audio_admitted_total": audio_admitted_total,
		"audio_suppressed_total": audio_suppressed_total,
		"boss_fight_median_seconds": boss_fight_median_seconds,
		"elite_killed_within_sixty_ratio": elite_killed_within_sixty_ratio,
		"wave_pair_metrics": wave_pair_metrics,
	}


static func _wave_pair_metrics(segment_rows: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var last_segment_index: int = -1
	for row: Dictionary in segment_rows:
		last_segment_index = maxi(last_segment_index, int(row.get("segment_index", -1)))
	# The difficulty minute starts at 2:00; its following minute is the kill wave.
	for peak_index: int in range(2, last_segment_index, 2):
		var peak: Dictionary = _segment_medians(segment_rows, peak_index)
		var rest: Dictionary = _segment_medians(segment_rows, peak_index + 1)
		var pressure_reduction: float = _reduction(float(peak["engaged"]), float(rest["engaged"]))
		var kill_gain: float = _gain(float(rest["kills"]), float(peak["kills"]))
		var xp_gain: float = _gain(float(rest["xp"]), float(peak["xp"]))
		var passed: bool = (
			pressure_reduction >= PRESSURE_REDUCTION_MIN
			and pressure_reduction <= PRESSURE_REDUCTION_MAX
			and kill_gain >= PEAK_GAIN_MIN
			and kill_gain <= PEAK_GAIN_MAX
			and xp_gain >= PEAK_GAIN_MIN
			and xp_gain <= PEAK_GAIN_MAX
			and absf(xp_gain - kill_gain) <= XP_KILL_GAIN_DIFFERENCE_MAX
		)
		result.append({
			"peak_segment": peak_index,
			"rest_segment": peak_index + 1,
			"pressure_reduction": pressure_reduction,
			"kill_gain": kill_gain,
			"xp_gain": xp_gain,
			"passed": passed,
			"reason": (
				"wave_pair_%d_%d pressure=%.3f kill_gain=%.3f xp_gain=%.3f"
				% [peak_index + 1, peak_index + 2, pressure_reduction, kill_gain, xp_gain]
			),
		})
	return result


static func _segment_medians(rows: Array[Dictionary], segment_index: int) -> Dictionary:
	var engaged: Array[float] = []
	var kills: Array[float] = []
	var xp: Array[float] = []
	for row: Dictionary in rows:
		if int(row.get("segment_index", -1)) != segment_index or not bool(row.get("completed", false)):
			continue
		engaged.append(float(row.get("mean_engaged_normal", 0.0)))
		kills.append(float(row.get("normal_kills", 0)))
		xp.append(float(row.get("normal_xp", 0)))
	return {"engaged": _median(engaged), "kills": _median(kills), "xp": _median(xp)}


static func _median(values: Array[float]) -> float:
	if values.is_empty():
		return -1.0
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	var middle: int = floori(float(sorted.size()) / 2.0)
	if sorted.size() % 2 == 1:
		return sorted[middle]
	return (sorted[middle - 1] + sorted[middle]) * 0.5


static func _reduction(peak: float, rest: float) -> float:
	return -1.0 if peak <= 0.0 else 1.0 - rest / peak


static func _gain(peak: float, rest: float) -> float:
	return -1.0 if rest <= 0.0 else peak / rest - 1.0
