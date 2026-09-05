class_name RunState
extends RefCounted


const TICKS_PER_SECOND: int = 60
const NORMAL_ENEMY_TYPE_COUNT: int = 4

var boss_start_tick: int = 0
var kill_chain_window_ticks: int = 0

var run_seed: int = 0
var rng_streams: RunRngStreams = null
var phase: GameTypes.RunPhase = GameTypes.RunPhase.BOOT
var combat_tick: int = 0
var current_hp: float = 0.0
var max_hp: float = 0.0
var base_max_hp: float = 0.0
var level: int = 1
var xp: int = 0
var xp_yield_remainder: int = 0
var pending_level_ups: int = 0
var upgrade_selections_applied: int = 0
var build_maxed: bool = false
var weapons: Array[RunWeapon] = []
var passives: Array[RunPassive] = []
var active_level_offer: LevelOffer = null
var active_chest_outcome: ChestOutcome = null
var next_offer_serial: int = 1
var next_chest_serial: int = 1
var applied_offer_serials: Dictionary[int, bool] = {}
var applied_chest_serials: Dictionary[int, bool] = {}
var pending_chest_sources: Array[int] = []
var opened_chests: int = 0
var evolution_count: int = 0
var boss_spawned: bool = false
var boss_transition_started: bool = false
var boss_defeated: bool = false
var boss_phase: int = 0
var boss_enrage_stacks: int = 0
var boss_hp: float = 0.0
var boss_max_hp: float = 0.0
var stop_until_tick: int = 0
var level_up_invulnerable_until_tick: int = 0
var next_entity_id: int = 1
var next_event_serial: int = 1
var next_swarm_group_id: int = 1
var spawn_credit: float = 0.0
var total_kills: int = 0
var normal_kills: int = 0
var elite_kills: int = 0
var boss_kills: int = 0
var normal_kills_by_type: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
var normal_kills_by_segment: PackedInt32Array = []
var normal_xp_by_segment: PackedInt32Array = []
var normal_active_samples_by_segment: PackedInt32Array = []
var normal_active_total_by_segment: PackedInt64Array = []
var normal_engaged_total_by_segment: PackedInt64Array = []
var elite_spawn_ticks: PackedInt32Array = []
var elite_kill_ticks: PackedInt32Array = []
var boss_spawn_tick: int = -1
var boss_defeat_tick: int = -1
var absorbed_normal_count: int = 0
var normal_far_despawn_count: int = 0
var absorbed_enemy_projectile_count: int = 0
var swarm_event_attempt_count: int = 0
var swarm_event_roll_success_count: int = 0
var swarm_event_spawn_failure_count: int = 0
var swarm_event_skipped_busy_count: int = 0
var swarm_event_group_count: int = 0
var swarm_event_generated_count: int = 0
var swarm_event_kill_count: int = 0
var swarm_event_exit_count: int = 0
var swarm_event_absorbed_count: int = 0
var swarm_event_xp: int = 0
var kill_chain_count: int = 0
var kill_chain_last_tick: int = -1
var kill_chain_accent_milestone: int = 0
var weapon_hit_count: int = 0
var weapon_kill_count: int = 0
var visible_weapon_hit_count: int = 0
var visible_weapon_kill_count: int = 0
var offscreen_weapon_hit_count: int = 0
var offscreen_weapon_kill_count: int = 0
var max_weapon_hit_center_distance: float = 0.0
var max_weapon_kill_center_distance: float = 0.0
var max_weapon_effect_outer_distance: float = 0.0
var visible_enemy_sample_count: int = 0
var visible_enemy_count_total: int = 0
var engaged_enemy_count_total: int = 0
var materializing_enemy_count_total: int = 0
var peak_visible_enemy_count: int = 0
var peak_engaged_enemy_count: int = 0
var peak_materializing_enemy_count: int = 0
var feedback_event_emitted_count: int = 0
var feedback_event_suppressed_count: int = 0
var weapon_damage_by_lineage: Dictionary[StringName, float] = {}
var recent_damage_samples: Array[DamageSample] = []


func elapsed_seconds() -> float:
	return float(combat_tick) / float(TICKS_PER_SECOND)


func weapon(weapon_id: StringName) -> RunWeapon:
	for runtime: RunWeapon in weapons:
		if runtime.weapon_id == weapon_id:
			return runtime
	return null


func weapon_for_lineage(lineage_id: StringName) -> RunWeapon:
	for runtime: RunWeapon in weapons:
		if runtime.lineage_id == lineage_id:
			return runtime
	return null


func passive(passive_id: StringName) -> RunPassive:
	for runtime: RunPassive in passives:
		if runtime.passive_id == passive_id:
			return runtime
	return null


func passive_level(passive_id: StringName) -> int:
	var runtime: RunPassive = passive(passive_id)
	return 0 if runtime == null else runtime.level


func record_weapon_damage(lineage_id: StringName, amount: float) -> void:
	if amount <= 0.0:
		return
	weapon_damage_by_lineage[lineage_id] = (
		weapon_damage_by_lineage.get(lineage_id, 0.0) + amount
	)


func record_kill_chain(current_tick: int) -> int:
	if kill_chain_last_tick >= 0 and current_tick - kill_chain_last_tick <= kill_chain_window_ticks:
		kill_chain_count += 1
	else:
		kill_chain_count = 1
		kill_chain_accent_milestone = 0
	kill_chain_last_tick = current_tick
	var milestone: int = _kill_chain_milestone(kill_chain_count)
	if milestone > kill_chain_accent_milestone:
		kill_chain_accent_milestone = milestone
		return milestone
	return 0


func kill_chain_is_visible() -> bool:
	return (
		kill_chain_count >= 3
		and kill_chain_last_tick >= 0
		and combat_tick - kill_chain_last_tick <= kill_chain_window_ticks
	)


func record_visible_enemy_sample(visible_count: int, engaged_count: int, materializing_count: int) -> void:
	visible_enemy_sample_count += 1
	visible_enemy_count_total += maxi(0, visible_count)
	engaged_enemy_count_total += maxi(0, engaged_count)
	materializing_enemy_count_total += maxi(0, materializing_count)
	peak_visible_enemy_count = maxi(peak_visible_enemy_count, visible_count)
	peak_engaged_enemy_count = maxi(peak_engaged_enemy_count, engaged_count)
	peak_materializing_enemy_count = maxi(peak_materializing_enemy_count, materializing_count)


func record_enemy_segment_sample(
	segment_index: int,
	active_normal_count: int,
	engaged_normal_count: int,
) -> void:
	if segment_index < 0 or segment_index >= normal_kills_by_segment.size():
		return
	normal_active_samples_by_segment[segment_index] += 1
	normal_active_total_by_segment[segment_index] += maxi(0, active_normal_count)
	normal_engaged_total_by_segment[segment_index] += maxi(0, engaged_normal_count)


func _kill_chain_milestone(count: int) -> int:
	if count in [10, 25, 50, 100]:
		return count
	if count > 100 and count % 50 == 0:
		return count
	return 0


func is_level_up_resume_invulnerable() -> bool:
	return combat_tick < level_up_invulnerable_until_tick


func pending_chest_count() -> int:
	return pending_chest_sources.size()


func is_stop_active() -> bool:
	return combat_tick < stop_until_tick


func allocate_entity_id() -> int:
	var allocated: int = next_entity_id
	next_entity_id += 1
	return allocated


func allocate_event_serial() -> int:
	var allocated: int = next_event_serial
	next_event_serial += 1
	return allocated


func allocate_swarm_group_id() -> int:
	var allocated: int = next_swarm_group_id
	next_swarm_group_id += 1
	return allocated
