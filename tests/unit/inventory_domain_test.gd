extends RefCounted


const FusionCommitServiceScript := preload(
	"res://src/inventory/fusion_commit_service.gd"
)
const GameAppScript := preload("res://src/app/game_app.gd")
const InventoryServiceScript := preload(
	"res://src/inventory/inventory_service.gd"
)
const RewardApplicationServiceScript := preload(
	"res://src/inventory/reward_application_service.gd"
)
const RunStateFactoryScript := preload("res://src/core/run_state_factory.gd")
const RunStateMachineScript := preload("res://src/core/run_state_machine.gd")
const ScoreServiceScript := preload("res://src/core/score_service.gd")
const SkillEquipServiceScript := preload(
	"res://src/skills/skill_equip_service.gd"
)

var _catalog: DefinitionCatalog = null


func test_names() -> PackedStringArray:
	return PackedStringArray([
		"inventory_capacity_order_and_refill_contract",
		"inventory_move_validation_contract",
		"inventory_rarity_sort_stability_and_isolation_contract",
		"equipment_move_and_unique_side_effect_contract",
		"lock_compare_select_and_discard_contract",
		"reward_skill_wild_and_autoequip_contract",
		"reward_unique_invariant_contract",
		"fusion_preview_commit_and_protection_contract",
		"skill_move_snapshot_and_crown_contract",
		"score_w8_and_retry_contract",
		"w8_reward_inventory_fusion_result_contract",
	])


func run_test(test_name: String, assertions: Variant, _context: Dictionary) -> void:
	match test_name:
		"inventory_capacity_order_and_refill_contract":
			_test_inventory_capacity_order_and_refill(assertions)
		"inventory_move_validation_contract":
			_test_inventory_move_validation(assertions)
		"inventory_rarity_sort_stability_and_isolation_contract":
			_test_inventory_rarity_sort_stability_and_isolation(assertions)
		"equipment_move_and_unique_side_effect_contract":
			_test_equipment_move_and_unique_side_effect(assertions)
		"lock_compare_select_and_discard_contract":
			_test_lock_compare_select_and_discard(assertions)
		"reward_skill_wild_and_autoequip_contract":
			_test_reward_skill_wild_and_autoequip(assertions)
		"reward_unique_invariant_contract":
			_test_reward_unique_invariant(assertions)
		"fusion_preview_commit_and_protection_contract":
			_test_fusion_preview_commit_and_protection(assertions)
		"skill_move_snapshot_and_crown_contract":
			_test_skill_move_snapshot_and_crown(assertions)
		"score_w8_and_retry_contract":
			_test_score_w8_and_retry(assertions)
		"w8_reward_inventory_fusion_result_contract":
			_test_w8_reward_inventory_fusion_result(assertions)
		_:
			assertions.expect_true(false, "registered inventory inventory-domain test")


func _test_inventory_capacity_order_and_refill(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _loaded_catalog(assertions)
	if catalog == null:
		return
	var state: RunState = _new_state(501, catalog)
	for item_index: int in range(40):
		var item: ItemInstance = _item(
			"capacity-%02d" % item_index,
			GameTypes.EquipmentSlot.HANDS,
			GameTypes.Rarity.COMMON,
		)
		var insertion: Dictionary = InventoryServiceScript.insert_item(state, item)
		assertions.expect_true(bool(insertion["success"]), "capacity item inserts %02d" % item_index)
		if item_index < RunState.INVENTORY_CAPACITY:
			assertions.expect_equal(
				InventoryServiceScript.KIND_INVENTORY,
				insertion["kind"],
				"first 36 items enter inventory",
			)
			assertions.expect_equal(item_index, insertion["index"], "inventory uses lowest empty index")
		else:
			assertions.expect_equal(
				InventoryServiceScript.KIND_OVERFLOW,
				insertion["kind"],
				"items past 36 enter overflow",
			)
			assertions.expect_equal(item_index - 36, insertion["index"], "overflow appends stably")
	assertions.expect_equal(36, state.inventory.size(), "inventory remains a fixed 36-slot array")
	assertions.expect_equal(
		PackedStringArray(["capacity-36", "capacity-37", "capacity-38", "capacity-39"]),
		_item_ids(state.overflow),
		"overflow preserves public insertion order",
	)

	state.inventory[5] = null
	assertions.expect_equal(1, InventoryServiceScript.refill_from_overflow(state), "one gap refilled")
	assertions.expect_equal("capacity-36", state.inventory[5].item_id, "oldest overflow enters lowest gap")
	assertions.expect_equal(
		PackedStringArray(["capacity-37", "capacity-38", "capacity-39"]),
		_item_ids(state.overflow),
		"refill shifts dense overflow without sorting",
	)

	var overflow_swap: Dictionary = InventoryServiceScript.apply_move(
		state,
		InventoryServiceScript.KIND_OVERFLOW,
		0,
		InventoryServiceScript.KIND_INVENTORY,
		10,
	)
	assertions.expect_true(bool(overflow_swap["success"]), "full inventory accepts overflow swap")
	assertions.expect_equal("capacity-37", state.inventory[10].item_id, "overflow item takes target slot")
	assertions.expect_equal("capacity-10", state.overflow[0].item_id, "displaced item replaces same overflow index")
	assertions.expect_equal("capacity-38", state.overflow[1].item_id, "following overflow index remains stable")
	var overflow_before: PackedStringArray = _item_ids(state.overflow)
	var reorder: Dictionary = InventoryServiceScript.apply_move(
		state,
		InventoryServiceScript.KIND_OVERFLOW,
		0,
		InventoryServiceScript.KIND_OVERFLOW,
		1,
	)
	assertions.expect_false(bool(reorder["success"]), "manual overflow-to-overflow reorder rejected")
	assertions.expect_equal(&"overflow_reorder", reorder["error"], "overflow reorder error is stable")
	assertions.expect_equal(overflow_before, _item_ids(state.overflow), "rejected reorder is state invariant")


func _test_inventory_move_validation(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _loaded_catalog(assertions)
	if catalog == null:
		return
	_assert_move_validation(
		assertions,
		null,
		InventoryServiceScript.KIND_INVENTORY,
		0,
		InventoryServiceScript.KIND_INVENTORY,
		1,
		false,
		&"invalid_state",
		"インベントリ状態が不正です",
		"null state",
	)

	var invalid_source: RunState = _new_state(520, catalog)
	_assert_move_validation(
		assertions,
		invalid_source,
		InventoryServiceScript.KIND_INVENTORY,
		0,
		InventoryServiceScript.KIND_INVENTORY,
		1,
		false,
		&"invalid_source",
		"移動元が不正です",
		"empty inventory source",
	)

	var invalid_target: RunState = _new_state(521, catalog)
	invalid_target.inventory[0] = _item(
		"validation-source",
		GameTypes.EquipmentSlot.HEAD,
		GameTypes.Rarity.COMMON,
	)
	_assert_move_validation(
		assertions,
		invalid_target,
		InventoryServiceScript.KIND_INVENTORY,
		0,
		InventoryServiceScript.KIND_INVENTORY,
		RunState.INVENTORY_CAPACITY,
		false,
		&"invalid_target",
		"移動先が不正です",
		"out-of-range target",
	)

	var main_same: RunState = _new_state(522, catalog)
	_assert_move_validation(
		assertions,
		main_same,
		InventoryServiceScript.KIND_EQUIPPED,
		GameTypes.EquipmentSlot.MAIN_WEAPON,
		InventoryServiceScript.KIND_EQUIPPED,
		GameTypes.EquipmentSlot.MAIN_WEAPON,
		false,
		&"main_weapon_required",
		InventoryServiceScript.MAIN_WEAPON_REQUIRED_MESSAGE,
		"main weapon same-slot unequip",
	)

	var main_to_empty: RunState = _new_state(523, catalog)
	_assert_move_validation(
		assertions,
		main_to_empty,
		InventoryServiceScript.KIND_EQUIPPED,
		GameTypes.EquipmentSlot.MAIN_WEAPON,
		InventoryServiceScript.KIND_INVENTORY,
		0,
		false,
		&"main_weapon_required",
		InventoryServiceScript.MAIN_WEAPON_REQUIRED_MESSAGE,
		"main weapon to empty storage",
	)

	var equipped_to_equipped: RunState = _new_state(524, catalog)
	equipped_to_equipped.equipped[GameTypes.EquipmentSlot.HEAD] = _item(
		"validation-equipped-head",
		GameTypes.EquipmentSlot.HEAD,
		GameTypes.Rarity.COMMON,
	)
	_assert_move_validation(
		assertions,
		equipped_to_equipped,
		InventoryServiceScript.KIND_EQUIPPED,
		GameTypes.EquipmentSlot.HEAD,
		InventoryServiceScript.KIND_EQUIPPED,
		GameTypes.EquipmentSlot.BODY,
		false,
		&"incompatible_slot",
		"別の装備枠へは移動できません",
		"different equipment slots",
	)

	var wrong_equipment_slot: RunState = _new_state(525, catalog)
	wrong_equipment_slot.inventory[0] = _item(
		"validation-storage-head",
		GameTypes.EquipmentSlot.HEAD,
		GameTypes.Rarity.COMMON,
	)
	_assert_move_validation(
		assertions,
		wrong_equipment_slot,
		InventoryServiceScript.KIND_INVENTORY,
		0,
		InventoryServiceScript.KIND_EQUIPPED,
		GameTypes.EquipmentSlot.BODY,
		false,
		&"incompatible_slot",
		"対応する装備枠へだけ装備できます",
		"storage item to wrong equipment slot",
	)

	var wrong_exchange_item: RunState = _new_state(526, catalog)
	wrong_exchange_item.equipped[GameTypes.EquipmentSlot.HEAD] = _item(
		"validation-head-source",
		GameTypes.EquipmentSlot.HEAD,
		GameTypes.Rarity.COMMON,
	)
	wrong_exchange_item.inventory[0] = _item(
		"validation-body-target",
		GameTypes.EquipmentSlot.BODY,
		GameTypes.Rarity.COMMON,
	)
	_assert_move_validation(
		assertions,
		wrong_exchange_item,
		InventoryServiceScript.KIND_EQUIPPED,
		GameTypes.EquipmentSlot.HEAD,
		InventoryServiceScript.KIND_INVENTORY,
		0,
		false,
		&"incompatible_slot",
		"交換先の装備種別が一致しません",
		"equipped item to incompatible exchange item",
	)

	var overflow_reorder: RunState = _new_state(527, catalog)
	overflow_reorder.overflow.append(_item(
		"validation-overflow-a",
		GameTypes.EquipmentSlot.HANDS,
		GameTypes.Rarity.COMMON,
	))
	overflow_reorder.overflow.append(_item(
		"validation-overflow-b",
		GameTypes.EquipmentSlot.FEET,
		GameTypes.Rarity.COMMON,
	))
	_assert_move_validation(
		assertions,
		overflow_reorder,
		InventoryServiceScript.KIND_OVERFLOW,
		0,
		InventoryServiceScript.KIND_OVERFLOW,
		1,
		false,
		&"overflow_reorder",
		"一時受取欄内では並べ替えできません",
		"overflow reorder",
	)

	var compatible_equip: RunState = _new_state(528, catalog)
	compatible_equip.inventory[0] = _item(
		"validation-compatible-head",
		GameTypes.EquipmentSlot.HEAD,
		GameTypes.Rarity.COMMON,
	)
	_assert_move_validation(
		assertions,
		compatible_equip,
		InventoryServiceScript.KIND_INVENTORY,
		0,
		InventoryServiceScript.KIND_EQUIPPED,
		GameTypes.EquipmentSlot.HEAD,
		true,
		&"",
		"",
		"compatible equipment placement",
	)

	var compatible_unequip: RunState = _new_state(529, catalog)
	compatible_unequip.equipped[GameTypes.EquipmentSlot.HEAD] = _item(
		"validation-unequip-head",
		GameTypes.EquipmentSlot.HEAD,
		GameTypes.Rarity.COMMON,
	)
	_assert_move_validation(
		assertions,
		compatible_unequip,
		InventoryServiceScript.KIND_EQUIPPED,
		GameTypes.EquipmentSlot.HEAD,
		InventoryServiceScript.KIND_EQUIPPED,
		GameTypes.EquipmentSlot.HEAD,
		true,
		&"",
		"",
		"non-main same-slot unequip",
	)

	var compatible_main_exchange: RunState = _new_state(530, catalog)
	compatible_main_exchange.inventory[0] = _item(
		"validation-main-exchange",
		GameTypes.EquipmentSlot.MAIN_WEAPON,
		GameTypes.Rarity.COMMON,
		GameTypes.MainWeaponType.BOW,
	)
	_assert_move_validation(
		assertions,
		compatible_main_exchange,
		InventoryServiceScript.KIND_EQUIPPED,
		GameTypes.EquipmentSlot.MAIN_WEAPON,
		InventoryServiceScript.KIND_INVENTORY,
		0,
		true,
		&"",
		"",
		"main weapon exchange",
	)


func _test_inventory_rarity_sort_stability_and_isolation(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _loaded_catalog(assertions)
	if catalog == null:
		return
	var state: RunState = _new_state(509, catalog)
	var common_a: ItemInstance = _item(
		"sort-common-a",
		GameTypes.EquipmentSlot.HANDS,
		GameTypes.Rarity.COMMON,
	)
	var rare_a: ItemInstance = _item(
		"sort-rare-a",
		GameTypes.EquipmentSlot.HEAD,
		GameTypes.Rarity.RARE,
	)
	var legendary_a: ItemInstance = _item(
		"sort-legendary-a",
		GameTypes.EquipmentSlot.BODY,
		GameTypes.Rarity.LEGENDARY,
	)
	var epic_unique: ItemInstance = _item(
		"sort-unique",
		GameTypes.EquipmentSlot.SUB_WEAPON,
		GameTypes.Rarity.UNIQUE,
		GameTypes.MainWeaponType.UNCLASSIFIED,
		&"bloodied_dagger",
	)
	var common_b: ItemInstance = _item(
		"sort-common-b",
		GameTypes.EquipmentSlot.FEET,
		GameTypes.Rarity.COMMON,
	)
	var epic_b: ItemInstance = _item(
		"sort-epic-b",
		GameTypes.EquipmentSlot.MAIN_WEAPON,
		GameTypes.Rarity.EPIC,
		GameTypes.MainWeaponType.BOW,
	)
	var legendary_locked: ItemInstance = _item(
		"sort-legendary-locked",
		GameTypes.EquipmentSlot.HANDS,
		GameTypes.Rarity.LEGENDARY,
		GameTypes.MainWeaponType.UNCLASSIFIED,
		&"",
		true,
	)
	var rare_b: ItemInstance = _item(
		"sort-rare-b",
		GameTypes.EquipmentSlot.BODY,
		GameTypes.Rarity.RARE,
	)
	state.inventory[0] = common_a
	state.inventory[1] = rare_a
	state.inventory[3] = legendary_a
	state.inventory[4] = epic_unique
	state.inventory[5] = common_b
	state.inventory[7] = epic_b
	state.inventory[8] = legendary_locked
	state.inventory[11] = rare_b
	state.overflow.append(_item(
		"sort-overflow-common",
		GameTypes.EquipmentSlot.HEAD,
		GameTypes.Rarity.COMMON,
	))
	state.overflow.append(_item(
		"sort-overflow-legendary",
		GameTypes.EquipmentSlot.FEET,
		GameTypes.Rarity.LEGENDARY,
	))

	var overflow_before: PackedStringArray = _item_ids(state.overflow)
	var overflow_first_before: ItemInstance = state.overflow[0]
	var equipped_before: ItemInstance = state.equipped[GameTypes.EquipmentSlot.MAIN_WEAPON]
	var rng_before: Dictionary = _rng_snapshot(state)
	var drop_serial_before: int = state.drop_serial
	var score_before: Dictionary = state.score_breakdown.duplicate(true)
	var result: Dictionary = InventoryServiceScript.sort_inventory_by_rarity(state)
	assertions.expect_true(bool(result["success"]), "rarity sort succeeds")
	assertions.expect_equal(&"", result["error"], "rarity sort has no error")
	assertions.expect_equal(
		InventoryServiceScript.SORT_COMPLETE_MESSAGE,
		result["message"],
		"rarity sort exposes the exact completion message",
	)
	assertions.expect_false(bool(result["no_op"]), "first rarity sort changes interleaved slots")

	var expected_ids := PackedStringArray([
		"sort-unique",
		"sort-legendary-a",
		"sort-legendary-locked",
		"sort-epic-b",
		"sort-rare-a",
		"sort-rare-b",
		"sort-common-a",
		"sort-common-b",
	])
	while expected_ids.size() < RunState.INVENTORY_CAPACITY:
		expected_ids.append("<null>")
	assertions.expect_equal(
		expected_ids,
		_inventory_ids(state),
		"rarity sort is descending, stable, and compacts empty slots",
	)
	assertions.expect_true(state.inventory[0] == epic_unique, "rarity sort preserves the exact Unique item reference")
	assertions.expect_true(legendary_locked.locked, "rarity sort preserves lock state")
	assertions.expect_equal(&"bloodied_dagger", epic_unique.unique_id, "rarity sort preserves unique identity")
	assertions.expect_equal(overflow_before, _item_ids(state.overflow), "rarity sort leaves overflow order unchanged")
	assertions.expect_true(state.overflow[0] == overflow_first_before, "rarity sort preserves overflow references")
	assertions.expect_true(
		state.equipped[GameTypes.EquipmentSlot.MAIN_WEAPON] == equipped_before,
		"rarity sort leaves equipped items unchanged",
	)
	assertions.expect_equal(rng_before, _rng_snapshot(state), "rarity sort consumes no RNG")
	assertions.expect_equal(drop_serial_before, state.drop_serial, "rarity sort consumes no drop serial")
	assertions.expect_equal(score_before, state.score_breakdown, "rarity sort changes no score")

	var sorted_before: PackedStringArray = _inventory_ids(state)
	var repeated: Dictionary = InventoryServiceScript.sort_inventory_by_rarity(state)
	assertions.expect_true(bool(repeated["success"]), "repeated rarity sort succeeds")
	assertions.expect_true(bool(repeated["no_op"]), "repeated rarity sort reports no-op")
	assertions.expect_equal(
		InventoryServiceScript.SORT_COMPLETE_MESSAGE,
		repeated["message"],
		"repeated rarity sort keeps the same completion message",
	)
	assertions.expect_equal(sorted_before, _inventory_ids(state), "repeated rarity sort is idempotent")

	var invalid_state: RunState = _new_state(510, catalog)
	invalid_state.inventory[0] = common_a
	invalid_state.inventory.resize(RunState.INVENTORY_CAPACITY - 1)
	var invalid_before: PackedStringArray = _inventory_ids(invalid_state)
	var rejected: Dictionary = InventoryServiceScript.sort_inventory_by_rarity(invalid_state)
	assertions.expect_false(bool(rejected["success"]), "structurally invalid inventory sort fails")
	assertions.expect_equal(&"invalid_state", rejected["error"], "invalid inventory sort error is stable")
	assertions.expect_equal(invalid_before, _inventory_ids(invalid_state), "invalid inventory sort changes no slot")


func _test_equipment_move_and_unique_side_effect(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _loaded_catalog(assertions)
	if catalog == null:
		return
	var state: RunState = _new_state(502, catalog)
	var wood: ItemInstance = state.equipped[GameTypes.EquipmentSlot.MAIN_WEAPON]
	var bow: ItemInstance = _item(
		"main-bow",
		GameTypes.EquipmentSlot.MAIN_WEAPON,
		GameTypes.Rarity.COMMON,
		GameTypes.MainWeaponType.BOW,
	)
	state.inventory[0] = bow
	var equip_bow: Dictionary = InventoryServiceScript.apply_move(
		state,
		InventoryServiceScript.KIND_INVENTORY,
		0,
		InventoryServiceScript.KIND_EQUIPPED,
		GameTypes.EquipmentSlot.MAIN_WEAPON,
	)
	assertions.expect_true(bool(equip_bow["success"]), "compatible main weapon equips")
	assertions.expect_equal(bow, state.equipped[GameTypes.EquipmentSlot.MAIN_WEAPON], "new main weapon equipped")
	assertions.expect_equal(wood, state.inventory[0], "old main weapon returns to exact source slot")

	var main_unequip: Dictionary = InventoryServiceScript.unequip(
		state,
		GameTypes.EquipmentSlot.MAIN_WEAPON,
	)
	assertions.expect_false(bool(main_unequip["success"]), "main weapon standalone unequip rejected")
	assertions.expect_equal(&"main_weapon_required", main_unequip["error"], "main weapon error code")
	assertions.expect_equal(
		InventoryServiceScript.MAIN_WEAPON_REQUIRED_MESSAGE,
		main_unequip["message"],
		"main weapon rejection text is exact",
	)
	var main_to_empty: Dictionary = InventoryServiceScript.apply_move(
		state,
		InventoryServiceScript.KIND_EQUIPPED,
		GameTypes.EquipmentSlot.MAIN_WEAPON,
		InventoryServiceScript.KIND_INVENTORY,
		1,
	)
	assertions.expect_false(bool(main_to_empty["success"]), "dragging main weapon to empty storage rejected")
	assertions.expect_equal(bow, state.equipped[GameTypes.EquipmentSlot.MAIN_WEAPON], "rejection keeps main non-null")
	var swap_main: Dictionary = InventoryServiceScript.apply_move(
		state,
		InventoryServiceScript.KIND_EQUIPPED,
		GameTypes.EquipmentSlot.MAIN_WEAPON,
		InventoryServiceScript.KIND_INVENTORY,
		0,
	)
	assertions.expect_true(bool(swap_main["success"]), "main weapon can exchange with another main weapon")
	assertions.expect_equal(wood, state.equipped[GameTypes.EquipmentSlot.MAIN_WEAPON], "main exchange uses target item")
	assertions.expect_equal(bow, state.inventory[0], "exchanged main returns to target slot")

	var head: ItemInstance = _item(
		"plain-head",
		GameTypes.EquipmentSlot.HEAD,
		GameTypes.Rarity.COMMON,
	)
	state.inventory[2] = head
	assertions.expect_true(bool(InventoryServiceScript.apply_move(
		state,
		InventoryServiceScript.KIND_INVENTORY,
		2,
		InventoryServiceScript.KIND_EQUIPPED,
		GameTypes.EquipmentSlot.HEAD,
	)["success"]), "non-main item equips into a compatible empty slot")
	var head_unequip: Dictionary = InventoryServiceScript.unequip(state, GameTypes.EquipmentSlot.HEAD)
	assertions.expect_true(bool(head_unequip["success"]), "non-main standalone unequip succeeds")
	assertions.expect_equal(1, head_unequip["target_index"], "unequip uses lowest inventory gap")
	assertions.expect_equal(head, state.inventory[1], "unequipped item occupies reported gap")

	var echo: ItemInstance = _item(
		"echo-hands",
		GameTypes.EquipmentSlot.HANDS,
		GameTypes.Rarity.UNIQUE,
		GameTypes.MainWeaponType.UNCLASSIFIED,
		&"echo_gauntlet",
	)
	state.inventory[3] = echo
	InventoryServiceScript.apply_move(
		state,
		InventoryServiceScript.KIND_INVENTORY,
		3,
		InventoryServiceScript.KIND_EQUIPPED,
		GameTypes.EquipmentSlot.HANDS,
	)
	assertions.expect_equal(echo.item_id, state.echo_progress_item_id, "echo equip starts tracking exact item")
	assertions.expect_equal(0, state.echo_primary_attack_progress, "echo equip resets progress")
	state.echo_primary_attack_progress = 2
	var plain_hands: ItemInstance = _item(
		"plain-hands",
		GameTypes.EquipmentSlot.HANDS,
		GameTypes.Rarity.COMMON,
	)
	state.inventory[4] = plain_hands
	InventoryServiceScript.apply_move(
		state,
		InventoryServiceScript.KIND_INVENTORY,
		4,
		InventoryServiceScript.KIND_EQUIPPED,
		GameTypes.EquipmentSlot.HANDS,
	)
	assertions.expect_equal("", state.echo_progress_item_id, "echo exchange clears tracked item")
	assertions.expect_equal(0, state.echo_primary_attack_progress, "echo exchange clears progress")

	state.skill_library[&"starfall"] = _skill(&"starfall", 1, 0)
	state.skill_library[&"thousand_blades"] = _skill(&"thousand_blades", 1, 1)
	var crown: ItemInstance = _item(
		"crown-head",
		GameTypes.EquipmentSlot.HEAD,
		GameTypes.Rarity.UNIQUE,
		GameTypes.MainWeaponType.UNCLASSIFIED,
		&"hollow_crown",
	)
	state.inventory[5] = crown
	InventoryServiceScript.apply_move(
		state,
		InventoryServiceScript.KIND_INVENTORY,
		5,
		InventoryServiceScript.KIND_EQUIPPED,
		GameTypes.EquipmentSlot.HEAD,
	)
	assertions.expect_equal(-1, state.skill_library[&"thousand_blades"].equipped_slot, "crown returns slot 1 skill to library")
	assertions.expect_true(SkillEquipServiceScript.is_slot_sealed(state, 1), "crown seals second skill slot")


func _test_lock_compare_select_and_discard(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _loaded_catalog(assertions)
	if catalog == null:
		return
	var state: RunState = _new_state(503, catalog)
	state.equipped[GameTypes.EquipmentSlot.MAIN_WEAPON] = _item(
		"equipped-bow",
		GameTypes.EquipmentSlot.MAIN_WEAPON,
		GameTypes.Rarity.COMMON,
		GameTypes.MainWeaponType.BOW,
	)
	var equipped_head: ItemInstance = _item(
		"equipped-head",
		GameTypes.EquipmentSlot.HEAD,
		GameTypes.Rarity.COMMON,
		GameTypes.MainWeaponType.UNCLASSIFIED,
		&"",
		false,
		[_affix(&"max_hp", 10.0)],
	)
	state.equipped[GameTypes.EquipmentSlot.HEAD] = equipped_head
	var candidate: ItemInstance = _item(
		"candidate-rare",
		GameTypes.EquipmentSlot.HEAD,
		GameTypes.Rarity.RARE,
		GameTypes.MainWeaponType.UNCLASSIFIED,
		&"",
		false,
		[_affix(&"max_hp", 18.0), _affix(&"attack_speed_pct", 14.0)],
	)
	state.inventory[0] = candidate
	var comparison: Dictionary = InventoryServiceScript.compare_item(state, candidate.item_id)
	assertions.expect_true(bool(comparison["success"]), "focus comparison succeeds")
	assertions.expect_float(8.0, float(comparison["deltas"][&"max_hp"]), "comparison reports max HP delta")
	assertions.expect_float(14.0, float(comparison["deltas"][&"attack_speed_pct"]), "comparison reports attack speed delta")
	assertions.expect_equal(1, comparison["rarity_delta"], "comparison reports rarity delta")

	state.inventory[1] = _item_with_affix("qa-inventory-02", &"max_hp")
	state.inventory[2] = _item_with_affix("qa-inventory-00", &"max_hp")
	state.inventory[3] = _item_with_affix("qa-inventory-01", &"max_hp")
	state.inventory[4] = _item_with_affix("zz-affinity", &"attack_speed_pct")
	state.inventory[5] = _item_with_affix("aa-locked", &"max_hp", true)
	state.inventory[6] = _item(
		"aa-unique",
		GameTypes.EquipmentSlot.SUB_WEAPON,
		GameTypes.Rarity.UNIQUE,
		GameTypes.MainWeaponType.UNCLASSIFIED,
		&"bloodied_dagger",
		false,
		[],
		"血塗れの短剣",
	)
	assertions.expect_equal(20, InventoryServiceScript.build_value(state.inventory[1], GameTypes.MainWeaponType.BOW, catalog), "non-affinity build value")
	assertions.expect_equal(30, InventoryServiceScript.build_value(state.inventory[4], GameTypes.MainWeaponType.BOW, catalog), "affinity adds ten build value")
	assertions.expect_equal(
		PackedStringArray(["qa-inventory-00", "qa-inventory-01", "qa-inventory-02"]),
		InventoryServiceScript.auto_select(state, GameTypes.Rarity.COMMON, catalog),
		"auto selection excludes protected items and uses value/item_id order",
	)
	var lock_result: Dictionary = InventoryServiceScript.toggle_lock(state, "qa-inventory-02")
	assertions.expect_true(bool(lock_result["locked"]), "lock toggles on")
	assertions.expect_true(bool(InventoryServiceScript.toggle_lock(state, "qa-inventory-02")["success"]), "lock toggles off")
	assertions.expect_false(state.inventory[1].locked, "second toggle clears lock")

	var protected_inventory: PackedStringArray = _inventory_ids(state)
	var locked_discard: Dictionary = InventoryServiceScript.discard(
		state,
		PackedStringArray(["aa-locked"]),
		true,
	)
	assertions.expect_equal(&"locked", locked_discard["error"], "locked discard rejected")
	assertions.expect_equal(protected_inventory, _inventory_ids(state), "locked rejection changes no slot")
	var equipped_discard: Dictionary = InventoryServiceScript.discard(
		state,
		PackedStringArray(["equipped-head"]),
		true,
	)
	assertions.expect_equal(&"equipped", equipped_discard["error"], "equipped discard rejected")

	state.overflow.append(_item_with_affix("overflow-refill", &"max_hp"))
	var rng_before: Dictionary = _rng_snapshot(state)
	var inventory_before: PackedStringArray = _inventory_ids(state)
	var overflow_before: PackedStringArray = _item_ids(state.overflow)
	var warning: Dictionary = InventoryServiceScript.discard(
		state,
		PackedStringArray(["aa-unique", "qa-inventory-02"]),
		false,
	)
	assertions.expect_equal(&"unique_confirmation_required", warning["error"], "unique discard asks for confirmation")
	assertions.expect_equal(
		PackedStringArray(["血塗れの短剣", "qa-inventory-02"]),
		warning["target_names"],
		"discard warning enumerates every target name",
	)
	assertions.expect_equal(PackedStringArray(["血塗れの短剣"]), warning["unique_names"], "warning identifies unique targets")
	assertions.expect_equal(inventory_before, _inventory_ids(state), "confirmation cancel keeps inventory")
	assertions.expect_equal(overflow_before, _item_ids(state.overflow), "confirmation cancel keeps overflow")
	assertions.expect_equal(rng_before, _rng_snapshot(state), "confirmation cancel consumes no RNG")

	var drop_before: int = state.drop_serial
	var wild_before: int = state.wild_material_count
	var score_before: Dictionary = state.score_breakdown.duplicate(true)
	var discard: Dictionary = InventoryServiceScript.discard(
		state,
		PackedStringArray(["aa-unique", "qa-inventory-02"]),
		true,
	)
	assertions.expect_true(bool(discard["success"]), "confirmed unique bulk discard succeeds")
	assertions.expect_true(InventoryServiceScript.find_item(state, "aa-unique").is_empty(), "unique target removed")
	assertions.expect_true(InventoryServiceScript.find_item(state, "qa-inventory-02").is_empty(), "normal target removed")
	assertions.expect_equal("overflow-refill", state.inventory[1].item_id, "refill uses lowest discarded slot")
	assertions.expect_true(state.overflow.is_empty(), "successful discard drains available overflow")
	assertions.expect_equal(rng_before, _rng_snapshot(state), "discard consumes no RNG")
	assertions.expect_equal(drop_before, state.drop_serial, "discard grants no serial or item")
	assertions.expect_equal(wild_before, state.wild_material_count, "discard grants no wild material")
	assertions.expect_equal(score_before, state.score_breakdown, "discard grants no score")


func _test_reward_skill_wild_and_autoequip(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _loaded_catalog(assertions)
	if catalog == null:
		return
	var state: RunState = _new_state(504, catalog)
	state.wave_number = 2
	for item_index: int in range(35):
		state.inventory[item_index] = _item(
			"held-%02d" % item_index,
			GameTypes.EquipmentSlot.HANDS,
			GameTypes.Rarity.COMMON,
		)
	state.skill_library[&"starfall"] = _skill(&"starfall", 3, 0)
	var past_reward: RewardRoll = _equipment_reward(
		"past-wave",
		1,
		1,
		_item("past-item", GameTypes.EquipmentSlot.FEET, GameTypes.Rarity.COMMON),
	)
	past_reward.revealed = false
	var rewards: Array[RewardRoll] = [
		_skill_reward("reward-star-wild", 2, 15, &"starfall"),
		_equipment_reward("reward-c", 2, 10, _item("reward-item-c", GameTypes.EquipmentSlot.BODY, GameTypes.Rarity.COMMON)),
		_skill_reward("reward-blade-lv3", 2, 13, &"thousand_blades"),
		_equipment_reward("reward-a", 2, 10, _item("reward-item-a", GameTypes.EquipmentSlot.SUB_WEAPON, GameTypes.Rarity.COMMON)),
		_skill_reward("reward-blade-new", 2, 11, &"thousand_blades"),
		_skill_reward("reward-blade-wild", 2, 14, &"thousand_blades"),
		_equipment_reward("reward-b", 2, 10, _item("reward-item-b", GameTypes.EquipmentSlot.HEAD, GameTypes.Rarity.COMMON)),
		_skill_reward("reward-blade-lv2", 2, 12, &"thousand_blades"),
	]
	for reward: RewardRoll in rewards:
		reward.revealed = true
	state.unopened_rewards = rewards
	state.unopened_rewards.append(past_reward)
	var application: Dictionary = RewardApplicationServiceScript.apply_revealed(state)
	assertions.expect_true(bool(application["success"]), "revealed rewards apply as one ordered command")
	assertions.expect_equal(
		PackedStringArray([
			"reward-a",
			"reward-b",
			"reward-c",
			"reward-blade-new",
			"reward-blade-lv2",
			"reward-blade-lv3",
			"reward-blade-wild",
			"reward-star-wild",
		]),
		application["applied_reward_ids"],
		"reward application uses acquired_tick then reward_id order",
	)
	assertions.expect_equal("reward-item-a", state.inventory[35].item_id, "first public equipment takes last inventory gap")
	assertions.expect_equal(
		PackedStringArray(["reward-item-b", "reward-item-c"]),
		_item_ids(state.overflow),
		"remaining public equipment appends to overflow in exact order",
	)
	assertions.expect_equal(3, state.skill_library[&"thousand_blades"].level, "skill duplicates level to three")
	assertions.expect_equal(1, state.skill_library[&"thousand_blades"].equipped_slot, "new skill auto-equips lowest empty slot")
	assertions.expect_equal(2, state.wild_material_count, "two level-three duplicates become wild materials")
	assertions.expect_equal(1, state.unopened_rewards.size(), "current-wave rewards removed after apply")
	assertions.expect_equal(past_reward, state.unopened_rewards[0], "other-wave reward record retained")

	var no_crown: RunState = _new_state(505, catalog)
	no_crown.skill_library[&"starfall"] = _skill(&"starfall", 1, 0)
	no_crown.unopened_rewards = [_skill_reward("no-crown-soul", 1, 1, &"soul_chain")]
	RewardApplicationServiceScript.apply_revealed(no_crown)
	assertions.expect_equal(1, no_crown.skill_library[&"soul_chain"].equipped_slot, "without crown slot 1 auto-equips")

	var crown_empty: RunState = _new_state(506, catalog)
	crown_empty.equipped[GameTypes.EquipmentSlot.HEAD] = _crown_item("crown-empty")
	crown_empty.unopened_rewards = [_skill_reward("crown-empty-soul", 1, 1, &"soul_chain")]
	RewardApplicationServiceScript.apply_revealed(crown_empty)
	assertions.expect_equal(0, crown_empty.skill_library[&"soul_chain"].equipped_slot, "crown permits auto-equip into empty slot 0")

	var crown_full: RunState = _new_state(507, catalog)
	crown_full.equipped[GameTypes.EquipmentSlot.HEAD] = _crown_item("crown-full")
	crown_full.skill_library[&"starfall"] = _skill(&"starfall", 1, 0)
	crown_full.unopened_rewards = [_skill_reward("crown-full-soul", 1, 1, &"soul_chain")]
	RewardApplicationServiceScript.apply_revealed(crown_full)
	assertions.expect_equal(-1, crown_full.skill_library[&"soul_chain"].equipped_slot, "crown never auto-equips sealed slot 1")

	var blocked: RunState = _new_state(508, catalog)
	var unopened: RewardRoll = _equipment_reward(
		"unrevealed",
		1,
		1,
		_item("unrevealed-item", GameTypes.EquipmentSlot.FEET, GameTypes.Rarity.COMMON),
	)
	unopened.revealed = false
	blocked.unopened_rewards = [unopened]
	var blocked_result: Dictionary = RewardApplicationServiceScript.apply_revealed(blocked)
	assertions.expect_equal(&"unrevealed_reward", blocked_result["error"], "unrevealed reward blocks application")
	assertions.expect_true(_all_inventory_empty(blocked), "blocked reward command is atomic")

	var skill_ids: Array[StringName] = [
		&"starfall",
		&"thousand_blades",
		&"soul_chain",
		&"bell_of_retribution",
	]
	for skill_index: int in range(skill_ids.size()):
		var skill_id: StringName = skill_ids[skill_index]
		var level_state: RunState = _new_state(520 + skill_index, catalog)
		level_state.wave_number = 3
		level_state.unopened_rewards = [
			_skill_reward("%s-new" % skill_id, 3, 1, skill_id),
			_skill_reward("%s-level-2" % skill_id, 3, 2, skill_id),
			_skill_reward("%s-level-3" % skill_id, 3, 3, skill_id),
			_skill_reward("%s-wild" % skill_id, 3, 4, skill_id),
		]
		var level_application: Dictionary = RewardApplicationServiceScript.apply_revealed(
			level_state,
		)
		assertions.expect_true(bool(level_application["success"]), "%s full reward sequence applies" % skill_id)
		assertions.expect_equal(1, level_application["new_skill_count"], "%s is acquired at level one" % skill_id)
		assertions.expect_equal(2, level_application["level_up_count"], "%s levels exactly twice" % skill_id)
		assertions.expect_equal(1, level_application["wild_gained"], "%s fourth copy becomes wild" % skill_id)
		assertions.expect_equal(3, level_state.skill_library[skill_id].level, "%s remains capped at level three" % skill_id)
		assertions.expect_equal(1, level_state.wild_material_count, "%s grants exactly one wild after level three" % skill_id)


func _test_fusion_preview_commit_and_protection(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _loaded_catalog(assertions)
	if catalog == null:
		return
	var state: RunState = _new_state(509, catalog)
	for item_index: int in range(36):
		state.inventory[item_index] = _item(
			"fusion-held-%02d" % item_index,
			GameTypes.EquipmentSlot.HANDS,
			GameTypes.Rarity.COMMON,
		)
	var first: ItemInstance = _item(
		"fusion-rare-a",
		GameTypes.EquipmentSlot.HANDS,
		GameTypes.Rarity.RARE,
	)
	var unique: ItemInstance = _item(
		"fusion-unique",
		GameTypes.EquipmentSlot.SUB_WEAPON,
		GameTypes.Rarity.UNIQUE,
		GameTypes.MainWeaponType.UNCLASSIFIED,
		&"bloodied_dagger",
		false,
		[],
		"血塗れの短剣",
	)
	var second: ItemInstance = _item(
		"fusion-rare-b",
		GameTypes.EquipmentSlot.BODY,
		GameTypes.Rarity.RARE,
	)
	var third: ItemInstance = _item(
		"fusion-rare-overflow",
		GameTypes.EquipmentSlot.HEAD,
		GameTypes.Rarity.RARE,
	)
	state.inventory[18] = first
	state.inventory[33] = unique
	state.inventory[34] = second
	state.overflow = [
		_item("overflow-old-0", GameTypes.EquipmentSlot.MAIN_WEAPON, GameTypes.Rarity.COMMON, GameTypes.MainWeaponType.STAFF),
		_item("overflow-old-1", GameTypes.EquipmentSlot.BODY, GameTypes.Rarity.COMMON),
		third,
		_item("overflow-old-3", GameTypes.EquipmentSlot.FEET, GameTypes.Rarity.COMMON),
	]
	var unique_material_ids := PackedStringArray([first.item_id, third.item_id, unique.item_id])
	var rng_before: Dictionary = _rng_snapshot(state)
	var unique_rejection: Dictionary = FusionCommitServiceScript.preview(
		state,
		unique_material_ids,
		false,
	)
	assertions.expect_equal(&"unique", unique_rejection["error"], "UNIQUE material is rejected without a confirmation path")
	assertions.expect_equal(rng_before, _rng_snapshot(state), "UNIQUE rejection consumes no RNG")

	var material_ids := PackedStringArray([first.item_id, third.item_id, second.item_id])
	var preview: Dictionary = FusionCommitServiceScript.preview(state, material_ids, false)
	assertions.expect_true(bool(preview["success"]), "cross-inventory fusion preview validates")
	assertions.expect_equal(GameTypes.Rarity.EPIC, preview["output_rarity"], "preview exposes only next rarity")
	assertions.expect_equal(FusionCommitServiceScript.PREVIEW_RULE_TEXT, preview["rule_text"], "preview rule text exact")
	assertions.expect_equal(
		"部位は6種から均等抽選／UNIQUEはボス宝箱限定",
		preview["rule_text"],
		"fusion preview explains the boss-only UNIQUE rule",
	)
	assertions.expect_false(preview.has("needs_unique_confirmation"), "fusion preview has no UNIQUE confirmation flow")
	assertions.expect_equal(rng_before, _rng_snapshot(state), "preview consumes no RNG")

	var serial_before: int = state.drop_serial
	var commit: Dictionary = FusionCommitServiceScript.commit(
		state,
		material_ids,
		false,
		catalog,
	)
	assertions.expect_true(bool(commit["success"]), "normal fusion commits without confirmation")
	assertions.expect_equal(GameTypes.Rarity.EPIC, commit["output_rarity"], "fusion advances rarity exactly once")
	assertions.expect_true((commit["output"] as ItemInstance).unique_id.is_empty(), "fusion output is always non-UNIQUE")
	assertions.expect_equal(18, commit["output_index"], "fusion output gets lowest consumed inventory slot first")
	assertions.expect_equal(commit["output"], state.inventory[18], "reported output occupies reported slot")
	assertions.expect_equal(unique, state.inventory[33], "UNIQUE remains untouched by normal fusion")
	assertions.expect_equal("overflow-old-0", state.inventory[34].item_id, "remaining overflow refills only after output placement")
	assertions.expect_equal(
		PackedStringArray(["overflow-old-1", "overflow-old-3"]),
		_item_ids(state.overflow),
		"overflow material removal and refill preserve stable order",
	)
	for material_id: String in material_ids:
		assertions.expect_true(InventoryServiceScript.find_item(state, material_id).is_empty(), "exact fusion material consumed: %s" % material_id)
	assertions.expect_equal(serial_before + 1, state.drop_serial, "fusion reserves one output serial")
	assertions.expect_equal(1, state.fusion_count, "successful fusion increments count once")

	var wild_state: RunState = _new_state(510, catalog)
	wild_state.inventory[0] = _item("wild-a", GameTypes.EquipmentSlot.HANDS, GameTypes.Rarity.COMMON)
	wild_state.inventory[1] = _item("wild-b", GameTypes.EquipmentSlot.FEET, GameTypes.Rarity.COMMON)
	wild_state.wild_material_count = 1
	var wild_commit: Dictionary = FusionCommitServiceScript.commit(
		wild_state,
		PackedStringArray(["wild-a", "wild-b"]),
		true,
		catalog,
	)
	assertions.expect_true(bool(wild_commit["success"]), "two items plus one wild fuses")
	assertions.expect_equal(0, wild_state.wild_material_count, "fusion consumes exactly one wild")
	assertions.expect_equal(GameTypes.Rarity.RARE, wild_state.inventory[0].rarity, "wild fusion output occupies lowest gap")
	assertions.expect_equal(1, wild_state.fusion_count, "wild fusion counts once")

	var invalid_state: RunState = _new_state(511, catalog)
	invalid_state.inventory[0] = _item("invalid-a", GameTypes.EquipmentSlot.HANDS, GameTypes.Rarity.COMMON)
	invalid_state.inventory[1] = _item("invalid-b", GameTypes.EquipmentSlot.HANDS, GameTypes.Rarity.COMMON)
	invalid_state.inventory[2] = _item("invalid-locked", GameTypes.EquipmentSlot.HANDS, GameTypes.Rarity.COMMON)
	invalid_state.inventory[2].locked = true
	var invalid_rng: Dictionary = _rng_snapshot(invalid_state)
	assertions.expect_equal(
		&"locked",
		FusionCommitServiceScript.preview(invalid_state, PackedStringArray(["invalid-a", "invalid-b", "invalid-locked"]), false)["error"],
		"locked fusion material rejected",
	)
	invalid_state.inventory[2].locked = false
	invalid_state.inventory[2].rarity = GameTypes.Rarity.RARE
	assertions.expect_equal(
		&"rarity_mismatch",
		FusionCommitServiceScript.preview(invalid_state, PackedStringArray(["invalid-a", "invalid-b", "invalid-locked"]), false)["error"],
		"mixed rarity fusion rejected",
	)
	invalid_state.inventory[0].rarity = GameTypes.Rarity.LEGENDARY
	invalid_state.inventory[1].rarity = GameTypes.Rarity.LEGENDARY
	invalid_state.inventory[2].rarity = GameTypes.Rarity.LEGENDARY
	assertions.expect_equal(
		&"legendary",
		FusionCommitServiceScript.preview(invalid_state, PackedStringArray(["invalid-a", "invalid-b", "invalid-locked"]), false)["error"],
		"Legendary fusion rejected",
	)
	assertions.expect_equal(
		&"duplicate_material",
		FusionCommitServiceScript.preview(invalid_state, PackedStringArray(["invalid-a", "invalid-a", "invalid-b"]), false)["error"],
		"duplicate material reference rejected",
	)
	invalid_state.inventory[0].rarity = GameTypes.Rarity.COMMON
	invalid_state.inventory[1].rarity = GameTypes.Rarity.COMMON
	assertions.expect_equal(
		&"wild_unavailable",
		FusionCommitServiceScript.preview(invalid_state, PackedStringArray(["invalid-a", "invalid-b"]), true)["error"],
		"unowned wild replacement rejected",
	)
	var equipped_id: String = invalid_state.equipped[GameTypes.EquipmentSlot.MAIN_WEAPON].item_id
	assertions.expect_equal(
		&"equipped",
		FusionCommitServiceScript.preview(invalid_state, PackedStringArray([equipped_id, "invalid-a", "invalid-b"]), false)["error"],
		"equipped material rejected",
	)
	assertions.expect_equal(invalid_rng, _rng_snapshot(invalid_state), "all invalid fusion checks consume no RNG")


func _test_reward_unique_invariant(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _loaded_catalog(assertions)
	if catalog == null:
		return
	var valid_state: RunState = _new_state(540, catalog)
	var valid_unique: ItemInstance = _item(
		"valid-boss-unique",
		GameTypes.EquipmentSlot.SUB_WEAPON,
		GameTypes.Rarity.UNIQUE,
		GameTypes.MainWeaponType.UNCLASSIFIED,
		&"bloodied_dagger",
		false,
		[],
		"血塗れの短剣",
	)
	valid_state.unopened_rewards = [_equipment_reward(
		"valid-boss-unique-reward",
		1,
		1,
		valid_unique,
		GameTypes.RewardSource.BOSS,
	)]
	var valid_result: Dictionary = RewardApplicationServiceScript.apply_revealed(valid_state)
	assertions.expect_true(bool(valid_result["success"]), "valid boss-sourced UNIQUE applies")
	assertions.expect_equal(valid_unique, valid_state.inventory[0], "valid UNIQUE enters inventory")

	_assert_invalid_unique_reward(
		assertions,
		catalog,
		541,
		_item("id-with-normal-rarity", GameTypes.EquipmentSlot.SUB_WEAPON, GameTypes.Rarity.RARE, GameTypes.MainWeaponType.UNCLASSIFIED, &"bloodied_dagger"),
		GameTypes.RewardSource.BOSS,
		&"invalid_unique_identity",
		"unique_id with normal rarity",
	)
	_assert_invalid_unique_reward(
		assertions,
		catalog,
		542,
		_item("unique-rarity-without-id", GameTypes.EquipmentSlot.HANDS, GameTypes.Rarity.UNIQUE),
		GameTypes.RewardSource.BOSS,
		&"invalid_unique_identity",
		"UNIQUE rarity without unique_id",
	)
	_assert_invalid_unique_reward(
		assertions,
		catalog,
		543,
		_item("unique-with-affix", GameTypes.EquipmentSlot.SUB_WEAPON, GameTypes.Rarity.UNIQUE, GameTypes.MainWeaponType.UNCLASSIFIED, &"bloodied_dagger", false, [_affix(&"damage_pct", 40.0)]),
		GameTypes.RewardSource.BOSS,
		&"invalid_unique_affixes",
		"UNIQUE with affix",
	)
	_assert_invalid_unique_reward(
		assertions,
		catalog,
		544,
		_item("normal-source-unique", GameTypes.EquipmentSlot.SUB_WEAPON, GameTypes.Rarity.UNIQUE, GameTypes.MainWeaponType.UNCLASSIFIED, &"bloodied_dagger"),
		GameTypes.RewardSource.NORMAL,
		&"invalid_unique_source",
		"UNIQUE from non-boss source",
	)

	var boss_normal_state: RunState = _new_state(545, catalog)
	boss_normal_state.unopened_rewards = [_equipment_reward(
		"boss-normal-reward",
		1,
		1,
		_item("boss-normal", GameTypes.EquipmentSlot.HANDS, GameTypes.Rarity.COMMON),
		GameTypes.RewardSource.BOSS,
	)]
	assertions.expect_true(
		bool(RewardApplicationServiceScript.apply_revealed(boss_normal_state)["success"]),
		"BOSS source permits the seven non-UNIQUE rewards",
	)


func _test_skill_move_snapshot_and_crown(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _loaded_catalog(assertions)
	if catalog == null:
		return
	var state: RunState = _new_state(512, catalog)
	state.skill_library[&"starfall"] = _skill(&"starfall", 3, 0, 2.5)
	state.skill_library[&"thousand_blades"] = _skill(&"thousand_blades", 2, 1, 6.0)
	state.skill_library[&"soul_chain"] = _skill(&"soul_chain", 1, -1, 9.0)
	state.skill_library[&"bell_of_retribution"] = _skill(&"bell_of_retribution", 3, -1, 4.0)
	var soul_to_zero: Dictionary = SkillEquipServiceScript.apply_move(
		state,
		SkillEquipServiceScript.SOURCE_CATALOG,
		&"soul_chain",
		SkillEquipServiceScript.SOURCE_SLOT,
		0,
	)
	assertions.expect_true(bool(soul_to_zero["success"]), "K4 catalog moves to K0")
	_assert_skill_slots(assertions, state, PackedInt32Array([-1, 1, 0, -1]), "K4 to K0")
	SkillEquipServiceScript.apply_move(
		state,
		SkillEquipServiceScript.SOURCE_CATALOG,
		&"thousand_blades",
		SkillEquipServiceScript.SOURCE_SLOT,
		0,
	)
	_assert_skill_slots(assertions, state, PackedInt32Array([-1, 0, 1, -1]), "K3 to K0")
	SkillEquipServiceScript.apply_move(
		state,
		SkillEquipServiceScript.SOURCE_CATALOG,
		&"starfall",
		SkillEquipServiceScript.SOURCE_SLOT,
		1,
	)
	_assert_skill_slots(assertions, state, PackedInt32Array([1, 0, -1, -1]), "K2 to K1")
	assertions.expect_float(2.5, state.skill_library[&"starfall"].trigger_progress, "moves preserve trigger progress")
	assertions.expect_equal(3, state.skill_library[&"starfall"].level, "moves preserve level")

	var snapshot: Dictionary = SkillEquipServiceScript.capture_snapshot(state)
	SkillEquipServiceScript.apply_move(
		state,
		SkillEquipServiceScript.SOURCE_CATALOG,
		&"bell_of_retribution",
		SkillEquipServiceScript.SOURCE_SLOT,
		0,
	)
	assertions.expect_true(SkillEquipServiceScript.restore_snapshot(state, snapshot), "B cancel restores slot snapshot")
	_assert_skill_slots(assertions, state, PackedInt32Array([1, 0, -1, -1]), "cancel snapshot")
	var self_move: Dictionary = SkillEquipServiceScript.apply_move(
		state,
		SkillEquipServiceScript.SOURCE_CATALOG,
		&"starfall",
		SkillEquipServiceScript.SOURCE_SLOT,
		1,
	)
	assertions.expect_true(bool(self_move["no_op"]), "catalog alias onto same slot is no-op")
	var different_catalog: Dictionary = SkillEquipServiceScript.apply_move(
		state,
		SkillEquipServiceScript.SOURCE_SLOT,
		1,
		SkillEquipServiceScript.SOURCE_CATALOG,
		&"bell_of_retribution",
	)
	assertions.expect_equal(&"different_catalog", different_catalog["error"], "slot cannot drop on another catalog card")
	_assert_skill_slots(assertions, state, PackedInt32Array([1, 0, -1, -1]), "rejected different catalog")

	state.equipped[GameTypes.EquipmentSlot.HEAD] = _crown_item("skill-crown")
	var seal: Dictionary = SkillEquipServiceScript.apply_crown_seal(state)
	assertions.expect_true(bool(seal["success"]), "crown seal command succeeds")
	assertions.expect_equal(-1, state.skill_library[&"starfall"].equipped_slot, "crown unmounts slot 1 skill")
	var sealed_move: Dictionary = SkillEquipServiceScript.apply_move(
		state,
		SkillEquipServiceScript.SOURCE_CATALOG,
		&"soul_chain",
		SkillEquipServiceScript.SOURCE_SLOT,
		1,
	)
	assertions.expect_equal(&"sealed_slot", sealed_move["error"], "sealed slot rejects placement")
	assertions.expect_equal(
		PackedStringArray(["thousand_blades", ""]),
		SkillEquipServiceScript.slot_skill_ids(state),
		"slot references remain unique after seal",
	)


func _test_score_w8_and_retry(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _loaded_catalog(assertions)
	if catalog == null:
		return
	var held: Array[ItemInstance] = [
		_item("score-common", GameTypes.EquipmentSlot.HANDS, GameTypes.Rarity.COMMON),
		_item("score-unique", GameTypes.EquipmentSlot.SUB_WEAPON, GameTypes.Rarity.UNIQUE, GameTypes.MainWeaponType.UNCLASSIFIED, &"bloodied_dagger"),
		_item("score-epic", GameTypes.EquipmentSlot.HEAD, GameTypes.Rarity.EPIC),
		_item("score-legendary", GameTypes.EquipmentSlot.FEET, GameTypes.Rarity.LEGENDARY),
	]
	var skills: Dictionary[StringName, SkillState] = {
		&"starfall": _skill(&"starfall", 3, 0),
		&"thousand_blades": _skill(&"thousand_blades", 2, 1),
	}
	var breakdown: Dictionary = ScoreServiceScript.calculate(
		100,
		1,
		1,
		20,
		8,
		true,
		held,
		skills,
		2,
		catalog.score_definition(),
	)
	assertions.expect_equal(9000, breakdown[&"combat_score"], "fixed combat subtotal")
	assertions.expect_equal(4210, breakdown[&"final_build_score"], "fixed build subtotal")
	assertions.expect_equal(13210, breakdown[&"total"], "fixed final score 13,210")

	var w8: RunState = _new_state(513, catalog)
	w8.phase = GameTypes.RunPhase.INVENTORY
	w8.wave_number = 8
	w8.overflow.append(_item("pending-overflow", GameTypes.EquipmentSlot.HANDS, GameTypes.Rarity.COMMON))
	assertions.expect_false(RunStateMachineScript.can_transition_state(w8, GameTypes.RunPhase.RESULT), "W8 overflow blocks result")
	w8.overflow.clear()
	var main_weapon: ItemInstance = w8.equipped[GameTypes.EquipmentSlot.MAIN_WEAPON]
	w8.equipped[GameTypes.EquipmentSlot.MAIN_WEAPON] = null
	assertions.expect_false(RunStateMachineScript.can_transition_state(w8, GameTypes.RunPhase.RESULT), "defensive gate blocks null main weapon")
	w8.equipped[GameTypes.EquipmentSlot.MAIN_WEAPON] = main_weapon
	assertions.expect_true(RunStateMachineScript.can_transition_state(w8, GameTypes.RunPhase.RESULT), "clean W8 inventory can enter result")

	var dirty: RunState = _new_state(514, catalog)
	dirty.wave_number = 7
	dirty.current_hp = 2.0
	dirty.inventory[0] = _item("old-item", GameTypes.EquipmentSlot.HEAD, GameTypes.Rarity.LEGENDARY)
	dirty.overflow.append(_item("old-overflow", GameTypes.EquipmentSlot.FEET, GameTypes.Rarity.EPIC))
	dirty.skill_library[&"starfall"] = _skill(&"starfall", 3, 0, 5.5)
	dirty.wild_material_count = 9
	dirty.drop_serial = 99
	dirty.next_entity_id = 12
	dirty.next_activation_serial = 13
	dirty.next_event_serial = 14
	dirty.coward_stationary_elapsed = 2.0
	dirty.echo_progress_item_id = "old-echo"
	dirty.echo_primary_attack_progress = 2
	dirty.total_kills = 999
	dirty.cleared_waves = 6
	dirty.fusion_count = 4
	dirty.peak_dps = 321.0
	dirty.score_breakdown = {&"total": 99999}
	var old_main: ItemInstance = dirty.equipped[GameTypes.EquipmentSlot.MAIN_WEAPON]
	var retry: RunState = RunStateFactoryScript.create(dirty.run_seed, catalog.wave(1))
	var expected_streams: RunRngStreams = RunRngStreams.create(dirty.run_seed)
	assertions.expect_equal(dirty.run_seed, retry.run_seed, "same-seed retry preserves only seed")
	assertions.expect_equal(GameTypes.RunPhase.COMBAT, retry.phase, "retry starts COMBAT")
	assertions.expect_equal(1, retry.wave_number, "retry starts W1")
	assertions.expect_float(100.0, retry.current_hp, "retry restores HP")
	assertions.expect_true(_all_inventory_empty(retry), "retry inventory empty")
	assertions.expect_true(retry.overflow.is_empty(), "retry overflow empty")
	assertions.expect_true(retry.skill_library.is_empty(), "retry skill library empty")
	assertions.expect_true(retry.unopened_rewards.is_empty(), "retry reward queue empty")
	assertions.expect_true(retry.scheduled_proc_replays.is_empty(), "retry proc queue empty")
	assertions.expect_equal(0, retry.wild_material_count, "retry wild reset")
	assertions.expect_equal(1, retry.drop_serial, "retry reserves only initial wood serial")
	assertions.expect_equal(0, retry.next_entity_id, "retry entity serial reset")
	assertions.expect_equal(0, retry.next_activation_serial, "retry activation serial reset")
	assertions.expect_equal(0, retry.next_event_serial, "retry event serial reset")
	assertions.expect_float(0.0, retry.coward_stationary_elapsed, "retry coward timer reset")
	assertions.expect_equal("", retry.echo_progress_item_id, "retry echo item reset")
	assertions.expect_equal(0, retry.echo_primary_attack_progress, "retry echo progress reset")
	assertions.expect_equal(0, retry.total_kills, "retry kill counters reset")
	assertions.expect_equal(0, retry.cleared_waves, "retry clear count reset")
	assertions.expect_equal(0, retry.fusion_count, "retry fusion count reset")
	assertions.expect_float(0.0, retry.peak_dps, "retry peak DPS reset")
	assertions.expect_true(retry.score_breakdown.is_empty(), "retry score reset")
	assertions.expect_not_equal(old_main, retry.equipped[GameTypes.EquipmentSlot.MAIN_WEAPON], "retry creates fresh initial item instance")
	assertions.expect_equal("木の棒", retry.equipped[GameTypes.EquipmentSlot.MAIN_WEAPON].display_name, "retry equips initial wood")
	assertions.expect_equal(expected_streams.combat_rng.state, retry.rng_streams.combat_rng.state, "retry combat RNG rederived")
	assertions.expect_equal(expected_streams.loot_rng.state, retry.rng_streams.loot_rng.state, "retry loot RNG rederived")
	assertions.expect_equal(expected_streams.fusion_rng.state, retry.rng_streams.fusion_rng.state, "retry fusion RNG rederived")


func _test_w8_reward_inventory_fusion_result(assertions: Variant) -> void:
	var catalog: DefinitionCatalog = _loaded_catalog(assertions)
	if catalog == null:
		return
	var state: RunState = _new_state(518, catalog)
	state.phase = GameTypes.RunPhase.REWARD_REVEAL
	state.wave_number = 8
	state.wave_cleared = true
	state.cleared_waves = 8
	for item_index: int in range(RunState.INVENTORY_CAPACITY):
		state.inventory[item_index] = _item(
			"w8-held-%02d" % item_index,
			GameTypes.EquipmentSlot.HANDS,
			GameTypes.Rarity.COMMON,
		)
	state.unopened_rewards = [
		_equipment_reward(
			"w8-reward-roll",
			8,
			1,
			_item(
				"w8-reward-item",
				GameTypes.EquipmentSlot.FEET,
				GameTypes.Rarity.COMMON,
			),
		),
	]

	var app: Variant = GameAppScript.new()
	app.set("_definition_catalog", catalog)
	app.set("run_state", state)
	app.call("_on_reward_reveal_completed")
	assertions.expect_equal(GameTypes.RunPhase.INVENTORY, state.phase, "W8 revealed rewards enter inventory through GameApp")
	assertions.expect_true(state.unopened_rewards.is_empty(), "W8 revealed reward records are consumed")
	assertions.expect_equal(PackedStringArray(["w8-reward-item"]), _item_ids(state.overflow), "W8 full inventory sends revealed equipment to overflow")

	var inventory_screen: Node = app.get("_active_screen") as Node
	assertions.expect_true(inventory_screen != null, "GameApp opens W8 inventory after reward application")
	if inventory_screen != null:
		app.remove_child(inventory_screen)
		inventory_screen.free()
	app.set("_active_screen", null)
	app.call("_on_inventory_continue_requested")
	assertions.expect_equal(GameTypes.RunPhase.INVENTORY, state.phase, "W8 cannot reach result while overflow remains")

	var material_ids := PackedStringArray([
		"w8-held-00",
		"w8-held-01",
		"w8-reward-item",
	])
	app.call("_on_inventory_fusion_requested", material_ids, false)
	assertions.expect_equal(1, state.fusion_count, "W8 inventory fusion commits through GameApp")
	assertions.expect_true(state.overflow.is_empty(), "W8 fusion resolves the reward overflow")
	for material_id: String in material_ids:
		assertions.expect_true(InventoryServiceScript.find_item(state, material_id).is_empty(), "W8 fusion consumes exact material %s" % material_id)
	var fused_item: ItemInstance = state.inventory[0]
	assertions.expect_true(fused_item != null, "W8 fusion places one output in the lowest consumed slot")
	if fused_item != null:
		assertions.expect_equal(GameTypes.Rarity.RARE, fused_item.rarity, "W8 Common fusion yields one Rare")

	app.call("_on_inventory_continue_requested")
	assertions.expect_equal(GameTypes.RunPhase.RESULT, state.phase, "W8 resolved inventory enters result through GameApp")
	assertions.expect_equal(GameTypes.RunPhase.RESULT, app.call("current_run_phase"), "GameApp exposes RESULT after W8 organization")
	assertions.expect_equal(8, state.cleared_waves, "W8 result preserves all cleared waves")
	assertions.expect_false(state.score_breakdown.is_empty(), "W8 GameApp transition calculates final score")
	var result_screen: Node = app.get("_active_screen") as Node
	assertions.expect_true(result_screen != null, "GameApp opens the result screen after W8")
	if result_screen != null:
		assertions.expect_equal(
			"res://src/ui/result_screen.gd",
			String(result_screen.get_script().resource_path),
			"W8 GameApp route owns the result screen",
		)
	app.free()


func _loaded_catalog(assertions: Variant) -> DefinitionCatalog:
	if _catalog == null:
		_catalog = DefinitionCatalog.new()
		var valid: bool = _catalog.load_and_validate()
		assertions.expect_true(valid, "inventory DefinitionCatalog valid: %s" % _catalog.error_text)
	return _catalog if _catalog.is_valid else null


func _new_state(run_seed: int, catalog: DefinitionCatalog) -> RunState:
	return RunStateFactoryScript.create(run_seed, catalog.wave(1))


func _item(
	item_id: String,
	slot: GameTypes.EquipmentSlot,
	rarity: GameTypes.Rarity,
	main_weapon_type: GameTypes.MainWeaponType = GameTypes.MainWeaponType.UNCLASSIFIED,
	unique_id: StringName = &"",
	locked: bool = false,
	affixes: Array[AffixRoll] = [],
	display_name: String = "",
) -> ItemInstance:
	var item := ItemInstance.new()
	item.item_id = item_id
	item.item_seed = item_id.hash()
	item.slot = slot
	item.main_weapon_type = (
		main_weapon_type
		if slot == GameTypes.EquipmentSlot.MAIN_WEAPON
		else GameTypes.MainWeaponType.UNCLASSIFIED
	)
	item.rarity = rarity
	item.unique_id = unique_id
	item.locked = locked
	item.affixes = affixes.duplicate()
	item.display_name = display_name if not display_name.is_empty() else item_id
	return item


func _item_with_affix(
	item_id: String,
	affix_id: StringName,
	locked: bool = false,
) -> ItemInstance:
	return _item(
		item_id,
		GameTypes.EquipmentSlot.HANDS,
		GameTypes.Rarity.COMMON,
		GameTypes.MainWeaponType.UNCLASSIFIED,
		&"",
		locked,
		[_affix(affix_id, 10.0)],
	)


func _crown_item(item_id: String) -> ItemInstance:
	return _item(
		item_id,
		GameTypes.EquipmentSlot.HEAD,
		GameTypes.Rarity.UNIQUE,
		GameTypes.MainWeaponType.UNCLASSIFIED,
		&"hollow_crown",
	)


func _affix(affix_id: StringName, value: float) -> AffixRoll:
	var affix := AffixRoll.new()
	affix.affix_id = affix_id
	affix.value = value
	return affix


func _skill(
	skill_id: StringName,
	level: int,
	equipped_slot: int,
	trigger_progress: float = 0.0,
) -> SkillState:
	var skill := SkillState.new()
	skill.skill_id = skill_id
	skill.level = level
	skill.equipped_slot = equipped_slot
	skill.trigger_progress = trigger_progress
	return skill


func _equipment_reward(
	reward_id: String,
	wave_number: int,
	acquired_tick: int,
	item: ItemInstance,
	source: GameTypes.RewardSource = GameTypes.RewardSource.NORMAL,
) -> RewardRoll:
	var reward := RewardRoll.new()
	reward.reward_id = reward_id
	reward.wave_number = wave_number
	reward.acquired_tick = acquired_tick
	reward.source = source
	reward.kind = GameTypes.RewardKind.EQUIPMENT
	reward.equipment = item
	reward.rarity_for_presentation = item.rarity
	reward.revealed = true
	return reward


func _assert_invalid_unique_reward(
	assertions: Variant,
	catalog: DefinitionCatalog,
	run_seed: int,
	item: ItemInstance,
	source: GameTypes.RewardSource,
	expected_error: StringName,
	label: String,
) -> void:
	var state: RunState = _new_state(run_seed, catalog)
	state.unopened_rewards = [_equipment_reward(
		"invalid-reward-%d" % run_seed,
		1,
		1,
		item,
		source,
	)]
	var before_inventory: PackedStringArray = _inventory_ids(state)
	var result: Dictionary = RewardApplicationServiceScript.apply_revealed(state)
	assertions.expect_equal(expected_error, result["error"], "%s is rejected" % label)
	assertions.expect_equal(before_inventory, _inventory_ids(state), "%s changes no inventory" % label)


func _skill_reward(
	reward_id: String,
	wave_number: int,
	acquired_tick: int,
	skill_id: StringName,
) -> RewardRoll:
	var reward := RewardRoll.new()
	reward.reward_id = reward_id
	reward.wave_number = wave_number
	reward.acquired_tick = acquired_tick
	reward.kind = GameTypes.RewardKind.SKILL
	reward.skill_id = skill_id
	reward.revealed = true
	return reward


func _assert_move_validation(
	assertions: Variant,
	state: RunState,
	source_kind: StringName,
	source_index: int,
	target_kind: StringName,
	target_index: int,
	expected_success: bool,
	expected_error: StringName,
	expected_message: String,
	label: String,
) -> void:
	var before: Dictionary = _move_validation_snapshot(state)
	var validation: Dictionary = InventoryServiceScript.validate_move(
		state,
		source_kind,
		source_index,
		target_kind,
		target_index,
	)
	assertions.expect_equal(3, validation.size(), "%s validation exposes exactly three keys" % label)
	assertions.expect_equal(expected_success, bool(validation["success"]), "%s validation success" % label)
	assertions.expect_equal(expected_error, validation["error"], "%s validation error" % label)
	assertions.expect_equal(expected_message, validation["message"], "%s validation message" % label)
	assertions.expect_equal(
		before,
		_move_validation_snapshot(state),
		"%s validation is state invariant" % label,
	)

	var applied: Dictionary = InventoryServiceScript.apply_move(
		state,
		source_kind,
		source_index,
		target_kind,
		target_index,
	)
	assertions.expect_equal(expected_success, bool(applied["success"]), "%s apply success parity" % label)
	assertions.expect_equal(expected_error, applied["error"], "%s apply error parity" % label)
	assertions.expect_equal(expected_message, applied["message"], "%s apply message parity" % label)
	if not expected_success:
		assertions.expect_equal(
			before,
			_move_validation_snapshot(state),
			"%s rejected apply is state invariant" % label,
		)


func _move_validation_snapshot(state: RunState) -> Dictionary:
	if state == null:
		return {"state": null}
	var equipped_ids := PackedStringArray()
	for slot_value: int in GameTypes.EquipmentSlot.values():
		var item: ItemInstance = state.equipped.get(slot_value, null) as ItemInstance
		equipped_ids.append(item.item_id if item != null else "<null>")
	return {
		"inventory": _inventory_ids(state),
		"overflow": _item_ids(state.overflow),
		"equipped": equipped_ids,
		"echo_item": state.echo_progress_item_id,
		"echo_progress": state.echo_primary_attack_progress,
		"rng": _rng_snapshot(state),
		"drop_serial": state.drop_serial,
		"score": state.score_breakdown.duplicate(true),
	}


func _item_ids(items: Array[ItemInstance]) -> PackedStringArray:
	var result := PackedStringArray()
	for item: ItemInstance in items:
		result.append(item.item_id if item != null else "<null>")
	return result


func _inventory_ids(state: RunState) -> PackedStringArray:
	return _item_ids(state.inventory)


func _all_inventory_empty(state: RunState) -> bool:
	for item: ItemInstance in state.inventory:
		if item != null:
			return false
	return true


func _rng_snapshot(state: RunState) -> Dictionary:
	return {
		"combat": state.rng_streams.combat_rng.state,
		"loot": state.rng_streams.loot_rng.state,
		"fusion": state.rng_streams.fusion_rng.state,
	}


func _assert_skill_slots(
	assertions: Variant,
	state: RunState,
	expected: PackedInt32Array,
	label: String,
) -> void:
	var skill_ids: Array[StringName] = [
		&"starfall",
		&"thousand_blades",
		&"soul_chain",
		&"bell_of_retribution",
	]
	var actual := PackedInt32Array()
	var occupied: Dictionary[int, bool] = {}
	var duplicate_count: int = 0
	for skill_id: StringName in skill_ids:
		var skill: SkillState = state.skill_library[skill_id]
		actual.append(skill.equipped_slot)
		if skill.equipped_slot < 0:
			continue
		if occupied.has(skill.equipped_slot):
			duplicate_count += 1
		occupied[skill.equipped_slot] = true
	assertions.expect_equal(expected, actual, "%s exact equipped slots" % label)
	assertions.expect_equal(0, duplicate_count, "%s has at most one skill per slot" % label)
