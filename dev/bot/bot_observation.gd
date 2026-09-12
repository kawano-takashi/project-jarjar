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
var world_origin := Vector2i.ZERO
## The same compass cues as the HUD, without hidden target positions or distance.
var chest_guidance: Array[Dictionary] = []
var camera_transform := Transform3D.IDENTITY
var camera_projection := Projection.IDENTITY
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
var _enemies: Array[Body] = []
var _packed_enemies: Dictionary = {}
var enemies: Array[Body]:
	get:
		if not _packed_enemies.is_empty():
			_enemies = unpack_bodies(_packed_enemies)
			_packed_enemies = {}
		return _enemies
	set(value):
		_enemies = value
		_packed_enemies = {}
var _bullets: Array[Body] = []
var _packed_bullets: Dictionary = {}
var bullets: Array[Body]:
	get:
		if not _packed_bullets.is_empty():
			_bullets = unpack_bodies(_packed_bullets)
			_packed_bullets = {}
		return _bullets
	set(value):
		_bullets = value
		_packed_bullets = {}
## Visible allied needles let the controller estimate firing cadence.
var needles: PackedVector2Array = []
## Each entry is (visual kind, world X, world Z, rendered scale).
## Packed values avoid allocating thousands of pickup objects every tick.
var loot: PackedVector4Array = []
## Visible warning geometry, not enemy action timers or future spawns.
var warnings: Array[Dictionary] = []
## Clipped visible line endpoints (start X/Z, end X/Z) and inward unit normals.
## No enclosure center, radius, lifetime or invisible edges enter this frame.
var boundary_segments: PackedVector4Array = []
var boundary_normals: PackedVector2Array = []


## The fast consumer uses packed values directly. Body objects are created only
## for callers that need the editable observation API.
func set_enemy_values(values: Dictionary) -> void:
	_packed_enemies = values
	_enemies = []


func enemy_values() -> Dictionary:
	return _packed_enemies if not _packed_enemies.is_empty() else pack_bodies(_enemies)


static func pack_bodies(bodies: Array[Body]) -> Dictionary:
	var positions := PackedVector2Array()
	var radii := PackedFloat64Array()
	var kinds := PackedInt32Array()
	var materializing := PackedByteArray()
	positions.resize(bodies.size())
	radii.resize(bodies.size())
	kinds.resize(bodies.size())
	materializing.resize(bodies.size())
	for index: int in bodies.size():
		positions[index] = bodies[index].position
		radii[index] = bodies[index].radius
		kinds[index] = bodies[index].kind
		materializing[index] = int(bodies[index].materializing)
	return {"positions": positions, "radii": radii, "kinds": kinds, "materializing": materializing}


static func unpack_bodies(values: Dictionary) -> Array[Body]:
	var positions: PackedVector2Array = values["positions"]
	var radii: PackedFloat64Array = values["radii"]
	var kinds: PackedInt32Array = values["kinds"]
	var materializing: PackedByteArray = values["materializing"]
	var bodies: Array[Body] = []
	for index: int in positions.size():
		var body := Body.new()
		body.position = positions[index]
		body.radius = radii[index]
		body.kind = kinds[index]
		body.materializing = materializing[index] != 0
		bodies.append(body)
	return bodies


func set_bullet_values(values: Dictionary) -> void:
	_packed_bullets = values
	_bullets = []


func bullet_values() -> Dictionary:
	return _packed_bullets if not _packed_bullets.is_empty() else pack_bodies(_bullets)
