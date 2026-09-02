extends Node2D
class_name ChessBoardFrameSurface

const FRAME_SHADER := preload("res://effects/chess_board_frame_material.gdshader")

@onready var top_surface: MeshInstance2D = $Top
@onready var edge_surface: MeshInstance2D = $Edges


func configure(top_quads: Array[PackedVector2Array], edge_quads: Array[PackedVector2Array], presentation_scale: float, visual_style: Resource) -> void:
	visible = visual_style != null and bool(visual_style.frame_material_enabled)
	if not visible:
		top_surface.mesh = null
		edge_surface.mesh = null
		return
	top_surface.mesh = _build_strip_mesh(top_quads, presentation_scale)
	edge_surface.mesh = _build_strip_mesh(edge_quads, presentation_scale)
	_configure_material(top_surface, visual_style.frame_top_color, visual_style.frame_top_texture, visual_style, 1.0)
	_configure_material(edge_surface, visual_style.frame_front_color, visual_style.frame_edge_texture, visual_style, visual_style.frame_material_edge_brightness)


func _configure_material(surface: MeshInstance2D, base_color: Color, texture: Texture2D, visual_style: Resource, face_brightness: float) -> void:
	var shader_material := surface.material as ShaderMaterial
	if shader_material == null:
		shader_material = ShaderMaterial.new()
		shader_material.shader = FRAME_SHADER
		surface.material = shader_material
	shader_material.set_shader_parameter("base_color", base_color)
	shader_material.set_shader_parameter("material_texture", texture)
	shader_material.set_shader_parameter("use_texture", texture != null)
	shader_material.set_shader_parameter("texture_scale", visual_style.frame_material_texture_scale)
	shader_material.set_shader_parameter("grain_tightness", visual_style.frame_material_grain_tightness)
	shader_material.set_shader_parameter("texture_strength", visual_style.frame_material_texture_strength)
	shader_material.set_shader_parameter("brightness", visual_style.frame_material_brightness * face_brightness)
	shader_material.set_shader_parameter("procedural_detail", visual_style.frame_material_procedural_detail)


func _build_strip_mesh(quads: Array[PackedVector2Array], presentation_scale: float) -> ArrayMesh:
	var vertices := PackedVector2Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var reference_repeat_length := maxf(128.0 * presentation_scale, 1.0)
	for quad in quads:
		if quad.size() != 4: continue
		var base := vertices.size()
		vertices.append_array(quad)
		var repeats := maxf((quad[0].distance_to(quad[1]) + quad[3].distance_to(quad[2])) * 0.5 / reference_repeat_length, 0.25)
		uvs.append_array(PackedVector2Array([Vector2(0, 0), Vector2(repeats, 0), Vector2(repeats, 1), Vector2(0, 1)]))
		indices.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result
