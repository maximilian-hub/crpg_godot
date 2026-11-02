extends Node

var failures: Array[String] = []
var checks := 0


func _ready() -> void:
	await _test_charge_targets_and_wall_stun()
	await _test_charge_collision_outcomes()
	await _test_rage_from_ordinary_damage()
	await _test_rage_from_spike_burst()
	await _test_rage_priority_before_raise_dead()
	await _test_alternating_rage_cascade()
	await _test_randomized_differential()
	if failures.is_empty():
		print("MINOTAUR CORE CHARACTERIZATION: PASS (", checks, " checks)")
		get_tree().quit(0)
		return
	printerr("MINOTAUR CORE CHARACTERIZATION: FAIL")
	for failure in failures: printerr(" - ", failure)
	get_tree().quit(1)


func _test_charge_targets_and_wall_stun() -> void:
	var minotaur := _ready_minotaur("white", Vector2i(4, 3))
	var friendly := Rook.new("white", Vector2i(4, 6))
	var model := _model([minotaur, friendly, ClassicKing.new("black", Vector2i(0, 7))])
	var state: ChessCoreState = ClassicChessCore.import_position(model.capture_position()).state
	_expect(_model_keys(model.get_legal_primary_actions("white")) == _core_keys(ClassicChessCore.legal_actions(state, "white")), "Charge targets, including the legacy friendly blocker target, match")
	var action := _find(state, ChessCoreAction.Kind.ACTIVE_ABILITY, minotaur.piece_id, Vector2i(4, 0))
	var result := ClassicChessCore.resolve_action(state, action)
	_expect(await model.submit_active_ability(minotaur, action.target), "model accepts wall Charge")
	var core_minotaur := result.state.piece_by_id(minotaur.piece_id)
	_expect(core_minotaur.coordinate == Vector2i(4, 0) and core_minotaur.stunned and core_minotaur.stun_timer == 2, "wall Charge lands and applies a two-turn self-stun")
	_expect(_json(result.state) == ChessPositionCodec.to_json(model.capture_position(), false), "wall Charge state matches the model")
	model.free()


func _test_charge_collision_outcomes() -> void:
	var charger := _ready_minotaur("white", Vector2i(4, 0))
	var durable := MinotaurKing.new("black", Vector2i(4, 4)); durable.stunned = true; durable.stun_timer = 20
	var model := _model([charger, durable])
	var state: ChessCoreState = ClassicChessCore.import_position(model.capture_position()).state
	var result := ClassicChessCore.resolve_action(state, _find(state, ChessCoreAction.Kind.ACTIVE_ABILITY, charger.piece_id, durable.coordinate))
	_expect(await model.submit_active_ability(charger, durable.coordinate), "model accepts Charge into a durable target")
	_expect(result.state.piece_by_id(charger.piece_id).coordinate == Vector2i(4, 3) and result.state.piece_by_id(durable.piece_id).current_hp == 2, "durable collision stops adjacent and deals two damage")
	_expect(_json(result.state) == ChessPositionCodec.to_json(model.capture_position(), false), "durable Charge matches the model")
	model.free()

	charger = _ready_minotaur("white", Vector2i(4, 0))
	var pawn := Pawn.new("black", Vector2i(4, 4))
	model = _model([charger, ClassicKing.new("black", Vector2i(0, 7)), pawn])
	state = ClassicChessCore.import_position(model.capture_position()).state
	result = ClassicChessCore.resolve_action(state, _find(state, ChessCoreAction.Kind.ACTIVE_ABILITY, charger.piece_id, pawn.coordinate))
	_expect(await model.submit_active_ability(charger, pawn.coordinate), "model accepts physical Charge capture")
	_expect(result.state.piece_by_id(pawn.piece_id) == null and result.state.piece_by_id(charger.piece_id).coordinate == pawn.coordinate, "one-HP collision captures and occupies the target square")
	_expect(_json(result.state) == ChessPositionCodec.to_json(model.capture_position(), false), "physical Charge capture matches the model")
	model.free()


func _test_rage_from_ordinary_damage() -> void:
	var rook := Rook.new("white", Vector2i(4, 0))
	var victim := Bishop.new("white", Vector2i(3, 3))
	var minotaur := MinotaurKing.new("black", Vector2i(4, 4))
	var model := _model([ClassicKing.new("white", Vector2i(7, 7)), rook, victim, minotaur])
	var state: ChessCoreState = ClassicChessCore.import_position(model.capture_position()).state
	var result := ClassicChessCore.resolve_action(state, _find(state, ChessCoreAction.Kind.MOVE, rook.piece_id, minotaur.coordinate))
	_expect(await model.submit_move(rook, minotaur.coordinate), "model accepts a surviving hit that triggers Rage")
	_expect(result.status == ChessCoreStepResult.Status.COMPLETED, "automatic Rage settles without a choice")
	_expect(result.state.piece_by_id(minotaur.piece_id).current_hp == 3 and result.state.piece_by_id(victim.piece_id) == null, "Rage damages every occupied adjacent square")
	_expect(_json(result.state) == ChessPositionCodec.to_json(model.capture_position(), false), "ordinary damage and Rage match the model")
	model.free()


func _test_rage_from_spike_burst() -> void:
	var arakne := ArakneKing.new("white", Vector2i(4, 3)); arakne.set_cooldown(0); arakne.initial_cooldown_turn_pending = false
	var minotaur := MinotaurKing.new("black", Vector2i(4, 4))
	var model := _model([arakne, minotaur])
	var state: ChessCoreState = ClassicChessCore.import_position(model.capture_position()).state
	var result := ClassicChessCore.resolve_action(state, _find(state, ChessCoreAction.Kind.ACTIVE_ABILITY, arakne.piece_id, minotaur.coordinate))
	_expect(await model.submit_active_ability(arakne, minotaur.coordinate), "model accepts Spike Burst that triggers Rage")
	_expect(result.state.piece_by_id(minotaur.piece_id).current_hp == 3 and result.state.piece_by_id(arakne.piece_id).current_hp == arakne.max_hp - 1, "Spike Burst damage is followed by adjacent Rage damage")
	_expect(_json(result.state) == ChessPositionCodec.to_json(model.capture_position(), false), "Spike Burst-triggered Rage matches the model")
	model.free()


func _test_rage_priority_before_raise_dead() -> void:
	var rook := Rook.new("white", Vector2i(4, 0))
	var bishop := Bishop.new("white", Vector2i(3, 3))
	var minotaur := MinotaurKing.new("black", Vector2i(4, 4))
	var necromancer := NecromancerKing.new("black", Vector2i(0, 7))
	var model := _model([ClassicKing.new("white", Vector2i(7, 7)), rook, bishop, minotaur, necromancer])
	var state: ChessCoreState = ClassicChessCore.import_position(model.capture_position()).state
	var result := ClassicChessCore.resolve_action(state, _find(state, ChessCoreAction.Kind.MOVE, rook.piece_id, minotaur.coordinate))
	_expect(await model.submit_move(rook, minotaur.coordinate), "mixed Rage and Raise Dead action begins")
	_expect(result.status == ChessCoreStepResult.Status.PENDING_CHOICE and result.choice.kind == &"raise_dead", "Rage resolves before exposing the resulting Raise Dead choice")
	_expect(model.has_pending_reaction() and result.choice.options == model.get_pending_reaction().targets, "post-Rage Raise Dead targets match")
	var selected: Vector2i = result.choice.options[0]
	result = ClassicChessCore.resolve_choice(result.state, selected)
	await model.submit_reaction_selection(selected)
	_expect(_json(result.state) == ChessPositionCodec.to_json(model.capture_position(), false), "mixed automatic and selected reactions settle identically")
	model.free()


func _test_alternating_rage_cascade() -> void:
	var rook := Rook.new("white", Vector2i(4, 0))
	var white := MinotaurKing.new("white", Vector2i(3, 3))
	var black := MinotaurKing.new("black", Vector2i(4, 4))
	var model := _model([white, rook, black])
	var state: ChessCoreState = ClassicChessCore.import_position(model.capture_position()).state
	var result := ClassicChessCore.resolve_action(state, _find(state, ChessCoreAction.Kind.MOVE, rook.piece_id, black.coordinate))
	_expect(await model.submit_move(rook, black.coordinate), "model settles alternating adjacent Rage reactions")
	_expect(result.status == ChessCoreStepResult.Status.COMPLETED and result.state.battle_over, "pure Rage cascade terminates at King defeat")
	_expect(_json(result.state) == ChessPositionCodec.to_json(model.capture_position(), false), "alternating Rage cascade and terminal result match the model")
	model.free()


func _test_randomized_differential() -> void:
	var white := _ready_minotaur("white", Vector2i(7, 4))
	var black := _ready_minotaur("black", Vector2i(0, 4))
	var model := _model([
		white, black, Rook.new("white", Vector2i(6, 0)), Bishop.new("white", Vector2i(6, 2)), Knight.new("white", Vector2i(5, 5)),
		Rook.new("black", Vector2i(1, 7)), Bishop.new("black", Vector2i(1, 5)), Knight.new("black", Vector2i(2, 2)),
	])
	var state: ChessCoreState = ClassicChessCore.import_position(model.capture_position()).state
	var rng := RandomNumberGenerator.new(); rng.seed = 731991
	var completed := 0
	for ply in range(40):
		if state.battle_over: break
		var model_map := {}; var core_map := {}
		for action in model.get_legal_primary_actions(model.current_turn): model_map[_action_key(action.kind, action.piece.piece_id, action.target, action.path)] = action
		for action in ClassicChessCore.legal_actions(state, state.current_turn): core_map[_action_key(action.kind, action.piece_id, action.target, action.path)] = action
		var model_keys := model_map.keys(); model_keys.sort()
		var core_keys := core_map.keys(); core_keys.sort()
		_expect(model_keys == core_keys, "random Minotaur ply %d legal actions match" % ply)
		if model_keys != core_keys or core_keys.is_empty(): break
		var key = core_keys[rng.randi_range(0, core_keys.size() - 1)]
		var core_result := ClassicChessCore.resolve_action(state, core_map[key])
		var model_action: ChessPrimaryAction = model_map[key]
		var accepted := await model.submit_active_ability(model_action.piece, model_action.target) if model_action.kind == ChessPrimaryAction.Kind.ACTIVE_ABILITY else await model.submit_move(model_action.piece, model_action.target)
		_expect(accepted, "random Minotaur ply %d model action is accepted" % ply)
		if not accepted or core_result.status != ChessCoreStepResult.Status.COMPLETED: break
		state = core_result.state
		_expect(_json(state) == ChessPositionCodec.to_json(model.capture_position(), false), "random Minotaur ply %d resulting position matches" % ply)
		if _json(state) != ChessPositionCodec.to_json(model.capture_position(), false): break
		completed += 1
	_expect(completed >= 20, "fixed-seed Minotaur differential completes a useful sequence")
	model.free()


func _ready_minotaur(color: String, coordinate: Vector2i) -> MinotaurKing:
	var result := MinotaurKing.new(color, coordinate)
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
