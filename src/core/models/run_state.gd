class_name RunState
extends RefCounted


const INVENTORY_CAPACITY: int = 36

var run_seed: int = 0
var rng_streams: RunRngStreams = null
var phase: GameTypes.RunPhase = GameTypes.RunPhase.BOOT
var wave_number: int = 1
var physics_tick: int = 0
var time_remaining: float = 0.0
var wave_cleared: bool = false
var boss_defeated: bool = false
var current_hp: float = 100.0
var max_hp: float = 100.0
var equipped: Dictionary[GameTypes.EquipmentSlot, ItemInstance] = {
	GameTypes.EquipmentSlot.WEAPON_1: null,
	GameTypes.EquipmentSlot.WEAPON_2: null,
	GameTypes.EquipmentSlot.WEAPON_3: null,
	GameTypes.EquipmentSlot.CHARM_1: null,
	GameTypes.EquipmentSlot.CHARM_2: null,
	GameTypes.EquipmentSlot.CHARM_3: null,
}
var inventory: Array[ItemInstance] = []
var overflow: Array[ItemInstance] = []
var unopened_rewards: Array[RewardRoll] = []
var drop_serial: int = 0
var next_entity_id: int = 0
var next_event_serial: int = 0
var spawn_credit: float = 0.0
var non_boss_spawned: int = 0
var wave_kills: int = 0
var total_kills: int = 0
var normal_kills: int = 0
var post_quota_kills: int = 0
var elite_kills: int = 0
var boss_kills: int = 0
var cleared_waves: int = 0
var wave_chests: int = 0
var total_chests: int = 0
var fusion_count: int = 0
var peak_dps: float = 0.0
var recent_damage_samples: Array[DamageSample] = []
var score_breakdown: Dictionary = {}


func _init() -> void:
	inventory.resize(INVENTORY_CAPACITY)
