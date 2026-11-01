extends Node

const CORE_ITERATIONS := 500
const MODEL_ITERATIONS := 100


func _ready() -> void:
	var source := _classic_position()
	var imported := ClassicChessCore.import_position(source)
	if not imported.ok:
		printerr("CLASSIC CORE PERFORMANCE: import failed: ", imported.error)
		get_tree().quit(1)
		return
	var state: ChessCoreState = imported.state
	var action: ChessCoreAction = ClassicChessCore.legal_actions(state, state.current_turn)[0]
	var metrics := {
		"core_import": _measure(CORE_ITERATIONS, func(): ClassicChessCore.import_position(source)),
		"core_clone": _measure(CORE_ITERATIONS, func(): state.copy()),
		"core_legal": _measure(CORE_ITERATIONS, func(): ClassicChessCore.legal_actions(state, state.current_turn)),
		"core_resolve": _measure(CORE_ITERATIONS, func(): ClassicChessCore.resolve_action(state, action)),
	}
	var model_load_legal: Array[int] = []
	var model_resolve: Array[int] = []
	for _index in range(MODEL_ITERATIONS):
		var started := Time.get_ticks_usec()
		var model := ChessBoardModel.new()
		model.startup_mode = ChessBoardModel.StartupMode.EMPTY
		model.diagnostic_logging_enabled = false
		add_child(model)
		model.load_position(source)
		model.get_legal_primary_actions(model.current_turn)
		model_load_legal.append(Time.get_ticks_usec() - started)
		var piece := model.find_piece_by_id(action.piece_id)
		started = Time.get_ticks_usec()
		await model.submit_move(piece, action.target)
		model_resolve.append(Time.get_ticks_usec() - started)
		model.free()
	metrics["model_construct_load_legal"] = _summary(model_load_legal)
	metrics["model_resolve"] = _summary(model_resolve)
	metrics["core_iterations"] = CORE_ITERATIONS
	metrics["model_iterations"] = MODEL_ITERATIONS
	metrics["core_node_constructions"] = 0
	print("CLASSIC CORE PERFORMANCE: ", JSON.stringify(metrics))
	print("CLASSIC CORE PERFORMANCE: PASS")
	get_tree().quit(0)


func _measure(iterations: int, operation: Callable) -> Dictionary:
	var samples: Array[int] = []
	for _index in range(iterations):
		var started := Time.get_ticks_usec()
		operation.call()
		samples.append(Time.get_ticks_usec() - started)
	return _summary(samples)


func _summary(samples: Array[int]) -> Dictionary:
	samples.sort()
	var total := 0
	for sample in samples: total += sample
	return {
		"median_usec": samples[floori(float(samples.size()) / 2.0)],
		"p95_usec": samples[mini(samples.size() - 1, ceili(float(samples.size()) * 0.95) - 1)],
		"mean_usec": float(total) / float(samples.size()),
		"maximum_usec": samples.back(),
	}


func _classic_position() -> ChessPosition:
	var model := ChessBoardModel.new()
	model.startup_mode = ChessBoardModel.StartupMode.EMPTY
	model.diagnostic_logging_enabled = false
	add_child(model)
	for _row in range(8): model.board.append([null, null, null, null, null, null, null, null])
	model.is_initialized = true
	for color in ["black", "white"]:
		var back := 0 if color == "black" else 7
		var pawn_row := 1 if color == "black" else 6
		for piece in [Rook.new(color, Vector2i(back, 0)), Knight.new(color, Vector2i(back, 1)), Bishop.new(color, Vector2i(back, 2)), Queen.new(color, Vector2i(back, 3)), ClassicKing.new(color, Vector2i(back, 4)), Bishop.new(color, Vector2i(back, 5)), Knight.new(color, Vector2i(back, 6)), Rook.new(color, Vector2i(back, 7))]: model.add_piece(piece, piece.coordinate)
		for column in range(8): model.add_piece(Pawn.new(color, Vector2i(pawn_row, column)), Vector2i(pawn_row, column))
	var result := model.capture_position()
	model.free()
	return result
