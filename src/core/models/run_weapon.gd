class_name RunWeapon
extends RefCounted


var weapon_id: StringName = &""
var lineage_id: StringName = &""
var level: int = 1
var evolved: bool = false
var cooldown_remaining_ticks: int = 0
var ready_on_resume: bool = true
var rng: RandomNumberGenerator = null


static func create(
	p_weapon_id: StringName,
	p_lineage_id: StringName,
	p_evolved: bool,
	p_rng: RandomNumberGenerator,
) -> RunWeapon:
	var runtime := RunWeapon.new()
	runtime.weapon_id = p_weapon_id
	runtime.lineage_id = p_lineage_id
	runtime.evolved = p_evolved
	runtime.rng = p_rng
	return runtime
