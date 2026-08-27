class_name RunRngStreams
extends RefCounted


const SeedServiceScript := preload("res://src/core/seed_service.gd")

var combat_seed: int = 0
var loot_seed: int = 0
var fusion_seed: int = 0
var combat_rng: RandomNumberGenerator
var loot_rng: RandomNumberGenerator
var fusion_rng: RandomNumberGenerator


static func create(run_seed: int) -> RunRngStreams:
	var streams := RunRngStreams.new()
	streams.combat_seed = SeedServiceScript.derive(run_seed, &"combat")
	streams.loot_seed = SeedServiceScript.derive(run_seed, &"loot")
	streams.fusion_seed = SeedServiceScript.derive(run_seed, &"fusion")

	streams.combat_rng = RandomNumberGenerator.new()
	streams.combat_rng.seed = streams.combat_seed
	streams.loot_rng = RandomNumberGenerator.new()
	streams.loot_rng.seed = streams.loot_seed
	streams.fusion_rng = RandomNumberGenerator.new()
	streams.fusion_rng.seed = streams.fusion_seed
	return streams
