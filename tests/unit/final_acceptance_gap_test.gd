extends RefCounted


const COMBAT_HUD_SCENE: PackedScene = preload("res://scenes/ui/combat_hud.tscn")


func test_names() -> PackedStringArray:
	return PackedStringArray([
		"arena_powerup_pool_caps_and_merges_without_losing_effects",
		"boss_hud_clock_continues_after_twenty_minutes",
		"segment_validator_rejects_incomplete_spawn_weight_shape",
	])


func run_test(test_name: String, assertions: Variant, context: Dictionary) -> void:
	match test_name:
		"arena_powerup_pool_caps_and_merges_without_losing_effects":
			_test_powerup_pool(assertions)
		"boss_hud_clock_continues_after_twenty_minutes":
			await _test_boss_hud_clock(assertions, context["tree"] as SceneTree)
		"segment_validator_rejects_incomplete_spawn_weight_shape":
			_test_segment_shape(assertions)
		_:
			assertions.expect_true(false, "registered final acceptance gap test")


func _test_powerup_pool(assertions: Variant) -> void:
	var catalog := DefinitionCatalog.new()
	assertions.expect_true(catalog.validate_manifest(BalanceTestFixtures.manifest()), "powerup pool catalog valid")
	if not catalog.is_valid:
		return
	var state: RunState = RunStateFactory.create(9401, catalog)
	state.current_hp = 0.0
	state.max_hp = 5000.0
	var objects := ArenaObjectSystem.new()
	objects.initialize(state, catalog)
	for index: int in range(ArenaObjectSystem.POWERUP_CAPACITY):
		objects._spawn_pickup(
			ArenaPickup.Kind.HEAL,
			Vector2.ZERO,
			index,
		)
	objects._spawn_pickup(ArenaPickup.Kind.HEAL, Vector2.ZERO, 100)
	objects._spawn_pickup(ArenaPickup.Kind.VACUUM, Vector2.ZERO, 101)
	objects._spawn_pickup(ArenaPickup.Kind.STOP, Vector2.ZERO, 102)
	assertions.expect_equal(32, objects.active_powerup_count(), "powerup active slots match renderer capacity")
	assertions.expect_equal(32, objects.powerup_transforms().size(), "all active powerup slots remain visible")
	assertions.expect_equal(35, objects.total_powerup_effect_count(), "overflow effects merge without loss")
	var collected: Array[ArenaPickup] = objects.collect_at(Vector2.ZERO)
	var vacuum_applied: bool = false
	for pickup: ArenaPickup in collected:
		var drop_type: GameTypes.NodeDropType = _drop_type_for_pickup(pickup.kind)
		var result: Dictionary = NodeDropService.apply_drop(state, catalog, drop_type)
		vacuum_applied = vacuum_applied or bool(result.get(&"vacuum", false))
	assertions.expect_float(990.0, state.current_hp, "all thirty-three stacked heals retain their numeric effect")
	assertions.expect_true(vacuum_applied, "stacked vacuum effect remains collectible")
	assertions.expect_equal(300, state.stop_until_tick, "stacked stop effect remains collectible")
	assertions.expect_equal(0, objects.active_powerup_count(), "collection returns all powerup slots to the free pool")
	for chest_index: int in range(4):
		objects.spawn_chest(Vector2(float(chest_index), 0.0), chest_index)
	for index: int in range(40):
		objects._spawn_pickup(
			ArenaPickup.Kind.HEAL,
			Vector2(10.0, 10.0),
			200 + index,
		)
	assertions.expect_equal(4, objects.chest_transforms().size(), "four permanent chests do not consume powerup slots")
	assertions.expect_equal(32, objects.powerup_transforms().size(), "uncollected powerups never exceed visible capacity")
	assertions.expect_equal(40, objects.total_powerup_effect_count(), "long-run powerup overflow remains lossless")


func _test_boss_hud_clock(assertions: Variant, tree: SceneTree) -> void:
	var hud: CombatHud = COMBAT_HUD_SCENE.instantiate() as CombatHud
	tree.root.add_child(hud)
	await tree.process_frame
	hud.update_from_values({
		"weapon_slot_count": 5,
		"passive_slot_count": 5,
		"time_seconds": 1265.0,
		"boss_active": true,
	})
	assertions.expect_equal("21:05  BOSS", hud.debug_state()["time"], "boss HUD reports real elapsed time after twenty minutes")
	hud.queue_free()
	await tree.process_frame


func _test_segment_shape(assertions: Variant) -> void:
	var canonical_catalog := DefinitionCatalog.new()
	assertions.expect_true(canonical_catalog.validate_manifest(BalanceTestFixtures.manifest()), "segment shape canonical catalog valid")
	if not canonical_catalog.is_valid:
		return
	var canonical: SurvivalContentManifest = canonical_catalog.manifest()
	var drift: SurvivalContentManifest = canonical.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as SurvivalContentManifest
	var copied_segments: Array[EnemySegmentDefinition] = []
	copied_segments.assign(canonical.segments)
	var truncated: EnemySegmentDefinition = canonical.segments[0].duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as EnemySegmentDefinition
	truncated.spawn_weights = PackedFloat32Array([0.7, 0.3, 0.0, 0.0])
	copied_segments[0] = truncated
	drift.segments = copied_segments
	var drift_catalog := DefinitionCatalog.new()
	assertions.expect_false(drift_catalog.validate_manifest(drift), "validator rejects a four-entry segment weight array")
	assertions.expect_true(
		drift_catalog.error_text.contains("spawn_weights") and drift_catalog.error_text.contains("6 weights"),
		"segment shape rejection is specific",
	)


func _drop_type_for_pickup(kind: ArenaPickup.Kind) -> GameTypes.NodeDropType:
	match kind:
		ArenaPickup.Kind.HEAL:
			return GameTypes.NodeDropType.HEAL
		ArenaPickup.Kind.VACUUM:
			return GameTypes.NodeDropType.VACUUM
		ArenaPickup.Kind.STOP:
			return GameTypes.NodeDropType.STOP
	return GameTypes.NodeDropType.NONE
