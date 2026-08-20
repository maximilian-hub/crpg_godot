extends Resource
class_name ChessHandStyle

## Race-specific artwork for a layered hand pose. The moved piece is rendered
## between each back texture and its matching front/thumb texture.

@export var open_back: Texture2D
@export var open_front: Texture2D
@export var closed_back: Texture2D
@export var closed_front: Texture2D
@export var sounds: ChessHandSoundSet


func is_complete() -> bool:
	return open_back != null and closed_back != null
