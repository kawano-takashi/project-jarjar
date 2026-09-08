class_name CombatHud
extends Control


const FEEDBACK_SECONDS: float = 0.45
const KILL_CHAIN_SECONDS: float = 1.5
const KILL_CHAIN_VISIBLE_MINIMUM: int = 3

@onready var _time_value: Label = %TimeValue
@onready var _level_kills: Label = %LevelKills
@onready var _hp_value: Label = %HpValue
@onready var _hp_bar: ProgressBar = %HpBar
@onready var _xp_value: Label = %XpValue
@onready var _xp_bar: ProgressBar = %XpBar
@onready var _boss_panel: PanelContainer = %BossPanel
@onready var _boss_hp_value: Label = %BossHpValue
@onready var _boss_hp_bar: ProgressBar = %BossHpBar
@onready var _weapon_container: HFlowContainer = %Weapons
@onready var _passive_container: HFlowContainer = %Passives
var _weapon_slots: Array[Label] = []
var _passive_slots: Array[Label] = []
@onready var _feedback_label: Label = %FeedbackLabel
@onready var _kill_chain: Label = %KillChain
@onready var _debug_overlay: Label = %DebugOverlay

var _feedback_remaining: float = 0.0
var _kill_chain_remaining: float = 0.0
var _kill_chain_count: int = 0
var _last_total_kills: int = -1
var _reduce_motion: bool = false
var _reduce_flashes: bool = false
var _chest_guidance: Array[Dictionary] = []


func _ready() -> void:
	_feedback_label.visible = false
	_kill_chain.visible = false
	_debug_overlay.visible = false
	update_from_values({})


func _process(delta: float) -> void:
	if delta <= 0.0:
		return
	if _feedback_remaining > 0.0:
		_feedback_remaining = maxf(0.0, _feedback_remaining - delta)
		if _feedback_remaining <= 0.0:
			_feedback_label.visible = false
	if _kill_chain_remaining > 0.0:
		_kill_chain_remaining = maxf(0.0, _kill_chain_remaining - delta)
		if _kill_chain_remaining <= 0.0:
			_kill_chain_count = 0
			_kill_chain.visible = false


func update_from_snapshot(snapshot: Variant) -> void:
	_chest_guidance.assign(_read_property(snapshot, &"chest_guidance", []))
	queue_redraw()
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
	if values.has("kill_chain_count"):
		_set_kill_chain(
			maxi(0, int(values.get("kill_chain_count", 0))),
			maxf(0.0, float(values.get("kill_chain_remaining_ticks", 0))) / 60.0,
		)
	elif _last_total_kills >= 0 and total_kills > _last_total_kills:
		_register_kills(total_kills - _last_total_kills)
	_last_total_kills = total_kills

	var current_hp: float = maxf(0.0, float(values.get("current_hp", 0.0)))
	var max_hp: float = maxf(0.0, float(values.get("max_hp", 0.0)))
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

	_resize_slots(_weapon_slots, _weapon_container, int(values.get("weapon_slot_count", 0)))
	_resize_slots(_passive_slots, _passive_container, int(values.get("passive_slot_count", 0)))
	_update_build_slots(_weapon_slots, values.get("weapons", []), true)
	_update_build_slots(_passive_slots, values.get("passives", []), false)
	_update_boss(values, boss_active)
	_update_debug(values)


func _draw() -> void:
	for cue: Dictionary in _chest_guidance:
		var cue_position: Vector2 = cue["screen_position"]
		var direction: Vector2 = cue["direction"]
		var tangent := Vector2(-direction.y, direction.x)
		var evolution: bool = int(cue["kind"]) == GameTypes.ChestKind.EVOLUTION_CAPABLE
		var color := Color(0.48, 0.92, 1.0) if evolution else Color(1.0, 0.8, 0.3)
		draw_circle(cue_position, 22.0, Color(0.02, 0.03, 0.04, 0.92))
		draw_colored_polygon(PackedVector2Array([
			cue_position + direction * 17.0,
			cue_position - direction * 4.0 + tangent * 9.0,
			cue_position - direction * 4.0 - tangent * 9.0,
		]), color)
		var icon_center: Vector2 = cue_position - direction * 10.0
		if evolution:
			draw_colored_polygon(PackedVector2Array([
				icon_center + Vector2(0, -5), icon_center + Vector2(5, 0),
				icon_center + Vector2(0, 5), icon_center + Vector2(-5, 0),
			]), color)
		else:
			draw_rect(Rect2(icon_center - Vector2(6, 4), Vector2(12, 8)), color, false, 2.0)


func present_damage(reduce_motion: bool = false, reduce_flashes: bool = false) -> void:
	_show_feedback("HIT", Color(1.0, 0.34, 0.28, 1.0), reduce_motion, reduce_flashes)


func present_pickup(count: int = 1, reduce_motion: bool = false, reduce_flashes: bool = false) -> void:
	var text: String = "+XP" if count <= 1 else "+XP ×%d" % count
	_show_feedback(text, Color(0.48, 0.9, 1.0, 1.0), reduce_motion, reduce_flashes)


func present_level_up(reduce_motion: bool = false, reduce_flashes: bool = false) -> void:
	_show_feedback("LEVEL UP", Color(1.0, 0.76, 0.28, 1.0), reduce_motion, reduce_flashes)


func present_evolution(reduce_motion: bool = false, reduce_flashes: bool = false) -> void:
	_show_feedback("EVOLUTION", Color(0.76, 0.54, 1.0, 1.0), reduce_motion, reduce_flashes)


func present_event(event: CombatPresentationEvent) -> void:
	if event == null:
		return
	# The snapshot is authoritative for chain count. Kill events from that same
	# tick only drive audiovisual feedback and must not increment it a second time.
	if event.kind == CombatPresentationEvent.Kind.CHAIN_MILESTONE:
		_set_kill_chain(event.count, KILL_CHAIN_SECONDS)


func set_accessibility(reduce_motion: bool, reduce_flashes: bool) -> void:
	_reduce_motion = reduce_motion
	_reduce_flashes = reduce_flashes
	if _kill_chain.visible:
		_kill_chain.modulate.a = 0.82 if reduce_flashes else 1.0


func set_debug_visible(should_show: bool) -> void:
	_debug_overlay.visible = should_show


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
		"kill_chain_visible": _kill_chain.visible,
		"kill_chain": _kill_chain.text,
		"debug_visible": _debug_overlay.visible,
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
		label.text = "%s\n%s" % [display_name, "EVO" if evolved else "Lv%d" % level]
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
	reduce_motion: bool,
	reduce_flashes: bool,
) -> void:
	_feedback_label.text = text
	_feedback_label.modulate = color
	_feedback_label.add_theme_constant_override("outline_size", 3 if reduce_flashes else 5)
	_feedback_label.modulate.a = 0.82 if reduce_flashes else 1.0
	_feedback_label.visible = true
	_feedback_remaining = FEEDBACK_SECONDS * (0.75 if reduce_motion else 1.0)


func _register_kills(count: int) -> void:
	if count <= 0:
		return
	if _kill_chain_remaining <= 0.0:
		_kill_chain_count = 0
	_kill_chain_count += count
	_kill_chain_remaining = KILL_CHAIN_SECONDS
	_refresh_kill_chain()


func _set_kill_chain(count: int, remaining_seconds: float) -> void:
	_kill_chain_count = count
	_kill_chain_remaining = remaining_seconds
	_refresh_kill_chain()


func _refresh_kill_chain() -> void:
	_kill_chain.visible = (
		_kill_chain_count >= KILL_CHAIN_VISIBLE_MINIMUM
		and _kill_chain_remaining > 0.0
	)
	if not _kill_chain.visible:
		return
	_kill_chain.text = "CHAIN ×%d" % _kill_chain_count
	_kill_chain.modulate = Color(1.0, 0.77, 0.28, 0.82 if _reduce_flashes else 1.0)
	if not _reduce_motion:
		_kill_chain.pivot_offset = _kill_chain.size * 0.5
		_kill_chain.scale = Vector2(1.08, 1.08)
		var tween: Tween = _kill_chain.create_tween()
		tween.tween_property(_kill_chain, "scale", Vector2.ONE, 0.10)


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

func _resize_slots(labels: Array[Label], container: HFlowContainer, count: int) -> void:
	while labels.size() > count:
		var label: Label = labels.pop_back()
		container.remove_child(label)
		label.queue_free()
	while labels.size() < count:
		var label := Label.new()
		label.custom_minimum_size = Vector2(96.0, 40.0)
		label.add_theme_font_size_override("font_size", 14)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		container.add_child(label)
		labels.append(label)
