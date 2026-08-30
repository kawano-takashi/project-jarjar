class_name ItemInstance
extends RefCounted


var item_id: String = ""
var item_seed: int = 0
var category: GameTypes.ItemCategory = GameTypes.ItemCategory.WEAPON
var weapon_type: GameTypes.WeaponType = GameTypes.WeaponType.NONE
var rarity: GameTypes.Rarity = GameTypes.Rarity.COMMON
var affixes: Array[AffixRoll] = []
var display_name: String = ""
var locked: bool = false
