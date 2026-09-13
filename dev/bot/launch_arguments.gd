extends RefCounted

const OPTIONS: Array[String] = ["--bot", "--run-seed", "--runs", "--bot-speed", "--bot-view", "--bot-profile", "--bot-evolution-after-tick"]


static func parse(arguments: PackedStringArray) -> Dictionary:
	var parsed: Dictionary = _parse_named_values(arguments, OPTIONS)
	if not parsed["valid"]:
		return parsed
	var values: Dictionary = parsed["values"]
	if not values.has("--bot"):
		return _rejected("--bot")
	return _parse_bot(values)


static func _parse_bot(values: Dictionary) -> Dictionary:
	if values["--bot"] not in ["fast", "watch"]:
		return _rejected("--bot")
	var seed_text: String = values.get("--run-seed", "1")
	var runs_text: String = values.get("--runs", "1")
	var speed_text: String = values.get("--bot-speed", "1")
	var profile_text: String = values.get("--bot-profile", "0")
	var evolution_text: String = values.get("--bot-evolution-after-tick", "0")
	if not evolution_text.is_valid_int() or evolution_text.to_int() < 0 or evolution_text.to_int() > 108000:
		return _rejected("--bot-evolution-after-tick")
	if profile_text not in ["0", "1"]:
		return _rejected("--bot-profile")
	if not seed_text.is_valid_int() or str(seed_text.to_int()) != seed_text:
		return _rejected("--run-seed")
	if not runs_text.is_valid_int() or runs_text.to_int() < 1 or runs_text.to_int() > 1_000_000:
		return _rejected("--runs")
	if seed_text.to_int() > 9223372036854775807 - (runs_text.to_int() - 1):
		return _rejected("--run-seed")
	if speed_text not in ["1", "4", "16"]:
		return _rejected("--bot-speed")
	if values["--bot"] == "watch" and runs_text.to_int() != 1:
		return _rejected("--runs")
	if values["--bot"] == "fast" and values.has("--bot-speed"):
		return _rejected("--bot-speed")
	var view_text: String = values.get("--bot-view", "1920x1080")
	var dimensions: PackedStringArray = view_text.split("x")
	if dimensions.size() != 2:
		return _rejected("--bot-view")
	for dimension: String in dimensions:
		if not dimension.is_valid_int() or dimension.to_int() < 64 or dimension.to_int() > 16384:
			return _rejected("--bot-view")
	var result: Dictionary = {"valid": true, "rejected_name": ""}
	result["bot"] = values["--bot"]
	result["run_seed"] = seed_text.to_int()
	result["runs"] = runs_text.to_int()
	result["bot_speed"] = speed_text.to_int()
	result["bot_profile"] = profile_text == "1"
	result["bot_evolution_after_tick"] = evolution_text.to_int()
	result["bot_view"] = Vector2i(dimensions[0].to_int(), dimensions[1].to_int())
	return result


static func _parse_named_values(arguments: PackedStringArray, allowed: Array[String]) -> Dictionary:
	var values: Dictionary = {}
	for argument in arguments:
		var option_name := _option_name(argument)
		if not option_name in allowed:
			return _rejected(option_name)
		if values.has(option_name):
			return _rejected(option_name)
		if not argument.contains("="):
			return _rejected(option_name)
		var value := argument.substr(argument.find("=") + 1)
		if value.is_empty():
			return _rejected(option_name)
		values[option_name] = value
	return {"valid": true, "values": values}


static func _rejected(name: String) -> Dictionary:
	return {"valid": false, "rejected_name": name if not name.is_empty() else "missing"}


static func _option_name(argument: String) -> String:
	if argument.is_empty():
		return "missing"
	var equals_index := argument.find("=")
	if equals_index < 0:
		return argument
	return argument.substr(0, equals_index)
