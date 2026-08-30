extends RefCounted


const REWARD_SCENE: PackedScene = preload("res://scenes/ui/reward_reveal_screen.tscn")
const RESULT_SCENE: PackedScene = preload("res://scenes/ui/result_screen.tscn")


func test_names() -> PackedStringArray:
	return PackedStringArray([
		"reward_reveal_handles_items_and_legendary_prealert",
		"summary_lists_only_six_equipped_items_and_current_scores",
	])


func run_test(test_name: String, assertions: Variant, context: Dictionary) -> void:
	match test_name:
		"reward_reveal_handles_items_and_legendary_prealert":
			await _test_reward(assertions, context)
		"summary_lists_only_six_equipped_items_and_current_scores":
			await _test_summary(assertions, context)
		_:
			assertions.expect_true(false, "registered reward UI scenario test")


func _test_reward(assertions: Variant, context: Dictionary) -> void:
	var catalog := DefinitionCatalog.new()
	assertions.expect_true(catalog.load_and_validate(), "reward UI catalog valid")
	if not catalog.is_valid:
		return
	var fixture: Dictionary = QaScenarioFactory.build("reward_controls", catalog)
	assertions.expect_true(fixture.get("valid", false), "reward UI fixture valid")
	if not fixture.get("valid", false):
		return
	var screen: RewardRevealScreen = REWARD_SCENE.instantiate() as RewardRevealScreen
	screen.set_automatic_progression(false)
	screen.initialize(fixture["state"], catalog)
	var viewport: SubViewport = await _attach(screen, context["tree"])
	var audio_events: Array[StringName] = []
	screen.audio_event_requested.connect(func(event_id: StringName) -> void: audio_events.append(event_id))
	screen.test_press_reward_open_all_action()
	assertions.expect_true(screen.reveal_controller().is_prealert_active(), "open-all starts one aggregate high-rarity prealert")
	assertions.expect_float(0.75, float(screen.reveal_controller().presentation_state()["prealert_duration"]), "legendary uses current high-rarity prealert duration")
	screen.test_tick(0.75)
	assertions.expect_true(screen.reveal_controller().is_complete(), "all item rewards reveal after prealert")
	assertions.expect_true(&"legendary_prealert" in audio_events, "legendary audio path remains")
	assertions.expect_false(&"unique_prealert" in audio_events, "removed unique audio path never emits")
	var name_text: String = (screen.get_node("RootMargin/Content/Body/CurrentColumn/RewardSpeedProxy/CurrentCardFrame/CurrentCardMotion/CurrentCard/Margin/Content/CurrentName") as Label).text
	var detail_text: String = (screen.get_node("RootMargin/Content/Body/CurrentColumn/RewardSpeedProxy/CurrentCardFrame/CurrentCardMotion/CurrentCard/Margin/Content/CurrentDetails") as Label).text
	assertions.expect_false(name_text.contains("スキル"), "reward card never renders a skill reward")
	assertions.expect_false(detail_text.contains("ユニーク"), "reward details have no unique branch")
	assertions.expect_true(detail_text.contains("基礎ダメージ") or detail_text.contains("お守り"), "reward card shows the item's own performance")
	await _detach(screen, viewport, context["tree"])


func _test_summary(assertions: Variant, context: Dictionary) -> void:
	var catalog := DefinitionCatalog.new()
	assertions.expect_true(catalog.load_and_validate(), "summary catalog valid")
	if not catalog.is_valid:
		return
	var fixture: Dictionary = QaScenarioFactory.build("result_controller", catalog)
	assertions.expect_true(fixture.get("valid", false), "summary fixture valid")
	if not fixture.get("valid", false):
		return
	var screen: RunSummaryScreen = RESULT_SCENE.instantiate() as RunSummaryScreen
	screen.initialize(fixture["state"], catalog)
	var viewport: SubViewport = await _attach(screen, context["tree"])
	var debug: Dictionary = screen.debug_state()
	var build_text: String = str(debug["build_text"])
	for token: String in ["武器1", "武器2", "武器3", "お守り1", "お守り2", "お守り3"]:
		assertions.expect_true(build_text.contains(token), "summary lists %s" % token)
	for removed: String in ["スキル", "ユニーク", "ワイルド"]:
		assertions.expect_false(build_text.contains(removed), "summary omits %s" % removed)
	var score_text: String = str(debug["score_text"])
	assertions.expect_true(score_text.contains("装備中6枠"), "score names equipped-only source")
	assertions.expect_false(score_text.contains("保持装備"), "score no longer counts held inventory")
	assertions.expect_equal(int(debug["combat_score"]) + int(debug["final_build_score"]), int(debug["total"]), "summary score recomposes")
	await _detach(screen, viewport, context["tree"])


func _attach(screen: Control, tree: SceneTree) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	tree.root.add_child(viewport)
	viewport.add_child(screen)
	await tree.process_frame
	await tree.process_frame
	return viewport


func _detach(screen: Control, viewport: SubViewport, tree: SceneTree) -> void:
	viewport.remove_child(screen)
	screen.free()
	tree.root.remove_child(viewport)
	viewport.free()
	await tree.process_frame
