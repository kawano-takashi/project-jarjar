class_name RarityDefinition
extends Resource


const Types := preload("res://src/core/game_types.gd")


@export var rarity: Types.Rarity = Types.Rarity.COMMON
@export var affix_count: int = 0
