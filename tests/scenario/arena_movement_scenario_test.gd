extends RefCounted


const ARENA_SCENE: PackedScene = preload("res://scenes/gameplay/arena_combat.tscn")
const SCREEN_DIRECTION_DOT_MINIMUM: float = 0.9999


func test_names() -> PackedStringArray:
	return PackedStringArray([
		"camera_relative_movement_matches_view",
		"camera_relative_movement_reaches_combat_and_tutorial",
		"gameplay_movement_input_bindings",
	])


func run_test(test_name: String, assertions: Variant, context: Dictionary) -> void:
	match test_name:
		"camera_relative_movement_matches_view":
			await _test_camera_relative_movement(assertions, context["tree"] as SceneTree)
		"camera_relative_movement_reaches_combat_and_tutorial":
			await _test_combat_and_tutorial_paths(assertions, context["tree"] as SceneTree)
		"gameplay_movement_input_bindings":
			_test_input_bindings(assertions)
		_:
			assertions.expect_true(false, "registered arena movement scenario test")


func _test_camera_relative_movement(assertions: Variant, tree: SceneTree) -> void:
	var arena: ArenaPresenter = ARENA_SCENE.instantiate() as ArenaPresenter
	assertions.expect_true(arena != null, "arena movement scene instantiates")
	if arena == null:
		return
	var viewport: SubViewport = await _attach(arena, tree)
	var camera: Camera3D = arena.get_node("%ArenaCamera") as Camera3D
	assertions.expect_true(camera != null, "arena movement camera exists")
	if camera == null:
		await _detach(arena, viewport, tree)
		return

	_assert_screen_direction(assertions, arena, camera, Vector2.RIGHT, Vector2.RIGHT, "right")
	_assert_screen_direction(assertions, arena, camera, Vector2.LEFT, Vector2.LEFT, "left")
	_assert_screen_direction(assertions, arena, camera, Vector2.UP, Vector2.UP, "up")
	_assert_screen_direction(assertions, arena, camera, Vector2.DOWN, Vector2.DOWN, "down")
	var current_world_right: Vector2 = arena._camera_relative_move_input(Vector2.RIGHT)
	var current_world_up: Vector2 = arena._camera_relative_move_input(Vector2.UP)
	assertions.expect_true(
		current_world_right.x > 0.0 and current_world_right.y < 0.0,
		"current camera maps screen right to positive X and negative Z",
	)
	assertions.expect_true(
		current_world_up.x < 0.0 and current_world_up.y < 0.0,
		"current camera maps screen up to negative X and negative Z",
	)

	var analog_input := Vector2(0.35, -0.72)
	var analog_world: Vector2 = arena._camera_relative_move_input(analog_input)
	assertions.expect_float(
		analog_input.length(),
		analog_world.length(),
		"camera-relative mapping preserves analog magnitude",
	)
	assertions.expect_equal(
		Vector2.ZERO,
		arena._camera_relative_move_input(Vector2.ZERO),
		"camera-relative mapping preserves zero input",
	)

	camera.position = Vector3(-12.0, 18.0, 7.0)
	camera.look_at(Vector3.ZERO, Vector3.UP)
	camera.force_update_transform()
	_assert_screen_direction(assertions, arena, camera, Vector2.RIGHT, Vector2.RIGHT, "yawed right")
	_assert_screen_direction(assertions, arena, camera, Vector2.UP, Vector2.UP, "yawed up")

	camera.rotation = Vector3(0.0, 0.0, PI * 0.5)
	camera.force_update_transform()
	assertions.expect_true(
		arena._camera_relative_move_input(analog_input).is_equal_approx(analog_input),
		"degenerate camera axis falls back to unmodified input",
	)
	await _detach(arena, viewport, tree)


func _test_combat_and_tutorial_paths(assertions: Variant, tree: SceneTree) -> void:
	var catalog := DefinitionCatalog.new()
	assertions.expect_true(catalog.load_and_validate(), "arena movement catalog valid")
	if not catalog.is_valid:
		return
	var arena: ArenaPresenter = ARENA_SCENE.instantiate() as ArenaPresenter
	assertions.expect_true(arena != null, "arena movement integration scene instantiates")
	if arena == null:
		return
	var viewport: SubViewport = await _attach(arena, tree)

	var combat_state: RunState = RunStateFactory.create(20260901, catalog.wave(1))
	var combat_simulation := CombatSimulation.new()
	combat_simulation.initialize(combat_state, catalog)
	arena.initialize(combat_simulation)
	arena.set_physics_process(false)
	Input.action_release(&"move_right")
	Input.action_press(&"move_right")
	arena._physics_process(1.0 / 60.0)
	Input.action_release(&"move_right")
	assertions.expect_true(
		combat_simulation.player_position.x > 0.0
		and combat_simulation.player_position.y < 0.0,
		"normal combat receives camera-relative right movement",
	)

	var tutorial_state: RunState = RunStateFactory.create(20260902, catalog.wave(1))
	var tutorial_simulation := CombatSimulation.new()
	tutorial_simulation.initialize(tutorial_state, catalog)
	var tutorial := TutorialController.new()
	tutorial.begin_run(false)
	arena.initialize(tutorial_simulation, tutorial)
	arena.set_physics_process(false)
	Input.action_press(&"move_right")
	arena._physics_process(1.0 / 60.0)
	Input.action_release(&"move_right")
	assertions.expect_true(
		tutorial_simulation.player_position.x > 0.0
		and tutorial_simulation.player_position.y < 0.0,
		"tutorial movement receives camera-relative right movement",
	)
	assertions.expect_equal(
		0,
		tutorial_state.physics_tick,
		"tutorial movement remains on the move-only simulation path",
	)
	await _detach(arena, viewport, tree)


func _test_input_bindings(assertions: Variant) -> void:
	_assert_action_bindings(
		assertions,
		&"move_up",
		KEY_W,
		KEY_UP,
		JOY_BUTTON_DPAD_UP,
		JOY_AXIS_LEFT_Y,
		-1.0,
	)
	_assert_action_bindings(
		assertions,
		&"move_down",
		KEY_S,
		KEY_DOWN,
		JOY_BUTTON_DPAD_DOWN,
		JOY_AXIS_LEFT_Y,
		1.0,
	)
	_assert_action_bindings(
		assertions,
		&"move_left",
		KEY_A,
		KEY_LEFT,
		JOY_BUTTON_DPAD_LEFT,
		JOY_AXIS_LEFT_X,
		-1.0,
	)
	_assert_action_bindings(
		assertions,
		&"move_right",
		KEY_D,
		KEY_RIGHT,
		JOY_BUTTON_DPAD_RIGHT,
		JOY_AXIS_LEFT_X,
		1.0,
	)


func _assert_screen_direction(
	assertions: Variant,
	arena: ArenaPresenter,
	camera: Camera3D,
	screen_input: Vector2,
	expected_screen_direction: Vector2,
	label: String,
) -> void:
	var world_input: Vector2 = arena._camera_relative_move_input(screen_input)
	var screen_origin: Vector2 = camera.unproject_position(Vector3.ZERO)
	var screen_target: Vector2 = camera.unproject_position(
		Vector3(world_input.x, 0.0, world_input.y)
	)
	var projected_direction := (screen_target - screen_origin).normalized()
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
	assertions.expect_float(
		0.2,
		InputMap.action_get_deadzone(action),
		"%s keeps the gameplay deadzone" % action,
	)
	assertions.expect_true(
		_has_physical_key(action, letter_key),
		"%s includes its WASD key" % action,
	)
	assertions.expect_true(
		_has_physical_key(action, arrow_key),
		"%s includes its arrow key" % action,
	)
	assertions.expect_true(
		_has_joy_button(action, dpad_button),
		"%s includes its direction-pad button" % action,
	)
	assertions.expect_true(
		_has_joy_motion(action, stick_axis, stick_value),
		"%s includes its left-stick direction" % action,
	)


func _has_physical_key(action: StringName, physical_keycode: Key) -> bool:
	for event: InputEvent in InputMap.action_get_events(action):
		var key_event := event as InputEventKey
		if key_event != null and key_event.physical_keycode == physical_keycode:
			return true
	return false


func _has_joy_button(action: StringName, button: JoyButton) -> bool:
	for event: InputEvent in InputMap.action_get_events(action):
		var button_event := event as InputEventJoypadButton
		if button_event != null and button_event.button_index == button:
			return true
	return false


func _has_joy_motion(action: StringName, axis: JoyAxis, axis_value: float) -> bool:
	for event: InputEvent in InputMap.action_get_events(action):
		var motion_event := event as InputEventJoypadMotion
		if (
			motion_event != null
			and motion_event.axis == axis
			and is_equal_approx(motion_event.axis_value, axis_value)
		):
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
	Input.action_release(&"move_right")
	viewport.remove_child(arena)
	arena.free()
	tree.root.remove_child(viewport)
	viewport.free()
	await tree.process_frame
