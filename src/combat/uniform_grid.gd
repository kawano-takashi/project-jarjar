class_name UniformGrid
extends RefCounted


const CELL_SIZE: float = 2.0

var _cells: Dictionary[Vector2i, Array] = {}
var _unique_enemy_ids: bool = false
## Negative means an insertion omitted its radius; callers then use catalog bounds.
var maximum_body_radius: float = 0.0


func clear() -> void:
	_cells.clear()
	maximum_body_radius = 0.0
	_unique_enemy_ids = false


func rebuild_enemies(store: EnemyStore, current_tick: int) -> void:
	clear()
	_unique_enemy_ids = true
	for enemy: EnemyEntity in store.entities:
		if not enemy.is_targetable(current_tick):
			continue
		maximum_body_radius = maxf(maximum_body_radius, enemy.body_radius())
		var key: Vector2i = cell_indices_for_position(enemy.position)
		if not _cells.has(key):
			_cells[key] = []
		_cells[key].append(enemy.entity_id)
	for cell: Array in _cells.values():
		cell.sort()


func insert(entity_id: int, position: Vector2) -> void:
	maximum_body_radius = -1.0
	_unique_enemy_ids = false
	var key: Vector2i = cell_indices_for_position(position)
	if not _cells.has(key):
		_cells[key] = []
	var cell: Array = _cells[key]
	cell.insert(cell.bsearch(entity_id, false), entity_id)


func cell_indices_for_position(position: Vector2) -> Vector2i:
	return Vector2i(floori(position.x / CELL_SIZE), floori(position.y / CELL_SIZE))


func query_circle_candidates(center: Vector2, radius: float, padding: float) -> Array[int]:
	var extent: Vector2 = Vector2.ONE * (maxf(0.0, radius) + maxf(0.0, padding))
	return query_aabb_candidates(center - extent, center + extent)


func query_segment_candidates(segment_start: Vector2, segment_end: Vector2, padding: float) -> Array[int]:
	var extent: Vector2 = Vector2.ONE * maxf(0.0, padding)
	return query_aabb_candidates(segment_start.min(segment_end) - extent, segment_start.max(segment_end) + extent)


func query_aabb_candidates(aabb_min: Vector2, aabb_max: Vector2) -> Array[int]:
	var lower: Vector2i = cell_indices_for_position(aabb_min.min(aabb_max))
	var upper: Vector2i = cell_indices_for_position(aabb_min.max(aabb_max))
	var result: Array[int] = []
	var seen: Dictionary[int, bool] = {}
	for row: int in range(lower.y, upper.y + 1):
		for column: int in range(lower.x, upper.x + 1):
			var cell: Array = _cells.get(Vector2i(column, row), [])
			for raw_id: Variant in cell:
				var entity_id: int = int(raw_id)
				if _unique_enemy_ids or not seen.has(entity_id):
					result.append(entity_id)
					if not _unique_enemy_ids:
						seen[entity_id] = true
	return result
