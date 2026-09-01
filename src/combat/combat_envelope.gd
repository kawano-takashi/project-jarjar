class_name CombatEnvelope
extends RefCounted


const ARENA_HALF_EXTENT: float = 15.0
const ARENA_SIZE: Vector2 = Vector2(ARENA_HALF_EXTENT * 2.0, ARENA_HALF_EXTENT * 2.0)
const ARENA_MIN: Vector2 = Vector2(-ARENA_HALF_EXTENT, -ARENA_HALF_EXTENT)
const ARENA_MAX: Vector2 = Vector2(ARENA_HALF_EXTENT, ARENA_HALF_EXTENT)

const PLAYER_BODY_RADIUS: float = 0.45
const PLAYER_CENTER_LIMIT: float = 14.55
const PLAYER_CENTER_MIN: Vector2 = Vector2(-PLAYER_CENTER_LIMIT, -PLAYER_CENTER_LIMIT)
const PLAYER_CENTER_MAX: Vector2 = Vector2(PLAYER_CENTER_LIMIT, PLAYER_CENTER_LIMIT)

const TARGET_CENTER_RADIUS: float = 8.0
const EFFECT_OUTER_RADIUS: float = 9.0
const DAMAGE_CENTER_RADIUS: float = 10.0
const BOT_AWARENESS_RADIUS: float = 10.0
const NORMAL_SPAWN_MIN_DISTANCE: float = 9.0

const NORMAL_ENTRY_TICKS: int = 21
const ELITE_ENTRY_TICKS: int = 36
const BOSS_ENTRY_TICKS: int = 60
const BOSS_CHARGE_TICKS: int = 30

const CAMERA_SIZE: float = 18.0
const CAMERA_FOLLOW_TAU_SECONDS: float = 0.12


static func entry_ticks_for_enemy_type(enemy_type: GameTypes.EnemyType) -> int:
	match enemy_type:
		GameTypes.EnemyType.ELITE:
			return ELITE_ENTRY_TICKS
		GameTypes.EnemyType.BOSS:
			return BOSS_ENTRY_TICKS
		_:
			return NORMAL_ENTRY_TICKS


static func enemy_center_limit(body_radius: float) -> float:
	return maxf(0.0, ARENA_HALF_EXTENT - maxf(0.0, body_radius))
