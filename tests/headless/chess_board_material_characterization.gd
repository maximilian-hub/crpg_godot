extends Node

const BOARD_BODY_SCENE := preload("res://scenes/board_body.tscn")
const STYLE := preload("res://assets/chess_board_default_style.tres")
const BoardMaterialSurface := preload("res://scripts/view/chess_board_material_surface.gd")
const LAB_SCENE := preload("res://tools/dev_chess_board/chess_board_lab.tscn")
const RuntimePublisher := preload("res://tools/dev_chess_shared/chess_lab_runtime_publisher.gd")

var failures := 0


func _ready() -> void:
	var body := BOARD_BODY_SCENE.instantiate() as BoardBodyView
	add_child(body)
	var style := STYLE.duplicate(true) as ChessBoardVisualStyle
	style.material_surface_enabled = true
	var projection := ChessBoardProjection.new()
	projection.configure(Vector2(1280, 720), 8, 8)
	body.configure(projection.get_board_outline(), projection.get_presentation_scale(), style)
	var surface := body.get_node("MaterialSurface") as MeshInstance2D
	surface.configure(projection, style)
	_check(surface.visible and surface.mesh != null and surface.mesh.surface_get_array_len(0) == 256, "8x8 material surface builds four shared-geometry vertices per cell")
	var outline_8 := projection.get_board_outline()
	projection.configure(Vector2(1280, 720), 6, 6)
	body.configure(projection.get_board_outline(), projection.get_presentation_scale(), style)
	surface.configure(projection, style)
	_check(surface.mesh.surface_get_array_len(0) == 144 and projection.get_board_outline() == outline_8, "6x6 changes material cell frequency without changing the physical board outline")
	style.frame_material_enabled = true
	body.configure(projection.get_board_outline(), projection.get_presentation_scale(), style)
	var frame_surface := body.get_node("MaterialFrame")
	_check(frame_surface.visible and frame_surface.top_surface.mesh.surface_get_array_len(0) == 16 and frame_surface.edge_surface.mesh.surface_get_array_len(0) == 12, "Material frame maps four top rails and three visible thickness faces from the projected outline")
	_check(not body.get_node("TopFrame").visible and not body.get_node("Thickness").visible, "Material frame replaces flat frame polygons without changing geometry")
	var shadow: Polygon2D = body.get_node("Shadow")
	var shadow_mid: Polygon2D = body.get_node("ShadowMid")
	var shadow_soft: Polygon2D = body.get_node("ShadowSoft")
	_check(shadow.polygon.size() == 4 and shadow_mid.polygon.size() == 4 and shadow_soft.polygon.size() == 4, "Board body builds three outline-following contact-shadow layers")
	_check(shadow_soft.polygon[0].distance_to(shadow_soft.polygon[2]) > shadow.polygon[0].distance_to(shadow.polygon[2]), "Soft shadow layer spreads beyond the contact core")
	_check(shadow.color.a > shadow_mid.color.a and shadow_mid.color.a > shadow_soft.color.a, "Contact shadow density falls off across the penumbra")
	style.board_shadow_enabled = false
	body.configure(projection.get_board_outline(), projection.get_presentation_scale(), style)
	_check(not shadow.visible and not shadow_mid.visible and not shadow_soft.visible, "Board shadow switch hides every contact-shadow layer together")
	style.board_shadow_enabled = true
	body.configure(projection.get_board_outline(), projection.get_presentation_scale(), style)
	_check(shadow.visible and shadow_mid.visible and shadow_soft.visible, "Board shadow switch restores every contact-shadow layer together")
	style.frame_material_enabled = false
	body.configure(projection.get_board_outline(), projection.get_presentation_scale(), style)
	_check(not frame_surface.visible and body.get_node("TopFrame").visible and body.get_node("Thickness").visible, "Flat frame remains available as a safe fallback")
	style.material_surface_enabled = false
	surface.configure(projection, style)
	_check(not surface.visible and surface.mesh == null, "flat-color fallback disables and clears the material surface")
	var lab := LAB_SCENE.instantiate()
	add_child(lab)
	await get_tree().process_frame
	_check(lab.environment_surface.visible and lab.environment_surface.mesh is QuadMesh, "Board Lab presents its replaceable environment through a viewport-filling surface")
	lab.environment_style.texture_enabled = false
	_check(lab.environment_surface.visible and not bool(lab.environment_surface.surface_material.get_shader_parameter("use_texture")), "Disabling environment texture preserves the flat-color fallback")
	lab.environment_style.texture_scale = 2.25
	lab.environment_style.brightness = 0.81
	_check(is_equal_approx(lab.environment_style.texture_scale, 2.25) and is_equal_approx(lab.environment_style.brightness, 0.81), "Environment texture scale and nondestructive brightness remain independent of board geometry")
	lab._set_environment_version(0)
	_check(lab.environment_style.surface_texture.resource_path.ends_with("portable_walnut_table_256_v1.png"), "Board Lab can restore the original downscaled tabletop")
	lab._set_environment_version(1)
	_check(lab.environment_style.surface_texture.resource_path.ends_with("portable_walnut_table_256_v2.png"), "Board Lab can compare the posterized RPG tabletop treatment")
	_check(lab.pieces.get_child_count() == 4, "Board Lab begins with representative piece samples")
	lab.piece_mode = 1
	lab._rebuild_pieces()
	_check(lab.pieces.get_child_count() == 32, "Board Lab can display the game's complete starting armies")
	lab.board_size = 6
	lab._sync_piece_mode_availability()
	lab._refresh_board()
	_check(lab.piece_mode == 0 and lab.pieces.get_child_count() == 4, "6x6 Board Lab safely returns to sample mode until small-board armies are designed")
	lab.visual_style.material_light_brightness = 0.72
	_check(is_equal_approx(lab.visual_style.material_light_brightness, 0.72), "Board Lab exposes nondestructive light-material brightness grading")
	lab._set_material_version(0)
	_check(lab.visual_style.light_square_texture.resource_path.ends_with("ivory_marble_128_v1.png") and lab.visual_style.dark_square_texture.resource_path.ends_with("burgundy_marble_128_v1.png"), "Board Lab can restore the original downscaled material pair")
	lab._set_material_version(1)
	_check(lab.visual_style.light_square_texture.resource_path.ends_with("ivory_marble_128_v2.png") and lab.visual_style.dark_square_texture.resource_path.ends_with("burgundy_marble_128_v2.png"), "Board Lab can compare the posterized RPG material pair")
	lab._set_frame_material_version(0)
	_check(lab.visual_style.frame_top_texture.resource_path.ends_with("dark_wood_frame_128_v1.png") and lab.visual_style.frame_edge_texture == lab.visual_style.frame_top_texture, "Board Lab can preview the original wood downscale on top and thickness faces")
	lab._set_frame_material_version(1)
	_check(lab.visual_style.frame_top_texture.resource_path.ends_with("dark_wood_frame_128_v2.png") and lab.visual_style.frame_edge_texture == lab.visual_style.frame_top_texture, "Board Lab can compare the posterized RPG wood treatment")
	lab.visual_style.frame_material_grain_tightness = 0.42
	_check(is_equal_approx(lab.visual_style.frame_material_grain_tightness, 0.42), "Board Lab exposes independent cross-rail grain tightness")
	lab._set_shadow_opacity(0.48)
	lab._set_shadow_offset_x(7.0)
	lab._set_shadow_offset_y(19.0)
	_check(is_equal_approx(lab.visual_style.shadow_color.a, 0.48) and lab.visual_style.reference_shadow_offset == Vector2(7.0, 19.0), "Board Lab exposes shadow opacity and two-axis placement")
	lab.visual_style.reference_shadow_softness = 27.0
	_check(is_equal_approx(lab.visual_style.reference_shadow_softness, 27.0), "Board Lab exposes contact-shadow softness")
	var board_publish_path := "user://chess_board_publish_characterization.tres"
	var environment_publish_path := "user://chess_environment_publish_characterization.tres"
	lab.visual_style.material_texture_scale = 1.37
	lab.visual_style.reference_shadow_offset = Vector2(8.0, 6.0)
	lab.environment_style.texture_scale = 3.25
	lab.environment_style.tint = Color("fff0df")
	var publish_result: Dictionary = lab._publish_to_game(board_publish_path, environment_publish_path)
	var published_board := ResourceLoader.load(board_publish_path, "ChessBoardVisualStyle", ResourceLoader.CACHE_MODE_IGNORE) as ChessBoardVisualStyle
	var published_environment := ResourceLoader.load(environment_publish_path, "ChessEnvironmentVisualStyle", ResourceLoader.CACHE_MODE_IGNORE) as ChessEnvironmentVisualStyle
	_check(publish_result.ok and published_board != null and published_environment != null, "Board Lab publishes both named presentation resources together")
	_check(is_equal_approx(published_board.material_texture_scale, 1.37) and published_board.reference_shadow_offset == Vector2(8.0, 6.0) and published_board.light_square_texture.resource_path == lab.visual_style.light_square_texture.resource_path, "Board publishing preserves material, shadow, and texture identity")
	_check(is_equal_approx(published_environment.texture_scale, 3.25) and published_environment.tint.is_equal_approx(Color("fff0df")) and published_environment.surface_texture.resource_path == lab.environment_style.surface_texture.resource_path, "Environment publishing preserves texture grading independently")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(board_publish_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(environment_publish_path))
	lab.queue_free()
	if failures == 0:
		print("CHESS BOARD MATERIAL CHARACTERIZATION: PASS")
	else:
		printerr("CHESS BOARD MATERIAL CHARACTERIZATION: FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _check(condition: bool, description: String) -> void:
	if condition:
		return
	failures += 1
	printerr("FAIL: ", description)
