class_name RunStateFactory
extends RefCounted


const ItemFactoryScript := preload("res://src/loot/item_factory.gd")


static func create(run_seed: int, first_wave: WaveDefinition) -> RunState:
	var state := RunState.new()
	state.run_seed = run_seed
	state.rng_streams = RunRngStreams.create(run_seed)
	state.phase = GameTypes.RunPhase.COMBAT
	state.wave_number = 1
	state.time_remaining = first_wave.duration_seconds
	state.current_hp = 100.0
	state.max_hp = 100.0
	var wood_stick: ItemInstance = ItemFactoryScript.create_initial_wood_stick(run_seed)
	state.equipped[GameTypes.EquipmentSlot.WEAPON_1] = wood_stick
	state.drop_serial = 1
	return state
