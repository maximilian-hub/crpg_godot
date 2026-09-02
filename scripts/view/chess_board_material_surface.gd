extends MeshInstance2D
class_name ChessBoardMaterialSurface

const MATERIAL_SHADER := preload("res://effects/chess_board_material.gdshader")

var surface_material := ShaderMaterial.new()


func _ready() -> void:
	surface_material.shader = MATERIAL_SHADER
	material = surface_material
	z_index = -2


func configure(projection: ChessBoardProjection, visual_style: Resource) -> void:
	visible = visual_style != null and bool(visual_style.material_surface_enabled)
	if not visible:
		mesh = null
		return
	mesh = _build_mesh(projection)
	surface_material.set_shader_parameter("light_color", visual_style.light_square_color)
	surface_material.set_shader_parameter("dark_color", visual_style.dark_square_color)
	surface_material.set_shader_parameter("light_texture", visual_style.light_square_texture)
	surface_material.set_shader_parameter("dark_texture", visual_style.dark_square_texture)
	surface_material.set_shader_parameter("use_light_texture", visual_style.light_square_texture != null)
	surface_material.set_shader_parameter("use_dark_texture", visual_style.dark_square_texture != null)
	surface_material.set_shader_parameter("board_dimensions", Vector2(projection.columns, projection.rows))
	surface_material.set_shader_parameter("texture_scale", visual_style.material_texture_scale)
	surface_material.set_shader_parameter("texture_strength", visual_style.material_texture_strength)
	surface_material.set_shader_parameter("light_brightness", visual_style.material_light_brightness)
	surface_material.set_shader_parameter("variation_strength", visual_style.material_variation_strength)
	surface_material.set_shader_parameter("procedural_detail", visual_style.material_procedural_detail)
	surface_material.set_shader_parameter("seam_width", visual_style.material_seam_width)
	surface_material.set_shader_parameter("seam_color", visual_style.material_seam_color)


func _build_mesh(projection: ChessBoardProjection) -> ArrayMesh:
	var vertices := PackedVector2Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for row in range(projection.rows):
		for column in range(projection.columns):
			var base := vertices.size()
			var points: Array = [
				projection.intersections[row][column],
				projection.intersections[row][column + 1],
				projection.intersections[row + 1][column + 1],
				projection.intersections[row + 1][column],
			]
			for point in points:
				vertices.append(point)
			uvs.append(Vector2(float(column) / projection.columns, float(row) / projection.rows))
			uvs.append(Vector2(float(column + 1) / projection.columns, float(row) / projection.rows))
			uvs.append(Vector2(float(column + 1) / projection.columns, float(row + 1) / projection.rows))
			uvs.append(Vector2(float(column) / projection.columns, float(row + 1) / projection.rows))
			indices.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result
