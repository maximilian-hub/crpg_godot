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
	await _test_ai_configuration_and_turns()
	await _test_nonlethal_attack_presentation()
	await _test_arakne_spike_burst()
	await _test_minotaur_charge_survivor_landing()
	await _test_minotaur_rage_barrier()
	await _test_active_bone_pawn_summon_presentation()
	await _test_rage_raise_dead_death_square_target()
	await _test_terminal_rank_raise_dead_expiration()
	await _test_rage_priority_before_raise_dead()
	await _test_raise_dead_selection_resume()
	await _test_battle_completion()


func _test_active_bone_pawn_summon_presentation() -> void:
	var context := await _create_game()
	var model: ChessBoardModel = context.model
	var controller: ChessBoardController = context.controller
	var necromancer := NecromancerKing.new("white", Vector2i(7, 4))
	var pawn := Pawn.new("white", Vector2i(6, 0))
	_reset_battle(model, controller, [necromancer, pawn])
	var observation := {"summoned_count": 0}
	model.piece_summoned.connect(
		func(piece: ModelPiece, _completion: CompletionGate):
			if piece is BonePawn:
				observation["summoned_count"] += 1
	)
	var target: Vector2i = necromancer.get_active_ability_targets()[0]
	await model.submit_active_ability(necromancer, target)
	await get_tree().process_frame

	var summoned_piece: ModelPiece = model.board[target.x][target.y]
	var piece_node: Node2D = context.adapter.get_piece_view(summoned_piece)
	_expect(summoned_piece is BonePawn and observation["summoned_count"] == 1, "active ability emits one Bone Pawn summon presentation event")
	_expect(piece_node.position == context.view.grid_to_screen(target.x, target.y), "summoned Bone Pawn settles exactly on its square")
	_expect((piece_node.get_node("Sprite2D") as Sprite2D).material == null, "summoned Bone Pawn restores its original sprite material")
	_expect(_count_summon_portals(context.view) == 0, "active summon portal cleans itself up")
	_expect(not model.action_in_progress, "active summon animation completes before action resolution ends")

	await _destroy_game(context.game)


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
	_expect(context.game.control_mode == ChessGame.ControlMode.PLAYER_VS_PLAYER, "test battle is configured for two players")
	_expect(controller.is_player_controlled("white") and controller.is_player_controlled("black"), "two-player mode leaves both colors player-controlled")
	_expect(not context.game.white_cpu_player.is_enabled and not context.game.black_cpu_player.is_enabled, "two-player mode disables both CPU clients")
	var pawn_view: Node = context.adapter.get_piece_view(pawn)
	_expect(is_instance_valid(pawn_view), "presentation maps the moved pawn to a View node")
	_expect(pawn_view.coordinate == Vector2i(4, 0), "movement animation leaves the View node at the destination")
	await get_tree().process_frame
	_expect(model.current_turn == "black", "two-player mode does not automatically take Black's turn")
	controller.select_piece(model.board[1][0])
	_expect(controller.selected_piece == model.board[1][0], "two-player mode still permits Black Controller selection")

	await _destroy_game(context.game)


func _test_ai_configuration_and_turns() -> void:
	var black_context := await _create_game(ChessGame.ControlMode.PLAYER_VS_CPU, "black")
	var black_model: ChessBoardModel = black_context.model
	var black_controller: ChessBoardController = black_context.controller
	_expect(black_controller.is_player_controlled("white"), "Black-AI game leaves White player-controlled")
	_expect(not black_controller.is_player_controlled("black"), "Black-AI game blocks Black Controller input")
	_expect(not black_context.game.white_cpu_player.is_enabled and black_context.game.black_cpu_player.is_enabled, "Black-AI game enables only the Black CPU")
	black_controller.select_piece(black_model.board[1][0])
	_expect(black_controller.selected_piece == null, "Controller cannot select a CPU-owned piece")
	var black_cpu_actions := {"count": 0}
	black_model.action_started.connect(
		func(color: String):
			if color == "black":
				black_cpu_actions["count"] += 1
	)
	await black_model.submit_move(black_model.board[6][0], Vector2i(4, 0))
	await _wait_for_idle_turn(black_model, "white")
	_expect(black_cpu_actions["count"] == 1, "Black CPU acts after the human action resolves")
	await _destroy_game(black_context.game)

	var white_context := await _create_game(ChessGame.ControlMode.PLAYER_VS_CPU, "white")
	var white_model: ChessBoardModel = white_context.model
	var white_controller: ChessBoardController = white_context.controller
	await _wait_for_idle_turn(white_model, "black")
	_expect(not white_controller.is_player_controlled("white") and white_controller.is_player_controlled("black"), "White-AI game assigns Controller ownership to Black")
	_expect(white_context.game.white_cpu_player.is_enabled and not white_context.game.black_cpu_player.is_enabled, "White-AI game enables only the White CPU")
	_expect(white_model.current_turn == "black" and not white_model.action_in_progress, "White CPU takes the opening turn")
	await _destroy_game(white_context.game)

	var zero_game := CHESS_GAME_SCENE.instantiate()
	zero_game.control_mode = ChessGame.ControlMode.CPU_VS_CPU
	add_child(zero_game)
	var zero_model: ChessBoardModel = zero_game.get_node("ChessModel")
	var zero_controller: ChessBoardController = zero_game.get_node("ChessController")
	var white_cpu: ChessCpuPlayer = zero_game.get_node("WhiteCpuPlayer")
	var black_cpu: ChessCpuPlayer = zero_game.get_node("BlackCpuPlayer")
	var zero_action_owners: Array[String] = []
	zero_model.action_started.connect(
		func(color: String):
			zero_action_owners.append(color)
			if zero_action_owners.size() == 2:
				white_cpu.is_enabled = false
				black_cpu.is_enabled = false
	)
	await _wait_for_action_count(zero_action_owners, 2)
	await _wait_for_idle_turn(zero_model, "white")
	_expect(zero_controller.player_controlled_colors.is_empty(), "CPU-vs-CPU mode gives the Controller no colors")
	_expect(zero_action_owners == ["white", "black"], "CPU-vs-CPU mode alternates White then Black")
	_expect(white_cpu.controlled_color == "white" and black_cpu.controlled_color == "black", "CPU-vs-CPU assigns one shared-script instance to each color")
	await _destroy_game(zero_game)


func _test_nonlethal_attack_presentation() -> void:
	var context := await _create_game()
	var model: ChessBoardModel = context.model
	var rook := Rook.new("white", Vector2i(4, 0))
	var minotaur := MinotaurKing.new("black", Vector2i(4, 4))
	_reset_battle(model, context.controller, [rook, minotaur])
	var rook_view: Node = context.adapter.get_piece_view(rook)
	var original_position: Vector2 = rook_view.position
	var observation := {"attack_events": 0, "action_open": false, "gate_pending": false}
	model.piece_attack_committed.connect(
		func(piece: ModelPiece, from: Vector2i, to: Vector2i, gate: CompletionGate):
			if piece == rook and from == Vector2i(4, 0) and to == Vector2i(4, 4):
				observation["attack_events"] += 1
				await get_tree().process_frame
				observation["action_open"] = model.action_in_progress
				observation["gate_pending"] = not gate.is_completed()
	)

	await model.submit_move(rook, minotaur.coordinate)
	_expect(observation["attack_events"] == 1, "surviving-defender combat emits one presentation event")
	_expect(observation["action_open"] and observation["gate_pending"], "nonlethal attack animation runs inside the open Model action")
	_expect(minotaur.current_hp == minotaur.max_hp - rook.attack_power, "animated nonlethal attack applies damage")
	_expect(model.board[4][0] == rook and rook.coordinate == Vector2i(4, 0), "animated attacker remains on its Model square")
	_expect(rook_view.coordinate == Vector2i(4, 0), "attack animation does not change the PieceView coordinate")
	_expect(rook_view.position.is_equal_approx(original_position), "attack animation returns the PieceView to its original position")
	_expect(model.current_turn == "black" and not model.action_in_progress, "turn completes after the attack returns")
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


func _test_minotaur_charge_survivor_landing() -> void:
	var context := await _create_game()
	var model: ChessBoardModel = context.model
	var charging_minotaur := MinotaurKing.new("white", Vector2i(4, 0))
	var defending_minotaur := MinotaurKing.new("black", Vector2i(4, 4))
	defending_minotaur.stunned = true
	_reset_battle(model, context.controller, [charging_minotaur, defending_minotaur])
	var charging_view: Node = context.adapter.get_piece_view(charging_minotaur)

	await model.submit_active_ability(charging_minotaur, defending_minotaur.coordinate)
	_expect(defending_minotaur.current_hp == defending_minotaur.max_hp - 2, "composed Charge damages its surviving target")
	_expect(model.board[4][4] == defending_minotaur, "composed surviving target retains its square")
	_expect(model.board[4][3] == charging_minotaur and charging_minotaur.coordinate == Vector2i(4, 3), "composed Charge ends adjacent to its surviving target")
	_expect(charging_view.coordinate == Vector2i(4, 3), "Charge presentation updates the Minotaur View coordinate")
	_expect(charging_view.position.is_equal_approx(context.view.grid_to_screen(4, 3)), "Charge presentation finishes on the adjacent square")
	_expect(model.current_turn == "black" and not model.action_in_progress, "surviving Charge landing completes before turn change")
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


func _test_rage_raise_dead_death_square_target() -> void:
	var context := await _create_game()
	var model: ChessBoardModel = context.model
	var controller: ChessBoardController = context.controller
	var minotaur := MinotaurKing.new("black", Vector2i(3, 3))
	var necromancer := NecromancerKing.new("black", Vector2i(0, 0))
	var rook := Rook.new("white", Vector2i(3, 4))
	_reset_battle(model, controller, [minotaur, necromancer, rook])

	_expect(model.begin_action("white"), "Rage-to-Raise-Dead action starts")
	await minotaur.take_damage(1)
	await model.continue_action_resolution()
	_expect(model.board[3][4] == null, "composed Rage leaves the defeated piece's square empty")
	_expect(controller.non_move_selection_mode, "Rage defeat enters Raise Dead selection mode")
	_expect(Vector2i(3, 4) in controller.legal_moves, "Controller receives the empty Rage death square as a Raise Dead target")
	await model.submit_reaction_selection(Vector2i(3, 4))
	await get_tree().process_frame
	_expect(model.board[3][4] is BonePawn, "composed Raise Dead summons on the Rage death square")
	_expect(_count_summon_portals(context.view) == 0, "Raise Dead uses and cleans up the shared summon portal")
	_expect(not controller.non_move_selection_mode, "death-square selection exits reaction mode")
	await _destroy_game(context.game)


func _test_terminal_rank_raise_dead_expiration() -> void:
	var context := await _create_game()
	var model: ChessBoardModel = context.model
	var controller: ChessBoardController = context.controller
	var minotaur := MinotaurKing.new("black", Vector2i(6, 3))
	var necromancer := NecromancerKing.new("black", Vector2i(0, 0))
	var rook := Rook.new("white", Vector2i(7, 4))
	_reset_battle(model, controller, [minotaur, necromancer, rook])
	var observation := {"bone_pawns_added": 0, "bone_pawns_destroyed": 0, "event_order": []}
	model.piece_added.connect(
		func(piece: ModelPiece):
			if piece is BonePawn:
				observation["bone_pawns_added"] += 1
	)
	model.piece_summoned.connect(
		func(piece: ModelPiece, _completion: CompletionGate):
			if piece is BonePawn:
				observation["event_order"].append("summoned")
	)
	model.piece_destroyed.connect(
		func(piece: ModelPiece):
			if piece is BonePawn:
				observation["bone_pawns_destroyed"] += 1
				observation["event_order"].append("destroyed")
	)

	model.begin_action("white")
	await minotaur.take_damage(1)
	await model.continue_action_resolution()
	_expect(Vector2i(7, 4) in controller.legal_moves, "Controller keeps the opposite back rank selectable")
	await model.submit_reaction_selection(Vector2i(7, 4))
	_expect(observation["bone_pawns_added"] == 1 and observation["bone_pawns_destroyed"] == 1, "composed summon immediately adds and destroys the terminal Bone Pawn")
	_expect(observation["event_order"] == ["summoned", "destroyed"], "terminal Bone Pawn finishes its summon event before destruction")
	_expect(model.board[7][4] == null, "composed terminal-rank summon leaves the Model square empty")
	_expect(context.adapter.get_piece_view(model.last_destroyed_piece) == null, "presentation removes the expired Bone Pawn mapping")
	_expect(not controller.non_move_selection_mode and model.current_turn == "black", "terminal-rank selection resolves and finishes the action")
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


func _create_game(control_mode: ChessGame.ControlMode = ChessGame.ControlMode.PLAYER_VS_PLAYER, ai_color: String = "black") -> Dictionary:
	var game := CHESS_GAME_SCENE.instantiate()
	game.control_mode = control_mode
	game.ai_color = ai_color
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


func _wait_for_idle_turn(model: ChessBoardModel, color: String, max_frames: int = 180) -> void:
	for frame in range(max_frames):
		if model.current_turn == color and not model.action_in_progress:
			return
		await get_tree().process_frame


func _wait_for_action_count(owners: Array[String], expected: int, max_frames: int = 360) -> void:
	for frame in range(max_frames):
		if owners.size() >= expected:
			return
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


func _count_summon_portals(view: ChessBoardView) -> int:
	var count := 0
	for child in view.get_children():
		if child is BonePawnSummonPortal:
			count += 1
	return count


func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(description)
