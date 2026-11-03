extends Node

const FIXED_WORK_LEAVES := 64
const FIXED_TIME_MSEC := 1200
const SAMPLES := 3

@export var arakne_benchmark := false
@export var necromancer_benchmark := false
@export var minotaur_benchmark := false
@export var quarterly_benchmark := false
@export var cannon_benchmark := false
@export var rhetorician_benchmark := false
@export var wraith_benchmark := false
@export var endgame_benchmark := false

var failures: Array[String] = []


func _ready() -> void:
	var position := _benchmark_position()
	# Warm both code paths before collecting medians.
	await _run(position, DupreAiBrain.SimulationBackend.MODEL, 4, 60000, false)
	await _run(position, DupreAiBrain.SimulationBackend.CLASSIC_CORE, 4, 60000, false)
	var fixed_work := {"model": [], "core": []}
	var fixed_time := {"model": [], "core": []}
	for _sample in range(SAMPLES):
		fixed_work.model.append(await _run(position, DupreAiBrain.SimulationBackend.MODEL, FIXED_WORK_LEAVES, 60000, false))
		fixed_work.core.append(await _run(position, DupreAiBrain.SimulationBackend.CLASSIC_CORE, FIXED_WORK_LEAVES, 60000, false))
		fixed_time.model.append(await _run(position, DupreAiBrain.SimulationBackend.MODEL, 100000, FIXED_TIME_MSEC, true))
		fixed_time.core.append(await _run(position, DupreAiBrain.SimulationBackend.CLASSIC_CORE, 100000, FIXED_TIME_MSEC, true))
	var summary := {
		"fixed_work": {"model": _median_record(fixed_work.model), "core": _median_record(fixed_work.core)},
		"fixed_time": {"model": _median_record(fixed_time.model), "core": _median_record(fixed_time.core)},
	}
	var model_work: Dictionary = summary.fixed_work.model
	var core_work: Dictionary = summary.fixed_work.core
	var model_time: Dictionary = summary.fixed_time.model
	var core_time: Dictionary = summary.fixed_time.core
	if int(core_work.model_constructions) != 0: failures.append("pure-core fixed-work search constructed simulation Nodes")
	if int(model_work.model_constructions) <= 0: failures.append("model baseline constructed no simulation models")
	if int(core_work.work_units) != int(model_work.work_units): failures.append("fixed-work backends did not examine equal work")
	if String(core_work.action) != String(model_work.action): failures.append("fixed-work backends selected different actions")
	var throughput_floor := 1.5 if endgame_benchmark or arakne_benchmark or necromancer_benchmark or minotaur_benchmark or quarterly_benchmark or cannon_benchmark or rhetorician_benchmark or wraith_benchmark else 2.0
	if float(core_work.work_per_second) < float(model_work.work_per_second) * throughput_floor: failures.append("pure-core fixed-work throughput was below the %.1fx rollout floor" % throughput_floor)
	if int(core_time.work_units) <= int(model_time.work_units): failures.append("pure-core fixed-time search completed no additional work")
	if int(core_work.maximum_uninterrupted_usec) > int(model_work.maximum_uninterrupted_usec) * 1.2 + 1000: failures.append("pure-core uninterrupted interval regressed by more than 20% plus 1ms tolerance")
	if int(core_work.core_runtime_failures) != 0 or int(core_time.core_runtime_failures) != 0: failures.append("pure-core benchmark encountered invalid transitions")
	var label := "DUPRE ENDGAME CORE PERFORMANCE" if endgame_benchmark else ("DUPRE WRAITH CORE PERFORMANCE" if wraith_benchmark else ("DUPRE RHETORICIAN CORE PERFORMANCE" if rhetorician_benchmark else ("DUPRE CANNON CORE PERFORMANCE" if cannon_benchmark else ("DUPRE QUARTERLY CORE PERFORMANCE" if quarterly_benchmark else ("DUPRE MINOTAUR CORE PERFORMANCE" if minotaur_benchmark else ("DUPRE NECROMANCER CORE PERFORMANCE" if necromancer_benchmark else ("DUPRE ARAKNE CORE PERFORMANCE" if arakne_benchmark else "DUPRE CLASSIC CORE PERFORMANCE")))))))
	print(label, ": ", JSON.stringify(summary))
	if failures.is_empty():
		print(label, ": PASS")
		get_tree().quit(0)
		return
	printerr(label, ": FAIL")
	for failure in failures: printerr(" - ", failure)
	get_tree().quit(1)


func _run(position: ChessPosition, backend: int, leaves: int, budget_msec: int, quiescence: bool) -> Dictionary:
	var model := ChessBoardModel.new(); model.startup_mode = ChessBoardModel.StartupMode.EMPTY; model.diagnostic_logging_enabled = false
	add_child(model); model.load_position(position.copy())
	var cpu := ChessCpuPlayer.new(); cpu.model = model; add_child(cpu)
	cpu.configure_mode(ChessCpuPlayer.ExecutionMode.MANUAL, "white")
	cpu.set_brain(ChessCpuPlayer.BrainKind.DUPRE); cpu.set_random_seed(90210)
	var brain: DupreAiBrain = cpu.brain
	brain.max_book_moves = 0; brain.simulation_backend = backend
	brain.max_reply_leaves = leaves; brain.think_budget_msec = budget_msec
	brain.quiescence_enabled = quiescence
	brain.core_detailed_profiling_enabled = true
	var started := Time.get_ticks_usec()
	var thought = await cpu.think()
	var elapsed := Time.get_ticks_usec() - started
	var profile := brain.get_last_profile()
	var work := int(profile.get("evaluated_reply_count", 0)) + int(profile.get("quiescence_node_count", 0))
	var result := {
		"elapsed_usec": elapsed,
		"work_units": work,
		"work_per_second": float(work) * 1000000.0 / float(maxi(1, elapsed)),
		"action": _thought_key(thought),
		"backend": String(profile.get("simulation_backend", "")),
		"model_constructions": int(profile.get("model_construction_count", 0)),
		"position_loads": int(profile.get("position_load_count", 0)),
		"core_resolutions": int(profile.get("core_resolution_count", 0)),
		"core_legal_generations": int(profile.get("core_legal_generation_count", 0)),
		"core_evaluations": int(profile.get("core_evaluation_count", 0)),
		"core_runtime_failures": int(profile.get("core_runtime_failure_count", 0)),
		"core_import_usec": int(profile.get("core_import_usec", 0)),
		"core_resolution_usec": int(profile.get("core_resolution_usec", 0)),
		"legal_generation_usec": int(profile.get("legal_action_generation_usec", 0)),
		"evaluation_usec": int(profile.get("evaluation_usec", 0)),
		"policy_ranking_usec": int(profile.get("policy_ranking_usec", 0)),
		"candidate_selection_usec": int(profile.get("candidate_selection_usec", 0)),
		"reply_ordering_usec": int(profile.get("reply_ordering_usec", 0)),
		"exact_roots": int(profile.get("exact_root_candidates", 0)),
		"incomplete_roots": int(profile.get("incomplete_root_candidates", 0)),
		"evaluated_replies": int(profile.get("evaluated_reply_count", 0)),
		"quiescence_nodes": int(profile.get("quiescence_node_count", 0)),
		"maximum_uninterrupted_usec": int(profile.get("maximum_uninterrupted_usec", 0)),
		"state_copy_count": int(profile.get("state_copy_count", 0)),
		"state_copy_usec": int(profile.get("state_copy_usec", 0)),
		"maximum_state_copy_usec": int(profile.get("maximum_state_copy_usec", 0)),
		"silent_event_count": int(profile.get("silent_event_count", 0)),
		"analysis_action_queries": int(profile.get("analysis_action_query_count", 0)),
		"analysis_action_cache_hits": int(profile.get("analysis_action_cache_hit_count", 0)),
		"analysis_action_generations": int(profile.get("analysis_action_generation_count", 0)),
		"analysis_action_count": int(profile.get("analysis_action_count", 0)),
		"analysis_action_usec": int(profile.get("analysis_action_usec", 0)),
		"maximum_analysis_action_usec": int(profile.get("maximum_analysis_action_usec", 0)),
		"ordered_piece_queries": int(profile.get("ordered_piece_query_count", 0)),
		"ordered_piece_cache_hits": int(profile.get("ordered_piece_cache_hit_count", 0)),
		"ordered_piece_sort_usec": int(profile.get("ordered_piece_sort_usec", 0)),
		"tactical_attacker_queries": int(profile.get("tactical_attacker_query_count", 0)),
		"tactical_attacker_cache_hits": int(profile.get("tactical_attacker_cache_hit_count", 0)),
		"tactical_attacker_scans": int(profile.get("tactical_attacker_scan_count", 0)),
		"tactical_attacker_usec": int(profile.get("tactical_attacker_usec", 0)),
		"resolution_by_action_kind": profile.get("resolution_by_action_kind", {}),
		"resolution_by_king_type": profile.get("resolution_by_king_type", {}),
		"endgame_evaluation_count": int(profile.get("endgame_evaluation_count", 0)),
		"endgame_evaluation_usec": int(profile.get("endgame_evaluation_usec", 0)),
		"endgame_policy_usec": int(profile.get("endgame_policy_usec", 0)),
		"endgame_weight": float(profile.get("endgame_weight", 0.0)),
	}
	cpu.queue_free(); model.queue_free(); await get_tree().process_frame
	return result


func _median_record(records: Array) -> Dictionary:
	var ordered := records.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.elapsed_usec) < int(b.elapsed_usec))
	return ordered[ordered.size() / 2]


func _thought_key(thought) -> String:
	if thought == null: return ""
	return "%s|%s|%s|%s" % [thought.action_kind, thought.piece_type_id, thought.piece_coordinate, thought.target]


func _benchmark_position() -> ChessPosition:
	var white_king: KingPiece = WraithKing.new("white", Vector2i(7, 4)) if wraith_benchmark else (RhetoricianKing.new("white", Vector2i(7, 4)) if rhetorician_benchmark else (CannonKing.new("white", Vector2i(7, 4)) if cannon_benchmark else (QuarterlyInitiativeKing.new("white", Vector2i(7, 4)) if quarterly_benchmark else (MinotaurKing.new("white", Vector2i(7, 4)) if minotaur_benchmark else (NecromancerKing.new("white", Vector2i(7, 4)) if necromancer_benchmark else (ArakneKing.new("white", Vector2i(4, 4)) if arakne_benchmark else ClassicKing.new("white", Vector2i(7, 4))))))))
	var black_king: KingPiece = WraithKing.new("black", Vector2i(0, 4)) if wraith_benchmark else (RhetoricianKing.new("black", Vector2i(0, 4)) if rhetorician_benchmark else (CannonKing.new("black", Vector2i(0, 4)) if cannon_benchmark else (QuarterlyInitiativeKing.new("black", Vector2i(0, 4)) if quarterly_benchmark else (MinotaurKing.new("black", Vector2i(0, 4)) if minotaur_benchmark else (NecromancerKing.new("black", Vector2i(0, 4)) if necromancer_benchmark else (ArakneKing.new("black", Vector2i(0, 4)) if arakne_benchmark else ClassicKing.new("black", Vector2i(0, 4))))))))
	if arakne_benchmark or necromancer_benchmark or minotaur_benchmark or quarterly_benchmark or cannon_benchmark or rhetorician_benchmark or wraith_benchmark:
		white_king.set_cooldown(0); white_king.initial_cooldown_turn_pending = false
		black_king.set_cooldown(0); black_king.initial_cooldown_turn_pending = false
	var black_queen_coordinate := Vector2i(4, 5) if arakne_benchmark else Vector2i(1, 3)
	var pieces: Array = [
		white_king, Queen.new("white", Vector2i(6, 3)), Rook.new("white", Vector2i(7, 0)),
		Bishop.new("white", Vector2i(5, 1)), Knight.new("white", Vector2i(5, 5)), Pawn.new("white", Vector2i(4, 2)), Pawn.new("white", Vector2i(6, 6)),
		black_king, Queen.new("black", black_queen_coordinate), Rook.new("black", Vector2i(0, 7)),
		Bishop.new("black", Vector2i(2, 6)), Knight.new("black", Vector2i(2, 2)), Pawn.new("black", Vector2i(3, 5)), Pawn.new("black", Vector2i(1, 1)),
	]
	if endgame_benchmark:
		pieces = [
			ClassicKing.new("white", Vector2i(6, 4)), Rook.new("white", Vector2i(6, 2)),
			Pawn.new("white", Vector2i(3, 2)), Pawn.new("white", Vector2i(5, 6)),
			ClassicKing.new("black", Vector2i(1, 4)), Rook.new("black", Vector2i(1, 7)),
			Pawn.new("black", Vector2i(4, 5)), Pawn.new("black", Vector2i(2, 1)),
		]
	var model := ChessBoardModel.new(); model.startup_mode = ChessBoardModel.StartupMode.EMPTY; model.diagnostic_logging_enabled = false
	add_child(model)
	for _row in range(8): model.board.append([null, null, null, null, null, null, null, null])
	model.is_initialized = true; model.current_turn = "white"
	for piece in pieces: model.add_piece(piece, piece.coordinate)
	var result := model.capture_position()
	if quarterly_benchmark: result.global_turn_number = 4
	model.queue_free(); return result
