extends Node

var failures: Array[String] = []
var checks := 0


func _ready() -> void:
	await _test_active_summon_parity()
	await _test_capture_raise_dead_parity()
	await _test_ability_destruction_raise_dead_parity()
	await _test_double_necromancer_order()
	await _test_bone_pawn_terminal_expiration()
	await _test_randomized_differential()
	_test_rejection_and_import_boundaries()
	if failures.is_empty():
		print("NECROMANCER CORE CHARACTERIZATION: PASS (", checks, " checks)")
		get_tree().quit(0)
		return
	printerr("NECROMANCER CORE CHARACTERIZATION: FAIL")
	for failure in failures: printerr(" - ", failure)
	get_tree().quit(1)


func _test_active_summon_parity() -> void:
	var necromancer := _ready_necromancer("white", Vector2i(7, 4))
	var model := _model([necromancer, ClassicKing.new("black", Vector2i(0, 4)), Pawn.new("white", Vector2i(5, 0))])
	var state: ChessCoreState = ClassicChessCore.import_position(model.capture_position()).state
	_expect(_model_keys(model.get_legal_primary_actions("white")) == _core_keys(ClassicChessCore.legal_actions(state, "white")), "Necromancer legal moves and summon targets match the model")
	var action := _find(state, ChessCoreAction.Kind.ACTIVE_ABILITY, necromancer.piece_id, Vector2i(6, 3))
	var result := ClassicChessCore.resolve_action(state, action)
	_expect(result.status == ChessCoreStepResult.Status.COMPLETED, "ordinary Summon Bone Pawn settles without a secondary choice")
	_expect(await model.submit_active_ability(necromancer, action.target), "model accepts the matching summon")
	_expect(_json(result.state) == ChessPositionCodec.to_json(model.capture_position(), false), "active summon, generated ID, and cooldown match the model")
	model.free()


func _test_capture_raise_dead_parity() -> void:
	var rook := Rook.new("white", Vector2i(4, 0))
	var bishop := Bishop.new("black", Vector2i(4, 3))
	var necromancer := _ready_necromancer("black", Vector2i(0, 7))
	var model := _model([ClassicKing.new("white", Vector2i(7, 7)), rook, necromancer, bishop])
	var state: ChessCoreState = ClassicChessCore.import_position(model.capture_position()).state
	var action := _find(state, ChessCoreAction.Kind.MOVE, rook.piece_id, bishop.coordinate)
	var result := ClassicChessCore.resolve_action(state, action)
	_expect(result.status == ChessCoreStepResult.Status.PENDING_CHOICE and result.choice.kind == &"raise_dead", "major capture pauses on a pure Raise Dead choice")
	var dupre_settled := DupreClassicCoreBackend.resolve(state, DupreClassicCoreBackend.describe(action))
	_expect(dupre_settled.status == ChessCoreStepResult.Status.COMPLETED and dupre_settled.resolved_reaction_colors == ["black"], "Dupre settles and diagnoses the pure reaction without a model")
	_expect(await model.submit_move(rook, bishop.coordinate) and model.has_pending_reaction(), "matching model capture pauses for Raise Dead")
	_expect(result.choice.options == model.get_pending_reaction().targets, "occupied capture square and adjacent Raise Dead targets match")
	var selected: Vector2i = result.choice.options[0]
	result = ClassicChessCore.resolve_choice(result.state, selected)
	_expect(await model.submit_reaction_selection(selected), "model accepts the matching Raise Dead target")
	_expect(result.status == ChessCoreStepResult.Status.COMPLETED and _json(result.state) == ChessPositionCodec.to_json(model.capture_position(), false), "Raise Dead summon and resumed turn match the model")
	model.free()


func _test_double_necromancer_order() -> void:
	var white_necro := _ready_necromancer("white", Vector2i(7, 7))
	var black_necro := _ready_necromancer("black", Vector2i(0, 7))
	var rook := Rook.new("white", Vector2i(4, 0))
	var bishop := Bishop.new("black", Vector2i(4, 3))
	var model := _model([white_necro, rook, black_necro, bishop])
	var state: ChessCoreState = ClassicChessCore.import_position(model.capture_position()).state
	var result := ClassicChessCore.resolve_action(state, _find(state, ChessCoreAction.Kind.MOVE, rook.piece_id, bishop.coordinate))
	_expect(result.choice.piece_id == black_necro.piece_id, "non-acting Necromancer receives the first corpse choice")
	_expect(await model.submit_move(rook, bishop.coordinate), "double-Necromancer model capture begins")
	for expected_id in [black_necro.piece_id, white_necro.piece_id]:
		_expect(result.status == ChessCoreStepResult.Status.PENDING_CHOICE and result.choice.piece_id == expected_id, "pure reaction order retains owner priority and sequence")
		var model_pending := model.get_pending_reaction()
		_expect(model_pending.calling_piece.piece_id == expected_id and result.choice.options == model_pending.targets, "each recomputed choice matches the model")
		var selected: Vector2i = result.choice.options[0]
		result = ClassicChessCore.resolve_choice(result.state, selected)
		await model.submit_reaction_selection(selected)
	_expect(result.status == ChessCoreStepResult.Status.COMPLETED and _json(result.state) == ChessPositionCodec.to_json(model.capture_position(), false), "chained opposing Raise Dead reactions settle identically")
	model.free()


func _test_ability_destruction_raise_dead_parity() -> void:
	var arakne := ArakneKing.new("white", Vector2i(4, 4)); arakne.set_cooldown(0); arakne.initial_cooldown_turn_pending = false
	var rook := Rook.new("black", Vector2i(4, 5))
	var necromancer := _ready_necromancer("black", Vector2i(0, 7))
	var model := _model([arakne, necromancer, rook])
	var state: ChessCoreState = ClassicChessCore.import_position(model.capture_position()).state
	var result := ClassicChessCore.resolve_action(state, _find(state, ChessCoreAction.Kind.ACTIVE_ABILITY, arakne.piece_id, rook.coordinate))
	_expect(await model.submit_active_ability(arakne, rook.coordinate), "model accepts lethal Spike Burst before Raise Dead")
	_expect(result.status == ChessCoreStepResult.Status.PENDING_CHOICE and rook.coordinate in result.choice.options and result.choice.options == model.get_pending_reaction().targets, "empty ability death square is available identically")
	var selected: Vector2i = rook.coordinate
	result = ClassicChessCore.resolve_choice(result.state, selected)
	await model.submit_reaction_selection(selected)
	_expect(_json(result.state) == ChessPositionCodec.to_json(model.capture_position(), false), "Spike Burst to Raise Dead composition settles identically")
	model.free()


func _test_bone_pawn_terminal_expiration() -> void:
	var bone := BonePawn.new("white", Vector2i(1, 2))
	var model := _model([ClassicKing.new("white", Vector2i(7, 7)), ClassicKing.new("black", Vector2i(0, 7)), bone])
	var state: ChessCoreState = ClassicChessCore.import_position(model.capture_position()).state
	var action := _find(state, ChessCoreAction.Kind.MOVE, bone.piece_id, Vector2i(0, 2))
	var result := ClassicChessCore.resolve_action(state, action)
	_expect(await model.submit_move(bone, action.target), "model accepts terminal Bone Pawn movement")
	_expect(result.state.piece_by_id(bone.piece_id) == null and _json(result.state) == ChessPositionCodec.to_json(model.capture_position(), false), "moved Bone Pawn expires before the turn settles in both authorities")
	model.free()


func _test_rejection_and_import_boundaries() -> void:
	var necromancer := _ready_necromancer("white", Vector2i(7, 7))
	var model := _model([necromancer, ClassicKing.new("black", Vector2i(0, 7)), BonePawn.new("white", Vector2i(5, 5))])
	var imported := ClassicChessCore.import_position(model.capture_position())
	_expect(imported.ok, "settled Necromancer and Bone Pawn positions import")
	var before := _json(imported.state)
	var rejected := ClassicChessCore.resolve_choice(imported.state, Vector2i(3, 3))
	_expect(rejected.status == ChessCoreStepResult.Status.REJECTED and _json(imported.state) == before, "choice without a pending reaction rejects atomically")
	model.free()


func _test_randomized_differential() -> void:
	var white := _ready_necromancer("white", Vector2i(7, 4))
	var black := _ready_necromancer("black", Vector2i(0, 4))
	var model := _model([
		white, black, Rook.new("white", Vector2i(6, 0)), Bishop.new("white", Vector2i(5, 2)), Knight.new("white", Vector2i(5, 5)),
		Rook.new("black", Vector2i(1, 7)), Bishop.new("black", Vector2i(2, 5)), Knight.new("black", Vector2i(2, 2)),
	])
	var state: ChessCoreState = ClassicChessCore.import_position(model.capture_position()).state
	var rng := RandomNumberGenerator.new(); rng.seed = 91377
	var completed := 0
	for ply in range(36):
		if state.battle_over: break
		var model_map := {}; var core_map := {}
		for action in model.get_legal_primary_actions(model.current_turn): model_map[_action_key(action.kind, action.piece.piece_id, action.target, action.path)] = action
		for action in ClassicChessCore.legal_actions(state, state.current_turn): core_map[_action_key(action.kind, action.piece_id, action.target, action.path)] = action
		var model_keys := model_map.keys(); model_keys.sort()
		var core_keys := core_map.keys(); core_keys.sort()
		_expect(model_keys == core_keys, "random Necromancer ply %d legal actions match" % ply)
		if model_keys != core_keys or core_keys.is_empty(): break
		var key = core_keys[rng.randi_range(0, core_keys.size() - 1)]
		var core_result := ClassicChessCore.resolve_action(state, core_map[key])
		var model_action: ChessPrimaryAction = model_map[key]
		var accepted := await model.submit_active_ability(model_action.piece, model_action.target) if model_action.kind == ChessPrimaryAction.Kind.ACTIVE_ABILITY else await model.submit_move(model_action.piece, model_action.target)
		_expect(accepted, "random Necromancer ply %d model action is accepted" % ply)
		if not accepted: break
		while core_result.status == ChessCoreStepResult.Status.PENDING_CHOICE:
			var pending := model.get_pending_reaction()
			_expect(not pending.is_empty() and core_result.choice.options == pending.targets, "random Necromancer ply %d pending reaction matches" % ply)
			if pending.is_empty(): break
			var selected: Vector2i = core_result.choice.options[rng.randi_range(0, core_result.choice.options.size() - 1)]
			core_result = ClassicChessCore.resolve_choice(core_result.state, selected)
			await model.submit_reaction_selection(selected)
		if core_result.status != ChessCoreStepResult.Status.COMPLETED: break
		state = core_result.state
		_expect(_json(state) == ChessPositionCodec.to_json(model.capture_position(), false), "random Necromancer ply %d resulting position matches" % ply)
		if _json(state) != ChessPositionCodec.to_json(model.capture_position(), false): break
		completed += 1
	_expect(completed >= 20, "fixed-seed Necromancer differential completes a useful sequence")
	model.free()


func _ready_necromancer(color: String, coordinate: Vector2i) -> NecromancerKing:
	var result := NecromancerKing.new(color, coordinate)
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
	for action in actions: result.append("%s|%s|%s|%s" % [action.kind, action.piece.piece_id, action.target, action.path])
	result.sort(); return result


func _core_keys(actions: Array[ChessCoreAction]) -> Array[String]:
	var result: Array[String] = []
	for action in actions: result.append("%s|%s|%s|%s" % [action.kind, action.piece_id, action.target, action.path])
	result.sort(); return result


func _action_key(kind: int, piece_id: String, target: Vector2i, path: Array) -> String:
	return "%s|%s|%s|%s" % [kind, piece_id, target, path]


func _json(state: ChessCoreState) -> String:
	return ChessPositionCodec.to_json(ClassicChessCore.export_position(state), false)


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
