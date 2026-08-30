class_name UniqueSelector
extends RefCounted


const UNIQUE_IDS: Array[StringName] = [
	&"bloodied_dagger",
	&"broken_clock",
	&"coward_boots",
	&"echo_gauntlet",
	&"hollow_crown",
	&"immortal_breastplate",
]


static func select_uniform(rng: RandomNumberGenerator) -> StringName:
	var weights := PackedFloat64Array()
	weights.resize(UNIQUE_IDS.size())
	weights.fill(1.0)
	return WeightedSelector.select(rng, UNIQUE_IDS, weights)
