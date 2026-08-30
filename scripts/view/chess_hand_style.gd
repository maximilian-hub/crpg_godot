extends Resource
class_name ChessHandStyle

## Character-specific artwork for a layered hand pose. Names describe render
## roles rather than anatomy, so hands approaching from either side of the board
## may place different fingers in the same depth slot.

@export var open_grip_back: Texture2D
@export var open_grip_front: Texture2D
@export var open_arm_foreground: Texture2D
@export var closed_grip_back: Texture2D
@export var closed_grip_front: Texture2D
@export var closed_arm_foreground: Texture2D
@export var sounds: ChessHandSoundSet


func is_complete() -> bool:
	return (
		open_grip_back != null
		and open_grip_front != null
		and open_arm_foreground != null
		and closed_grip_back != null
		and closed_grip_front != null
		and closed_arm_foreground != null
	)
