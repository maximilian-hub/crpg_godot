extends Resource
class_name PieceArtProfile

## Visual metadata shared by every color that uses the same piece silhouette.

@export var reference_texture: Texture2D
## Position at which a hand should hold the piece, relative to its ground origin.
@export var grip_anchor := Vector2.ZERO
