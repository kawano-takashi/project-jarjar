class_name JarjarTestRegistry
extends RefCounted


const UNIT_SCRIPT_PATHS: Array[String] = [
	"res://tests/unit/smoke_bootstrap_test.gd",
	"res://tests/unit/gate_02_domain_test.gd",
]
const SCENARIO_SCRIPT_PATHS: Array[String] = []
const SIMULATION_SCRIPT_PATHS: Array[String] = []


static func script_paths_for_suite(suite: String) -> Array[String]:
	match suite:
		"unit":
			return UNIT_SCRIPT_PATHS.duplicate()
		"scenario":
			return SCENARIO_SCRIPT_PATHS.duplicate()
		"simulation":
			return SIMULATION_SCRIPT_PATHS.duplicate()
	return []
