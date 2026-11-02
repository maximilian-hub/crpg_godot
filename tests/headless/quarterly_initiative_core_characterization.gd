extends Node

var failures: Array[String] = []
var checks := 0


func _ready() -> void:
	await _test_performance_cycle_and_choice()
	await _test_granted_movement_and_attacks()
	await _test_efficiency()
	await _test_lethal_cycle_cost()
	await _test_randomized_differential()
	if failures.is_empty():
		print("QUARTERLY INITIATIVE CORE CHARACTERIZATION: PASS (", checks, " checks)")
		get_tree().quit(0)
		return
	printerr("QUARTERLY INITIATIVE CORE CHARACTERIZATION: FAIL")
	for failure in failures: printerr(" - ", failure)
	get_tree().quit(1)


func _test_performance_cycle_and_choice() -> void:
	var quarterly := _ready_quarterly("white", Vector2i(7, 7))
	var rook := Rook.new("white", Vector2i(5, 5))
	var model := _model([quarterly, rook, ClassicKing.new("black", Vector2i(0, 0))])
	model.movement_type_selection_requested.connect(func(_king, _target, _options): model.call_deferred("submit_movement_type_grant", &"bishop"))
	var state: ChessCoreState = ClassicChessCore.import_position(model.capture_position()).state
	var action := _find(state, ChessCoreAction.Kind.ACTIVE_ABILITY, quarterly.piece_id, rook.coordinate)
	var result := ClassicChessCore.resolve_action(state, action)
	_expect(result.status == ChessCoreStepResult.Status.PENDING_CHOICE and result.choice.kind == &"movement_type_grant" and result.choice.target_piece_id == rook.piece_id, "Stakeholder Pandering exposes an explicit recipient choice")
	result = ClassicChessCore.resolve_choice(result.state, &"bishop")
	_expect(await model.submit_active_ability(quarterly, rook.coordinate), "model accepts a paid Quarterly grant")
	_expect(result.state.piece_by_id(quarterly.piece_id).current_hp == 3 and &"bishop" in result.state.piece_by_id(rook.piece_id).granted_movement_types, "paid grant costs HP and persists Bishop movement")
	_expect(_json(result.state) == ChessPositionCodec.to_json(model.capture_position(), false), "paid Quarterly action matches the model")
	await get_tree().process_frame; model.free()

	quarterly = _ready_quarterly("white", Vector2i(7, 7)); rook = Rook.new("white", Vector2i(5, 5))
	model = _model([quarterly, rook, ClassicKing.new("black", Vector2i(0, 0))]); model.global_turn_number = 4
	model.movement_type_selection_requested.connect(func(_king, _target, _options): model.call_deferred("submit_movement_type_grant", &"knight"))
	state = ClassicChessCore.import_position(model.capture_position()).state
	result = ClassicChessCore.resolve_action(state, _find(state, ChessCoreAction.Kind.ACTIVE_ABILITY, quarterly.piece_id, rook.coordinate))
	result = ClassicChessCore.resolve_choice(result.state, &"knight")
	await model.submit_active_ability(quarterly, rook.coordinate)
	_expect(result.state.piece_by_id(quarterly.piece_id).current_hp == 4, "fourth-round Performance Cycle is free")
	_expect(_json(result.state) == ChessPositionCodec.to_json(model.capture_position(), false), "free Quarterly action matches the model")
	await get_tree().process_frame; model.free()


func _test_granted_movement_and_attacks() -> void:
	var elevated := Knight.new("white", Vector2i(4, 4)); elevated.grant_movement_type(&"rook")
	var enemy := Bishop.new("black", Vector2i(4, 0))
	var model := _model([ClassicKing.new("white", Vector2i(7, 7)), elevated, ClassicKing.new("black", Vector2i(0, 7)), enemy])
	var imported := ClassicChessCore.import_position(model.capture_position())
	_expect(imported.ok, "supported movement grants import into the core")
	var state: ChessCoreState = imported.state
	_expect(_model_keys(model.get_legal_primary_actions("white")) == _core_keys(ClassicChessCore.legal_actions(state, "white")), "granted movement legal actions match")
	_expect(ClassicChessCore.directly_attacks_square(state, state.piece_by_id(elevated.piece_id), enemy.coordinate), "granted movement participates in pure tactical geometry")
	var result := ClassicChessCore.resolve_action(state, _find(state, ChessCoreAction.Kind.MOVE, elevated.piece_id, enemy.coordinate))
	await model.submit_move(elevated, enemy.coordinate)
	_expect(_json(result.state) == ChessPositionCodec.to_json(model.capture_position(), false), "granted-movement capture matches the model")
	await get_tree().process_frame; model.free()


func _test_efficiency() -> void:
	var quarterly := QuarterlyInitiativeKing.new("white", Vector2i(4, 4))
	var pawn := Pawn.new("white", Vector2i(3, 4))
	var model := _model([quarterly, pawn, ClassicKing.new("black", Vector2i(0, 7))])
	var state: ChessCoreState = ClassicChessCore.import_position(model.capture_position()).state
	var action := _find(state, ChessCoreAction.Kind.MOVE, quarterly.piece_id, pawn.coordinate)
	_expect(action != null, "Efficiency exposes an adjacent friendly piece as a legal move")
	var result := ClassicChessCore.resolve_action(state, action)
	await model.submit_move(quarterly, pawn.coordinate)
	_expect(result.state.piece_by_id(pawn.piece_id) == null and result.state.piece_by_id(quarterly.piece_id).coordinate == pawn.coordinate, "Efficiency captures a vulnerable ally")
	_expect(_json(result.state) == ChessPositionCodec.to_json(model.capture_position(), false), "Efficiency capture matches the model")
	await get_tree().process_frame; model.free()

	quarterly = QuarterlyInitiativeKing.new("white", Vector2i(4, 4))
	var durable := MinotaurKing.new("white", Vector2i(3, 4)); durable.stunned = true; durable.stun_timer = 20
	model = _model([quarterly, durable, ClassicKing.new("black", Vector2i(0, 7))])
	state = ClassicChessCore.import_position(model.capture_position()).state
	result = ClassicChessCore.resolve_action(state, _find(state, ChessCoreAction.Kind.MOVE, quarterly.piece_id, durable.coordinate))
	await model.submit_move(quarterly, durable.coordinate)
	_expect(result.state.piece_by_id(durable.piece_id).current_hp == 3 and result.state.piece_by_id(quarterly.piece_id).coordinate == Vector2i(4, 4), "Efficiency damages a durable ally without moving")
	_expect(_json(result.state) == ChessPositionCodec.to_json(model.capture_position(), false), "durable Efficiency combat matches the model")
	await get_tree().process_frame; model.free()


func _test_lethal_cycle_cost() -> void:
	var quarterly := _ready_quarterly("white", Vector2i(7, 7)); quarterly.current_hp = 1
	var pawn := Pawn.new("white", Vector2i(6, 0))
	var model := _model([quarterly, pawn, ClassicKing.new("black", Vector2i(0, 7))])
	var requests := {"count": 0}
	model.movement_type_selection_requested.connect(func(_king, _target, _options): requests.count += 1)
	var state: ChessCoreState = ClassicChessCore.import_position(model.capture_position()).state
	var result := ClassicChessCore.resolve_action(state, _find(state, ChessCoreAction.Kind.ACTIVE_ABILITY, quarterly.piece_id, pawn.coordinate))
	await model.submit_active_ability(quarterly, pawn.coordinate)
	_expect(result.status == ChessCoreStepResult.Status.COMPLETED and result.state.battle_over and result.state.pending_choice == null, "lethal Performance Cycle ends without a choice")
	_expect(requests.count == 0 and _json(result.state) == ChessPositionCodec.to_json(model.capture_position(), false), "lethal cost behavior matches the model")
	await get_tree().process_frame; model.free()


func _test_randomized_differential() -> void:
	var white := _ready_quarterly("white", Vector2i(7, 4))
	var black := _ready_quarterly("black", Vector2i(0, 4))
	var model := _model([
		white, black, Rook.new("white", Vector2i(6, 0)), Bishop.new("white", Vector2i(6, 2)), Knight.new("white", Vector2i(5, 5)),
		Rook.new("black", Vector2i(1, 7)), Bishop.new("black", Vector2i(1, 5)), Knight.new("black", Vector2i(2, 2)),
	])
	var choice_box := {"value": &"knight"}
	model.movement_type_selection_requested.connect(func(_king, _target, options): model.call_deferred("submit_movement_type_grant", choice_box.value if choice_box.value in options else options[0]))
	var state: ChessCoreState = ClassicChessCore.import_position(model.capture_position()).state
	var rng := RandomNumberGenerator.new(); rng.seed = 814731
	var completed := 0
	for ply in range(32):
		if state.battle_over: break
		var model_map := {}; var core_map := {}
		for action in model.get_legal_primary_actions(model.current_turn): model_map[_action_key(action.kind, action.piece.piece_id, action.target, action.path)] = action
		for action in ClassicChessCore.legal_actions(state, state.current_turn): core_map[_action_key(action.kind, action.piece_id, action.target, action.path)] = action
		var model_keys := model_map.keys(); model_keys.sort(); var core_keys := core_map.keys(); core_keys.sort()
		_expect(model_keys == core_keys, "random Quarterly ply %d legal actions match" % ply)
		if model_keys != core_keys or core_keys.is_empty(): break
		var key = core_keys[rng.randi_range(0, core_keys.size() - 1)]
		var core_result := ClassicChessCore.resolve_action(state, core_map[key])
		choice_box.value = QuarterlyInitiativeCoreRules.GRANT_OPTIONS[rng.randi_range(0, QuarterlyInitiativeCoreRules.GRANT_OPTIONS.size() - 1)]
		if core_result.status == ChessCoreStepResult.Status.PENDING_CHOICE and core_result.choice.kind == &"movement_type_grant":
			core_result = ClassicChessCore.resolve_choice(core_result.state, choice_box.value)
		var model_action: ChessPrimaryAction = model_map[key]
		var accepted := await model.submit_active_ability(model_action.piece, model_action.target) if model_action.kind == ChessPrimaryAction.Kind.ACTIVE_ABILITY else await model.submit_move(model_action.piece, model_action.target)
		_expect(accepted, "random Quarterly ply %d model action is accepted" % ply)
		if not accepted or core_result.status != ChessCoreStepResult.Status.COMPLETED: break
		state = core_result.state
		var model_json := ChessPositionCodec.to_json(model.capture_position(), false)
		_expect(_json(state) == model_json, "random Quarterly ply %d resulting position matches" % ply)
		if _json(state) != model_json:
			printerr("Quarterly core: ", _json(state))
			printerr("Quarterly model: ", model_json)
			break
		completed += 1
	_expect(completed >= 16, "fixed-seed Quarterly differential completes a useful sequence")
	await get_tree().process_frame; model.free()


func _ready_quarterly(color: String, coordinate: Vector2i) -> QuarterlyInitiativeKing:
	var result := QuarterlyInitiativeKing.new(color, coordinate)
	result.set_cooldown(0); result.initial_cooldown_turn_pending = false
	return result


func _model(pieces: Array) -> ChessBoardModel:
	var model := ChessBoardModel.new(); model.startup_mode = ChessBoardModel.StartupMode.EMPTY; model.diagnostic_logging_enabled = false
	add_child(model)
	for _row in range(8): model.board.append([null, null, null, null, null, null, null, null])
	model.is_initialized = true; model.current_turn = "white"
	for piece in pieces: model.add_piece(piece, piece.coordinate)
	return model


func _find(state: ChessCoreState, kind: int, piece_id: String, target: Vector2i) -> ChessCoreAction:
	for action in ClassicChessCore.legal_actions(state, state.current_turn):
		if action.kind == kind and action.piece_id == piece_id and action.target == target: return action
	return null


func _model_keys(actions: Array[ChessPrimaryAction]) -> Array[String]:
	var result: Array[String] = []
	for action in actions: result.append(_action_key(action.kind, action.piece.piece_id, action.target, action.path))
	result.sort(); return result


func _core_keys(actions: Array[ChessCoreAction]) -> Array[String]:
	var result: Array[String] = []
	for action in actions: result.append(_action_key(action.kind, action.piece_id, action.target, action.path))
	result.sort(); return result


func _action_key(kind: int, piece_id: String, target: Vector2i, path: Array) -> String:
	return "%s|%s|%s|%s" % [kind, piece_id, target, path]


func _json(state: ChessCoreState) -> String:
	return ChessPositionCodec.to_json(ClassicChessCore.export_position(state), false)


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
