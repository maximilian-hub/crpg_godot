extends Resource
class_name PieceArtProfile

## Visual metadata shared by every color that uses the same piece silhouette.

@export var reference_texture: Texture2D
## Optional finished White-army artwork. When absent, PieceView renders the
## reference texture through the standard White palette shader.
@export var white_texture: Texture2D
## Intended physical height in PieceView-local board units. Source textures are
## scaled uniformly to this height, so art resolution does not change footprint.
@export_range(1.0, 256.0, 1.0) var display_height := 64.0
## Position at which a hand should hold the piece, relative to its ground origin.
@export var grip_anchor := Vector2.ZERO


func texture_for_color(color: String) -> Texture2D:
	if color == "white" and white_texture != null:
		return white_texture
	return reference_texture


func texture_scale(texture: Texture2D = null) -> float:
	var selected_texture := texture if texture != null else reference_texture
	if selected_texture == null or selected_texture.get_height() <= 0:
		return 1.0
	return display_height / float(selected_texture.get_height())
