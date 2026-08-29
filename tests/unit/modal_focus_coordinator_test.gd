extends RefCounted


func test_names() -> PackedStringArray:
	return PackedStringArray(["modal_focus_coordinator_lifo_and_restore_contract"])


func run_test(test_name: String, assertions: Variant, context: Dictionary) -> void:
	if test_name != "modal_focus_coordinator_lifo_and_restore_contract":
		assertions.expect_true(false, "registered modal focus coordinator test")
		return
	await _exercise_coordinator(assertions, context["tree"] as SceneTree)


func _exercise_coordinator(assertions: Variant, tree: SceneTree) -> void:
	var host := Control.new()
	host.name = "ModalCoordinatorTestHost"
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := Control.new()
	background.name = "Background"
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(background)
	var origin := Button.new()
	origin.name = "Origin"
	origin.focus_mode = Control.FOCUS_ALL
	background.add_child(origin)
	var fallback := Button.new()
	fallback.name = "Fallback"
	fallback.focus_mode = Control.FOCUS_ALL
	background.add_child(fallback)

	var modal_a := _new_modal("ModalA")
	var modal_a_focus := modal_a.get_node("Focus") as Button
	host.add_child(modal_a)
	var modal_b := _new_modal("ModalB")
	var modal_b_focus := modal_b.get_node("Focus") as Button
	host.add_child(modal_b)
	tree.root.add_child(host)
	await tree.process_frame

	origin.grab_focus()
	assertions.expect_equal(origin, host.get_viewport().gui_get_focus_owner(), "fixture starts on the background origin")
	var coordinator := ModalFocusCoordinator.new()
	coordinator.configure(host.get_viewport(), [background])
	assertions.expect_true(coordinator.push(modal_a, fallback), "first modal pushes")
	modal_a.visible = true
	modal_a_focus.grab_focus()
	assertions.expect_true(coordinator.is_active(modal_a), "first modal is active")
	assertions.expect_equal(Control.FOCUS_NONE, origin.get_focus_mode_with_override(), "background effective focus is disabled")
	assertions.expect_equal(Control.MOUSE_FILTER_IGNORE, origin.get_mouse_filter_with_override(), "background effective mouse is disabled")
	assertions.expect_false(background.mouse_behavior_recursive == Control.MOUSE_BEHAVIOR_ENABLED, "background recursive mouse override is not enabled")
	origin.grab_focus()
	assertions.expect_false(host.get_viewport().gui_get_focus_owner() == origin, "direct background grab_focus cannot focus behind modal")
	FocusController.grab_focus_safe(modal_a_focus)

	assertions.expect_true(coordinator.push(modal_b, fallback), "nested modal pushes")
	modal_b.visible = true
	modal_b_focus.grab_focus()
	assertions.expect_equal(2, coordinator.stack_size(), "nested modal stack is LIFO")
	assertions.expect_false(coordinator.pop(modal_a), "non-top modal cannot pop out of order")
	assertions.expect_equal(Control.FOCUS_NONE, modal_a_focus.get_focus_mode_with_override(), "lower modal effective focus is disabled")
	assertions.expect_equal(Control.MOUSE_FILTER_IGNORE, modal_a_focus.get_mouse_filter_with_override(), "lower modal effective mouse is disabled")
	assertions.expect_false(modal_a.is_processing_input(), "lower modal raw input processing is suspended")
	modal_a_focus.grab_focus()
	assertions.expect_false(host.get_viewport().gui_get_focus_owner() == modal_a_focus, "direct lower-modal grab_focus cannot steal nested focus")
	FocusController.grab_focus_safe(modal_b_focus)
	FocusController.grab_focus_deferred(modal_a_focus)
	await tree.process_frame
	assertions.expect_equal(modal_b_focus, host.get_viewport().gui_get_focus_owner(), "delayed lower-modal focus is rejected")

	modal_b.visible = false
	assertions.expect_true(coordinator.pop(modal_b), "top nested modal pops")
	assertions.expect_equal(modal_a_focus, host.get_viewport().gui_get_focus_owner(), "nested close restores the exact lower-modal origin")
	assertions.expect_equal(Control.FOCUS_ALL, modal_a_focus.get_focus_mode_with_override(), "revealed lower modal focus is re-enabled")

	origin.disabled = true
	modal_a.visible = false
	assertions.expect_true(coordinator.pop(modal_a), "last modal pops")
	assertions.expect_equal(fallback, host.get_viewport().gui_get_focus_owner(), "disabled origin falls back to the screen default")
	assertions.expect_equal(Control.FOCUS_ALL, fallback.get_focus_mode_with_override(), "background effective focus is restored")
	assertions.expect_false(coordinator.has_active_modal(), "stack is empty after final pop")

	origin.disabled = false
	origin.grab_focus()
	assertions.expect_true(coordinator.push(modal_a, fallback), "modal can open again after a complete pop")
	modal_a.visible = true
	modal_a_focus.grab_focus()
	origin.queue_free()
	await tree.process_frame
	modal_a.visible = false
	assertions.expect_true(coordinator.pop(modal_a), "modal with a freed origin pops")
	assertions.expect_equal(fallback, host.get_viewport().gui_get_focus_owner(), "freed origin also falls back to the screen default")

	tree.root.remove_child(host)
	host.free()


func _new_modal(node_name: String) -> Control:
	var modal := Control.new()
	modal.name = node_name
	modal.visible = false
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	modal.mouse_force_pass_scroll_events = false
	modal.set_process_input(false)
	var focus := Button.new()
	focus.name = "Focus"
	focus.focus_mode = Control.FOCUS_ALL
	modal.add_child(focus)
	return modal
