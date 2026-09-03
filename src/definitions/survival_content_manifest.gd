class_name SurvivalContentManifest
extends Resource


const DEFAULT_XP_EARLY_MAX_LEVEL: int = 19
const DEFAULT_XP_EARLY_COEFFICIENT: int = 10
const DEFAULT_XP_EARLY_OFFSET: int = -5
const DEFAULT_XP_LEVEL_20_REQUIREMENT: int = 795
const DEFAULT_XP_MIDDLE_MAX_LEVEL: int = 39
const DEFAULT_XP_MIDDLE_COEFFICIENT: int = 13
const DEFAULT_XP_MIDDLE_OFFSET: int = -65
const DEFAULT_XP_LEVEL_40_REQUIREMENT: int = 2855
const DEFAULT_XP_LATE_COEFFICIENT: int = 16
const DEFAULT_XP_LATE_OFFSET: int = -185
const DEFAULT_XP_GROWTH_COMPENSATION_LEVELS: Array[int] = [20, 40]
const DEFAULT_XP_GROWTH_COMPENSATION_MULTIPLIER: float = 2.0
const DEFAULT_XP_POOL_CAPACITY: int = 2048
const DEFAULT_XP_PICKUP_ATTRACT_RADIUS: float = 2.25
const DEFAULT_XP_PICKUP_COLLECT_RADIUS: float = 0.7
const DEFAULT_XP_PICKUP_SPEED: float = 14.0
const DEFAULT_XP_YIELD_PERCENT: int = 100
const DEFAULT_NORMAL_ENEMY_DAMAGE_SCALE: float = 1.0
const DEFAULT_BOSS_HP_MULTIPLIER: float = 3.75
const DEFAULT_BOSS_DAMAGE_MULTIPLIER: float = 2.28
const DEFAULT_BOSS_ACTION_RATE_MULTIPLIER: float = 1.0

@export var balance: BalanceManifest = null
@export var ticks_per_second: int = 60
@export var arena_size: Vector2 = Vector2(30.0, 30.0)
@export var boss_start_tick: int = 36000
@export var xp_early_max_level: int = DEFAULT_XP_EARLY_MAX_LEVEL
@export var xp_early_coefficient: int = DEFAULT_XP_EARLY_COEFFICIENT
@export var xp_early_offset: int = DEFAULT_XP_EARLY_OFFSET
@export var xp_level_20_requirement: int = DEFAULT_XP_LEVEL_20_REQUIREMENT
@export var xp_middle_max_level: int = DEFAULT_XP_MIDDLE_MAX_LEVEL
@export var xp_middle_coefficient: int = DEFAULT_XP_MIDDLE_COEFFICIENT
@export var xp_middle_offset: int = DEFAULT_XP_MIDDLE_OFFSET
@export var xp_level_40_requirement: int = DEFAULT_XP_LEVEL_40_REQUIREMENT
@export var xp_late_coefficient: int = DEFAULT_XP_LATE_COEFFICIENT
@export var xp_late_offset: int = DEFAULT_XP_LATE_OFFSET
@export var xp_growth_compensation_levels: PackedInt32Array = PackedInt32Array(
	DEFAULT_XP_GROWTH_COMPENSATION_LEVELS
)
@export var xp_growth_compensation_multiplier: float = DEFAULT_XP_GROWTH_COMPENSATION_MULTIPLIER
@export var xp_pool_capacity: int = DEFAULT_XP_POOL_CAPACITY
@export var xp_pickup_attract_radius: float = DEFAULT_XP_PICKUP_ATTRACT_RADIUS
@export var xp_pickup_collect_radius: float = DEFAULT_XP_PICKUP_COLLECT_RADIUS
@export var xp_pickup_speed: float = DEFAULT_XP_PICKUP_SPEED
@export_range(50, 200, 5) var xp_yield_percent: int = DEFAULT_XP_YIELD_PERCENT
@export_range(0.20, 1.10, 0.05) var normal_enemy_damage_scale: float = (
	DEFAULT_NORMAL_ENEMY_DAMAGE_SCALE
)
@export var weapon_slot_count: int = 5
@export var passive_slot_count: int = 5
@export var level_offer_count: int = 3
@export var owned_offer_attempt_count: int = 2
@export var owned_offer_luck_coefficient: float = 0.3
@export var starter_weapon_id: StringName = &"homing_core"
@export var elite_spawn_ticks: PackedInt32Array = PackedInt32Array([7200, 14400, 21600, 28800])
@export var node_site_count: int = 8
@export var active_node_count: int = 4
@export var node_respawn_ticks: int = 1800
@export var node_heal_amount: float = 30.0
@export var node_stop_ticks: int = 300
@export var node_drop_weights: PackedFloat32Array = PackedFloat32Array([0.55, 0.35, 0.07, 0.03])
@export var damage_invulnerability_ticks: int = 30
@export var modal_resume_invulnerability_ticks: int = 45
@export var boss_hp_multiplier: float = DEFAULT_BOSS_HP_MULTIPLIER
@export var boss_damage_multiplier: float = DEFAULT_BOSS_DAMAGE_MULTIPLIER
@export var boss_action_rate_multiplier: float = DEFAULT_BOSS_ACTION_RATE_MULTIPLIER
@export var boss_enrage_interval_ticks: int = 1800
@export var boss_enrage_max_stacks: int = 10
@export var boss_attack_bonus_per_stack: float = 0.10
@export var boss_interval_reduction_per_stack: float = 0.10
@export var weapons: Array[WeaponDefinition] = []
@export var passives: Array[PassiveDefinition] = []
@export var evolutions: Array[EvolutionDefinition] = []
@export var enemies: Array[EnemyDefinition] = []
@export var segments: Array[EnemySegmentDefinition] = []


static func default_required_xp_for_level(current_level: int) -> int:
	if current_level <= 0:
		return 0
	if current_level <= DEFAULT_XP_EARLY_MAX_LEVEL:
		return DEFAULT_XP_EARLY_COEFFICIENT * current_level + DEFAULT_XP_EARLY_OFFSET
	if current_level == 20:
		return DEFAULT_XP_LEVEL_20_REQUIREMENT
	if current_level <= DEFAULT_XP_MIDDLE_MAX_LEVEL:
		return DEFAULT_XP_MIDDLE_COEFFICIENT * current_level + DEFAULT_XP_MIDDLE_OFFSET
	if current_level == 40:
		return DEFAULT_XP_LEVEL_40_REQUIREMENT
	return DEFAULT_XP_LATE_COEFFICIENT * current_level + DEFAULT_XP_LATE_OFFSET


static func default_growth_multiplier_for_level(current_level: int) -> float:
	return (
		DEFAULT_XP_GROWTH_COMPENSATION_MULTIPLIER
		if current_level in DEFAULT_XP_GROWTH_COMPENSATION_LEVELS
		else 1.0
	)


func required_xp_for_level(current_level: int) -> int:
	if current_level <= 0:
		return 0
	if current_level <= xp_early_max_level:
		return xp_early_coefficient * current_level + xp_early_offset
	if current_level == 20:
		return xp_level_20_requirement
	if current_level <= xp_middle_max_level:
		return xp_middle_coefficient * current_level + xp_middle_offset
	if current_level == 40:
		return xp_level_40_requirement
	return xp_late_coefficient * current_level + xp_late_offset


func growth_multiplier_for_level(current_level: int) -> float:
	return (
		xp_growth_compensation_multiplier
		if current_level in xp_growth_compensation_levels
		else 1.0
	)
