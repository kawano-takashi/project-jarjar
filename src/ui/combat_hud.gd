class_name CombatHud
extends Control


const MIN_FEEDBACK_DURATION_SECONDS: float = 0.40
const FLASH_PULSE_DURATION_SECONDS: float = 0.50
const REDUCED_FLASH_OUTLINE_SIZE: int = 5
const InventoryItemVisualsScript := preload("res://src/ui/inventory_item_visuals.gd")

@onready var _wave_value: Label = %WaveValue
@onready var _time_value: Label = %TimeValue
@onready var _kills_value: Label = %KillsValue
@onready var _hp_value: Label = %HpValue
@onready var _chests_value: Label = %ChestsValue
@onready var _weapon_icons: Array[TextureRect] = [
	%WeaponSlot0Icon,
	%WeaponSlot1Icon,
	%WeaponSlot2Icon,
]
@onready var _weapon_values: Array[Label] = [
	%WeaponSlot0Value,
	%WeaponSlot1Value,
	%WeaponSlot2Value,
]
@onready var _bonus_time: Label = %BonusTime
@onready var _boss_requirement: Label = %BossRequirement
@onready var _boss_spawn_status: Label = %BossSpawnStatus
@onready var _debug_overlay: PanelContainer = %DebugOverlay
@onready var _debug_active: Label = %DebugActive
@onready var _debug_overflow: Label = %DebugOverflow
@onready var _feedback_label: Label = %FeedbackLabel

var _feedback_remaining: float = 0.0
var _feedback_duration: float = 0.0
var _feedback_elapsed: float = 0.0
var _feedback_reduce_motion: bool = false
var _feedback_reduce_flashes: bool = false
var _feedback_pulse_start_count: int = 0
var _feedback_merged_event_count: int = 0


func _ready() -> void:
	_debug_overlay.visible = OS.is_debug_build()
	set_process(false)


func _process(delta: float) -> void:
	var safe_delta: float = maxf(0.0, delta)
	_feedback_remaining = maxf(0.0, _feedback_remaining - safe_delta)
	_feedback_elapsed += safe_delta
	if _feedback_remaining <= 0.0:
		_feedback_label.visible = false
		set_process(false)
		return
	var progress: float = clampf(_feedback_elapsed / _feedback_duration, 0.0, 1.0)
	var flash_progress: float = clampf(
		_feedback_elapsed / FLASH_PULSE_DURATION_SECONDS,
		0.0,
		1.0,
	)
	_feedback_label.modulate.a = (
		1.0
		if _feedback_reduce_flashes
		else 0.72 + 0.28 * sin(flash_progress * PI)
	)
	_feedback_label.scale = (
		Vector2.ONE
		if _feedback_reduce_motion
		else Vector2.ONE * (1.0 + 0.05 * sin(progress * PI))
	)


func present_damage(reduce_motion: bool, reduce_flashes: bool) -> void:
	_show_feedback(
		"DAMAGE",
		Color(1.0, 0.52, 0.42),
		MIN_FEEDBACK_DURATION_SECONDS,
		reduce_motion,
		reduce_flashes,
	)


func present_pickup(count: int, reduce_motion: bool, reduce_flashes: bool) -> void:
	_show_feedback(
		"箱を自動回収 +%d" % maxi(1, count),
		Color(1.0, 0.78, 0.32),
		0.50,
		reduce_motion,
		reduce_flashes,
	)


func present_wave_clear(reduce_motion: bool, reduce_flashes: bool) -> void:
	_show_feedback(
		"WAVE CLEAR",
		Color(0.46, 0.95, 0.72),
		0.80,
		reduce_motion,
		reduce_flashes,
	)


func test_tick_feedback(delta: float) -> void:
	_process(delta)


func debug_feedback_state() -> Dictionary:
	return {
		"visible": _feedback_label.visible,
		"text": _feedback_label.text,
		"scale": _feedback_label.scale,
		"alpha": _feedback_label.modulate.a,
		"outline_size": _feedback_label.get_theme_constant("outline_size"),
		"reduce_motion": _feedback_reduce_motion,
		"reduce_flashes": _feedback_reduce_flashes,
		"pulse_start_count": _feedback_pulse_start_count,
		"merged_event_count": _feedback_merged_event_count,
		"elapsed": _feedback_elapsed,
		"remaining": _feedback_remaining,
	}


func update_from_snapshot(snapshot: CombatSnapshot) -> void:
	if snapshot == null:
		return
	var values: Dictionary = snapshot.hud_values
	var wave_number := int(values.get("wave_number", 1))
	var time_remaining := maxf(0.0, float(values.get("time_remaining", 0.0)))
	var wave_kills := int(values.get("wave_kills", 0))
	var kill_quota := int(values.get("kill_quota", 0))
	var current_hp := maxf(0.0, float(values.get("current_hp", 0.0)))
	var max_hp := maxf(0.0, float(values.get("max_hp", 0.0)))
	var wave_chests := int(values.get("wave_chests", 0))
	var wave_cleared := bool(values.get("wave_cleared", false))
	var boss_defeated := bool(values.get("boss_defeated", false))
	var non_boss_spawned := int(values.get("non_boss_spawned", 0))

	_wave_value.text = "WAVE %d" % wave_number
	_time_value.text = "残り %d 秒" % int(ceil(time_remaining))
	_kills_value.text = "撃破 %d / %d" % [wave_kills, kill_quota]
	_hp_value.text = "HP %s / %s" % [_format_health(current_hp), _format_health(max_hp)]
	_chests_value.text = "箱  %d" % wave_chests
	var weapon_slots: Array = values.get("weapon_slots", []) as Array
	for index: int in range(_weapon_values.size()):
		_update_weapon_slot(weapon_slots, index)
	_bonus_time.visible = wave_cleared
	_update_boss_gate(wave_number, boss_defeated, non_boss_spawned)
	_update_debug_overlay(values, snapshot)


func _update_weapon_slot(weapon_slots: Array, slot_index: int) -> void:
	var icon: TextureRect = _weapon_icons[slot_index]
	var label: Label = _weapon_values[slot_index]
	if slot_index < 0 or slot_index >= weapon_slots.size():
		icon.texture = null
		label.text = "空き"
		return
	var slot: Dictionary = weapon_slots[slot_index] as Dictionary
	var weapon_type: int = int(slot.get("weapon_type", GameTypes.WeaponType.NONE))
	var rarity: int = int(slot.get("rarity", -1))
	if weapon_type == GameTypes.WeaponType.NONE or rarity < 0:
		icon.texture = null
		label.text = "空き"
		return
	icon.texture = InventoryItemVisualsScript.icon_for_weapon_type(weapon_type)
	icon.modulate = UiPolish.rarity_color(rarity)
	label.text = _rarity_label(rarity)
	label.add_theme_color_override(&"font_color", UiPolish.rarity_color(rarity))


func _rarity_label(rarity: int) -> String:
	match rarity:
		GameTypes.Rarity.RARE:
			return "RARE"
		GameTypes.Rarity.EPIC:
			return "EPIC"
		GameTypes.Rarity.LEGENDARY:
			return "LEGENDARY"
	return "COMMON"


func _update_boss_gate(
	wave_number: int,
	boss_defeated: bool,
	non_boss_spawned: int
) -> void:
	if wave_number != 8:
		_boss_requirement.visible = false
		_boss_spawn_status.visible = false
		return
	_boss_requirement.visible = true
	if boss_defeated:
		_boss_requirement.text = "ボス撃破済み／通常敵スポーン中"
		_boss_spawn_status.visible = false
		return
	_boss_requirement.text = "300到達にはボス撃破が必要"
	_boss_spawn_status.text = "通常敵スポーン停止中"
	_boss_spawn_status.visible = non_boss_spawned >= 299


func _update_debug_overlay(values: Dictionary, snapshot: CombatSnapshot) -> void:
	if not OS.is_debug_build():
		_debug_overlay.visible = false
		return
	_debug_overlay.visible = true
	var active_enemy := int(values.get("active_enemy", snapshot.active_enemy_count))
	var active_projectile := int(
		values.get("active_projectile", snapshot.active_projectile_count)
	)
	var active_vfx := int(values.get("active_vfx", snapshot.active_vfx_count))
	var enemy_overflow := int(values.get("enemy_pool_overflow", 0))
	var projectile_overflow := int(values.get("projectile_pool_overflow", 0))
	var vfx_overflow := int(values.get("vfx_pool_overflow", 0))
	_debug_active.text = (
		"ACTIVE  ENEMY %d  PROJECTILE %d  VFX %d"
		% [active_enemy, active_projectile, active_vfx]
	)
	_debug_overflow.text = (
		"POOL OVERFLOW  ENEMY %d  PROJECTILE %d  VFX %d"
		% [enemy_overflow, projectile_overflow, vfx_overflow]
	)


func _format_health(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return "%.1f" % value


func _show_feedback(
	text: String,
	color: Color,
	duration: float,
	reduce_motion: bool,
	reduce_flashes: bool,
) -> void:
	var was_visible: bool = _feedback_label.visible
	_feedback_label.text = text
	_feedback_label.add_theme_color_override("font_color", color)
	_feedback_label.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.04, 1.0))
	_feedback_label.add_theme_constant_override(
		"outline_size",
		REDUCED_FLASH_OUTLINE_SIZE if reduce_flashes else 2,
	)
	if was_visible:
		_feedback_merged_event_count += 1
	else:
		_feedback_elapsed = 0.0
		_feedback_pulse_start_count += 1
		_feedback_label.modulate = Color.WHITE
		_feedback_label.scale = Vector2.ONE
	_feedback_label.visible = true
	var safe_duration: float = maxf(MIN_FEEDBACK_DURATION_SECONDS, duration)
	if was_visible:
		_feedback_remaining = maxf(_feedback_remaining, safe_duration)
		_feedback_duration = maxf(_feedback_duration, safe_duration)
	else:
		_feedback_remaining = safe_duration
		_feedback_duration = safe_duration
	_feedback_reduce_motion = reduce_motion
	_feedback_reduce_flashes = reduce_flashes
	if not was_visible:
		_feedback_label.modulate.a = 1.0 if reduce_flashes else 0.72
	set_process(true)
