class_name JarjarTestRegistry
extends RefCounted


const UNIT_SCRIPT_PATHS: Array[String] = [
	"res://tests/unit/project_contract_test.gd",
	"res://tests/unit/gate_02_domain_test.gd",
	"res://tests/unit/gate_03_combat_core_test.gd",
]
const SCENARIO_SCRIPT_PATHS: Array[String] = [
	"res://tests/scenario/gate_03_combat_scenario_test.gd",
	"res://tests/scenario/gate_03_lifecycle_contract_test.gd",
]
const SIMULATION_SCRIPT_PATHS: Array[String] = [
	"res://tests/simulation/gate_03_wave_simulation_test.gd",
]


static func script_paths_for_suite(suite: String) -> Array[String]:
	match suite:
		"unit":
			return UNIT_SCRIPT_PATHS.duplicate()
		"scenario":
			return SCENARIO_SCRIPT_PATHS.duplicate()
		"simulation":
			return SIMULATION_SCRIPT_PATHS.duplicate()
	return []
