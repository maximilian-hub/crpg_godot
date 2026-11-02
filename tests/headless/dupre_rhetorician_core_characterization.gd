extends Node

var failures: Array[String] = []


func _ready() -> void:
	var position := _position()
	var model_result := await _think(position, DupreAiBrain.SimulationBackend.MODEL)
	var core_result := await _think(position, DupreAiBrain.SimulationBackend.CLASSIC_CORE)
	_expect(model_result.thought != null and core_result.thought != null, "both Rhetorician backends produce a decision")
	if model_result.thought != null and core_result.thought != null:
		_expect(_key(model_result.thought) == _key(core_result.thought), "Rhetorician model/core best action matches")
		_expect(is_equal_approx(float(model_result.thought.score), float(core_result.thought.score)), "Rhetorician model/core score matches (%s vs %s)" % [model_result.thought.score, core_result.thought.score])
		_expect(int(core_result.profile.model_construction_count) == 0 and String(core_result.profile.simulation_backend) == "classic_core", "Rhetorician core search constructs no Nodes")
		_expect(int(core_result.profile.invalid_root_candidates) == 0, "Rhetorician core search has no invalid roots")
	_expect(model_result.before == model_result.after and core_result.before == core_result.after, "Rhetorician speculation does not mutate live position or RNG")
	var auto_result := await _think(position, DupreAiBrain.SimulationBackend.AUTO)
	_expect(String(auto_result.profile.simulation_backend) == "classic_core", "AUTO routes Rhetorician through the pure backend")
	if failures.is_empty():
		print("DUPRE RHETORICIAN CORE CHARACTERIZATION: PASS (7 checks)"); get_tree().quit(0); return
	printerr("DUPRE RHETORICIAN CORE CHARACTERIZATION: FAIL")
	for failure in failures: printerr(" - ", failure)
	get_tree().quit(1)


func _think(position: ChessPosition, backend: int) -> Dictionary:
	var model := ChessBoardModel.new(); model.startup_mode = ChessBoardModel.StartupMode.EMPTY; model.diagnostic_logging_enabled = false; add_child(model); model.load_position(position.copy())
	var cpu := ChessCpuPlayer.new(); cpu.model = model; add_child(cpu); cpu.configure_mode(ChessCpuPlayer.ExecutionMode.MANUAL, "white"); cpu.set_brain(ChessCpuPlayer.BrainKind.DUPRE); cpu.set_random_seed(77123)
	var brain: DupreAiBrain = cpu.brain; brain.max_book_moves = 0; brain.simulation_backend = backend; brain.think_budget_msec = 10000; brain.max_reply_leaves = 10000; brain.candidate_limit = 3; brain.quiescence_enabled = false
	var before := ChessPositionCodec.to_json(model.capture_position(), false)
	var thought = await cpu.think()
	var result := {"thought": thought, "profile": brain.get_last_profile(), "before": before, "after": ChessPositionCodec.to_json(model.capture_position(), false)}
	cpu.queue_free(); model.queue_free(); await get_tree().process_frame
	return result


func _position() -> ChessPosition:
	var rhetorician := RhetoricianKing.new("white", Vector2i(4, 4)); rhetorician.set_cooldown(0); rhetorician.initial_cooldown_turn_pending = false
	var model := ChessBoardModel.new(); model.startup_mode = ChessBoardModel.StartupMode.EMPTY; model.diagnostic_logging_enabled = false; add_child(model)
	for _row in range(8): model.board.append([null, null, null, null, null, null, null, null])
	model.is_initialized = true; model.current_turn = "white"; model.set_lunacy_random_seed(771991)
	for piece in [rhetorician, ClassicKing.new("black", Vector2i(0, 7)), Rook.new("white", Vector2i(6, 0)), Pawn.new("black", Vector2i(2, 2)), Queen.new("black", Vector2i(3, 3)), Rook.new("black", Vector2i(1, 4))]: model.add_piece(piece, piece.coordinate)
	var result := model.capture_position(); model.queue_free(); return result


func _key(thought) -> String:
	return "%s|%s|%s|%s" % [thought.action_kind, thought.piece_type_id, thought.piece_coordinate, thought.target]


func _expect(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
