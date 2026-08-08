extends Node

var failures: Array[String] = []
var checks: int = 0

func _ready() -> void:
	await _run()
	if failures.is_empty():
		print("HEADLESS MODEL CHARACTERIZATION: PASS (", checks, " checks)")
		get_tree().quit(0)
		return
	for failure in failures:
		printerr(" - ", failure)
	printerr("HEADLESS MODEL CHARACTERIZATION: FAIL")
	get_tree().quit(1)

func _run() -> void:
	_test_completion_gate_contract()
	await _test_initialization_and_move()
	await _test_special_moves()
	await _test_headless_rage()
	await _test_headless_reaction_priority()
	await _test_model_owned_raise_dead_choice()
	await _test_complete_battle_from_commands()

func _test_completion_gate_contract() -> void:
	var unclaimed := CompletionGate.new()
	unclaimed.close()
	_expect(unclaimed.is_completed(), "unclaimed completion gate resolves immediately")
	var claimed := CompletionGate.new()
	claimed.hold()
	claimed.close()
	_expect(not claimed.is_completed(), "claimed completion gate waits after emission closes")
	claimed.release()
	_expect(claimed.is_completed(), "claimed completion gate resolves after release")

func _test_initialization_and_move() -> void:
	var model := ChessBoardModel.new()
	_expect(model.initialize_battle(), "standalone Model initializes explicitly")
	_expect(not model.initialize_battle(), "standalone initialization is idempotent")
	_expect(_count_pieces(model) == 32, "standalone Model creates the default board")
	var pawn: ModelPiece = model.board[6][0]
	_expect(await model.submit_move(pawn, Vector2i(4, 0)), "standalone Model accepts a legal move")
	_expect(model.board[4][0] == pawn and model.current_turn == "black", "headless move resolves state and turn")
	_expect(not model.action_in_progress, "unobserved movement gate completes immediately")
	_expect(not (await model.submit_move(pawn, Vector2i(3, 0))), "wrong-turn command is rejected")
	model.free()

func _test_headless_rage() -> void:
	var model := _new_empty_model()
	var minotaur := MinotaurKing.new("black", Vector2i(3, 3))
	var pawn := Pawn.new("white", Vector2i(3, 4))
	model.add_piece(minotaur, minotaur.coordinate)
	model.add_piece(pawn, pawn.coordinate)
	_expect(model.begin_action("white"), "headless Rage action starts")
	await minotaur.take_damage(1)
	await model.continue_action_resolution()
	_expect(model.board[3][4] == null, "headless Rage resolves adjacent damage")
	_expect(model.current_turn == "black", "headless Rage completes the action")
	model.free()

func _test_headless_reaction_priority() -> void:
	var model := _new_empty_model()
	var minotaur := MinotaurKing.new("black", Vector2i(3, 3))
	var necromancer := NecromancerKing.new("black", Vector2i(0, 0))
	var rook := Rook.new("white", Vector2i(6, 6))
	model.add_piece(minotaur, minotaur.coordinate)
	model.add_piece(necromancer, necromancer.coordinate)
	model.add_piece(rook, rook.coordinate)
	var observation := {"rage_effects": 0}
	model.ability_effect_resolved.connect(
		func(_piece: KingPiece, ability_name: String, _coords: Array):
			if ability_name == MinotaurKing.PASSIVE_ABILITY_NAME:
				observation["rage_effects"] += 1
	)
	model.begin_action("white")
	model.destroy_piece(rook, true)
	await minotaur.take_damage(1)
	await model.continue_action_resolution()
	_expect(observation["rage_effects"] == 1, "automatic Rage resolves before a pending choice")
	_expect(model.get_pending_reaction()["calling_piece"] == necromancer, "Raise Dead remains pending after higher-priority Rage")
	var target: Vector2i = model.get_pending_reaction()["targets"][0]
	await model.submit_reaction_selection(target)
	model.free()

func _test_special_moves() -> void:
	var castle_model := _new_empty_model()
	var king := ClassicKing.new("white", Vector2i(7, 4))
	var rook := Rook.new("white", Vector2i(7, 7))
	castle_model.add_piece(king, king.coordinate)
	castle_model.add_piece(rook, rook.coordinate)
	_expect(await castle_model.submit_move(king, Vector2i(7, 6)), "headless castling command is accepted")
	_expect(castle_model.board[7][6] == king and castle_model.board[7][5] == rook, "castling moves rook before completing king move")
	castle_model.free()

	var passant_model := _new_empty_model()
	var white_pawn := Pawn.new("white", Vector2i(3, 4))
	var black_pawn := Pawn.new("black", Vector2i(3, 5))
	passant_model.add_piece(white_pawn, white_pawn.coordinate)
	passant_model.add_piece(black_pawn, black_pawn.coordinate)
	passant_model.last_move = {"piece": black_pawn, "from": Vector2i(1, 5), "to": Vector2i(3, 5)}
	_expect(await passant_model.submit_move(white_pawn, Vector2i(2, 5)), "headless en passant command is accepted")
	_expect(passant_model.board[2][5] == white_pawn and passant_model.board[3][5] == null, "en passant removes the adjacent pawn")
	passant_model.free()

	var promotion_model := _new_empty_model()
	var promoting_pawn := Pawn.new("white", Vector2i(1, 0))
	promotion_model.add_piece(promoting_pawn, promoting_pawn.coordinate)
	_expect(await promotion_model.submit_move(promoting_pawn, Vector2i(0, 0)), "headless promotion move is accepted")
	_expect(promotion_model.board[0][0] is Queen, "promotion replaces the pawn with a Queen")
	promotion_model.free()

func _test_model_owned_raise_dead_choice() -> void:
	var model := _new_empty_model()
	var necromancer := NecromancerKing.new("black", Vector2i(0, 0))
	var bishop := Bishop.new("white", Vector2i(4, 4))
	model.add_piece(necromancer, necromancer.coordinate)
	model.add_piece(bishop, bishop.coordinate)
	_expect(model.begin_action("white"), "headless Raise Dead action starts")
	model.destroy_piece(bishop, true)
	await model.continue_action_resolution()
	_expect(model.has_pending_reaction(), "Model owns the pending Raise Dead decision")
	var pending := model.get_pending_reaction()
	_expect(pending["calling_piece"] == necromancer, "pending decision identifies its reacting piece")
	var target: Vector2i = pending["targets"][0]
	_expect(not (await model.submit_reaction_selection(Vector2i(-1, -1))), "invalid reaction choice is rejected")
	_expect(model.has_pending_reaction(), "invalid reaction choice preserves pending state")
	_expect(await model.submit_reaction_selection(target), "valid reaction choice is accepted")
	_expect(model.board[target.x][target.y] is BonePawn, "headless Raise Dead summons a Bone Pawn")
	_expect(not model.action_in_progress and model.current_turn == "black", "reaction submission resumes and finishes the action")
	model.free()

func _test_complete_battle_from_commands() -> void:
	var model := _new_empty_model()
	var arakne := ArakneKing.new("white", Vector2i(4, 4))
	var black_king := ClassicKing.new("black", Vector2i(3, 3))
	model.add_piece(arakne, arakne.coordinate)
	model.add_piece(black_king, black_king.coordinate)
	_expect(await model.submit_active_ability(arakne, black_king.coordinate), "headless active-ability command is accepted")
	_expect(model.battle_over, "headless command sequence completes a battle")
	_expect(model.battle_result == "white", "headless battle records the winner")
	model.free()

func _new_empty_model() -> ChessBoardModel:
	var model := ChessBoardModel.new()
	model.initialize_battle()
	for row in model.board:
		for piece in row:
			if piece != null:
				model.unregister_piece(piece)
	model.board.clear()
	for row_index in range(8):
		var row: Array = []
		for column_index in range(8):
			row.append(null)
		model.board.append(row)
	model.last_move = {}
	model.current_turn = "white"
	model.battle_over = false
	model.battle_result = ""
	model.defeated_king_colors.clear()
	model.selection_queue.clear()
	model.pending_reaction.clear()
	model.action_in_progress = false
	model.action_owner_color = ""
	return model

func _count_pieces(model: ChessBoardModel) -> int:
	var count := 0
	for row in model.board:
		for piece in row:
			if piece != null:
				count += 1
	return count

func _expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
