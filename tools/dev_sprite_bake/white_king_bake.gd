# TEMPORARY DEV ART PIPELINE TOOL
# Used to bake the runtime white-piece shader into a PNG for Pixelorama source art.
# Safe to delete after the baked canonical white base has been captured.

extends Node

const SOURCE_TEXTURE_PATH := "res://assets/pieces/standard/black_king.png"
const WHITE_SHADER_PATH := "res://assets/pieces/profiles/white_piece_palette.gdshader"
const OUTPUT_DIRECTORY := "res://.cache/sprite_bakes"
const OUTPUT_PATH := OUTPUT_DIRECTORY + "/standard_white_king.png"


func _ready() -> void:
	# This Godot 4.4 macOS build maps --headless to the dummy renderer, which
	# cannot execute CanvasItem shaders or produce frame_post_draw readback.
	if DisplayServer.get_name() == "headless":
		_fail("The --headless display driver uses a dummy renderer on this Godot 4.4 macOS build. Run this scene with the normal macOS renderer.")
		return
	var source_texture := load(SOURCE_TEXTURE_PATH) as Texture2D
	if source_texture == null:
		_fail("Could not load source texture: %s" % SOURCE_TEXTURE_PATH)
		return
	var white_shader := load(WHITE_SHADER_PATH) as Shader
	if white_shader == null:
		_fail("Could not load White palette shader: %s" % WHITE_SHADER_PATH)
		return

	var source_size := source_texture.get_size()
	var viewport := SubViewport.new()
	viewport.name = "WhiteKingBakeViewport"
	viewport.size = Vector2i(source_size)
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
	sprite.name = "NativeKingSource"
	sprite.texture = source_texture
	sprite.material = material
	sprite.centered = false
	sprite.position = Vector2.ZERO
	sprite.scale = Vector2.ONE
	sprite.modulate = Color.WHITE
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	viewport.add_child(sprite)

	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var baked_image := viewport.get_texture().get_image()
	if baked_image == null or baked_image.is_empty():
		_fail("SubViewport image readback failed.")
		return
	if baked_image.get_size() != Vector2i(source_size):
		_fail("Bake resized unexpectedly: expected %s, got %s." % [Vector2i(source_size), baked_image.get_size()])
		return

	var source_image := source_texture.get_image()
	if source_image == null or source_image.is_empty():
		_fail("Could not read source image for alpha/orientation validation.")
		return
	var validation_error := _validate_alpha_alignment(source_image, baked_image)
	if not validation_error.is_empty():
		_fail(validation_error)
		return

	var output_directory_absolute := ProjectSettings.globalize_path(OUTPUT_DIRECTORY)
	var directory_error := DirAccess.make_dir_recursive_absolute(output_directory_absolute)
	if directory_error != OK:
		_fail("Could not create output directory %s (error %d)." % [output_directory_absolute, directory_error])
		return
	var output_absolute := ProjectSettings.globalize_path(OUTPUT_PATH)
	var save_error := baked_image.save_png(output_absolute)
	if save_error != OK:
		_fail("Could not save PNG to %s (error %d)." % [output_absolute, save_error])
		return

	print("WHITE KING BAKE: PASS")
	print("Dimensions: %dx%d; alpha preserved; orientation and pixel alignment verified." % [baked_image.get_width(), baked_image.get_height()])
	print("Output: %s" % output_absolute)
	get_tree().quit(0)


func _validate_alpha_alignment(source: Image, baked: Image) -> String:
	if source.get_size() != baked.get_size():
		return "Source and baked image dimensions differ during validation."
	var transparent_pixels := 0
	var visible_pixels := 0
	for y in range(source.get_height()):
		for x in range(source.get_width()):
			var source_alpha := source.get_pixel(x, y).a
			var baked_alpha := baked.get_pixel(x, y).a
			if absf(source_alpha - baked_alpha) > (1.0 / 255.0):
				return "Baked alpha mask differs at (%d, %d); output may be flipped or misaligned." % [x, y]
			if baked_alpha <= (1.0 / 255.0):
				transparent_pixels += 1
			else:
				visible_pixels += 1
	if transparent_pixels == 0:
		return "Baked image has no transparent background pixels."
	if visible_pixels == 0:
		return "Baked image contains no visible artwork."
	return ""


func _fail(message: String) -> void:
	push_error("WHITE KING BAKE: FAIL — %s" % message)
	get_tree().quit(1)
