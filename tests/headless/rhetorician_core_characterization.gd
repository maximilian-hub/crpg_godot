extends Node

var failures: Array[String] = []
var checks := 0


func _ready() -> void:
	await _test_passive_and_compel()
	await _test_lunacy_and_socratic_rng()
	await _test_live_authority()
	await _test_compel_reaction_composition()
	await _test_socratic_no_move_path()
	await _test_randomized_differential()
	if failures.is_empty():
		print("RHETORICIAN CORE CHARACTERIZATION: PASS (", checks, " checks)")
		get_tree().quit(0)
		return
	printerr("RHETORICIAN CORE CHARACTERIZATION: FAIL")
	for failure in failures: printerr(" - ", failure)
	get_tree().quit(1)


func _test_passive_and_compel() -> void:
	var rhetorician := RhetoricianKing.new("white", Vector2i(4, 4)); rhetorician.set_cooldown(0); rhetorician.initial_cooldown_turn_pending = false
	var adjacent := Rook.new("black", Vector2i(4, 3))
	var distant := Rook.new("black", Vector2i(1, 4))
	var compelled := Pawn.new("black", Vector2i(2, 2))
	var victim := Bishop.new("black", Vector2i(3, 3))
	var model := _model([rhetorician, adjacent, distant, compelled, victim, ClassicKing.new("black", Vector2i(0, 7))])
	var imported := ClassicChessCore.import_position(model.capture_position())
	_expect(imported.ok, "Rhetorician position imports into the pure core")
	var state: ChessCoreState = imported.state
	var adjacent_core := state.piece_by_id(adjacent.piece_id)
	var distant_core := state.piece_by_id(distant.piece_id)
	_expect(not ClassicChessCore.directly_attacks_square(state, adjacent_core, rhetorician.coordinate), "adjacent ordinary attacks are blocked in pure tactical geometry")
	_expect(ClassicChessCore.directly_attacks_square(state, distant_core, rhetorician.coordinate), "distant ordinary attacks remain legal")
	var black_keys := _core_keys(ClassicChessCore.analysis_actions(state, "black"))
	_expect(_key(ChessCoreAction.Kind.MOVE, adjacent.piece_id, rhetorician.coordinate, [rhetorician.coordinate]) not in black_keys, "adjacent attacks are absent from legal action analysis")
	var action := _find(state, ChessCoreAction.Kind.ACTIVE_ABILITY, rhetorician.piece_id, compelled.coordinate)
	var result := ClassicChessCore.resolve_action(state, action)
	_expect(result.status == ChessCoreStepResult.Status.COMPLETED, "Can Logic Move Them resolves synchronously when no choice is required")
	_expect(result.state.occupant(Vector2i(3, 3)).piece_id == compelled.piece_id and result.state.piece_by_id(victim.piece_id) == null, "compelled movement lethally captures the destination occupant")
	await model.submit_active_ability(rhetorician, compelled.coordinate)
	_expect(_json(result.state) == ChessPositionCodec.to_json(model.capture_position(), false), "compel result exactly matches ChessBoardModel")
	model.free(); await get_tree().process_frame


func _test_lunacy_and_socratic_rng() -> void:
	var rhetorician := RhetoricianKing.new("white", Vector2i(7, 7)); rhetorician.initial_cooldown_turn_pending = false
	var white_rook := Rook.new("white", Vector2i(6, 0))
	var black_rook := Rook.new("black", Vector2i(1, 0))
	var model := _model([rhetorician, white_rook, black_rook, ClassicKing.new("black", Vector2i(0, 7))])
	var black_rook_id := black_rook.piece_id
	_set_authoritative_metadata(model, "black", "white", 5, 731)
	black_rook = model.find_piece_by_id(black_rook_id) as Rook
	var imported := ClassicChessCore.import_position(model.capture_position())
	_expect(imported.ok, "active Socratic state imports with serialized RNG")
	var state: ChessCoreState = imported.state
	var action := _find(state, ChessCoreAction.Kind.MOVE, black_rook.piece_id, Vector2i(2, 0))
	var result := ClassicChessCore.resolve_action(state, action)
	await model.submit_move(black_rook, Vector2i(2, 0))
	_expect(result.status == ChessCoreStepResult.Status.COMPLETED, "a Socratic move settles inside the triggering transition")
	_expect(int(result.state.socratic_turns_by_color.white) == 1 and result.state.current_turn == "black", "first Socratic move consumes one turn and returns control")
	_expect(_json(result.state) == ChessPositionCodec.to_json(model.capture_position(), false), "Socratic selection and RNG state exactly match ChessBoardModel")
	var selected := result.events.filter(func(event: ChessCoreEvent): return event.kind == &"socratic_action_selected")
	_expect(selected.size() == 1, "Socratic resolution emits one selected-action event")
	model.free(); await get_tree().process_frame


func _test_live_authority() -> void:
	var rhetorician := RhetoricianKing.new("white", Vector2i(4, 4)); rhetorician.set_cooldown(0); rhetorician.initial_cooldown_turn_pending = false
	var compelled := Pawn.new("black", Vector2i(2, 2))
	var victim := Bishop.new("black", Vector2i(3, 3))
	var model := _model([rhetorician, compelled, victim, ClassicKing.new("black", Vector2i(0, 7))])
	_expect(model.set_live_authority(ChessBoardModel.LiveAuthority.CLASSIC_CORE), "Rhetorician position activates experimental pure authority")
	_expect(await model.submit_active_ability(rhetorician, compelled.coordinate), "live pure authority accepts Can Logic Move Them")
	_expect(model.board[3][3] == compelled and not model.is_piece_active(victim), "live bridge presents compelled capture")
	_expect(model.get_live_authority_diagnostics().projection_mismatches == 0, "Rhetorician live projection remains identical")
	model.free(); await get_tree().process_frame

	var lunatic := RhetoricianKing.new("white", Vector2i(7, 7)); lunatic.initial_cooldown_turn_pending = false
	var black_rook := Rook.new("black", Vector2i(1, 0))
	model = _model([lunatic, Rook.new("white", Vector2i(6, 0)), black_rook, ClassicKing.new("black", Vector2i(0, 7))])
	var black_rook_id := black_rook.piece_id
	_set_authoritative_metadata(model, "black", "white", 5, 731)
	black_rook = model.find_piece_by_id(black_rook_id) as Rook
	_expect(model.set_live_authority(ChessBoardModel.LiveAuthority.CLASSIC_CORE), "active Socratic state activates pure live authority")
	_expect(await model.submit_move(black_rook, Vector2i(2, 0)), "live pure authority resolves the triggering move and automatic Socratic move")
	_expect(int(model.socratic_turns_by_color.white) == 1 and model.current_turn == "black", "live Socratic presentation returns control with one forced turn remaining")
	_expect(model.get_live_authority_diagnostics().projection_mismatches == 0, "live Socratic projection remains identical")
	model.free(); await get_tree().process_frame

	rhetorician = RhetoricianKing.new("white", Vector2i(4, 4)); rhetorician.set_cooldown(0); rhetorician.initial_cooldown_turn_pending = false
	compelled = Pawn.new("black", Vector2i(2, 2)); var major_victim := Queen.new("black", Vector2i(3, 3))
	var necromancer := NecromancerKing.new("black", Vector2i(0, 7)); necromancer.initial_cooldown_turn_pending = false
	model = _model([rhetorician, compelled, major_victim, necromancer])
	_expect(model.set_live_authority(ChessBoardModel.LiveAuthority.CLASSIC_CORE), "mixed Rhetorician/Necromancer position activates pure live authority")
	_expect(await model.submit_active_ability(rhetorician, compelled.coordinate) and model.has_pending_reaction(), "live compelled capture exposes Raise Dead through the existing reaction API")
	var reaction_target: Vector2i = model.get_pending_reaction().targets[0]
	_expect(await model.submit_reaction_selection(reaction_target), "live bridge resumes a compelled-capture reaction")
	_expect(model.board[reaction_target.x][reaction_target.y] is BonePawn and model.get_live_authority_diagnostics().projection_mismatches == 0, "mixed compel reaction settles with an identical projection")
	model.free(); await get_tree().process_frame


func _test_compel_reaction_composition() -> void:
	var rhetorician := RhetoricianKing.new("white", Vector2i(4, 4)); rhetorician.set_cooldown(0); rhetorician.initial_cooldown_turn_pending = false
	var compelled := Pawn.new("black", Vector2i(2, 2))
	var victim := Queen.new("black", Vector2i(3, 3))
	var necromancer := NecromancerKing.new("black", Vector2i(0, 7)); necromancer.initial_cooldown_turn_pending = false
	var model := _model([rhetorician, compelled, victim, necromancer])
	var state: ChessCoreState = ClassicChessCore.import_position(model.capture_position()).state
	var result := ClassicChessCore.resolve_action(state, _find(state, ChessCoreAction.Kind.ACTIVE_ABILITY, rhetorician.piece_id, compelled.coordinate))
	_expect(result.status == ChessCoreStepResult.Status.PENDING_CHOICE and result.choice.kind == &"raise_dead", "compelled major capture enters the shared Raise Dead reaction lifecycle")
	var selected: Vector2i = result.choice.options[0]
	model.reaction_selection_requested.connect(func(_caller, _action_type, targets): model.call_deferred(&"submit_reaction_selection", selected if selected in targets else targets[0]), CONNECT_ONE_SHOT)
	var settled := ClassicChessCore.resolve_choice(result.state, selected)
	await model.submit_active_ability(rhetorician, compelled.coordinate)
	for _frame in range(4):
		if model.is_settled(): break
		await get_tree().process_frame
	var core_json := _json(settled.state); var model_json := ChessPositionCodec.to_json(model.capture_position(), false)
	_expect(settled.status == ChessCoreStepResult.Status.COMPLETED and core_json == model_json, "compel, Raise Dead, cooldown, and turn completion match the model")
	model.free(); await get_tree().process_frame


func _test_socratic_no_move_path() -> void:
	var rhetorician := RhetoricianKing.new("white", Vector2i(7, 7)); rhetorician.stunned = true; rhetorician.stun_timer = 20; rhetorician.initial_cooldown_turn_pending = false
	var black_rook := Rook.new("black", Vector2i(1, 0))
	var model := _model([rhetorician, black_rook, ClassicKing.new("black", Vector2i(0, 7))])
	var black_rook_id := black_rook.piece_id
	_set_authoritative_metadata(model, "black", "white", 5, 441)
	black_rook = model.find_piece_by_id(black_rook_id) as Rook
	var state: ChessCoreState = ClassicChessCore.import_position(model.capture_position()).state
	var result := ClassicChessCore.resolve_action(state, _find(state, ChessCoreAction.Kind.MOVE, black_rook.piece_id, Vector2i(2, 0)))
	await model.submit_move(black_rook, Vector2i(2, 0))
	_expect(_json(result.state) == ChessPositionCodec.to_json(model.capture_position(), false), "a Socratic color with no legal moves skips and resolves forced passes identically")
	model.free(); await get_tree().process_frame


func _test_randomized_differential() -> void:
	var white := RhetoricianKing.new("white", Vector2i(7, 4)); white.set_cooldown(0); white.initial_cooldown_turn_pending = false
	var black := RhetoricianKing.new("black", Vector2i(0, 4)); black.set_cooldown(0); black.initial_cooldown_turn_pending = false
	var model := _model([
		white, Rook.new("white", Vector2i(6, 0)), Bishop.new("white", Vector2i(5, 2)), Knight.new("white", Vector2i(6, 6)),
		black, Rook.new("black", Vector2i(1, 7)), Bishop.new("black", Vector2i(2, 5)), Knight.new("black", Vector2i(1, 1)),
	])
	_set_authoritative_metadata(model, "black", "white", 5, 918273)
	var state: ChessCoreState = ClassicChessCore.import_position(model.capture_position()).state
	var rng := RandomNumberGenerator.new(); rng.seed = 552211
	var compared := 0
	for _ply in range(24):
		if state.battle_over: break
		var model_map := {}
		for action in model.get_legal_primary_actions(model.current_turn): model_map[_model_action_key(action)] = action
		var core_map := {}
		for action in ClassicChessCore.legal_actions(state, state.current_turn): core_map[_core_action_key(action)] = action
		_expect(model_map.keys() == core_map.keys(), "randomized Rhetorician legal actions match at ply %d" % compared)
		if model_map.keys() != core_map.keys() or model_map.is_empty(): break
		var keys := model_map.keys(); keys.sort()
		var selected: String = keys[rng.randi_range(0, keys.size() - 1)]
		var core_result := ClassicChessCore.resolve_action(state, core_map[selected])
		var model_action: ChessPrimaryAction = model_map[selected]
		if model_action.kind == ChessPrimaryAction.Kind.ACTIVE_ABILITY:
			await model.submit_active_ability(model_action.piece, model_action.target)
		elif model_action.path.size() == 2:
			await model.submit_move_path(model_action.piece, model_action.path)
		else:
			await model.submit_move(model_action.piece, model_action.target)
		state = core_result.state
		compared += 1
		_expect(_json(state) == ChessPositionCodec.to_json(model.capture_position(), false), "randomized Rhetorician state matches at ply %d" % compared)
		if _json(state) != ChessPositionCodec.to_json(model.capture_position(), false): break
	_expect(compared >= 12, "randomized Rhetorician differential completes meaningful depth")
	model.free(); await get_tree().process_frame


func _model(pieces: Array) -> ChessBoardModel:
	var model := ChessBoardModel.new(); model.startup_mode = ChessBoardModel.StartupMode.EMPTY; model.diagnostic_logging_enabled = false
	add_child(model)
	for _row in range(8): model.board.append([null, null, null, null, null, null, null, null])
	model.is_initialized = true; model.current_turn = "white"
	for piece in pieces: model.add_piece(piece, piece.coordinate)
	return model


func _set_authoritative_metadata(model: ChessBoardModel, turn: String, lunacy_color: String, lunacy: int, seed: int) -> void:
	var position := model.capture_position()
	position.current_turn = turn
	position.lunacy_by_color[lunacy_color] = lunacy
	position.socratic_turns_by_color[lunacy_color] = 2 if lunacy >= RhetoricianCoreRules.LUNACY_THRESHOLD else 0
	var rng := RandomNumberGenerator.new(); rng.seed = seed
	position.random_states[&"lunacy"] = rng.state
	assert(model.load_position(position))


func _find(state: ChessCoreState, kind: int, piece_id: String, target: Vector2i) -> ChessCoreAction:
	for action in ClassicChessCore.legal_actions(state, state.current_turn):
		if action.kind == kind and action.piece_id == piece_id and action.target == target: return action
	return null


func _core_keys(actions: Array[ChessCoreAction]) -> Array[String]:
	var result: Array[String] = []
	for action in actions: result.append(_key(action.kind, action.piece_id, action.target, action.path))
	return result


func _key(kind: int, piece_id: String, target: Vector2i, path: Array) -> String:
	return "%s|%s|%s|%s" % [kind, piece_id, target, path]


func _model_action_key(action: ChessPrimaryAction) -> String:
	return _key(action.kind, action.piece.piece_id, action.target, action.path)


func _core_action_key(action: ChessCoreAction) -> String:
	return _key(action.kind, action.piece_id, action.target, action.path)


func _json(state: ChessCoreState) -> String:
	return ChessPositionCodec.to_json(ClassicChessCore.export_position(state), false)


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
