class_name RunSummaryScreen
extends Control


signal retry_same_seed_requested
signal retry_new_seed_requested
signal title_requested
signal exit_requested

const SCORE_ROWS: Array[Dictionary] = [
	{"key": &"normal_kills", "label": "通常撃破"},
	{"key": &"post_quota_bonus", "label": "ノルマ後撃破"},
	{"key": &"elite_kills", "label": "エリート撃破"},
	{"key": &"boss_kills", "label": "ボス撃破"},
	{"key": &"wave_clears", "label": "ウェーブクリア"},
	{"key": &"run_clear", "label": "ラン完走"},
	{"key": &"equipment", "label": "保持装備"},
	{"key": &"unique_tags", "label": "ユニーク"},
	{"key": &"skill_levels", "label": "スキルLv"},
	{"key": &"wild_materials", "label": "ワイルド素材"},
]
const SLOT_LABELS: Array[String] = [
	"主武器",
	"副武器",
	"頭",
	"胴",
	"手",
	"足",
]

@onready var _heading: Label = %SummaryHeading
@onready var _outcome: Label = %SummaryOutcome
@onready var _run_text: Label = %SummaryRunText
@onready var _build_text: Label = %SummaryBuildText
@onready var _score_text: Label = %SummaryScoreText
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


func initialize(state: RunState, _catalog: DefinitionCatalog = null) -> void:
	_pending_state = state
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
	var score: Dictionary = _pending_state.score_breakdown if _pending_state != null else {}
	return {
		"screen": _screen_prefix(),
		"focus_id": _focus_controller.current_focus_id(get_viewport()),
		"focus_order": focus_order(),
		"settings_open": _settings_overlay.visible,
		"modal_stack_size": _modal_focus.stack_size(),
		"run_seed": _pending_state.run_seed if _pending_state != null else 0,
		"combat_score": int(score.get(&"combat_score", 0)),
		"final_build_score": int(score.get(&"final_build_score", 0)),
		"total": int(score.get(&"total", 0)),
		"run_text": _run_text.text,
		"build_text": _build_text.text,
		"score_text": _score_text.text,
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
	_outcome.text = (
		"WAVE %d で敗北" % (_pending_state.wave_number if _pending_state != null else 0)
		if _is_failed_screen()
		else "8 WAVE COMPLETE"
	)
	if _pending_state == null:
		_run_text.text = "ラン情報を読み込み中"
		_build_text.text = "装備情報を読み込み中"
		_score_text.text = "スコアを読み込み中"
		return
	_run_text.text = _run_summary_text(_pending_state)
	_build_text.text = _build_summary_text(_pending_state)
	_score_text.text = _score_summary_text(_pending_state.score_breakdown)


func _run_summary_text(state: RunState) -> String:
	var lines := PackedStringArray([
		"SEED  %d" % state.run_seed,
		"クリアウェーブ  %d" % state.cleared_waves,
	])
	if _is_failed_screen():
		lines.append("失敗ウェーブ  %d" % state.wave_number)
	lines.append("総撃破数  %d" % state.total_kills)
	lines.append("ノルマ後撃破数  %d" % state.post_quota_kills)
	lines.append("獲得箱数  %d" % state.total_chests)
	lines.append("合成回数  %d" % state.fusion_count)
	lines.append("最高 DPS  %.1f" % state.peak_dps)
	return "\n".join(lines)


func _build_summary_text(state: RunState) -> String:
	var lines := PackedStringArray(["最終装備"])
	for slot_index: int in range(GameTypes.EquipmentSlot.size()):
		var item: ItemInstance = state.equipped.get(slot_index) as ItemInstance
		lines.append("%s: %s" % [
			SLOT_LABELS[slot_index],
			_item_label(item),
		])
	lines.append("")
	lines.append("装着スキル")
	var equipped_skills: Array[StringName] = [&"", &""]
	for value: Variant in state.skill_library.values():
		var skill: SkillState = value as SkillState
		if skill != null and skill.equipped_slot >= 0 and skill.equipped_slot < 2:
			equipped_skills[skill.equipped_slot] = skill.skill_id
	for slot_index: int in range(equipped_skills.size()):
		var skill_id: StringName = equipped_skills[slot_index]
		var skill: SkillState = state.skill_library.get(skill_id) as SkillState
		lines.append("枠%d: %s" % [
			slot_index + 1,
			"— 空き —" if skill == null else "%s Lv%d" % [_skill_name(skill_id), skill.level],
		])
	return "\n".join(lines)


func _score_summary_text(score: Dictionary) -> String:
	var lines := PackedStringArray(["スコア内訳"])
	for row: Dictionary in SCORE_ROWS:
		lines.append("%-14s %6d" % [row["label"], int(score.get(row["key"], 0))])
	var combat_score: int = int(score.get(&"combat_score", 0))
	var final_build_score: int = int(score.get(&"final_build_score", 0))
	var displayed_total: int = int(score.get(&"total", combat_score + final_build_score))
	lines.append("")
	lines.append("戦闘由来小計  %d" % combat_score)
	lines.append("最終ビルド小計  %d" % final_build_score)
	lines.append("合計  %d" % displayed_total)
	lines.append("照合  %d + %d = %d" % [combat_score, final_build_score, displayed_total])
	return "\n".join(lines)


func _item_label(item: ItemInstance) -> String:
	if item == null:
		return "— 空き —"
	return "%s  %s" % [_rarity_label(item.rarity), item.display_name]


func _rarity_label(rarity: GameTypes.Rarity) -> String:
	match rarity:
		GameTypes.Rarity.RARE:
			return "RARE"
		GameTypes.Rarity.EPIC:
			return "EPIC"
		GameTypes.Rarity.LEGENDARY:
			return "LEGENDARY"
		GameTypes.Rarity.UNIQUE:
			return "★ UNIQUE"
	return "COMMON"


func _skill_name(skill_id: StringName) -> String:
	match skill_id:
		&"starfall":
			return "星落とし"
		&"thousand_blades":
			return "千刃陣"
		&"soul_chain":
			return "魂の連鎖"
		&"bell_of_retribution":
			return "報復の鐘"
	return String(skill_id)


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
