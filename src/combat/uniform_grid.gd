class_name UniformGrid
extends RefCounted


const CELL_SIZE: float = 2.0
const ARENA_MIN: Vector2 = CombatEnvelope.ARENA_MIN
const ARENA_MAX: Vector2 = CombatEnvelope.ARENA_MAX
const COLUMN_COUNT: int = 15
const ROW_COUNT: int = 15
const CELL_COUNT: int = COLUMN_COUNT * ROW_COUNT

var _cells: Array[Array] = []


func _init() -> void:
	_cells.resize(CELL_COUNT)
	for key: int in range(CELL_COUNT):
		_cells[key] = []


func clear() -> void:
	for cell: Array in _cells:
		cell.clear()


func insert(entity_id: int, position: Vector2) -> void:
	var key: int = cell_key_for_position(position)
	var cell: Array = _cells[key]
	var insert_at: int = cell.size()
	for index: int in range(cell.size()):
		if entity_id < int(cell[index]):
			insert_at = index
			break
	cell.insert(insert_at, entity_id)


func cell_key_for_position(position: Vector2) -> int:
	var indices: Vector2i = cell_indices_for_position(position)
	return indices.x + indices.y * COLUMN_COUNT


func cell_indices_for_position(position: Vector2) -> Vector2i:
	var column: int = clampi(int(floor((position.x - ARENA_MIN.x) / CELL_SIZE)), 0, COLUMN_COUNT - 1)
	var row: int = clampi(int(floor((position.y - ARENA_MIN.y) / CELL_SIZE)), 0, ROW_COUNT - 1)
	return Vector2i(column, row)


func clamped_cell_range(aabb_min: Vector2, aabb_max: Vector2) -> Rect2i:
	var normalized_min := Vector2(minf(aabb_min.x, aabb_max.x), minf(aabb_min.y, aabb_max.y))
	var normalized_max := Vector2(maxf(aabb_min.x, aabb_max.x), maxf(aabb_min.y, aabb_max.y))
	if (
		normalized_max.x < ARENA_MIN.x
		or normalized_max.y < ARENA_MIN.y
		or normalized_min.x > ARENA_MAX.x
		or normalized_min.y > ARENA_MAX.y
	):
		return Rect2i()
	var minimum_indices: Vector2i = cell_indices_for_position(normalized_min)
	var maximum_indices: Vector2i = cell_indices_for_position(normalized_max)
	return Rect2i(minimum_indices, maximum_indices - minimum_indices + Vector2i.ONE)


func query_circle_candidates(
	center: Vector2,
	radius: float,
	padding: float,
) -> Array[int]:
	var extent: float = maxf(0.0, radius) + maxf(0.0, padding)
	return query_aabb_candidates(center - Vector2.ONE * extent, center + Vector2.ONE * extent)


func query_segment_candidates(
	segment_start: Vector2,
	segment_end: Vector2,
	padding: float,
) -> Array[int]:
	var extent: Vector2 = Vector2.ONE * maxf(0.0, padding)
	var minimum := Vector2(minf(segment_start.x, segment_end.x), minf(segment_start.y, segment_end.y)) - extent
	var maximum := Vector2(maxf(segment_start.x, segment_end.x), maxf(segment_start.y, segment_end.y)) + extent
	return query_aabb_candidates(minimum, maximum)


func query_aabb_candidates(aabb_min: Vector2, aabb_max: Vector2) -> Array[int]:
	var cell_range: Rect2i = clamped_cell_range(aabb_min, aabb_max)
	var result: Array[int] = []
	var seen: Dictionary[int, bool] = {}
	for row: int in range(cell_range.position.y, cell_range.end.y):
		for column: int in range(cell_range.position.x, cell_range.end.x):
			var key: int = column + row * COLUMN_COUNT
			for raw_entity_id: Variant in _cells[key]:
				var entity_id: int = int(raw_entity_id)
				if not seen.has(entity_id):
					seen[entity_id] = true
					result.append(entity_id)
	return result


func occupied_keys_for_aabb(aabb_min: Vector2, aabb_max: Vector2) -> Array[int]:
	var cell_range: Rect2i = clamped_cell_range(aabb_min, aabb_max)
	var result: Array[int] = []
	for row: int in range(cell_range.position.y, cell_range.end.y):
		for column: int in range(cell_range.position.x, cell_range.end.x):
			result.append(column + row * COLUMN_COUNT)
	return result
