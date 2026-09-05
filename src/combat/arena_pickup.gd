class_name ArenaPickup
extends RefCounted


enum Kind { CHEST, HEAL, VACUUM, STOP }

var pickup_id: int = -1
var kind: Kind = Kind.HEAL
var position: Vector2 = Vector2.ZERO
var source_serial: int = -1
var chest_kind: GameTypes.ChestKind = GameTypes.ChestKind.NORMAL
var active: bool = true
var effect_counts: PackedInt32Array = PackedInt32Array()


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
	effect_counts.resize(Kind.size())
	effect_counts.fill(0)
	effect_counts[int(kind)] = 1


func deactivate() -> void:
	pickup_id = -1
	kind = Kind.HEAL
	position = Vector2.ZERO
	source_serial = -1
	chest_kind = GameTypes.ChestKind.NORMAL
	active = false
	if effect_counts.size() != Kind.size():
		effect_counts.resize(Kind.size())
	effect_counts.fill(0)


func add_effect(effect_kind: Kind, count: int = 1) -> void:
	if not active or effect_kind == Kind.CHEST or count <= 0:
		return
	if effect_counts.size() != Kind.size():
		effect_counts.resize(Kind.size())
	effect_counts[int(effect_kind)] += count


func effect_count(effect_kind: Kind) -> int:
	if not active or effect_counts.size() != Kind.size():
		return 0
	return effect_counts[int(effect_kind)]


func total_effect_count() -> int:
	var total: int = 0
	for count: int in effect_counts:
		total += count
	return total


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
