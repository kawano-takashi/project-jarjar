class_name OpenFieldGround
extends Node3D

## Visual chunks only. They have no walls or collision shapes.
const CHUNK_SIZE: int = 16
const CHUNKS_PER_ORIGIN: int = int(float(CombatSimulation.ORIGIN_STEP_METERS) / CHUNK_SIZE)

var run_seed: int = 0
var _chunks: Dictionary[Vector2i, Dictionary] = {}
var _region := Rect2i()
var _origin := Vector2i.ZERO
var _floor: MultiMeshInstance3D
var _stones: MultiMeshInstance3D
var _lines: MultiMeshInstance3D


func _ready() -> void:
	_floor = _instances(Vector3(CHUNK_SIZE, 0.08, CHUNK_SIZE), Color.WHITE, true)
	_stones = _instances(Vector3.ONE, Color(0.22, 0.29, 0.28), false)
	_lines = _instances(Vector3.ONE, Color(0.13, 0.23, 0.21), false)


func update_view(view: ArenaView, origin: Vector2i) -> void:
	var coverage: Rect2 = view.ground_rect().grow(CHUNK_SIZE)
	var lower := Vector2i(floori(coverage.position.x / CHUNK_SIZE), floori(coverage.position.y / CHUNK_SIZE))
	var upper := Vector2i(floori(coverage.end.x / CHUNK_SIZE), floori(coverage.end.y / CHUNK_SIZE))
	var region := Rect2i(lower + origin * CHUNKS_PER_ORIGIN, upper - lower + Vector2i.ONE)
	if region == _region and origin == _origin:
		return
	_region = region
	_origin = origin
	for chunk: Vector2i in _chunks.keys():
		if not region.has_point(chunk):
			_chunks.erase(chunk)
	var floors: Array[Transform3D] = []
	var colors: Array[Color] = []
	var stones: Array[Transform3D] = []
	var lines: Array[Transform3D] = []
	for y: int in range(region.position.y, region.end.y):
		for x: int in range(region.position.x, region.end.x):
			var chunk := Vector2i(x, y)
			if not _chunks.has(chunk):
				_chunks[chunk] = chunk_layout(run_seed, chunk)
			var layout: Dictionary = _chunks[chunk]
			var local: Vector2i = (chunk - origin * CHUNKS_PER_ORIGIN) * CHUNK_SIZE
			var offset := Vector3(local.x, 0.0, local.y)
			floors.append(Transform3D(Basis.IDENTITY, offset + Vector3(8.0, -0.04, 8.0)))
			colors.append(layout["color"])
			for stone: Transform3D in layout["stones"]:
				stone.origin += offset
				stones.append(stone)
			for index: int in range(8):
				lines.append(Transform3D(Basis.IDENTITY.scaled(Vector3(16.0, 0.008, 0.018)), offset + Vector3(8.0, 0.004, index * 2.0)))
				lines.append(Transform3D(Basis.IDENTITY.scaled(Vector3(0.018, 0.008, 16.0)), offset + Vector3(index * 2.0, 0.004, 8.0)))
	_upload(_floor, floors, colors)
	_upload(_stones, stones)
	_upload(_lines, lines)


## Pure layout: revisiting a chunk regenerates exactly the same landmarks.
static func chunk_layout(seed_value: int, chunk: Vector2i) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = SeedService.derive(seed_value, StringName("ground:%d:%d" % [chunk.x, chunk.y]))
	var tint: float = rng.randf_range(0.94, 1.06)
	var stones: Array[Transform3D] = []
	var center := Vector3(rng.randf_range(3.0, 13.0), 0.0, rng.randf_range(3.0, 13.0))
	var angle: float = rng.randf_range(0.0, TAU)
	for index: int in range(rng.randi_range(3, 6)):
		var height: float = rng.randf_range(0.06, 0.22)
		var scale_value := Vector3(rng.randf_range(0.4, 1.1), height, rng.randf_range(0.5, 1.5))
		var stone_position: Vector3 = center + Vector3(rng.randf_range(-2.0, 2.0), height * 0.5, rng.randf_range(-2.0, 2.0))
		stones.append(Transform3D(Basis(Vector3.UP, angle + rng.randf_range(-0.2, 0.2)).scaled_local(scale_value), stone_position))
	return {"color": Color(0.105 * tint, 0.165 * tint, 0.16 * tint), "stones": stones}


func _instances(size: Vector3, color: Color, use_colors: bool) -> MultiMeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.vertex_color_use_as_albedo = use_colors
	material.roughness = 1.0
	mesh.material = material
	var instance := MultiMeshInstance3D.new()
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.multimesh = MultiMesh.new()
	instance.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	instance.multimesh.use_colors = use_colors
	instance.multimesh.mesh = mesh
	add_child(instance)
	return instance


func _upload(instance: MultiMeshInstance3D, transforms: Array[Transform3D], colors: Array[Color] = []) -> void:
	var mesh: MultiMesh = instance.multimesh
	if mesh.instance_count < transforms.size():
		mesh.instance_count = transforms.size()
	for index: int in transforms.size():
		mesh.set_instance_transform(index, transforms[index])
		if not colors.is_empty():
			mesh.set_instance_color(index, colors[index])
	mesh.visible_instance_count = transforms.size()
