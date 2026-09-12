extends RefCounted


const COMBAT_HUD_SCENE: PackedScene = preload("res://scenes/ui/combat_hud.tscn")


func test_powerups_persist_at_their_drop_sites_beyond_render_capacity(a: Variant, _context: Dictionary) -> void:
	var catalog: DefinitionCatalog = BalanceTestFixtures.catalog()
	var state: RunState = RunStateFactory.create(9401, catalog)
	var objects := ArenaObjectSystem.new()
	objects.initialize(state, catalog)
	for index: int in 80:
		objects._spawn_pickup(ArenaPickup.Kind.HEAL, Vector2(index * 5.0, 50), index)
	a.expect_equal(80, objects.active_powerup_count(), "every uncollected powerup remains independent")
	a.expect_equal(80, objects.powerup_transforms().size(), "render input includes every active powerup")
	var collected: Array[ArenaPickup] = objects.collect_at(Vector2(200, 50))
	a.expect_equal(1, collected.size(), "collection does not pull effects from other drop sites")
	a.expect_equal(40, collected[0].source_serial, "the original pickup is collected")
	objects.shift_origin(Vector2(1024, 0))
	collected = objects.collect_at(Vector2(395 - 1024, 50))
	a.expect_equal(1, collected.size(), "a distant pickup remains collectible after an origin shift")
	a.expect_equal(79, collected[0].source_serial, "origin changes preserve pickup identity")
	objects.spawn_chest(Vector2.ZERO, 0)
	a.expect_equal(78, objects.active_powerup_count(), "chests do not consume or merge powerups")


func test_boss_hud_clock_continues_after_fifteen_minutes(assertions: Variant, context: Dictionary) -> void:
	var tree: SceneTree = context["tree"]
	var hud: CombatHud = COMBAT_HUD_SCENE.instantiate() as CombatHud
	tree.root.add_child(hud)
	await tree.process_frame
	hud.update_from_values({
		"weapon_slot_count": 5,
		"passive_slot_count": 5,
		"time_seconds": 965.0,
		"boss_active": true,
	})
	assertions.expect_true(str(hud.debug_state()["time"]).contains("16:05"), "boss HUD reports real elapsed time after fifteen minutes")
	hud.queue_free()
	await tree.process_frame


func test_segment_validator_rejects_incomplete_spawn_weight_shape(assertions: Variant, _context: Dictionary) -> void:
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
