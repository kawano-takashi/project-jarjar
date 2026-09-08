class_name RunRngStreams
extends RefCounted


var run_seed: int = 0
var spawn_seed: int = 0
var upgrade_seed: int = 0
var chest_seed: int = 0
var powerup_seed: int = 0
var swarm_event_seed: int = 0
var spawn_rng: RandomNumberGenerator = null
var upgrade_rng: RandomNumberGenerator = null
var chest_rng: RandomNumberGenerator = null
var powerup_rng: RandomNumberGenerator = null
var swarm_event_rng: RandomNumberGenerator = null
var node_spawn_rng: RandomNumberGenerator = null


static func create(p_run_seed: int) -> RunRngStreams:
	var streams := RunRngStreams.new()
	streams.run_seed = p_run_seed
	streams.spawn_seed = SeedService.derive(p_run_seed, &"spawn")
	streams.upgrade_seed = SeedService.derive(p_run_seed, &"upgrade")
	streams.chest_seed = SeedService.derive(p_run_seed, &"chest")
	streams.powerup_seed = SeedService.derive(p_run_seed, &"powerup")
	streams.swarm_event_seed = SeedService.derive(p_run_seed, &"swarm_event")
	streams.spawn_rng = _rng_from_seed(streams.spawn_seed)
	streams.upgrade_rng = _rng_from_seed(streams.upgrade_seed)
	streams.chest_rng = _rng_from_seed(streams.chest_seed)
	streams.powerup_rng = _rng_from_seed(streams.powerup_seed)
	streams.swarm_event_rng = _rng_from_seed(streams.swarm_event_seed)
	streams.node_spawn_rng = _rng_from_seed(SeedService.derive(p_run_seed, &"node_spawn"))
	return streams


func create_weapon_rng(lineage_id: StringName, slot_index: int) -> RandomNumberGenerator:
	return _rng_from_seed(SeedService.derive(
		run_seed,
		StringName("weapon|%s|%d" % [lineage_id, slot_index]),
	))


func create_enemy_rng(entity_id: int) -> RandomNumberGenerator:
	return _rng_from_seed(SeedService.derive(
		run_seed,
		StringName("enemy|%d" % entity_id),
	))


func state_digest() -> Dictionary:
	return {
		&"spawn": spawn_rng.state,
		&"upgrade": upgrade_rng.state,
		&"chest": chest_rng.state,
		&"powerup": powerup_rng.state,
		&"swarm_event": swarm_event_rng.state,
		&"node_spawn": node_spawn_rng.state,
	}


static func _rng_from_seed(value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = value
	return rng
