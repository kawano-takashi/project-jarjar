class_name RewardRoll
extends RefCounted


var reward_id: String = ""
var wave_number: int = 0
var acquired_tick: int = 0
var is_guaranteed_weapon: bool = false
var source: GameTypes.RewardSource = GameTypes.RewardSource.NORMAL
var item: ItemInstance = null
var rarity_for_presentation: GameTypes.Rarity = GameTypes.Rarity.COMMON
var revealed: bool = false
