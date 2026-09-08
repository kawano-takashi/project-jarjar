class_name DefinitionCatalog
extends RefCounted


const MANIFEST_PATH: String = "res://data/balance/survival_content_manifest.tres"
const FLOAT_TOLERANCE: float = 0.0001
const PASSIVE_STATS: Array[StringName] = [
	&"might_pct", &"cooldown_pct", &"projectile_speed_pct", &"area_pct",
	&"duration_pct", &"max_hp_pct", &"recovery_per_second", &"luck_pct",
]

var weapons: Dictionary[StringName, WeaponDefinition] = {}
var _lineage_by_weapon_id: Dictionary[StringName, StringName] = {}
var passives: Dictionary[StringName, PassiveDefinition] = {}
var enemies: Dictionary[StringName, EnemyDefinition] = {}
var segments: Dictionary[int, EnemySegmentDefinition] = {}
var evolutions: Dictionary[StringName, EvolutionDefinition] = {}
var is_valid: bool = false
var error_text: String = ""
var validation_errors: PackedStringArray = []
var boss_start_tick: int = 0
var segment_start_ticks: PackedInt32Array = []
var segment_end_ticks: PackedInt32Array = []
var elite_spawn_ticks: PackedInt32Array = []
var elite_chest_kinds: Array[GameTypes.ChestKind] = []
var swarm_attempts: Array[Dictionary] = []
var envelope: CombatEnvelope = null
var maximum_enemy_body_radius: float = 0.0

var _manifest: SurvivalContentManifest = null
var _enemies_by_type: Dictionary[int, EnemyDefinition] = {}
var _evolved_weapon_ids: Dictionary[StringName, bool] = {}


func load_and_validate(path: String = MANIFEST_PATH) -> bool:
	var loaded: Resource = ResourceLoader.load(path)
	if not loaded is SurvivalContentManifest:
		_reset()
		validation_errors.append("%s: resource=%s; SurvivalContentManifest is required" % [path, loaded])
		return _finish_validation()
	return validate_manifest(loaded as SurvivalContentManifest)


func validate_manifest(content: SurvivalContentManifest) -> bool:
	_reset()
	_manifest = content
	if content == null:
		validation_errors.append("<manifest>: resource=null; SurvivalContentManifest is required")
		return _finish_validation()
	for key: String in ["player", "progression", "arena", "combat", "spawn", "swarm_event", "encounters"]:
		_require(content, key, content.get(key) != null, "required Resource reference")
	if not validation_errors.is_empty():
		return _finish_validation()
	_index_content()
	_validate_settings()
	_validate_passives()
	_validate_weapons()
	_validate_evolutions()
	for definition: EnemyDefinition in enemies.values():
		_validate_enemy(definition)
	for enemy_type: int in GameTypes.EnemyType.values():
		_require(content, "enemies", _enemies_by_type.has(enemy_type), "one definition for enemy type %d" % enemy_type)
	_validate_swarm()
	_validate_encounters()
	_validate_segments()
	if validation_errors.is_empty():
		envelope = CombatEnvelope.new(content)
	return _finish_validation()


func manifest() -> SurvivalContentManifest:
	return _manifest


func weapon(id: StringName) -> WeaponDefinition:
	return weapons.get(id) as WeaponDefinition


func passive(id: StringName) -> PassiveDefinition:
	return passives.get(id) as PassiveDefinition


func enemy(id: StringName) -> EnemyDefinition:
	return enemies.get(id) as EnemyDefinition


func enemy_for_type(enemy_type: GameTypes.EnemyType) -> EnemyDefinition:
	return _enemies_by_type.get(int(enemy_type)) as EnemyDefinition


func segment(index: int) -> EnemySegmentDefinition:
	return segments.get(index) as EnemySegmentDefinition


func segment_index_for_tick(tick: int) -> int:
	if tick < 0 or tick >= boss_start_tick:
		return -1
	for index: int in range(segment_end_ticks.size()):
		if tick < segment_end_ticks[index]:
			return index
	return -1


func segment_for_tick(tick: int) -> EnemySegmentDefinition:
	if segments.is_empty():
		return null
	var index: int = segment_index_for_tick(tick)
	return segment(segments.size() - 1 if index < 0 else index)


func evolution_for_weapon(id: StringName) -> EvolutionDefinition:
	return evolutions.get(id) as EvolutionDefinition


func lineage_for_weapon(id: StringName) -> StringName:
	return _lineage_by_weapon_id.get(id, &"")


func is_evolved_weapon(id: StringName) -> bool:
	return _evolved_weapon_ids.has(id)


func basic_weapon_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for definition: WeaponDefinition in weapons.values():
		if not definition.is_evolved:
			ids.append(definition.weapon_id)
	return WeightedSelector.sort_ordinal(ids)


func evolved_weapon_ids() -> Array[StringName]:
	return WeightedSelector.sort_ordinal(_evolved_weapon_ids.keys())


func passive_ids() -> Array[StringName]:
	return WeightedSelector.sort_ordinal(passives.keys())


func _reset() -> void:
	weapons.clear()
	_lineage_by_weapon_id.clear()
	passives.clear()
	enemies.clear()
	segments.clear()
	evolutions.clear()
	_enemies_by_type.clear()
	_evolved_weapon_ids.clear()
	validation_errors.clear()
	segment_start_ticks.clear()
	segment_end_ticks.clear()
	elite_spawn_ticks.clear()
	elite_chest_kinds.clear()
	swarm_attempts.clear()
	boss_start_tick = 0
	maximum_enemy_body_radius = 0.0
	envelope = null
	_manifest = null
	is_valid = false
	error_text = ""


func _index_content() -> void:
	for definition: WeaponDefinition in _manifest.weapons:
		if _index_entry(definition, "weapon_id", weapons):
			_lineage_by_weapon_id[definition.weapon_id] = definition.weapon_id
			if definition.is_evolved:
				_evolved_weapon_ids[definition.weapon_id] = true
	for definition: PassiveDefinition in _manifest.passives:
		_index_entry(definition, "passive_id", passives)
	for definition: EnemyDefinition in _manifest.enemies:
		if _index_entry(definition, "enemy_id", enemies):
			_require(definition, "enemy_type", not _enemies_by_type.has(int(definition.enemy_type)), "unique enemy type")
			_enemies_by_type[int(definition.enemy_type)] = definition
	for definition: EvolutionDefinition in _manifest.evolutions:
		if _index_entry(definition, "base_weapon_id", evolutions):
			_lineage_by_weapon_id[definition.evolved_weapon_id] = definition.base_weapon_id
	for index: int in range(_manifest.segments.size()):
		var definition: EnemySegmentDefinition = _manifest.segments[index]
		if definition == null:
			_error(_manifest, "segments[%d]" % index, null, "required Resource")
		else:
			segments[index] = definition


func _index_entry(definition: Resource, key: String, entries: Dictionary) -> bool:
	if definition == null:
		_error(_manifest, key, null, "required definition Resource")
		return false
	var id: StringName = definition.get(key)
	if id == &"" or entries.has(id):
		_error(definition, key, id, "nonempty unique ID")
		return false
	entries[id] = definition
	return true


func _validate_settings() -> void:
	for settings: Resource in [_manifest.player, _manifest.progression, _manifest.arena, _manifest.combat, _manifest.spawn]:
		_validate_numbers(settings, ["xp_early_offset", "xp_middle_offset", "xp_late_offset", "xp_early_coefficient", "xp_middle_coefficient", "xp_late_coefficient"])
	var player: PlayerBalanceDefinition = _manifest.player
	for key: String in ["base_max_hp", "body_radius", "kill_chain_window_ticks"]:
		_positive(player, key)
	var progression: ProgressionBalanceDefinition = _manifest.progression
	for key: String in ["weapon_slot_count", "level_offer_count", "xp_pool_capacity", "xp_early_max_level", "xp_first_transition_requirement", "xp_second_transition_requirement"]:
		_positive(progression, key)
	_require(progression, "xp_middle_max_level", progression.xp_middle_max_level > progression.xp_early_max_level + 1, "greater than early boundary + 1")
	_require(progression, "xp_growth_compensation_multiplier", is_finite(progression.xp_growth_compensation_multiplier) and progression.xp_growth_compensation_multiplier >= 1.0 and progression.xp_growth_compensation_multiplier == floorf(progression.xp_growth_compensation_multiplier), "finite whole integer >= 1")
	_unique_positive_integers(progression, "xp_growth_compensation_levels")
	_require(progression, "xp_pickup_collect_radius", progression.xp_pickup_collect_radius <= progression.xp_pickup_attract_radius, "<= xp_pickup_attract_radius")
	var starter: WeaponDefinition = weapon(progression.starter_weapon_id)
	_require(progression, "starter_weapon_id", starter != null and not starter.is_evolved, "existing basic weapon")
	# Piecewise linear XP only needs endpoints and both transition levels checked.
	var reachable_level: int = 1
	for definition: WeaponDefinition in weapons.values():
		if not definition.is_evolved:
			reachable_level += definition.max_level
	for definition: PassiveDefinition in passives.values():
		reachable_level += maxi(0, definition.max_level)
	for level: int in [1, progression.xp_early_max_level, progression.xp_early_max_level + 1, progression.xp_early_max_level + 2, progression.xp_middle_max_level, progression.xp_middle_max_level + 1, progression.xp_middle_max_level + 2, reachable_level]:
		if level > 0 and level <= reachable_level:
			var xp: int = ProgressionService.xp_required_for_level(level, progression)
			if xp <= 0:
				_error(progression, "required_xp(level=%d)" % level, xp, "positive XP at every reachable level")
	var arena: ArenaBalanceDefinition = _manifest.arena
	for key: String in ["node_max_hp", "node_body_radius", "node_capacity", "node_spawn_interval_ticks"]:
		_positive(arena, key)
	_require(arena, "node_initial_count", arena.node_initial_count <= arena.node_capacity, "<= node_capacity")
	_require(arena, "node_spawn_chance_max", arena.node_spawn_chance <= arena.node_spawn_chance_max and arena.node_spawn_chance_max <= 1.0, "node_spawn_chance <= maximum <= 1")
	_validate_weights(arena, "node_drop_weights", GameTypes.NodeDropType.size())
	var combat: CombatBalanceDefinition = _manifest.combat
	for key: String in ["boss_hp_multiplier", "boss_action_rate_multiplier", "boss_enrage_interval_ticks", "min_cooldown_multiplier", "min_duration_multiplier", "min_projectile_speed_multiplier", "min_area_multiplier", "target_center_radius", "effect_outer_radius", "damage_center_radius", "boss_phase_interval_multiplier", "boss_min_interval_multiplier", "orbital_damage_interval_ticks", "homing_burst_interval_ticks"]:
		_positive(combat, key)
	_require(combat, "target_center_radius", combat.target_center_radius <= combat.effect_outer_radius, "<= effect_outer_radius")
	_require(combat, "effect_outer_radius", combat.effect_outer_radius <= combat.damage_center_radius, "<= damage_center_radius")
	_require(combat, "melee_arc_degrees", combat.melee_arc_degrees > 0.0 and combat.melee_arc_degrees <= 360.0, "(0, 360] degrees")
	_require(combat, "returning_ring_spread_degrees", combat.returning_ring_spread_degrees <= 360.0, "[0, 360] degrees")
	_require(combat, "boss_phase_two_hp_ratio", combat.boss_phase_two_hp_ratio <= 1.0 and combat.boss_phase_two_hp_ratio > combat.boss_phase_three_hp_ratio, "phase_three_hp_ratio < ratio <= 1")
	_require(combat, "boss_stop_time_scale", combat.boss_stop_time_scale <= 1.0, "time multiplier in [0, 1]")
	var spawn: SpawnBalanceDefinition = _manifest.spawn
	_positive(spawn, "target_ramp_ticks")
	_positive(spawn, "offscreen_band_width")
	_positive(spawn, "despawn_margin")


func _validate_passives() -> void:
	var total: float = 0.0
	for definition: PassiveDefinition in passives.values():
		_validate_numbers(definition, ["amount_per_level"])
		_positive(definition, "max_level")
		_require(definition, "display_name", not definition.display_name.is_empty(), "nonempty name")
		_require(definition, "stat_id", definition.stat_id in PASSIVE_STATS, "supported passive stat")
		_require(definition, "amount_per_level", is_finite(definition.amount_per_level) and definition.amount_per_level != 0.0, "finite nonzero signed modifier")
		total += definition.selection_weight
	if _manifest.progression.passive_slot_count > 0 and not passives.is_empty():
		_require(_manifest, "passives", is_finite(total) and total > 0.0, "finite positive total selection weight")
	for stat: StringName in [&"max_hp_pct", &"luck_pct"]:
		var penalties: Array[float] = []
		for definition: PassiveDefinition in passives.values():
			if definition.stat_id == stat and definition.amount_per_level < 0.0:
				penalties.append(definition.amount_per_level * float(maxi(0, definition.max_level)))
		penalties.sort()
		var minimum: float = 0.0
		for index: int in range(mini(maxi(0, _manifest.progression.passive_slot_count), penalties.size())):
			minimum += penalties[index]
		if not is_finite(minimum) or minimum <= -100.0:
			_error(_manifest, "passives.%s.minimum_total" % stat, minimum, "> -100%; combined HP and luck multipliers must stay positive")


func _validate_weapons() -> void:
	var total: float = 0.0
	var max_area: float = _maximum_area_multiplier()
	for definition: WeaponDefinition in weapons.values():
		_validate_numbers(definition)
		_require(definition, "display_name", not definition.display_name.is_empty(), "nonempty name")
		_require(definition, "behavior", int(definition.behavior) in GameTypes.WeaponBehavior.values(), "supported weapon behavior")
		_positive(definition, "max_level")
		var arrays_valid: bool = true
		for key: String in ["damage_by_level", "cooldown_ticks_by_level", "amount_by_level", "projectile_speed_by_level", "range_by_level", "projectile_radius_by_level", "effect_radius_by_level", "duration_ticks_by_level", "pierce_by_level"]:
			var values: Variant = definition.get(key)
			if values.size() != definition.max_level:
				arrays_valid = false
				_error(definition, key, values, "same nonzero length as damage_by_level")
			for index: int in range(values.size()):
				var value: float = float(values[index])
				var needs_positive: bool = key in ["damage_by_level", "cooldown_ticks_by_level", "amount_by_level"]
				if not is_finite(value) or value < 0.0 or (needs_positive and value == 0.0):
					_error(definition, "%s[%d]" % [key, index], values[index], "finite and positive" if needs_positive else "finite and nonnegative")
		for key: String in ["critical_chance", "life_steal_ratio"]:
			_require(definition, key, float(definition.get(key)) <= 1.0, "probability/ratio in [0, 1]")
		_require(definition, "critical_multiplier", definition.critical_multiplier >= 1.0, ">= 1")
		if definition.is_evolved:
			_require(definition, "selection_weight", definition.selection_weight == 0.0, "evolved weapons are acquired by evolution only (0)")
			_require(definition, "max_level", definition.max_level == 1, "one terminal evolved level")
		else:
			total += definition.selection_weight
		if not arrays_valid:
			continue
		for level: int in range(2, definition.max_level + 1):
			if definition.level_deltas(level).is_empty():
				_error(definition, "level[%d]" % level, "no changes", "at least one stat changes")
		for level: int in range(1, definition.max_level + 1):
			if definition.behavior == GameTypes.WeaponBehavior.ORBITAL and definition.range_at(level) <= 0.0:
				_error(definition, "range_by_level[%d]" % (level - 1), definition.range_at(level), "positive orbital radius for angular motion")
			var outer: float = StatCalculator.weapon_outer_radius(definition, level, max_area)
			if not is_finite(outer) or outer > _manifest.combat.effect_outer_radius + FLOAT_TOLERANCE:
				_error(definition, "effective_outer_radius(level=%d)" % level, outer, "<= combat.effect_outer_radius (%s m) at maximum attainable area" % _manifest.combat.effect_outer_radius)
	_require(_manifest, "weapons", is_finite(total) and total > 0.0, "finite positive basic weapon selection weight total")


func _maximum_area_multiplier() -> float:
	var gains: Array[float] = []
	for definition: PassiveDefinition in passives.values():
		if definition.stat_id == &"area_pct" and definition.amount_per_level > 0.0:
			gains.append(definition.amount_per_level * float(maxi(0, definition.max_level)))
	gains.sort()
	gains.reverse()
	var total: float = 0.0
	for index: int in range(mini(maxi(0, _manifest.progression.passive_slot_count), gains.size())):
		total += gains[index]
	return maxf(_manifest.combat.min_area_multiplier, 1.0 + total / 100.0)


func _validate_evolutions() -> void:
	var targets: Dictionary[StringName, bool] = {}
	for definition: EvolutionDefinition in evolutions.values():
		var base: WeaponDefinition = weapon(definition.base_weapon_id)
		var evolved: WeaponDefinition = weapon(definition.evolved_weapon_id)
		_require(definition, "base_weapon_id", base != null and not base.is_evolved, "existing basic weapon")
		_require(definition, "passive_id", passive(definition.passive_id) != null, "existing passive")
		_require(definition, "evolved_weapon_id", evolved != null and evolved.is_evolved and not targets.has(definition.evolved_weapon_id), "unique existing evolved weapon")
		targets[definition.evolved_weapon_id] = true
	for id: StringName in _evolved_weapon_ids:
		_require(weapon(id), "weapon_id", targets.has(id), "referenced by an evolution definition")


func _validate_enemy(definition: EnemyDefinition) -> void:
	_validate_numbers(definition)
	_require(definition, "display_name", not definition.display_name.is_empty(), "nonempty name")
	for key: String in ["base_hp", "body_radius"]:
		_positive(definition, key)
	_require(definition, "enemy_id", definition.enemy_id != &"", "nonempty ID")
	_require(definition, "enemy_type", int(definition.enemy_type) in GameTypes.EnemyType.values(), "supported enemy type")
	maximum_enemy_body_radius = maxf(maximum_enemy_body_radius, definition.body_radius)
	if definition.enemy_type != GameTypes.EnemyType.BOSS:
		for key: String in ["special_interval_ticks", "telegraph_ticks", "projectile_damage", "projectile_speed", "projectile_radius", "projectile_lifetime_ticks", "volley_count"]:
			_require(definition, key, float(definition.get(key)) == 0.0, "contact-only enemy: unused special attack field must be 0")
	elif definition.special_interval_ticks > 0:
		for key: String in ["telegraph_ticks", "projectile_lifetime_ticks", "volley_count"]:
			_positive(definition, key)


func _validate_swarm() -> void:
	var swarm: SwarmEventDefinition = _manifest.swarm_event
	_validate_numbers(swarm)
	for key: String in ["lateral_count", "depth_count", "lateral_pitch", "depth_pitch", "telegraph_ticks"]:
		_positive(swarm, key)
	_require(swarm, "event_id", swarm.event_id != &"", "nonempty ID")
	_require(swarm, "member_count", swarm.member_count > 0 and swarm.member_count <= EnemyStore.CAPACITY, "formation product in [1, enemy pool capacity %d]" % EnemyStore.CAPACITY)
	_require(swarm, "unit_definition", swarm.unit_definition != null, "required enemy Resource")
	if swarm.unit_definition != null:
		_validate_enemy(swarm.unit_definition)
		_require(swarm.unit_definition, "enemy_type", swarm.unit_definition.enemy_type == GameTypes.EnemyType.SWARMER, "swarm event unit is SWARMER")


func _validate_encounters() -> void:
	var encounter: EncounterBalanceDefinition = _manifest.encounters
	_validate_numbers(encounter)
	for key: String in ["member_count", "elite_radius_x", "elite_radius_y", "elite_lifetime_ticks", "opponent_distance", "boss_initial_radius", "boss_final_radius", "boss_shrink_ticks"]:
		_positive(encounter, key)
	_require(encounter, "member_count", encounter.member_count < EnemyStore.CAPACITY, "members and opponent fit enemy pool")
	_require(encounter, "unit_definition", encounter.unit_definition != null, "required enemy Resource")
	if encounter.unit_definition == null:
		return
	_validate_enemy(encounter.unit_definition)
	_require(encounter.unit_definition, "enemy_type", encounter.unit_definition.enemy_type == GameTypes.EnemyType.PURSUER, "encircler is a pursuing contact enemy")
	var elite: EnemyDefinition = enemy_for_type(GameTypes.EnemyType.ELITE)
	var boss: EnemyDefinition = enemy_for_type(GameTypes.EnemyType.BOSS)
	if elite == null or boss == null:
		return
	_require(encounter, "opponent_distance", encounter.opponent_distance > _manifest.player.body_radius + maxf(elite.body_radius, boss.body_radius), "opponent starts clear of player")
	_require(encounter, "elite_radius_x", minf(encounter.elite_radius_x, encounter.elite_radius_y) > encounter.opponent_distance + elite.body_radius + encounter.unit_definition.body_radius, "opponent fits inside ring")
	_require(encounter, "boss_initial_radius", encounter.boss_initial_radius > encounter.opponent_distance + boss.body_radius and encounter.boss_initial_radius >= encounter.boss_final_radius, "opponent fits initial boundary; shrink cannot expand")
	_require(encounter, "boss_final_radius", encounter.boss_final_radius > boss.body_radius + _manifest.player.body_radius, "both bodies fit final boundary")


func _validate_segments() -> void:
	_require(_manifest, "segments", not _manifest.segments.is_empty(), "at least one ordered segment")
	for index: int in range(_manifest.segments.size()):
		var definition: EnemySegmentDefinition = segment(index)
		if definition == null:
			continue
		_validate_numbers(definition)
		_positive(definition, "duration_ticks")
		_positive(definition, "hp_multiplier")
		_require(definition, "target_active", definition.target_active <= EnemyStore.CAPACITY, "0..enemy pool capacity %d" % EnemyStore.CAPACITY)
		_validate_weights(definition, "spawn_weights", GameTypes.EnemyType.size())
		for enemy_type: int in [GameTypes.EnemyType.ELITE, GameTypes.EnemyType.BOSS]:
			if enemy_type < definition.spawn_weights.size():
				_require(definition, "spawn_weights", definition.spawn_weights[enemy_type] == 0.0, "elite/boss weights are 0; scheduled separately")
		if definition.duration_ticks <= 0 or definition.duration_ticks > 2147483647 - boss_start_tick:
			_require(definition, "duration_ticks", false, "positive duration, cumulative tick <= 2147483647")
			continue
		segment_start_ticks.append(boss_start_tick)
		for elite: EliteSpawnDefinition in definition.elite_spawns:
			if elite == null:
				_error(definition, "elite_spawns", null, "required elite spawn Resource")
				continue
			_validate_numbers(elite)
			_require(elite, "offset_ticks", elite.offset_ticks >= 0 and elite.offset_ticks < definition.duration_ticks, "0 <= offset_ticks < duration_ticks")
			_require(elite, "chest_kind", int(elite.chest_kind) in GameTypes.ChestKind.values(), "supported chest kind")
			if elite.offset_ticks >= 0 and elite.offset_ticks < definition.duration_ticks:
				elite_spawn_ticks.append(boss_start_tick + elite.offset_ticks)
				elite_chest_kinds.append(elite.chest_kind)
		var ids: Dictionary[StringName, bool] = {}
		for schedule: SwarmEventScheduleDefinition in definition.swarm_schedules:
			if schedule == null:
				_error(definition, "swarm_schedules", null, "required schedule Resource")
				continue
			_validate_numbers(schedule)
			_require(schedule, "schedule_id", schedule.schedule_id != &"" and not ids.has(schedule.schedule_id), "nonempty unique ID within segment")
			ids[schedule.schedule_id] = true
			_positive(schedule, "interval_ticks")
			_positive(schedule, "hp_multiplier")
			_require(schedule, "spawn_chance", schedule.spawn_chance <= 1.0, "probability in [0, 1]")
			var last_offset: int = schedule.first_offset_ticks + maxi(0, schedule.attempt_count - 1) * schedule.interval_ticks
			var fits: bool = schedule.first_offset_ticks >= 0 and last_offset >= schedule.first_offset_ticks and last_offset < definition.duration_ticks
			_require(schedule, "first_offset_ticks", fits, "all attempts inside segment: first + (count - 1) * interval < duration_ticks (%d)" % definition.duration_ticks)
			if fits and schedule.interval_ticks > 0 and schedule.attempt_count >= 0:
				for attempt: int in range(schedule.attempt_count):
					swarm_attempts.append({&"tick": boss_start_tick + schedule.first_offset_ticks + attempt * schedule.interval_ticks, &"chance": schedule.spawn_chance, &"hp_multiplier": schedule.hp_multiplier, &"damage_multiplier": schedule.damage_multiplier})
		boss_start_tick += definition.duration_ticks
		segment_end_ticks.append(boss_start_tick)


func _validate_numbers(resource: Resource, signed_fields: Array[String] = []) -> void:
	for property: Dictionary in resource.get_property_list():
		if (int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var key: String = property.name
		var value: Variant = resource.get(key)
		if typeof(value) == TYPE_FLOAT:
			_require(resource, key, is_finite(float(value)) and (key in signed_fields or float(value) >= 0.0), "finite signed value" if key in signed_fields else "finite nonnegative value")
		elif typeof(value) == TYPE_INT and key not in signed_fields:
			_require(resource, key, int(value) >= 0, "nonnegative integer")


func _validate_weights(resource: Resource, key: String, size: int) -> void:
	var values: Variant = resource.get(key)
	_require(resource, key, values.size() == size, "%d weights in enum order" % size)
	var total: float = 0.0
	for index: int in range(values.size()):
		var value: float = float(values[index])
		if not is_finite(value) or value < 0.0:
			_error(resource, "%s[%d]" % [key, index], value, "finite nonnegative relative weight")
		total += value
	_require(resource, key, is_finite(total) and total > 0.0, "finite positive total relative weight")


func _unique_positive_integers(resource: Resource, key: String) -> void:
	var used: Dictionary[int, bool] = {}
	for value: int in resource.get(key):
		_require(resource, key, value > 0 and not used.has(value), "unique positive integers")
		used[value] = true


func _positive(resource: Resource, key: String) -> void:
	var value: float = float(resource.get(key))
	_require(resource, key, is_finite(value) and value > 0.0, "finite and positive")


func _require(resource: Resource, key: String, condition: bool, rule: String) -> void:
	if not condition:
		_error(resource, key, resource.get(key), rule)


func _error(resource: Resource, key: String, value: Variant, rule: String) -> void:
	var path: String = resource.resource_path
	if path.is_empty():
		path = "<%s fixture>" % (resource.get_script() as Script).get_global_name()
	validation_errors.append("%s: %s=%s; %s" % [path, key, var_to_str(value), rule])


func _finish_validation() -> bool:
	is_valid = validation_errors.is_empty()
	error_text = "\n".join(validation_errors)
	return is_valid
