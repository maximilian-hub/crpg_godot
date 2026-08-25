extends Resource
class_name ChessHandStyle

## Race-specific artwork for a layered hand pose. Grip artwork depth-sorts with
## the carried piece, while the long arm can remain above the board.

@export var open_arm: Texture2D
@export var open_rear_fingers: Texture2D
@export var open_thumb: Texture2D
@export var closed_arm: Texture2D
@export var closed_rear_fingers: Texture2D
@export var closed_thumb: Texture2D
@export var sounds: ChessHandSoundSet


func is_complete() -> bool:
	return (
		open_arm != null
		and open_rear_fingers != null
		and open_thumb != null
		and closed_arm != null
		and closed_rear_fingers != null
		and closed_thumb != null
	)
