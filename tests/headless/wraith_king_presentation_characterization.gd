extends Node

var failures: Array[String] = []

func _ready() -> void:
	var game: ChessGame = preload("res://scenes/chess_game.tscn").instantiate()
	game.play_opening_presentation = false
	game.apply_initial_piece_placement_variation = false
	game.resolve_unplayable_turns_after_rebuild = false
	game.control_mode = ChessGame.ControlMode.PLAYER_VS_PLAYER
	add_child(game)
	await get_tree().process_frame
	var model := game.model
	var position := ChessPosition.new()
	for spec in [[&"wraith_king", "white", Vector2i(4, 4)], [&"pawn", "white", Vector2i(3, 3)], [&"rook", "black", Vector2i(0, 0)], [&"classic_king", "black", Vector2i(0, 7)]]:
		position.pieces.append(ChessPieceCatalog.create_piece(spec[0], spec[1], spec[2]).capture_piece_state())
	_check(model.load_position(position), "Wraith presentation fixture loads")
	await get_tree().process_frame
	var king := model.get_king("white") as WraithKing
	var target := model.board[0][0] as ModelPiece
	model.add_tile_effect(&"cursed_mark", Vector2i(2, 2), "white", king.piece_id)
	await model.summon_wraith(king, target)
	var adapter := game.get_node("ChessPresentationAdapter") as ChessPresentationAdapter
	var entity := model.autonomous_entities[0]
	var sprite := adapter.autonomous_entity_views.get(entity.entity_id) as Sprite2D
	var mark_view := adapter.tile_effect_views.values()[0] as Node2D
	_check(adapter.tile_effect_views.size() == 1 and is_instance_valid(mark_view), "Cursed Mark has an independent tile-effect view")
	_check(mark_view.get_node_or_null("Stain") is Polygon2D and mark_view.get_node_or_null("Outline") is Line2D and mark_view.get_node_or_null("Rune") is Line2D, "Cursed Mark visibly fills and outlines its square with a placeholder rune")
	_check(is_instance_valid(sprite) and is_equal_approx(sprite.modulate.a, 0.5), "summoned Wraith reuses team art at half opacity")
	_check(is_instance_valid(sprite) and sprite.texture == load("res://assets/pieces/kings/white_wraith.png"), "White Wraith uses White Wraith King artwork")
	model.remove_tile_effect(&"cursed_mark", Vector2i(2, 2), king.piece_id)
	await get_tree().process_frame
	_check(adapter.tile_effect_views.is_empty() and not is_instance_valid(mark_view), "Cursed Mark placeholder disappears when the mark is consumed")
	game.queue_free()
	await get_tree().process_frame
	if failures.is_empty():
		print("WRAITH KING PRESENTATION CHARACTERIZATION: PASS")
		get_tree().quit(0)
	else:
		for failure in failures: printerr(" - ", failure)
		printerr("WRAITH KING PRESENTATION CHARACTERIZATION: FAIL")
		get_tree().quit(1)

func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
