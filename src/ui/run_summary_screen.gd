class_name RunSummaryScreen
extends Control


signal retry_same_seed_requested
signal retry_new_seed_requested
signal title_requested
signal exit_requested

@onready var _heading: Label = %SummaryHeading
@onready var _outcome: Label = %SummaryOutcome
@onready var _run_text: Label = %SummaryRunText
@onready var _build_text: Label = %SummaryBuildText
@onready var _damage_text: Label = %SummaryDamageText
@onready var _retry_same: Button = %RetrySameSeed
@onready var _retry_new: Button = %RetryNewSeed
@onready var _title_button: Button = %SummaryTitleButton
@onready var _exit_button: Button = %SummaryExitButton
@onready var _settings_button: Button = %SummarySettingsButton
@onready var _content_root: Control = $Margin
@onready var _settings_overlay: SettingsOverlay = %SettingsOverlay

var _focus_controller := FocusController.new()
var _modal_focus := ModalFocusCoordinator.new()
var _pending_state: RunState = null
var _catalog: DefinitionCatalog = null


func _ready() -> void:
	_retry_same.pressed.connect(func() -> void: retry_same_seed_requested.emit())
	_retry_new.pressed.connect(func() -> void: retry_new_seed_requested.emit())
	_title_button.pressed.connect(func() -> void: title_requested.emit())
	_exit_button.pressed.connect(func() -> void: exit_requested.emit())
	_settings_button.pressed.connect(_open_settings)
	_settings_overlay.closed.connect(_on_settings_closed)
	_modal_focus.configure(get_viewport(), [_content_root])
	_configure_focus()
	_render()
	_focus_controller.focus_initial_deferred()


func initialize(state: RunState, catalog: DefinitionCatalog = null) -> void:
	_pending_state = state
	_catalog = catalog
	if is_node_ready():
		_render()
		_configure_focus()
		_focus_controller.focus_initial_deferred()


func refresh_from_state() -> void:
	_render()


func focus_order() -> PackedStringArray:
	return PackedStringArray([
		_focus_id("retry_same_seed"),
		_focus_id("retry_new_seed"),
		_focus_id("title"),
		_focus_id("exit"),
		_focus_id("settings"),
	])


func initial_focus_control() -> Control:
	return _retry_same


func focus_control(focus_id: String) -> Control:
	return _focus_controller.control_for_id(focus_id)


func neighbor_specification(focus_id: String) -> Dictionary:
	return _focus_controller.neighbor_specification(focus_id)


func debug_state() -> Dictionary:
	return {
		"screen": _screen_prefix(),
		"focus_id": _focus_controller.current_focus_id(get_viewport()),
		"focus_order": focus_order(),
		"settings_open": _settings_overlay.visible,
		"modal_stack_size": _modal_focus.stack_size(),
		"run_seed": _pending_state.run_seed if _pending_state != null else 0,
		"outcome": _outcome.text,
		"run_text": _run_text.text,
		"build_text": _build_text.text,
		"damage_text": _damage_text.text,
	}


func test_focus(focus_id: String) -> bool:
	return _focus_controller.grab_focus_id(focus_id)


func test_direction(direction: StringName) -> bool:
	return _focus_controller.move(get_viewport(), direction)


func test_accept() -> void:
	var focus_id: String = _focus_controller.current_focus_id(get_viewport())
	if focus_id == _focus_id("retry_same_seed"):
		retry_same_seed_requested.emit()
	elif focus_id == _focus_id("retry_new_seed"):
		retry_new_seed_requested.emit()
	elif focus_id == _focus_id("title"):
		title_requested.emit()
	elif focus_id == _focus_id("exit"):
		exit_requested.emit()
	elif focus_id == _focus_id("settings"):
		_open_settings()


func _input(event: InputEvent) -> void:
	if _modal_focus.has_active_modal():
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
	if direction.is_empty():
		if FocusController.is_left_stick_focus_motion(event):
			get_viewport().set_input_as_handled()
		return
	_focus_controller.move(get_viewport(), direction)
	get_viewport().set_input_as_handled()


func _screen_prefix() -> String:
	return "summary"


func _is_failed_screen() -> bool:
	return false


func _configure_focus() -> void:
	var ids: PackedStringArray = focus_order()
	var buttons: Array[Button] = [
		_retry_same,
		_retry_new,
		_title_button,
		_exit_button,
		_settings_button,
	]
	var controls: Dictionary = {}
	var graph: Dictionary = {}
	for index: int in range(ids.size()):
		var focus_id: String = ids[index]
		controls[focus_id] = buttons[index]
		graph[focus_id] = {
			FocusController.DIRECTION_TOP: ids[posmod(index - 1, ids.size())],
			FocusController.DIRECTION_BOTTOM: ids[(index + 1) % ids.size()],
			FocusController.DIRECTION_LEFT: focus_id,
			FocusController.DIRECTION_RIGHT: focus_id,
		}
	_focus_controller.configure_graph(controls, graph, ids[0], ids)


func _render() -> void:
	if not is_node_ready():
		return
	_heading.text = "RUN FAILED" if _is_failed_screen() else "RUN COMPLETE"
	if _pending_state == null:
		_outcome.text = "集計中"
		_run_text.text = "ラン情報を読み込み中"
		_build_text.text = "ビルド情報を読み込み中"
		_damage_text.text = "ダメージ情報を読み込み中"
		return
	var elapsed_seconds: int = maxi(
		0,
		floori(float(_pending_state.combat_tick) / 60.0),
	)
	_outcome.text = "BOSS RESULT: %s" % _boss_result_text(_pending_state)
	_run_text.text = _run_summary_text(_pending_state, elapsed_seconds)
	_build_text.text = _build_summary_text(_pending_state)
	_damage_text.text = _damage_summary_text(_pending_state)


func _run_summary_text(state: RunState, elapsed_seconds: int) -> String:
	return "\n".join(PackedStringArray([
		"SEED  %d" % state.run_seed,
		"生存時間  %s" % _format_time(elapsed_seconds),
		"最終LEVEL  %d" % state.level,
		"総撃破数  %d" % state.total_kills,
		"エリート撃破  %d / 4" % state.elite_kills,
		"進化数  %d / 4" % state.evolution_count,
		"ボス結果  %s" % _boss_result_text(state),
	]))


func _boss_result_text(state: RunState) -> String:
	if state.boss_defeated:
		return "DEFEATED"
	if state.boss_spawned:
		return "PLAYER DEFEATED"
	return "NOT REACHED"


func _build_summary_text(state: RunState) -> String:
	var lines := PackedStringArray(["最終ビルド", "", "WEAPONS"])
	_append_build_entries(lines, state.weapons, 5, true)
	lines.append("")
	lines.append("PASSIVES")
	_append_build_entries(lines, state.passives, 5, false)
	return "\n".join(lines)


func _append_build_entries(
	lines: PackedStringArray,
	entries: Array,
	capacity: int,
	is_weapon: bool,
) -> void:
	for index: int in range(capacity):
		if index >= entries.size():
			lines.append("%d. —" % (index + 1))
			continue
		var entry: Variant = entries[index]
		var content_id := StringName(str(_read_property(
			entry,
			&"weapon_id" if is_weapon else &"passive_id",
			&"unknown",
		)))
		var display_name: String = _content_display_name(content_id, is_weapon)
		var level: int = int(_read_property(entry, &"level", 1))
		var evolved: bool = bool(_read_property(entry, &"evolved", false))
		lines.append("%d. %s  %s" % [
			index + 1,
			display_name,
			"EVOLVED" if evolved else "Lv %d" % level,
		])


func _damage_summary_text(state: RunState) -> String:
	var damage_by_lineage: Dictionary = state.weapon_damage_by_lineage
	var lineage_ids := PackedStringArray()
	for lineage_id: Variant in damage_by_lineage:
		lineage_ids.append(str(lineage_id))
	lineage_ids.sort()
	var total_damage: float = 0.0
	var lines := PackedStringArray(["DAMAGE BY LINEAGE", "進化前後は同系統へ合算", ""])
	for lineage_id: String in lineage_ids:
		var damage: float = float(damage_by_lineage.get(StringName(lineage_id), damage_by_lineage.get(lineage_id, 0.0)))
		total_damage += damage
		lines.append("%-20s %10d" % [
			_lineage_display_name(state, StringName(lineage_id)),
			roundi(damage),
		])
	lines.append("")
	lines.append("TOTAL  %d" % roundi(total_damage))
	return "\n".join(lines)


func _content_display_name(content_id: StringName, is_weapon: bool) -> String:
	if _catalog == null:
		return String(content_id)
	if is_weapon:
		var weapon_definition: WeaponDefinition = _catalog.weapon(content_id)
		return (
			weapon_definition.display_name
			if weapon_definition != null
			else String(content_id)
		)
	var passive_definition: PassiveDefinition = _catalog.passive(content_id)
	return (
		passive_definition.display_name
		if passive_definition != null
		else String(content_id)
	)


func _lineage_display_name(state: RunState, lineage_id: StringName) -> String:
	var final_weapon_id: StringName = lineage_id
	var runtime: RunWeapon = state.weapon_for_lineage(lineage_id)
	if runtime != null:
		final_weapon_id = runtime.weapon_id
	return _content_display_name(final_weapon_id, true)


func _format_time(total_seconds: int) -> String:
	var minutes: int = floori(float(total_seconds) / 60.0)
	return "%02d:%02d" % [minutes, total_seconds % 60]


func _read_property(value: Variant, property_name: StringName, fallback: Variant) -> Variant:
	if value is Dictionary:
		return (value as Dictionary).get(property_name, fallback)
	if value is Object:
		var object := value as Object
		for property: Dictionary in object.get_property_list():
			if StringName(property.get("name", "")) == property_name:
				return object.get(property_name)
	return fallback


func _open_settings() -> void:
	if _modal_focus.has_active_modal():
		return
	if not _modal_focus.push(_settings_overlay, _retry_same):
		return
	_settings_overlay.open_overlay()


func _on_settings_closed() -> void:
	_configure_focus()
	_modal_focus.pop(_settings_overlay, null, _retry_same)


func _focus_id(suffix: String) -> String:
	return "%s_%s" % [_screen_prefix(), suffix]
