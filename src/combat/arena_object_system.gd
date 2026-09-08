class_name ArenaObjectSystem
extends RefCounted


var nodes: Array[ArenaNodeState] = []
var pickups: Array[ArenaPickup] = []
var destroyed_node_count: int = 0

var _state: RunState = null
var _catalog: DefinitionCatalog = null
var _manifest: SurvivalContentManifest = null
var _view: ArenaView = null
var _spawn_rng: RandomNumberGenerator = null
var _next_node_id: int = 0
var _next_pickup_id: int = 0
var _last_spawn_tick: int = 0


func initialize(state: RunState, catalog: DefinitionCatalog, view: ArenaView = null) -> void:
	_state = state
	_catalog = catalog
	_manifest = catalog.manifest()
	_view = view if view != null else ArenaView.new()
	_spawn_rng = state.rng_streams.node_spawn_rng
	nodes.clear()
	pickups.clear()
	_next_node_id = 0
	_next_pickup_id = 0
	_last_spawn_tick = state.combat_tick
	destroyed_node_count = 0
	for _index: int in range(_manifest.arena.node_initial_count):
		_spawn_node()


func advance(current_tick: int, player_position: Vector2 = Vector2.ZERO) -> void:
	if _state.phase != GameTypes.RunPhase.COMBAT:
		return
	if current_tick - _last_spawn_tick < _manifest.arena.node_spawn_interval_ticks:
		return
	_last_spawn_tick = current_tick
	var full: bool = active_node_count() >= _manifest.arena.node_capacity
	var chance: float = _manifest.arena.node_spawn_chance
	if not full:
		var luck: float = 1.0 + ProgressionService.passive_stat_total(_state, _catalog, &"luck_pct") / 100.0
		chance = minf(chance * luck, _manifest.arena.node_spawn_chance_max)
	if _spawn_rng.randf() >= chance:
		return
	if full:
		var farthest: ArenaNodeState = null
		var distance: float = -1.0
		for node: ArenaNodeState in nodes:
			if not node.active or _view.is_body_visible(node.position, _manifest.arena.node_body_radius):
				continue
			var candidate_distance: float = node.position.distance_squared_to(player_position)
			if candidate_distance > distance:
				farthest = node
				distance = candidate_distance
		if farthest == null:
			return
		farthest.deactivate()
	_spawn_node()


func _spawn_node() -> void:
	var slot: ArenaNodeState = null
	for node: ArenaNodeState in nodes:
		if not node.active:
			slot = node
			break
	if slot == null:
		slot = ArenaNodeState.new()
		nodes.append(slot)
	var position: Vector2 = _view.sample_offscreen_position(
		_spawn_rng, _manifest.spawn.offscreen_band_width, _manifest.arena.node_body_radius,
	)
	slot.activate(_next_node_id, position, _manifest.arena.node_max_hp)
	_next_node_id += 1


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
	hit_node_ids: Dictionary[int, bool],
) -> int:
	if damage <= 0.0:
		return 0
	var destroyed: int = 0
	for node: ArenaNodeState in nodes:
		if not node.active or hit_node_ids.has(node.node_id):
			continue
		var intersection_t: float = CombatGeometry.segment_circle_first_t(
			segment_start,
			segment_end,
			node.position,
			maxf(0.0, projectile_radius) + _manifest.arena.node_body_radius,
		)
		if intersection_t < 0.0:
			continue
		hit_node_ids[node.node_id] = true
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
		pickup.active = false
		collected.append(pickup)
	return collected


func spawn_chest(position: Vector2, elite_serial: int) -> ArenaPickup:
	if elite_serial < 0 or elite_serial >= _catalog.elite_chest_kinds.size():
		return null
	var pickup: ArenaPickup = _spawn_pickup(ArenaPickup.Kind.CHEST, position, elite_serial)
	pickup.chest_kind = _catalog.elite_chest_kinds[elite_serial]
	return pickup


func chest_transforms(chest_kind: int = -1) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	for pickup: ArenaPickup in pickups:
		if pickup.active and pickup.kind == ArenaPickup.Kind.CHEST and (chest_kind < 0 or int(pickup.chest_kind) == chest_kind):
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
	var count: int = 0
	for pickup: ArenaPickup in pickups:
		if pickup.active and pickup.kind != ArenaPickup.Kind.CHEST:
			count += 1
	return count


func _destroy_node(node: ArenaNodeState, _current_tick: int) -> void:
	var drop_position: Vector2 = node.position
	node.deactivate()
	destroyed_node_count += 1
	var drop_type: GameTypes.NodeDropType = NodeDropService.roll_drop(_state, _catalog)
	match drop_type:
		GameTypes.NodeDropType.HEAL:
			_spawn_pickup(ArenaPickup.Kind.HEAL, drop_position, node.node_id)
		GameTypes.NodeDropType.VACUUM:
			_spawn_pickup(ArenaPickup.Kind.VACUUM, drop_position, node.node_id)
		GameTypes.NodeDropType.STOP:
			_spawn_pickup(ArenaPickup.Kind.STOP, drop_position, node.node_id)


func _spawn_pickup(kind: ArenaPickup.Kind, position: Vector2, source_serial: int) -> ArenaPickup:
	var pickup := ArenaPickup.new(_next_pickup_id, kind, position, source_serial)
	_next_pickup_id += 1
	pickups.append(pickup)
	return pickup


func shift_origin(displacement: Vector2) -> void:
	for node: ArenaNodeState in nodes:
		node.position -= displacement
	for pickup: ArenaPickup in pickups:
		pickup.position -= displacement


func chest_guidance(player_position: Vector2) -> Array[Dictionary]:
	var nearest: Dictionary[int, ArenaPickup] = {}
	for pickup: ArenaPickup in pickups:
		if not pickup.active or pickup.kind != ArenaPickup.Kind.CHEST or _view.is_bounds_visible(pickup.chest_visual_bounds()):
			continue
		var kind: int = int(pickup.chest_kind)
		if not nearest.has(kind) or pickup.position.distance_squared_to(player_position) < nearest[kind].position.distance_squared_to(player_position):
			nearest[kind] = pickup
	var result: Array[Dictionary] = []
	for kind: int in [GameTypes.ChestKind.NORMAL, GameTypes.ChestKind.EVOLUTION_CAPABLE]:
		if nearest.has(kind):
			var cue: Dictionary = _view.edge_guidance(nearest[kind].position)
			cue["kind"] = kind
			result.append(cue)
	return result
