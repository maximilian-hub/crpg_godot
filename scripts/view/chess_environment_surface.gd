extends MeshInstance2D
class_name ChessEnvironmentSurface

const SURFACE_SHADER := preload("res://effects/chess_environment_surface.gdshader")

var surface_material := ShaderMaterial.new()


func _ready() -> void:
	surface_material.shader = SURFACE_SHADER
	material = surface_material
	# The lab adds this surface before its board, and GameFlow adds ActiveContent
	# after Main's flat fallback background. Keeping the environment at ordinary
	# canvas depth therefore places it correctly in both contexts. A negative
	# z-index would put it behind Main/Background and make it invisible in-game.
	z_index = 0


func configure(viewport_size: Vector2, style: ChessEnvironmentVisualStyle) -> void:
	visible = style != null
	if style == null:
		mesh = null
		return
	var quad := mesh as QuadMesh
	if quad == null:
		quad = QuadMesh.new()
		mesh = quad
	quad.size = viewport_size
	position = viewport_size * 0.5
	surface_material.set_shader_parameter("flat_color", style.flat_color)
	surface_material.set_shader_parameter("surface_texture", style.surface_texture)
	surface_material.set_shader_parameter("use_texture", style.texture_enabled and style.surface_texture != null)
	surface_material.set_shader_parameter("texture_scale", style.texture_scale)
	surface_material.set_shader_parameter("texture_strength", style.texture_strength)
	surface_material.set_shader_parameter("brightness", style.brightness)
	surface_material.set_shader_parameter("tint", style.tint)
