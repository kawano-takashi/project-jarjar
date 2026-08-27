class_name RewardRoll
extends RefCounted


var reward_id: String = ""
var wave_number: int = 0
var acquired_tick: int = 0
var is_guaranteed_main_weapon: bool = false
var kind: GameTypes.RewardKind = GameTypes.RewardKind.EQUIPMENT
var equipment: ItemInstance = null
var skill_id: StringName = &""
var rarity_for_presentation: int = -1
var revealed: bool = false
