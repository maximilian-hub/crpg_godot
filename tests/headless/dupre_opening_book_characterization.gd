extends Node

const OpeningBook = preload("res://scripts/ai/dupre_opening_book.gd")

var failures: Array[String] = []
var checks := 0


func _ready() -> void:
	await _test_generated_data_and_authoritative_routes()
	await _test_seeded_variety_and_uniform_family_selection()
	await _test_recognized_branch_and_limit()
	await _test_unknown_reply_general_continuation()
	await _test_unrelated_action_preserves_context()
	await _test_illegal_recommendation_falls_back()
	await _test_immediate_win_and_urgent_defense_override()
	await _test_special_ability_overrides_book()
	await _test_black_book_play()
	await _test_special_kings_play_black_book()
	await _test_reset_and_special_kings()
	await _test_normal_dupre_after_book_exit()
	if failures.is_empty():
		print("DUPRE OPENING BOOK CHARACTERIZATION: PASS (", checks, " checks)")
		get_tree().quit(0)
		return
	for failure in failures: printerr(" - ", failure)
	get_tree().quit(1)


func _test_generated_data_and_authoritative_routes() -> void:
	var active := OpeningBook.families()
	var canonical = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/openings/lichess_openings_canonical.json"))
	var diagnostics = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/openings/lichess_openings_diagnostics.json"))
	_expect(active.size() == 48, "reviewed runtime repertoire contains 48 uniformly selectable families")
	_expect(canonical is Dictionary and canonical.families.size() > active.size(), "complete compatible repertoire remains available separately from active configuration")
	_expect(diagnostics.summary.authoritative_rejected == 0 and diagnostics.summary.authoritative_accepted > 3000, "generated diagnostics record successful dual validation at useful scale")
	_expect(diagnostics.expected_first_move_distribution.white.size() >= 6, "diagnostics expose expected first-move probabilities under family-uniform sampling")
	_expect(diagnostics.active_depth_coverage.white.counts.some > 0 and diagnostics.active_depth_coverage.black.counts.some > 0, "diagnostics report practical seven-own-move coverage for both colors")
	var imported_castling := false
	for family in canonical.families:
		for line in family.lines:
			if "e1g1" in line.uci or "e1c1" in line.uci or "e8g8" in line.uci or "e8c8" in line.uci:
				imported_castling = true
				break
		if imported_castling: break
	_expect(imported_castling, "authoritatively validated canonical theory includes native castling moves")

	for color in ["white", "black"]:
		var route: Array[Dictionary] = []
		for family in active:
			route = _route_with_own_moves(StringName(family.id), color, 7)
			if not route.is_empty(): break
		var legal := not route.is_empty()
		if legal:
			var model := _classic_model()
			for descriptor in route:
				if not await _submit_descriptor(model, descriptor):
					legal = false
					break
			model.queue_free()
			await get_tree().process_frame
		_expect(legal, "an imported route supplying seven " + color + " book moves replays through the authoritative model")


func _test_seeded_variety_and_uniform_family_selection() -> void:
	var counts := {}
	var first_moves := {}
	var book_hits := 0
	var fallbacks := 0
	for seed_value in range(960):
		var model := _classic_model()
		var cpu := _cpu(model, "white", seed_value)
		var thought = await cpu.think()
		var family: StringName = thought.search_profile.get("opening_family", &"") if thought != null else &""
		counts[family] = int(counts.get(family, 0)) + 1
		if thought != null: first_moves["%s>%s" % [thought.piece_coordinate, thought.target]] = true
		if thought != null and thought.search_profile.opening_book_hit: book_hits += 1
		if thought != null and thought.search_profile.opening_book_fallback: fallbacks += 1
		_cleanup(cpu, model)
	_expect(counts.size() == OpeningBook.families().size(), "seeded selection reaches every active opening family")
	_expect(first_moves.size() >= 6, "family-uniform selection produces broad traditional first-move variety")
	_expect(book_hits == 960 and fallbacks == 0, "uncomplicated Classic starts hit imported theory without tactical fallback across fixed seeds")
	var within_tolerance := true
	for count in counts.values():
		if count < 4 or count > 40: within_tolerance = false
	_expect(within_tolerance, "family selection remains uniform regardless of each family's variation count")


func _test_recognized_branch_and_limit() -> void:
	var model := _classic_model()
	var cpu := _cpu(model, "white", 3)
	var brain: DupreAiBrain = cpu.brain
	brain.max_book_moves = 2
	brain.opening_session.begin(&"italian_game", model.global_turn_number)
	var first = await cpu.think()
	_expect(_is_move(first, Vector2i(6, 4), Vector2i(4, 4)) and first.search_profile.opening_book_hit, "selected family supplies its authoritative first move")
	_expect(brain.opening_session.book_moves_played == 0, "thinking alone does not consume the book-move limit")
	await cpu.execute_thought()
	_expect(brain.opening_session.book_moves_played == 1, "a successfully executed book action increments Dupre's own book count")
	var replies := OpeningBook.child_descriptors(&"italian_game", brain.opening_session.node_id, "black")
	var reply: Dictionary = replies[0]
	await _submit_descriptor(model, reply)
	var continuation = await cpu.think()
	_expect(continuation != null and continuation.search_profile.opening_book_hit and not brain.opening_session.deviated, "recognized opponent response follows a compatible branch")
	await cpu.execute_thought()
	_expect(brain.opening_session.book_moves_played == 2 and not brain.opening_session.active and brain.opening_session.exit_reason == &"move_limit", "book ceiling counts only Dupre's accepted book actions")
	_cleanup(cpu, model)


func _test_unknown_reply_general_continuation() -> void:
	var model := _classic_model()
	var cpu := _cpu(model, "white", 4)
	var brain: DupreAiBrain = cpu.brain
	brain.opening_session.begin(&"italian_game", model.global_turn_number)
	await cpu.think(); await cpu.execute_thought()
	await _submit(model, Vector2i(1, 2), Vector2i(3, 2))
	var thought = await cpu.think()
	_expect(brain.opening_session.deviated and thought != null and thought.search_profile.opening_book_hit, "an unfamiliar ordinary reply permits a legal family-level continuation")
	_cleanup(cpu, model)


func _test_unrelated_action_preserves_context() -> void:
	var model := _classic_model()
	var cpu := _cpu(model, "white", 5)
	var brain: DupreAiBrain = cpu.brain
	brain.opening_session.begin(&"italian_game", model.global_turn_number)
	await cpu.think(); await cpu.execute_thought()
	model.current_turn = "white"
	model.global_turn_number += 1
	var thought = await cpu.think()
	_expect(brain.opening_session.active and thought != null and thought.search_profile.opening_book_hit, "an unrelated RPG action preserves compatible context without advancing the orthodox trie")
	_cleanup(cpu, model)


func _test_illegal_recommendation_falls_back() -> void:
	var model := _classic_model()
	var cpu := _cpu(model, "white", 6)
	var brain: DupreAiBrain = cpu.brain
	brain.max_reply_leaves = 0
	brain.opening_session.begin(&"italian_game", model.global_turn_number)
	var pawn: ModelPiece = model.board[6][4]
	model.unregister_piece(pawn); model.board[6][4] = null; pawn.free()
	var thought = await cpu.think()
	_expect(thought != null and not thought.search_profile.opening_book_hit and thought.search_profile.opening_book_fallback and brain.opening_session.exit_reason == &"no_legal_continuation", "illegal book recommendations are rejected and cleanly fall back")
	_cleanup(cpu, model)


func _test_immediate_win_and_urgent_defense_override() -> void:
	var win_model := _classic_model()
	var win_cpu := _cpu(win_model, "white", 7)
	var win_brain: DupreAiBrain = win_cpu.brain
	win_brain.opening_session.begin(&"italian_game", win_model.global_turn_number)
	var enemy_king: ModelPiece = win_model.get_king("black")
	enemy_king.current_hp = 1
	win_model.unregister_piece(enemy_king); win_model.board[0][4] = null; enemy_king.coordinate = Vector2i(5, 0); win_model.add_piece(enemy_king, enemy_king.coordinate)
	var rook: ModelPiece = win_model.board[7][0]
	win_model.unregister_piece(rook); win_model.board[7][0] = null; rook.coordinate = Vector2i(5, 7); win_model.add_piece(rook, rook.coordinate)
	var winning = await win_cpu.think()
	_expect(winning != null and winning.target == enemy_king.coordinate and winning.search_profile.opening_book_override and not winning.search_profile.opening_book_hit, "an immediate victory overrides imported theory")
	_cleanup(win_cpu, win_model)

	var danger_model := _classic_model()
	var danger_cpu := _cpu(danger_model, "white", 8)
	var danger_brain: DupreAiBrain = danger_cpu.brain
	danger_brain.max_reply_leaves = 0
	danger_brain.opening_session.begin(&"italian_game", danger_model.global_turn_number)
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
	_expect(thought != null and thought.search_profile.opening_book_hit and thought.piece_coordinate.x == 1, "Black conditions uniform family selection on White's observed first move")
	_cleanup(cpu, model)


func _test_special_kings_play_black_book() -> void:
	for king_type in [&"minotaur_king", &"rhetorician_king"]:
		var model := _classic_model()
		var position := model.capture_position()
		for state in position.pieces:
			if state.color == "black" and state.type_id == &"classic_king":
				state.type_id = king_type
		model.load_position(position)
		await _submit(model, Vector2i(6, 4), Vector2i(4, 4))
		var cpu := _cpu(model, "black", 19)
		var thought = await cpu.think()
		_expect(thought != null and thought.search_profile.opening_book_hit, String(king_type) + " follows compatible imported theory as Black")
		_cleanup(cpu, model)


func _test_special_ability_overrides_book() -> void:
	var model := _classic_model()
	var position := model.capture_position()
	for state in position.pieces:
		if state.color == "white" and state.type_id == &"classic_king":
			state.type_id = &"minotaur_king"
			state.current_cooldown = 0
			state.cooldown_reset_pending = false
		elif state.color == "white" and state.coordinate == Vector2i(6, 4):
			state.coordinate = Vector2i(4, 7)
		elif state.color == "black" and state.type_id == &"classic_king":
			state.coordinate = Vector2i(3, 4)
			state.max_hp = 4
			state.current_hp = 2
	model.load_position(position)
	var cpu := _cpu(model, "white", 91)
	var brain: DupreAiBrain = cpu.brain
	brain.opening_session.begin(&"italian_game", model.global_turn_number)
	var thought = await cpu.think()
	_expect(thought != null and thought.action_kind == ChessPrimaryAction.Kind.ACTIVE_ABILITY and thought.target == Vector2i(3, 4) and thought.search_profile.opening_book_override, "a lethal Minotaur ability overrides an active traditional opening")
	_expect(brain.opening_session.book_moves_played == 0, "a special-King opening override does not consume Dupre's book-move allowance")
	_cleanup(cpu, model)


func _test_reset_and_special_kings() -> void:
	var model := _classic_model()
	var cpu := _cpu(model, "white", 10)
	await cpu.think()
	var position := model.capture_position()
	model.load_position(position)
	_expect(not cpu.brain.opening_session.active and cpu.brain.opening_session.exit_reason == &"not_started", "position replacement resets the opening session")
	await cpu.think()
	_expect(cpu.brain.opening_session.active and cpu.brain.opening_session.selected_family_id != &"", "a replaced starting position creates a fresh opening session")
	cpu.configure_mode(ChessCpuPlayer.ExecutionMode.MANUAL, "black")
	_expect(not cpu.brain.opening_session.active, "changing the controlled side resets opening state")
	_cleanup(cpu, model)

	for king_type in [&"arakne_king", &"minotaur_king", &"rhetorician_king"]:
		var special_model := _classic_model()
		var state := special_model.capture_position()
		for piece_state in state.pieces:
			if piece_state.color == "white" and piece_state.type_id == &"classic_king": piece_state.type_id = king_type
		special_model.load_position(state)
		var special_cpu := _cpu(special_model, "white", 11)
		var special_thought = await special_cpu.think()
		_expect(special_thought != null and special_thought.search_profile.opening_book_hit, String(king_type) + " can use authoritative orthodox opening moves")
		_cleanup(special_cpu, special_model)


func _test_normal_dupre_after_book_exit() -> void:
	var model := _classic_model()
	var cpu := _cpu(model, "white", 12)
	var brain: DupreAiBrain = cpu.brain
	brain.max_book_moves = 0
	brain.max_reply_leaves = 1
	var thought = await cpu.think()
	_expect(thought != null and not thought.search_profile.opening_book_hit and thought.search_profile.selected_status == &"screened_fallback" and thought.search_profile.evaluated_reply_count == 1, "after book exit Dupre retains normal policy-guided tactical behavior")
	_cleanup(cpu, model)


func _route_with_own_moves(family_id: StringName, color: String, minimum: int) -> Array[Dictionary]:
	var stack: Array[Dictionary] = [{"node": 0, "path": [], "count": 0}]
	while not stack.is_empty():
		var entry: Dictionary = stack.pop_back()
		if int(entry.count) >= minimum:
			var result: Array[Dictionary] = []
			result.assign(entry.path)
			return result
		for descriptor in OpeningBook.child_descriptors(family_id, int(entry.node), "white") + OpeningBook.child_descriptors(family_id, int(entry.node), "black"):
			var next_path: Array = entry.path.duplicate()
			next_path.append(descriptor)
			stack.append({"node": int(descriptor.node), "path": next_path, "count": int(entry.count) + int(descriptor.color == color)})
	return []


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


func _submit_descriptor(model: ChessBoardModel, descriptor: Dictionary) -> bool:
	var from: Vector2i = descriptor.from
	var piece: ModelPiece = model.board[from.x][from.y]
	if piece == null: return false
	var expected_path: Array[Vector2i] = []
	expected_path.assign(descriptor.path)
	for action in model.get_legal_primary_actions(model.current_turn):
		if action.piece == piece and action.target == descriptor.to and action.path == expected_path:
			return await model.submit_move(action.piece, action.target)
	return false


func _submit(model: ChessBoardModel, from: Vector2i, to: Vector2i) -> bool:
	var piece: ModelPiece = model.board[from.x][from.y]
	return piece != null and await model.submit_move(piece, to)


func _is_move(thought, from: Vector2i, to: Vector2i) -> bool:
	return thought != null and thought.action_kind == ChessPrimaryAction.Kind.MOVE and thought.piece_coordinate == from and thought.target == to


func _thought_matches_any(thought, descriptors: Array[Dictionary]) -> bool:
	for descriptor in descriptors:
		if _is_move(thought, descriptor.from, descriptor.to) and thought.path == descriptor.path:
			return true
	return false


func _cleanup(cpu: ChessCpuPlayer, model: ChessBoardModel) -> void:
	cpu.queue_free()
	model.queue_free()


func _expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition: failures.append(description)
