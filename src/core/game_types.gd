class_name GameTypes
extends RefCounted


enum RunPhase { BOOT, TITLE, COMBAT, LEVEL_UP, CHEST_REWARD, RESULT, FAILED }
enum UpgradeKind { WEAPON, PASSIVE }
enum WeaponBehavior {
	MELEE_WAVE,
	HOMING_PROJECTILE,
	DIRECTIONAL_PROJECTILE,
	ARC_PROJECTILE,
	RETURNING_RING,
	ORBITAL,
	MASS_PROJECTILE,
	AURA,
}
enum EnemyType { PURSUER, SWARMER, BULWARK, SHOOTER, ELITE, BOSS }
enum ChestOutcomeKind { EVOLUTION, UPGRADE, FULL_HEAL }
enum NodeDropType { NONE, HEAL, VACUUM, STOP }


static func run_phase_to_key(value: RunPhase) -> StringName:
	match value:
		RunPhase.BOOT:
			return &"boot"
		RunPhase.TITLE:
			return &"title"
		RunPhase.COMBAT:
			return &"combat"
		RunPhase.LEVEL_UP:
			return &"level_up"
		RunPhase.CHEST_REWARD:
			return &"chest_reward"
		RunPhase.RESULT:
			return &"result"
		RunPhase.FAILED:
			return &"failed"
	return &""


static func upgrade_kind_to_key(value: UpgradeKind) -> StringName:
	match value:
		UpgradeKind.WEAPON:
			return &"weapon"
		UpgradeKind.PASSIVE:
			return &"passive"
	return &""


static func weapon_behavior_to_key(value: WeaponBehavior) -> StringName:
	match value:
		WeaponBehavior.MELEE_WAVE:
			return &"melee_wave"
		WeaponBehavior.HOMING_PROJECTILE:
			return &"homing_projectile"
		WeaponBehavior.DIRECTIONAL_PROJECTILE:
			return &"directional_projectile"
		WeaponBehavior.ARC_PROJECTILE:
			return &"arc_projectile"
		WeaponBehavior.RETURNING_RING:
			return &"returning_ring"
		WeaponBehavior.ORBITAL:
			return &"orbital"
		WeaponBehavior.MASS_PROJECTILE:
			return &"mass_projectile"
		WeaponBehavior.AURA:
			return &"aura"
	return &""


static func enemy_type_to_key(value: EnemyType) -> StringName:
	match value:
		EnemyType.PURSUER:
			return &"pursuer"
		EnemyType.SWARMER:
			return &"swarmer"
		EnemyType.BULWARK:
			return &"bulwark"
		EnemyType.SHOOTER:
			return &"shooter"
		EnemyType.ELITE:
			return &"elite"
		EnemyType.BOSS:
			return &"boss"
	return &""


static func chest_outcome_kind_to_key(value: ChestOutcomeKind) -> StringName:
	match value:
		ChestOutcomeKind.EVOLUTION:
			return &"evolution"
		ChestOutcomeKind.UPGRADE:
			return &"upgrade"
		ChestOutcomeKind.FULL_HEAL:
			return &"full_heal"
	return &""


static func node_drop_type_to_key(value: NodeDropType) -> StringName:
	match value:
		NodeDropType.NONE:
			return &"none"
		NodeDropType.HEAL:
			return &"heal"
		NodeDropType.VACUUM:
			return &"vacuum"
		NodeDropType.STOP:
			return &"stop"
	return &""
