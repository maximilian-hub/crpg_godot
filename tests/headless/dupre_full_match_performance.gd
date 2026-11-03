extends Node

@export_range(1, 80) var maximum_plies := 8
@export var think_budget_msec := 350
@export var max_reply_leaves := 64
@export var seeds: Array[int] = [1409]


func _ready() -> void:
	var results: Array[Dictionary] = []
	for seed_value in seeds:
		for scenario in [&"classic", &"arakne_necromancer", &"cannon_minotaur", &"quarterly_wraith"]:
			results.append(await _play(scenario, seed_value))
	print("DUPRE FULL MATCH PERFORMANCE: ", JSON.stringify({
		"configuration": {"maximum_plies": maximum_plies, "budget_msec": think_budget_msec, "reply_leaves": max_reply_leaves, "seeds": seeds},
		"matches": results,
	}))
	print("DUPRE FULL MATCH PERFORMANCE: PASS")
	get_tree().quit(0)


func _play(scenario: StringName, seed_value: int) -> Dictionary:
	var model := _model(scenario)
	var players := {
		"white": _cpu(model, "white", seed_value),
		"black": _cpu(model, "black", seed_value + 1),
	}
	var totals := {
		"decision_usec": 0, "evaluated_replies": 0, "quiescence_nodes": 0,
		"core_resolutions": 0, "state_copies": 0, "state_copy_usec": 0,
		"analysis_action_queries": 0, "analysis_action_generations": 0,
		"analysis_action_usec": 0, "ordered_piece_cache_hits": 0,
		"ordered_piece_sort_usec": 0, "tactical_attacker_scans": 0,
		"tactical_attacker_usec": 0, "maximum_uninterrupted_usec": 0,
		"fallbacks": 0, "incomplete_roots": 0, "invalid_roots": 0,
		"policy_components": {}, "candidate_components": {},
	}
	var actions: Array[String] = []
	for _ply in range(maximum_plies):
		if model.battle_over: break
		var cpu: ChessCpuPlayer = players[model.current_turn]
		var started := Time.get_ticks_usec()
		var thought = await cpu.think()
		var elapsed := Time.get_ticks_usec() - started
		if thought == null: break
		var profile: Dictionary = cpu.brain.get_last_profile()
		totals.decision_usec += elapsed
		_accumulate(totals, profile)
		actions.append("%s:%s:%s>%s" % [thought.color, thought.piece_type_id, thought.piece_coordinate, thought.target])
		if not await cpu.execute_thought(): break
	var plies := actions.size()
	var result := {
		"scenario": String(scenario), "seed": seed_value, "plies": plies,
		"winner": model.battle_result, "actions": actions, "totals": totals,
		"average_decision_usec": int(totals.decision_usec) / maxi(1, plies),
		"work_units": int(totals.evaluated_replies) + int(totals.quiescence_nodes),
		"work_per_second": float(int(totals.evaluated_replies) + int(totals.quiescence_nodes)) * 1000000.0 / float(maxi(1, int(totals.decision_usec))),
	}
	for cpu in players.values(): cpu.queue_free()
	model.queue_free()
	await get_tree().process_frame
	return result


func _accumulate(totals: Dictionary, profile: Dictionary) -> void:
	for mapping in [
		["evaluated_replies", "evaluated_reply_count"], ["quiescence_nodes", "quiescence_node_count"],
		["core_resolutions", "core_resolution_count"], ["state_copies", "state_copy_count"],
		["state_copy_usec", "state_copy_usec"], ["analysis_action_queries", "analysis_action_query_count"],
		["analysis_action_generations", "analysis_action_generation_count"], ["analysis_action_usec", "analysis_action_usec"],
		["ordered_piece_cache_hits", "ordered_piece_cache_hit_count"], ["ordered_piece_sort_usec", "ordered_piece_sort_usec"],
		["tactical_attacker_scans", "tactical_attacker_scan_count"], ["tactical_attacker_usec", "tactical_attacker_usec"],
		["incomplete_roots", "incomplete_root_candidates"], ["invalid_roots", "invalid_root_candidates"],
	]: totals[mapping[0]] += int(profile.get(mapping[1], 0))
	totals.maximum_uninterrupted_usec = maxi(int(totals.maximum_uninterrupted_usec), int(profile.get("maximum_uninterrupted_usec", 0)))
	if bool(profile.get("unverified_selection", false)): totals.fallbacks += 1
	_merge_component_metrics(totals.policy_components, profile.get("policy_component_metrics", {}))
	_merge_component_metrics(totals.candidate_components, profile.get("candidate_component_metrics", {}))


func _merge_component_metrics(target: Dictionary, source: Dictionary) -> void:
	for key in source:
		var incoming: Dictionary = source[key]
		var bucket: Dictionary = target.get(key, {"count": 0, "usec": 0, "maximum_usec": 0, "worst_action": ""})
		bucket.count = int(bucket.count) + int(incoming.get("count", 0))
		bucket.usec = int(bucket.usec) + int(incoming.get("usec", 0))
		if int(incoming.get("maximum_usec", 0)) > int(bucket.maximum_usec):
			bucket.maximum_usec = int(incoming.maximum_usec)
			bucket.worst_action = String(incoming.get("worst_action", ""))
		target[key] = bucket


func _cpu(model: ChessBoardModel, color: String, seed_value: int) -> ChessCpuPlayer:
	var cpu := ChessCpuPlayer.new()
	cpu.model = model
	add_child(cpu)
	cpu.configure_mode(ChessCpuPlayer.ExecutionMode.MANUAL, color)
	cpu.set_brain(ChessCpuPlayer.BrainKind.DUPRE)
	cpu.set_random_seed(seed_value)
	var brain: DupreAiBrain = cpu.brain
	brain.max_book_moves = 0
	brain.simulation_backend = DupreAiBrain.SimulationBackend.CLASSIC_CORE
	brain.think_budget_msec = think_budget_msec
	brain.max_reply_leaves = max_reply_leaves
	brain.core_detailed_profiling_enabled = true
	brain.policy_detailed_profiling_enabled = true
	return cpu


func _model(scenario: StringName) -> ChessBoardModel:
	var white_king: KingPiece
	var black_king: KingPiece
	match scenario:
		&"arakne_necromancer": white_king = ArakneKing.new("white", Vector2i(7, 4)); black_king = NecromancerKing.new("black", Vector2i(0, 4))
		&"cannon_minotaur": white_king = CannonKing.new("white", Vector2i(7, 4)); black_king = MinotaurKing.new("black", Vector2i(0, 4))
		&"quarterly_wraith": white_king = QuarterlyInitiativeKing.new("white", Vector2i(7, 4)); black_king = WraithKing.new("black", Vector2i(0, 4))
		_: white_king = ClassicKing.new("white", Vector2i(7, 4)); black_king = ClassicKing.new("black", Vector2i(0, 4))
	for king in [white_king, black_king]:
		king.set_cooldown(0)
		king.initial_cooldown_turn_pending = false
	var model := ChessBoardModel.new()
	model.startup_mode = ChessBoardModel.StartupMode.EMPTY
	model.diagnostic_logging_enabled = false
	add_child(model)
	for _row in range(8): model.board.append([null, null, null, null, null, null, null, null])
	model.is_initialized = true
	model.current_turn = "white"
	for piece in [
		white_king, Queen.new("white", Vector2i(7, 3)), Rook.new("white", Vector2i(7, 0)), Bishop.new("white", Vector2i(7, 2)), Knight.new("white", Vector2i(7, 1)), Pawn.new("white", Vector2i(6, 3)), Pawn.new("white", Vector2i(6, 4)),
		black_king, Queen.new("black", Vector2i(0, 3)), Rook.new("black", Vector2i(0, 7)), Bishop.new("black", Vector2i(0, 5)), Knight.new("black", Vector2i(0, 6)), Pawn.new("black", Vector2i(1, 3)), Pawn.new("black", Vector2i(1, 4)),
	]: model.add_piece(piece, piece.coordinate)
	if scenario == &"quarterly_wraith": model.global_turn_number = 4
	return model
