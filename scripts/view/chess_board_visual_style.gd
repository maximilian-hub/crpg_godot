extends Resource
class_name ChessBoardVisualStyle

## Replaceable presentation data for a physical chess board. The generated
## renderer uses these values today; later material-specific renderers can keep
## the same resource boundary.

## These are universal defaults for now. Later, piece and board material
## properties can select a more specific interaction sound set.
@export var interaction_sounds: ChessBoardSoundSet:
	set(value):
		interaction_sounds = value
		emit_changed()

@export var light_square_color := Color("d8c6a0"):
	set(value):
		light_square_color = value
		emit_changed()

@export var dark_square_color := Color("806047"):
	set(value):
		dark_square_color = value
		emit_changed()

@export var frame_top_color := Color("4a2d1c"):
	set(value):
		frame_top_color = value
		emit_changed()

@export var frame_front_color := Color("2f1a12"):
	set(value):
		frame_front_color = value
		emit_changed()

@export var frame_side_color := Color("3a2116"):
	set(value):
		frame_side_color = value
		emit_changed()

@export var shadow_color := Color(0.0, 0.0, 0.0, 0.35):
	set(value):
		shadow_color = value
		emit_changed()

@export_range(0.0, 64.0, 1.0) var reference_frame_width := 20.0:
	set(value):
		reference_frame_width = value
		emit_changed()

@export_range(0.0, 48.0, 1.0) var reference_thickness := 14.0:
	set(value):
		reference_thickness = value
		emit_changed()

@export var reference_shadow_offset := Vector2(0.0, 12.0):
	set(value):
		reference_shadow_offset = value
		emit_changed()
