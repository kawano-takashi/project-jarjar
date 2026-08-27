class_name UniqueSelector
extends RefCounted


const UNIQUE_CHANCE: float = 0.04
const UNIQUE_IDS: Array[StringName] = [
	&"bloodied_dagger",
	&"broken_clock",
	&"coward_boots",
	&"echo_gauntlet",
	&"hollow_crown",
	&"immortal_breastplate",
]


static func select_won(rng: RandomNumberGenerator) -> StringName:
	var weights := PackedFloat64Array()
	weights.resize(UNIQUE_IDS.size())
	weights.fill(1.0)
	return WeightedSelector.select(rng, UNIQUE_IDS, weights)
