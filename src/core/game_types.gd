class_name GameTypes
extends RefCounted


enum EquipmentSlot { MAIN_WEAPON, SUB_WEAPON, HEAD, BODY, HANDS, FEET }
enum MainWeaponType { UNCLASSIFIED, BOW, STAFF, SWORD }
enum Rarity { COMMON, RARE, EPIC, LEGENDARY, UNIQUE }
enum TriggerType { TIME, PRIMARY_ATTACK_COUNT, KILL_COUNT, HIT_COUNT }
enum RunPhase { BOOT, TITLE, COMBAT, REWARD_REVEAL, INVENTORY, RESULT, FAILED }
enum EnemyType { TRACKER, FAST, ARMORED, RANGED, ELITE, BOSS }
enum RewardKind { EQUIPMENT, SKILL }
enum RewardSource { NORMAL, ELITE, BOSS, FALLBACK }


static func equipment_slot_to_key(value: EquipmentSlot) -> StringName:
	match value:
		EquipmentSlot.MAIN_WEAPON:
			return &"main_weapon"
		EquipmentSlot.SUB_WEAPON:
			return &"sub_weapon"
		EquipmentSlot.HEAD:
			return &"head"
		EquipmentSlot.BODY:
			return &"body"
		EquipmentSlot.HANDS:
			return &"hands"
		EquipmentSlot.FEET:
			return &"feet"
	return &""


static func main_weapon_type_to_key(value: MainWeaponType) -> StringName:
	match value:
		MainWeaponType.UNCLASSIFIED:
			return &"unclassified"
		MainWeaponType.BOW:
			return &"bow"
		MainWeaponType.STAFF:
			return &"staff"
		MainWeaponType.SWORD:
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
		Rarity.UNIQUE:
			return &"unique"
	return &""


static func trigger_type_to_key(value: TriggerType) -> StringName:
	match value:
		TriggerType.TIME:
			return &"time"
		TriggerType.PRIMARY_ATTACK_COUNT:
			return &"primary_attack_count"
		TriggerType.KILL_COUNT:
			return &"kill_count"
		TriggerType.HIT_COUNT:
			return &"hit_count"
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


static func reward_kind_to_key(value: RewardKind) -> StringName:
	match value:
		RewardKind.EQUIPMENT:
			return &"equipment"
		RewardKind.SKILL:
			return &"skill"
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
