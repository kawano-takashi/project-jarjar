class_name CombatHud
extends Control


@onready var _wave_value: Label = %WaveValue
@onready var _time_value: Label = %TimeValue
@onready var _kills_value: Label = %KillsValue
@onready var _hp_value: Label = %HpValue
@onready var _weapon_value: Label = %WeaponValue
@onready var _chests_value: Label = %ChestsValue
@onready var _bonus_time: Label = %BonusTime
@onready var _boss_requirement: Label = %BossRequirement
@onready var _boss_spawn_status: Label = %BossSpawnStatus
@onready var _debug_overlay: PanelContainer = %DebugOverlay
@onready var _debug_active: Label = %DebugActive
@onready var _debug_overflow: Label = %DebugOverflow
@onready var _evidence_caption: Label = %EvidenceCaption


func _ready() -> void:
	_debug_overlay.visible = OS.is_debug_build()


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
	var weapon_name := str(values.get("weapon_name", "木の棒"))
	var wave_chests := int(values.get("wave_chests", 0))
	var wave_cleared := bool(values.get("wave_cleared", false))
	var boss_defeated := bool(values.get("boss_defeated", false))
	var non_boss_spawned := int(values.get("non_boss_spawned", 0))
	var evidence_caption := str(values.get("evidence_caption", ""))

	_wave_value.text = "WAVE %d" % wave_number
	_time_value.text = "残り %d 秒" % int(ceil(time_remaining))
	_kills_value.text = "撃破 %d / %d" % [wave_kills, kill_quota]
	_hp_value.text = "HP %s / %s" % [_format_health(current_hp), _format_health(max_hp)]
	_weapon_value.text = "主武器  %s" % weapon_name
	_chests_value.text = "箱  %d" % wave_chests
	_bonus_time.visible = wave_cleared
	_update_boss_gate(wave_number, boss_defeated, non_boss_spawned)
	_update_debug_overlay(values, snapshot)
	_evidence_caption.text = evidence_caption
	_evidence_caption.visible = not evidence_caption.is_empty()


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
