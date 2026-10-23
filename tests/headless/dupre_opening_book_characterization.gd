extends Node

const OpeningBook = preload("res://scripts/ai/dupre_opening_book.gd")

var failures: Array[String] = []
var checks := 0


func _ready() -> void:
	await _test_all_curated_lines_are_authoritatively_legal()
	await _test_seeded_variety_and_uniformity()
	await _test_recognized_branch_and_limit()
	await _test_seven_move_ceiling_with_current_line_depth()
	await _test_unknown_reply_general_continuation()
	await _test_unrelated_action_preserves_context()
	await _test_illegal_recommendation_falls_back()
	await _test_immediate_win_and_urgent_defense_override()
	await _test_black_book_play()
	await _test_reset_and_incompatible_king()
	await _test_normal_dupre_after_book_exit()
	if failures.is_empty():
		print("DUPRE OPENING BOOK CHARACTERIZATION: PASS (", checks, " checks)")
		get_tree().quit(0)
		return
	for failure in failures: printerr(" - ", failure)
	get_tree().quit(1)


func _test_all_curated_lines_are_authoritatively_legal() -> void:
	var legal := true
	for family in OpeningBook.families():
		for line in family.lines:
			var model := _classic_model()
			for ply_index in range(line.size()):
				var descriptor: Dictionary = line[ply_index]
				var matching: ChessPrimaryAction = null
				for action in model.get_legal_primary_actions(model.current_turn):
					if action.kind == int(descriptor["kind"]) and action.piece.color == String(descriptor["color"]) and String(action.piece.get_position_type_id()) == String(descriptor["piece"]) and action.piece.coordinate == descriptor["from"] and action.target == descriptor["to"]:
						matching = action
						break
				if matching == null or not await model.submit_move(matching.piece, matching.target):
					legal = false
					printerr("ILLEGAL BOOK LINE: ", family.id, " ply ", ply_index + 1, " ", descriptor)
					break
			model.queue_free()
			await get_tree().process_frame
	_expect(legal, "every curated opening line is legal through the authoritative model")


func _test_seeded_variety_and_uniformity() -> void:
	var counts := {}
	var first_moves := {}
	for seed_value in range(200):
		var model := _classic_model()
		var cpu := _cpu(model, "white", seed_value)
		var thought = await cpu.think()
		var family: StringName = thought.search_profile.get("opening_family", &"") if thought != null else &""
		counts[family] = int(counts.get(family, 0)) + 1
		if thought != null: first_moves["%s>%s" % [thought.piece_coordinate, thought.target]] = true
		_cleanup(cpu, model)
	_expect(counts.size() == OpeningBook.families().size(), "seeded selection reaches every eligible opening family")
	_expect(first_moves.size() >= 4, "different seeds produce varied traditional first moves")
	var within_tolerance := true
	for count in counts.values():
		if count < 8 or count > 32: within_tolerance = false
	_expect(within_tolerance, "uniform family selection remains within a broad deterministic 200-seed tolerance")


func _test_recognized_branch_and_limit() -> void:
	var model := _classic_model()
	var cpu := _cpu(model, "white", 3)
	var brain: DupreAiBrain = cpu.brain
	brain.max_book_moves = 2
	brain.opening_session.begin(_family(&"italian"), model.global_turn_number)
	var first = await cpu.think()
	_expect(_is_move(first, Vector2i(6, 4), Vector2i(4, 4)) and first.search_profile.opening_book_hit, "selected family supplies its first authoritative legal move")
	_expect(brain.opening_session.book_moves_played == 0, "thinking alone does not consume the book-move limit")
	await cpu.execute_thought()
	_expect(brain.opening_session.book_moves_played == 1, "a successfully executed book action increments Dupre's own book count")
	await _submit(model, Vector2i(1, 4), Vector2i(3, 4))
	var continuation = await cpu.think()
	_expect(_is_move(continuation, Vector2i(7, 6), Vector2i(5, 5)), "recognized opponent response follows the selected family's branch")
	await cpu.execute_thought()
	_expect(brain.opening_session.book_moves_played == 2 and not brain.opening_session.active and brain.opening_session.exit_reason == &"move_limit", "book ceiling counts only Dupre's two accepted book actions")
	_cleanup(cpu, model)


func _test_seven_move_ceiling_with_current_line_depth() -> void:
	var model := _classic_model()
	var cpu := _cpu(model, "white", 30)
	var brain: DupreAiBrain = cpu.brain
	brain.max_reply_leaves = 0
	var family := _family(&"italian")
	brain.opening_session.begin(family, model.global_turn_number, 0, [0])
	var line: Array = family.lines[0]
	for ply_index in range(line.size()):
		var descriptor: Dictionary = line[ply_index]
		if descriptor.color == "white":
			var thought = await cpu.think()
			if not _is_move(thought, descriptor.from, descriptor.to) or not await cpu.execute_thought(): break
		else:
			if not await _submit(model, descriptor.from, descriptor.to): break
	_expect(brain.max_book_moves == 7 and brain.opening_session.book_moves_played == 4 and brain.opening_session.active, "the seven-move ceiling preserves the four book moves currently available in a complete line")
	var fallback = await cpu.think()
	_expect(fallback != null and not fallback.search_profile.opening_book_hit and brain.opening_session.exit_reason == &"no_legal_continuation", "exhausting current four-move theory exits cleanly before the seven-move ceiling")
	_cleanup(cpu, model)


func _test_unknown_reply_general_continuation() -> void:
	var model := _classic_model()
	var cpu := _cpu(model, "white", 4)
	var brain: DupreAiBrain = cpu.brain
	brain.opening_session.begin(_family(&"italian"), model.global_turn_number)
	await cpu.think(); await cpu.execute_thought()
	await _submit(model, Vector2i(1, 2), Vector2i(3, 2))
	var thought = await cpu.think()
	_expect(brain.opening_session.deviated and _is_move(thought, Vector2i(7, 6), Vector2i(5, 5)) and thought.search_profile.opening_book_hit, "an unfamiliar ordinary reply permits a compatible family-level continuation")
	_cleanup(cpu, model)


func _test_unrelated_action_preserves_context() -> void:
	var model := _classic_model()
	var cpu := _cpu(model, "white", 5)
	var brain: DupreAiBrain = cpu.brain
	brain.opening_session.begin(_family(&"italian"), model.global_turn_number)
	await cpu.think(); await cpu.execute_thought()
	# An ability does not update ChessBoardModel.last_move.  Re-entering Dupre's
	# turn with that ordinary-move record unchanged models the relevant session
	# observation without fabricating a book action.
	model.current_turn = "white"
	model.global_turn_number += 1
	var thought = await cpu.think()
	_expect(brain.opening_session.active and _is_move(thought, Vector2i(7, 6), Vector2i(5, 5)), "an unrelated RPG action preserves compatible opening context without advancing it as an opponent move")
	_cleanup(cpu, model)


func _test_illegal_recommendation_falls_back() -> void:
	var model := _classic_model()
	var cpu := _cpu(model, "white", 6)
	var brain: DupreAiBrain = cpu.brain
	brain.max_reply_leaves = 0
	brain.opening_session.begin(_family(&"reti"), model.global_turn_number)
	var knight: ModelPiece = model.board[7][6]
	model.unregister_piece(knight); model.board[7][6] = null; knight.free()
	var thought = await cpu.think()
	_expect(thought != null and not thought.search_profile.opening_book_hit and thought.search_profile.opening_book_fallback and brain.opening_session.exit_reason == &"no_legal_continuation", "an illegal book recommendation is rejected and cleanly falls back")
	_cleanup(cpu, model)


func _test_immediate_win_and_urgent_defense_override() -> void:
	var win_model := _classic_model()
	var win_cpu := _cpu(win_model, "white", 7)
	var win_brain: DupreAiBrain = win_cpu.brain
	win_brain.opening_session.begin(_family(&"italian"), win_model.global_turn_number)
	var enemy_king: ModelPiece = win_model.get_king("black")
	enemy_king.current_hp = 1
	win_model.unregister_piece(enemy_king); win_model.board[0][4] = null; enemy_king.coordinate = Vector2i(5, 0); win_model.add_piece(enemy_king, enemy_king.coordinate)
	var rook: ModelPiece = win_model.board[7][0]
	win_model.unregister_piece(rook); win_model.board[7][0] = null; rook.coordinate = Vector2i(5, 7); win_model.add_piece(rook, rook.coordinate)
	var winning = await win_cpu.think()
	_expect(winning != null and winning.target == enemy_king.coordinate and winning.search_profile.opening_book_override and not winning.search_profile.opening_book_hit, "an immediate victory overrides the opening fast path")
	_cleanup(win_cpu, win_model)

	var danger_model := _classic_model()
	var danger_cpu := _cpu(danger_model, "white", 8)
	var danger_brain: DupreAiBrain = danger_cpu.brain
	danger_brain.max_reply_leaves = 0
	danger_brain.opening_session.begin(_family(&"italian"), danger_model.global_turn_number)
	var black_rook: ModelPiece = danger_model.board[0][0]
	danger_model.unregister_piece(black_rook); danger_model.board[0][0] = null; black_rook.coordinate = Vector2i(3, 3); danger_model.add_piece(black_rook, black_rook.coordinate)
	var white_queen: ModelPiece = danger_model.board[7][3]
	danger_model.unregister_piece(white_queen); danger_model.board[7][3] = null; white_queen.coordinate = Vector2i(4, 3); danger_model.add_piece(white_queen, white_queen.coordinate)
	var defensive = await danger_cpu.think()
	_expect(defensive != null and defensive.search_profile.opening_book_override and not defensive.search_profile.opening_book_hit, "an immediately threatened major piece prevents blind book play")
	_cleanup(danger_cpu, danger_model)


func _test_black_book_play() -> void:
	var model := _classic_model()
	await _submit(model, Vector2i(6, 4), Vector2i(4, 4))
	var cpu := _cpu(model, "black", 9)
	var thought = await cpu.think()
	_expect(thought != null and thought.search_profile.opening_book_hit and thought.piece_coordinate.x == 1, "Dupre recognizes White's first move and uses a compatible opening family as Black")
	_cleanup(cpu, model)


func _test_reset_and_incompatible_king() -> void:
	var model := _classic_model()
	var cpu := _cpu(model, "white", 10)
	await cpu.think()
	var first_family: StringName = cpu.brain.opening_session.selected_family.get("id", &"")
	var position := model.capture_position()
	model.load_position(position)
	_expect(not cpu.brain.opening_session.active and cpu.brain.opening_session.exit_reason == &"not_started", "position replacement resets the opening session")
	await cpu.think()
	_expect(cpu.brain.opening_session.active and not cpu.brain.opening_session.selected_family.is_empty(), "a replaced starting position creates a fresh opening session")
	cpu.configure_mode(ChessCpuPlayer.ExecutionMode.MANUAL, "black")
	_expect(not cpu.brain.opening_session.active, "changing the controlled side resets opening state")
	_cleanup(cpu, model)

	var arakne_model := _classic_model()
	var state := arakne_model.capture_position()
	for piece_state in state.pieces:
		if piece_state.color == "white" and piece_state.type_id == &"classic_king": piece_state.type_id = &"arakne_king"
	arakne_model.load_position(state)
	var arakne_cpu := _cpu(arakne_model, "white", 11)
	(arakne_cpu.brain as DupreAiBrain).max_reply_leaves = 0
	var arakne_thought = await arakne_cpu.think()
	_expect(arakne_thought != null and not arakne_thought.search_profile.opening_book_hit and arakne_cpu.brain.opening_session.exit_reason == &"incompatible_position", "non-Classic king setups do not receive Classic-only book actions")
	_cleanup(arakne_cpu, arakne_model)


func _test_normal_dupre_after_book_exit() -> void:
	var model := _classic_model()
	var cpu := _cpu(model, "white", 12)
	var brain: DupreAiBrain = cpu.brain
	brain.max_book_moves = 0
	brain.max_reply_leaves = 1
	var thought = await cpu.think()
	_expect(thought != null and not thought.search_profile.opening_book_hit and thought.search_profile.selected_status == &"policy_fallback" and thought.search_profile.evaluated_reply_count == 1, "after book exit Dupre retains its normal policy-guided tactical behavior")
	_cleanup(cpu, model)


func _classic_model() -> ChessBoardModel:
	var model := ChessBoardModel.new()
	model.diagnostic_logging_enabled = false
	add_child(model)
	var position := model.capture_position()
	for state in position.pieces:
		if String(state.type_id).contains("king"): state.type_id = &"classic_king"
	position.current_turn = "white"
	position.global_turn_number = 1
	model.load_position(position)
	return model


func _cpu(model: ChessBoardModel, color: String, seed_value: int) -> ChessCpuPlayer:
	var cpu := ChessCpuPlayer.new()
	cpu.model = model
	add_child(cpu)
	cpu.configure_mode(ChessCpuPlayer.ExecutionMode.MANUAL, color)
	cpu.set_brain(ChessCpuPlayer.BrainKind.DUPRE)
	cpu.set_random_seed(seed_value)
	return cpu


func _family(id: StringName) -> Dictionary:
	for family in OpeningBook.families():
		if family.id == id: return family
	return {}


func _submit(model: ChessBoardModel, from: Vector2i, to: Vector2i) -> bool:
	var piece: ModelPiece = model.board[from.x][from.y]
	return piece != null and await model.submit_move(piece, to)


func _is_move(thought, from: Vector2i, to: Vector2i) -> bool:
	return thought != null and thought.action_kind == ChessPrimaryAction.Kind.MOVE and thought.piece_coordinate == from and thought.target == to


func _cleanup(cpu: ChessCpuPlayer, model: ChessBoardModel) -> void:
	cpu.queue_free()
	model.queue_free()


func _expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition: failures.append(description)
