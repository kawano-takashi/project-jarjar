extends "res://tests/test_runner.gd"


func _excluded_roots() -> Array[String]:
	return ["tests"]


func _test_directory() -> String:
	return "res://dev/bot/tests/"
