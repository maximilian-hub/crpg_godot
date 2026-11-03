extends Node

var failures: Array[String] = []
var checks := 0


func _ready() -> void:
	for scenario in [&"quiet", &"poisoned", &"king_danger", &"promotion"]:
		await _compare_completed_search(scenario)
	await _compare_arakne_search()
	await _compare_necromancer_search()
	await _test_necromancer_core_routing()
	await _compare_minotaur_search()
	await _test_minotaur_core_routing()
	await _compare_quarterly_search()
	await _test_quarterly_core_routing()
	await _test_cannon_core_routing()
	await _compare_rhetorician_search()
	await _test_rhetorician_core_routing()
	await _test_forced_core_rejection_fallback()
	if failures.is_empty():
		print("DUPRE CLASSIC CORE CHARACTERIZATION: PASS (", checks, " checks)")
		get_tree().quit(0)
		return
	printerr("DUPRE CLASSIC CORE CHARACTERIZATION: FAIL")
	for failure in failures: printerr(" - ", failure)
	get_tree().quit(1)


func _compare_completed_search(scenario: StringName) -> void:
	var position := _position(scenario)
	var model_result := await _think(position, DupreAiBrain.SimulationBackend.MODEL)
	var core_result := await _think(position, DupreAiBrain.SimulationBackend.CLASSIC_CORE)
	_expect(model_result.thought != null and core_result.thought != null, "%s produces decisions through both backends" % scenario)
	if model_result.thought == null or core_result.thought == null: return
	_expect(model_result.action == core_result.action, "%s exact best action matches" % scenario)
	_expect(is_equal_approx(float(model_result.thought.score), float(core_result.thought.score)), "%s exact selected score matches" % scenario)
	_expect(int(model_result.profile.invalid_root_candidates) == 0 and int(core_result.profile.invalid_root_candidates) == 0, "%s has no invalid candidates" % scenario)
	_expect(int(model_result.profile.incomplete_root_candidates) == 0 and int(core_result.profile.incomplete_root_candidates) == 0, "%s completes both searches" % scenario)
	_expect(String(core_result.profile.simulation_backend) == "classic_core" and int(core_result.profile.model_construction_count) == 0, "%s core search constructs no simulation Nodes" % scenario)
	_expect(model_result.before == model_result.after and core_result.before == core_result.after, "%s speculative searches preserve live state" % scenario)
	var model_scores := _exact_scores(model_result.thought.candidates)
	var core_scores := _exact_scores(core_result.thought.candidates)
	_expect(model_scores.keys() == core_scores.keys(), "%s exact candidate identities match" % scenario)
	for key in model_scores:
		_expect(is_equal_approx(float(model_scores[key]), float(core_scores.get(key, INF))), "%s score matches for %s" % [scenario, key])


func _test_necromancer_core_routing() -> void:
	var model := _model_from_position(_necromancer_position())
	var result := await _think_on_model(model, DupreAiBrain.SimulationBackend.AUTO)
	_expect(result.thought != null, "AUTO produces a Necromancer decision")
	_expect(String(result.profile.simulation_backend) == "classic_core" and int(result.profile.model_construction_count) == 0, "AUTO routes migrated Necromancer state through the pure backend")


func _test_minotaur_core_routing() -> void:
	var model := _model_from_position(_minotaur_position())
	var result := await _think_on_model(model, DupreAiBrain.SimulationBackend.AUTO)
	_expect(result.thought != null, "AUTO produces a Minotaur decision")
	_expect(String(result.profile.simulation_backend) == "classic_core" and int(result.profile.model_construction_count) == 0, "AUTO routes migrated Minotaur state through the pure backend")


func _test_quarterly_core_routing() -> void:
	var model := _model_from_position(_quarterly_position())
	var result := await _think_on_model(model, DupreAiBrain.SimulationBackend.AUTO)
	_expect(result.thought != null, "AUTO produces a Quarterly decision")
	_expect(String(result.profile.simulation_backend) == "classic_core" and int(result.profile.model_construction_count) == 0, "AUTO routes migrated Quarterly state through the pure backend")


func _test_cannon_core_routing() -> void:
	var model := _model_from_position(_cannon_position())
	var result := await _think_on_model(model, DupreAiBrain.SimulationBackend.AUTO)
	_expect(result.thought != null, "AUTO produces a Cannon decision")
	_expect(String(result.profile.simulation_backend) == "classic_core" and int(result.profile.model_construction_count) == 0, "AUTO routes migrated Cannon state through the pure backend")


func _test_rhetorician_core_routing() -> void:
	var model := _model_from_position(_rhetorician_position())
	var result := await _think_on_model(model, DupreAiBrain.SimulationBackend.AUTO)
	_expect(result.thought != null, "AUTO produces a Rhetorician decision")
	_expect(String(result.profile.simulation_backend) == "classic_core" and int(result.profile.model_construction_count) == 0, "AUTO routes migrated Rhetorician state through the pure backend")


func _compare_arakne_search() -> void:
	var position := _arakne_position()
	var model_result := await _think(position, DupreAiBrain.SimulationBackend.MODEL)
	var core_result := await _think(position, DupreAiBrain.SimulationBackend.CLASSIC_CORE)
	_expect(model_result.thought != null and core_result.thought != null, "Arakne produces decisions through both backends")
	if model_result.thought == null or core_result.thought == null: return
	_expect(model_result.action == core_result.action, "Arakne exact best action matches")
	_expect(is_equal_approx(float(model_result.thought.score), float(core_result.thought.score)), "Arakne selected score matches")
	_expect(String(core_result.profile.simulation_backend) == "classic_core" and int(core_result.profile.model_construction_count) == 0, "Arakne core search constructs no simulation Nodes")


func _compare_necromancer_search() -> void:
	var position := _necromancer_position()
	var model_result := await _think(position, DupreAiBrain.SimulationBackend.MODEL)
	var core_result := await _think(position, DupreAiBrain.SimulationBackend.CLASSIC_CORE)
	_expect(model_result.thought != null and core_result.thought != null, "Necromancer produces decisions through both backends")
	if model_result.thought == null or core_result.thought == null: return
	_expect(model_result.action == core_result.action, "Necromancer exact best action matches")
	_expect(is_equal_approx(float(model_result.thought.score), float(core_result.thought.score)), "Necromancer selected score matches")
	_expect(int(model_result.profile.invalid_root_candidates) == 0 and int(core_result.profile.invalid_root_candidates) == 0, "Necromancer has no invalid simulated reaction chains")
	_expect(String(core_result.profile.simulation_backend) == "classic_core" and int(core_result.profile.model_construction_count) == 0, "Necromancer core search constructs no simulation Nodes")


func _compare_minotaur_search() -> void:
	var position := _minotaur_position()
	var model_result := await _think(position, DupreAiBrain.SimulationBackend.MODEL)
	var core_result := await _think(position, DupreAiBrain.SimulationBackend.CLASSIC_CORE)
	_expect(model_result.thought != null and core_result.thought != null, "Minotaur produces decisions through both backends")
	if model_result.thought == null or core_result.thought == null: return
	_expect(model_result.action == core_result.action, "Minotaur exact best action matches")
	_expect(is_equal_approx(float(model_result.thought.score), float(core_result.thought.score)), "Minotaur selected score matches")
	_expect(int(model_result.profile.invalid_root_candidates) == 0 and int(core_result.profile.invalid_root_candidates) == 0, "Minotaur has no invalid simulated Rage chains")
	_expect(String(core_result.profile.simulation_backend) == "classic_core" and int(core_result.profile.model_construction_count) == 0, "Minotaur core search constructs no simulation Nodes")


func _compare_quarterly_search() -> void:
	var position := _quarterly_position()
	var model_result := await _think(position, DupreAiBrain.SimulationBackend.MODEL)
	var core_result := await _think(position, DupreAiBrain.SimulationBackend.CLASSIC_CORE)
	_expect(model_result.thought != null and core_result.thought != null, "Quarterly produces decisions through both backends")
	if model_result.thought == null or core_result.thought == null: return
	_expect(model_result.action == core_result.action, "Quarterly exact best action matches")
	_expect(is_equal_approx(float(model_result.thought.score), float(core_result.thought.score)), "Quarterly selected score matches")
	_expect(int(model_result.profile.invalid_root_candidates) == 0 and int(core_result.profile.invalid_root_candidates) == 0, "Quarterly has no invalid secondary choices")
	_expect(String(core_result.profile.simulation_backend) == "classic_core" and int(core_result.profile.model_construction_count) == 0, "Quarterly core search constructs no simulation Nodes")


func _compare_rhetorician_search() -> void:
	var position := _rhetorician_position()
	var model_result := await _think(position, DupreAiBrain.SimulationBackend.MODEL)
	var core_result := await _think(position, DupreAiBrain.SimulationBackend.CLASSIC_CORE)
	_expect(model_result.thought != null and core_result.thought != null, "Rhetorician produces decisions through both backends")
	if model_result.thought == null or core_result.thought == null: return
	_expect(model_result.action == core_result.action, "Rhetorician exact best action matches")
	_expect(is_equal_approx(float(model_result.thought.score), float(core_result.thought.score)), "Rhetorician selected score matches")
	_expect(int(core_result.profile.invalid_root_candidates) == 0, "Rhetorician core search has no invalid candidates")
	_expect(String(core_result.profile.simulation_backend) == "classic_core" and int(core_result.profile.model_construction_count) == 0, "Rhetorician core search constructs no simulation Nodes")
	_expect(model_result.before == model_result.after and core_result.before == core_result.after, "Rhetorician speculative search preserves live RNG and position state")


func _test_forced_core_rejection_fallback() -> void:
	var modified := _position(&"quiet")
	modified.pieces[0].granted_movement_types.append(&"teleport")
	var result := await _think(modified, DupreAiBrain.SimulationBackend.CLASSIC_CORE)
	_expect(result.thought != null, "forced core mode safely produces a decision for unsupported modified state")
	_expect(String(result.profile.simulation_backend) == "model" and String(result.profile.simulation_backend_fallback_reason) == "unsupported_position", "forced core mode falls back before search when import rejects the position")


func _think(position: ChessPosition, backend: int) -> Dictionary:
	return await _think_on_model(_model_from_position(position), backend)


func _think_on_model(model: ChessBoardModel, backend: int) -> Dictionary:
	if not model.is_inside_tree(): add_child(model)
	var cpu := ChessCpuPlayer.new(); cpu.model = model; add_child(cpu)
	cpu.configure_mode(ChessCpuPlayer.ExecutionMode.MANUAL, model.current_turn)
	cpu.set_brain(ChessCpuPlayer.BrainKind.DUPRE); cpu.set_random_seed(77123)
	var brain: DupreAiBrain = cpu.brain
	brain.max_book_moves = 0
	brain.simulation_backend = backend
	# Keep this parity gate bounded: two policy-leading roots are enough to prove
	# backend identity without turning a characterization test into a long soak.
	brain.think_budget_msec = 4000
	brain.max_reply_leaves = 256
	brain.candidate_limit = 2
	var before := ChessPositionCodec.to_json(model.capture_position(), false)
	var thought = await cpu.think()
	var output := {
		"thought": thought, "action": _thought_key(thought), "profile": brain.get_last_profile(),
		"before": before, "after": ChessPositionCodec.to_json(model.capture_position(), false),
	}
	cpu.queue_free(); model.queue_free(); await get_tree().process_frame
	return output


func _exact_scores(candidates: Array) -> Dictionary:
	var result := {}
	for candidate in candidates:
		if String(candidate.get("status", "")) != "complete": continue
		var action: Dictionary = candidate.get("action", {})
		result[_descriptor_key(action)] = float(candidate.get("search_score", 0.0))
	return result


func _descriptor_key(value: Dictionary) -> String:
	return "%s|%s|%s|%s" % [value.get("kind", -1), value.get("piece_id", ""), value.get("target", []), value.get("path", [])]


func _thought_key(thought) -> String:
	if thought == null: return ""
	return "%s|%s|%s|%s" % [thought.action_kind, thought.piece_type_id, thought.piece_coordinate, thought.target]


func _position(scenario: StringName) -> ChessPosition:
	var pieces: Array = []
	match scenario:
		&"poisoned": pieces = [
			ClassicKing.new("white", Vector2i(7, 7)), ClassicKing.new("black", Vector2i(0, 7)),
			Queen.new("white", Vector2i(4, 4)), Pawn.new("black", Vector2i(4, 3)), Rook.new("black", Vector2i(4, 0)),
		]
		&"king_danger": pieces = [
			ClassicKing.new("white", Vector2i(7, 4)), ClassicKing.new("black", Vector2i(0, 7)),
			Rook.new("black", Vector2i(7, 0)), Rook.new("white", Vector2i(6, 4)), Bishop.new("white", Vector2i(6, 2)),
		]
		&"promotion": pieces = [
			ClassicKing.new("white", Vector2i(7, 7)), ClassicKing.new("black", Vector2i(0, 7)),
			Pawn.new("white", Vector2i(1, 0)), Rook.new("white", Vector2i(5, 4)), Pawn.new("black", Vector2i(2, 6)),
		]
		_: pieces = [
			ClassicKing.new("white", Vector2i(7, 4)), ClassicKing.new("black", Vector2i(0, 4)),
			Rook.new("white", Vector2i(6, 0)), Bishop.new("white", Vector2i(6, 2)), Knight.new("white", Vector2i(5, 5)),
			Rook.new("black", Vector2i(1, 7)), Bishop.new("black", Vector2i(1, 5)), Knight.new("black", Vector2i(2, 2)),
		]
	return _position_from_pieces(pieces)


func _arakne_position() -> ChessPosition:
	var arakne := ArakneKing.new("white", Vector2i(4, 4)); arakne.set_cooldown(0); arakne.initial_cooldown_turn_pending = false
	return _position_from_pieces([arakne, ClassicKing.new("black", Vector2i(0, 4)), Rook.new("white", Vector2i(6, 0)), Rook.new("black", Vector2i(4, 5))])


func _necromancer_position() -> ChessPosition:
	return _position_from_pieces([NecromancerKing.new("white", Vector2i(7, 4)), ClassicKing.new("black", Vector2i(0, 4)), Rook.new("white", Vector2i(6, 0)), Rook.new("black", Vector2i(1, 7))])


func _minotaur_position() -> ChessPosition:
	var minotaur := MinotaurKing.new("white", Vector2i(7, 4)); minotaur.set_cooldown(0); minotaur.initial_cooldown_turn_pending = false
	return _position_from_pieces([minotaur, ClassicKing.new("black", Vector2i(0, 4)), Rook.new("white", Vector2i(6, 0)), Rook.new("black", Vector2i(4, 4)), Bishop.new("black", Vector2i(2, 2))])


func _quarterly_position() -> ChessPosition:
	var quarterly := QuarterlyInitiativeKing.new("white", Vector2i(7, 4)); quarterly.set_cooldown(0); quarterly.initial_cooldown_turn_pending = false
	var rook := Rook.new("white", Vector2i(6, 0)); rook.grant_movement_type(&"knight")
	var position := _position_from_pieces([quarterly, ClassicKing.new("black", Vector2i(0, 4)), rook, Bishop.new("white", Vector2i(5, 2)), Rook.new("black", Vector2i(1, 7)), Bishop.new("black", Vector2i(2, 2))])
	position.global_turn_number = 4
	return position


func _cannon_position() -> ChessPosition:
	var cannon := CannonKing.new("white", Vector2i(7, 4)); cannon.set_cooldown(0); cannon.initial_cooldown_turn_pending = false
	return _position_from_pieces([cannon, ClassicKing.new("black", Vector2i(0, 4)), Rook.new("white", Vector2i(6, 0)), Rook.new("black", Vector2i(3, 3)), Bishop.new("black", Vector2i(3, 4))])


func _rhetorician_position() -> ChessPosition:
	var rhetorician := RhetoricianKing.new("white", Vector2i(4, 4)); rhetorician.set_cooldown(0); rhetorician.initial_cooldown_turn_pending = false
	return _position_from_pieces([rhetorician, ClassicKing.new("black", Vector2i(0, 7)), Rook.new("white", Vector2i(6, 0)), Pawn.new("black", Vector2i(2, 2)), Queen.new("black", Vector2i(3, 3)), Rook.new("black", Vector2i(1, 4))])


func _position_from_pieces(pieces: Array) -> ChessPosition:
	var model := ChessBoardModel.new(); model.startup_mode = ChessBoardModel.StartupMode.EMPTY; model.diagnostic_logging_enabled = false
	add_child(model)
	for _row in range(8): model.board.append([null, null, null, null, null, null, null, null])
	model.is_initialized = true; model.current_turn = "white"
	for piece in pieces: model.add_piece(piece, piece.coordinate)
	var result := model.capture_position()
	model.queue_free()
	return result


func _model_from_position(position: ChessPosition) -> ChessBoardModel:
	var model := ChessBoardModel.new()
	model.startup_mode = ChessBoardModel.StartupMode.EMPTY
	model.diagnostic_logging_enabled = false
	add_child(model)
	model.load_position(position.copy())
	return model


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
