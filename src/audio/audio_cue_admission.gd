class_name AudioCueAdmission
extends RefCounted


const MAX_CUES_PER_WINDOW: int = 12
const MAX_NONCRITICAL_CUES_PER_WINDOW: int = 8
const MAX_PICKUP_CUES_PER_WINDOW: int = 4
const PRIORITY_AMBIENT: int = 0
const PRIORITY_IMPORTANT: int = 2

var admitted_count: int = 0
var suppressed_count: int = 0

var _admitted_units: Array[int] = []
var _admitted_priorities: PackedInt32Array = PackedInt32Array()
var _last_request_unit_by_group: Dictionary[StringName, int] = {}


func reset() -> void:
	admitted_count = 0
	suppressed_count = 0
	_admitted_units.clear()
	_admitted_priorities.clear()
	_last_request_unit_by_group.clear()


func try_admit(
	now_units: int,
	window_units: int,
	incoming_priority: int,
	group: StringName = &"",
	cooldown_units: int = 0,
	force: bool = false,
) -> bool:
	var resolved_window: int = maxi(1, window_units)
	var resolved_cooldown: int = maxi(0, cooldown_units)
	if not group.is_empty() and resolved_cooldown > 0:
		var previous_unit: int = int(_last_request_unit_by_group.get(
			group,
			now_units - resolved_cooldown,
		))
		if not force and now_units - previous_unit < resolved_cooldown:
			suppressed_count += 1
			return false
		# Match production feedback: a cue that reaches the global admission
		# stage starts its group cooldown even if the rolling budget is full.
		_last_request_unit_by_group[group] = now_units
	_prune(now_units, resolved_window)
	if _admitted_units.size() >= MAX_CUES_PER_WINDOW:
		suppressed_count += 1
		return false
	var noncritical_count: int = 0
	var pickup_count: int = 0
	for priority: int in _admitted_priorities:
		if priority < PRIORITY_IMPORTANT:
			noncritical_count += 1
		if priority <= PRIORITY_AMBIENT:
			pickup_count += 1
	if incoming_priority < PRIORITY_IMPORTANT:
		if noncritical_count >= MAX_NONCRITICAL_CUES_PER_WINDOW:
			suppressed_count += 1
			return false
		if (
			incoming_priority <= PRIORITY_AMBIENT
			and pickup_count >= MAX_PICKUP_CUES_PER_WINDOW
		):
			suppressed_count += 1
			return false
	_admitted_units.append(now_units)
	_admitted_priorities.append(incoming_priority)
	admitted_count += 1
	return true


func _prune(now_units: int, window_units: int) -> void:
	var expired_count: int = 0
	while (
		expired_count < _admitted_units.size()
		and now_units - _admitted_units[expired_count] >= window_units
	):
		expired_count += 1
	if expired_count <= 0:
		return
	_admitted_units = _admitted_units.slice(expired_count)
	_admitted_priorities = _admitted_priorities.slice(expired_count)
