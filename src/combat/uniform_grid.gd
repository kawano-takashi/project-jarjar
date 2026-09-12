class_name UniformGrid
extends RefCounted


const CELL_SIZE: float = 2.0

var _kernel: RefCounted = null
## Negative means an insertion omitted its radius; callers then use catalog bounds.
var maximum_body_radius: float = 0.0


func clear() -> void:
	_native().clear_index(CELL_SIZE)
	maximum_body_radius = 0.0


func rebuild_enemies(store: EnemyStore, current_tick: int) -> void:
	var ids := PackedInt64Array()
	var positions := PackedVector2Array()
	maximum_body_radius = 0.0
	for enemy: EnemyEntity in store.entities:
		if not enemy.is_targetable(current_tick):
			continue
		maximum_body_radius = maxf(maximum_body_radius, enemy.body_radius())
		ids.append(enemy.entity_id)
		positions.append(enemy.position)
	_native().rebuild_index(ids, positions, CELL_SIZE)


func insert(entity_id: int, position: Vector2) -> void:
	maximum_body_radius = -1.0
	_native().insert_id(entity_id, position)


func cell_indices_for_position(position: Vector2) -> Vector2i:
	return Vector2i(floori(position.x / CELL_SIZE), floori(position.y / CELL_SIZE))


func query_circle_candidates(center: Vector2, radius: float, padding: float) -> Array[int]:
	var extent: Vector2 = Vector2.ONE * (maxf(0.0, radius) + maxf(0.0, padding))
	return query_aabb_candidates(center - extent, center + extent)


func query_segment_candidates(segment_start: Vector2, segment_end: Vector2, padding: float) -> Array[int]:
	var extent: Vector2 = Vector2.ONE * maxf(0.0, padding)
	return query_aabb_candidates(segment_start.min(segment_end) - extent, segment_start.max(segment_end) + extent)


func query_aabb_candidates(aabb_min: Vector2, aabb_max: Vector2) -> Array[int]:
	return _native().query_aabb(aabb_min, aabb_max)


## Numerical positions/radii for one projectile stage; HP remains in EnemyStore.
## Arrays have equal lengths, radii are metres, IDs retain their full 64 bits.
func set_damage_geometry(ids: PackedInt64Array, positions: PackedVector2Array, radii: PackedFloat64Array) -> void:
	_native().set_damage_bodies(ids, positions, radii)


## Returns [PackedInt32 offsets, PackedInt64 enemy IDs, PackedFloat64 first t].
## Offsets delimit each input segment; t is in [0, 1], in grid traversal order.
func intersect_segments(starts: PackedVector2Array, ends: PackedVector2Array, radii: PackedFloat64Array, padding: float) -> Array:
	return _native().intersect_segments(starts, ends, radii, padding, CombatGeometry.EPSILON)


func _native() -> RefCounted:
	if _kernel == null:
		_kernel = CombatNative.create_kernel()
		if _kernel != null:
			_kernel.clear_index(CELL_SIZE)
	return _kernel
