extends RefCounted

const BotObservation = preload("res://dev/bot/bot_observation.gd")

enum Kind { MOVE, CHOOSE_UPGRADE, CONTINUE_CHEST }

var kind: Kind = Kind.MOVE
## Screen-relative analog input, length at most one, exactly like a controller.
var move_input := Vector2.ZERO
var choice_index: int = -1
var reason: StringName = &""


func is_valid_for(observation: BotObservation) -> bool:
	match observation.phase:
		GameTypes.RunPhase.COMBAT:
			return kind == Kind.MOVE and move_input.is_finite() and move_input.length_squared() <= 1.000001
		GameTypes.RunPhase.LEVEL_UP:
			return kind == Kind.CHOOSE_UPGRADE and choice_index >= 0 and choice_index < observation.options.size()
		GameTypes.RunPhase.CHEST_REWARD:
			return kind == Kind.CONTINUE_CHEST
	return false
