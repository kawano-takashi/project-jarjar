extends RefCounted


const ARENA_SCENE: PackedScene = preload("res://scenes/gameplay/arena_combat.tscn")
const SCREEN_DIRECTION_DOT_MINIMUM: float = 0.9999


func test_names() -> PackedStringArray:
	return PackedStringArray([
		"camera_relative_movement_matches_view",
		"survival_arena_is_forty_by_forty",
		"gameplay_movement_input_bindings",
	])


func run_test(test_name: String, assertions: Variant, context: Dictionary) -> void:
	match test_name:
		"camera_relative_movement_matches_view":
			await _test_camera_relative_movement(assertions, context["tree"] as SceneTree)
		"survival_arena_is_forty_by_forty":
			await _test_arena_dimensions(assertions, context["tree"] as SceneTree)
		"gameplay_movement_input_bindings":
			_test_input_bindings(assertions)
		_:
			assertions.expect_true(false, "registered arena movement scenario test")


func _test_camera_relative_movement(assertions: Variant, tree: SceneTree) -> void:
	var arena: ArenaPresenter = ARENA_SCENE.instantiate() as ArenaPresenter
	assertions.expect_true(arena != null, "survival arena scene instantiates")
	if arena == null:
		return
	var viewport: SubViewport = await _attach(arena, tree)
	var camera: Camera3D = arena.get_node("%ArenaCamera") as Camera3D
	assertions.expect_true(camera != null, "survival arena camera exists")
	if camera != null:
		_assert_screen_direction(assertions, arena, camera, Vector2.RIGHT, Vector2.RIGHT, "right")
		_assert_screen_direction(assertions, arena, camera, Vector2.UP, Vector2.UP, "up")
		var analog_input := Vector2(0.35, -0.72)
		assertions.expect_float(
			analog_input.length(),
			arena.camera_relative_move_input(analog_input).length(),
			"camera-relative mapping preserves analog magnitude",
		)
	await _detach(arena, viewport, tree)


func _test_arena_dimensions(assertions: Variant, tree: SceneTree) -> void:
	var arena: ArenaPresenter = ARENA_SCENE.instantiate() as ArenaPresenter
	if arena == null:
		assertions.expect_true(false, "survival arena scene instantiates for dimensions")
		return
	var viewport: SubViewport = await _attach(arena, tree)
	var floor_mesh_instance: MeshInstance3D = arena.get_node("Floor") as MeshInstance3D
	var floor_mesh: BoxMesh = floor_mesh_instance.mesh as BoxMesh
	assertions.expect_equal(Vector3(40.0, 0.1, 40.0), floor_mesh.size, "floor mesh is forty meters square")
	assertions.expect_float(-20.0, (arena.get_node("BoundaryNorth") as MeshInstance3D).position.z, "north boundary is at minus twenty")
	assertions.expect_float(20.0, (arena.get_node("BoundarySouth") as MeshInstance3D).position.z, "south boundary is at plus twenty")
	assertions.expect_float(-20.0, (arena.get_node("BoundaryWest") as MeshInstance3D).position.x, "west boundary is at minus twenty")
	assertions.expect_float(20.0, (arena.get_node("BoundaryEast") as MeshInstance3D).position.x, "east boundary is at plus twenty")
	assertions.expect_equal(2048, ((arena.get_node("%XpInstances") as MultiMeshInstance3D).multimesh).instance_count, "arena renders the complete XP pool")
	await _detach(arena, viewport, tree)


func _test_input_bindings(assertions: Variant) -> void:
	_assert_action_bindings(assertions, &"move_up", KEY_W, KEY_UP, JOY_BUTTON_DPAD_UP, JOY_AXIS_LEFT_Y, -1.0)
	_assert_action_bindings(assertions, &"move_down", KEY_S, KEY_DOWN, JOY_BUTTON_DPAD_DOWN, JOY_AXIS_LEFT_Y, 1.0)
	_assert_action_bindings(assertions, &"move_left", KEY_A, KEY_LEFT, JOY_BUTTON_DPAD_LEFT, JOY_AXIS_LEFT_X, -1.0)
	_assert_action_bindings(assertions, &"move_right", KEY_D, KEY_RIGHT, JOY_BUTTON_DPAD_RIGHT, JOY_AXIS_LEFT_X, 1.0)


func _assert_screen_direction(
	assertions: Variant,
	arena: ArenaPresenter,
	camera: Camera3D,
	screen_input: Vector2,
	expected_screen_direction: Vector2,
	label: String,
) -> void:
	var world_input: Vector2 = arena.camera_relative_move_input(screen_input)
	var screen_origin: Vector2 = camera.unproject_position(Vector3.ZERO)
	var screen_target: Vector2 = camera.unproject_position(Vector3(world_input.x, 0.0, world_input.y))
	var projected_direction: Vector2 = (screen_target - screen_origin).normalized()
	assertions.expect_true(
		projected_direction.dot(expected_screen_direction) >= SCREEN_DIRECTION_DOT_MINIMUM,
		"%s input follows the matching screen direction" % label,
	)


func _assert_action_bindings(
	assertions: Variant,
	action: StringName,
	letter_key: Key,
	arrow_key: Key,
	dpad_button: JoyButton,
	stick_axis: JoyAxis,
	stick_value: float,
) -> void:
	assertions.expect_float(0.2, InputMap.action_get_deadzone(action), "%s keeps the gameplay deadzone" % action)
	assertions.expect_true(_has_physical_key(action, letter_key), "%s includes WASD" % action)
	assertions.expect_true(_has_physical_key(action, arrow_key), "%s includes arrows" % action)
	assertions.expect_true(_has_joy_button(action, dpad_button), "%s includes direction pad" % action)
	assertions.expect_true(_has_joy_motion(action, stick_axis, stick_value), "%s includes left stick" % action)


func _has_physical_key(action: StringName, physical_keycode: Key) -> bool:
	for event: InputEvent in InputMap.action_get_events(action):
		var key_event: InputEventKey = event as InputEventKey
		if key_event != null and key_event.physical_keycode == physical_keycode:
			return true
	return false


func _has_joy_button(action: StringName, button: JoyButton) -> bool:
	for event: InputEvent in InputMap.action_get_events(action):
		var button_event: InputEventJoypadButton = event as InputEventJoypadButton
		if button_event != null and button_event.button_index == button:
			return true
	return false


func _has_joy_motion(action: StringName, axis: JoyAxis, axis_value: float) -> bool:
	for event: InputEvent in InputMap.action_get_events(action):
		var motion_event: InputEventJoypadMotion = event as InputEventJoypadMotion
		if motion_event != null and motion_event.axis == axis and is_equal_approx(motion_event.axis_value, axis_value):
			return true
	return false


func _attach(arena: ArenaPresenter, tree: SceneTree) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	tree.root.add_child(viewport)
	viewport.add_child(arena)
	await tree.process_frame
	await tree.process_frame
	return viewport


func _detach(arena: ArenaPresenter, viewport: SubViewport, tree: SceneTree) -> void:
	viewport.remove_child(arena)
	arena.free()
	tree.root.remove_child(viewport)
	viewport.free()
	await tree.process_frame
