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
	await _test_nonlethal_combat()
	await _test_special_moves()
	await _test_minotaur_charge_landing()
	await _test_headless_rage()
	await _test_rage_raise_dead_includes_death_square()
	await _test_terminal_rank_raise_dead_expires_bone_pawn()
	await _test_headless_reaction_priority()
	await _test_model_owned_raise_dead_choice()
	await _test_raise_dead_excludes_occupied_death_square()
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

func _test_nonlethal_combat() -> void:
	var model := _new_empty_model()
	var rook := Rook.new("white", Vector2i(4, 0))
	var minotaur := MinotaurKing.new("black", Vector2i(4, 4))
	model.add_piece(rook, rook.coordinate)
	model.add_piece(minotaur, minotaur.coordinate)
	var observation := {"attack_events": 0}
	model.piece_attack_committed.connect(
		func(piece: ModelPiece, from: Vector2i, to: Vector2i, _gate: CompletionGate):
			if piece == rook and from == Vector2i(4, 0) and to == Vector2i(4, 4):
				observation["attack_events"] += 1
	)

	_expect(await model.submit_move(rook, minotaur.coordinate), "headless nonlethal attack command is accepted")
	_expect(minotaur.current_hp == minotaur.max_hp - rook.attack_power, "nonlethal attack damages its defender")
	_expect(model.board[4][0] == rook and rook.coordinate == Vector2i(4, 0), "nonlethal attacker remains on its original square")
	_expect(model.board[4][4] == minotaur, "surviving defender remains on its square")
	_expect(observation["attack_events"] == 1, "nonlethal combat emits one attack presentation event")
	_expect(not model.action_in_progress and model.current_turn == "black", "unobserved attack presentation gate completes headlessly")
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

func _test_rage_raise_dead_includes_death_square() -> void:
	var model := _new_empty_model()
	var minotaur := MinotaurKing.new("black", Vector2i(3, 3))
	var necromancer := NecromancerKing.new("black", Vector2i(0, 0))
	var rook := Rook.new("white", Vector2i(3, 4))
	model.add_piece(minotaur, minotaur.coordinate)
	model.add_piece(necromancer, necromancer.coordinate)
	model.add_piece(rook, rook.coordinate)
	model.begin_action("white")
	await minotaur.take_damage(1)
	await model.continue_action_resolution()

	_expect(model.board[3][4] == null, "Rage leaves its defeated piece's square empty")
	_expect(model.has_pending_reaction(), "Rage defeat queues a Raise Dead selection")
	var pending := model.get_pending_reaction()
	_expect(Vector2i(3, 4) in pending["targets"], "Raise Dead includes a death square emptied by Rage")
	await model.submit_reaction_selection(Vector2i(3, 4))
	_expect(model.board[3][4] is BonePawn, "Raise Dead can summon directly onto a Rage death square")
	model.free()

func _test_terminal_rank_raise_dead_expires_bone_pawn() -> void:
	var model := _new_empty_model()
	var minotaur := MinotaurKing.new("black", Vector2i(6, 3))
	var necromancer := NecromancerKing.new("black", Vector2i(0, 0))
	var rook := Rook.new("white", Vector2i(7, 4))
	model.add_piece(minotaur, minotaur.coordinate)
	model.add_piece(necromancer, necromancer.coordinate)
	model.add_piece(rook, rook.coordinate)
	var observation := {"bone_pawns_added": 0, "bone_pawns_destroyed": 0}
	model.piece_added.connect(
		func(piece: ModelPiece):
			if piece is BonePawn:
				observation["bone_pawns_added"] += 1
	)
	model.piece_destroyed.connect(
		func(piece: ModelPiece):
			if piece is BonePawn:
				observation["bone_pawns_destroyed"] += 1
	)

	model.begin_action("white")
	await minotaur.take_damage(1)
	await model.continue_action_resolution()
	_expect(Vector2i(7, 4) in model.get_pending_reaction()["targets"], "opposite back rank remains a legal Raise Dead target")
	await model.submit_reaction_selection(Vector2i(7, 4))
	_expect(observation["bone_pawns_added"] == 1, "terminal-rank Bone Pawn is spawned through normal Model events")
	_expect(observation["bone_pawns_destroyed"] == 1, "terminal-rank Bone Pawn is immediately destroyed")
	_expect(model.board[7][4] == null, "terminal-rank summon leaves its square empty")
	_expect(not model.action_in_progress and model.current_turn == "black", "terminal-rank expiration completes the reaction action")
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
	var passant_captures: Array[Dictionary] = []
	passant_model.piece_capture_committed.connect(
		func(attacker: ModelPiece, defender: ModelPiece, from: Vector2i, to: Vector2i, captured_at: Vector2i, _completion: CompletionGate):
			passant_captures.append({"attacker": attacker, "defender": defender, "from": from, "to": to, "captured_at": captured_at})
	)
	_expect(await passant_model.submit_move(white_pawn, Vector2i(2, 5)), "headless en passant command is accepted")
	_expect(passant_model.board[2][5] == white_pawn and passant_model.board[3][5] == null, "en passant removes the adjacent pawn")
	_expect(passant_captures.size() == 1 and passant_captures[0]["captured_at"] == Vector2i(3, 5), "en passant reports its separate captured square through the lethal-capture event")
	passant_model.free()

	var promotion_model := _new_empty_model()
	var promoting_pawn := Pawn.new("white", Vector2i(1, 0))
	promotion_model.add_piece(promoting_pawn, promoting_pawn.coordinate)
	_expect(await promotion_model.submit_move(promoting_pawn, Vector2i(0, 0)), "headless promotion move is accepted")
	_expect(promotion_model.board[0][0] is Queen, "promotion replaces the pawn with a Queen")
	promotion_model.free()

func _test_minotaur_charge_landing() -> void:
	var surviving_model := _new_empty_model()
	var charging_minotaur := MinotaurKing.new("white", Vector2i(4, 0))
	var defending_minotaur := MinotaurKing.new("black", Vector2i(4, 4))
	defending_minotaur.stunned = true
	surviving_model.add_piece(charging_minotaur, charging_minotaur.coordinate)
	surviving_model.add_piece(defending_minotaur, defending_minotaur.coordinate)
	_expect(await surviving_model.submit_active_ability(charging_minotaur, defending_minotaur.coordinate), "Charge against a surviving king is accepted")
	_expect(defending_minotaur.current_hp == defending_minotaur.max_hp - 2, "Charge damages the surviving king")
	_expect(surviving_model.board[4][4] == defending_minotaur, "surviving Charge target keeps its square")
	_expect(surviving_model.board[4][3] == charging_minotaur and charging_minotaur.coordinate == Vector2i(4, 3), "Charge lands adjacent to a surviving target")
	_expect(not surviving_model.action_in_progress and surviving_model.current_turn == "black", "adjacent Charge landing completes the action")
	surviving_model.free()

	var lethal_model := _new_empty_model()
	var lethal_minotaur := MinotaurKing.new("white", Vector2i(4, 0))
	var arakne := ArakneKing.new("black", Vector2i(4, 4))
	lethal_model.add_piece(lethal_minotaur, lethal_minotaur.coordinate)
	lethal_model.add_piece(arakne, arakne.coordinate)
	_expect(await lethal_model.submit_active_ability(lethal_minotaur, arakne.coordinate), "lethal Charge command is accepted")
	_expect(lethal_model.board[4][4] == lethal_minotaur and lethal_minotaur.coordinate == Vector2i(4, 4), "lethal Charge still occupies the target square")
	lethal_model.free()

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
	_expect(bishop.coordinate in pending["targets"], "direct destruction includes its empty death square")
	var target: Vector2i = bishop.coordinate
	_expect(not (await model.submit_reaction_selection(Vector2i(-1, -1))), "invalid reaction choice is rejected")
	_expect(model.has_pending_reaction(), "invalid reaction choice preserves pending state")
	_expect(await model.submit_reaction_selection(target), "valid reaction choice is accepted")
	_expect(model.board[target.x][target.y] is BonePawn, "headless Raise Dead summons a Bone Pawn")
	_expect(not model.action_in_progress and model.current_turn == "black", "reaction submission resumes and finishes the action")
	model.free()

func _test_raise_dead_excludes_occupied_death_square() -> void:
	var model := _new_empty_model()
	var rook := Rook.new("white", Vector2i(4, 0))
	var bishop := Bishop.new("black", Vector2i(4, 4))
	var necromancer := NecromancerKing.new("black", Vector2i(0, 0))
	model.add_piece(rook, rook.coordinate)
	model.add_piece(bishop, bishop.coordinate)
	model.add_piece(necromancer, necromancer.coordinate)
	var capture_events: Array[Dictionary] = []
	model.piece_capture_committed.connect(
		func(attacker: ModelPiece, defender: ModelPiece, from: Vector2i, to: Vector2i, captured_at: Vector2i, _completion: CompletionGate):
			capture_events.append({"attacker": attacker, "defender": defender, "from": from, "to": to, "captured_at": captured_at})
	)
	_expect(await model.submit_move(rook, bishop.coordinate), "lethal capture that triggers Raise Dead is accepted")
	_expect(capture_events.size() == 1 and capture_events[0]["defender"] == bishop and capture_events[0]["captured_at"] == Vector2i(4, 4), "ordinary lethal capture reports both pieces and its destination square")
	_expect(model.board[4][4] == rook, "capturing piece occupies the defender's death square")
	var pending := model.get_pending_reaction()
	_expect(Vector2i(4, 4) not in pending["targets"], "Raise Dead excludes an occupied death square")
	_expect(not pending["targets"].is_empty(), "occupied death square still leaves adjacent Raise Dead choices")
	await model.submit_reaction_selection(pending["targets"][0])
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
