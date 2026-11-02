extends Node

var failures: Array[String] = []
var checks := 0


func _ready() -> void:
	_test_legal_paths_and_attacks()
	await _test_skitter_parity()
	await _test_spike_burst_parity()
	await _test_randomized_differential()
	_test_cooldown_lifecycle()
	_test_lethal_and_disabled_ability()
	_test_atomic_rejection_and_schema()
	if failures.is_empty():
		print("ARAKNE CORE CHARACTERIZATION: PASS (", checks, " checks)")
		get_tree().quit(0)
		return
	printerr("ARAKNE CORE CHARACTERIZATION: FAIL")
	for failure in failures: printerr(" - ", failure)
	get_tree().quit(1)


func _test_legal_paths_and_attacks() -> void:
	var arakne := _ready_arakne("white", Vector2i(4, 4))
	var model := _model([arakne, ClassicKing.new("black", Vector2i(0, 7)), Pawn.new("black", Vector2i(3, 3))])
	var imported := ClassicChessCore.import_position(model.capture_position())
	_expect(imported.ok, "Arakne position imports into the pure core")
	var model_keys := _model_keys(model.get_legal_primary_actions("white"))
	var core_keys := _core_keys(ClassicChessCore.legal_actions(imported.state, "white"))
	_expect(model_keys == core_keys, "Arakne movement paths and Spike Burst actions match the model")
	var shared := 0
	for action in ClassicChessCore.legal_actions(imported.state, "white"):
		if action.kind == ChessCoreAction.Kind.MOVE and action.target == Vector2i(3, 4) and action.path.size() == 2: shared += 1
	_expect(shared == 2, "same-destination Skitter routes retain distinct path identity")
	var core_piece: ChessCorePiece = imported.state.piece_by_id(arakne.piece_id)
	_expect(ClassicChessCore.directly_attacks_square(imported.state, core_piece, Vector2i(3, 4)) and not ClassicChessCore.directly_attacks_square(imported.state, core_piece, Vector2i(2, 4)), "Arakne direct attacks remain ordinary King geometry")
	model.free()


func _test_skitter_parity() -> void:
	var arakne := _ready_arakne("white", Vector2i(4, 4))
	var model := _model([arakne, ClassicKing.new("black", Vector2i(0, 7))])
	var imported := ClassicChessCore.import_position(model.capture_position())
	var action := _find(imported.state, ChessCoreAction.Kind.MOVE, arakne.piece_id, Vector2i(3, 6), [Vector2i(4, 5), Vector2i(3, 6)])
	var result := ClassicChessCore.resolve_action(imported.state, action)
	_expect(result.status == ChessCoreStepResult.Status.COMPLETED and _event_kinds(result.events).slice(1, 6) == [&"piece_moved", &"piece_landed", &"skitter_step_started", &"piece_moved", &"piece_landed"], "Skitter resolves two ordered landings with an explicit second-step marker")
	_expect(await model.submit_move_path(arakne, action.path), "the model accepts the matching Skitter path")
	_expect(_json(result.state) == ChessPositionCodec.to_json(model.capture_position(), false), "pure Skitter result matches the model exactly")
	model.free()


func _test_spike_burst_parity() -> void:
	var arakne := _ready_arakne("white", Vector2i(4, 4))
	var target := Rook.new("black", Vector2i(4, 5)); target.max_hp = 2; target.current_hp = 2
	var model := _model([arakne, ClassicKing.new("black", Vector2i(0, 7)), target])
	var imported := ClassicChessCore.import_position(model.capture_position())
	var action := _find(imported.state, ChessCoreAction.Kind.ACTIVE_ABILITY, arakne.piece_id, target.coordinate, [])
	var result := ClassicChessCore.resolve_action(imported.state, action)
	_expect(result.status == ChessCoreStepResult.Status.COMPLETED and _event_kinds(result.events).slice(0, 4) == [&"action_started", &"ability_committed", &"piece_damaged", &"cooldown_scheduled"], "Spike Burst emits its semantic effect and cooldown in order")
	_expect(await model.submit_active_ability(arakne, target.coordinate), "the model accepts matching Spike Burst")
	_expect(_json(result.state) == ChessPositionCodec.to_json(model.capture_position(), false), "nonlethal Spike Burst and scheduled cooldown match the model")
	model.free()


func _test_randomized_differential() -> void:
	var white := _ready_arakne("white", Vector2i(7, 4))
	var black := _ready_arakne("black", Vector2i(0, 4))
	var model := _model([
		white, black,
		Rook.new("white", Vector2i(6, 0)), Knight.new("white", Vector2i(6, 6)),
		Rook.new("black", Vector2i(1, 7)), Knight.new("black", Vector2i(1, 1)),
	])
	var state: ChessCoreState = ClassicChessCore.import_position(model.capture_position()).state
	var rng := RandomNumberGenerator.new(); rng.seed = 771923
	var completed := 0
	for _ply in range(40):
		if state.battle_over: break
		var model_map := {}
		for action in model.get_legal_primary_actions(model.current_turn): model_map[_model_key(action)] = action
		var core_map := {}
		for action in ClassicChessCore.legal_actions(state, state.current_turn): core_map[_core_key(action)] = action
		var model_keys := model_map.keys(); model_keys.sort()
		var core_keys := core_map.keys(); core_keys.sort()
		_expect(model_keys == core_keys, "random Arakne ply %d legal actions match" % _ply)
		if model_keys != core_keys or core_keys.is_empty(): break
		var key = core_keys[rng.randi_range(0, core_keys.size() - 1)]
		var core_result := ClassicChessCore.resolve_action(state, core_map[key])
		var model_action: ChessPrimaryAction = model_map[key]
		var accepted := false
		if model_action.kind == ChessPrimaryAction.Kind.ACTIVE_ABILITY:
			accepted = await model.submit_active_ability(model_action.piece, model_action.target)
		elif model_action.path.size() == 2:
			accepted = await model.submit_move_path(model_action.piece, model_action.path)
		else:
			accepted = await model.submit_move(model_action.piece, model_action.target)
		_expect(accepted and core_result.status == ChessCoreStepResult.Status.COMPLETED, "random Arakne ply %d settles in both authorities" % _ply)
		if not accepted or core_result.status != ChessCoreStepResult.Status.COMPLETED: break
		state = core_result.state
		_expect(_json(state) == ChessPositionCodec.to_json(model.capture_position(), false), "random Arakne ply %d resulting positions match" % _ply)
		if _json(state) != ChessPositionCodec.to_json(model.capture_position(), false): break
		completed += 1
	_expect(completed >= 20, "fixed-seed Arakne differential completes a useful sequence")
	model.free()


func _test_cooldown_lifecycle() -> void:
	var arakne := _ready_arakne("white", Vector2i(4, 4))
	var target := Rook.new("black", Vector2i(4, 5)); target.max_hp = 2; target.current_hp = 2
	var model := _model([arakne, ClassicKing.new("black", Vector2i(0, 7)), target])
	var state: ChessCoreState = ClassicChessCore.import_position(model.capture_position()).state
	state = ClassicChessCore.resolve_action(state, _find(state, ChessCoreAction.Kind.ACTIVE_ABILITY, arakne.piece_id, target.coordinate, [])).state
	var core_arakne := state.piece_by_id(arakne.piece_id)
	_expect(core_arakne.cooldown_reset_pending and core_arakne.current_cooldown == 0, "spent Spike Burst schedules rather than immediately starts cooldown")
	state = _resolve(state, ChessCoreAction.Kind.MOVE, state.occupant(Vector2i(0, 7)).piece_id, Vector2i(0, 6), [Vector2i(0, 6)])
	core_arakne = state.piece_by_id(arakne.piece_id)
	_expect(not core_arakne.cooldown_reset_pending and core_arakne.current_cooldown == 1, "Arakne's next turn starts the authored cooldown")
	state = _resolve(state, ChessCoreAction.Kind.MOVE, core_arakne.piece_id, Vector2i(5, 4), [Vector2i(5, 4)])
	state = _resolve(state, ChessCoreAction.Kind.MOVE, state.occupant(Vector2i(0, 6)).piece_id, Vector2i(0, 7), [Vector2i(0, 7)])
	core_arakne = state.piece_by_id(arakne.piece_id)
	_expect(core_arakne.current_cooldown == 0 and not core_arakne.cooldown_reset_pending, "the following Arakne turn makes Spike Burst ready")
	model.free()


func _test_lethal_and_disabled_ability() -> void:
	var arakne := _ready_arakne("white", Vector2i(4, 4))
	var model := _model([arakne, ClassicKing.new("black", Vector2i(3, 3))])
	var state: ChessCoreState = ClassicChessCore.import_position(model.capture_position()).state
	var result := ClassicChessCore.resolve_action(state, _find(state, ChessCoreAction.Kind.ACTIVE_ABILITY, arakne.piece_id, Vector2i(3, 3), []))
	_expect(result.state.battle_over and result.state.battle_result == "white" and result.state.piece_by_id(model.board[3][3].piece_id) == null, "lethal Spike Burst defeats an enemy King")
	model.free()

	var disabled_arakne := ArakneKing.new("white", Vector2i(4, 4))
	var disabled_target := Rook.new("black", Vector2i(4, 5)); disabled_target.max_hp = 2; disabled_target.current_hp = 2
	var disabled_model := _model([disabled_arakne, ClassicKing.new("black", Vector2i(0, 7)), disabled_target])
	disabled_model.set_active_ability_cooldowns_disabled(true)
	var disabled: ChessCoreState = ClassicChessCore.import_position(disabled_model.capture_position()).state
	var ability := _find(disabled, ChessCoreAction.Kind.ACTIVE_ABILITY, disabled_arakne.piece_id, disabled_target.coordinate, [])
	var disabled_result := ClassicChessCore.resolve_action(disabled, ability)
	var final_arakne := disabled_result.state.piece_by_id(disabled_arakne.piece_id)
	_expect(ability != null and final_arakne.current_cooldown == 0 and not final_arakne.cooldown_reset_pending, "disabled cooldowns keep Spike Burst immediately ready")
	disabled_model.free()


func _test_atomic_rejection_and_schema() -> void:
	var arakne := _ready_arakne("white", Vector2i(4, 4))
	var model := _model([arakne, ClassicKing.new("black", Vector2i(0, 7))])
	var position := model.capture_position()
	position.active_ability_cooldowns_disabled = true
	var encoded := ChessPositionCodec.to_json(position, false)
	var decoded: ChessPosition = ChessPositionCodec.from_json(encoded).position
	_expect(decoded != null and decoded.schema_version == 4 and decoded.active_ability_cooldowns_disabled and decoded.pieces.any(func(piece): return piece.type_id == &"arakne_king" and not piece.initial_cooldown_turn_pending), "schema 4 round-trips Arakne cooldown rule state")
	var arakne_state: ChessPieceState = position.pieces.filter(func(piece): return piece.type_id == &"arakne_king")[0]
	position.active_ability_cooldowns_disabled = false
	arakne_state.current_cooldown = 1; arakne_state.initial_cooldown_turn_pending = true
	var loaded := ChessBoardModel.new(); loaded.startup_mode = ChessBoardModel.StartupMode.EMPTY; loaded.diagnostic_logging_enabled = false; add_child(loaded)
	_expect(loaded.load_position(position.copy()), "schema-4 Arakne position loads")
	var loaded_arakne := loaded.get_king("white") as ArakneKing
	_expect(loaded_arakne.current_cooldown == 1 and loaded_arakne.initial_cooldown_turn_pending, "position replacement preserves the initial cooldown hold exactly")
	loaded.free()
	var state: ChessCoreState = ClassicChessCore.import_position(position).state
	var before := _json(state)
	var illegal := ChessCoreAction.new(); illegal.kind = ChessCoreAction.Kind.MOVE; illegal.piece_id = arakne.piece_id; illegal.color = "white"; illegal.from = arakne.coordinate; illegal.target = Vector2i(2, 5); illegal.path = [Vector2i(3, 5), Vector2i(2, 5)]
	var rejected := ClassicChessCore.resolve_action(state, illegal)
	_expect(rejected.status == ChessCoreStepResult.Status.REJECTED and _json(state) == before, "illegal Skitter paths reject atomically")
	model.free()


func _ready_arakne(color: String, coordinate: Vector2i) -> ArakneKing:
	var result := ArakneKing.new(color, coordinate)
	result.set_cooldown(0)
	result.initial_cooldown_turn_pending = false
	return result


func _model(pieces: Array) -> ChessBoardModel:
	var model := ChessBoardModel.new(); model.startup_mode = ChessBoardModel.StartupMode.EMPTY; model.diagnostic_logging_enabled = false
	add_child(model)
	for _row in range(8): model.board.append([null, null, null, null, null, null, null, null])
	model.is_initialized = true; model.current_turn = "white"
	for piece in pieces: model.add_piece(piece, piece.coordinate)
	return model


func _find(state: ChessCoreState, kind: int, piece_id: String, target: Vector2i, path: Array) -> ChessCoreAction:
	for action in ClassicChessCore.legal_actions(state, state.current_turn):
		if action.kind == kind and action.piece_id == piece_id and action.target == target and action.path == path: return action
	return null


func _resolve(state: ChessCoreState, kind: int, piece_id: String, target: Vector2i, path: Array) -> ChessCoreState:
	return ClassicChessCore.resolve_action(state, _find(state, kind, piece_id, target, path)).state


func _model_keys(actions: Array[ChessPrimaryAction]) -> Array[String]:
	var result: Array[String] = []
	for action in actions: result.append(_model_key(action))
	result.sort(); return result


func _core_keys(actions: Array[ChessCoreAction]) -> Array[String]:
	var result: Array[String] = []
	for action in actions: result.append(_core_key(action))
	result.sort(); return result


func _model_key(action: ChessPrimaryAction) -> String:
	return "%s|%s|%s|%s" % [action.kind, action.piece.piece_id, action.target, action.path]


func _core_key(action: ChessCoreAction) -> String:
	return "%s|%s|%s|%s" % [action.kind, action.piece_id, action.target, action.path]


func _event_kinds(events: Array[ChessCoreEvent]) -> Array[StringName]:
	var result: Array[StringName] = []
	for event in events: result.append(event.kind)
	return result


func _json(state: ChessCoreState) -> String:
	return ChessPositionCodec.to_json(ClassicChessCore.export_position(state), false)


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
