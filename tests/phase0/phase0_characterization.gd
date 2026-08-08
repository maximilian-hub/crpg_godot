extends Node

## Phase 0 behavior characterization.
##
## These tests deliberately exercise the current, fully composed battle scene.
## They document existing coupling as well as gameplay behavior; they are not a
## headless Model harness. A later phase must make the same rule flows available
## without constructing ChessBoardView or ChessBoardController.

const CHESS_GAME_SCENE := preload("res://scenes/chess_game.tscn")

var _failures: Array[String] = []
var _checks: int = 0


func _ready() -> void:
	await _run_suite()

	if _failures.is_empty():
		print("PHASE 0 CHARACTERIZATION: PASS (", _checks, " checks)")
		get_tree().quit(0)
		return

	printerr("PHASE 0 CHARACTERIZATION: FAIL (", _failures.size(), " failures)")
	for failure in _failures:
		printerr(" - ", failure)
	get_tree().quit(1)


func _run_suite() -> void:
	await _test_default_initialization_and_normal_move()
	await _test_arakne_spike_burst()
	await _test_minotaur_rage_barrier()
	await _test_rage_priority_before_raise_dead()
	await _test_raise_dead_selection_resume()
	await _test_battle_completion()


func _test_default_initialization_and_normal_move() -> void:
	var context := await _create_game()
	var model: ChessBoardModel = context.model
	var controller: ChessBoardController = context.controller

	_expect(_count_board_pieces(model) == 32, "default board contains 32 pieces")
	_expect(model.current_turn == "white", "default battle starts with White")
	_expect(model.get_king("white") != null, "default board has a White king")
	_expect(model.get_king("black") != null, "default board has a Black king")

	var pawn: ModelPiece = model.board[6][0]
	var legal_moves := model.get_legal_moves(pawn)
	_expect(Vector2i(5, 0) in legal_moves, "unmoved White pawn can advance one square")
	_expect(Vector2i(4, 0) in legal_moves, "unmoved White pawn can advance two clear squares")

	await model.move_piece(pawn, Vector2i(4, 0))
	_expect(model.board[4][0] == pawn and model.board[6][0] == null, "normal move updates authoritative board state")
	_expect(pawn.coordinate == Vector2i(4, 0) and pawn.has_moved, "normal move updates piece state")
	_expect(model.last_move.get("piece") == pawn, "normal move records its piece")
	_expect(model.last_move.get("from") == Vector2i(6, 0), "normal move records its origin")
	_expect(model.last_move.get("to") == Vector2i(4, 0), "normal move records its destination")
	_expect(model.current_turn == "black", "resolved normal move switches the turn")
	_expect(not model.action_in_progress, "resolved normal move closes the action")
	_expect(not controller.is_input_locked, "resolved normal move unlocks ordinary input")
	var pawn_view: Node = context.adapter.get_piece_view(pawn)
	_expect(is_instance_valid(pawn_view), "presentation maps the moved pawn to a View node")
	_expect(pawn_view.coordinate == Vector2i(4, 0), "movement animation leaves the View node at the destination")

	await _destroy_game(context.game)


func _test_arakne_spike_burst() -> void:
	var context := await _create_game()
	var model: ChessBoardModel = context.model
	var arakne := ArakneKing.new("white", Vector2i(4, 4))
	var target := MinotaurKing.new("black", Vector2i(3, 3))
	_reset_battle(model, context.controller, [arakne, target])

	var targets := arakne.get_active_ability_targets()
	_expect(Vector2i(3, 3) in targets, "Spike Burst targets an adjacent enemy")
	await model.perform_active_ability(arakne, Vector2i(3, 3))
	_expect(target.current_hp == target.max_hp - ArakneKing.SPIKE_BURST_DAMAGE, "Spike Burst applies its configured damage")
	_expect(arakne.current_cooldown == ArakneKing.ACTIVE_ABILITY_COOLDOWN, "Spike Burst resets Arakne cooldown")
	_expect(model.current_turn == "black", "Spike Burst consumes White's action")
	_expect(not model.action_in_progress, "Spike Burst finishes its action")

	await _destroy_game(context.game)


func _test_minotaur_rage_barrier() -> void:
	var context := await _create_game()
	var model: ChessBoardModel = context.model
	var minotaur := MinotaurKing.new("black", Vector2i(3, 3))
	var adjacent_pawn := Pawn.new("white", Vector2i(3, 4))
	_reset_battle(model, context.controller, [minotaur, adjacent_pawn])

	var observation := {"intro_completed": false}
	context.view.rage_intro_animation_completed.connect(
		func(): observation["intro_completed"] = true,
		CONNECT_ONE_SHOT
	)
	_expect(model.begin_action("white"), "Rage characterization action starts")
	await minotaur.take_damage(1)
	_expect(model.selection_queue.size() == 1, "surviving Minotaur damage queues one reaction")
	_expect(model.selection_queue[0]["action_type"] == "retaliating_rage", "queued Minotaur reaction is Retaliating Rage")
	await model.continue_action_resolution()

	_expect(observation["intro_completed"], "Rage intro animation completes before action resolution returns")
	_expect(model.board[3][4] == null, "Rage damages and destroys an adjacent one-HP piece")
	_expect(model.current_turn == "black", "completed Rage chain switches the turn")
	_expect(not model.action_in_progress, "completed Rage chain closes the action")

	await _destroy_game(context.game)


func _test_rage_priority_before_raise_dead() -> void:
	var context := await _create_game()
	var model: ChessBoardModel = context.model
	var controller: ChessBoardController = context.controller
	var minotaur := MinotaurKing.new("black", Vector2i(3, 3))
	var necromancer := NecromancerKing.new("black", Vector2i(0, 0))
	var rook := Rook.new("white", Vector2i(6, 6))
	_reset_battle(model, controller, [minotaur, necromancer, rook])

	_expect(model.begin_action("white"), "mixed-reaction characterization action starts")
	model.destroy_piece(rook, true)
	await minotaur.take_damage(1)
	_expect(model.selection_queue.size() == 2, "Raise Dead and Rage coexist in the reaction queue")
	await model.continue_action_resolution()

	_expect(minotaur.current_hp == minotaur.max_hp - 1, "Rage source retains the triggering damage")
	_expect(controller.non_move_selection_mode, "Raise Dead pauses after automatic Rage resolves")
	_expect(controller.active_piece == necromancer, "pending selection belongs to the Necromancer")
	_expect(model.get_pending_reaction()["calling_piece"] == necromancer, "Model owns the pending mixed-reaction choice")
	_expect(model.action_in_progress, "action remains open while Raise Dead awaits a choice")

	var choice: Vector2i = controller.legal_moves[0]
	await model.submit_reaction_selection(choice)
	_expect(model.board[choice.x][choice.y] is BonePawn, "Raise Dead creates a Bone Pawn after the queued Rage")
	_expect(not model.action_in_progress, "mixed reaction action finishes after the choice")

	await _destroy_game(context.game)


func _test_raise_dead_selection_resume() -> void:
	var context := await _create_game()
	var model: ChessBoardModel = context.model
	var controller: ChessBoardController = context.controller
	var necromancer := NecromancerKing.new("black", Vector2i(0, 0))
	var bishop := Bishop.new("white", Vector2i(4, 4))
	_reset_battle(model, controller, [necromancer, bishop])

	_expect(model.begin_action("white"), "Raise Dead characterization action starts")
	model.destroy_piece(bishop, true)
	await model.continue_action_resolution()
	_expect(controller.non_move_selection_mode, "Raise Dead enters non-move selection mode")
	_expect(controller.active_piece == necromancer, "Raise Dead exposes its caller through Controller state")
	_expect(not controller.legal_moves.is_empty(), "Raise Dead exposes legal choices through Controller state")
	_expect(model.has_pending_reaction(), "Raise Dead exposes the pending choice through Model state")
	_expect(model.action_in_progress, "Raise Dead pauses the current Model action")

	var choice: Vector2i = controller.legal_moves[0]
	await model.submit_reaction_selection(choice)
	_expect(model.board[choice.x][choice.y] is BonePawn, "Raise Dead choice summons a Bone Pawn")
	_expect(not controller.non_move_selection_mode, "Raise Dead choice exits selection mode")
	_expect(model.current_turn == "black", "Raise Dead choice resumes resolution and switches turn")

	await _destroy_game(context.game)


func _test_battle_completion() -> void:
	var context := await _create_game()
	var model: ChessBoardModel = context.model
	var controller: ChessBoardController = context.controller
	var white_king := ClassicKing.new("white", Vector2i(7, 7))
	var black_king := ClassicKing.new("black", Vector2i(0, 0))
	_reset_battle(model, controller, [white_king, black_king])

	var observation := {"reported_result": ""}
	model.battle_finished.connect(
		func(result: String): observation["reported_result"] = result,
		CONNECT_ONE_SHOT
	)
	_expect(model.begin_action("white"), "battle-completion characterization action starts")
	model.destroy_piece(black_king, true)
	await model.continue_action_resolution()

	_expect(model.battle_over, "destroying a king completes the battle")
	_expect(model.battle_result == "white", "destroying Black's king records White as winner")
	_expect(observation["reported_result"] == "white", "battle completion emits the winning color")
	_expect(controller.is_input_locked, "battle completion leaves Controller input locked")
	_expect(not model.action_in_progress, "battle completion closes the current action")

	await _destroy_game(context.game)


func _create_game() -> Dictionary:
	var game := CHESS_GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	return {
		"game": game,
		"model": game.get_node("ChessModel"),
		"controller": game.get_node("ChessController"),
		"adapter": game.get_node("ChessPresentationAdapter"),
		"view": game.get_node("CanvasLayer/ChessBoard"),
	}


func _destroy_game(game: Node) -> void:
	game.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _reset_battle(model: ChessBoardModel, controller: ChessBoardController, pieces: Array) -> void:
	var adapter: ChessPresentationAdapter = model.get_parent().get_node("ChessPresentationAdapter")
	for row in model.board:
		for piece in row:
			if piece != null:
				model.unregister_piece(piece)

	for piece_node in adapter.view.get_node("Pieces").get_children():
		piece_node.free()
	adapter.piece_views.clear()

	model.board = []
	for row_index in range(8):
		var row: Array = []
		for column_index in range(8):
			row.append(null)
		model.board.append(row)

	model.last_move = {}
	model.last_destroyed_piece = null
	model.current_turn = "white"
	model.battle_over = false
	model.battle_result = ""
	model.defeated_king_colors.clear()
	model.selection_queue.clear()
	model.pending_reaction.clear()
	model.selection_sequence = 0
	model.action_in_progress = false
	model.action_owner_color = ""

	controller.selected_piece = null
	controller.active_king = null
	controller.active_piece = null
	controller.last_active_piece = null
	controller.legal_moves.clear()
	controller.is_input_locked = false
	controller.active_ability_selected = false
	controller.non_move_selection_mode = false

	for piece in pieces:
		var added := model.add_piece(piece, piece.coordinate)
		_expect(added, "test setup adds %s at %s" % [piece.type, piece.coordinate])


func _count_board_pieces(model: ChessBoardModel) -> int:
	var count := 0
	for row in model.board:
		for piece in row:
			if piece != null:
				count += 1
	return count


func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(description)
