extends Node

var failures: Array[String] = []
var checks := 0


func _ready() -> void:
	var state := _state()
	var metrics := ChessCorePerformanceMetrics.new()
	metrics.detailed_analysis_enabled = true
	state.performance_metrics = metrics
	var first := ClassicChessCore.analysis_actions(state, "white")
	var second := ClassicChessCore.analysis_actions(state, "black")
	var first_keys := _keys(first)
	var second_keys := _keys(second)
	_expect(not first.is_empty() and not second.is_empty(), "both colors generate analysis actions")
	_expect(int(metrics.snapshot().ordered_piece_query_count) == 2, "piece ordering is queried for both colors")
	_expect(int(metrics.snapshot().ordered_piece_cache_hit_count) == 1, "the second color reuses the state-local piece ordering")

	var copied := state.copy()
	_expect(copied.analysis_cache.is_empty(), "copied states do not inherit analysis references")
	_expect(_keys(ClassicChessCore.analysis_actions(copied, "white")) == first_keys, "copy produces identical ordered action identities")

	var rook := state.piece_by_id("white_rook")
	state.move_piece(rook, Vector2i(5, 0))
	_expect(state.analysis_cache.is_empty(), "state mutation invalidates cached ordering")
	var moved_keys := _keys(ClassicChessCore.analysis_actions(state, "white"))
	_expect(moved_keys != first_keys, "regenerated actions describe the mutated position")
	_expect(_keys(ClassicChessCore.analysis_actions(copied, "black")) == second_keys, "cached parent references cannot alter a copied state")

	if failures.is_empty():
		print("DUPRE CORE ANALYSIS CACHE CHARACTERIZATION: PASS (", checks, " checks)")
		get_tree().quit(0)
		return
	printerr("DUPRE CORE ANALYSIS CACHE CHARACTERIZATION: FAIL")
	for failure in failures: printerr(" - ", failure)
	get_tree().quit(1)


func _state() -> ChessCoreState:
	var state := ChessCoreState.new()
	for data in [
		["white_king", &"classic_king", "white", Vector2i(7, 4)],
		["white_rook", &"rook", "white", Vector2i(6, 0)],
		["white_pawn", &"pawn", "white", Vector2i(5, 3)],
		["black_king", &"classic_king", "black", Vector2i(0, 4)],
		["black_rook", &"rook", "black", Vector2i(1, 7)],
		["black_pawn", &"pawn", "black", Vector2i(2, 3)],
	]:
		var piece := ChessCorePiece.new()
		piece.piece_id = data[0]
		piece.type_id = data[1]
		piece.color = data[2]
		piece.coordinate = data[3]
		piece.max_hp = 3 if piece.type_id == &"classic_king" else 1
		piece.current_hp = piece.max_hp
		state.add_piece(piece)
	return state


func _keys(actions: Array[ChessCoreAction]) -> Array[String]:
	var result: Array[String] = []
	for action in actions:
		result.append("%s|%s|%s|%s" % [action.kind, action.piece_id, action.target, action.path])
	return result


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
