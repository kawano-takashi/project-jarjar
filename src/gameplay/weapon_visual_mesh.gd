@tool
class_name WeaponVisualMesh
extends ArrayMesh

## A real planar silhouette, also available to the bot through SceneState.
@export_enum("Default", "Wave", "Homing", "Needle", "Crystal", "Ring", "Orbital", "Mass", "Field")
var visual_kind: int = 0:
	set(value):
		visual_kind = clampi(value, 0, 8)
		_rebuild()


func _init() -> void:
	_rebuild()


func _rebuild() -> void:
	clear_surfaces()
	var points := PackedVector2Array()
	match visual_kind:
		2:
			# The rounded rear joins the pointed nose through its upper shoulders.
			points = PackedVector2Array([
				Vector2(0, 1), Vector2(-0.58, 0.05), Vector2(-0.68, -0.38),
				Vector2(-0.48, -0.78), Vector2(0, -1), Vector2(0.48, -0.78),
				Vector2(0.68, -0.38), Vector2(0.58, 0.05),
			])
		3:
			points = PackedVector2Array([Vector2(0, 1), Vector2(-0.4, 0.3), Vector2(-0.32, -1), Vector2(0.32, -1), Vector2(0.4, 0.3)])
		4:
			points = PackedVector2Array([Vector2(0, 1), Vector2(-0.72, 0), Vector2(0, -1), Vector2(0.72, 0)])
		5:
			# A gap at the front identifies the return direction even in a still frame.
			for index: int in range(41):
				var angle: float = 0.32 + (TAU - 0.64) * float(index) / 40.0
				points.append(Vector2(sin(angle), cos(angle)))
			for index: int in range(40, -1, -1):
				var angle: float = 0.32 + (TAU - 0.64) * float(index) / 40.0
				points.append(Vector2(sin(angle), cos(angle)) * 0.62)
		6:
			points = PackedVector2Array([Vector2(0, 1), Vector2(-0.866, -0.5), Vector2(0.866, -0.5)])
		_:
			for index: int in range(40):
				points.append(Vector2.from_angle(TAU * float(index) / 40.0))
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var body_scale: Vector2 = WeaponVisualStyle.PROJECTILE_BODY_SCALE.get(visual_kind, Vector2.ONE)
	for point: Vector2 in points:
		vertices.append(Vector3(point.x * body_scale.x, 0.0, point.y * body_scale.y))
		normals.append(Vector3.UP)
		uvs.append(point * 0.5 + Vector2.ONE * 0.5)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = Geometry2D.triangulate_polygon(points)
	add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	surface_set_material(0, WeaponVisualStyle.projectile_material(visual_kind))
