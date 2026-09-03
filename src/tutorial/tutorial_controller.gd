class_name TutorialController
extends RefCounted


signal revision_completed(revision: int)

const REVISION: int = 4
const MOVE_REQUIRED_SECONDS: float = 1.0
const CONTEXT_MESSAGE_SECONDS: float = 4.5
const MOVE_MESSAGE: String = "WASD / 矢印 / 左スティックで移動。攻撃は自動です"
const MESSAGE_BY_CONTEXT: Dictionary[StringName, String] = {
	&"xp_pickup": "小さな図形はXPです。近づくと吸い寄せられます",
	&"level_up": "レベルアップは3択。武器5枠・パッシブ5枠を組み立てます",
	&"chest_pickup": "2・4・6・8分のエリートは宝箱を落とします",
	&"evolution": "武器Lv8＋触媒Lv1以上で宝箱から進化。触媒は最大Lv不要・進化後も消費されません",
	&"stop_pickup": "停止場は通常敵とエリートを5秒停止し、ボスを減速します",
	&"boss_spawn": "10:00。最後のボスを倒せばクリアです",
}

var enabled: bool = false
var move_elapsed: float = 0.0
var move_completed: bool = false
var message_remaining: float = 0.0
var active_message: String = ""
var revision_marked: bool = false

var _shown_contexts: Dictionary[StringName, bool] = {}


func begin_run(stored_revision: int) -> void:
	enabled = stored_revision < REVISION
	move_elapsed = 0.0
	move_completed = not enabled
	message_remaining = 0.0
	active_message = MOVE_MESSAGE if enabled else ""
	revision_marked = not enabled
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
	if not revision_marked:
		revision_marked = true
		revision_completed.emit(REVISION)
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
		or not MESSAGE_BY_CONTEXT.has(context_id)
	):
		return false
	_shown_contexts[context_id] = true
	active_message = MESSAGE_BY_CONTEXT[context_id]
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
		"revision": REVISION,
		"enabled": enabled,
		"move_elapsed": move_elapsed,
		"move_completed": move_completed,
		"message": current_message(),
		"message_remaining": message_remaining,
		"revision_marked": revision_marked,
		"shown_contexts": shown,
	}
