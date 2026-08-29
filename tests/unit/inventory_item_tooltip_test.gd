extends RefCounted


const TOOLTIP_SCENE: PackedScene = preload("res://scenes/ui/inventory_item_tooltip.tscn")

var _payloads: Dictionary = {}


func test_names() -> PackedStringArray:
	return PackedStringArray(["inventory_item_tooltip_input_visibility_and_placement_contract"])


func run_test(test_name: String, assertions: Variant, context: Dictionary) -> void:
	if test_name != "inventory_item_tooltip_input_visibility_and_placement_contract":
		assertions.expect_true(false, "registered inventory item tooltip test")
		return
	await _exercise_tooltip(assertions, context["tree"] as SceneTree)


func _exercise_tooltip(assertions: Variant, tree: SceneTree) -> void:
	var host := Control.new()
	host.name = "InventoryItemTooltipTestHost"
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var left_card := _new_card("LeftCard", &"left", Vector2(32.0, 120.0))
	var right_card := _new_card("RightCard", &"right", Vector2(1792.0, 760.0))
	var outside_target := Button.new()
	outside_target.name = "OutsideTarget"
	outside_target.focus_mode = Control.FOCUS_ALL
	outside_target.position = Vector2(900.0, 900.0)
	outside_target.size = Vector2(120.0, 64.0)
	host.add_child(left_card)
	host.add_child(right_card)
	host.add_child(outside_target)
	var tooltip := TOOLTIP_SCENE.instantiate() as InventoryItemTooltip
	host.add_child(tooltip)
	tree.root.add_child(host)
	await tree.process_frame
	await tree.process_frame

	_payloads = {
		&"left": {
			"details": "種類: 主武器／弓\nレアリティ: Rare\n操作: A／Enter",
			"warning": "",
			"urgent": false,
		},
		&"right": {
			"details": "種類: 副武器／触媒\nレアリティ: Epic\n操作: A／Enter",
			"warning": "配置不可: 交換先の装備種別が一致しません",
			"urgent": false,
		},
	}
	left_card.tooltip_text = "native left details"
	right_card.tooltip_text = "native right details"
	tooltip.bind_target(left_card, _payload_for.bind(&"left"))
	tooltip.bind_target(right_card, _payload_for.bind(&"right"))
	tooltip.begin_session()

	var snapshot: Dictionary = tooltip.debug_snapshot()
	assertions.expect_false(snapshot["visible"], "tooltip is hidden before the first real input")
	assertions.expect_equal(&"none", snapshot["input_mode"], "tooltip starts with no preferred input mode")
	assertions.expect_equal("native left details", left_card.tooltip_text, "managed tooltip preserves the complete native text")
	assertions.expect_equal("", left_card.get_tooltip(Vector2.ZERO), "managed tooltip suppresses native duplicate rendering")
	assertions.expect_equal(Control.MOUSE_FILTER_IGNORE, tooltip.mouse_filter, "tooltip overlay never blocks pointer input")

	left_card.grab_focus()
	await tree.process_frame
	assertions.expect_false(tooltip.debug_snapshot()["visible"], "programmatic initial focus does not reveal the tooltip")
	tooltip.activate_focus_input()
	await tree.process_frame
	snapshot = tooltip.debug_snapshot()
	assertions.expect_true(snapshot["visible"], "keyboard or controller input reveals the focused card immediately")
	assertions.expect_equal(&"focus", snapshot["input_mode"], "focus input becomes the preferred input mode")
	assertions.expect_equal(&"left", snapshot["target_focus_id"], "focus tooltip follows the focused card")
	assertions.expect_true("種類: 主武器／弓" in str(snapshot["details"]), "focus tooltip reads its provider at display time")
	assertions.expect_equal("", snapshot["warning"], "empty warning region remains hidden")
	_assert_rect_inside_safe_viewport(assertions, snapshot["panel_rect"], host.get_viewport(), "right-side tooltip")
	assertions.expect_true(
		(snapshot["panel_rect"] as Rect2).position.x
		>= (snapshot["anchor_rect"] as Rect2).end.x + InventoryItemTooltip.TARGET_GAP - 0.5,
		"tooltip prefers the right side when it fits",
	)

	outside_target.grab_focus()
	await tree.process_frame
	assertions.expect_false(tooltip.debug_snapshot()["visible"], "focus moving to a non-target hides the tooltip")

	tooltip.activate_pointer_input()
	tooltip.call("_on_target_mouse_entered", left_card)
	snapshot = tooltip.debug_snapshot()
	assertions.expect_false(snapshot["visible"], "ordinary hover does not reveal the tooltip immediately")
	assertions.expect_equal(&"left", snapshot["pending_focus_id"], "ordinary hover waits on the hovered card")
	await tree.create_timer(InventoryItemTooltip.HOVER_DELAY_SECONDS * 0.5).timeout
	tooltip.activate_pointer_input()
	await tree.create_timer(InventoryItemTooltip.HOVER_DELAY_SECONDS * 0.5 + 0.05).timeout
	snapshot = tooltip.debug_snapshot()
	assertions.expect_true(snapshot["visible"], "ordinary hover reveals after 0.20 seconds without mouse motion resetting the delay")
	assertions.expect_equal(&"pointer", snapshot["input_mode"], "pointer input becomes the preferred input mode")
	tooltip.call("_on_target_mouse_exited", left_card)
	assertions.expect_false(tooltip.debug_snapshot()["visible"], "mouse exit hides the pointer tooltip")

	right_card.grab_focus()
	tooltip.activate_focus_input()
	await tree.process_frame
	snapshot = tooltip.debug_snapshot()
	assertions.expect_equal(&"right", snapshot["target_focus_id"], "last-used focus input overrides the former pointer target")
	assertions.expect_equal(
		AccessibilityServer.LIVE_POLITE,
		snapshot["warning_accessibility_live"],
		"warning is exposed through a polite accessibility live region",
	)
	assertions.expect_true(
		(snapshot["panel_rect"] as Rect2).end.x
		<= (snapshot["anchor_rect"] as Rect2).position.x - InventoryItemTooltip.TARGET_GAP + 0.5,
		"tooltip flips to the left near the right screen edge",
	)
	_assert_rect_inside_safe_viewport(assertions, snapshot["panel_rect"], host.get_viewport(), "left-side tooltip")

	(_payloads[&"right"] as Dictionary)["details"] = "更新後の詳細"
	(_payloads[&"right"] as Dictionary)["warning"] = "配置不可: 更新後の理由"
	tooltip.refresh_active()
	snapshot = tooltip.debug_snapshot()
	assertions.expect_equal("更新後の詳細", snapshot["details"], "visible tooltip recomputes dynamic details")
	assertions.expect_equal("配置不可: 更新後の理由", snapshot["warning"], "visible tooltip recomputes dynamic warnings")

	tooltip.hide_tooltip(true)
	(_payloads[&"right"] as Dictionary)["urgent"] = true
	tooltip.activate_pointer_input()
	tooltip.call("_on_target_mouse_entered", right_card)
	snapshot = tooltip.debug_snapshot()
	assertions.expect_true(snapshot["visible"], "urgent drag placement payload bypasses the hover delay")
	assertions.expect_equal(&"right", snapshot["target_focus_id"], "urgent pointer tooltip uses the hovered target")

	var visible_rect: Rect2 = host.get_viewport().get_visible_rect()
	var safe_inset: float = InventoryItemTooltip.VIEWPORT_MARGIN + 20.0
	var wide_anchor := Rect2(
		visible_rect.position.x + safe_inset,
		visible_rect.position.y + 40.0,
		visible_rect.size.x - safe_inset * 2.0,
		96.0,
	)
	var below_position: Vector2 = tooltip.call("_position_for_target", wide_anchor, Vector2(480.0, 220.0))
	assertions.expect_true(
		below_position.y >= wide_anchor.end.y + InventoryItemTooltip.TARGET_GAP - 0.5,
		"placement falls back below when neither horizontal side fits",
	)
	wide_anchor = Rect2(
		visible_rect.position.x + safe_inset,
		visible_rect.end.y - InventoryItemTooltip.VIEWPORT_MARGIN - 96.0,
		visible_rect.size.x - safe_inset * 2.0,
		96.0,
	)
	var above_position: Vector2 = tooltip.call("_position_for_target", wide_anchor, Vector2(480.0, 220.0))
	assertions.expect_true(
		above_position.y + 220.0 <= wide_anchor.position.y - InventoryItemTooltip.TARGET_GAP + 0.5,
		"placement falls back above when the lower edge is unavailable",
	)

	tooltip.unbind_target(right_card)
	snapshot = tooltip.debug_snapshot()
	assertions.expect_false(snapshot["visible"], "unbinding the displayed target hides the tooltip")
	assertions.expect_equal("native right details", right_card.get_tooltip(Vector2.ZERO), "unbinding restores native tooltip rendering")
	left_card.queue_free()
	await tree.process_frame
	assertions.expect_equal(0, tooltip.debug_snapshot()["bound_target_count"], "target deletion unregisters the final tooltip binding")

	tooltip.end_session()
	tree.root.remove_child(host)
	host.free()
	_payloads.clear()


func _new_card(node_name: String, focus_id: StringName, card_position: Vector2) -> InventoryCardButton:
	var card := InventoryCardButton.new()
	card.name = node_name
	card.focus_mode = Control.FOCUS_ALL
	card.position = card_position
	card.size = Vector2(96.0, 96.0)
	card.set_meta("focus_id", focus_id)
	return card


func _payload_for(payload_id: StringName) -> Dictionary:
	return (_payloads.get(payload_id, {}) as Dictionary).duplicate(true)


func _assert_rect_inside_safe_viewport(
	assertions: Variant,
	rect: Rect2,
	viewport: Viewport,
	label: String,
) -> void:
	var visible_rect: Rect2 = viewport.get_visible_rect()
	var margin: float = InventoryItemTooltip.VIEWPORT_MARGIN
	assertions.expect_true(rect.position.x >= visible_rect.position.x + margin - 0.5, "%s keeps the left margin" % label)
	assertions.expect_true(rect.position.y >= visible_rect.position.y + margin - 0.5, "%s keeps the top margin" % label)
	assertions.expect_true(rect.end.x <= visible_rect.end.x - margin + 0.5, "%s keeps the right margin" % label)
	assertions.expect_true(rect.end.y <= visible_rect.end.y - margin + 0.5, "%s keeps the bottom margin" % label)
