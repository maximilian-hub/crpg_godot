# DEV ART PIPELINE TOOL
# Bakes the runtime White palette shader into all six Chunky piece PNGs.
# Run with the normal renderer; headless mode cannot execute CanvasItem shaders.

extends Node

const PIECE_NAMES := ["pawn", "rook", "knight", "bishop", "queen", "king"]
const SOURCE_DIRECTORY := "res://assets/pieces/chunky"
const WHITE_SHADER_PATH := "res://assets/pieces/profiles/white_piece_palette.gdshader"


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		_fail("The headless display driver cannot render the White palette shader. Run this scene with the normal renderer.")
		return
	var white_shader := load(WHITE_SHADER_PATH) as Shader
	if white_shader == null:
		_fail("Could not load White palette shader: %s" % WHITE_SHADER_PATH)
		return
	for piece_name in PIECE_NAMES:
		var error := await _bake_piece(piece_name, white_shader)
		if not error.is_empty():
			_fail(error)
			return
	print("WHITE PIECE BATCH BAKE: PASS")
	print("Baked %d Chunky pieces with dimensions, alpha, orientation, and pixel alignment preserved." % PIECE_NAMES.size())
	get_tree().quit(0)


func _bake_piece(piece_name: String, white_shader: Shader) -> String:
	var source_path := "%s/black_%s.png" % [SOURCE_DIRECTORY, piece_name]
	var output_path := "%s/white_%s.png" % [SOURCE_DIRECTORY, piece_name]
	var source_texture := load(source_path) as Texture2D
	if source_texture == null:
		return "Could not load source texture: %s" % source_path

	var source_size := Vector2i(source_texture.get_size())
	var viewport := SubViewport.new()
	viewport.name = "%sBakeViewport" % piece_name.capitalize()
	viewport.size = source_size
	viewport.transparent_bg = true
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.msaa_2d = Viewport.MSAA_DISABLED
	viewport.use_hdr_2d = false
	viewport.disable_3d = true
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	viewport.snap_2d_transforms_to_pixel = true
	add_child(viewport)

	var material := ShaderMaterial.new()
	material.shader = white_shader
	var sprite := Sprite2D.new()
	sprite.texture = source_texture
	sprite.material = material
	sprite.centered = false
	sprite.position = Vector2.ZERO
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	viewport.add_child(sprite)

	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var baked_image := viewport.get_texture().get_image()
	if baked_image == null or baked_image.is_empty():
		viewport.queue_free()
		return "%s image readback failed." % piece_name.capitalize()
	var source_image := source_texture.get_image()
	var validation_error := _validate_alpha_alignment(source_image, baked_image)
	if not validation_error.is_empty():
		viewport.queue_free()
		return "%s: %s" % [piece_name.capitalize(), validation_error]
	var save_error := baked_image.save_png(ProjectSettings.globalize_path(output_path))
	viewport.queue_free()
	if save_error != OK:
		return "Could not save %s (error %d)." % [output_path, save_error]
	print("Baked %s -> %s (%dx%d)" % [source_path, output_path, source_size.x, source_size.y])
	return ""


func _validate_alpha_alignment(source: Image, baked: Image) -> String:
	if source == null or source.is_empty():
		return "Could not read the source image."
	if source.get_size() != baked.get_size():
		return "Source and baked image dimensions differ."
	var transparent_pixels := 0
	var visible_pixels := 0
	for y in range(source.get_height()):
		for x in range(source.get_width()):
			var source_alpha := source.get_pixel(x, y).a
			var baked_alpha := baked.get_pixel(x, y).a
			if absf(source_alpha - baked_alpha) > (1.0 / 255.0):
				return "Alpha mask differs at (%d, %d)." % [x, y]
			if baked_alpha <= (1.0 / 255.0): transparent_pixels += 1
			else: visible_pixels += 1
	if transparent_pixels == 0: return "Baked image has no transparent pixels."
	if visible_pixels == 0: return "Baked image contains no visible artwork."
	return ""


func _fail(message: String) -> void:
	push_error("WHITE PIECE BATCH BAKE: FAIL — %s" % message)
	get_tree().quit(1)
