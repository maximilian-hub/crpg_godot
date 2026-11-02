extends Node

var failures: Array[String] = []
var checks := 0


func _ready() -> void:
	await _test_core_is_mandatory()
	await _test_piece_nodes_are_presentation_state()
	await _test_facade_projects_core_actions()
	await _test_load_rejects_before_rebuilding_projection()
	await _test_core_owns_rng_and_turn_resolution()
	if failures.is_empty():
		print("HEADLESS MODEL FACADE CHARACTERIZATION: PASS (", checks, " checks)")
		get_tree().quit(0)
		return
	printerr("HEADLESS MODEL FACADE CHARACTERIZATION: FAIL")
	for failure in failures: printerr(" - ", failure)
	get_tree().quit(1)


func _test_core_is_mandatory() -> void:
	var model := _model(_position([
		_piece(&"classic_king", "white", Vector2i(7, 7)),
		_piece(&"classic_king", "black", Vector2i(0, 7)),
	]))
	_expect(model.active_live_authority == ChessBoardModel.LiveAuthority.CLASSIC_CORE, "new models use pure-core authority")
	_expect(not model.set_live_authority(999), "a nonexistent alternate authority cannot be enabled")
	_expect(model.get_live_authority_diagnostics().fallback_reason.contains("Only pure-core"), "alternate authority rejection is diagnostic")
	model.free(); await get_tree().process_frame


func _test_piece_nodes_are_presentation_state() -> void:
	var model := _model(_position([
		_piece(&"classic_king", "white", Vector2i(7, 7)),
		_piece(&"classic_king", "black", Vector2i(0, 7)),
		_piece(&"rook", "white", Vector2i(6, 0)),
	]))
	var rook := model.board[6][0] as ModelPiece
	_expect(not rook.has_method("take_damage") and not rook.has_method("stun"), "ModelPiece no longer executes damage or stun rules")
	_expect(not rook.has_method("active_target_selected") and not rook.has_method("resolve_automatic_reaction"), "piece nodes no longer execute abilities or reactions")
	_expect(rook.get_legal_moves() == model.get_legal_moves(rook), "piece convenience queries delegate to the authoritative core")
	model.free(); await get_tree().process_frame


func _test_facade_projects_core_actions() -> void:
	var model := _model(_position([
		_piece(&"classic_king", "white", Vector2i(7, 7)),
		_piece(&"classic_king", "black", Vector2i(0, 7)),
		_piece(&"rook", "white", Vector2i(6, 0)),
		_piece(&"bishop", "black", Vector2i(3, 0)),
	]))
	var counters := {"moved": 0, "destroyed": 0}
	model.piece_capture_committed.connect(func(_a, _d, _f, _t, _c, _p): counters.moved += 1)
	model.piece_destroyed.connect(func(_piece): counters.destroyed += 1)
	var rook := model.board[6][0] as ModelPiece
	_expect(await model.submit_move(rook, Vector2i(3, 0)), "facade accepts a core-validated capture")
	_expect(model.board[3][0] == rook and counters.moved == 1 and counters.destroyed == 1, "facade projects core state through presentation signals and ModelPieces")
	_expect(model.get_live_authority_diagnostics().projection_mismatches == 0, "projected facade remains identical to core state")
	model.free(); await get_tree().process_frame


func _test_load_rejects_before_rebuilding_projection() -> void:
	var model := _model(_position([
		_piece(&"classic_king", "white", Vector2i(7, 7)),
		_piece(&"classic_king", "black", Vector2i(0, 7)),
	]))
	var before := ChessPositionCodec.to_json(model.capture_position(), false)
	var unsupported := model.capture_position().copy()
	unsupported.pieces[0].custom_state["legacy_rule_state"] = true
	_expect(not model.load_position(unsupported), "unsupported rule state is rejected by the core")
	_expect(ChessPositionCodec.to_json(model.capture_position(), false) == before, "failed core import does not rebuild or corrupt the live projection")
	model.free(); await get_tree().process_frame


func _test_core_owns_rng_and_turn_resolution() -> void:
	var position := _position([
		_piece(&"archer_king", "white", Vector2i(7, 7)),
		_piece(&"classic_king", "black", Vector2i(0, 7)),
		_piece(&"rook", "black", Vector2i(4, 7)),
	])
	position.random_states = {&"lunacy": 17, &"archer_volley": 29}
	var model := _model(position)
	var before_rng := model.capture_position().random_states.duplicate(true)
	var action := model.get_legal_primary_actions("white").filter(func(candidate): return candidate.kind == ChessPrimaryAction.Kind.MOVE and candidate.target == Vector2i(4, 7))[0] as ChessPrimaryAction
	_expect(await model.submit_move(action.piece, action.target), "authoritative Archer action resolves through the facade")
	var after := model.capture_position()
	_expect(after.current_turn == "black" and after.random_states == before_rng, "core owns deterministic RNG snapshots and turn completion")
	model.free(); await get_tree().process_frame


func _model(position: ChessPosition) -> ChessBoardModel:
	var model := ChessBoardModel.new()
	model.startup_mode = ChessBoardModel.StartupMode.EMPTY
	model.diagnostic_logging_enabled = false
	add_child(model)
	assert(model.load_position(position))
	return model


func _position(pieces: Array[ChessPieceState]) -> ChessPosition:
	var position := ChessPosition.new()
	position.pieces.assign(pieces)
	position.random_states = {&"lunacy": 17, &"archer_volley": 29}
	return position


func _piece(type_id: StringName, color: String, coordinate: Vector2i) -> ChessPieceState:
	var piece := ChessPieceCatalog.create_piece(type_id, color, coordinate)
	var state := piece.capture_piece_state()
	piece.free()
	return state


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
