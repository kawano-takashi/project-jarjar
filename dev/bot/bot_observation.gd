extends RefCounted

## Values only: never attach entities, Resources, RNGs or simulation references.
enum LootKind { XP, CHEST, EVOLUTION_CHEST, POWERUP, NODE }

class Body:
	extends RefCounted
	var position := Vector2.ZERO
	var kind: int = 0
	var radius: float = 0.0
	var materializing: bool = false

var tick: int = 0
var phase: GameTypes.RunPhase = GameTypes.RunPhase.COMBAT
var player_position := Vector2.ZERO
var camera_transform := Transform3D.IDENTITY
var viewport_size := Vector2i(1920, 1080)
var hp: float = 0.0
var max_hp: float = 0.0
var level: int = 1
var build_maxed: bool = false
var boss_active: bool = false
var boss_hp: float = 0.0
var weapons: Array[Dictionary] = []
var passives: Array[Dictionary] = []
var options: Array[Dictionary] = []
var enemies: Array[Body] = []
var bullets: Array[Body] = []
## Visible allied needles let the controller estimate firing cadence.
var needles: PackedVector2Array = []
## Each entry is (visual kind, world X, world Z, rendered scale).
## Packed values avoid allocating thousands of pickup objects every tick.
var loot: PackedVector4Array = []
## Visible warning geometry, not enemy action timers or future spawns.
var warnings: Array[Dictionary] = []
