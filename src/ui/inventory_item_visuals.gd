class_name InventoryItemVisuals
extends RefCounted


const WEAPON_STICK: Texture2D = preload("res://assets/ui/inventory_icons/weapon_stick.png")
const WEAPON_BOW: Texture2D = preload("res://assets/ui/inventory_icons/weapon_bow.png")
const WEAPON_STAFF: Texture2D = preload("res://assets/ui/inventory_icons/weapon_staff.png")
const WEAPON_SWORD: Texture2D = preload("res://assets/ui/inventory_icons/weapon_sword.png")
const CHARM: Texture2D = preload("res://assets/ui/inventory_icons/slot_sub_weapon.png")


static func icon_for_item(item: ItemInstance) -> Texture2D:
	if item == null:
		return null
	if item.category == GameTypes.ItemCategory.CHARM:
		return CHARM
	return icon_for_weapon_type(item.weapon_type)


static func icon_for_weapon_type(weapon_type: int) -> Texture2D:
	match weapon_type:
		GameTypes.WeaponType.BOW:
			return WEAPON_BOW
		GameTypes.WeaponType.STAFF:
			return WEAPON_STAFF
		GameTypes.WeaponType.SWORD:
			return WEAPON_SWORD
	return WEAPON_STICK


static func icon_for_slot(slot: int) -> Texture2D:
	return WEAPON_STICK if GameTypes.is_weapon_slot(slot as GameTypes.EquipmentSlot) else CHARM


static func slot_label(slot: int) -> String:
	match slot:
		GameTypes.EquipmentSlot.WEAPON_1:
			return "武器1"
		GameTypes.EquipmentSlot.WEAPON_2:
			return "武器2"
		GameTypes.EquipmentSlot.WEAPON_3:
			return "武器3"
		GameTypes.EquipmentSlot.CHARM_1:
			return "お守り1"
		GameTypes.EquipmentSlot.CHARM_2:
			return "お守り2"
		GameTypes.EquipmentSlot.CHARM_3:
			return "お守り3"
	return "不明"


static func item_type_label(item: ItemInstance) -> String:
	if item == null:
		return "不明"
	if item.category == GameTypes.ItemCategory.CHARM:
		return "お守り"
	return weapon_type_label(item.weapon_type)


static func weapon_type_label(weapon_type: int) -> String:
	match weapon_type:
		GameTypes.WeaponType.BOW:
			return "弓"
		GameTypes.WeaponType.STAFF:
			return "杖"
		GameTypes.WeaponType.SWORD:
			return "剣"
		GameTypes.WeaponType.WOOD_STICK:
			return "木の棒"
	return "武器"
