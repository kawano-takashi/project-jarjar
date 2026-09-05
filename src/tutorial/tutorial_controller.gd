class_name TutorialController
extends RefCounted


signal completed()

const MOVE_REQUIRED_SECONDS: float = 1.0
const CONTEXT_MESSAGE_SECONDS: float = 4.5
const MOVE_MESSAGE: String = "WASD / 矢印 / 左スティックで移動。攻撃は自動です"
const MESSAGE_BY_CONTEXT: Dictionary[StringName, String] = {
	&"xp_pickup": "小さな図形はXPです。近づくと吸い寄せられます",
	&"level_up": "レベルアップで武器・パッシブを選びます",
	&"chest_pickup": "エリートは宝箱を落とします",
	&"evolution": "武器が最大Lv、触媒がLv1以上なら宝箱から進化。触媒は最大Lv不要・進化後も消費されません",
	&"stop_pickup": "停止場は通常敵とエリートを停止し、ボスを減速します",
	&"boss_spawn": "最後のボスを倒せばクリアです",
}

var enabled: bool = false
var move_elapsed: float = 0.0
var move_completed: bool = false
var message_remaining: float = 0.0
var active_message: String = ""

var _messages: Dictionary[StringName, String] = {}

var _shown_contexts: Dictionary[StringName, bool] = {}


func begin_run(tutorial_completed: bool, catalog: DefinitionCatalog) -> void:
	_messages = MESSAGE_BY_CONTEXT.duplicate()
	var progression: ProgressionBalanceDefinition = catalog.manifest().progression
	_messages[&"level_up"] = "レベルアップは最大%d択。武器%d枠・パッシブ%d枠を組み立てます" % [progression.level_offer_count, progression.weapon_slot_count, progression.passive_slot_count]
	_messages[&"stop_pickup"] = "停止場は通常敵とエリートを%s秒停止し、ボスを減速します" % String.num(float(catalog.manifest().arena.node_stop_ticks) / float(RunState.TICKS_PER_SECOND), 2)
	_messages[&"boss_spawn"] = "%02d:%02d。最後のボスを倒せばクリアです" % [floori(float(catalog.boss_start_tick) / 3600.0), floori(float(catalog.boss_start_tick) / 60.0) % 60]
	enabled = not tutorial_completed
	move_elapsed = 0.0
	move_completed = not enabled
	message_remaining = 0.0
	active_message = MOVE_MESSAGE if enabled else ""
	_shown_contexts.clear()


func advance_movement(actual_movement: Vector2, delta: float) -> bool:
	if not enabled or move_completed or delta <= 0.0:
		return false
	if actual_movement.length_squared() <= 0.000001:
		return false
	move_elapsed = minf(MOVE_REQUIRED_SECONDS, move_elapsed + delta)
	if move_elapsed < MOVE_REQUIRED_SECONDS:
		return false
	move_completed = true
	active_message = ""
	message_remaining = 0.0
	completed.emit()
	return true


func advance(delta: float) -> void:
	if not enabled or not move_completed or message_remaining <= 0.0 or delta <= 0.0:
		return
	message_remaining = maxf(0.0, message_remaining - delta)
	if message_remaining <= 0.0:
		active_message = ""


func notify_context(context_id: StringName) -> bool:
	if (
		not enabled
		or not move_completed
		or _shown_contexts.has(context_id)
		or not _messages.has(context_id)
	):
		return false
	_shown_contexts[context_id] = true
	active_message = _messages[context_id]
	message_remaining = CONTEXT_MESSAGE_SECONDS
	return true


func current_message() -> String:
	return active_message if enabled else ""


func debug_state() -> Dictionary:
	var shown: Array[StringName] = []
	for context_id: StringName in _shown_contexts:
		shown.append(context_id)
	shown.sort()
	return {
		"enabled": enabled,
		"move_elapsed": move_elapsed,
		"move_completed": move_completed,
		"message": current_message(),
		"message_remaining": message_remaining,
		"shown_contexts": shown,
	}
