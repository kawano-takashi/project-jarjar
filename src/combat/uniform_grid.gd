class_name UniformGrid
extends RefCounted


const CELL_SIZE: float = 2.0

var arena_min: Vector2
var arena_max: Vector2
var column_count: int = 0
var row_count: int = 0
var cell_count: int = 0

var _cells: Array[Array] = []
var _occupied_keys: Array[int] = []
var _unique_enemy_ids: bool = false
## Negative means an insertion omitted its radius; callers then use catalog bounds.
var maximum_body_radius: float = 0.0


func configure(arena_size: Vector2) -> void:
	arena_min = -arena_size * 0.5
	arena_max = arena_size * 0.5
	column_count = ceili(arena_size.x / CELL_SIZE)
	row_count = ceili(arena_size.y / CELL_SIZE)
	cell_count = column_count * row_count
	_cells.clear()
	_occupied_keys.clear()
	maximum_body_radius = 0.0
	_unique_enemy_ids = false
	_cells.resize(cell_count)
	for key: int in range(cell_count):
		_cells[key] = []


func clear() -> void:
	for key: int in _occupied_keys:
		_cells[key].clear()
	_occupied_keys.clear()
	maximum_body_radius = 0.0
	_unique_enemy_ids = false


func rebuild_enemies(store: EnemyStore, current_tick: int) -> void:
	clear()
	# EnemyStore owns unique IDs and inserts each live entity into one cell.
	_unique_enemy_ids = true
	for enemy: EnemyEntity in store.entities:
		if not enemy.is_targetable(current_tick):
			continue
		maximum_body_radius = maxf(maximum_body_radius, enemy.body_radius())
		var position: Vector2 = enemy.position
		var column: int = clampi(floori((position.x - arena_min.x) / CELL_SIZE), 0, column_count - 1)
		var row: int = clampi(floori((position.y - arena_min.y) / CELL_SIZE), 0, row_count - 1)
		var key: int = column + row * column_count
		var cell: Array = _cells[key]
		if cell.is_empty():
			_occupied_keys.append(key)
		cell.append(enemy.entity_id)
	for key: int in _occupied_keys:
		_cells[key].sort()


func insert(entity_id: int, position: Vector2) -> void:
	maximum_body_radius = -1.0
	_unique_enemy_ids = false
	var key: int = cell_key_for_position(position)
	var cell: Array = _cells[key]
	if cell.is_empty():
		_occupied_keys.append(key)
	# Keep IDs ascending, with the same placement after any duplicate IDs.
	cell.insert(cell.bsearch(entity_id, false), entity_id)


func cell_key_for_position(position: Vector2) -> int:
	var indices: Vector2i = cell_indices_for_position(position)
	return indices.x + indices.y * column_count


func cell_indices_for_position(position: Vector2) -> Vector2i:
	var column: int = clampi(int(floor((position.x - arena_min.x) / CELL_SIZE)), 0, column_count - 1)
	var row: int = clampi(int(floor((position.y - arena_min.y) / CELL_SIZE)), 0, row_count - 1)
	return Vector2i(column, row)


func clamped_cell_range(aabb_min: Vector2, aabb_max: Vector2) -> Rect2i:
	var normalized_min := Vector2(minf(aabb_min.x, aabb_max.x), minf(aabb_min.y, aabb_max.y))
	var normalized_max := Vector2(maxf(aabb_min.x, aabb_max.x), maxf(aabb_min.y, aabb_max.y))
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
	var lower: Vector2 = aabb_min.min(aabb_max)
	var upper: Vector2 = aabb_min.max(aabb_max)
	var first_column: int = clampi(floori((lower.x - arena_min.x) / CELL_SIZE), 0, column_count - 1)
	var last_column: int = clampi(floori((upper.x - arena_min.x) / CELL_SIZE), 0, column_count - 1)
	var first_row: int = clampi(floori((lower.y - arena_min.y) / CELL_SIZE), 0, row_count - 1)
	var last_row: int = clampi(floori((upper.y - arena_min.y) / CELL_SIZE), 0, row_count - 1)
	var result: Array[int] = []
	if _unique_enemy_ids:
		for row: int in range(first_row, last_row + 1):
			var row_offset: int = row * column_count
			for column: int in range(first_column, last_column + 1):
				result.append_array(_cells[column + row_offset])
		return result
	var seen: Dictionary[int, bool] = {}
	for row: int in range(first_row, last_row + 1):
		var row_offset: int = row * column_count
		for column: int in range(first_column, last_column + 1):
			var key: int = column + row_offset
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
			result.append(column + row * column_count)
	return result
