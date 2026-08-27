class_name ResultScreen
extends RunSummaryScreen


func set_evidence_mode(mode: String) -> bool:
	return mode in ["", "final_result"]


func _screen_prefix() -> String:
	return "result"
