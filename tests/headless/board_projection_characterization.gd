extends Node

const BOARD_BODY_SCENE := preload("res://scenes/board_body.tscn")
const DEFAULT_VISUAL_STYLE := preload("res://assets/chess_board_default_style.tres")
const PIECE_SCENE := preload("res://scenes/piece.tscn")

var failures: Array[String] = []
var checks := 0


func _ready() -> void:
	_test_geometry(Vector2(1920, 1080))
	_test_geometry(Vector2(960, 540))
	_test_player_relative_orientation()
	_test_adjustable_layout()
	_test_board_body(Vector2(1920, 1080))
	_test_board_body(Vector2(960, 540))
	_test_piece_ground_anchors()
	_test_fixed_battle_layout()
	_test_fluid_world_scale()
	if failures.is_empty():
		print("BOARD PROJECTION CHARACTERIZATION: PASS (", checks, " checks)")
		get_tree().quit(0)
		return
	for failure in failures:
		printerr(" - ", failure)
	get_tree().quit(1)


func _test_geometry(viewport_size: Vector2) -> void:
	var projection := ChessBoardProjection.new()
	projection.configure(viewport_size, 8, 8, "white")
	var outline := projection.get_board_outline()
	_expect(outline[1].x - outline[0].x < outline[2].x - outline[3].x, "far edge is narrower than near edge")
	for point in outline:
		_expect(point.x >= 0.0 and point.x <= viewport_size.x, "board outline stays within viewport width")
		_expect(point.y >= 0.0 and point.y <= viewport_size.y, "board outline stays within viewport height")
	for row in range(8):
		for column in range(7):
			var left := projection.get_cell_polygon(Vector2i(row, column))
			var right := projection.get_cell_polygon(Vector2i(row, column + 1))
			_expect(left[1] == right[0] and left[2] == right[3], "horizontal neighbors share their complete edge")
	for row in range(7):
		for column in range(8):
			var far_cell := projection.get_cell_polygon(Vector2i(row, column))
			var near_cell := projection.get_cell_polygon(Vector2i(row + 1, column))
			_expect(far_cell[3] == near_cell[0] and far_cell[2] == near_cell[1], "vertical neighbors share their complete edge")


func _test_player_relative_orientation() -> void:
	var white_view := ChessBoardProjection.new()
	white_view.configure(Vector2(1920, 1080), 8, 8, "white")
	var black_view := ChessBoardProjection.new()
	black_view.configure(Vector2(1920, 1080), 8, 8, "black")
	_expect(white_view.get_cell_anchor(Vector2i(7, 0)).y > white_view.get_cell_anchor(Vector2i(0, 0)).y, "White back rank is nearest from White's seat")
	_expect(black_view.get_cell_anchor(Vector2i(0, 0)).y > black_view.get_cell_anchor(Vector2i(7, 0)).y, "Black back rank is nearest from Black's seat")
	_expect(black_view.get_cell_anchor(Vector2i(0, 0)).x > black_view.get_cell_anchor(Vector2i(0, 7)).x, "Black viewpoint reverses files")
	var board_view := ChessBoardView.new()
	board_view.projection = white_view
	_expect(board_view.get_piece_depth(Vector2i(7, 0)) - board_view.get_piece_depth(Vector2i(6, 0)) == ChessBoardView.BOARD_DEPTH_STRIDE, "adjacent displayed rows reserve one complete hand-layer depth band")
	board_view.projection = black_view
	_expect(board_view.get_piece_depth(Vector2i(0, 0)) - board_view.get_piece_depth(Vector2i(1, 0)) == ChessBoardView.BOARD_DEPTH_STRIDE, "Black perspective reverses row depth while preserving the hand-layer band")
	_expect(PlayerHandRig.GRIP_FRONT_Z > 7 * ChessBoardView.BOARD_DEPTH_STRIDE, "front grip remains above ordinary board pieces")
	_expect(PlayerHandRig.GRIP_BACK_Z < PlayerHandRig.ACTIVE_PIECE_Z and PlayerHandRig.ACTIVE_PIECE_Z < PlayerHandRig.CAPTURED_PIECE_Z and PlayerHandRig.CAPTURED_PIECE_Z < PlayerHandRig.PLACEMENT_OCCLUDER_Z and PlayerHandRig.PLACEMENT_OCCLUDER_Z < PlayerHandRig.GRIP_FRONT_Z, "absolute grip stack supports a placement occluder between carried pieces and the front grip")
	_expect(PlayerHandRig.GRIP_FRONT_Z < PlayerHandRig.INTERACTION_OCCLUDER_Z and PlayerHandRig.INTERACTION_OCCLUDER_Z < PlayerHandRig.ARM_FOREGROUND_Z, "temporary interaction occluders fit between the front grip and foreground arm")
	_expect(ChessBoardView.BOARD_EFFECT_Z > PlayerHandRig.ARM_FOREGROUND_Z, "board effects remain above the foreground arm")
	board_view.free()


func _test_adjustable_layout() -> void:
	var projection := ChessBoardProjection.new()
	projection.configure(Vector2(1920, 1080), 8, 8, "white")
	var original_outline := projection.get_board_outline()
	projection.configure(Vector2(1920, 1080), 8, 8, "white", 0.80, 0.55, 0.90, 0.98, 0.42)
	var adjusted_outline := projection.get_board_outline()
	_expect(adjusted_outline != original_outline, "layout ratios change projected geometry")
	_expect(adjusted_outline[0].y < original_outline[0].y, "vertical center ratio moves the board")
	_expect(projection.get_near_edge_width() > 0.0, "projection exposes its near-edge width")
	_expect(projection.get_presentation_scale() > 0.0, "projection exposes a positive presentation scale")
	var coordinate := Vector2i(4, 4)
	var center := projection.get_cell_center(coordinate)
	var forward_anchor := projection.get_piece_ground_anchor(coordinate, 0.10)
	_expect(forward_anchor.y > center.y, "piece bias moves the ground anchor toward the viewer")


func _test_board_body(viewport_size: Vector2) -> void:
	var projection := ChessBoardProjection.new()
	projection.configure(viewport_size, 8, 8, "white")
	var body := BOARD_BODY_SCENE.instantiate()
	add_child(body)
	body.configure(
		projection.get_board_outline(),
		projection.get_presentation_scale(),
		DEFAULT_VISUAL_STYLE
	)
	var near_frame := body.get_node("TopFrame/Near") as Polygon2D
	var front := body.get_node("Thickness/Front") as Polygon2D
	var shadow := body.get_node("Shadow") as Polygon2D
	_expect(near_frame.polygon.size() == 4, "generated renderer creates a four-point near frame")
	_expect(front.polygon.size() == 4, "generated renderer creates a four-point front face")
	_expect(shadow.polygon.size() == 4, "generated renderer creates a four-point contact shadow")
	for polygon_node in [near_frame, front, shadow]:
		for point in polygon_node.polygon:
			_expect(point.x >= 0.0 and point.x <= viewport_size.x, "physical board remains inside viewport width")
			_expect(point.y >= 0.0 and point.y <= viewport_size.y, "physical board remains inside viewport height")
	body.queue_free()


func _test_piece_ground_anchors() -> void:
	var models: Array[ModelPiece] = [
		Pawn.new("white", Vector2i.ZERO),
		MinotaurKing.new("white", Vector2i.ZERO),
		BonePawn.new("white", Vector2i.ZERO),
		NecromancerKing.new("white", Vector2i.ZERO),
		ArakneKing.new("white", Vector2i.ZERO),
	]
	for model in models:
		var piece := PIECE_SCENE.instantiate() as PieceView
		add_child(piece)
		piece.set_model(model)
		_expect(is_zero_approx(piece.get_sprite_bottom_local_y()), "%s artwork rests on the PieceView ground origin" % model.type)
		_expect(piece.get_sprite_top_local_y() < 0.0, "%s artwork extends upward from its ground origin" % model.type)
		_expect(piece.get_ground_anchor().position == Vector2.ZERO, "%s ground effect anchor remains at the board-contact origin" % model.type)
		_expect(piece.get_body_anchor().position == piece.sprite.position, "%s body effect anchor tracks the artwork center" % model.type)
		_expect(is_equal_approx(piece.get_head_anchor().position.y, piece.get_sprite_top_local_y()), "%s head effect anchor tracks the artwork top" % model.type)
		_expect(piece.get_grip_anchor().position != piece.get_head_anchor().position, "%s grip anchor is independently configured from its head anchor" % model.type)
		_expect(piece.sprite.texture.resource_path.begins_with("res://assets/pieces/"), "%s resolves through its configured art profile" % model.type)
		if model is MinotaurKing:
			_expect(piece.sprite.texture.resource_path == "res://assets/pieces/kings/white_minotaur.png", "White Minotaur King resolves its authored White art")
			_expect(piece.sprite.material == null, "authored White Minotaur art bypasses the White palette shader")
			var displayed_height := float(piece.sprite.texture.get_height()) * absf(piece.sprite.scale.y)
			_expect(is_equal_approx(displayed_height, piece.art_profile.display_height), "Minotaur King source resolution normalizes to its configured board height")
		elif model is NecromancerKing:
			_expect(piece.sprite.texture.resource_path == "res://assets/pieces/kings/white_necromancer.png", "White Necromancer King resolves its authored White art")
			_expect(piece.sprite.material == null, "authored White Necromancer art bypasses the White palette shader")
			var displayed_height := float(piece.sprite.texture.get_height()) * absf(piece.sprite.scale.y)
			_expect(is_equal_approx(displayed_height, piece.art_profile.display_height), "Necromancer King source resolution normalizes to its configured board height")
		elif model is ArakneKing:
			_expect(piece.sprite.texture.resource_path == "res://assets/pieces/kings/white_arakne.png", "White Arakne King resolves its authored White art")
			_expect(piece.sprite.material == null, "authored White Arakne art bypasses the White palette shader")
			var displayed_height := float(piece.sprite.texture.get_height()) * absf(piece.sprite.scale.y)
			_expect(is_equal_approx(displayed_height, piece.art_profile.display_height), "Arakne King source resolution normalizes to its configured board height")
		elif model is BonePawn:
			_expect(piece.sprite.texture.resource_path == "res://assets/pieces/special/white_bone_pawn.png", "White Bone Pawn resolves its authored White art")
			_expect(piece.sprite.material == null, "authored White Bone Pawn art bypasses the White palette shader")
			var displayed_height := float(piece.sprite.texture.get_height()) * absf(piece.sprite.scale.y)
			_expect(is_equal_approx(displayed_height, piece.art_profile.display_height), "Bone Pawn source resolution normalizes to its configured pawn board height")
		else:
			_expect(piece.sprite.material is ShaderMaterial, "%s receives the fallback White palette" % model.type)
		piece.queue_free()
	var black_piece := PIECE_SCENE.instantiate() as PieceView
	add_child(black_piece)
	black_piece.set_model(Queen.new("black", Vector2i.ZERO))
	_expect(black_piece.sprite.texture.resource_path == "res://assets/pieces/standard/black_queen.png", "Black Queen uses its standardized authored texture")
	_expect(black_piece.sprite.material == null, "Black authored art is not palette transformed")
	black_piece.queue_free()
	var black_minotaur := PIECE_SCENE.instantiate() as PieceView
	add_child(black_minotaur)
	black_minotaur.set_model(MinotaurKing.new("black", Vector2i.ZERO))
	_expect(black_minotaur.sprite.texture.resource_path == "res://assets/pieces/kings/black_minotaur.png", "Black Minotaur King resolves its authored Black art")
	_expect(black_minotaur.sprite.material == null, "authored Black Minotaur art is not palette transformed")
	black_minotaur.queue_free()
	var black_necromancer := PIECE_SCENE.instantiate() as PieceView
	add_child(black_necromancer)
	black_necromancer.set_model(NecromancerKing.new("black", Vector2i.ZERO))
	_expect(black_necromancer.sprite.texture.resource_path == "res://assets/pieces/kings/black_necromancer.png", "Black Necromancer King resolves its authored Black art")
	_expect(black_necromancer.sprite.material == null, "authored Black Necromancer art is not palette transformed")
	black_necromancer.queue_free()
	var black_arakne := PIECE_SCENE.instantiate() as PieceView
	add_child(black_arakne)
	black_arakne.set_model(ArakneKing.new("black", Vector2i.ZERO))
	_expect(black_arakne.sprite.texture.resource_path == "res://assets/pieces/kings/black_arakne.png", "Black Arakne King resolves its authored Black art")
	_expect(black_arakne.sprite.material == null, "authored Black Arakne art is not palette transformed")
	black_arakne.queue_free()
	var black_bone_pawn := PIECE_SCENE.instantiate() as PieceView
	add_child(black_bone_pawn)
	black_bone_pawn.set_model(BonePawn.new("black", Vector2i.ZERO))
	_expect(black_bone_pawn.sprite.texture.resource_path == "res://assets/pieces/special/black_bone_pawn.png", "Black Bone Pawn resolves its authored Black art")
	_expect(black_bone_pawn.sprite.material == null, "authored Black Bone Pawn art is not palette transformed")
	black_bone_pawn.queue_free()
	var profile := PieceArtProfile.new()
	profile.display_height = 64.0
	profile.reference_texture = ImageTexture.create_from_image(Image.create_empty(8, 128, false, Image.FORMAT_RGBA8))
	profile.white_texture = ImageTexture.create_from_image(Image.create_empty(8, 256, false, Image.FORMAT_RGBA8))
	_expect(is_equal_approx(profile.texture_scale(profile.texture_for_color("black")), 0.5), "Black art scales from its selected texture height")
	_expect(is_equal_approx(profile.texture_scale(profile.texture_for_color("white")), 0.25), "authored White art independently scales from its selected texture height")

func _test_fixed_battle_layout() -> void:
	var cases := {
		Vector2i(960, 540): 1,
		Vector2i(1280, 720): 1,
		Vector2i(1920, 1080): 2,
		Vector2i(2560, 1440): 2,
		Vector2i(3840, 2160): 4,
	}
	for window_size in cases:
		var layout := GameFlow.calculate_battle_layout(window_size)
		_expect(layout.integer_scale == cases[window_size], "%s selects the expected integer battle scale" % window_size)
		_expect(layout.frame_size == GameFlow.BATTLE_LOGICAL_SIZE * layout.integer_scale, "%s preserves the fixed logical aspect" % window_size)
		_expect(layout.position == Vector2((window_size - layout.frame_size) / 2), "%s centers the battle frame" % window_size)

func _test_fluid_world_scale() -> void:
	_expect(is_equal_approx(ChessBoardView.calculate_world_scale(486.0), 1.0), "960x540 projected board remains the 1x piece reference")
	_expect(is_equal_approx(ChessBoardView.calculate_world_scale(972.0), 2.0), "doubling projected board width doubles every piece")
	_expect(is_equal_approx(ChessBoardView.calculate_world_scale(1440.0), 1440.0 / 486.0), "fluid piece scale preserves fractional window fit")


func _expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
