extends Node

var failures: Array[String] = []
var checks := 0

func _ready() -> void:
	await _run()
	if failures.is_empty():
		print("BOARD EDITOR CHARACTERIZATION: PASS (", checks, " checks)")
		get_tree().quit(0)
		return
	for failure in failures: printerr(" - ", failure)
	get_tree().quit(1)

func _run() -> void:
	_test_catalog()
	await _test_round_trip_and_mutations()
	_test_codec()
	_test_history()
	await _test_manual_ai()

func _test_catalog() -> void:
	for type_id in ChessPieceCatalog.get_type_ids(true):
		var piece := ChessPieceCatalog.create_piece(type_id, "white", Vector2i.ZERO)
		_expect(piece != null and piece.get_position_type_id() == type_id, "catalog constructs %s" % type_id)

func _test_round_trip_and_mutations() -> void:
	var model := ChessBoardModel.new()
	model.initialize_battle()
	var original := model.capture_position()
	_expect(original.pieces.size() == 32, "default model captures 32 pieces")
	var pawn: ModelPiece = model.board[6][0]
	pawn.current_hp = 1
	pawn.has_moved = true
	var customized := model.capture_position()
	_expect(model.load_position(customized), "settled position loads")
	_expect(model.board[6][0].has_moved, "piece state restores")
	_expect(model.board[6][0].model == model, "piece dependency restores")
	var clear_result := ChessPositionEditor.clear_board(model.capture_position())
	_expect(model.load_position(clear_result.position), "empty edited position loads")
	_expect(model.board.size() == 8 and _count(model) == 0, "clear leaves an empty 8x8 model")
	var king := ChessPieceCatalog.create_piece(&"classic_king", "white", Vector2i(4, 4))
	var place := ChessPositionEditor.place_piece(model.capture_position(), king.capture_piece_state())
	model.load_position(place.position)
	var defeated := 0
	model.battle_finished.connect(func(_winner: String): defeated += 1)
	var remove := ChessPositionEditor.remove_piece(model.capture_position(), Vector2i(4, 4))
	model.load_position(remove.position)
	_expect(defeated == 0 and not model.battle_over, "editor king removal has no defeat side effect")
	model.load_position(original)
	var moving_before: ModelPiece = model.board[6][0]
	var move := ChessPositionEditor.move_piece(model.capture_position(), Vector2i(6, 0), Vector2i(1, 0))
	model.load_position(move.position)
	_expect(model.board[1][0].color == "white" and _count(model) == 31, "occupied edit move replaces destination")
	_expect(not model.board[1][0].has_moved and model.current_turn == "white", "editor move preserves state and turn")
	_expect(moving_before != model.board[1][0], "position rebuild replaces live piece objects")
	model.free()

func _test_codec() -> void:
	var position := ChessPositionPresets.debug_layout()
	var text := ChessPositionCodec.to_json(position)
	var decoded := ChessPositionCodec.from_json(text)
	_expect(decoded.errors.is_empty(), "position JSON decodes")
	_expect(decoded.position.pieces.size() == position.pieces.size(), "position JSON round-trips pieces")
	_expect(ChessPositionCodec.from_json("nope").position == null, "malformed JSON is rejected")

func _test_history() -> void:
	var history := BoardPositionHistory.new()
	var empty := ChessPositionPresets.empty()
	history.establish_baseline(empty)
	var one := empty.copy()
	one.pieces.append(ChessPieceCatalog.create_piece(&"rook", "white", Vector2i.ZERO).capture_piece_state())
	history.push(one)
	_expect(history.can_undo() and history.undo().pieces.is_empty(), "history undo restores prior snapshot")
	var branch := empty.copy()
	branch.current_turn = "black"
	history.push(branch)
	_expect(not history.can_redo(), "new history branch invalidates redo")

func _test_manual_ai() -> void:
	var model := ChessBoardModel.new()
	model.initialize_battle()
	var cpu := ChessCpuPlayer.new()
	cpu.model = model
	add_child(cpu)
	cpu.configure_mode(ChessCpuPlayer.ExecutionMode.MANUAL, "white")
	cpu.set_random_seed(7)
	await get_tree().process_frame
	_expect(model.current_turn == "white", "manual AI does not auto-submit")
	var thought = cpu.think()
	_expect(thought != null and model.current_turn == "white", "AI think does not mutate model")
	_expect(await cpu.execute_thought(), "AI executes a current thought")
	_expect(model.current_turn == "black", "manual AI executes exactly one action")
	model.load_position(ChessPositionPresets.normal_start())
	cpu.configure_mode(ChessCpuPlayer.ExecutionMode.MANUAL, "white")
	thought = cpu.think()
	model.load_position(ChessPositionPresets.normal_start())
	_expect(not await cpu.execute_thought(), "restoration invalidates stale thought")
	cpu.queue_free()
	model.free()

func _count(model: ChessBoardModel) -> int:
	var count := 0
	for row in model.board:
		for piece in row:
			if piece != null: count += 1
	return count

func _expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition: failures.append(description)
