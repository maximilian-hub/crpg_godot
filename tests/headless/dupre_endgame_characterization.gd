extends Node

const EndgamePolicy = preload("res://scripts/ai/dupre_endgame_policy.gd")
const CoreBackend = preload("res://scripts/ai/dupre_classic_core_backend.gd")

var failures: Array[String] = []
var checks := 0


func _ready() -> void:
	_test_phase_taper()
	_test_passed_pawn_progress()
	_test_enemy_passer_danger()
	_test_king_activity()
	_test_rook_support()
	_test_simplification_direction()
	_test_model_core_parity()
	_test_core_cache_and_metrics()
	if failures.is_empty():
		print("DUPRE ENDGAME CHARACTERIZATION: PASS (", checks, " checks)")
		get_tree().quit(0)
		return
	for failure in failures: printerr(" - ", failure)
	get_tree().quit(1)


func _test_phase_taper() -> void:
	var sparse := _snapshot([_p("wk", &"classic_king", "white", Vector2i(7, 4), true), _p("bk", &"classic_king", "black", Vector2i(0, 4), true)])
	var crowded_pieces: Array[Dictionary] = sparse.pieces.duplicate(true)
	for color in ["white", "black"]:
		for index in range(4): crowded_pieces.append(_p("%s-q%s" % [color, index], &"queen", color, Vector2i(2 + index, index + (0 if color == "white" else 4))))
	_expect(float(EndgamePolicy.analyze(sparse, "white").endgame_weight) == 1.0, "king-only positions receive full endgame weight")
	_expect(float(EndgamePolicy.analyze(_snapshot(crowded_pieces), "white").endgame_weight) == 0.0, "heavy middlegames do not receive endgame policy bonuses")


func _test_passed_pawn_progress() -> void:
	var before := _base_with([_p("wp", &"pawn", "white", Vector2i(4, 2))])
	var after := _base_with([_p("wp", &"pawn", "white", Vector2i(3, 2))])
	_expect(float(EndgamePolicy.transition_bonus(before, after, "white").score) > 0.0, "advancing a safe passed pawn is purposeful")


func _test_enemy_passer_danger() -> void:
	var far := _base_with([_p("bp", &"pawn", "black", Vector2i(4, 2))])
	var near := _base_with([_p("bp", &"pawn", "black", Vector2i(5, 2))])
	_expect(float(EndgamePolicy.analyze(near, "white").score) < float(EndgamePolicy.analyze(far, "white").score), "an advancing enemy passer is increasingly urgent")


func _test_king_activity() -> void:
	var edge := _snapshot([_p("wk", &"classic_king", "white", Vector2i(7, 7), true), _p("bk", &"classic_king", "black", Vector2i(0, 0), true)])
	var center := _snapshot([_p("wk", &"classic_king", "white", Vector2i(4, 4), true), _p("bk", &"classic_king", "black", Vector2i(0, 0), true)])
	_expect(float(EndgamePolicy.analyze(center, "white").score) > float(EndgamePolicy.analyze(edge, "white").score), "a safe centralized king is valued in the endgame")


func _test_rook_support() -> void:
	var unsupported := _base_with([_p("wp", &"pawn", "white", Vector2i(3, 2)), _p("wr", &"rook", "white", Vector2i(7, 3))])
	var supported := _base_with([_p("wp", &"pawn", "white", Vector2i(3, 2)), _p("wr", &"rook", "white", Vector2i(7, 2))])
	_expect(float(EndgamePolicy.analyze(supported, "white").score) > float(EndgamePolicy.analyze(unsupported, "white").score), "a rook behind its passer is valued over unrelated rook activity")


func _test_simplification_direction() -> void:
	var ahead := _base_with([_p("wq", &"queen", "white", Vector2i(6, 0)), _p("wr", &"rook", "white", Vector2i(6, 1)), _p("bq", &"queen", "black", Vector2i(1, 0))])
	var ahead_trade := _base_with([_p("wr", &"rook", "white", Vector2i(6, 1))])
	var behind := _base_with([_p("wq", &"queen", "white", Vector2i(6, 0)), _p("bq", &"queen", "black", Vector2i(1, 0)), _p("br", &"rook", "black", Vector2i(1, 1))])
	var behind_trade := _base_with([_p("br", &"rook", "black", Vector2i(1, 1))])
	_expect(float(EndgamePolicy.transition_bonus(ahead, ahead_trade, "white").trade) > 0.0, "a materially ahead side receives a simplification bonus")
	_expect(float(EndgamePolicy.transition_bonus(behind, behind_trade, "white").trade) < 0.0, "a materially behind side avoids an equal simplification")


func _test_model_core_parity() -> void:
	var model := ChessBoardModel.new(); model.diagnostic_logging_enabled = false; model.initialize_battle(); add_child(model)
	for row in model.board:
		for piece in row:
			if piece != null: model.unregister_piece(piece)
	model.board.clear()
	for _row in range(8): model.board.append([null, null, null, null, null, null, null, null])
	for piece in [ClassicKing.new("white", Vector2i(6, 4)), ClassicKing.new("black", Vector2i(1, 4)), Pawn.new("white", Vector2i(3, 2)), Rook.new("white", Vector2i(6, 2))]: model.add_piece(piece, piece.coordinate)
	var imported := ClassicChessCore.import_position(model._capture_projected_position())
	var live := EndgamePolicy.analyze_model(model, "white")
	var pure := EndgamePolicy.analyze_core(imported.state, "white")
	_expect(is_equal_approx(float(live.score), float(pure.score)), "live and pure-core positions share the same endgame evaluator")
	model.queue_free()


func _test_core_cache_and_metrics() -> void:
	var state := ChessCoreState.new(); state.performance_metrics = ChessCorePerformanceMetrics.new()
	for record in _base_with([_p("wp", &"pawn", "white", Vector2i(3, 2))]).pieces:
		var piece := ChessCorePiece.new(); piece.piece_id = record.piece_id; piece.type_id = record.type_id; piece.color = record.color; piece.coordinate = record.coordinate; state.add_piece(piece)
	var first := EndgamePolicy.analyze_core(state, "white")
	var second := EndgamePolicy.analyze_core(state, "white")
	state.copy()
	_expect(not bool(first.cache_hit) and bool(second.cache_hit), "pure endgame analysis is memoized only within an unchanged state")
	_expect(int(state.performance_metrics.snapshot().state_copy_count) == 1, "pure-core state-copy instrumentation records search work")
	var evaluation := CoreBackend.evaluate_static(state, "white", false, false)
	_expect(evaluation.has("endgame"), "pure leaf evaluation reports its phase-aware endgame component")


func _base_with(extra: Array[Dictionary]) -> Dictionary:
	var pieces: Array[Dictionary] = [_p("wk", &"classic_king", "white", Vector2i(7, 4), true), _p("bk", &"classic_king", "black", Vector2i(0, 4), true)]
	pieces.append_array(extra)
	return _snapshot(pieces)


func _snapshot(pieces: Array[Dictionary]) -> Dictionary:
	var occupancy := {}
	for piece in pieces: occupancy[piece.coordinate] = piece
	return {"pieces": pieces, "occupancy": occupancy}


func _p(id: String, type_id: StringName, color: String, coordinate: Vector2i, king := false) -> Dictionary:
	return {"piece_id": id, "type_id": type_id, "color": color, "coordinate": coordinate, "is_king": king}


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
