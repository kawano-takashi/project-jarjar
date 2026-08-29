extends RefCounted


const TITLE_SCENE: PackedScene = preload("res://scenes/ui/title_screen.tscn")
const REWARD_SCENE: PackedScene = preload("res://scenes/ui/reward_reveal_screen.tscn")
const INVENTORY_SCENE: PackedScene = preload("res://scenes/ui/inventory_screen.tscn")
const RESULT_SCENE: PackedScene = preload("res://scenes/ui/result_screen.tscn")
const FAILED_SCENE: PackedScene = preload("res://scenes/ui/failed_screen.tscn")
const FOCUS_FRAME_PATH := NodePath("__FocusShapeFrame")
const LOGICAL_VIEWPORT_SIZE := Vector2i(1920, 1080)
const TARGET_RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1920, 1080),
	Vector2i(1600, 900),
	Vector2i(1280, 720),
]


func test_names() -> PackedStringArray:
	return PackedStringArray([
		"ui_focus_shape_labels_and_resolution_contract",
	])


func run_test(test_name: String, assertions: Variant, context: Dictionary) -> void:
	match test_name:
		"ui_focus_shape_labels_and_resolution_contract":
			await _test_ui_polish_contract(assertions, context)
		_:
			assertions.expect_true(false, "registered release readiness UI polish scenario test")


func _test_ui_polish_contract(assertions: Variant, context: Dictionary) -> void:
	var tree: SceneTree = context["tree"] as SceneTree
	_assert_project_stretch_contract(assertions)
	var catalog := DefinitionCatalog.new()
	assertions.expect_true(
		catalog.load_and_validate(),
		"release readiness UI polish catalog valid: %s" % catalog.error_text,
	)
	if not catalog.is_valid:
		return

	var title := TITLE_SCENE.instantiate() as Control
	await _attach_screen(title, tree)
	await _assert_screen_contract(assertions, title, "TITLE", tree)
	(title.get_node("%TitleSettings") as Button).emit_signal("pressed")
	await tree.process_frame
	await _assert_screen_contract(
		assertions,
		title.get_node("%SettingsOverlay") as Control,
		"SETTINGS",
		tree,
	)
	await _remove_screen(title, tree)

	var reward_qa: Dictionary = QaScenarioFactory.build("reward_controls", catalog)
	assertions.expect_true(reward_qa.get("valid", false), "reward UI polish fixture valid")
	if reward_qa.get("valid", false):
		var reward := REWARD_SCENE.instantiate() as RewardRevealScreen
		reward.set_automatic_progression(false)
		reward.initialize(reward_qa["state"] as RunState)
		await _attach_screen(reward, tree)
		await _assert_screen_contract(assertions, reward, "REWARD_REVEAL", tree)
		await _remove_screen(reward, tree)

	var inventory_qa: Dictionary = QaScenarioFactory.build("inventory_controller", catalog)
	assertions.expect_true(inventory_qa.get("valid", false), "inventory UI polish fixture valid")
	if inventory_qa.get("valid", false):
		var inventory := INVENTORY_SCENE.instantiate() as InventoryScreen
		inventory.initialize(inventory_qa["state"] as RunState, catalog)
		await _attach_screen(inventory, tree)
		await _assert_screen_contract(assertions, inventory, "INVENTORY", tree)
		inventory.test_focus("action_2")
		inventory.test_accept()
		await tree.process_frame
		await _assert_screen_contract(
			assertions,
			inventory.get_node("%FusionDialog") as Control,
			"FUSION_DIALOG",
			tree,
		)
		inventory.test_cancel()
		inventory.test_open_bulk()
		await tree.process_frame
		var bulk := inventory.get_node("%BulkSelectDialog") as Control
		await _assert_screen_contract(assertions, bulk, "BULK_SELECT_DIALOG", tree)
		(bulk.get_node("%BulkCancel") as Button).emit_signal("pressed")
		await tree.process_frame
		await _remove_screen(inventory, tree)

	var summary_qa: Dictionary = QaScenarioFactory.build("result_controller", catalog)
	assertions.expect_true(summary_qa.get("valid", false), "summary UI polish fixture valid")
	if not summary_qa.get("valid", false):
		return
	var summary_state: RunState = summary_qa["state"] as RunState
	var result := RESULT_SCENE.instantiate() as RunSummaryScreen
	result.initialize(summary_state, catalog)
	await _attach_screen(result, tree)
	await _assert_screen_contract(assertions, result, "RESULT", tree)
	await _remove_screen(result, tree)

	summary_state.phase = GameTypes.RunPhase.FAILED
	summary_state.wave_number = 6
	summary_state.cleared_waves = 5
	var failed := FAILED_SCENE.instantiate() as RunSummaryScreen
	failed.initialize(summary_state, catalog)
	await _attach_screen(failed, tree)
	await _assert_screen_contract(assertions, failed, "FAILED", tree)
	await _remove_screen(failed, tree)


func _attach_screen(screen: Control, tree: SceneTree) -> void:
	if screen == null:
		return
	var viewport := SubViewport.new()
	viewport.name = "__ReleaseReadinessLayoutViewport"
	viewport.size = LOGICAL_VIEWPORT_SIZE
	viewport.size_2d_override = LOGICAL_VIEWPORT_SIZE
	viewport.size_2d_override_stretch = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	tree.root.add_child(viewport)
	viewport.add_child(screen)
	await tree.process_frame
	await tree.process_frame


func _remove_screen(screen: Control, tree: SceneTree) -> void:
	if screen == null:
		return
	var viewport := screen.get_parent() as SubViewport
	if viewport != null:
		viewport.remove_child(screen)
	screen.free()
	if viewport != null:
		if viewport.get_parent() == tree.root:
			tree.root.remove_child(viewport)
		viewport.free()
	await tree.process_frame


func _assert_screen_contract(
	assertions: Variant,
	screen: Control,
	label: String,
	tree: SceneTree,
) -> void:
	assertions.expect_true(screen != null, "%s scene instantiates" % label)
	if screen == null:
		return
	_assert_focus_shapes(assertions, screen, label)
	_assert_button_labels(assertions, screen, label)
	await _assert_resolution_layout(assertions, screen, label, tree)


func _assert_project_stretch_contract(assertions: Variant) -> void:
	assertions.expect_equal(
		LOGICAL_VIEWPORT_SIZE.x,
		int(ProjectSettings.get_setting("display/window/size/viewport_width", 0)),
		"release readiness base viewport width remains 1920",
	)
	assertions.expect_equal(
		LOGICAL_VIEWPORT_SIZE.y,
		int(ProjectSettings.get_setting("display/window/size/viewport_height", 0)),
		"release readiness base viewport height remains 1080",
	)
	assertions.expect_equal(
		"canvas_items",
		str(ProjectSettings.get_setting("display/window/stretch/mode", "")),
		"release readiness uses canvas_items stretch",
	)
	assertions.expect_equal(
		"expand",
		str(ProjectSettings.get_setting("display/window/stretch/aspect", "")),
		"release readiness uses expand stretch aspect",
	)
	for resolution: Vector2i in TARGET_RESOLUTIONS:
		assertions.expect_equal(
			resolution.x * LOGICAL_VIEWPORT_SIZE.y,
			resolution.y * LOGICAL_VIEWPORT_SIZE.x,
			"%dx%d preserves the 16:9 logical canvas" % [resolution.x, resolution.y],
		)


func _assert_focus_shapes(assertions: Variant, root: Control, label: String) -> void:
	var focusable_count: int = 0
	for control: Control in _descendant_controls(root):
		if control.focus_mode != Control.FOCUS_ALL:
			continue
		focusable_count += 1
		var frame := control.get_node_or_null(FOCUS_FRAME_PATH) as Panel
		var focus_id := str(control.get_meta("focus_id", control.name))
		assertions.expect_true(frame != null, "%s %s has persistent shape frame" % [label, focus_id])
		assertions.expect_true(
			int(control.get_meta("focus_shape_border_width", 0)) >= 3,
			"%s %s focus border is at least 3px" % [label, focus_id],
		)
		assertions.expect_equal(
			"asymmetric_outline",
			str(control.get_meta("focus_shape_kind", "")),
			"%s %s focus cue differs by shape" % [label, focus_id],
		)
	assertions.expect_true(focusable_count > 0, "%s exposes focusable controls" % label)
	var focused: Control = root.get_viewport().gui_get_focus_owner()
	assertions.expect_true(focused != null, "%s has an active focused control" % label)
	if focused != null:
		var focused_frame := focused.get_node_or_null(FOCUS_FRAME_PATH) as Panel
		assertions.expect_true(
			focused_frame != null and focused_frame.visible,
			"%s active focus shape remains visible" % label,
		)


func _assert_button_labels(assertions: Variant, root: Control, label: String) -> void:
	var button_count: int = 0
	for control: Control in _descendant_controls(root):
		if not control is BaseButton:
			continue
		button_count += 1
		var button := control as BaseButton
		var text_value: String = button.text
		assertions.expect_true(
			_contains_japanese(text_value),
			"%s %s has a Japanese operation label" % [label, button.name],
		)
		assertions.expect_true(
			_has_keyboard_mapping(text_value),
			"%s %s shows a keyboard mapping" % [label, button.name],
		)
		assertions.expect_true(
			_has_gamepad_mapping(text_value),
			"%s %s shows a gamepad mapping" % [label, button.name],
		)
	assertions.expect_true(button_count > 0, "%s exposes operation buttons" % label)


func _assert_resolution_layout(
	assertions: Variant,
	root: Control,
	label: String,
	tree: SceneTree,
) -> void:
	var viewport := root.get_viewport() as SubViewport
	assertions.expect_true(viewport != null, "%s uses the release readiness render viewport" % label)
	if viewport == null:
		return
	assertions.expect_equal(
		LOGICAL_VIEWPORT_SIZE,
		viewport.size_2d_override,
		"%s uses the project logical canvas" % label,
	)
	assertions.expect_true(
		viewport.size_2d_override_stretch,
		"%s enables Godot's 2D stretch path" % label,
	)

	for resolution: Vector2i in TARGET_RESOLUTIONS:
		viewport.size = resolution
		await tree.process_frame
		await tree.process_frame

		assertions.expect_equal(
			resolution,
			viewport.size,
			"%s render target is actually %dx%d" % [label, resolution.x, resolution.y],
		)
		assertions.expect_equal(
			Vector2(resolution),
			viewport.get_texture().get_size(),
			"%s rendered texture is %dx%d" % [label, resolution.x, resolution.y],
		)

		var root_rect: Rect2 = root.get_global_rect()
		assertions.expect_true(
			root_rect.position.is_equal_approx(Vector2.ZERO)
			and root_rect.size.is_equal_approx(Vector2(LOGICAL_VIEWPORT_SIZE)),
			"%s keeps a laid-out 1920x1080 logical root at %dx%d" % [
				label,
				resolution.x,
				resolution.y,
			],
		)
		if root_rect.size.x <= 0.0 or root_rect.size.y <= 0.0:
			continue

		var stretch_transform: Transform2D = viewport.get_stretch_transform()
		var expected_scale: float = float(resolution.x) / float(LOGICAL_VIEWPORT_SIZE.x)
		assertions.expect_float(
			expected_scale,
			stretch_transform.x.length(),
			"%s Godot stretch X matches %dx%d" % [label, resolution.x, resolution.y],
		)
		assertions.expect_float(
			expected_scale,
			stretch_transform.y.length(),
			"%s Godot stretch Y matches %dx%d" % [label, resolution.x, resolution.y],
		)
		assertions.expect_true(
			stretch_transform.origin.is_equal_approx(Vector2.ZERO),
			"%s Godot stretch has no 16:9 letterbox offset at %dx%d" % [
				label,
				resolution.x,
				resolution.y,
			],
		)

		var physical_bounds := Rect2(Vector2.ZERO, Vector2(resolution))
		var outside_controls: PackedStringArray = []
		var clipped_text_controls: PackedStringArray = []
		for control: Control in _descendant_controls(root):
			if not control.is_visible_in_tree():
				continue
			if control != root:
				var physical_rect := _transformed_rect(
					control.get_global_rect(),
					stretch_transform,
				)
				if not _rect_fits_inside(physical_rect, physical_bounds, 0.75):
					outside_controls.append(
						"%s rect=%s min=%s anchors=%s/%s offsets=%s/%s"
						% [
							root.get_path_to(control),
							physical_rect,
							control.get_combined_minimum_size() * expected_scale,
							Vector2(control.anchor_left, control.anchor_top),
							Vector2(control.anchor_right, control.anchor_bottom),
							Vector2(control.offset_left, control.offset_top),
							Vector2(control.offset_right, control.offset_bottom),
						]
					)
			if not (control is Label or control is BaseButton):
				continue
			var minimum_size: Vector2 = control.get_combined_minimum_size()
			if (
				control.size.x + 0.5 < minimum_size.x
				or control.size.y + 0.5 < minimum_size.y
			):
				clipped_text_controls.append(str(root.get_path_to(control)))
				continue
			if control is Label:
				var text_label := control as Label
				if text_label.get_visible_line_count() != text_label.get_line_count():
					clipped_text_controls.append(str(root.get_path_to(control)))

		assertions.expect_equal(
			PackedStringArray(),
			outside_controls,
			"%s has zero controls outside %dx%d" % [label, resolution.x, resolution.y],
		)
		assertions.expect_equal(
			PackedStringArray(),
			clipped_text_controls,
			"%s has zero clipped text controls at %dx%d" % [
				label,
				resolution.x,
				resolution.y,
			],
		)
		assertions.expect_equal(
			PackedStringArray(),
			_find_content_overlaps(root),
			"%s has zero content overlaps at %dx%d" % [label, resolution.x, resolution.y],
		)


func _transformed_rect(source: Rect2, transform: Transform2D) -> Rect2:
	var corners := PackedVector2Array([
		source.position,
		Vector2(source.end.x, source.position.y),
		source.end,
		Vector2(source.position.x, source.end.y),
	])
	var result := Rect2(transform * corners[0], Vector2.ZERO)
	for index: int in range(1, corners.size()):
		result = result.expand(transform * corners[index])
	return result


func _rect_fits_inside(inner: Rect2, outer: Rect2, tolerance: float) -> bool:
	return (
		inner.position.x >= outer.position.x - tolerance
		and inner.position.y >= outer.position.y - tolerance
		and inner.end.x <= outer.end.x + tolerance
		and inner.end.y <= outer.end.y + tolerance
	)


func _find_content_overlaps(root: Control) -> PackedStringArray:
	var content_controls: Array[Control] = []
	for control: Control in _descendant_controls(root):
		if control.is_visible_in_tree() and _is_content_leaf(control):
			content_controls.append(control)
	var overlaps: PackedStringArray = []
	for first_index: int in range(content_controls.size()):
		for second_index: int in range(first_index + 1, content_controls.size()):
			var first: Control = content_controls[first_index]
			var second: Control = content_controls[second_index]
			if first.is_ancestor_of(second) or second.is_ancestor_of(first):
				continue
			var first_visible_rect: Rect2 = _visible_content_rect(first)
			var second_visible_rect: Rect2 = _visible_content_rect(second)
			if first_visible_rect.has_area() == false or second_visible_rect.has_area() == false:
				continue
			var overlap: Rect2 = first_visible_rect.intersection(second_visible_rect)
			if overlap.size.x * overlap.size.y > 0.25:
				overlaps.append(
					"%s rect=%s / %s rect=%s overlap=%s"
					% [
						root.get_path_to(first),
						first.get_global_rect(),
						root.get_path_to(second),
						second.get_global_rect(),
						overlap,
					]
				)
	return overlaps


func _visible_content_rect(control: Control) -> Rect2:
	var result: Rect2 = control.get_global_rect()
	var ancestor: Node = control.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			result = result.intersection((ancestor as ScrollContainer).get_global_rect())
			if not result.has_area():
				return Rect2()
		ancestor = ancestor.get_parent()
	return result


func _is_content_leaf(control: Control) -> bool:
	return control is Label or control is BaseButton or control is HSlider


func _descendant_controls(root: Control) -> Array[Control]:
	var result: Array[Control] = [root]
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var current: Node = pending.pop_back()
		for child: Node in current.get_children():
			pending.append(child)
			if child is Control:
				result.append(child as Control)
	return result


func _contains_japanese(text_value: String) -> bool:
	for index: int in range(text_value.length()):
		var codepoint: int = text_value.unicode_at(index)
		if (
			(codepoint >= 0x3040 and codepoint <= 0x30ff)
			or (codepoint >= 0x3400 and codepoint <= 0x9fff)
		):
			return true
	return false


func _has_keyboard_mapping(text_value: String) -> bool:
	return "Enter" in text_value or "Esc" in text_value or "←" in text_value


func _has_gamepad_mapping(text_value: String) -> bool:
	return (
		"A" in text_value
		or "B" in text_value
		or "X" in text_value
		or "Y" in text_value
		or "方向パッド" in text_value
	)
