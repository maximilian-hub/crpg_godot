extends Resource
class_name ChessEnvironmentVisualStyle

## Replaceable presentation for the surface beneath the physical chess board.
## This intentionally owns no board geometry or chess state.

@export var texture_enabled := false:
	set(value):
		texture_enabled = value
		emit_changed()

@export var flat_color := Color("17131c"):
	set(value):
		flat_color = value
		emit_changed()

@export var surface_texture: Texture2D:
	set(value):
		surface_texture = value
		emit_changed()

@export_range(0.25, 8.0, 0.05) var texture_scale := 1.0:
	set(value):
		texture_scale = value
		emit_changed()

@export_range(0.0, 1.0, 0.01) var texture_strength := 1.0:
	set(value):
		texture_strength = value
		emit_changed()

@export_range(0.4, 1.4, 0.01) var brightness := 1.0:
	set(value):
		brightness = value
		emit_changed()

@export var tint := Color.WHITE:
	set(value):
		tint = value
		emit_changed()
