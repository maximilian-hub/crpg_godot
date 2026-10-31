extends Node

const BUDGET_MSEC := 1200
const KINDS: Array[StringName] = [&"classic", &"quarterly", &"cannon", &"poisoned_capture"]
const CONFIGS := [
	{"id": &"baseline"},
	{"id": &"legacy_quiescence", "quiescence_mode": DupreAiBrain.QuiescenceMode.CURRENT},
	{"id": &"no_quiescence", "quiescence_mode": DupreAiBrain.QuiescenceMode.DISABLED},
	{"id": &"immediate_quiescence", "quiescence_mode": DupreAiBrain.QuiescenceMode.IMMEDIATE_ONLY},
	{"id": &"immediate_reduced", "quiescence_mode": DupreAiBrain.QuiescenceMode.IMMEDIATE_ONLY, "reduced_evaluation": true},
	{"id": &"direct_position_load", "copy_position": false},
	{"id": &"incumbent_schedule", "completion_schedule": DupreAiBrain.CompletionSchedule.ESTABLISH_INCUMBENT},
	{"id": &"no_quiescence_incumbent", "quiescence_mode": DupreAiBrain.QuiescenceMode.DISABLED, "completion_schedule": DupreAiBrain.CompletionSchedule.ESTABLISH_INCUMBENT},
	{"id": &"combined", "quiescence_mode": DupreAiBrain.QuiescenceMode.IMMEDIATE_ONLY, "reduced_evaluation": true, "copy_position": false, "completion_schedule": DupreAiBrain.CompletionSchedule.ESTABLISH_INCUMBENT},
]

var failures: Array[String] = []


func _ready() -> void:
	_test_direct_load_immutability()
	var results: Array[Dictionary] = []
	var baseline_actions := {}
	for kind in KINDS:
		for config in CONFIGS:
			var result := await _run(kind, config)
			results.append(result)
			if config.id == &"baseline":
				baseline_actions[kind] = result.action
			else:
				result["decision_matches_baseline"] = result.action == baseline_actions.get(kind, "")
			if not bool(result.produced_action): failures.append("%s/%s produced no action" % [kind, config.id])
			if int(result.invalid_root_candidates) > 0: failures.append("%s/%s produced invalid roots" % [kind, config.id])
			if kind == &"poisoned_capture" and result.action == "0|queen|(4, 4)|(4, 3)": failures.append("%s accepted the poisoned Queen capture" % config.id)
	print("DUPRE OPTIMIZATION INVESTIGATION: ", JSON.stringify(results))
	if failures.is_empty():
		print("DUPRE OPTIMIZATION INVESTIGATION: PASS")
		get_tree().quit(0)
		return
	for failure in failures: printerr(" - ", failure)
	get_tree().quit(1)


func _run(kind: StringName, config: Dictionary) -> Dictionary:
	var model := _position(kind)
	add_child(model)
	var cpu := ChessCpuPlayer.new()
	cpu.model = model
	add_child(cpu)
	cpu.configure_mode(ChessCpuPlayer.ExecutionMode.MANUAL, "white")
	cpu.set_brain(ChessCpuPlayer.BrainKind.DUPRE)
	cpu.set_random_seed(90210)
	var brain: DupreAiBrain = cpu.brain
	brain.max_book_moves = 0
	brain.think_budget_msec = BUDGET_MSEC
	brain.quiescence_mode = int(config.get("quiescence_mode", DupreAiBrain.QuiescenceMode.TACTICAL))
	brain.reduced_quiescence_evaluation = bool(config.get("reduced_evaluation", false))
	brain.copy_position_before_load = bool(config.get("copy_position", true))
	brain.completion_schedule = int(config.get("completion_schedule", DupreAiBrain.CompletionSchedule.BREADTH_FIRST))
	var started := Time.get_ticks_usec()
	var thought = await cpu.think()
	var elapsed := Time.get_ticks_usec() - started
	var profile := brain.get_last_profile()
	var work_units := int(profile.get("evaluated_reply_count", 0)) + int(profile.get("quiescence_node_count", 0))
	var result := {
		"kind": kind,
		"config": config.id,
		"elapsed_usec": elapsed,
		"produced_action": thought != null,
		"action": _thought_key(thought),
		"work_units": work_units,
		"work_units_per_second": float(work_units) * 1000000.0 / float(maxi(1, elapsed)),
		"evaluated_replies": int(profile.get("evaluated_reply_count", 0)),
		"quiescence_nodes": int(profile.get("quiescence_node_count", 0)),
		"quiescence_forcing_actions": int(profile.get("quiescence_forcing_action_count", 0)),
		"quiescence_ability_actions": int(profile.get("quiescence_ability_action_count", 0)),
		"quiescence_critical_classifications": int(profile.get("quiescence_critical_classification_count", 0)),
		"quiescence_tactical_classifications": int(profile.get("quiescence_tactical_classification_count", 0)),
		"quiescence_quiet_classifications": int(profile.get("quiescence_quiet_classification_count", 0)),
		"quiescence_classification_reasons": profile.get("quiescence_classification_reasons", {}).duplicate(true),
		"quiescence_classification_usec": int(profile.get("quiescence_classification_usec", 0)),
		"model_constructions": int(profile.get("model_construction_count", 0)),
		"position_copies": int(profile.get("position_copy_count", 0)),
		"startup_pieces": int(profile.get("simulation_startup_piece_count", 0)),
		"registered_pieces": int(profile.get("simulation_piece_registration_count", 0)),
		"disposed_pieces": int(profile.get("simulation_piece_disposal_count", 0)),
		"legal_generations": int(profile.get("legal_action_generation_count", 0)),
		"evaluations": int(profile.get("evaluation_count", 0)),
		"exact_roots": int(profile.get("exact_root_candidates", 0)),
		"pruned_roots": int(profile.get("pruned_root_candidates", 0)),
		"invalid_root_candidates": int(profile.get("invalid_root_candidates", 0)),
		"fallback": bool(profile.get("fallback_used", false)),
		"incumbent_completed": bool(profile.get("incumbent_completion_succeeded", false)),
		"maximum_uninterrupted_usec": int(profile.get("maximum_uninterrupted_usec", 0)),
		"maximum_legal_generation_usec": int(profile.get("maximum_legal_action_generation_usec", 0)),
		"model_construction_usec": int(profile.get("model_construction_usec", 0)),
		"position_copy_usec": int(profile.get("position_copy_usec", 0)),
		"position_load_usec": int(profile.get("position_load_usec", 0)),
		"simulation_cleanup_usec": int(profile.get("simulation_cleanup_usec", 0)),
		"action_execution_usec": int(profile.get("action_execution_usec", 0)),
		"legal_generation_usec": int(profile.get("legal_action_generation_usec", 0)),
		"evaluation_usec": int(profile.get("evaluation_usec", 0)),
		"evaluation_material_usec": int(profile.get("evaluation_material_usec", 0)),
		"evaluation_legal_component_usec": int(profile.get("evaluation_legal_generation_usec", 0)),
		"evaluation_tactical_usec": int(profile.get("evaluation_tactical_usec", 0)),
		"evaluation_layer_usec": int(profile.get("evaluation_layer_usec", 0)),
		"evaluation_other_usec": int(profile.get("evaluation_other_usec", 0)),
		"policy_ranking_usec": int(profile.get("policy_ranking_usec", 0)),
		"candidate_selection_usec": int(profile.get("candidate_selection_usec", 0)),
		"reply_ordering_usec": int(profile.get("reply_ordering_usec", 0)),
	}
	cpu.queue_free()
	model.queue_free()
	await get_tree().process_frame
	return result


func _test_direct_load_immutability() -> void:
	var source_model := _position(&"cannon")
	var position := source_model.capture_position()
	var before := ChessPositionCodec.to_json(position, false)
	var first := ChessBoardModel.new()
	var second := ChessBoardModel.new()
	var first_loaded := first.load_position(position)
	var middle := ChessPositionCodec.to_json(position, false)
	var second_loaded := second.load_position(position)
	var after := ChessPositionCodec.to_json(position, false)
	if not first_loaded or not second_loaded or before != middle or before != after:
		failures.append("direct load mutated or failed to reload its source ChessPosition")
	if first_loaded and second_loaded and ChessPositionCodec.to_json(first.capture_position(), false) != ChessPositionCodec.to_json(second.capture_position(), false):
		failures.append("repeated direct loads produced different authoritative positions")
	first.free(); second.free(); source_model.free()


func _thought_key(thought) -> String:
	if thought == null: return ""
	return "%s|%s|%s|%s" % [thought.action_kind, thought.piece_type_id, thought.piece_coordinate, thought.target]


func _position(kind: StringName) -> ChessBoardModel:
	var model := ChessBoardModel.new()
	model.diagnostic_logging_enabled = false
	model.initialize_battle()
	for row in model.board:
		for piece in row:
			if piece != null: model.unregister_piece(piece)
	model.board.clear()
	for _row in range(8): model.board.append([null, null, null, null, null, null, null, null])
	if kind == &"poisoned_capture":
		for piece in [ClassicKing.new("white", Vector2i(7, 7)), ClassicKing.new("black", Vector2i(0, 7)), Queen.new("white", Vector2i(4, 4)), Pawn.new("black", Vector2i(4, 3)), Rook.new("black", Vector2i(4, 0))]:
			model.add_piece(piece, piece.coordinate)
		model.current_turn = "white"
		return model
	var white_king: KingPiece
	match kind:
		&"quarterly":
			white_king = QuarterlyInitiativeKing.new("white", Vector2i(7, 4))
			white_king.set_cooldown(0)
			model.global_turn_number = 4
		&"cannon":
			white_king = CannonKing.new("white", Vector2i(7, 4))
			white_king.set_cooldown(0)
		_:
			white_king = ClassicKing.new("white", Vector2i(7, 4))
	for piece in [
		white_king, Queen.new("white", Vector2i(6, 3)), Rook.new("white", Vector2i(7, 0)), Knight.new("white", Vector2i(5, 2)), Pawn.new("white", Vector2i(6, 0)),
		ClassicKing.new("black", Vector2i(0, 4)), Queen.new("black", Vector2i(1, 3)), Rook.new("black", Vector2i(0, 0)), Knight.new("black", Vector2i(2, 2)), Pawn.new("black", Vector2i(1, 0)),
	]: model.add_piece(piece, piece.coordinate)
	model.current_turn = "white"
	return model
