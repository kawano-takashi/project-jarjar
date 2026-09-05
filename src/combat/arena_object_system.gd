class_name ArenaObjectSystem
extends RefCounted


const POWERUP_CAPACITY: int = 32
const POWERUP_KINDS: Array[ArenaPickup.Kind] = [
	ArenaPickup.Kind.HEAL,
	ArenaPickup.Kind.VACUUM,
	ArenaPickup.Kind.STOP,
]

var nodes: Array[ArenaNodeState] = []
var pickups: Array[ArenaPickup] = []
var destroyed_node_count: int = 0

var _state: RunState = null
var _catalog: DefinitionCatalog = null
var _manifest: SurvivalContentManifest = null
var _powerup_rng: RandomNumberGenerator = null
var _pending_respawn_ticks: Array[int] = []
var _next_pickup_id: int = 0
var _free_powerup_slots: Array[ArenaPickup] = []


func initialize(state: RunState, catalog: DefinitionCatalog) -> void:
	_state = state
	_catalog = catalog
	_manifest = catalog.manifest()
	_powerup_rng = state.rng_streams.powerup_rng
	nodes.clear()
	pickups.clear()
	_pending_respawn_ticks.clear()
	_free_powerup_slots.clear()
	_next_pickup_id = 0
	destroyed_node_count = 0
	for _slot_index: int in range(POWERUP_CAPACITY):
		var pickup_slot := ArenaPickup.new()
		pickup_slot.deactivate()
		_free_powerup_slots.append(pickup_slot)
	for site_index: int in range(_manifest.arena.node_site_positions.size()):
		var node := ArenaNodeState.new()
		node.site_index = site_index
		node.position = _manifest.arena.node_site_positions[site_index]
		if site_index in _manifest.arena.initial_active_sites:
			node.activate(site_index, node.position, _manifest.arena.node_max_hp)
		nodes.append(node)


func advance(current_tick: int) -> void:
	while not _pending_respawn_ticks.is_empty() and _pending_respawn_ticks[0] <= current_tick:
		_pending_respawn_ticks.pop_front()
		_respawn_one_node()


func damage_nodes_circle(
	center: Vector2,
	radius: float,
	damage: float,
	current_tick: int,
) -> int:
	if damage <= 0.0:
		return 0
	var destroyed: int = 0
	var combined_radius: float = maxf(0.0, radius) + _manifest.arena.node_body_radius
	var combined_radius_squared: float = combined_radius * combined_radius
	for node: ArenaNodeState in nodes:
		if not node.active:
			continue
		if node.position.distance_squared_to(center) > combined_radius_squared:
			continue
		node.hp = maxf(0.0, node.hp - damage)
		if node.hp > 0.0:
			continue
		_destroy_node(node, current_tick)
		destroyed += 1
	return destroyed


func damage_nodes_segment(
	segment_start: Vector2,
	segment_end: Vector2,
	projectile_radius: float,
	damage: float,
	current_tick: int,
	hit_site_indices: Dictionary[int, bool],
) -> int:
	if damage <= 0.0:
		return 0
	var destroyed: int = 0
	for node: ArenaNodeState in nodes:
		if not node.active or hit_site_indices.has(node.site_index):
			continue
		var intersection_t: float = CombatGeometry.segment_circle_first_t(
			segment_start,
			segment_end,
			node.position,
			maxf(0.0, projectile_radius) + _manifest.arena.node_body_radius,
		)
		if intersection_t < 0.0:
			continue
		hit_site_indices[node.site_index] = true
		node.hp = maxf(0.0, node.hp - damage)
		if node.hp <= 0.0:
			_destroy_node(node, current_tick)
			destroyed += 1
	return destroyed


func collect_at(player_position: Vector2) -> Array[ArenaPickup]:
	var collected: Array[ArenaPickup] = []
	var radius_squared: float = _manifest.arena.pickup_collect_radius * _manifest.arena.pickup_collect_radius
	var index: int = 0
	while index < pickups.size():
		var pickup: ArenaPickup = pickups[index]
		if pickup.position.distance_squared_to(player_position) > radius_squared:
			index += 1
			continue
		pickups.remove_at(index)
		if pickup.kind == ArenaPickup.Kind.CHEST:
			pickup.active = false
			collected.append(pickup)
			continue
		_append_collected_powerup_effects(collected, pickup)
		pickup.deactivate()
		_free_powerup_slots.append(pickup)
	return collected


func spawn_chest(position: Vector2, elite_serial: int) -> ArenaPickup:
	return _spawn_pickup(ArenaPickup.Kind.CHEST, position, elite_serial)


func chest_transforms() -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	for pickup: ArenaPickup in pickups:
		if pickup.active and pickup.kind == ArenaPickup.Kind.CHEST:
			result.append(pickup.transform())
	return result


func powerup_transforms() -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	for pickup: ArenaPickup in pickups:
		if pickup.active and pickup.kind != ArenaPickup.Kind.CHEST:
			result.append(pickup.transform())
	return result


func node_transforms() -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	for node: ArenaNodeState in nodes:
		if not node.active:
			continue
		result.append(Transform3D(
			Basis.IDENTITY,
			Vector3(node.position.x, 0.5, node.position.y),
		))
	return result


func active_node_count() -> int:
	var count: int = 0
	for node: ArenaNodeState in nodes:
		if node.active:
			count += 1
	return count


func active_powerup_count() -> int:
	return POWERUP_CAPACITY - _free_powerup_slots.size()


func total_powerup_effect_count() -> int:
	var total: int = 0
	for pickup: ArenaPickup in pickups:
		if pickup.active and pickup.kind != ArenaPickup.Kind.CHEST:
			total += pickup.total_effect_count()
	return total


func _destroy_node(node: ArenaNodeState, current_tick: int) -> void:
	var drop_position: Vector2 = node.position
	node.deactivate()
	destroyed_node_count += 1
	_pending_respawn_ticks.append(current_tick + _manifest.arena.node_respawn_ticks)
	_pending_respawn_ticks.sort()
	var drop_type: GameTypes.NodeDropType = NodeDropService.roll_drop(_state, _catalog)
	match drop_type:
		GameTypes.NodeDropType.HEAL:
			_spawn_pickup(ArenaPickup.Kind.HEAL, drop_position, node.site_index)
		GameTypes.NodeDropType.VACUUM:
			_spawn_pickup(ArenaPickup.Kind.VACUUM, drop_position, node.site_index)
		GameTypes.NodeDropType.STOP:
			_spawn_pickup(ArenaPickup.Kind.STOP, drop_position, node.site_index)


func _spawn_pickup(kind: ArenaPickup.Kind, position: Vector2, source_serial: int) -> ArenaPickup:
	var pickup_id: int = _next_pickup_id
	_next_pickup_id += 1
	if kind != ArenaPickup.Kind.CHEST and _free_powerup_slots.is_empty():
		var merge_target: ArenaPickup = _powerup_merge_target(kind, position)
		if merge_target != null:
			merge_target.add_effect(kind)
			return merge_target
		return null
	var pickup: ArenaPickup
	if kind == ArenaPickup.Kind.CHEST:
		pickup = ArenaPickup.new(pickup_id, kind, position, source_serial)
	else:
		pickup = _free_powerup_slots.pop_back()
		pickup.activate(pickup_id, kind, position, source_serial)
	pickups.append(pickup)
	return pickup


func _powerup_merge_target(
	kind: ArenaPickup.Kind,
	position: Vector2,
) -> ArenaPickup:
	var same_kind_target: ArenaPickup = null
	var same_kind_distance: float = INF
	var fallback_target: ArenaPickup = null
	var fallback_distance: float = INF
	for pickup: ArenaPickup in pickups:
		if not pickup.active or pickup.kind == ArenaPickup.Kind.CHEST:
			continue
		var distance_squared: float = pickup.position.distance_squared_to(position)
		if (
			distance_squared < fallback_distance
			or (
				is_equal_approx(distance_squared, fallback_distance)
				and fallback_target != null
				and pickup.pickup_id < fallback_target.pickup_id
			)
		):
			fallback_target = pickup
			fallback_distance = distance_squared
		if pickup.effect_count(kind) <= 0:
			continue
		if (
			distance_squared < same_kind_distance
			or (
				is_equal_approx(distance_squared, same_kind_distance)
				and same_kind_target != null
				and pickup.pickup_id < same_kind_target.pickup_id
			)
		):
			same_kind_target = pickup
			same_kind_distance = distance_squared
	return same_kind_target if same_kind_target != null else fallback_target


func _append_collected_powerup_effects(
	collected: Array[ArenaPickup],
	pickup: ArenaPickup,
) -> void:
	for effect_kind: ArenaPickup.Kind in POWERUP_KINDS:
		var count: int = pickup.effect_count(effect_kind)
		if count <= 0:
			continue
		# Multiple heals retain their complete numeric value. Vacuum and stop are
		# idempotent when collected on the same tick, so one returned effect is
		# gameplay-equivalent to every stacked copy.
		if effect_kind == ArenaPickup.Kind.HEAL and count > 1:
			_state.current_hp = minf(
				_state.max_hp,
				_state.current_hp + _manifest.arena.node_heal_amount * float(count - 1),
			)
		var collected_effect := ArenaPickup.new(
			pickup.pickup_id,
			effect_kind,
			pickup.position,
			pickup.source_serial,
		)
		collected_effect.active = false
		collected.append(collected_effect)


func _respawn_one_node() -> void:
	if active_node_count() >= _manifest.arena.initial_active_sites.size():
		return
	var inactive_sites: Array[int] = []
	for node: ArenaNodeState in nodes:
		if not node.active:
			inactive_sites.append(node.site_index)
	if inactive_sites.is_empty():
		return
	var selected_index: int = 0
	if _powerup_rng != null:
		selected_index = _powerup_rng.randi_range(0, inactive_sites.size() - 1)
	var site_index: int = inactive_sites[selected_index]
	nodes[site_index].activate(site_index, _manifest.arena.node_site_positions[site_index], _manifest.arena.node_max_hp)
