class_name JarjarAssertions
extends RefCounted


var test_name: String = ""
var verbose: bool = false
var check_count: int = 0
var failures: int = 0


func expect_equal(expected: Variant, actual: Variant, label: String) -> void:
	_record(label, expected, actual, expected == actual)


func expect_true(actual: bool, label: String) -> void:
	_record(label, true, actual, actual)


func expect_false(actual: bool, label: String) -> void:
	_record(label, false, actual, not actual)


func expect_float(expected: float, actual: float, label: String) -> void:
	_record(label, expected, actual, is_equal_approx(expected, actual))


func expect_not_equal(unexpected: Variant, actual: Variant, label: String) -> void:
	_record(label, "not %s" % _display(unexpected), actual, unexpected != actual)


func _record(label: String, expected: Variant, actual: Variant, passed: bool) -> void:
	check_count += 1
	if not passed:
		failures += 1
	if verbose or not passed:
		print("ASSERT test=%s label=%s expected=%s actual=%s result=%s" % [
			test_name, label, _display(expected), _display(actual), "PASS" if passed else "FAIL",
		])


func _display(value: Variant) -> String:
	return str(value).replace("\r", "\\r").replace("\n", "\\n")
