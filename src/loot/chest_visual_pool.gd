class_name ChestVisualPool
extends RefCounted


const ChestVisualScript := preload("res://src/loot/chest_visual.gd")
const CAPACITY: int = 128

var slots: Array[ChestVisualScript] = []
var forced_absorb_count: int = 0
var completed_absorb_count: int = 0

var _next_activation_serial: int = 0


func _init() -> void:
	for _index: int in range(CAPACITY):
		slots.append(ChestVisualScript.new())


func acquire(reward_id: String, position: Vector2, acquired_tick: int) -> ChestVisualScript:
	var visual: ChestVisualScript = _first_inactive()
	if visual == null:
		visual = _oldest_active()
		visual.deactivate()
		forced_absorb_count += 1
	visual.activate(reward_id, position, acquired_tick, _next_activation_serial)
	_next_activation_serial += 1
	return visual


func advance(delta: float) -> void:
	for visual: ChestVisualScript in slots:
		if visual.advance(delta):
			completed_absorb_count += 1


func transforms() -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	for visual: ChestVisualScript in slots:
		if visual.active:
			result.append(visual.current_transform())
	return result


func absorb_all() -> void:
	for visual: ChestVisualScript in slots:
		if visual.active:
			visual.deactivate()
			completed_absorb_count += 1


func clear() -> void:
	for visual: ChestVisualScript in slots:
		visual.deactivate()
	forced_absorb_count = 0
	completed_absorb_count = 0
	_next_activation_serial = 0


func active_count() -> int:
	var count: int = 0
	for visual: ChestVisualScript in slots:
		if visual.active:
			count += 1
	return count


func _first_inactive() -> ChestVisualScript:
	for visual: ChestVisualScript in slots:
		if not visual.active:
			return visual
	return null


func _oldest_active() -> ChestVisualScript:
	var oldest: ChestVisualScript = null
	for visual: ChestVisualScript in slots:
		if not visual.active:
			continue
		if oldest == null or visual.activation_serial < oldest.activation_serial:
			oldest = visual
	return oldest
