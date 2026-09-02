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

## Places each piece's ground-contact origin between the geometric center of
## its projected square (0.0) and that square's viewer-facing edge (1.0).
@export_range(0.0, 1.0, 0.01) var piece_forward_bias := 0.35:
	set(value):
		piece_forward_bias = clampf(value, 0.0, 1.0)
		emit_changed()

@export var material_surface_enabled := false:
	set(value):
		material_surface_enabled = value
		emit_changed()

@export var light_square_texture: Texture2D:
	set(value):
		light_square_texture = value
		emit_changed()

@export var dark_square_texture: Texture2D:
	set(value):
		dark_square_texture = value
		emit_changed()

@export_range(0.25, 8.0, 0.05) var material_texture_scale := 1.0:
	set(value):
		material_texture_scale = value
		emit_changed()

@export_range(0.0, 1.0, 0.01) var material_texture_strength := 0.7:
	set(value):
		material_texture_strength = value
		emit_changed()

@export_range(0.4, 1.2, 0.01) var material_light_brightness := 1.0:
	set(value):
		material_light_brightness = value
		emit_changed()

@export_range(0.0, 0.25, 0.005) var material_variation_strength := 0.06:
	set(value):
		material_variation_strength = value
		emit_changed()

@export_range(0.0, 1.0, 0.01) var material_procedural_detail := 0.35:
	set(value):
		material_procedural_detail = value
		emit_changed()

@export_range(0.0, 0.08, 0.001) var material_seam_width := 0.012:
	set(value):
		material_seam_width = value
		emit_changed()

@export var material_seam_color := Color(0.12, 0.08, 0.06, 0.45):
	set(value):
		material_seam_color = value
		emit_changed()

@export var frame_top_color := Color("4a2d1c"):
	set(value):
		frame_top_color = value
		emit_changed()

@export var frame_material_enabled := false:
	set(value):
		frame_material_enabled = value
		emit_changed()

@export var frame_top_texture: Texture2D:
	set(value):
		frame_top_texture = value
		emit_changed()

@export var frame_edge_texture: Texture2D:
	set(value):
		frame_edge_texture = value
		emit_changed()

@export_range(0.25, 8.0, 0.05) var frame_material_texture_scale := 1.0:
	set(value):
		frame_material_texture_scale = value
		emit_changed()

@export_range(0.15, 2.0, 0.01) var frame_material_grain_tightness := 1.0:
	set(value):
		frame_material_grain_tightness = value
		emit_changed()

@export_range(0.0, 1.0, 0.01) var frame_material_texture_strength := 0.8:
	set(value):
		frame_material_texture_strength = value
		emit_changed()

@export_range(0.4, 1.4, 0.01) var frame_material_brightness := 1.0:
	set(value):
		frame_material_brightness = value
		emit_changed()

@export_range(0.3, 1.0, 0.01) var frame_material_edge_brightness := 0.72:
	set(value):
		frame_material_edge_brightness = value
		emit_changed()

@export_range(0.0, 1.0, 0.01) var frame_material_procedural_detail := 0.35:
	set(value):
		frame_material_procedural_detail = value
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

@export var board_shadow_enabled := true:
	set(value):
		board_shadow_enabled = value
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

@export_range(0.0, 64.0, 1.0) var reference_shadow_softness := 18.0:
	set(value):
		reference_shadow_softness = value
		emit_changed()
