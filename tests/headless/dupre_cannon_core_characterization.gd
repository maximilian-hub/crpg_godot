extends Node

var failures: Array[String] = []


func _ready() -> void:
	var position := _position()
	var model_result := await _think(position, DupreAiBrain.SimulationBackend.MODEL)
	var core_result := await _think(position, DupreAiBrain.SimulationBackend.CLASSIC_CORE)
	_expect(model_result.thought != null and core_result.thought != null, "both Cannon backends produce a decision")
	if model_result.thought != null and core_result.thought != null:
		_expect(_key(model_result.thought) == _key(core_result.thought), "Cannon model/core best action matches")
		_expect(is_equal_approx(float(model_result.thought.score), float(core_result.thought.score)), "Cannon model/core score matches")
		_expect(int(core_result.profile.model_construction_count) == 0 and String(core_result.profile.simulation_backend) == "classic_core", "Cannon core search constructs no Nodes")
		_expect(int(core_result.profile.invalid_root_candidates) == 0, "Cannon core search has no invalid roots")
	_expect(model_result.before == model_result.after and core_result.before == core_result.after, "Cannon speculation does not mutate live state")
	if failures.is_empty():
		print("DUPRE CANNON CORE CHARACTERIZATION: PASS (6 checks)"); get_tree().quit(0); return
	printerr("DUPRE CANNON CORE CHARACTERIZATION: FAIL")
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
	var cannon := CannonKing.new("white", Vector2i(7, 4)); cannon.set_cooldown(0); cannon.initial_cooldown_turn_pending = false
	var model := ChessBoardModel.new(); model.startup_mode = ChessBoardModel.StartupMode.EMPTY; model.diagnostic_logging_enabled = false; add_child(model)
	for _row in range(8): model.board.append([null, null, null, null, null, null, null, null])
	model.is_initialized = true; model.current_turn = "white"
	for piece in [cannon, ClassicKing.new("black", Vector2i(0, 4)), Rook.new("white", Vector2i(6, 0)), Rook.new("black", Vector2i(3, 3)), Bishop.new("black", Vector2i(3, 4))]: model.add_piece(piece, piece.coordinate)
	var result := model.capture_position(); model.queue_free(); return result


func _key(thought) -> String:
	return "%s|%s|%s|%s" % [thought.action_kind, thought.piece_type_id, thought.piece_coordinate, thought.target]


func _expect(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
