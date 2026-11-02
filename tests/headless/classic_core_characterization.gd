extends Node

var failures: Array[String] = []
var checks := 0


func _ready() -> void:
	_test_import_and_legal_parity()
	await _test_quiet_and_capture_parity()
	_test_core_special_moves()
	_test_core_promotion_choices()
	await _test_live_promotion_choice()
	await _test_cpu_promotion_default()
	_test_rejection_and_immutability()
	_test_forced_pass_draw_and_rng()
	_test_archer_core_rules()
	_test_unsupported_imports()
	if failures.is_empty():
		print("CLASSIC CORE CHARACTERIZATION: PASS (", checks, " checks)")
		get_tree().quit(0)
		return
	for failure in failures: printerr(" - ", failure)
	get_tree().quit(1)


func _test_import_and_legal_parity() -> void:
	var model := _classic_start_model()
	var imported := ClassicChessCore.import_position(model.capture_position())
	_expect(imported.ok, "default Classic position imports: %s" % imported.get("error", ""))
	if imported.ok:
		var core_actions := _core_action_keys(ClassicChessCore.legal_actions(imported.state, "white"))
		var model_actions := _model_action_keys(model.get_legal_primary_actions("white"))
		_expect(core_actions == model_actions, "default legal actions match ChessBoardModel")
		for color in ["white", "black"]:
			var analysis_actions := _core_action_keys(ClassicChessCore.analysis_actions(imported.state, color))
			_expect(analysis_actions == _core_action_keys(ClassicChessCore.analysis_actions(imported.state, color)), "%s arbitrary-color analysis is deterministic" % color)
		_expect(_direct_attack_signature(model, imported.state) == _core_attack_signature(imported.state), "pure direct-attack relationships match every Classic piece/square pair")
		var exported := ClassicChessCore.export_position(imported.state)
		_expect(exported != null and _piece_signature(exported) == _piece_signature(model.capture_position()), "settled state exports without piece drift")
	model.free()


func _test_quiet_and_capture_parity() -> void:
	var quiet_model := _model_with([
		ClassicKing.new("white", Vector2i(7, 7)), ClassicKing.new("black", Vector2i(0, 7)), Rook.new("white", Vector2i(4, 4)),
	])
	var quiet_import := ClassicChessCore.import_position(quiet_model.capture_position())
	var quiet_action := _find_core_action(quiet_import.state, quiet_model.board[4][4].piece_id, Vector2i(4, 2))
	var before := _state_signature(quiet_import.state)
	var quiet_result := ClassicChessCore.resolve_action(quiet_import.state, quiet_action)
	var silent_result := ClassicChessCore.resolve_action(quiet_import.state, quiet_action, false)
	_expect(quiet_result.status == ChessCoreStepResult.Status.COMPLETED, "quiet core move completes synchronously")
	_expect(_state_signature(quiet_import.state) == before, "core action does not mutate its input")
	_expect(_event_kinds(quiet_result.events) == [&"action_started", &"piece_moved", &"piece_landed", &"turn_changed", &"action_finished"], "quiet move emits presentation-independent events in authoritative order")
	_expect(silent_result.events.is_empty(), "speculative resolution can suppress unconsumed semantic events")
	_expect(_state_signature(silent_result.state) == _state_signature(quiet_result.state), "event suppression does not change authoritative resolution")
	await quiet_model.submit_move(quiet_model.board[4][4], Vector2i(4, 2))
	_expect(_piece_signature(ClassicChessCore.export_position(quiet_result.state)) == _piece_signature(quiet_model.capture_position()), "quiet move result matches ChessBoardModel")
	quiet_model.free()

	var durable := Rook.new("black", Vector2i(4, 2)); durable.max_hp = 2; durable.current_hp = 2
	var damage_model := _model_with([
		ClassicKing.new("white", Vector2i(7, 7)), ClassicKing.new("black", Vector2i(0, 7)), Rook.new("white", Vector2i(4, 4)), durable,
	])
	var damage_import := ClassicChessCore.import_position(damage_model.capture_position())
	var attacker: ModelPiece = damage_model.board[4][4]
	var damage_action := _find_core_action(damage_import.state, attacker.piece_id, Vector2i(4, 2))
	var damage_result := ClassicChessCore.resolve_action(damage_import.state, damage_action)
	await damage_model.submit_move(attacker, Vector2i(4, 2))
	_expect(damage_result.state.occupant(Vector2i(4, 4)) != null and damage_result.state.occupant(Vector2i(4, 2)).current_hp == 1, "nonlethal combat damages without moving the attacker")
	_expect(_piece_signature(ClassicChessCore.export_position(damage_result.state)) == _piece_signature(damage_model.capture_position()), "nonlethal combat matches ChessBoardModel")
	damage_model.free()


func _test_core_special_moves() -> void:
	var castle_model := _model_with([ClassicKing.new("white", Vector2i(7, 4)), Rook.new("white", Vector2i(7, 7)), ClassicKing.new("black", Vector2i(0, 7))])
	var castle := ClassicChessCore.import_position(castle_model.capture_position())
	var king_id: String = castle_model.board[7][4].piece_id
	var castle_result := ClassicChessCore.resolve_action(castle.state, _find_core_action(castle.state, king_id, Vector2i(7, 6)))
	_expect(castle_result.state.occupant(Vector2i(7, 6)).type_id == &"classic_king" and castle_result.state.occupant(Vector2i(7, 5)).type_id == &"rook", "core resolves current castling semantics")
	_expect(_event_kinds(castle_result.events).slice(1, 4) == [&"pieces_castled", &"piece_landed", &"piece_landed"], "castling events preserve compound landing order")
	castle_model.free()

	var white_pawn := Pawn.new("white", Vector2i(3, 4)); white_pawn.has_moved = true
	var black_pawn := Pawn.new("black", Vector2i(1, 5))
	var passant_model := _model_with([ClassicKing.new("white", Vector2i(7, 7)), ClassicKing.new("black", Vector2i(0, 7)), white_pawn, black_pawn])
	passant_model.current_turn = "black"
	passant_model._resynchronize_live_authority()
	await passant_model.submit_move(black_pawn, Vector2i(3, 5))
	var passant := ClassicChessCore.import_position(passant_model.capture_position())
	var passant_action := _find_core_action(passant.state, white_pawn.piece_id, Vector2i(2, 5))
	var result := ClassicChessCore.resolve_action(passant.state, passant_action)
	_expect(passant_action != null and result.status == ChessCoreStepResult.Status.COMPLETED and result.state.occupant(Vector2i(2, 5)) != null and result.state.occupant(Vector2i(3, 5)) == null, "core resolves en passant and its separate captured square")
	passant_model.free()


func _test_core_promotion_choices() -> void:
	for option in ClassicChessCore.PROMOTION_OPTIONS:
		var model := _model_with([ClassicKing.new("white", Vector2i(7, 7)), ClassicKing.new("black", Vector2i(0, 7)), Pawn.new("white", Vector2i(1, 0))])
		var imported := ClassicChessCore.import_position(model.capture_position())
		var pawn_id: String = model.board[1][0].piece_id
		var moved := ClassicChessCore.resolve_action(imported.state, _find_core_action(imported.state, pawn_id, Vector2i(0, 0)))
		_expect(moved.status == ChessCoreStepResult.Status.PENDING_CHOICE and moved.choice.options == ClassicChessCore.PROMOTION_OPTIONS, "terminal pawn requests all promotion choices")
		var promoted := ClassicChessCore.resolve_choice(moved.state, option)
		_expect(promoted.status == ChessCoreStepResult.Status.COMPLETED and promoted.state.occupant(Vector2i(0, 0)).type_id == option, "promotion resolves to %s" % option)
		model.free()


func _test_live_promotion_choice() -> void:
	for selected in ClassicChessCore.PROMOTION_OPTIONS:
		var model := _model_with([ClassicKing.new("white", Vector2i(7, 7)), ClassicKing.new("black", Vector2i(0, 7)), Pawn.new("white", Vector2i(1, 0))])
		var requested := {"count": 0, "options": []}
		model.promotion_selection_requested.connect(func(_pawn: ModelPiece, options: Array[StringName]):
			requested.count += 1; requested.options = options.duplicate(); model.call_deferred("submit_promotion_selection", selected)
		)
		_expect(await model.submit_move(model.board[1][0], Vector2i(0, 0)), "live %s promotion move is accepted" % selected)
		_expect(requested.count == 1 and requested.options == ClassicChessCore.PROMOTION_OPTIONS, "live model requests the four promotion choices")
		_expect(model.board[0][0].get_position_type_id() == selected and model.current_turn == "black" and model.is_settled(), "live %s promotion completes before the turn changes" % selected)
		await get_tree().process_frame
		model.free()


func _test_cpu_promotion_default() -> void:
	var model := _model_with([ClassicKing.new("white", Vector2i(7, 7)), ClassicKing.new("black", Vector2i(0, 7)), Pawn.new("white", Vector2i(1, 0))])
	var cpu := ChessCpuPlayer.new()
	cpu.model = model
	add_child(cpu)
	cpu.configure_mode(ChessCpuPlayer.ExecutionMode.MANUAL, "white")
	_expect(await model.submit_move(model.board[1][0], Vector2i(0, 0)), "CPU-controlled promotion move completes")
	_expect(model.board[0][0] is Queen and model.is_settled(), "current CPU brains preserve automatic Queen promotion")
	await get_tree().process_frame
	cpu.free(); model.free()


func _test_rejection_and_immutability() -> void:
	var model := _model_with([ClassicKing.new("white", Vector2i(7, 7)), ClassicKing.new("black", Vector2i(0, 7)), Pawn.new("white", Vector2i(1, 0))])
	var imported := ClassicChessCore.import_position(model.capture_position())
	var pawn_id: String = model.board[1][0].piece_id
	var pending := ClassicChessCore.resolve_action(imported.state, _find_core_action(imported.state, pawn_id, Vector2i(0, 0)))
	var signature := _state_signature(pending.state)
	var invalid_choice := ClassicChessCore.resolve_choice(pending.state, &"king")
	_expect(invalid_choice.status == ChessCoreStepResult.Status.REJECTED and _state_signature(pending.state) == signature, "invalid choice rejects atomically")
	var stale := ChessCoreAction.new(); stale.piece_id = pawn_id; stale.color = "white"; stale.from = Vector2i(1, 0); stale.target = Vector2i(4, 4); stale.path = [stale.target]
	var rejected := ClassicChessCore.resolve_action(imported.state, stale)
	_expect(rejected.status == ChessCoreStepResult.Status.REJECTED and _state_signature(imported.state) == _state_signature(rejected.state), "illegal action rejects without mutation")
	model.free()


func _test_forced_pass_draw_and_rng() -> void:
	var model := _model_with([ClassicKing.new("white", Vector2i(7, 7)), ClassicKing.new("black", Vector2i(0, 7))])
	var imported := ClassicChessCore.import_position(model.capture_position())
	var state: ChessCoreState = imported.state
	for piece in state.pieces: piece.stunned = true; piece.stun_timer = 20
	state.random_states = {&"test": 9223372036854770000}
	var events: Array[ChessCoreEvent] = []
	ClassicChessCore._resolve_forced_passes(state, events)
	_expect(state.battle_over and state.battle_result == "draw" and _event_kinds(events).count(&"turn_passed") == 6, "six forced passes complete a draw")
	_expect(state.random_states[&"test"] == 9223372036854770000, "Classic resolution preserves opaque RNG state")
	model.free()


func _test_unsupported_imports() -> void:
	var special_model := _model_with([ArcherKing.new("white", Vector2i(7, 7)), ClassicKing.new("black", Vector2i(0, 7))])
	var special := special_model.capture_position()
	_expect(ClassicChessCore.import_position(special).ok, "Archer King positions are supported by the pure core")
	var hazard_model := _model_with([ClassicKing.new("white", Vector2i(7, 7)), ClassicKing.new("black", Vector2i(0, 7))])
	var hazards := hazard_model.capture_position()
	var effect := ChessTileEffectState.new(); effect.type_id = &"test"; effect.coordinate = Vector2i(4, 4); hazards.tile_effects.append(effect)
	_expect(not ClassicChessCore.import_position(hazards).ok, "tile-effect positions are explicitly rejected")
	special_model.free(); hazard_model.free()


func _test_archer_core_rules() -> void:
	for type_id in ArcherCoreRules.TYPES:
		var archer := ChessPieceCatalog.create_piece(type_id, "white", Vector2i(4, 4)) as ArcherKing
		var target := Pawn.new("black", Vector2i(1, 4)); target.max_hp = 2; target.current_hp = 2
		var model := _model_with([archer, ClassicKing.new("black", Vector2i(0, 7)), target])
		var imported := ClassicChessCore.import_position(model.capture_position())
		_expect(imported.ok, "%s imports with variant state" % type_id)
		if imported.ok and type_id != &"archer_king_charge":
			var action := _find_core_action(imported.state, archer.piece_id, target.coordinate)
			_expect(action != null, "%s exposes its ranged target" % type_id)
			if action != null:
				var resolved := ClassicChessCore.resolve_action(imported.state, action)
				var final_target := resolved.state.piece_by_id(target.piece_id)
				if type_id in ArcherCoreRules.DRAW_TYPES:
					_expect(final_target.current_hp == 2 and ArcherCoreRules.draw_target(resolved.state.piece_by_id(archer.piece_id)) == target.coordinate, "%s begins Draw without premature damage" % type_id)
				else:
					_expect(final_target.current_hp == 1 and resolved.state.piece_by_id(archer.piece_id).coordinate == Vector2i(4, 4), "%s shoots without moving" % type_id)
				if type_id == &"archer_king_quiver":
					_expect(resolved.state.has_effect(&"archer_arrow", target.coordinate, archer.piece_id), "%s leaves an authoritative arrow effect" % type_id)
		elif imported.ok:
			var charge: ChessCoreAction
			for candidate in ClassicChessCore.legal_actions(imported.state, "white"):
				if candidate.kind == ChessCoreAction.Kind.ARCHER_CHARGE: charge = candidate; break
			_expect(charge != null, "Charge Archer exposes its native charge action")
			if charge != null:
				var charged := ClassicChessCore.resolve_action(imported.state, charge)
				_expect(ArcherCoreRules.charge_level(charged.state.piece_by_id(archer.piece_id)) == 1, "Charge begins at level one")
		model.free()


func _model_with(pieces: Array) -> ChessBoardModel:
	var model := ChessBoardModel.new()
	model.startup_mode = ChessBoardModel.StartupMode.EMPTY
	model.diagnostic_logging_enabled = false
	add_child(model)
	for _row in range(8): model.board.append([null, null, null, null, null, null, null, null])
	model.is_initialized = true
	model.current_turn = "white"
	for piece in pieces: model.add_piece(piece, piece.coordinate)
	return model


func _classic_start_model() -> ChessBoardModel:
	var pieces: Array = []
	for color in ["black", "white"]:
		var back := 0 if color == "black" else 7
		var pawn_row := 1 if color == "black" else 6
		pieces.append_array([
			Rook.new(color, Vector2i(back, 0)), Knight.new(color, Vector2i(back, 1)), Bishop.new(color, Vector2i(back, 2)), Queen.new(color, Vector2i(back, 3)), ClassicKing.new(color, Vector2i(back, 4)), Bishop.new(color, Vector2i(back, 5)), Knight.new(color, Vector2i(back, 6)), Rook.new(color, Vector2i(back, 7)),
		])
		for column in range(8): pieces.append(Pawn.new(color, Vector2i(pawn_row, column)))
	return _model_with(pieces)


func _find_core_action(state: ChessCoreState, piece_id: String, target: Vector2i) -> ChessCoreAction:
	for action in ClassicChessCore.legal_actions(state, state.current_turn):
		if action.piece_id == piece_id and action.target == target: return action
	return null


func _core_action_keys(actions: Array[ChessCoreAction]) -> Array[String]:
	var result: Array[String] = []
	for action in actions: result.append("%s|%s|%s" % [action.piece_id, action.target, action.path])
	result.sort(); return result


func _model_action_keys(actions: Array[ChessPrimaryAction]) -> Array[String]:
	var result: Array[String] = []
	for action in actions: result.append("%s|%s|%s" % [action.piece.piece_id, action.target, action.path])
	result.sort(); return result


func _event_kinds(events: Array[ChessCoreEvent]) -> Array[StringName]:
	var result: Array[StringName] = []
	for event in events: result.append(event.kind)
	return result


func _direct_attack_signature(model: ChessBoardModel, state: ChessCoreState) -> Array[String]:
	var occupancy := {}
	for row in model.board:
		for piece in row:
			if piece != null: occupancy[piece.coordinate] = piece
	var position := ChessAttackPosition.from_occupancy(Vector2i(8, 8), occupancy)
	var result: Array[String] = []
	for row in model.board:
		for piece in row:
			if piece == null: continue
			for x in range(8):
				for y in range(8):
					var target := Vector2i(x, y)
					if piece.can_directly_attack_square(piece.coordinate, target, position): result.append("%s|%s" % [piece.piece_id, target])
	result.sort(); return result


func _core_attack_signature(state: ChessCoreState) -> Array[String]:
	var result: Array[String] = []
	for piece in state.pieces:
		for x in range(8):
			for y in range(8):
				var target := Vector2i(x, y)
				if ClassicChessCore.directly_attacks_square(state, piece, target): result.append("%s|%s" % [piece.piece_id, target])
	result.sort(); return result


func _piece_signature(position: ChessPosition) -> String:
	var values: Array[String] = []
	for piece in position.pieces: values.append("%s|%s|%s|%d|%d|%s" % [piece.piece_id, piece.type_id, piece.coordinate, piece.current_hp, piece.max_hp, piece.has_moved])
	values.sort()
	return "%s;%s;%s;%s" % [position.current_turn, position.battle_over, position.battle_result, values]


func _state_signature(state: ChessCoreState) -> String:
	var position := ClassicChessCore.export_position(state)
	if position != null: return _piece_signature(position)
	var pieces: Array[String] = []
	for piece in state.pieces: pieces.append("%s|%s|%s|%d" % [piece.piece_id, piece.type_id, piece.coordinate, piece.current_hp])
	pieces.sort()
	return "%s|%s|%s" % [state.current_turn, pieces, state.pending_choice.kind if state.pending_choice != null else &""]


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
