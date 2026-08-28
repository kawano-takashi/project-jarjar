class_name JarjarTestRegistry
extends RefCounted


const UNIT_SCRIPT_PATHS: Array[String] = [
	"res://tests/unit/project_contract_test.gd",
	"res://tests/unit/gate_02_domain_test.gd",
	"res://tests/unit/gate_03_combat_core_test.gd",
	"res://tests/unit/gate_04_loot_domain_test.gd",
	"res://tests/unit/gate_05_inventory_domain_test.gd",
	"res://tests/unit/gate_05_combat_skill_test.gd",
	"res://tests/unit/gate_05_qa_fixture_test.gd",
	"res://tests/unit/gate_06_audio_test.gd",
	"res://tests/unit/gate_06_performance_metrics_test.gd",
	"res://tests/unit/gate_06_tutorial_test.gd",
]
const SCENARIO_SCRIPT_PATHS: Array[String] = [
	"res://tests/scenario/gate_03_combat_scenario_test.gd",
	"res://tests/scenario/gate_03_lifecycle_contract_test.gd",
	"res://tests/scenario/gate_04_combat_loot_scenario_test.gd",
	"res://tests/scenario/gate_04_reward_ui_scenario_test.gd",
	"res://tests/scenario/gate_05_skill_combat_scenario_test.gd",
	"res://tests/scenario/gate_05_inventory_ui_scenario_test.gd",
	"res://tests/scenario/gate_06_controller_only_scenario_test.gd",
	"res://tests/scenario/gate_06_fusion_accessibility_scenario_test.gd",
	"res://tests/scenario/gate_06_ui_polish_scenario_test.gd",
]
const SIMULATION_SCRIPT_PATHS: Array[String] = [
	"res://tests/simulation/gate_03_wave_simulation_test.gd",
	"res://tests/simulation/gate_04_loot_simulation_test.gd",
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
