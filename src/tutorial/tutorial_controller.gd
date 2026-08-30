class_name TutorialController
extends RefCounted


const MOVE_REQUIRED_SECONDS: float = 1.0
const PICKUP_MESSAGE_SECONDS: float = 2.0
const MOVE_MESSAGE: String = "WASD / 矢印 / 左スティックで移動"
const PICKUP_MESSAGE: String = "宝箱は自動回収されます"
const REWARD_MESSAGE: String = "報酬は獲得時に確定しています"
const INVENTORY_MESSAGE: String = (
	"1. 3本の武器は、それぞれ独立してすべて自動攻撃\n"
	+ "2. 3個のお守りは、武器とプレイヤー全体を強化\n"
	+ "3. 同じレアリティのアイテム3個で、上位1個へ合成"
)

var enabled: bool = false
var move_elapsed: float = 0.0
var move_completed: bool = false
var pickup_shown: bool = false
var pickup_remaining: float = 0.0
var reward_shown: bool = false
var inventory_shown: bool = false
var noncombat_message: String = ""


func begin_run(tutorial_seen: bool) -> void:
	enabled = not tutorial_seen
	move_elapsed = 0.0
	move_completed = not enabled
	pickup_shown = false
	pickup_remaining = 0.0
	reward_shown = false
	inventory_shown = false
	noncombat_message = ""


func should_gate_combat(wave_number: int) -> bool:
	return enabled and wave_number == 1 and not move_completed


func advance_move(actual_movement: Vector2, delta: float) -> bool:
	if move_completed or not enabled or delta <= 0.0:
		return false
	if actual_movement.length_squared() <= 0.000000000001:
		return false
	move_elapsed = TimerMath.advance_clamped(
		move_elapsed,
		MOVE_REQUIRED_SECONDS,
		delta,
	)
	if not TimerMath.is_ready(move_elapsed, MOVE_REQUIRED_SECONDS):
		return false
	move_completed = true
	return true


func advance_combat(delta: float) -> void:
	if pickup_remaining <= 0.0:
		return
	pickup_remaining = TimerMath.countdown(pickup_remaining, maxf(0.0, delta))


func notify_first_pickup() -> bool:
	if not enabled or pickup_shown:
		return false
	pickup_shown = true
	pickup_remaining = PICKUP_MESSAGE_SECONDS
	return true


func enter_reward(wave_number: int) -> bool:
	if not enabled or wave_number != 1 or reward_shown:
		noncombat_message = ""
		return false
	reward_shown = true
	noncombat_message = REWARD_MESSAGE
	return true


func enter_inventory(wave_number: int) -> bool:
	if not enabled or wave_number != 1 or inventory_shown:
		noncombat_message = ""
		return false
	inventory_shown = true
	noncombat_message = INVENTORY_MESSAGE
	return true


func dismiss_noncombat() -> bool:
	if noncombat_message.is_empty():
		return false
	noncombat_message = ""
	return true


func leave_w1_inventory(wave_number: int) -> bool:
	if not enabled or wave_number != 1:
		return false
	enabled = false
	noncombat_message = ""
	pickup_remaining = 0.0
	return true


func current_message(in_combat: bool, wave_number: int = 0) -> String:
	if in_combat:
		if should_gate_combat(wave_number):
			return MOVE_MESSAGE
		if pickup_remaining > 0.0:
			return PICKUP_MESSAGE
		return ""
	return noncombat_message


func debug_state() -> Dictionary:
	return {
		"enabled": enabled,
		"move_elapsed": move_elapsed,
		"move_completed": move_completed,
		"pickup_shown": pickup_shown,
		"pickup_remaining": pickup_remaining,
		"reward_shown": reward_shown,
		"inventory_shown": inventory_shown,
		"noncombat_message": noncombat_message,
	}
