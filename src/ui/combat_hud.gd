class_name CombatHud
extends Control


const FEEDBACK_SECONDS: float = 0.45

@onready var _time_value: Label = %TimeValue
@onready var _level_kills: Label = %LevelKills
@onready var _hp_value: Label = %HpValue
@onready var _hp_bar: ProgressBar = %HpBar
@onready var _xp_value: Label = %XpValue
@onready var _xp_bar: ProgressBar = %XpBar
@onready var _boss_panel: PanelContainer = %BossPanel
@onready var _boss_hp_value: Label = %BossHpValue
@onready var _boss_hp_bar: ProgressBar = %BossHpBar
@onready var _weapon_slots: Array[Label] = [
	%WeaponSlot0,
	%WeaponSlot1,
	%WeaponSlot2,
	%WeaponSlot3,
	%WeaponSlot4,
]
@onready var _passive_slots: Array[Label] = [
	%PassiveSlot0,
	%PassiveSlot1,
	%PassiveSlot2,
	%PassiveSlot3,
	%PassiveSlot4,
]
@onready var _feedback_label: Label = %FeedbackLabel
@onready var _debug_overlay: Label = %DebugOverlay

var _feedback_remaining: float = 0.0


func _ready() -> void:
	_feedback_label.visible = false
	update_from_values({})


func _process(delta: float) -> void:
	if _feedback_remaining <= 0.0 or delta <= 0.0:
		return
	_feedback_remaining = maxf(0.0, _feedback_remaining - delta)
	if _feedback_remaining <= 0.0:
		_feedback_label.visible = false


func update_from_snapshot(snapshot: Variant) -> void:
	var values: Variant = _read_property(snapshot, &"hud_values", {})
	if values is Dictionary:
		update_from_values(values as Dictionary)
	else:
		update_from_values({})


func update_from_values(values: Dictionary) -> void:
	var combat_tick: int = int(values.get("combat_tick", 0))
	var elapsed_seconds: float = float(values.get(
		"time_seconds",
		values.get("elapsed_seconds", float(combat_tick) / 60.0),
	))
	var boss_active: bool = bool(values.get("boss_active", values.get("boss_spawned", false)))
	_time_value.text = _format_time(elapsed_seconds, boss_active)

	var level: int = int(values.get("level", values.get("player_level", 1)))
	var total_kills: int = int(values.get("total_kills", values.get("kills", 0)))
	_level_kills.text = "LEVEL %d　撃破 %d" % [level, total_kills]

	var current_hp: float = maxf(0.0, float(values.get("current_hp", 100.0)))
	var max_hp: float = maxf(1.0, float(values.get("max_hp", 100.0)))
	_hp_bar.max_value = max_hp
	_hp_bar.value = minf(current_hp, max_hp)
	_hp_value.text = "HP %s / %s" % [_format_number(current_hp), _format_number(max_hp)]

	var build_maxed: bool = bool(values.get("build_maxed", false))
	if build_maxed:
		_xp_bar.max_value = 1.0
		_xp_bar.value = 1.0
		_xp_value.text = "XP MAX"
	else:
		var xp: int = maxi(0, int(values.get("xp_into_level", values.get("xp", 0))))
		var xp_for_next: int = maxi(1, int(values.get("xp_for_next_level", 1)))
		_xp_bar.max_value = xp_for_next
		_xp_bar.value = mini(xp, xp_for_next)
		_xp_value.text = "XP %d / %d" % [xp, xp_for_next]

	_update_build_slots(_weapon_slots, values.get("weapons", []), true)
	_update_build_slots(_passive_slots, values.get("passives", []), false)
	_update_boss(values, boss_active)
	_update_debug(values)


func present_damage(reduce_motion: bool = false, reduce_flashes: bool = false) -> void:
	_show_feedback("HIT", Color(1.0, 0.34, 0.28, 1.0), reduce_motion, reduce_flashes)


func present_pickup(count: int = 1, reduce_motion: bool = false, reduce_flashes: bool = false) -> void:
	var text: String = "+XP" if count <= 1 else "+XP ×%d" % count
	_show_feedback(text, Color(0.48, 0.9, 1.0, 1.0), reduce_motion, reduce_flashes)


func present_level_up(reduce_motion: bool = false, reduce_flashes: bool = false) -> void:
	_show_feedback("LEVEL UP", Color(1.0, 0.76, 0.28, 1.0), reduce_motion, reduce_flashes)


func present_evolution(reduce_motion: bool = false, reduce_flashes: bool = false) -> void:
	_show_feedback("EVOLUTION", Color(0.76, 0.54, 1.0, 1.0), reduce_motion, reduce_flashes)


func debug_state() -> Dictionary:
	var weapons := PackedStringArray()
	var passives := PackedStringArray()
	for label: Label in _weapon_slots:
		weapons.append(label.text)
	for label: Label in _passive_slots:
		passives.append(label.text)
	return {
		"time": _time_value.text,
		"level_kills": _level_kills.text,
		"hp": _hp_value.text,
		"xp": _xp_value.text,
		"boss_visible": _boss_panel.visible,
		"boss_hp": _boss_hp_value.text,
		"weapons": weapons,
		"passives": passives,
		"feedback_visible": _feedback_label.visible,
		"feedback": _feedback_label.text,
	}


func _update_build_slots(labels: Array[Label], value: Variant, weapon: bool) -> void:
	var entries: Array = []
	if value is Array:
		entries.assign(value)
	for index: int in range(labels.size()):
		var label: Label = labels[index]
		if index >= entries.size():
			label.text = "空き"
			label.modulate = Color(0.56, 0.62, 0.65, 1.0)
			continue
		var entry: Variant = entries[index]
		var display_name: String = str(_read_property(
			entry,
			&"display_name",
			_read_property(entry, &"definition_id", ""),
		))
		if display_name.is_empty():
			display_name = "武器" if weapon else "パッシブ"
		var level: int = maxi(1, int(_read_property(entry, &"level", 1)))
		var evolved: bool = bool(_read_property(entry, &"evolved", false))
		label.text = "%s\n%s" % [display_name, "EVOLVED" if evolved else "Lv %d" % level]
		label.modulate = Color(1.0, 0.8, 0.38, 1.0) if evolved else Color.WHITE


func _update_boss(values: Dictionary, boss_active: bool) -> void:
	_boss_panel.visible = boss_active
	if not boss_active:
		return
	var boss_hp: float = maxf(0.0, float(values.get("boss_hp", 0.0)))
	var boss_max_hp: float = maxf(1.0, float(values.get("boss_max_hp", 1.0)))
	_boss_hp_bar.max_value = boss_max_hp
	_boss_hp_bar.value = minf(boss_hp, boss_max_hp)
	_boss_hp_value.text = "FINAL BOSS %s / %s" % [
		_format_number(boss_hp),
		_format_number(boss_max_hp),
	]


func _update_debug(values: Dictionary) -> void:
	_debug_overlay.text = "E %d / P %d / FX %d / XP %d" % [
		int(values.get("active_enemy", 0)),
		int(values.get("active_projectile", 0)),
		int(values.get("active_vfx", 0)),
		int(values.get(
			"active_xp",
			values.get("active_xp_pickup", values.get("active_pickup", 0)),
		)),
	]


func _show_feedback(
	text: String,
	color: Color,
	_reduce_motion: bool,
	reduce_flashes: bool,
) -> void:
	_feedback_label.text = text
	_feedback_label.modulate = color
	_feedback_label.add_theme_constant_override("outline_size", 3 if reduce_flashes else 5)
	_feedback_label.visible = true
	_feedback_remaining = FEEDBACK_SECONDS


func _format_time(elapsed_seconds: float, boss_active: bool) -> String:
	var total_seconds: int = floori(maxf(0.0, elapsed_seconds))
	var minutes: int = floori(float(total_seconds) / 60.0)
	var base: String = "%02d:%02d" % [minutes, total_seconds % 60]
	return "%s  BOSS" % base if boss_active else base


func _format_number(value: float) -> String:
	return "%d" % roundi(value)


func _read_property(value: Variant, property_name: StringName, fallback: Variant) -> Variant:
	if value is Dictionary:
		return (value as Dictionary).get(property_name, fallback)
	if value is Object:
		var object := value as Object
		for property: Dictionary in object.get_property_list():
			if StringName(property.get("name", "")) == property_name:
				return object.get(property_name)
	return fallback
