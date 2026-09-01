class_name RunState
extends RefCounted


const TICKS_PER_SECOND: int = 60
const BOSS_START_TICK: int = 36000

var run_seed: int = 0
var rng_streams: RunRngStreams = null
var phase: GameTypes.RunPhase = GameTypes.RunPhase.BOOT
var combat_tick: int = 0
var current_hp: float = 100.0
var max_hp: float = 100.0
var base_max_hp: float = 100.0
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
var boss_defeated: bool = false
var boss_phase: int = 0
var boss_enrage_stacks: int = 0
var boss_hp: float = 0.0
var boss_max_hp: float = 0.0
var stop_until_tick: int = 0
var damage_invulnerable_until_tick: int = 0
var modal_invulnerable_until_tick: int = 0
var next_entity_id: int = 1
var next_event_serial: int = 1
var spawn_credit: float = 0.0
var total_kills: int = 0
var normal_kills: int = 0
var elite_kills: int = 0
var boss_kills: int = 0
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


func is_invulnerable() -> bool:
	return combat_tick < maxi(
		damage_invulnerable_until_tick,
		modal_invulnerable_until_tick,
	)


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
