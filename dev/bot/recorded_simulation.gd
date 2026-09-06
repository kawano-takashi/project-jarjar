extends CombatSimulation

## Accepted damage capped at remaining HP, before recovery; reporting only.
var total_damage_taken: float = 0.0

func _apply_raw_player_damage(raw_damage: float) -> void:
	var hp_before: float = state.current_hp
	super(raw_damage)
	if state.current_hp < hp_before:
		total_damage_taken += minf(hp_before, raw_damage)
