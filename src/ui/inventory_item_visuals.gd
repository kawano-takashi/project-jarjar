class_name InventoryItemVisuals
extends RefCounted


const WEAPON_STICK: Texture2D = preload("res://assets/ui/inventory_icons/weapon_stick.png")
const WEAPON_BOW: Texture2D = preload("res://assets/ui/inventory_icons/weapon_bow.png")
const WEAPON_STAFF: Texture2D = preload("res://assets/ui/inventory_icons/weapon_staff.png")
const WEAPON_SWORD: Texture2D = preload("res://assets/ui/inventory_icons/weapon_sword.png")
const SLOT_SUB_WEAPON: Texture2D = preload("res://assets/ui/inventory_icons/slot_sub_weapon.png")
const SLOT_HEAD: Texture2D = preload("res://assets/ui/inventory_icons/slot_head.png")
const SLOT_BODY: Texture2D = preload("res://assets/ui/inventory_icons/slot_body.png")
const SLOT_HANDS: Texture2D = preload("res://assets/ui/inventory_icons/slot_hands.png")
const SLOT_FEET: Texture2D = preload("res://assets/ui/inventory_icons/slot_feet.png")


static func icon_for_item(item: ItemInstance) -> Texture2D:
	if item == null:
		return null
	return icon_for_slot(item.slot, item.main_weapon_type)


static func icon_for_slot(slot: int, main_weapon_type: int = GameTypes.MainWeaponType.UNCLASSIFIED) -> Texture2D:
	match slot:
		GameTypes.EquipmentSlot.MAIN_WEAPON:
			match main_weapon_type:
				GameTypes.MainWeaponType.BOW:
					return WEAPON_BOW
				GameTypes.MainWeaponType.STAFF:
					return WEAPON_STAFF
				GameTypes.MainWeaponType.SWORD:
					return WEAPON_SWORD
				_:
					return WEAPON_STICK
		GameTypes.EquipmentSlot.SUB_WEAPON:
			return SLOT_SUB_WEAPON
		GameTypes.EquipmentSlot.HEAD:
			return SLOT_HEAD
		GameTypes.EquipmentSlot.BODY:
			return SLOT_BODY
		GameTypes.EquipmentSlot.HANDS:
			return SLOT_HANDS
		GameTypes.EquipmentSlot.FEET:
			return SLOT_FEET
	return null


static func slot_label(slot: int) -> String:
	match slot:
		GameTypes.EquipmentSlot.MAIN_WEAPON:
			return "主武器"
		GameTypes.EquipmentSlot.SUB_WEAPON:
			return "触媒"
		GameTypes.EquipmentSlot.HEAD:
			return "兜"
		GameTypes.EquipmentSlot.BODY:
			return "鎧"
		GameTypes.EquipmentSlot.HANDS:
			return "手甲"
		GameTypes.EquipmentSlot.FEET:
			return "靴"
	return "不明"


static func item_type_label(item: ItemInstance) -> String:
	if item == null:
		return "不明"
	if item.slot != GameTypes.EquipmentSlot.MAIN_WEAPON:
		return slot_label(item.slot)
	return "%s／%s" % [slot_label(item.slot), main_weapon_type_label(item.main_weapon_type)]


static func main_weapon_type_label(main_weapon_type: int) -> String:
	match main_weapon_type:
		GameTypes.MainWeaponType.BOW:
			return "弓"
		GameTypes.MainWeaponType.STAFF:
			return "杖"
		GameTypes.MainWeaponType.SWORD:
			return "剣"
	return "木の棒"
