extends RefCounted


const ARENA_SCENE: PackedScene = preload("res://scenes/gameplay/arena_combat.tscn")
const SCREEN_DIRECTION_DOT_MINIMUM: float = 0.9999


func test_camera_relative_movement_matches_view(assertions: Variant, context: Dictionary) -> void:
	var tree: SceneTree = context["tree"]
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
		assertions.expect_true(arena.view.world_to_screen_input(arena.camera_relative_move_input(analog_input)).is_equal_approx(analog_input), "bot and player movement mappings are inverse operations")
	await _detach(arena, viewport, tree)


func test_camera_keeps_combat_envelope_visible_while_following(assertions: Variant, context: Dictionary) -> void:
	var tree: SceneTree = context["tree"]
	var arena := ARENA_SCENE.instantiate() as ArenaPresenter
	var viewport: SubViewport = await _attach(arena, tree)
	var camera := arena.get_node("%ArenaCamera") as Camera3D
	var move_speed: float = BalanceTestFixtures.catalog().manifest().player.move_speed
	for dimensions: Vector2i in [Vector2i(1920, 1080), Vector2i(1280, 720), Vector2i(1024, 768)]:
		viewport.size = dimensions
		await tree.process_frame
		for direction_index: int in 8:
			var direction := Vector2.from_angle(TAU * float(direction_index) / 8.0)
			var player := Vector2.ZERO
			arena.view.reset(player)
			for _tick: int in 120:
				player += direction * move_speed / 60.0
				arena.view.viewport_size = dimensions
				arena.view.advance(player, 1.0 / 60.0)
				arena._update_camera()
			var visible: bool = true
			for sample: int in 72:
				var point: Vector2 = player + Vector2.from_angle(TAU * float(sample) / 72.0) * 10.0
				visible = visible and camera.is_position_in_frustum(Vector3(point.x, 0.0, point.y))
			assertions.expect_true(visible, "the ten-metre ground radius remains visible after movement follow lag at %s, direction %d" % [dimensions, direction_index])
	await _detach(arena, viewport, tree)


func test_ground_revisits_and_rendering_share_the_simulation_camera(a: Variant, context: Dictionary) -> void:
	var tree: SceneTree = context["tree"]
	var catalog: DefinitionCatalog = BalanceTestFixtures.catalog()
	var simulation := CombatSimulation.new()
	simulation.initialize(RunStateFactory.create(17, catalog), catalog)
	var arena := ARENA_SCENE.instantiate() as ArenaPresenter
	arena.initialize(simulation)
	var viewport: SubViewport = await _attach(arena, tree)
	a.expect_true(arena.view == simulation.view, "rendering uses the simulation's camera")
	var original_chunk: Vector2i = arena._ground._chunks.keys()[0]
	var layout: Dictionary = arena._ground._chunks[original_chunk].duplicate(true)
	simulation.player_position = Vector2(1023.99, -1023.99)
	simulation.view.reset(simulation.player_position)
	simulation.state.weapons.clear()
	simulation.advance_tick(Vector2(1, -1))
	var before: Transform3D = simulation.view.camera_transform
	arena.present_snapshot(simulation.build_snapshot(), 1.0 / 60.0)
	arena.present_snapshot(simulation.build_snapshot(), 1.0 / 60.0)
	a.expect_equal(before, simulation.view.camera_transform, "repeated presentation never advances camera follow")
	a.expect_equal(Vector2i(1, -1), simulation.world_origin, "a long move rebases both axes in 1024m steps")
	a.expect_true(simulation.last_player_displacement.length() < 0.1, "distance measurement excludes origin changes")
	a.expect_false(arena._ground._chunks.has(original_chunk), "distant chunks are discarded from rendering")
	simulation.player_position = -Vector2(simulation.world_origin) * CombatSimulation.ORIGIN_STEP_METERS
	simulation.view.reset(simulation.player_position)
	simulation.advance_tick(Vector2.ZERO)
	arena.present_snapshot(simulation.build_snapshot(), 1.0 / 60.0)
	a.expect_equal(layout, arena._ground._chunks[original_chunk], "returning to a chunk restores its landmarks")
	a.expect_true(arena._ground._chunks.size() < 100, "ground storage stays local after a long move and return")
	simulation.set_viewport_size(Vector2i(1024, 768))
	a.expect_equal(Vector2i(1024, 768), arena.view.viewport_size, "viewport changes reach the same camera model")
	simulation.state.phase = GameTypes.RunPhase.LEVEL_UP
	var paused_camera: Transform3D = simulation.view.camera_transform
	a.expect_false(simulation.advance_tick(Vector2.RIGHT), "selection screens do not advance the shared camera")
	a.expect_equal(paused_camera, arena.view.camera_transform, "resizing a paused view does not move its camera")
	await _detach(arena, viewport, tree)


func test_gameplay_movement_input_bindings(assertions: Variant, _context: Dictionary) -> void:
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
