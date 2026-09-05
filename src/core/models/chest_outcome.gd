class_name ChestOutcome
extends RefCounted


var serial: int = 0
var source_elite_index: int = -1
var source_chest_kind: GameTypes.ChestKind = GameTypes.ChestKind.NORMAL
var kind: GameTypes.ChestOutcomeKind = GameTypes.ChestOutcomeKind.FULL_HEAL
var upgrade_kind: GameTypes.UpgradeKind = GameTypes.UpgradeKind.WEAPON
var content_id: StringName = &""
var display_name: String = ""
var upgrade_detail: String = ""
var previous_level: int = 0
var new_level: int = 0
var source_weapon_id: StringName = &""
var applied: bool = false
