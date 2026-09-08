extends RefCounted

const BotObservation = preload("res://dev/bot/bot_observation.gd")

## Public game rules copied from the validated catalog, without run state.
var move_speed: float
var player_radius: float
var pickup_radius: float
var weapon_slots: int
var passive_slots: int
var starter_weapon_id: StringName
var weapons: Dictionary[StringName, Dictionary] = {}
var passives: Dictionary[StringName, Dictionary] = {}
var evolutions: Dictionary[StringName, Dictionary] = {}
var enemy_speeds: Dictionary[int, float] = {}
var swarm_speed: float
var swarm_radius: float
var spawn_band_width: float
var swarm_depth: float
var minimum_cooldown_multiplier: float


func _init(catalog: DefinitionCatalog) -> void:
	var content: SurvivalContentManifest = catalog.manifest()
	move_speed = content.player.move_speed
	player_radius = content.player.body_radius
	pickup_radius = content.progression.xp_pickup_attract_radius
	weapon_slots = content.progression.weapon_slot_count
	passive_slots = content.progression.passive_slot_count
	starter_weapon_id = content.progression.starter_weapon_id
	swarm_speed = content.swarm_event.unit_definition.move_speed
	swarm_radius = content.swarm_event.unit_definition.body_radius
	spawn_band_width = content.spawn.offscreen_band_width
	swarm_depth = float(content.swarm_event.depth_count - 1) * content.swarm_event.depth_pitch
	minimum_cooldown_multiplier = content.combat.min_cooldown_multiplier
	for definition: WeaponDefinition in content.weapons:
		weapons[definition.weapon_id] = {
			"behavior": definition.behavior, "max_level": definition.max_level,
			"damage": definition.damage_by_level.duplicate(),
			"cooldown": definition.cooldown_ticks_by_level.duplicate(),
			"amount": definition.amount_by_level.duplicate(),
			"range": definition.range_by_level.duplicate(),
			"effect_radius": definition.effect_radius_by_level.duplicate(),
			"life_steal": definition.life_steal_ratio,
		}
	for definition: PassiveDefinition in content.passives:
		passives[definition.passive_id] = {
			"stat": definition.stat_id, "amount": definition.amount_per_level,
			"max_level": definition.max_level,
		}
	for definition: EvolutionDefinition in content.evolutions:
		evolutions[definition.base_weapon_id] = {
			"passive": definition.passive_id, "weapon": definition.evolved_weapon_id,
		}
	for definition: EnemyDefinition in content.enemies:
		enemy_speeds[int(definition.enemy_type)] = definition.move_speed


func evolution_ready(observation: BotObservation) -> bool:
	for weapon: Dictionary in observation.weapons:
		var weapon_id: StringName = weapon["id"]
		if not evolutions.has(weapon_id):
			continue
		if int(weapon["level"]) < int(weapons[weapon_id]["max_level"]):
			continue
		for passive: Dictionary in observation.passives:
			if passive["id"] == evolutions[weapon_id]["passive"]:
				return true
	return false
