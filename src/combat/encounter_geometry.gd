class_name EncounterGeometry
extends RefCounted


# The same closed polygon is used by physical constraints, drawing and bot vision.
const SEGMENT_COUNT: int = 128
const BOUNDARY_HEIGHT: float = 0.08
const _APOTHEM_FACTOR: float = cos(PI / SEGMENT_COUNT)

static var _vertex_directions: PackedVector2Array = []
static var _face_normals: PackedVector2Array = []


static func _static_init() -> void:
	for index: int in range(SEGMENT_COUNT):
		_vertex_directions.append(Vector2.from_angle(TAU * float(index) / SEGMENT_COUNT))
		_face_normals.append(Vector2.from_angle(TAU * (float(index) + 0.5) / SEGMENT_COUNT))


static func points(center: Vector2, radius: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	for direction: Vector2 in _vertex_directions:
		result.append(center + direction * radius)
	return result


static func constrain_body(position: Vector2, body_radius: float, center: Vector2, radius: float) -> Vector2:
	var offset: Vector2 = position - center
	var apothem: float = radius * _APOTHEM_FACTOR - body_radius
	# A radial projection first handles large displacements / shrinking past a body.
	# Projecting onto the closest polygon face then permits motion along that face.
	offset = offset.limit_length(maxf(0.0, radius - body_radius))
	for outward: Vector2 in _face_normals:
		var excess: float = offset.dot(outward) - apothem
		if excess > 0.0:
			offset -= outward * excess
	return center + offset
