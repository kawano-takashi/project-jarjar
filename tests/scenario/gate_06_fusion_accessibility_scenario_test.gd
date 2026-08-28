extends RefCounted


const INVENTORY_SCENE: PackedScene = preload("res://scenes/ui/inventory_screen.tscn")
const COMBAT_HUD_SCENE: PackedScene = preload("res://scenes/ui/combat_hud.tscn")


func test_names() -> PackedStringArray:
	return PackedStringArray([
		"gate06_fusion_feedback_accessibility_contract",
		"gate06_combat_and_pickup_feedback_accessibility_contract",
	])


func run_test(test_name: String, assertions: Variant, context: Dictionary) -> void:
	match test_name:
		"gate06_fusion_feedback_accessibility_contract":
			await _test_fusion_feedback_accessibility(assertions, context)
		"gate06_combat_and_pickup_feedback_accessibility_contract":
			await _test_combat_and_pickup_feedback(assertions, context)
		_:
			assertions.expect_true(false, "registered Gate 6 fusion accessibility test")


func _test_fusion_feedback_accessibility(
	assertions: Variant,
	context: Dictionary,
) -> void:
	var catalog := DefinitionCatalog.new()
	assertions.expect_true(
		catalog.load_and_validate(),
		"Gate 6 fusion accessibility catalog valid: %s" % catalog.error_text,
	)
	if not catalog.is_valid:
		return
	var qa: Dictionary = QaScenarioFactory.build("inventory_controller", catalog)
	assertions.expect_true(qa.get("valid", false), "fusion accessibility fixture valid")
	if not qa.get("valid", false):
		return
	var state: RunState = qa["state"] as RunState
	var screen := INVENTORY_SCENE.instantiate() as InventoryScreen
	assertions.expect_true(screen != null, "fusion accessibility INVENTORY instantiates")
	if screen == null:
		return
	screen.initialize(state, catalog)
	var tree: SceneTree = context["tree"] as SceneTree
	tree.root.add_child(screen)
	await tree.process_frame


	await tree.process_frame

	var settings_store: Variant = context["settings_store"]
	var state_before: Dictionary = _state_observation(state)
	var cases: Array[Dictionary] = [
		{"label": "normal", "reduce_motion": false, "reduce_flashes": false},
		{"label": "Reduce Motion", "reduce_motion": true, "reduce_flashes": false},
		{"label": "Reduce Flashes", "reduce_motion": false, "reduce_flashes": true},
		{"label": "both reductions", "reduce_motion": true, "reduce_flashes": true},
	]
	for test_case: Dictionary in cases:
		var label: String = str(test_case["label"])
		var reduce_motion: bool = bool(test_case["reduce_motion"])
		var reduce_flashes: bool = bool(test_case["reduce_flashes"])
		settings_store.reduce_motion = reduce_motion
		settings_store.reduce_flashes = reduce_flashes
		screen.apply_command_result(&"fusion", {"success": true, "message": ""})
		var initial: Dictionary = screen.debug_state()
		assertions.expect_equal(
			InventoryScreen.FUSION_SUCCESS_FALLBACK_TEXT,
			initial["status"],
			"%s exposes a visible fusion-success message" % label,
		)
		assertions.expect_true(
			bool(initial["fusion_feedback_presented"]),
			"%s records fusion feedback presentation" % label,
		)
		assertions.expect_equal(
			reduce_motion,
			initial["fusion_feedback_reduce_motion"],
			"%s records Reduce Motion" % label,
		)
		assertions.expect_equal(
			reduce_flashes,
			initial["fusion_feedback_reduce_flashes"],
			"%s records Reduce Flashes" % label,
		)
		assertions.expect_equal(
			not reduce_motion,
			initial["fusion_feedback_motion_enabled"],
			"%s motion branch matches setting" % label,
		)
		assertions.expect_equal(
			not reduce_flashes,
			initial["fusion_feedback_flash_enabled"],
			"%s flash branch matches setting" % label,
		)
		assertions.expect_equal(
			reduce_flashes,
			initial["fusion_feedback_static_outline"],
			"%s static outline substitutes flash" % label,
		)
		assertions.expect_equal(
			InventoryScreen.FUSION_FEEDBACK_OUTLINE_SIZE if reduce_flashes else 0,
			initial["fusion_feedback_outline_size"],
			"%s outline thickness matches the static alternative" % label,
		)

		screen.test_tick_fusion_feedback(
			InventoryScreen.FUSION_FEEDBACK_DURATION_SECONDS * 0.5
		)
		var midpoint: Dictionary = screen.debug_state()
		if reduce_motion:
			assertions.expect_equal(
				Vector2.ONE,
				midpoint["fusion_feedback_status_scale"],
				"%s has no scale change" % label,
			)
		else:
			assertions.expect_not_equal(
				Vector2.ONE,
				midpoint["fusion_feedback_status_scale"],
				"%s runs the short scale pulse" % label,
			)
		var midpoint_modulate: Color = midpoint["fusion_feedback_status_modulate"] as Color
		if reduce_flashes:
			assertions.expect_equal(
				Color.WHITE,
				midpoint_modulate,
				"%s has no color or alpha pulse" % label,
			)
		else:
			assertions.expect_not_equal(
				Color.WHITE,
				midpoint_modulate,
				"%s runs the short color pulse" % label,
			)
		assertions.expect_float(
			1.0,
			midpoint_modulate.a,
			"%s never lowers success-message alpha" % label,
		)
		screen.test_tick_fusion_feedback(
			InventoryScreen.FUSION_FEEDBACK_DURATION_SECONDS * 0.5
		)
		var settled: Dictionary = screen.debug_state()
		assertions.expect_false(
			bool(settled["fusion_feedback_animating"]),
			"%s short pulse finishes after 0.4 seconds" % label,
		)
		assertions.expect_equal(
			Vector2.ONE,
			settled["fusion_feedback_status_scale"],
			"%s restores status scale after the pulse" % label,
		)
		assertions.expect_equal(
			Color.WHITE,
			settled["fusion_feedback_status_modulate"],
			"%s restores status color after the pulse" % label,
		)
		assertions.expect_equal(
			InventoryScreen.FUSION_FEEDBACK_OUTLINE_SIZE if reduce_flashes else 0,
			settled["fusion_feedback_outline_size"],
			"%s keeps only the static flash alternative" % label,
		)

	settings_store.reduce_motion = true
	settings_store.reduce_flashes = true
	screen.apply_command_result(
		&"fusion",
		{"success": true, "message": "既存の合成メッセージ"},
	)
	assertions.expect_equal(
		"既存の合成メッセージ",
		screen.debug_state()["status"],
		"non-empty fusion result wording is preserved exactly",
	)
	screen.apply_command_result(
		&"fusion",
		{"success": false, "error": &"invalid", "message": "合成できません"},
	)
	var failure: Dictionary = screen.debug_state()
	assertions.expect_equal("合成できません", failure["status"], "fusion failure wording is unchanged")
	assertions.expect_false(
		bool(failure["fusion_feedback_presented"]),
		"fusion failure does not present success feedback",
	)
	assertions.expect_equal(0, failure["fusion_feedback_outline_size"], "failure clears static outline")
	assertions.expect_equal(
		state_before,
		_state_observation(state),
		"fusion presentation changes no run, balance, serial, or RNG state",
	)

	settings_store.reduce_motion = false
	settings_store.reduce_flashes = false
	tree.root.remove_child(screen)
	screen.free()
	await tree.process_frame


func _test_combat_and_pickup_feedback(assertions: Variant, context: Dictionary) -> void:
	var hud := COMBAT_HUD_SCENE.instantiate() as CombatHud
	assertions.expect_true(hud != null, "combat feedback HUD instantiates")
	if hud == null:
		return
	var tree: SceneTree = context["tree"] as SceneTree
	tree.root.add_child(hud)
	await tree.process_frame

	assertions.expect_true(
		1.0 / CombatHud.MIN_FEEDBACK_DURATION_SECONDS < 3.0,
		"same-region feedback start rate stays strictly below three per second",
	)
	hud.present_damage(false, false)
	var initial: Dictionary = hud.debug_feedback_state()
	assertions.expect_true(bool(initial["visible"]), "damage feedback is visible")
	assertions.expect_equal(1, initial["pulse_start_count"], "first event starts one pulse")
	assertions.expect_float(0.72, float(initial["alpha"]), "normal feedback begins the one-shot fade")
	assertions.expect_equal(2, initial["outline_size"], "normal feedback uses the standard outline")

	for _index: int in range(10):
		hud.present_damage(false, false)
	var merged: Dictionary = hud.debug_feedback_state()
	assertions.expect_equal(
		1,
		merged["pulse_start_count"],
		"rapid same-region events merge instead of starting extra flashes",
	)
	assertions.expect_equal(10, merged["merged_event_count"], "every rapid event is coalesced")
	hud.test_tick_feedback(CombatHud.MIN_FEEDBACK_DURATION_SECONDS * 0.5)
	var midpoint: Dictionary = hud.debug_feedback_state()
	assertions.expect_true(
		float(midpoint["alpha"]) > 0.72,
		"normal feedback has one non-repeating brightness rise",
	)
	assertions.expect_true(
		(midpoint["scale"] as Vector2).x > 1.0,
		"normal feedback has one scale cue",
	)
	hud.test_tick_feedback(CombatHud.MIN_FEEDBACK_DURATION_SECONDS * 0.5)
	assertions.expect_false(
		bool(hud.debug_feedback_state()["visible"]),
		"damage feedback finishes after the minimum safe interval",
	)

	hud.present_pickup(3, true, true)
	var reduced: Dictionary = hud.debug_feedback_state()
	assertions.expect_equal("箱を自動回収 +3", reduced["text"], "chest absorption has visible feedback")
	assertions.expect_true(bool(reduced["reduce_motion"]), "pickup receives Reduce Motion")
	assertions.expect_true(bool(reduced["reduce_flashes"]), "pickup receives Reduce Flashes")
	assertions.expect_equal(
		CombatHud.REDUCED_FLASH_OUTLINE_SIZE,
		reduced["outline_size"],
		"Reduce Flashes substitutes a fixed outline",
	)
	hud.test_tick_feedback(0.20)
	var reduced_midpoint: Dictionary = hud.debug_feedback_state()
	assertions.expect_equal(Vector2.ONE, reduced_midpoint["scale"], "Reduce Motion removes scaling")
	assertions.expect_float(1.0, float(reduced_midpoint["alpha"]), "Reduce Flashes removes fading")

	tree.root.remove_child(hud)
	hud.free()
	await tree.process_frame


func _state_observation(state: RunState) -> Dictionary:
	return {
		"run_seed": state.run_seed,
		"phase": state.phase,
		"wave_number": state.wave_number,
		"fusion_count": state.fusion_count,
		"drop_serial": state.drop_serial,
		"combat_rng": state.rng_streams.combat_rng.state,
		"loot_rng": state.rng_streams.loot_rng.state,
		"fusion_rng": state.rng_streams.fusion_rng.state,
		"inventory_size": state.inventory.size(),
		"overflow_size": state.overflow.size(),
		"wild_material_count": state.wild_material_count,
	}
