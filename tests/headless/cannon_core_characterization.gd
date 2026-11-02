extends Node

var failures: Array[String] = []
var checks := 0


func _ready() -> void:
	await _test_launch_and_projection()
	await _test_live_authority_launch()
	await _test_live_authority_impact()
	_test_delayed_impact_and_source_independence()
	_test_import_validation()
	if failures.is_empty():
		print("CANNON CORE CHARACTERIZATION: PASS (", checks, " checks)")
		get_tree().quit(0)
		return
	printerr("CANNON CORE CHARACTERIZATION: FAIL")
	for failure in failures: printerr(" - ", failure)
	get_tree().quit(1)


func _test_launch_and_projection() -> void:
	var cannon := CannonKing.new("white", Vector2i(7, 7)); cannon.set_cooldown(0); cannon.initial_cooldown_turn_pending = false
	var target := Rook.new("black", Vector2i(3, 3))
	var model := _model([cannon, Rook.new("white", Vector2i(7, 0)), target, ClassicKing.new("black", Vector2i(0, 0))])
	var state: ChessCoreState = ClassicChessCore.import_position(model.capture_position()).state
	var action := _find(state, cannon.piece_id, Vector2i(3, 3))
	var result := ClassicChessCore.resolve_action(state, action)
	_expect(result.status == ChessCoreStepResult.Status.COMPLETED, "Arc Mortar resolves as an ordinary completed primary action")
	_expect(result.state.autonomous_entities.size() == 1, "Arc Mortar creates one pure autonomous entity")
	var entity: ChessCoreAutonomousEntity = result.state.autonomous_entities[0]
	_expect(entity.coordinate == Vector2i(3, 3) and entity.owner_color == "white" and int(entity.custom_state.landing_turn) == 4, "mortar stores its anchor, owner, and third-round landing")
	var final_cannon := result.state.piece_by_id(cannon.piece_id)
	_expect(final_cannon.cooldown_reset_pending and int(final_cannon.custom_state.scheduled_arc_cooldown) == 4, "enemy footprint schedules the full cooldown")
	_expect(ClassicChessCore.import_position(ClassicChessCore.export_position(result.state)).ok, "mortar state round-trips through ChessPosition")
	await model.submit_active_ability(cannon, Vector2i(3, 3))
	_expect(ChessPositionCodec.to_json(ClassicChessCore.export_position(result.state), false) == ChessPositionCodec.to_json(model.capture_position(), false), "launch result exactly matches ChessBoardModel")
	await get_tree().process_frame; model.free()


func _test_delayed_impact_and_source_independence() -> void:
	var cannon := CannonKing.new("white", Vector2i(7, 7)); cannon.set_cooldown(0); cannon.initial_cooldown_turn_pending = false
	var target := Rook.new("black", Vector2i(3, 3)); target.max_hp = 2; target.current_hp = 2
	var model := _model([cannon, Rook.new("white", Vector2i(7, 0)), target, ClassicKing.new("black", Vector2i(0, 0))])
	var state: ChessCoreState = ClassicChessCore.import_position(model.capture_position()).state
	state = ClassicChessCore.resolve_action(state, _find(state, cannon.piece_id, Vector2i(3, 3))).state
	state.remove_piece(state.piece_by_id(cannon.piece_id))
	_expect(state.autonomous_entities.size() == 1, "mortar survives removal of its source Cannon")
	# Advance three shared rounds with harmless king shuffles.
	for _ply in range(5):
		var actions := ClassicChessCore.legal_actions(state, state.current_turn)
		var quiet: ChessCoreAction
		for candidate in actions:
			if candidate.kind == ChessCoreAction.Kind.MOVE and state.occupant(candidate.target) == null:
				quiet = candidate; break
		_expect(quiet != null, "delay fixture has a quiet move")
		if quiet == null: break
		state = ClassicChessCore.resolve_action(state, quiet).state
	_expect(state.global_turn_number >= 4, "five later plies reach the shooter's third later turn")
	_expect(state.autonomous_entities.is_empty(), "due mortar is removed after impact")
	_expect(state.piece_by_id(target.piece_id).current_hp == 1, "due mortar damages an occupied footprint square once")
	model.free()


func _test_live_authority_launch() -> void:
	var cannon := CannonKing.new("white", Vector2i(7, 7)); cannon.set_cooldown(0); cannon.initial_cooldown_turn_pending = false
	var model := _model([cannon, Rook.new("black", Vector2i(3, 3)), ClassicKing.new("black", Vector2i(0, 0))])
	var signals := {"added": 0}
	model.autonomous_entity_added.connect(func(_entity, _gate): signals.added += 1)
	_expect(model.set_live_authority(ChessBoardModel.LiveAuthority.CLASSIC_CORE), "Cannon position activates experimental pure authority")
	_expect(await model.submit_active_ability(cannon, Vector2i(3, 3)), "pure live authority accepts Arc Mortar")
	_expect(signals.added == 1 and model.autonomous_entities.size() == 1, "live authority emits and projects one mortar warning")
	_expect(model.get_live_authority_diagnostics().projection_mismatches == 0, "Cannon launch leaves live projection identical")
	await get_tree().process_frame; model.free()


func _test_live_authority_impact() -> void:
	var cannon := CannonKing.new("white", Vector2i(7, 7)); cannon.set_cooldown(0); cannon.initial_cooldown_turn_pending = false
	var target := Rook.new("black", Vector2i(3, 3)); target.max_hp = 2; target.current_hp = 2
	var model := _model([cannon, Rook.new("white", Vector2i(7, 0)), target, ClassicKing.new("black", Vector2i(0, 0))])
	var signals := {"impact": 0, "removed": 0}
	model.arc_mortar_impact.connect(func(_entity, _area, _gate): signals.impact += 1)
	model.autonomous_entity_removed.connect(func(_entity, reason, _gate):
		if reason == &"impact": signals.removed += 1
	)
	_expect(model.set_live_authority(ChessBoardModel.LiveAuthority.CLASSIC_CORE), "delayed-impact fixture activates pure authority")
	await model.submit_active_ability(cannon, Vector2i(3, 3))
	for _ply in range(5):
		var selected: ChessPrimaryAction
		for action in model.get_legal_primary_actions(model.current_turn):
			if action.kind == ChessPrimaryAction.Kind.MOVE and action.piece != target and model.board[action.target.x][action.target.y] == null:
				selected = action; break
		_expect(selected != null, "live delayed-impact fixture has a quiet move")
		if selected == null: break
		if selected.path.size() > 1: await model.submit_move_path(selected.piece, selected.path)
		else: await model.submit_move(selected.piece, selected.target)
	_expect(signals == {"impact": 1, "removed": 1}, "live bridge presents exactly one impact and removal")
	_expect(target.current_hp == 1 and model.autonomous_entities.is_empty(), "live impact projects damage and entity removal")
	_expect(model.get_live_authority_diagnostics().projection_mismatches == 0, "delayed impact leaves live projection identical")
	await get_tree().process_frame; model.free()


func _test_import_validation() -> void:
	var model := _model([CannonKing.new("white", Vector2i(7, 7)), ClassicKing.new("black", Vector2i(0, 0))])
	var position := model.capture_position()
	var unsupported := ChessAutonomousEntityState.new(); unsupported.entity_id = "entity_99"; unsupported.type_id = &"wraith"; unsupported.coordinate = Vector2i(4, 4); unsupported.owner_color = "white"
	position.autonomous_entities.append(unsupported)
	_expect(not ClassicChessCore.import_position(position).ok, "malformed Wraith entities retain safe fallback")
	position.autonomous_entities.clear(); position.pieces[0].custom_state["mystery"] = 7
	_expect(not ClassicChessCore.import_position(position).ok, "unknown Cannon custom state is rejected")
	model.free()


func _model(pieces: Array) -> ChessBoardModel:
	var model := ChessBoardModel.new(); model.startup_mode = ChessBoardModel.StartupMode.EMPTY; model.diagnostic_logging_enabled = false
	add_child(model)
	for _row in range(8): model.board.append([null, null, null, null, null, null, null, null])
	model.is_initialized = true; model.current_turn = "white"
	for piece in pieces: model.add_piece(piece, piece.coordinate)
	return model


func _find(state: ChessCoreState, piece_id: String, target: Vector2i) -> ChessCoreAction:
	for action in ClassicChessCore.legal_actions(state, state.current_turn):
		if action.kind == ChessCoreAction.Kind.ACTIVE_ABILITY and action.piece_id == piece_id and action.target == target: return action
	return null


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
