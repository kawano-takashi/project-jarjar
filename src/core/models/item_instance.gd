class_name ItemInstance
extends RefCounted


var item_id: String = ""
var item_seed: int = 0
var slot: GameTypes.EquipmentSlot = GameTypes.EquipmentSlot.MAIN_WEAPON
var main_weapon_type: GameTypes.MainWeaponType = GameTypes.MainWeaponType.UNCLASSIFIED
var rarity: GameTypes.Rarity = GameTypes.Rarity.COMMON
var affixes: Array[AffixRoll] = []
var unique_id: StringName = &""
var display_name: String = ""
var locked: bool = false
