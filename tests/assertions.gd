class_name JarjarAssertions
extends RefCounted


var records: Array[Dictionary] = []


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


func has_failures() -> bool:
	for record in records:
		if not record["passed"]:
			return true
	return false


func failure_count() -> int:
	var count := 0
	for record in records:
		if not record["passed"]:
			count += 1
	return count


func _record(label: String, expected: Variant, actual: Variant, passed: bool) -> void:
	records.append({
		"label": label,
		"expected": _display(expected),
		"actual": _display(actual),
		"passed": passed,
	})


func _display(value: Variant) -> String:
	return str(value).replace("\r", "\\r").replace("\n", "\\n")
