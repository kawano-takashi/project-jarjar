class_name ArenaPickup
extends RefCounted


enum Kind { CHEST, HEAL, VACUUM, STOP }

const CHEST_MESH: Mesh = preload("res://scenes/gameplay/chest_mesh.tres")
const EVOLUTION_CHEST_MESH: Mesh = preload("res://scenes/gameplay/evolution_chest_mesh.tres")

var pickup_id: int = -1
var kind: Kind = Kind.HEAL
var position: Vector2 = Vector2.ZERO
var source_serial: int = -1
var chest_kind: GameTypes.ChestKind = GameTypes.ChestKind.NORMAL
var active: bool = true


func _init(
	p_pickup_id: int = -1,
	p_kind: Kind = Kind.HEAL,
	p_position: Vector2 = Vector2.ZERO,
	p_source_serial: int = -1,
) -> void:
	activate(p_pickup_id, p_kind, p_position, p_source_serial)


func activate(
	p_pickup_id: int,
	p_kind: Kind,
	p_position: Vector2,
	p_source_serial: int,
) -> void:
	pickup_id = p_pickup_id
	kind = p_kind
	position = p_position
	source_serial = p_source_serial
	chest_kind = GameTypes.ChestKind.NORMAL
	active = true


func deactivate() -> void:
	pickup_id = -1
	kind = Kind.HEAL
	position = Vector2.ZERO
	source_serial = -1
	chest_kind = GameTypes.ChestKind.NORMAL
	active = false


func chest_visual_bounds() -> AABB:
	var mesh: Mesh = EVOLUTION_CHEST_MESH if chest_kind == GameTypes.ChestKind.EVOLUTION_CAPABLE else CHEST_MESH
	return transform() * mesh.get_aabb()


func transform() -> Transform3D:
	var scale_value: float = 1.0
	var height: float = 0.3
	if kind == Kind.CHEST:
		scale_value = 1.35
		height = 0.38
	return Transform3D(
		Basis.IDENTITY.scaled(Vector3.ONE * scale_value),
		Vector3(position.x, height, position.y),
	)
