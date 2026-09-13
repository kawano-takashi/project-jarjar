extends CombatSimulation

## Accepted damage capped at remaining HP, before recovery; reporting only.
var total_damage_taken: float = 0.0
var recording_enabled: bool = true
var damage_by_source: Dictionary[StringName, float] = {}
var fatal_hit: Dictionary = {}
var _damage_source: StringName = &"unknown"


func _apply_player_damage_candidates(candidates: Array[Dictionary]) -> void:
	if recording_enabled:
		var selected: Dictionary = _select_player_damage_candidate(candidates)
		_damage_source = selected.get("source_effect_id", &"unknown")
		var enemy: EnemyEntity = enemy_system.enemy_store.get_by_id(int(selected.get("source_entity_id", -1)))
		if enemy != null:
			_damage_source = enemy.definition.enemy_id
	super(candidates)
	_damage_source = &"unknown"


func _apply_raw_player_damage(raw_damage: float) -> void:
	var hp_before: float = state.current_hp
	super(raw_damage)
	if recording_enabled and state.current_hp < hp_before:
		var accepted: float = minf(hp_before, raw_damage)
		total_damage_taken += accepted
		damage_by_source[_damage_source] = damage_by_source.get(_damage_source, 0.0) + accepted
		if state.current_hp <= 0.0:
			fatal_hit = {"source": _damage_source, "tick": state.combat_tick, "damage": accepted}
