class_name DifficultyAcceptance
extends RefCounted


const EXPECTED_RUN_COUNT: int = 12
const EXPECTED_NORMAL_RUN_COUNT: int = 4
const TWO_MINUTE_TICK: int = 7_200
const THREE_MINUTE_TICK: int = 10_800
const FIVE_MINUTE_TICK: int = 18_000
const SEVEN_MINUTE_TICK: int = 25_200
const BOSS_REACH_MIN: int = 9
const BOSS_REACH_MAX: int = 11
const BOSS_CLEAR_MIN: int = 5
const BOSS_CLEAR_MAX: int = 8
const NORMAL_EVOLVED_BY_FIVE: int = 2
const NORMAL_EVOLVED_BY_SEVEN: int = 4
const NORMAL_EVOLUTION_MEAN_SECONDS_MIN: float = 288.0
const NORMAL_EVOLUTION_MEAN_SECONDS_MAX: float = 324.0


static func evaluate(results: Array[Dictionary]) -> Dictionary:
	var reasons: PackedStringArray = PackedStringArray()
	var early_deaths: int = 0
	var boss_reached: int = 0
	var boss_cleared: int = 0
	var evolved_by_three: int = 0
	var normal_run_count: int = 0
	var normal_evolved_by_five: int = 0
	var normal_evolved_by_seven: int = 0
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

	for result: Dictionary in results:
		if bool(result.get("death_before_two_minutes", false)):
			early_deaths += 1
		if bool(result.get("boss_reached", false)):
			boss_reached += 1
		if bool(result.get("boss_cleared", false)):
			boss_cleared += 1
		var evolution_tick: int = int(result.get("first_evolution_tick", -1))
		if evolution_tick >= 0 and evolution_tick <= THREE_MINUTE_TICK:
			evolved_by_three += 1
		if str(result.get("policy", "")) == "normal":
			normal_run_count += 1
			if evolution_tick >= 0:
				normal_evolved_runs += 1
				normal_evolution_seconds_total += float(evolution_tick) / 60.0
				if evolution_tick <= FIVE_MINUTE_TICK:
					normal_evolved_by_five += 1
				if evolution_tick <= SEVEN_MINUTE_TICK:
					normal_evolved_by_seven += 1
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
		if float(result["max_hit_center_distance"]) > CombatEnvelope.DAMAGE_CENTER_RADIUS + 0.0001:
			hit_distance_runs += 1
		if float(result["max_kill_center_distance"]) > CombatEnvelope.DAMAGE_CENTER_RADIUS + 0.0001:
			kill_distance_runs += 1
		if float(result["max_effect_outer_distance"]) > CombatEnvelope.EFFECT_OUTER_RADIUS + 0.0001:
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
	if results.size() != EXPECTED_RUN_COUNT:
		reasons.append("run_count expected=%d actual=%d" % [EXPECTED_RUN_COUNT, results.size()])
	if early_deaths != 0:
		reasons.append("deaths_by_2m expected=0 actual=%d" % early_deaths)
	if boss_reached < BOSS_REACH_MIN or boss_reached > BOSS_REACH_MAX:
		reasons.append(
			"boss_reached expected=%d..%d actual=%d"
			% [BOSS_REACH_MIN, BOSS_REACH_MAX, boss_reached]
		)
	if boss_cleared < BOSS_CLEAR_MIN or boss_cleared > BOSS_CLEAR_MAX:
		reasons.append(
			"boss_cleared expected=%d..%d actual=%d"
			% [BOSS_CLEAR_MIN, BOSS_CLEAR_MAX, boss_cleared]
		)
	if evolved_by_three != 0:
		reasons.append("evolved_by_3m expected=0 actual=%d" % evolved_by_three)
	if normal_run_count != EXPECTED_NORMAL_RUN_COUNT:
		reasons.append(
			"normal_run_count expected=%d actual=%d"
			% [EXPECTED_NORMAL_RUN_COUNT, normal_run_count]
		)
	if normal_evolved_by_five != NORMAL_EVOLVED_BY_FIVE:
		reasons.append(
			"normal_evolved_by_5m expected=%d actual=%d"
			% [NORMAL_EVOLVED_BY_FIVE, normal_evolved_by_five]
		)
	if normal_evolved_by_seven != NORMAL_EVOLVED_BY_SEVEN:
		reasons.append(
			"normal_evolved_by_7m expected=%d actual=%d"
			% [NORMAL_EVOLVED_BY_SEVEN, normal_evolved_by_seven]
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

	return {
		"passed": reasons.is_empty(),
		"reasons": reasons,
		"run_count": results.size(),
		"early_deaths": early_deaths,
		"boss_reached": boss_reached,
		"boss_cleared": boss_cleared,
		"evolved_by_three": evolved_by_three,
		"normal_run_count": normal_run_count,
		"normal_evolved_runs": normal_evolved_runs,
		"normal_evolved_by_five": normal_evolved_by_five,
		"normal_evolved_by_seven": normal_evolved_by_seven,
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
	}
