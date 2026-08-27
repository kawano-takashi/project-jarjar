class_name FailedScreen
extends RunSummaryScreen


func _screen_prefix() -> String:
	return "failed"


func _is_failed_screen() -> bool:
	return true
