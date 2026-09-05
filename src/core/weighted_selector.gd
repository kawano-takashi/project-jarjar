class_name WeightedSelector
extends RefCounted


static func validate_weights(
	candidates: Array[StringName],
	weights: PackedFloat64Array
) -> bool:
	if candidates.is_empty() or candidates.size() != weights.size():
		return false
	var total: float = 0.0
	for weight: float in weights:
		if not is_finite(weight) or weight < 0.0:
			return false
		total += weight
	return is_finite(total) and total > 0.0


static func select(
	rng: RandomNumberGenerator,
	candidates: Array[StringName],
	weights: PackedFloat64Array
) -> StringName:
	if not validate_weights(candidates, weights):
		return &""
	return select_with_value(candidates, weights, rng.randf())


static func select_with_value(
	candidates: Array[StringName],
	weights: PackedFloat64Array,
	randf_value: float
) -> StringName:
	if not validate_weights(candidates, weights):
		return &""
	var total: float = 0.0
	var last_positive: StringName = &""
	for index: int in range(candidates.size()):
		var weight: float = weights[index]
		if weight <= 0.0:
			continue
		total += weight
		last_positive = candidates[index]
	var roll: float = clampf(randf_value, 0.0, 1.0) * total
	var cumulative: float = 0.0
	for index: int in range(candidates.size()):
		var weight: float = weights[index]
		if weight <= 0.0:
			continue
		cumulative += weight
		if roll < cumulative:
			return candidates[index]
	return last_positive


## Godot randf() includes both endpoints; probability 1 must also accept a draw of 1.
static func chance_succeeds_with_value(probability: float, randf_value: float) -> bool:
	if not is_finite(probability) or probability < 0.0 or probability > 1.0:
		return false
	if not is_finite(randf_value) or randf_value < 0.0 or randf_value > 1.0:
		return false
	return probability > 0.0 and (probability == 1.0 or randf_value < probability)


static func sort_ordinal(candidates: Array[StringName]) -> Array[StringName]:
	var sorted: Array[StringName] = []
	for index: int in _ordinal_order(candidates):
		sorted.append(candidates[index])
	return sorted


static func _ordinal_order(candidates: Array[StringName]) -> Array[int]:
	var order: Array[int] = []
	for index: int in range(candidates.size()):
		order.append(index)
	for left: int in range(order.size()):
		var smallest: int = left
		for right: int in range(left + 1, order.size()):
			if String(candidates[order[right]]) < String(candidates[order[smallest]]):
				smallest = right
		if smallest != left:
			var swap: int = order[left]
			order[left] = order[smallest]
			order[smallest] = swap
	return order
