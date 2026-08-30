class_name GameTypes
extends RefCounted


enum ItemCategory { WEAPON, CHARM }
enum EquipmentSlot { WEAPON_1, WEAPON_2, WEAPON_3, CHARM_1, CHARM_2, CHARM_3 }
enum WeaponType { NONE, WOOD_STICK, BOW, STAFF, SWORD }
enum Rarity { COMMON, RARE, EPIC, LEGENDARY }
enum RunPhase { BOOT, TITLE, COMBAT, REWARD_REVEAL, INVENTORY, RESULT, FAILED }
enum EnemyType { TRACKER, FAST, ARMORED, RANGED, ELITE, BOSS }
enum RewardSource { NORMAL, ELITE, BOSS, FALLBACK }


static func equipment_slot_to_key(value: EquipmentSlot) -> StringName:
	match value:
		EquipmentSlot.WEAPON_1:
			return &"weapon_1"
		EquipmentSlot.WEAPON_2:
			return &"weapon_2"
		EquipmentSlot.WEAPON_3:
			return &"weapon_3"
		EquipmentSlot.CHARM_1:
			return &"charm_1"
		EquipmentSlot.CHARM_2:
			return &"charm_2"
		EquipmentSlot.CHARM_3:
			return &"charm_3"
	return &""


static func item_category_to_key(value: ItemCategory) -> StringName:
	match value:
		ItemCategory.WEAPON:
			return &"weapon"
		ItemCategory.CHARM:
			return &"charm"
	return &""


static func weapon_type_to_key(value: WeaponType) -> StringName:
	match value:
		WeaponType.NONE:
			return &"none"
		WeaponType.WOOD_STICK:
			return &"wood_stick"
		WeaponType.BOW:
			return &"bow"
		WeaponType.STAFF:
			return &"staff"
		WeaponType.SWORD:
			return &"sword"
	return &""


static func rarity_to_key(value: Rarity) -> StringName:
	match value:
		Rarity.COMMON:
			return &"common"
		Rarity.RARE:
			return &"rare"
		Rarity.EPIC:
			return &"epic"
		Rarity.LEGENDARY:
			return &"legendary"
	return &""


static func run_phase_to_key(value: RunPhase) -> StringName:
	match value:
		RunPhase.BOOT:
			return &"boot"
		RunPhase.TITLE:
			return &"title"
		RunPhase.COMBAT:
			return &"combat"
		RunPhase.REWARD_REVEAL:
			return &"reward_reveal"
		RunPhase.INVENTORY:
			return &"inventory"
		RunPhase.RESULT:
			return &"result"
		RunPhase.FAILED:
			return &"failed"
	return &""


static func enemy_type_to_key(value: EnemyType) -> StringName:
	match value:
		EnemyType.TRACKER:
			return &"tracker"
		EnemyType.FAST:
			return &"fast"
		EnemyType.ARMORED:
			return &"armored"
		EnemyType.RANGED:
			return &"ranged"
		EnemyType.ELITE:
			return &"elite"
		EnemyType.BOSS:
			return &"boss"
	return &""


static func reward_source_to_key(value: RewardSource) -> StringName:
	match value:
		RewardSource.NORMAL:
			return &"normal"
		RewardSource.ELITE:
			return &"elite"
		RewardSource.BOSS:
			return &"boss"
		RewardSource.FALLBACK:
			return &"fallback"
	return &""


static func is_weapon_slot(value: EquipmentSlot) -> bool:
	return value in [
		EquipmentSlot.WEAPON_1,
		EquipmentSlot.WEAPON_2,
		EquipmentSlot.WEAPON_3,
	]


static func category_for_slot(value: EquipmentSlot) -> ItemCategory:
	return ItemCategory.WEAPON if is_weapon_slot(value) else ItemCategory.CHARM


static func weapon_slots() -> Array[EquipmentSlot]:
	return [
		EquipmentSlot.WEAPON_1,
		EquipmentSlot.WEAPON_2,
		EquipmentSlot.WEAPON_3,
	]


static func charm_slots() -> Array[EquipmentSlot]:
	return [
		EquipmentSlot.CHARM_1,
		EquipmentSlot.CHARM_2,
		EquipmentSlot.CHARM_3,
	]
