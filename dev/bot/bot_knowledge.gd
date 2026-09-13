extends RefCounted

## Public game rules copied from the validated catalog, without run state.
var move_speed: float
var player_radius: float
var pickup_radius: float
var object_collect_radius: float
var enemy_contact_damage: Dictionary[int, float] = {}
var _segment_damage: Array[Vector2] = []
var _normal_damage_scale: float
var _boss_damage_scale: float
var weapon_slots: int
var passive_slots: int
var max_evolutions: int
var starter_weapon_id: StringName
var weapon_lineages: Dictionary[StringName, StringName] = {}
var weapons: Dictionary[StringName, Dictionary] = {}
var passives: Dictionary[StringName, Dictionary] = {}
var evolutions: Dictionary[StringName, Dictionary] = {}
var enemy_speeds: Dictionary[int, float] = {}
var swarm_speed: float
var swarm_radius: float
var spawn_band_width: float
var swarm_depth: float
var minimum_cooldown_multiplier: float
var minimum_area_multiplier: float
var melee_arc_degrees: float


func _init(catalog: DefinitionCatalog) -> void:
	var content: SurvivalContentManifest = catalog.manifest()
	move_speed = content.player.move_speed
	player_radius = content.player.body_radius
	pickup_radius = content.progression.xp_pickup_attract_radius
	object_collect_radius = content.arena.pickup_collect_radius
	_normal_damage_scale = content.combat.normal_enemy_damage_scale
	_boss_damage_scale = content.combat.boss_damage_multiplier
	var end_tick: int = 0
	for segment: EnemySegmentDefinition in content.segments:
		end_tick += segment.duration_ticks
		_segment_damage.append(Vector2(end_tick, segment.damage_multiplier))
	weapon_slots = content.progression.weapon_slot_count
	passive_slots = content.progression.passive_slot_count
	max_evolutions = content.progression.max_evolutions_per_run
	starter_weapon_id = content.progression.starter_weapon_id
	swarm_speed = content.swarm_event.unit_definition.move_speed
	swarm_radius = content.swarm_event.unit_definition.body_radius
	spawn_band_width = content.spawn.offscreen_band_width
	swarm_depth = float(content.swarm_event.depth_count - 1) * content.swarm_event.depth_pitch
	minimum_cooldown_multiplier = content.combat.min_cooldown_multiplier
	minimum_area_multiplier = content.combat.min_area_multiplier
	melee_arc_degrees = content.combat.melee_arc_degrees
	for definition: WeaponDefinition in content.weapons:
		weapon_lineages[definition.weapon_id] = catalog.lineage_for_weapon(definition.weapon_id)
		weapons[definition.weapon_id] = {
			"behavior": definition.behavior, "max_level": definition.max_level,
			"selectable": definition.selection_weight > 0.0,
			"damage": definition.damage_by_level.duplicate(),
			"cooldown": definition.cooldown_ticks_by_level.duplicate(),
			"shot_interval": definition.shot_interval_ticks_by_level.duplicate(),
			"amount": definition.amount_by_level.duplicate(),
			"range": definition.range_by_level.duplicate(),
			"effect_radius": definition.effect_radius_by_level.duplicate(),
			"range_scales_with_area": definition.range_scales_with_area,
			"effect_radius_scales_with_area": definition.effect_radius_scales_with_area,
			"life_steal": definition.life_steal_ratio,
		}
	for definition: PassiveDefinition in content.passives:
		passives[definition.passive_id] = {
			"stat": definition.stat_id, "amount": definition.amount_per_level,
			"max_level": definition.max_level,
			"selectable": definition.selection_weight > 0.0,
		}
	for definition: EvolutionDefinition in content.evolutions:
		evolutions[definition.base_weapon_id] = {
			"passive": definition.passive_id, "weapon": definition.evolved_weapon_id,
		}
	for definition: EnemyDefinition in content.enemies:
		enemy_speeds[int(definition.enemy_type)] = definition.move_speed
		enemy_contact_damage[int(definition.enemy_type)] = definition.contact_damage
	enemy_speeds[CombatSnapshot.EnemyVisualKind.SWARMER_EVENT_RED] = swarm_speed
	enemy_contact_damage[CombatSnapshot.EnemyVisualKind.SWARMER_EVENT_RED] = content.swarm_event.unit_definition.contact_damage
	enemy_speeds[CombatSnapshot.EnemyVisualKind.ENCIRCLER] = content.encounters.unit_definition.move_speed
	enemy_contact_damage[CombatSnapshot.EnemyVisualKind.ENCIRCLER] = content.encounters.unit_definition.contact_damage


func contact_damage_for_tick(tick: int) -> Dictionary[int, float]:
	var multiplier: float = _segment_damage.back().y
	for segment: Vector2 in _segment_damage:
		if tick < int(segment.x):
			multiplier = segment.y
			break
	var result: Dictionary[int, float] = {}
	for kind: int in enemy_contact_damage:
		var scale: float = multiplier
		if kind == CombatSnapshot.EnemyVisualKind.BOSS:
			scale = _boss_damage_scale
		elif kind not in [CombatSnapshot.EnemyVisualKind.ELITE, CombatSnapshot.EnemyVisualKind.SWARMER_EVENT_RED]:
			scale *= _normal_damage_scale
		result[kind] = enemy_contact_damage[kind] * scale
	return result
