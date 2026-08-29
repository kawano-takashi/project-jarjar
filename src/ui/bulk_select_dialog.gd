class_name BulkSelectDialog
extends Control


signal rarity_selected(rarity: GameTypes.Rarity)
signal cancelled

const FOCUS_IDS: Array[String] = [
	"bulk_common",
	"bulk_rare",
	"bulk_epic",
	"bulk_legendary",
	"bulk_cancel",
]

@onready var _common: Button = %BulkCommon
@onready var _rare: Button = %BulkRare
@onready var _epic: Button = %BulkEpic
@onready var _legendary: Button = %BulkLegendary
@onready var _cancel: Button = %BulkCancel

var _focus_controller := FocusController.new()
var _origin_focus_id: String = "action_0"


func _ready() -> void:
	var controls: Array[Control] = [_common, _rare, _epic, _legendary, _cancel]
	var control_map: Dictionary = {}
	var graph: Dictionary = {}
	for index: int in range(controls.size()):
		var focus_id: String = FOCUS_IDS[index]
		control_map[focus_id] = controls[index]
		graph[focus_id] = {
			FocusController.DIRECTION_TOP: FOCUS_IDS[(index - 1 + controls.size()) % controls.size()],
			FocusController.DIRECTION_BOTTOM: FOCUS_IDS[(index + 1) % controls.size()],
			FocusController.DIRECTION_LEFT: focus_id,
			FocusController.DIRECTION_RIGHT: focus_id,
		}
	_focus_controller.configure_graph(
		control_map,
		graph,
		"bulk_common",
		PackedStringArray(FOCUS_IDS),
	)
	_common.pressed.connect(_choose.bind(GameTypes.Rarity.COMMON))
	_rare.pressed.connect(_choose.bind(GameTypes.Rarity.RARE))
	_epic.pressed.connect(_choose.bind(GameTypes.Rarity.EPIC))
	_legendary.pressed.connect(_choose.bind(GameTypes.Rarity.LEGENDARY))
	_cancel.pressed.connect(_cancel_dialog)
	visible = false
	set_process_input(false)
	set_process_unhandled_input(false)


func open_dialog(initial_rarity: GameTypes.Rarity, p_origin_focus_id: String = "action_0") -> void:
	_origin_focus_id = p_origin_focus_id
	visible = true
	set_process_input(true)
	var initial_id: String = _focus_id_for_rarity(initial_rarity)
	_focus_controller.set_initial_focus_id(initial_id)
	_focus_controller.focus_initial_deferred()


func close_without_signal() -> void:
	visible = false
	set_process_input(false)
	set_process_unhandled_input(false)


func focus_order() -> PackedStringArray:
	return PackedStringArray(FOCUS_IDS)


func focus_controls() -> Dictionary:
	var result: Dictionary = {}
	for focus_id: String in FOCUS_IDS:
		result[focus_id] = _focus_controller.control_for_id(focus_id)
	return result


func origin_focus_id() -> String:
	return _origin_focus_id


func debug_state() -> Dictionary:
	return {
		"visible": visible,
		"focus_id": _focus_controller.current_focus_id(get_viewport()),
		"origin_focus_id": _origin_focus_id,
	}


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		_cancel_dialog()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"ui_focus_next") and not event.is_echo():
		_focus_controller.move_tab(get_viewport(), true)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"ui_focus_prev") and not event.is_echo():
		_focus_controller.move_tab(get_viewport(), false)
		get_viewport().set_input_as_handled()
		return
	var direction: StringName = FocusController.direction_for_event(event)
	if not direction.is_empty():
		_focus_controller.move(get_viewport(), direction)
		get_viewport().set_input_as_handled()
	elif FocusController.is_left_stick_focus_motion(event):
		get_viewport().set_input_as_handled()


func _choose(rarity: GameTypes.Rarity) -> void:
	if not visible:
		return
	close_without_signal()
	rarity_selected.emit(rarity)


func _cancel_dialog() -> void:
	if not visible:
		return
	close_without_signal()
	cancelled.emit()


func _focus_id_for_rarity(rarity: GameTypes.Rarity) -> String:
	match rarity:
		GameTypes.Rarity.RARE:
			return "bulk_rare"
		GameTypes.Rarity.EPIC:
			return "bulk_epic"
		GameTypes.Rarity.LEGENDARY:
			return "bulk_legendary"
	return "bulk_common"
